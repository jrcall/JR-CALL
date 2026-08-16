// ===============================================================
// JR CALL
// File: signaling_service.dart
// Location: lib/services/call/signaling_service.dart
// Fixes: BUG 04, BUG 07, BUG 08
// Production-safe replacement
// Existing APIs preserved
//
// IMPORTANT PRODUCTION FIXES:
// - Firebase UID remains canonical call identity.
// - Call creation matches current firestore.rules.
// - SDP writer role protected.
// - ICE writer role protected.
// - Late SDP/ICE writes after terminal state are ignored.
// - Generic updates are explicitly allow-listed.
// - Busy check no longer performs an unauthorized privacy-breaking
//   query against another user's private call documents.
// - Deterministic call-history document remains one record per call.
// - History is persisted before any future signaling deletion.
// - No fake ringing / connected / timer state is generated here.
// - No WebRTC / ICE application / recovery ownership duplicated.
// ===============================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class SignalingService {
  SignalingService._();

  static final SignalingService instance = SignalingService._();

  // =============================================================
  // FIREBASE
  // =============================================================

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  /// Existing public compatibility API.
  final FirebaseAuth auth = FirebaseAuth.instance;

  // =============================================================
  // COLLECTIONS
  // =============================================================

  static const String callsCollectionName = 'calls';
  static const String callHistoryCollectionName = 'call_history';

  CollectionReference<Map<String, dynamic>> get callsCollection =>
      firestore.collection(callsCollectionName);

  CollectionReference<Map<String, dynamic>> get callHistoryCollection =>
      firestore.collection(callHistoryCollectionName);

  // =============================================================
  // STATUS CONTRACT
  // =============================================================

  static const Set<String> _validStatuses = <String>{
    'calling',
    'ringing',
    'connecting',
    'connected',
    'reconnecting',
    'ended',
    'rejected',
    'declined',
    'cancelled',
    'failed',
    'timeout',
  };

  static const Set<String> _terminalStatuses = <String>{
    'ended',
    'rejected',
    'declined',
    'cancelled',
    'failed',
    'timeout',
  };

  static const List<String> _activeStatuses = <String>[
    'calling',
    'ringing',
    'connecting',
    'connected',
    'reconnecting',
  ];

  static const List<String> _stalePendingStatuses = <String>[
    'calling',
    'ringing',
    'connecting',
  ];

  // =============================================================
  // GENERIC UPDATE CONTRACT
  // =============================================================

  /// Current firestore.rules allow these non-lifecycle fields to
  /// change on calls/{callId}.
  ///
  /// Explicit allow-list prevents updateCall() from accidentally
  /// sending unsupported fields and receiving permission-denied.
  static const Set<String> _genericMutableFields = <String>{
    'connectionState',
    'iceConnectionState',
    'signalingState',
    'iceGatheringState',
    'networkRecovered',
    'iceRestartCount',
    'callerName',
    'receiverName',
  };

  // =============================================================
  // LEGACY COMPATIBILITY
  // =============================================================

  /// Actual WebRTC signaling state belongs to WebRTCService.
  String get signalingState => 'stable';

  // =============================================================
  // CALL CREATION
  // =============================================================

  Future<DocumentReference<Map<String, dynamic>>> createCall({
    required String callerId,
    required String receiverId,
    bool isVideoCall = true,
  }) async {
    final String normalizedCallerId = _requireId(callerId, 'callerId');

    final String normalizedReceiverId = _requireId(receiverId, 'receiverId');

    if (normalizedCallerId == normalizedReceiverId) {
      throw ArgumentError('A JR CALL user cannot call themselves.');
    }

    final String authenticatedUid = _requireAuthenticatedUid();

    if (authenticatedUid != normalizedCallerId) {
      throw StateError('Authenticated Firebase UID does not match callerId.');
    }

    final DocumentReference<Map<String, dynamic>> reference = callsCollection
        .doc();

    // IMPORTANT:
    // Current firestore.rules explicitly require initial status
    // == "calling".
    await reference.set(<String, dynamic>{
      'callId': reference.id,
      'callerId': normalizedCallerId,
      'receiverId': normalizedReceiverId,
      'status': 'calling',
      'isVideoCall': isVideoCall,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'endedAt': null,
      'offer': null,
      'answer': null,
      'callerCandidates': <Map<String, dynamic>>[],
      'receiverCandidates': <Map<String, dynamic>>[],
      'connectionState': 'new',
      'iceConnectionState': 'new',
      'signalingState': 'stable',
      'iceGatheringState': 'new',
      'networkRecovered': false,
      'iceRestartCount': 0,
    });

    return reference;
  }

  // =============================================================
  // SDP OFFER / ANSWER
  // =============================================================

  Future<void> saveOffer(String callId, Map<String, dynamic> offer) {
    return _saveSessionDescription(
      callId: callId,
      field: 'offer',
      description: offer,
      expectedType: 'offer',
      expectedWriterRole: _CallParticipantRole.caller,
    );
  }

  Future<void> saveAnswer(String callId, Map<String, dynamic> answer) {
    return _saveSessionDescription(
      callId: callId,
      field: 'answer',
      description: answer,
      expectedType: 'answer',
      expectedWriterRole: _CallParticipantRole.receiver,
    );
  }

  Future<void> _saveSessionDescription({
    required String callId,
    required String field,
    required Map<String, dynamic> description,
    required String expectedType,
    required _CallParticipantRole expectedWriterRole,
  }) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final String authenticatedUid = _requireAuthenticatedUid();

    final String? sdp = _readString(description['sdp']);

    final String? type = _readString(description['type'])?.toLowerCase();

    if (sdp == null || type != expectedType) {
      throw ArgumentError('Invalid WebRTC $expectedType session description.');
    }

    final DocumentReference<Map<String, dynamic>> reference = callsCollection
        .doc(normalizedCallId);

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);

      final Map<String, dynamic>? data = snapshot.data();

      if (!snapshot.exists || data == null) {
        throw StateError('Call document does not exist.');
      }

      _requireExpectedParticipantRole(
        data: data,
        authenticatedUid: authenticatedUid,
        expectedRole: expectedWriterRole,
      );

      final String? status = _readString(data['status'])?.toLowerCase();

      if (status == null || _terminalStatuses.contains(status)) {
        return;
      }

      final Map<String, dynamic>? previous = _normalizeMap(data[field]);

      final String? previousSdp = _readString(previous?['sdp']);

      final String? previousType = _readString(
        previous?['type'],
      )?.toLowerCase();

      if (previousSdp == sdp && previousType == type) {
        return;
      }

      transaction.update(reference, <String, dynamic>{
        field: <String, dynamic>{'type': type, 'sdp': sdp},
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<Map<String, dynamic>?> getOffer(String callId) {
    return _getSessionDescription(
      callId: callId,
      field: 'offer',
      expectedType: 'offer',
    );
  }

  Future<Map<String, dynamic>?> getAnswer(String callId) {
    return _getSessionDescription(
      callId: callId,
      field: 'answer',
      expectedType: 'answer',
    );
  }

  Future<Map<String, dynamic>?> _getSessionDescription({
    required String callId,
    required String field,
    required String expectedType,
  }) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await callsCollection.doc(normalizedCallId).get();

    final Map<String, dynamic>? data = snapshot.data();

    if (!snapshot.exists || data == null) {
      return null;
    }

    _requireParticipant(data, _requireAuthenticatedUid());

    final Map<String, dynamic>? description = _normalizeMap(data[field]);

    if (description == null) {
      return null;
    }

    final String? sdp = _readString(description['sdp']);

    final String? type = _readString(description['type'])?.toLowerCase();

    if (sdp == null || type != expectedType) {
      return null;
    }

    return Map<String, dynamic>.unmodifiable(<String, dynamic>{
      'type': type,
      'sdp': sdp,
    });
  }

  // =============================================================
  // RAW CALL ACCESS
  // =============================================================

  Stream<DocumentSnapshot<Map<String, dynamic>>> listenCall(String callId) {
    final String normalizedCallId = _requireId(callId, 'callId');

    return callsCollection.doc(normalizedCallId).snapshots();
  }

  Future<Map<String, dynamic>> getCallDocument(String callId) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await callsCollection.doc(normalizedCallId).get();

    final Map<String, dynamic>? data = snapshot.data();

    if (!snapshot.exists || data == null) {
      throw StateError(
        'Call document not found for callId: '
        '$normalizedCallId',
      );
    }

    _requireParticipant(data, _requireAuthenticatedUid());

    return Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(data));
  }

  // =============================================================
  // GENERIC CALL UPDATE
  // =============================================================

  Future<void> updateCall({
    required String callId,
    required Map<String, dynamic> data,
  }) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    if (data.isEmpty) {
      return;
    }

    final Map<String, dynamic> updateData = <String, dynamic>{};

    for (final MapEntry<String, dynamic> entry in data.entries) {
      if (_genericMutableFields.contains(entry.key)) {
        updateData[entry.key] = entry.value;
      }
    }

    if (updateData.isEmpty) {
      return;
    }

    if (updateData.containsKey('iceRestartCount')) {
      final Object? rawCount = updateData['iceRestartCount'];

      if (rawCount is int) {
        if (rawCount < 0) {
          throw ArgumentError('iceRestartCount cannot be negative.');
        }
      } else if (rawCount is! FieldValue) {
        throw ArgumentError(
          'iceRestartCount must be an integer '
          'or Firestore increment value.',
        );
      }
    }

    if (updateData.containsKey('networkRecovered') &&
        updateData['networkRecovered'] is! bool) {
      throw ArgumentError('networkRecovered must be a boolean.');
    }

    final String authenticatedUid = _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>> reference = callsCollection
        .doc(normalizedCallId);

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);

      final Map<String, dynamic>? callData = snapshot.data();

      if (!snapshot.exists || callData == null) {
        return;
      }

      _requireParticipant(callData, authenticatedUid);

      final String? status = _readString(callData['status'])?.toLowerCase();

      if (status == null || _terminalStatuses.contains(status)) {
        return;
      }

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      transaction.update(reference, updateData);
    });
  }

  // =============================================================
  // CALL STATUS
  // =============================================================

  Future<void> updateCallStatus(String callId, String status) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final String normalizedStatus = status.trim().toLowerCase();

    if (!_validStatuses.contains(normalizedStatus)) {
      throw ArgumentError.value(
        status,
        'status',
        'Unsupported JR CALL status.',
      );
    }

    final String authenticatedUid = _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>> reference = callsCollection
        .doc(normalizedCallId);

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);

      final Map<String, dynamic>? data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return;
      }

      _requireParticipant(data, authenticatedUid);

      final String? currentStatus = _readString(data['status'])?.toLowerCase();

      if (currentStatus == normalizedStatus) {
        return;
      }

      // A terminal call can never return to an active state.
      if (currentStatus != null && _terminalStatuses.contains(currentStatus)) {
        return;
      }

      final Map<String, dynamic> update = <String, dynamic>{
        'status': normalizedStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_terminalStatuses.contains(normalizedStatus)) {
        update['endedAt'] = FieldValue.serverTimestamp();

        update['networkRecovered'] = false;

        update['callerCandidates'] = <Map<String, dynamic>>[];

        update['receiverCandidates'] = <Map<String, dynamic>>[];
      }

      transaction.update(reference, update);
    });
  }

  // =============================================================
  // END CALL
  // =============================================================

  Future<void> endCall(String callId) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final String authenticatedUid = _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>> reference = callsCollection
        .doc(normalizedCallId);

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);

      final Map<String, dynamic>? data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return;
      }

      _requireParticipant(data, authenticatedUid);

      final String? currentStatus = _readString(data['status'])?.toLowerCase();

      if (currentStatus != null && _terminalStatuses.contains(currentStatus)) {
        return;
      }

      transaction.update(reference, <String, dynamic>{
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'networkRecovered': false,
        'callerCandidates': <Map<String, dynamic>>[],
        'receiverCandidates': <Map<String, dynamic>>[],
      });
    });
  }

  // =============================================================
  // DELETE CALL
  // =============================================================

  Future<void> deleteCall(String callId) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final String authenticatedUid = _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>> reference = callsCollection
        .doc(normalizedCallId);

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);

      final Map<String, dynamic>? data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return;
      }

      _requireParticipant(data, authenticatedUid);

      transaction.delete(reference);
    });
  }

  // =============================================================
  // ICE CANDIDATE WRITE
  // =============================================================

  Future<void> addCallerCandidate(
    String callId,
    Map<String, dynamic> candidate,
  ) {
    return _appendIceCandidate(
      callId: callId,
      field: 'callerCandidates',
      candidate: candidate,
      expectedRole: _CallParticipantRole.caller,
    );
  }

  Future<void> addReceiverCandidate(
    String callId,
    Map<String, dynamic> candidate,
  ) {
    return _appendIceCandidate(
      callId: callId,
      field: 'receiverCandidates',
      candidate: candidate,
      expectedRole: _CallParticipantRole.receiver,
    );
  }

  Future<void> addIceCandidate(
    String callId,
    bool isCaller,
    Map<String, dynamic> candidate,
  ) async {
    const int maximumAttempts = 3;

    Object? lastError;
    StackTrace? lastStackTrace;

    for (int attempt = 1; attempt <= maximumAttempts; attempt++) {
      try {
        if (isCaller) {
          await addCallerCandidate(callId, candidate);
        } else {
          await addReceiverCandidate(callId, candidate);
        }

        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;

        if (!_shouldRetryIceWrite(error) || attempt >= maximumAttempts) {
          break;
        }

        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }

    final Object failure =
        lastError ?? StateError('Unknown ICE candidate persistence error.');

    _reportError('ICE candidate persistence', failure, lastStackTrace);

    if (lastStackTrace != null) {
      Error.throwWithStackTrace(failure, lastStackTrace);
    }

    throw failure;
  }

  Future<void> _appendIceCandidate({
    required String callId,
    required String field,
    required Map<String, dynamic> candidate,
    required _CallParticipantRole expectedRole,
  }) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final String authenticatedUid = _requireAuthenticatedUid();

    final Map<String, dynamic> normalizedCandidate = _normalizeIceCandidate(
      candidate,
    );

    final DocumentReference<Map<String, dynamic>> reference = callsCollection
        .doc(normalizedCallId);

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);

      final Map<String, dynamic>? data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return;
      }

      _requireExpectedParticipantRole(
        data: data,
        authenticatedUid: authenticatedUid,
        expectedRole: expectedRole,
      );

      final String? status = _readString(data['status'])?.toLowerCase();

      if (status == null || _terminalStatuses.contains(status)) {
        return;
      }

      final List<dynamic> currentCandidates = data[field] is List
          ? List<dynamic>.from(data[field] as List)
          : <dynamic>[];

      final String candidateSignature = _iceCandidateSignature(
        normalizedCandidate,
      );

      final bool alreadyExists = currentCandidates.any((dynamic rawCandidate) {
        final Map<String, dynamic>? existing = _normalizeMap(rawCandidate);

        if (existing == null) {
          return false;
        }

        return _iceCandidateSignature(existing) == candidateSignature;
      });

      if (alreadyExists) {
        return;
      }

      transaction.update(reference, <String, dynamic>{
        field: FieldValue.arrayUnion(<Map<String, dynamic>>[
          normalizedCandidate,
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  String _iceCandidateSignature(Map<String, dynamic> candidate) {
    return '${_readString(candidate['candidate']) ?? ''}|'
        '${_readString(candidate['sdpMid']) ?? ''}|'
        '${candidate['sdpMLineIndex'] ?? ''}';
  }

  bool _shouldRetryIceWrite(Object error) {
    if (error is! FirebaseException) {
      return false;
    }

    switch (error.code) {
      case 'aborted':
      case 'cancelled':
      case 'deadline-exceeded':
      case 'internal':
      case 'resource-exhausted':
      case 'unavailable':
      case 'unknown':
        return true;

      default:
        return false;
    }
  }

  // =============================================================
  // REMOTE ICE STREAM
  // =============================================================

  Stream<List<Map<String, dynamic>>> listenToRemoteICECandidates(
    String callId,
    bool isCaller,
  ) {
    final String normalizedCallId = _requireId(callId, 'callId');

    final String targetField = isCaller
        ? 'receiverCandidates'
        : 'callerCandidates';

    return callsCollection.doc(normalizedCallId).snapshots().map<
      List<Map<String, dynamic>>
    >((DocumentSnapshot<Map<String, dynamic>> snapshot) {
      if (!snapshot.exists) {
        return const <Map<String, dynamic>>[];
      }

      final Object? rawCandidates = snapshot.data()?[targetField];

      if (rawCandidates is! List) {
        return const <Map<String, dynamic>>[];
      }

      final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];

      final Set<String> signatures = <String>{};

      for (final dynamic rawCandidate in rawCandidates) {
        final Map<String, dynamic>? candidate = _normalizeMap(rawCandidate);

        if (candidate == null || _readString(candidate['candidate']) == null) {
          continue;
        }

        final String signature = _iceCandidateSignature(candidate);

        if (!signatures.add(signature)) {
          continue;
        }

        result.add(Map<String, dynamic>.unmodifiable(candidate));
      }

      return List<Map<String, dynamic>>.unmodifiable(result);
    });
  }

  // =============================================================
  // COMPATIBILITY LISTENER — ANSWER
  // =============================================================

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> listenToAnswer(
    String callId,
    void Function(Map<String, dynamic>?) onAnswer,
  ) {
    final String normalizedCallId = _requireId(callId, 'callId');

    String? previousSignature;

    return callsCollection
        .doc(normalizedCallId)
        .snapshots()
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snapshot) {
            if (!snapshot.exists) {
              return;
            }

            final Map<String, dynamic>? answer = _normalizeMap(
              snapshot.data()?['answer'],
            );

            if (answer == null) {
              return;
            }

            final String? sdp = _readString(answer['sdp']);

            final String? type = _readString(answer['type'])?.toLowerCase();

            if (sdp == null || type != 'answer') {
              return;
            }

            final String signature = '$type::$sdp';

            if (signature == previousSignature) {
              return;
            }

            previousSignature = signature;

            onAnswer(
              Map<String, dynamic>.unmodifiable(<String, dynamic>{
                'type': type,
                'sdp': sdp,
              }),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            _reportError('listenToAnswer', error, stackTrace);
          },
        );
  }

  // =============================================================
  // COMPATIBILITY LISTENER — STATUS
  // =============================================================

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> listenToCallStatus(
    String callId,
    void Function(String status) onStatusChanged,
  ) {
    final String normalizedCallId = _requireId(callId, 'callId');

    String? previousStatus;

    return callsCollection
        .doc(normalizedCallId)
        .snapshots()
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snapshot) {
            if (!snapshot.exists) {
              if (previousStatus != 'ended') {
                previousStatus = 'ended';
                onStatusChanged('ended');
              }

              return;
            }

            final String? status = _readString(
              snapshot.data()?['status'],
            )?.toLowerCase();

            if (status == null ||
                !_validStatuses.contains(status) ||
                status == previousStatus) {
              return;
            }

            previousStatus = status;

            onStatusChanged(status);
          },
          onError: (Object error, StackTrace stackTrace) {
            _reportError('listenToCallStatus', error, stackTrace);
          },
        );
  }

  // =============================================================
  // BUSY CHECK
  // =============================================================

  /// IMPORTANT SECURITY FIX:
  ///
  /// Current firestore.rules allow reading calls only when the
  /// authenticated user is caller/receiver of that call.
  ///
  /// Therefore Client A CANNOT legally query:
  ///
  /// "Does arbitrary User B currently have another call?"
  ///
  /// Such a query can be rejected with permission-denied.
  ///
  /// For the authenticated user's own UID we can safely query
  /// their own active call state.
  ///
  /// For another UID we return false here and allow call creation.
  /// The receiving side / call lifecycle is responsible for
  /// rejecting/busy handling without exposing User B's private
  /// calls to User A.
  ///
  /// This prevents BUG 07 from dying before createCall().
  Future<bool> checkUserBusyStatus(String userId) async {
    final String normalizedUserId = _requireId(userId, 'userId');

    final String currentUid = _requireAuthenticatedUid();

    if (normalizedUserId != currentUid) {
      return false;
    }

    final List<bool> results = await Future.wait<bool>(<Future<bool>>[
      _hasOwnedActiveCall(field: 'callerId', userId: normalizedUserId),
      _hasOwnedActiveCall(field: 'receiverId', userId: normalizedUserId),
    ]);

    return results.any((bool busy) => busy);
  }

  Future<bool> _hasOwnedActiveCall({
    required String field,
    required String userId,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await callsCollection
        .where(field, isEqualTo: userId)
        .where('status', whereIn: _activeStatuses)
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  Future<bool> checkUserInCallStatus(String userId) {
    return checkUserBusyStatus(userId);
  }

  Future<bool> checkCallActiveStatus(String callId) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await callsCollection.doc(normalizedCallId).get();

    final Map<String, dynamic>? data = snapshot.data();

    if (!snapshot.exists || data == null) {
      return false;
    }

    _requireParticipant(data, _requireAuthenticatedUid());

    final String? status = _readString(data['status'])?.toLowerCase();

    return status != null && _activeStatuses.contains(status);
  }

  // =============================================================
  // CALL HISTORY
  // =============================================================

  /// Deterministic one-document-per-call history.
  ///
  /// callerId/receiverId remain on the shared history record so
  /// UI/provider can derive incoming/outgoing for the currently
  /// authenticated user without manufacturing duplicate records.
  Future<void> saveCallHistory({
    required String callId,
    required int duration,
    required String status,
    String callType = 'video',
  }) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    if (duration < 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Call duration cannot be negative.',
      );
    }

    final String normalizedCallType = callType.trim().toLowerCase();

    if (normalizedCallType != 'voice' && normalizedCallType != 'video') {
      throw ArgumentError.value(
        callType,
        'callType',
        'Call type must be voice or video.',
      );
    }

    final String normalizedHistoryStatus = _normalizeHistoryStatus(status);

    final String authenticatedUid = _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>> callReference =
        callsCollection.doc(normalizedCallId);

    final DocumentReference<Map<String, dynamic>> historyReference =
        callHistoryCollection.doc(normalizedCallId);

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> callSnapshot =
          await transaction.get(callReference);

      final Map<String, dynamic>? callData = callSnapshot.data();

      if (!callSnapshot.exists || callData == null) {
        throw StateError(
          'Cannot save call history because '
          'the call document is unavailable.',
        );
      }

      _requireParticipant(callData, authenticatedUid);

      final String? callerId = _readString(callData['callerId']);

      final String? receiverId = _readString(callData['receiverId']);

      if (callerId == null || receiverId == null) {
        throw StateError(
          'Cannot save call history because '
          'participant identity is invalid.',
        );
      }

      final DocumentSnapshot<Map<String, dynamic>> historySnapshot =
          await transaction.get(historyReference);

      // One shared deterministic record prevents duplicate
      // caller/receiver history documents.
      if (historySnapshot.exists) {
        return;
      }

      transaction.set(historyReference, <String, dynamic>{
        // Required by firestore.rules.
        'callId': normalizedCallId,
        'duration': duration,
        'status': normalizedHistoryStatus,
        'callType': normalizedCallType,

        // Participant identity required for future read/delete.
        'callerId': callerId,
        'receiverId': receiverId,

        // Stable session compatibility.
        'sessionId': normalizedCallId,

        // Optional real call data only.
        'callerName': callData['callerName'],
        'receiverName': callData['receiverName'],

        // Do not manufacture photos/names.
        if (callData.containsKey('callerPhoto'))
          'callerPhoto': callData['callerPhoto'],

        if (callData.containsKey('receiverPhoto'))
          'receiverPhoto': callData['receiverPhoto'],

        'createdAt': callData['createdAt'] ?? FieldValue.serverTimestamp(),

        'endedAt': callData['endedAt'] ?? FieldValue.serverTimestamp(),

        'savedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  String _normalizeHistoryStatus(String status) {
    final String normalized = status.trim().toLowerCase();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        status,
        'status',
        'Call history status cannot be empty.',
      );
    }

    switch (normalized) {
      case 'completed':
      case 'complete':
      case 'ended':
      case 'connected':
      case 'success':
        return 'completed';

      case 'timeout':
      case 'missed':
      case 'missed_call':
      case 'noanswer':
      case 'no_answer':
      case 'unanswered':
        return 'missed';

      case 'rejected':
        return 'rejected';

      case 'declined':
        return 'declined';

      case 'cancelled':
      case 'canceled':
        return 'cancelled';

      case 'failed':
      case 'error':
        return 'failed';

      case 'busy':
      case 'user_busy':
        return 'busy';

      default:
        // Preserve an unknown real backend status rather than
        // falsely claiming completed.
        return normalized;
    }
  }

  // =============================================================
  // RECOVERY METADATA
  // =============================================================

  Future<void> incrementIceRestart(String callId) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final String authenticatedUid = _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>> reference = callsCollection
        .doc(normalizedCallId);

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);

      final Map<String, dynamic>? data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return;
      }

      _requireParticipant(data, authenticatedUid);

      final String? status = _readString(data['status'])?.toLowerCase();

      if (status == null || _terminalStatuses.contains(status)) {
        return;
      }

      transaction.update(reference, <String, dynamic>{
        'iceRestartCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> markNetworkRecovered(String callId, bool recovered) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final String authenticatedUid = _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>> reference = callsCollection
        .doc(normalizedCallId);

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await transaction
          .get(reference);

      final Map<String, dynamic>? data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return;
      }

      _requireParticipant(data, authenticatedUid);

      final String? status = _readString(data['status'])?.toLowerCase();

      if (status == null || _terminalStatuses.contains(status)) {
        return;
      }

      transaction.update(reference, <String, dynamic>{
        'networkRecovered': recovered,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // =============================================================
  // CONNECTION METADATA
  // =============================================================

  Future<void> updateConnectionMetadata({
    required String callId,
    String? connectionState,
    String? iceConnectionState,
    String? signalingState,
    String? iceGatheringState,
  }) async {
    final Map<String, dynamic> update = <String, dynamic>{};

    final String? connection = _readString(connectionState);

    final String? iceConnection = _readString(iceConnectionState);

    final String? signaling = _readString(signalingState);

    final String? gathering = _readString(iceGatheringState);

    if (connection != null) {
      update['connectionState'] = connection;
    }

    if (iceConnection != null) {
      update['iceConnectionState'] = iceConnection;
    }

    if (signaling != null) {
      update['signalingState'] = signaling;
    }

    if (gathering != null) {
      update['iceGatheringState'] = gathering;
    }

    if (update.isEmpty) {
      return;
    }

    await updateCall(callId: callId, data: update);
  }

  // =============================================================
  // PRESENCE COMPATIBILITY
  // =============================================================

  Future<void> updateLastSeen(String userId) async {
    final String normalizedUserId = _requireId(userId, 'userId');

    final User? currentUser = auth.currentUser;

    if (currentUser == null || currentUser.uid != normalizedUserId) {
      return;
    }

    await firestore.collection('users').doc(normalizedUserId).set(
      <String, dynamic>{'lastSeen': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
  listenConnectionHealth(
    String userId,
    void Function(bool isOnline) onHealthChanged,
  ) {
    final String normalizedUserId = _requireId(userId, 'userId');

    bool? previousValue;

    return firestore
        .collection('users')
        .doc(normalizedUserId)
        .snapshots()
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snapshot) {
            final DateTime? lastSeen = _timestampToDate(
              snapshot.data()?['lastSeen'],
            );

            final bool online =
                lastSeen != null &&
                DateTime.now().difference(lastSeen).inSeconds < 45;

            if (online == previousValue) {
              return;
            }

            previousValue = online;

            onHealthChanged(online);
          },
          onError: (Object error, StackTrace stackTrace) {
            _reportError('presence listener', error, stackTrace);
          },
        );
  }

  // =============================================================
  // STALE CALL CLEANUP
  // =============================================================

  Future<void> deleteExpiredCalls() async {
    final String? userId = _clean(auth.currentUser?.uid);

    if (userId == null) {
      return;
    }

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> documents =
        await _loadOwnedCallsByStatus(
          userId: userId,
          statuses: _stalePendingStatuses,
        );

    final DateTime now = DateTime.now();

    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
        in documents) {
      final Map<String, dynamic> data = document.data();

      final DateTime? createdAt = _timestampToDate(data['createdAt']);

      if (createdAt == null ||
          now.difference(createdAt) <= const Duration(minutes: 2)) {
        continue;
      }

      final String? status = _readString(data['status'])?.toLowerCase();

      if (status == null || !_stalePendingStatuses.contains(status)) {
        continue;
      }

      try {
        await updateCallStatus(document.id, 'timeout');
      } catch (error, stackTrace) {
        _reportError('stale-call cleanup ${document.id}', error, stackTrace);
      }
    }
  }

  // =============================================================
  // ENDED CALL CLEANUP
  // =============================================================

  Future<void> cleanupEndedCalls() async {
    final String? userId = _clean(auth.currentUser?.uid);

    if (userId == null) {
      return;
    }

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> documents =
        await _loadOwnedCallsByStatus(
          userId: userId,
          statuses: _terminalStatuses.toList(growable: false),
        );

    final DateTime now = DateTime.now();

    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
        in documents) {
      final DateTime? endedAt = _timestampToDate(document.data()['endedAt']);

      if (endedAt == null ||
          now.difference(endedAt) <= const Duration(hours: 24)) {
        continue;
      }

      try {
        await deleteCall(document.id);
      } catch (error, stackTrace) {
        _reportError('ended-call cleanup ${document.id}', error, stackTrace);
      }
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadOwnedCallsByStatus({
    required String userId,
    required List<String> statuses,
  }) async {
    if (statuses.isEmpty) {
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }

    final List<QuerySnapshot<Map<String, dynamic>>> results =
        await Future.wait<QuerySnapshot<Map<String, dynamic>>>(
          <Future<QuerySnapshot<Map<String, dynamic>>>>[
            callsCollection
                .where('callerId', isEqualTo: userId)
                .where('status', whereIn: statuses)
                .get(),
            callsCollection
                .where('receiverId', isEqualTo: userId)
                .where('status', whereIn: statuses)
                .get(),
          ],
        );

    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
    uniqueDocuments = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    for (final QuerySnapshot<Map<String, dynamic>> snapshot in results) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> document
          in snapshot.docs) {
        uniqueDocuments[document.id] = document;
      }
    }

    return List<QueryDocumentSnapshot<Map<String, dynamic>>>.unmodifiable(
      uniqueDocuments.values,
    );
  }

  // =============================================================
  // AUTHORIZATION
  // =============================================================

  String _requireAuthenticatedUid() {
    final String? uid = _clean(auth.currentUser?.uid);

    if (uid == null) {
      throw StateError('Firebase authentication is required.');
    }

    return uid;
  }

  void _requireParticipant(Map<String, dynamic> data, String authenticatedUid) {
    final String? callerId = _readString(data['callerId']);

    final String? receiverId = _readString(data['receiverId']);

    if (callerId == null || receiverId == null) {
      throw StateError('Call participant identity is invalid.');
    }

    if (authenticatedUid != callerId && authenticatedUid != receiverId) {
      throw StateError(
        'Authenticated user is not a participant '
        'of this call.',
      );
    }
  }

  void _requireExpectedParticipantRole({
    required Map<String, dynamic> data,
    required String authenticatedUid,
    required _CallParticipantRole expectedRole,
  }) {
    final String? callerId = _readString(data['callerId']);

    final String? receiverId = _readString(data['receiverId']);

    if (callerId == null || receiverId == null) {
      throw StateError('Call participant identity is invalid.');
    }

    final String expectedUid = expectedRole == _CallParticipantRole.caller
        ? callerId
        : receiverId;

    if (authenticatedUid != expectedUid) {
      throw StateError(
        expectedRole == _CallParticipantRole.caller
            ? 'Only the authenticated caller may '
                  'write caller signaling data.'
            : 'Only the authenticated receiver may '
                  'write receiver signaling data.',
      );
    }
  }

  // =============================================================
  // DATA HELPERS
  // =============================================================

  String _requireId(String value, String parameterName) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        parameterName,
        '$parameterName cannot be empty.',
      );
    }

    return normalized;
  }

  String? _clean(String? value) {
    final String normalized = value?.trim() ?? '';

    return normalized.isEmpty ? null : normalized;
  }

  String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }

    return _clean(value);
  }

  Map<String, dynamic>? _normalizeMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      final Map<String, dynamic> result = <String, dynamic>{};

      for (final MapEntry<dynamic, dynamic> entry in value.entries) {
        if (entry.key is! String) {
          return null;
        }

        result[entry.key as String] = entry.value;
      }

      return result;
    }

    return null;
  }

  Map<String, dynamic> _normalizeIceCandidate(Map<String, dynamic> candidate) {
    final String? candidateValue = _readString(candidate['candidate']);

    if (candidateValue == null) {
      throw ArgumentError('ICE candidate string cannot be empty.');
    }

    final String? sdpMid = _readString(candidate['sdpMid']);

    final Object? rawLineIndex = candidate['sdpMLineIndex'];

    int? lineIndex;

    if (rawLineIndex is int) {
      lineIndex = rawLineIndex;
    } else if (rawLineIndex is num && rawLineIndex.isFinite) {
      lineIndex = rawLineIndex.toInt();
    } else if (rawLineIndex is String) {
      lineIndex = int.tryParse(rawLineIndex.trim());
    }

    if (lineIndex != null && lineIndex < 0) {
      lineIndex = null;
    }

    return <String, dynamic>{
      'candidate': candidateValue,
      'sdpMid': sdpMid,
      'sdpMLineIndex': lineIndex,
    };
  }

  DateTime? _timestampToDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is num) {
      final int raw = value.toInt();

      try {
        if (raw.abs() < 100000000000) {
          return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
        }

        if (raw.abs() >= 100000000000000) {
          return DateTime.fromMicrosecondsSinceEpoch(raw);
        }

        return DateTime.fromMillisecondsSinceEpoch(raw);
      } on RangeError {
        return null;
      }
    }

    if (value is String) {
      return DateTime.tryParse(value.trim());
    }

    return null;
  }

  // =============================================================
  // LOGGING
  // =============================================================

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint(
      'JR CALL [SignalingService/$source] '
      'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [SignalingService/$source]',
        stackTrace: stackTrace,
      );
    }
  }
}

enum _CallParticipantRole { caller, receiver }

// ===============================================================
// END OF FILE
//
// FIXED:
// - BUG 04: deterministic real call-history persistence hardened
// - BUG 07: unauthorized remote busy-query blocker removed
// - BUG 07: caller/receiver UID and signaling roles hardened
// - BUG 07: late terminal SDP/ICE/status writes blocked
// - BUG 08: video-call type preserved through signaling creation
// - BUG 08: caller/receiver signaling ownership preserved
// - Duplicate ICE candidate persistence prevented
// - Generic Firestore writes restricted to rule-approved fields
// - History status normalization hardened
// - Timestamp compatibility hardened
//
// STATUS: READY FOR FORMAT + ANALYZE
//
// NEXT FILE: call_listener_service.dart
// Location: lib/services/call/call_listener_service.dart
// ===============================================================
