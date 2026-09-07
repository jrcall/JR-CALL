// ===============================================================
// JR CALL
// File: signaling_service.dart
// Location: lib/services/call/signaling_service.dart
//
// FINAL PRODUCTION SIGNALING SERVICE
//
// OWNERSHIP:
//
// Firebase Auth UID:
// - Canonical internal participant identity.
//
// SignalingService:
// - Firestore call-document signaling.
// - Offer / answer persistence.
// - Negotiation revision persistence.
// - ICE candidate persistence.
// - Call status persistence.
// - Recovery metadata persistence.
// - Deterministic call-history persistence.
//
// CallService:
// - Complete lifecycle orchestration.
// - Terminal outcome orchestration.
// - History orchestration.
// - Collision / busy / multi-device policy.
//
// CallListenerService:
// - Ordered call-document observation.
//
// WebRTCService / PeerConnectionManager:
// - PeerConnection.
// - Local / remote SDP application.
// - Negotiation rollback / perfect-negotiation behavior.
// - Media transport.
//
// IceManager:
// - Local / remote candidate coordination.
// - Out-of-order candidate buffering.
// - Candidate application.
//
// RecoveryManager / NetworkManager:
// - Network recovery.
// - Handover.
// - Bounded ICE restart policy.
//
// PRODUCTION GUARANTEES:
//
// - FILE 01 CallStatus is canonical.
// - Firebase UID is canonical identity.
// - Legacy status aliases are read/input compatible only.
// - New writes never persist declined/timeout aliases.
// - Terminal status is immutable.
// - CallSecurity validates lifecycle transitions.
// - Late SDP / ICE after terminal state is ignored.
// - Generic updates cannot mutate protected signaling identity.
// - Duplicate ICE persistence is prevented.
// - ICE usernameFragment is preserved when supplied.
// - Initial caller remains preferred negotiation side.
// - Either participant may initiate later renegotiation.
// - Concurrent offer glare uses deterministic caller-wins policy.
// - Answer writer must be opposite the current offerer.
// - Negotiation revisions reject stale answer ownership.
// - Either endpoint can request/persist ICE restart metadata.
// - No fake CONNECTED lifecycle is generated here.
// - Call history is exactly one document per callId.
// - Arbitrary remote-user private busy enumeration is not performed.
// ===============================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/call_status.dart';
import 'call_security.dart';

class SignalingService {
  SignalingService._();

  static final SignalingService instance =
  SignalingService._();

  // =============================================================
  // FIREBASE
  // =============================================================

  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  /// Existing public compatibility API.
  final FirebaseAuth auth =
      FirebaseAuth.instance;

  final CallSecurity _security =
      CallSecurity.instance;

  // =============================================================
  // COLLECTIONS
  // =============================================================

  static const String callsCollectionName =
      'calls';

  static const String callHistoryCollectionName =
      'call_history';

  CollectionReference<Map<String, dynamic>>
  get callsCollection {
    return firestore.collection(
      callsCollectionName,
    );
  }

  CollectionReference<Map<String, dynamic>>
  get callHistoryCollection {
    return firestore.collection(
      callHistoryCollectionName,
    );
  }

  // =============================================================
  // STATUS CONTRACT
  // =============================================================

  static const Set<String> _validStatuses =
  <String>{
    'calling',
    'ringing',
    'accepted',
    'rejected',
    'ended',
    'missed',
    'connecting',
    'connected',
    'reconnecting',
    'busy',
    'cancelled',
    'failed',
  };

  static const Set<String> _terminalStatuses =
  <String>{
    'rejected',
    'ended',
    'missed',
    'busy',
    'cancelled',
    'failed',
  };

  static const List<String> _activeStatuses =
  <String>[
    'calling',
    'ringing',
    'accepted',
    'connecting',
    'connected',
    'reconnecting',
  ];

  static const List<String> _stalePendingStatuses =
  <String>[
    'calling',
    'ringing',
    'accepted',
    'connecting',
  ];

  // =============================================================
  // GENERIC MUTABLE FIELD CONTRACT
  // =============================================================

  static const Set<String> _genericMutableFields =
  <String>{
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
  // COMPATIBILITY
  // =============================================================

  /// Existing compatibility getter.
  ///
  /// Actual runtime signaling state remains PeerConnection-owned.
  String get signalingState => 'stable';

  // =============================================================
  // CALL CREATION
  // =============================================================

  Future<DocumentReference<Map<String, dynamic>>> createCall({
    required String callerId,
    required String receiverId,
    bool isVideoCall = true,
  }) async {
    final String normalizedCallerId =
    _requireId(
      callerId,
      'callerId',
    );

    final String normalizedReceiverId =
    _requireId(
      receiverId,
      'receiverId',
    );

    if (normalizedCallerId ==
        normalizedReceiverId) {
      throw ArgumentError(
        'A JR CALL user cannot call themselves.',
      );
    }

    final String authenticatedUid =
    _requireAuthenticatedUid();

    if (authenticatedUid !=
        normalizedCallerId) {
      throw StateError(
        'Authenticated Firebase UID '
            'does not match callerId.',
      );
    }

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc();

    await reference.set(
      <String, dynamic>{
        'callId': reference.id,
        'callerId':
        normalizedCallerId,
        'receiverId':
        normalizedReceiverId,
        'status':
        CallStatus.calling.name,
        'video':
        isVideoCall,
        'isVideoCall':
        isVideoCall,
        'createdAt':
        FieldValue.serverTimestamp(),
        'serverCreatedAt':
        FieldValue.serverTimestamp(),
        'updatedAt':
        FieldValue.serverTimestamp(),
        'endedAt':
        null,
        'endedBy':
        null,
        'schemaVersion':
        1,
        'revision':
        0,
        'offer':
        null,
        'answer':
        null,
        'offererUid':
        null,
        'answererUid':
        null,
        'negotiationRevision':
        0,
        'offerRevision':
        0,
        'answerRevision':
        0,
        'callerCandidates':
        <Map<String, dynamic>>[],
        'receiverCandidates':
        <Map<String, dynamic>>[],
        'connectionState':
        'new',
        'iceConnectionState':
        'new',
        'signalingState':
        'stable',
        'iceGatheringState':
        'new',
        'networkRecovered':
        false,
        'iceRestartCount':
        0,
        'iceRestartRequestedBy':
        null,
        'iceRestartRequestedAt':
        null,
      },
    );

    return reference;
  }

  // =============================================================
  // OFFER
  // =============================================================

  Future<void> saveOffer(
      String callId,
      Map<String, dynamic> offer,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final String? sdp =
    _readString(
      offer['sdp'],
    );

    final String? type =
    _readString(
      offer['type'],
    )?.toLowerCase();

    if (sdp == null ||
        type != 'offer') {
      throw ArgumentError(
        'Invalid WebRTC offer '
            'session description.',
      );
    }

    if (sdp.length > 600000) {
      throw ArgumentError(
        'WebRTC offer is too large.',
      );
    }

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        snapshot =
        await transaction.get(
          reference,
        );

        final Map<String, dynamic>? data =
        snapshot.data();

        if (!snapshot.exists ||
            data == null) {
          throw StateError(
            'Call document does not exist.',
          );
        }

        _requireParticipant(
          data,
          authenticatedUid,
        );

        final String? canonicalStatus =
        _canonicalStatusOrNull(
          _readString(
            data['status'],
          ) ??
              '',
        );

        if (canonicalStatus == null) {
          throw StateError(
            'Call status is invalid.',
          );
        }

        if (_terminalStatuses.contains(
          canonicalStatus,
        )) {
          return;
        }

        final String callerUid =
        _requireParticipantId(
          data,
          'callerId',
        );

        final String? currentOfferer =
        _readString(
          data['offererUid'],
        );

        final int currentOfferRevision =
            _readNonNegativeInt(
              data['offerRevision'],
            ) ??
                0;

        final int currentAnswerRevision =
            _readNonNegativeInt(
              data['answerRevision'],
            ) ??
                0;

        final int currentNegotiationRevision =
            _readNonNegativeInt(
              data['negotiationRevision'],
            ) ??
                0;

        final Map<String, dynamic>?
        previousOffer =
        _normalizeMap(
          data['offer'],
        );

        final String? previousSdp =
        _readString(
          previousOffer?['sdp'],
        );

        final String? previousType =
        _readString(
          previousOffer?['type'],
        )?.toLowerCase();

        if (currentOfferer ==
            authenticatedUid &&
            previousSdp == sdp &&
            previousType == type) {
          return;
        }

        final bool outstandingOffer =
            currentOfferRevision >
                currentAnswerRevision &&
                previousSdp != null;

        if (outstandingOffer &&
            currentOfferer != null &&
            currentOfferer !=
                authenticatedUid) {
          if (authenticatedUid !=
              callerUid) {
            return;
          }
        }

        final int baseRevision =
        currentNegotiationRevision >
            currentOfferRevision
            ? currentNegotiationRevision
            : currentOfferRevision;

        final int nextRevision =
            baseRevision + 1;

        transaction.update(
          reference,
          <String, dynamic>{
            'offer':
            <String, dynamic>{
              'type':
              'offer',
              'sdp':
              sdp,
            },
            'answer':
            null,
            'offererUid':
            authenticatedUid,
            'answererUid':
            null,
            'negotiationRevision':
            nextRevision,
            'offerRevision':
            nextRevision,
            'answerRevision':
            currentAnswerRevision,
            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );
      },
    );
  }

  // =============================================================
  // ANSWER
  // =============================================================

  Future<void> saveAnswer(
      String callId,
      Map<String, dynamic> answer,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final String? sdp =
    _readString(
      answer['sdp'],
    );

    final String? type =
    _readString(
      answer['type'],
    )?.toLowerCase();

    if (sdp == null ||
        type != 'answer') {
      throw ArgumentError(
        'Invalid WebRTC answer '
            'session description.',
      );
    }

    if (sdp.length > 600000) {
      throw ArgumentError(
        'WebRTC answer is too large.',
      );
    }

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        snapshot =
        await transaction.get(
          reference,
        );

        final Map<String, dynamic>? data =
        snapshot.data();

        if (!snapshot.exists ||
            data == null) {
          throw StateError(
            'Call document does not exist.',
          );
        }

        _requireParticipant(
          data,
          authenticatedUid,
        );

        final String? canonicalStatus =
        _canonicalStatusOrNull(
          _readString(
            data['status'],
          ) ??
              '',
        );

        if (canonicalStatus == null) {
          throw StateError(
            'Call status is invalid.',
          );
        }

        if (_terminalStatuses.contains(
          canonicalStatus,
        )) {
          return;
        }

        final String? offererUid =
        _readString(
          data['offererUid'],
        );

        final int offerRevision =
            _readNonNegativeInt(
              data['offerRevision'],
            ) ??
                0;

        final int answerRevision =
            _readNonNegativeInt(
              data['answerRevision'],
            ) ??
                0;

        if (offererUid == null ||
            offerRevision <= 0) {
          throw StateError(
            'Cannot save an answer before '
                'a valid offer exists.',
          );
        }

        if (authenticatedUid ==
            offererUid) {
          throw StateError(
            'The current offerer cannot '
                'answer their own offer.',
          );
        }

        if (answerRevision >
            offerRevision) {
          throw StateError(
            'Negotiation revision is invalid.',
          );
        }

        final Map<String, dynamic>?
        previousAnswer =
        _normalizeMap(
          data['answer'],
        );

        final String? previousSdp =
        _readString(
          previousAnswer?['sdp'],
        );

        final String? previousType =
        _readString(
          previousAnswer?['type'],
        )?.toLowerCase();

        if (answerRevision ==
            offerRevision &&
            previousSdp == sdp &&
            previousType == type) {
          return;
        }

        if (answerRevision ==
            offerRevision &&
            previousSdp != null &&
            previousSdp != sdp) {
          return;
        }

        transaction.update(
          reference,
          <String, dynamic>{
            'answer':
            <String, dynamic>{
              'type':
              'answer',
              'sdp':
              sdp,
            },
            'answererUid':
            authenticatedUid,
            'answerRevision':
            offerRevision,
            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );
      },
    );
  }

  // =============================================================
  // GET OFFER / ANSWER
  // =============================================================

  Future<Map<String, dynamic>?> getOffer(
      String callId,
      ) {
    return _getSessionDescription(
      callId: callId,
      field: 'offer',
      expectedType: 'offer',
    );
  }

  Future<Map<String, dynamic>?> getAnswer(
      String callId,
      ) {
    return _getSessionDescription(
      callId: callId,
      field: 'answer',
      expectedType: 'answer',
    );
  }

  Future<Map<String, dynamic>?>
  _getSessionDescription({
    required String callId,
    required String field,
    required String expectedType,
  }) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final DocumentSnapshot<Map<String, dynamic>>
    snapshot =
    await callsCollection
        .doc(
      normalizedCallId,
    )
        .get();

    final Map<String, dynamic>? data =
    snapshot.data();

    if (!snapshot.exists ||
        data == null) {
      return null;
    }

    _requireParticipant(
      data,
      _requireAuthenticatedUid(),
    );

    final Map<String, dynamic>? description =
    _normalizeMap(
      data[field],
    );

    if (description == null) {
      return null;
    }

    final String? sdp =
    _readString(
      description['sdp'],
    );

    final String? type =
    _readString(
      description['type'],
    )?.toLowerCase();

    if (sdp == null ||
        type != expectedType) {
      return null;
    }

    return Map<String, dynamic>.unmodifiable(
      <String, dynamic>{
        'type':
        type,
        'sdp':
        sdp,
      },
    );
  }

  // =============================================================
  // RAW CALL STREAM
  // =============================================================

  Stream<DocumentSnapshot<Map<String, dynamic>>>
  listenCall(
      String callId,
      ) {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    return callsCollection
        .doc(
      normalizedCallId,
    )
        .snapshots()
        .map<
        DocumentSnapshot<
            Map<String, dynamic>>>(
          (
          DocumentSnapshot<
              Map<String, dynamic>>
          snapshot,
          ) {
        if (!snapshot.exists) {
          return snapshot;
        }

        final Map<String, dynamic>? data =
        snapshot.data();

        if (data != null) {
          _requireParticipant(
            data,
            _requireAuthenticatedUid(),
          );
        }

        return snapshot;
      },
    );
  }

  // =============================================================
  // RAW CALL ACCESS
  // =============================================================

  Future<Map<String, dynamic>>
  getCallDocument(
      String callId,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final DocumentSnapshot<Map<String, dynamic>>
    snapshot =
    await callsCollection
        .doc(
      normalizedCallId,
    )
        .get();

    final Map<String, dynamic>? data =
    snapshot.data();

    if (!snapshot.exists ||
        data == null) {
      throw StateError(
        'Call document not found '
            'for callId: $normalizedCallId',
      );
    }

    _requireParticipant(
      data,
      _requireAuthenticatedUid(),
    );

    return Map<String, dynamic>.unmodifiable(
      Map<String, dynamic>.from(
        data,
      ),
    );
  }

  // =============================================================
  // GENERIC CALL UPDATE
  // =============================================================

  Future<void> updateCall({
    required String callId,
    required Map<String, dynamic> data,
  }) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    if (data.isEmpty) {
      return;
    }

    final Map<String, dynamic> updateData =
    <String, dynamic>{};

    for (final MapEntry<String, dynamic>
    entry in data.entries) {
      if (!_genericMutableFields.contains(
        entry.key,
      )) {
        continue;
      }

      switch (entry.key) {
        case 'networkRecovered':
          if (entry.value is! bool) {
            throw ArgumentError(
              'networkRecovered must '
                  'be a boolean.',
            );
          }

          updateData[entry.key] =
              entry.value;
          break;

        case 'iceRestartCount':
          final Object? value =
              entry.value;

          if (value is int) {
            if (value < 0) {
              throw ArgumentError(
                'iceRestartCount cannot '
                    'be negative.',
              );
            }

            updateData[entry.key] =
                value;
          } else if (value is FieldValue) {
            updateData[entry.key] =
                value;
          } else {
            throw ArgumentError(
              'iceRestartCount must be '
                  'an integer or Firestore '
                  'increment value.',
            );
          }

          break;

        case 'callerName':
        case 'receiverName':
          final String? value =
          _readString(
            entry.value,
          );

          if (value == null) {
            continue;
          }

          if (value.length > 200) {
            throw ArgumentError(
              '${entry.key} is too long.',
            );
          }

          updateData[entry.key] =
              value;
          break;

        default:
          final String? value =
          _readString(
            entry.value,
          );

          if (value == null) {
            continue;
          }

          if (value.length > 80) {
            throw ArgumentError(
              '${entry.key} is too long.',
            );
          }

          updateData[entry.key] =
              value;
          break;
      }
    }

    if (updateData.isEmpty) {
      return;
    }

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        snapshot =
        await transaction.get(
          reference,
        );

        final Map<String, dynamic>? callData =
        snapshot.data();

        if (!snapshot.exists ||
            callData == null) {
          return;
        }

        _requireParticipant(
          callData,
          authenticatedUid,
        );

        final String? status =
        _canonicalStatusOrNull(
          _readString(
            callData['status'],
          ) ??
              '',
        );

        if (status == null ||
            _terminalStatuses.contains(
              status,
            )) {
          return;
        }

        final Object? requestedRestart =
        updateData['iceRestartCount'];

        if (requestedRestart is int) {
          final int currentRestart =
              _readNonNegativeInt(
                callData[
                'iceRestartCount'],
              ) ??
                  0;

          if (requestedRestart <
              currentRestart) {
            throw StateError(
              'iceRestartCount cannot move backwards.',
            );
          }
        }

        final Map<String, dynamic>
        committedUpdate =
        Map<String, dynamic>.from(
          updateData,
        );

        committedUpdate['updatedAt'] =
            FieldValue.serverTimestamp();

        transaction.update(
          reference,
          committedUpdate,
        );
      },
    );
  }

  // =============================================================
  // CALL STATUS
  // =============================================================

  Future<void> updateCallStatus(
      String callId,
      String status,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String? canonicalStatus =
    _canonicalStatusOrNull(
      status,
    );

    if (canonicalStatus == null) {
      throw ArgumentError.value(
        status,
        'status',
        'Unsupported JR CALL status.',
      );
    }

    final CallStatus nextStatus =
    _callStatusFromCanonical(
      canonicalStatus,
    );

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        snapshot =
        await transaction.get(
          reference,
        );

        final Map<String, dynamic>? data =
        snapshot.data();

        if (!snapshot.exists ||
            data == null) {
          return;
        }

        _requireParticipant(
          data,
          authenticatedUid,
        );

        final String? canonicalCurrent =
        _canonicalStatusOrNull(
          _readString(
            data['status'],
          ) ??
              '',
        );

        if (canonicalCurrent == null) {
          throw StateError(
            'Current JR CALL status is invalid.',
          );
        }

        final CallStatus currentStatus =
        _callStatusFromCanonical(
          canonicalCurrent,
        );

        if (currentStatus ==
            nextStatus) {
          return;
        }

        if (_security.isTerminalStatus(
          currentStatus,
        )) {
          return;
        }

        if (!_security.isValidStatusTransition(
          currentStatus,
          nextStatus,
        )) {
          throw StateError(
            'Invalid JR CALL status transition: '
                '${currentStatus.name} -> '
                '${nextStatus.name}.',
          );
        }

        _requireStatusWriter(
          data: data,
          authenticatedUid:
          authenticatedUid,
          nextStatus:
          nextStatus,
        );

        final Map<String, dynamic> update =
        _buildStatusUpdate(
          data: data,
          authenticatedUid:
          authenticatedUid,
          nextStatus:
          nextStatus,
        );

        transaction.update(
          reference,
          update,
        );
      },
    );
  }

  // =============================================================
  // END CALL
  // =============================================================

  Future<void> endCall(
      String callId,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        snapshot =
        await transaction.get(
          reference,
        );

        final Map<String, dynamic>? data =
        snapshot.data();

        if (!snapshot.exists ||
            data == null) {
          return;
        }

        _requireParticipant(
          data,
          authenticatedUid,
        );

        final String? canonicalCurrent =
        _canonicalStatusOrNull(
          _readString(
            data['status'],
          ) ??
              '',
        );

        if (canonicalCurrent == null) {
          throw StateError(
            'Current JR CALL status is invalid.',
          );
        }

        final CallStatus currentStatus =
        _callStatusFromCanonical(
          canonicalCurrent,
        );

        if (_security.isTerminalStatus(
          currentStatus,
        )) {
          return;
        }

        final String callerUid =
        _requireParticipantId(
          data,
          'callerId',
        );

        final CallStatus nextStatus;

        switch (currentStatus) {
          case CallStatus.calling:
          case CallStatus.ringing:
            nextStatus =
            authenticatedUid ==
                callerUid
                ? CallStatus.cancelled
                : CallStatus.rejected;
            break;

          case CallStatus.accepted:
          case CallStatus.connecting:
          case CallStatus.connected:
          case CallStatus.reconnecting:
            nextStatus =
                CallStatus.ended;
            break;

          case CallStatus.rejected:
          case CallStatus.ended:
          case CallStatus.missed:
          case CallStatus.busy:
          case CallStatus.cancelled:
          case CallStatus.failed:
            return;
        }

        if (!_security.isValidStatusTransition(
          currentStatus,
          nextStatus,
        )) {
          throw StateError(
            'Invalid JR CALL end transition: '
                '${currentStatus.name} -> '
                '${nextStatus.name}.',
          );
        }

        _requireStatusWriter(
          data: data,
          authenticatedUid:
          authenticatedUid,
          nextStatus:
          nextStatus,
        );

        transaction.update(
          reference,
          _buildStatusUpdate(
            data: data,
            authenticatedUid:
            authenticatedUid,
            nextStatus:
            nextStatus,
          ),
        );
      },
    );
  }

  // =============================================================
  // DELETE CALL
  // =============================================================

  Future<void> deleteCall(
      String callId,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        snapshot =
        await transaction.get(
          reference,
        );

        final Map<String, dynamic>? data =
        snapshot.data();

        if (!snapshot.exists ||
            data == null) {
          return;
        }

        _requireParticipant(
          data,
          authenticatedUid,
        );

        transaction.delete(
          reference,
        );
      },
    );
  }

  // =============================================================
  // CALLER ICE
  // =============================================================

  Future<void> addCallerCandidate(
      String callId,
      Map<String, dynamic> candidate,
      ) {
    return _appendIceCandidate(
      callId: callId,
      field: 'callerCandidates',
      candidate: candidate,
      expectedRole:
      _CallParticipantRole.caller,
    );
  }

  // =============================================================
  // RECEIVER ICE
  // =============================================================

  Future<void> addReceiverCandidate(
      String callId,
      Map<String, dynamic> candidate,
      ) {
    return _appendIceCandidate(
      callId: callId,
      field: 'receiverCandidates',
      candidate: candidate,
      expectedRole:
      _CallParticipantRole.receiver,
    );
  }

  // =============================================================
  // GENERIC ICE COMPATIBILITY
  // =============================================================

  Future<void> addIceCandidate(
      String callId,
      bool isCaller,
      Map<String, dynamic> candidate,
      ) async {
    const int maximumAttempts =
    3;

    Object? lastError;
    StackTrace? lastStackTrace;

    for (
    int attempt = 1;
    attempt <= maximumAttempts;
    attempt++
    ) {
      try {
        if (isCaller) {
          await addCallerCandidate(
            callId,
            candidate,
          );
        } else {
          await addReceiverCandidate(
            callId,
            candidate,
          );
        }

        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;

        if (!_shouldRetryIceWrite(
          error,
        ) ||
            attempt >=
                maximumAttempts) {
          break;
        }

        await Future<void>.delayed(
          Duration(
            milliseconds:
            250 * attempt,
          ),
        );
      }
    }

    final Object failure =
        lastError ??
            StateError(
              'Unknown ICE candidate '
                  'persistence error.',
            );

    _reportError(
      'ICE candidate persistence',
      failure,
      lastStackTrace,
    );

    if (lastStackTrace != null) {
      Error.throwWithStackTrace(
        failure,
        lastStackTrace,
      );
    }

    throw failure;
  }

  Future<void> _appendIceCandidate({
    required String callId,
    required String field,
    required Map<String, dynamic> candidate,
    required _CallParticipantRole expectedRole,
  }) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final Map<String, dynamic>
    normalizedCandidate =
    _normalizeIceCandidate(
      candidate,
    );

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        snapshot =
        await transaction.get(
          reference,
        );

        final Map<String, dynamic>? data =
        snapshot.data();

        if (!snapshot.exists ||
            data == null) {
          return;
        }

        _requireExpectedParticipantRole(
          data: data,
          authenticatedUid:
          authenticatedUid,
          expectedRole:
          expectedRole,
        );

        final String? status =
        _canonicalStatusOrNull(
          _readString(
            data['status'],
          ) ??
              '',
        );

        if (status == null ||
            _terminalStatuses.contains(
              status,
            )) {
          return;
        }

        final Object? rawCurrentCandidates =
        data[field];

        final List<dynamic>
        currentCandidates =
        rawCurrentCandidates is List
            ? List<dynamic>.from(
          rawCurrentCandidates,
        )
            : <dynamic>[];

        final String signature =
        _iceCandidateSignature(
          normalizedCandidate,
        );

        final bool duplicate =
        currentCandidates.any(
              (dynamic rawCandidate) {
            final Map<String, dynamic>?
            existing =
            _normalizeMap(
              rawCandidate,
            );

            if (existing == null) {
              return false;
            }

            return _iceCandidateSignature(
              existing,
            ) ==
                signature;
          },
        );

        if (duplicate) {
          return;
        }

        transaction.update(
          reference,
          <String, dynamic>{
            field:
            FieldValue.arrayUnion(
              <Map<String, dynamic>>[
                normalizedCandidate,
              ],
            ),
            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );
      },
    );
  }

  String _iceCandidateSignature(
      Map<String, dynamic> candidate,
      ) {
    final String candidateValue =
        _readString(
          candidate['candidate'],
        ) ??
            '';

    final String sdpMid =
        _readString(
          candidate['sdpMid'],
        ) ??
            '';

    final Object? lineIndex =
    candidate['sdpMLineIndex'];

    final String usernameFragment =
        _readString(
          candidate[
          'usernameFragment'],
        ) ??
            '';

    return '$candidateValue|'
        '$sdpMid|'
        '${lineIndex ?? ''}|'
        '$usernameFragment';
  }

  bool _shouldRetryIceWrite(
      Object error,
      ) {
    if (error is! FirebaseException) {
      return false;
    }

    switch (error.code.trim().toLowerCase()) {
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

  Stream<List<Map<String, dynamic>>>
  listenToRemoteICECandidates(
      String callId,
      bool isCaller,
      ) {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String targetField =
    isCaller
        ? 'receiverCandidates'
        : 'callerCandidates';

    final _CallParticipantRole localRole =
    isCaller
        ? _CallParticipantRole.caller
        : _CallParticipantRole.receiver;

    return callsCollection
        .doc(
      normalizedCallId,
    )
        .snapshots()
        .map<
        List<Map<String, dynamic>>>(
          (
          DocumentSnapshot<
              Map<String, dynamic>>
          snapshot,
          ) {
        if (!snapshot.exists) {
          return const <
              Map<String, dynamic>>[];
        }

        final Map<String, dynamic>? data =
        snapshot.data();

        if (data == null) {
          return const <
              Map<String, dynamic>>[];
        }

        _requireExpectedParticipantRole(
          data: data,
          authenticatedUid:
          _requireAuthenticatedUid(),
          expectedRole:
          localRole,
        );

        final Object? rawCandidates =
        data[targetField];

        if (rawCandidates is! List) {
          return const <
              Map<String, dynamic>>[];
        }

        final List<Map<String, dynamic>>
        result =
        <Map<String, dynamic>>[];

        final Set<String> signatures =
        <String>{};

        for (final dynamic rawCandidate
        in rawCandidates) {
          final Map<String, dynamic>?
          candidate =
          _normalizeMap(
            rawCandidate,
          );

          if (candidate == null ||
              _readString(
                candidate[
                'candidate'],
              ) ==
                  null) {
            continue;
          }

          final String signature =
          _iceCandidateSignature(
            candidate,
          );

          if (!signatures.add(
            signature,
          )) {
            continue;
          }

          result.add(
            Map<String, dynamic>.unmodifiable(
              candidate,
            ),
          );
        }

        return List<
            Map<String, dynamic>>.unmodifiable(
          result,
        );
      },
    );
  }

  // =============================================================
  // COMPATIBILITY ANSWER LISTENER
  // =============================================================

  StreamSubscription<
      DocumentSnapshot<Map<String, dynamic>>>
  listenToAnswer(
      String callId,
      void Function(Map<String, dynamic>?)
      onAnswer,
      ) {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    String? previousSignature;

    return callsCollection
        .doc(
      normalizedCallId,
    )
        .snapshots()
        .listen(
          (
          DocumentSnapshot<
              Map<String, dynamic>>
          snapshot,
          ) {
        if (!snapshot.exists) {
          return;
        }

        final Map<String, dynamic>? data =
        snapshot.data();

        if (data == null) {
          return;
        }

        _requireParticipant(
          data,
          _requireAuthenticatedUid(),
        );

        final Map<String, dynamic>?
        answer =
        _normalizeMap(
          data['answer'],
        );

        if (answer == null) {
          return;
        }

        final String? sdp =
        _readString(
          answer['sdp'],
        );

        final String? type =
        _readString(
          answer['type'],
        )?.toLowerCase();

        if (sdp == null ||
            type != 'answer') {
          return;
        }

        final int revision =
            _readNonNegativeInt(
              data['answerRevision'],
            ) ??
                0;

        final String signature =
            '$revision::$type::$sdp';

        if (signature ==
            previousSignature) {
          return;
        }

        previousSignature =
            signature;

        onAnswer(
          Map<String, dynamic>.unmodifiable(
            <String, dynamic>{
              'type':
              type,
              'sdp':
              sdp,
            },
          ),
        );
      },
      onError: (
          Object error,
          StackTrace stackTrace,
          ) {
        _reportError(
          'listenToAnswer',
          error,
          stackTrace,
        );
      },
    );
  }

  // =============================================================
  // COMPATIBILITY STATUS LISTENER
  // =============================================================

  StreamSubscription<
      DocumentSnapshot<Map<String, dynamic>>>
  listenToCallStatus(
      String callId,
      void Function(String status)
      onStatusChanged,
      ) {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    String? previousStatus;

    return callsCollection
        .doc(
      normalizedCallId,
    )
        .snapshots()
        .listen(
          (
          DocumentSnapshot<
              Map<String, dynamic>>
          snapshot,
          ) {
        if (!snapshot.exists) {
          if (previousStatus !=
              CallStatus.ended.name) {
            previousStatus =
                CallStatus.ended.name;

            onStatusChanged(
              CallStatus.ended.name,
            );
          }

          return;
        }

        final Map<String, dynamic>? data =
        snapshot.data();

        if (data == null) {
          return;
        }

        _requireParticipant(
          data,
          _requireAuthenticatedUid(),
        );

        final String? status =
        _canonicalStatusOrNull(
          _readString(
            data['status'],
          ) ??
              '',
        );

        if (status == null ||
            status == previousStatus) {
          return;
        }

        previousStatus =
            status;

        onStatusChanged(
          status,
        );
      },
      onError: (
          Object error,
          StackTrace stackTrace,
          ) {
        _reportError(
          'listenToCallStatus',
          error,
          stackTrace,
        );
      },
    );
  }

  // =============================================================
  // BUSY CHECK
  // =============================================================

  Future<bool> checkUserBusyStatus(
      String userId,
      ) async {
    final String normalizedUserId =
    _requireId(
      userId,
      'userId',
    );

    final String currentUid =
    _requireAuthenticatedUid();

    if (normalizedUserId !=
        currentUid) {
      return false;
    }

    final List<bool> results =
    await Future.wait<bool>(
      <Future<bool>>[
        _hasOwnedActiveCall(
          field: 'callerId',
          userId:
          normalizedUserId,
        ),
        _hasOwnedActiveCall(
          field: 'receiverId',
          userId:
          normalizedUserId,
        ),
      ],
    );

    return results.any(
          (bool busy) => busy,
    );
  }

  Future<bool> _hasOwnedActiveCall({
    required String field,
    required String userId,
  }) async {
    final QuerySnapshot<Map<String, dynamic>>
    snapshot =
    await callsCollection
        .where(
      field,
      isEqualTo: userId,
    )
        .where(
      'status',
      whereIn:
      _activeStatuses,
    )
        .limit(
      1,
    )
        .get();

    return snapshot.docs.isNotEmpty;
  }

  Future<bool> checkUserInCallStatus(
      String userId,
      ) {
    return checkUserBusyStatus(
      userId,
    );
  }

  Future<bool> checkCallActiveStatus(
      String callId,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final DocumentSnapshot<Map<String, dynamic>>
    snapshot =
    await callsCollection
        .doc(
      normalizedCallId,
    )
        .get();

    final Map<String, dynamic>? data =
    snapshot.data();

    if (!snapshot.exists ||
        data == null) {
      return false;
    }

    _requireParticipant(
      data,
      _requireAuthenticatedUid(),
    );

    final String? status =
    _canonicalStatusOrNull(
      _readString(
        data['status'],
      ) ??
          '',
    );

    return status != null &&
        _activeStatuses.contains(
          status,
        );
  }

  // =============================================================
  // CALL HISTORY
  // =============================================================

  Future<void> saveCallHistory({
    required String callId,
    required int duration,
    required String status,
    String callType = 'video',
  }) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    if (duration < 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Call duration cannot '
            'be negative.',
      );
    }

    final String normalizedCallType =
    callType.trim().toLowerCase();

    if (normalizedCallType !=
        'voice' &&
        normalizedCallType !=
            'video') {
      throw ArgumentError.value(
        callType,
        'callType',
        'Call type must be '
            'voice or video.',
      );
    }

    _normalizeHistoryStatus(
      status,
    );

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>>
    callReference =
    callsCollection.doc(
      normalizedCallId,
    );

    final DocumentReference<Map<String, dynamic>>
    historyReference =
    callHistoryCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        callSnapshot =
        await transaction.get(
          callReference,
        );

        final Map<String, dynamic>? callData =
        callSnapshot.data();

        if (!callSnapshot.exists ||
            callData == null) {
          throw StateError(
            'Cannot save call history '
                'because the call document '
                'is unavailable.',
          );
        }

        _requireParticipant(
          callData,
          authenticatedUid,
        );

        final String? callerId =
        _readString(
          callData['callerId'],
        );

        final String? receiverId =
        _readString(
          callData['receiverId'],
        );

        if (callerId == null ||
            receiverId == null) {
          throw StateError(
            'Cannot save call history '
                'because participant '
                'identity is invalid.',
          );
        }

        final String? callStatus =
        _canonicalStatusOrNull(
          _readString(
            callData['status'],
          ) ??
              '',
        );

        if (callStatus == null ||
            !_terminalStatuses.contains(
              callStatus,
            )) {
          throw StateError(
            'Cannot save final call history '
                'before the call reaches a '
                'terminal lifecycle state.',
          );
        }

        final DocumentSnapshot<Map<String, dynamic>>
        historySnapshot =
        await transaction.get(
          historyReference,
        );

        if (historySnapshot.exists) {
          return;
        }

        final String authoritativeHistoryStatus =
        _historyStatusFromCallStatus(
          callStatus,
        );

        final bool? actualVideo =
            _readBool(
              callData[
              'isVideoCall'],
            ) ??
                _readBool(
                  callData['video'],
                );

        final String authoritativeCallType =
        actualVideo == null
            ? normalizedCallType
            : actualVideo
            ? 'video'
            : 'voice';

        final Map<String, dynamic> history =
        <String, dynamic>{
          'callId':
          normalizedCallId,
          'sessionId':
          normalizedCallId,
          'callerId':
          callerId,
          'receiverId':
          receiverId,
          'duration':
          duration,
          'status':
          authoritativeHistoryStatus,
          'callType':
          authoritativeCallType,
          'createdAt':
          callData['createdAt'] ??
              callData[
              'serverCreatedAt'] ??
              FieldValue
                  .serverTimestamp(),
          'endedAt':
          callData['endedAt'] ??
              FieldValue
                  .serverTimestamp(),
          'savedAt':
          FieldValue.serverTimestamp(),
        };

        if (callData.containsKey(
          'callerName',
        )) {
          history['callerName'] =
          callData['callerName'];
        }

        if (callData.containsKey(
          'receiverName',
        )) {
          history['receiverName'] =
          callData[
          'receiverName'];
        }

        if (callData.containsKey(
          'callerPhoto',
        )) {
          history['callerPhoto'] =
          callData[
          'callerPhoto'];
        }

        if (callData.containsKey(
          'receiverPhoto',
        )) {
          history['receiverPhoto'] =
          callData[
          'receiverPhoto'];
        }

        transaction.set(
          historyReference,
          history,
        );
      },
    );
  }

  String _normalizeHistoryStatus(
      String status,
      ) {
    final String normalized =
    status.trim().toLowerCase();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        status,
        'status',
        'Call history status '
            'cannot be empty.',
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
      case 'timed' 'out':
      case 'missed':
      case 'missed_call':
      case 'no' 'answer':
      case 'no_answer':
      case 'unanswered':
        return 'missed';

      case 'rejected':
      case 'declined':
        return 'rejected';

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
        return normalized;
    }
  }

  String _historyStatusFromCallStatus(
      String canonicalStatus,
      ) {
    switch (canonicalStatus) {
      case 'ended':
        return 'completed';

      case 'rejected':
        return 'rejected';

      case 'missed':
        return 'missed';

      case 'busy':
        return 'busy';

      case 'cancelled':
        return 'cancelled';

      case 'failed':
        return 'failed';
    }

    throw StateError(
      'Call status "$canonicalStatus" '
          'is not terminal.',
    );
  }

  // =============================================================
  // ICE RESTART METADATA
  // =============================================================

  Future<void> incrementIceRestart(
      String callId,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        snapshot =
        await transaction.get(
          reference,
        );

        final Map<String, dynamic>? data =
        snapshot.data();

        if (!snapshot.exists ||
            data == null) {
          return;
        }

        _requireParticipant(
          data,
          authenticatedUid,
        );

        final String? status =
        _canonicalStatusOrNull(
          _readString(
            data['status'],
          ) ??
              '',
        );

        if (status == null ||
            _terminalStatuses.contains(
              status,
            )) {
          return;
        }

        final int currentCount =
            _readNonNegativeInt(
              data[
              'iceRestartCount'],
            ) ??
                0;

        transaction.update(
          reference,
          <String, dynamic>{
            'iceRestartCount':
            currentCount + 1,
            'iceRestartRequestedBy':
            authenticatedUid,
            'iceRestartRequestedAt':
            FieldValue.serverTimestamp(),
            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );
      },
    );
  }

  // =============================================================
  // NETWORK RECOVERY METADATA
  // =============================================================

  Future<void> markNetworkRecovered(
      String callId,
      bool recovered,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String authenticatedUid =
    _requireAuthenticatedUid();

    final DocumentReference<Map<String, dynamic>>
    reference =
    callsCollection.doc(
      normalizedCallId,
    );

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        snapshot =
        await transaction.get(
          reference,
        );

        final Map<String, dynamic>? data =
        snapshot.data();

        if (!snapshot.exists ||
            data == null) {
          return;
        }

        _requireParticipant(
          data,
          authenticatedUid,
        );

        final String? status =
        _canonicalStatusOrNull(
          _readString(
            data['status'],
          ) ??
              '',
        );

        if (status == null ||
            _terminalStatuses.contains(
              status,
            )) {
          return;
        }

        transaction.update(
          reference,
          <String, dynamic>{
            'networkRecovered':
            recovered,
            'updatedAt':
            FieldValue.serverTimestamp(),
          },
        );
      },
    );
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
    final Map<String, dynamic> update =
    <String, dynamic>{};

    final String? connection =
    _readString(
      connectionState,
    );

    final String? iceConnection =
    _readString(
      iceConnectionState,
    );

    final String? signaling =
    _readString(
      signalingState,
    );

    final String? gathering =
    _readString(
      iceGatheringState,
    );

    if (connection != null) {
      update['connectionState'] =
          connection;
    }

    if (iceConnection != null) {
      update['iceConnectionState'] =
          iceConnection;
    }

    if (signaling != null) {
      update['signalingState'] =
          signaling;
    }

    if (gathering != null) {
      update['iceGatheringState'] =
          gathering;
    }

    if (update.isEmpty) {
      return;
    }

    await updateCall(
      callId: callId,
      data: update,
    );
  }

  // =============================================================
  // PRESENCE COMPATIBILITY
  // =============================================================

  Future<void> updateLastSeen(
      String userId,
      ) async {
    final String normalizedUserId =
    _requireId(
      userId,
      'userId',
    );

    final User? currentUser =
        auth.currentUser;

    if (currentUser == null ||
        currentUser.uid !=
            normalizedUserId) {
      return;
    }

    await firestore
        .collection(
      'users',
    )
        .doc(
      normalizedUserId,
    )
        .set(
      <String, dynamic>{
        'lastSeen':
        FieldValue.serverTimestamp(),
      },
      SetOptions(
        merge: true,
      ),
    );
  }

  StreamSubscription<
      DocumentSnapshot<Map<String, dynamic>>>
  listenConnectionHealth(
      String userId,
      void Function(bool isOnline)
      onHealthChanged,
      ) {
    final String normalizedUserId =
    _requireId(
      userId,
      'userId',
    );

    bool? previousValue;

    return firestore
        .collection(
      'users',
    )
        .doc(
      normalizedUserId,
    )
        .snapshots()
        .listen(
          (
          DocumentSnapshot<
              Map<String, dynamic>>
          snapshot,
          ) {
        final DateTime? lastSeen =
        _timestampToDate(
          snapshot.data()?['lastSeen'],
        );

        final bool online =
            lastSeen != null &&
                DateTime.now()
                    .difference(
                  lastSeen,
                )
                    .inSeconds <
                    45;

        if (online ==
            previousValue) {
          return;
        }

        previousValue =
            online;

        onHealthChanged(
          online,
        );
      },
      onError: (
          Object error,
          StackTrace stackTrace,
          ) {
        _reportError(
          'presence listener',
          error,
          stackTrace,
        );
      },
    );
  }

  // =============================================================
  // STALE CALL CLEANUP
  // =============================================================

  Future<void> deleteExpiredCalls() async {
    final String? userId =
    _clean(
      auth.currentUser?.uid,
    );

    if (userId == null) {
      return;
    }

    final List<
        QueryDocumentSnapshot<
            Map<String, dynamic>>>
    documents =
    await _loadOwnedCallsByStatus(
      userId: userId,
      statuses:
      _stalePendingStatuses,
    );

    final DateTime now =
    DateTime.now();

    for (final QueryDocumentSnapshot<
        Map<String, dynamic>>
    document in documents) {
      final Map<String, dynamic> data =
      document.data();

      final DateTime? createdAt =
      _timestampToDate(
        data['serverCreatedAt'] ??
            data['createdAt'],
      );

      if (createdAt == null ||
          now.difference(
            createdAt,
          ) <=
              const Duration(
                minutes: 2,
              )) {
        continue;
      }

      final String? status =
      _canonicalStatusOrNull(
        _readString(
          data['status'],
        ) ??
            '',
      );

      if (status == null ||
          !_stalePendingStatuses.contains(
            status,
          )) {
        continue;
      }

      final String terminalStatus;

      switch (status) {
        case 'calling':
        case 'ringing':
          terminalStatus =
              CallStatus.missed.name;
          break;

        case 'accepted':
        case 'connecting':
          terminalStatus =
              CallStatus.failed.name;
          break;

        default:
          continue;
      }

      try {
        await updateCallStatus(
          document.id,
          terminalStatus,
        );
      } catch (error, stackTrace) {
        _reportError(
          'stale-call cleanup '
              '${document.id}',
          error,
          stackTrace,
        );
      }
    }
  }

  // =============================================================
  // ENDED CALL CLEANUP
  // =============================================================

  Future<void> cleanupEndedCalls() async {
    final String? userId =
    _clean(
      auth.currentUser?.uid,
    );

    if (userId == null) {
      return;
    }

    final List<
        QueryDocumentSnapshot<
            Map<String, dynamic>>>
    documents =
    await _loadOwnedCallsByStatus(
      userId: userId,
      statuses:
      _terminalStatuses.toList(
        growable: false,
      ),
    );

    final DateTime now =
    DateTime.now();

    for (final QueryDocumentSnapshot<
        Map<String, dynamic>>
    document in documents) {
      final DateTime? endedAt =
      _timestampToDate(
        document.data()['endedAt'],
      );

      if (endedAt == null ||
          now.difference(
            endedAt,
          ) <=
              const Duration(
                hours: 24,
              )) {
        continue;
      }

      try {
        await deleteCall(
          document.id,
        );
      } catch (error, stackTrace) {
        _reportError(
          'ended-call cleanup '
              '${document.id}',
          error,
          stackTrace,
        );
      }
    }
  }

  Future<
      List<
          QueryDocumentSnapshot<
              Map<String, dynamic>>>>
  _loadOwnedCallsByStatus({
    required String userId,
    required List<String> statuses,
  }) async {
    if (statuses.isEmpty) {
      return const <
          QueryDocumentSnapshot<
              Map<String, dynamic>>>[];
    }

    final List<
        QuerySnapshot<
            Map<String, dynamic>>>
    results =
    await Future.wait<
        QuerySnapshot<
            Map<String, dynamic>>>(
      <Future<
          QuerySnapshot<
              Map<String, dynamic>>>>[
        callsCollection
            .where(
          'callerId',
          isEqualTo: userId,
        )
            .where(
          'status',
          whereIn: statuses,
        )
            .get(),
        callsCollection
            .where(
          'receiverId',
          isEqualTo: userId,
        )
            .where(
          'status',
          whereIn: statuses,
        )
            .get(),
      ],
    );

    final Map<
        String,
        QueryDocumentSnapshot<
            Map<String, dynamic>>>
    uniqueDocuments =
    <String,
        QueryDocumentSnapshot<
            Map<String, dynamic>>>{};

    for (final QuerySnapshot<
        Map<String, dynamic>>
    snapshot in results) {
      for (final QueryDocumentSnapshot<
          Map<String, dynamic>>
      document in snapshot.docs) {
        uniqueDocuments[document.id] =
            document;
      }
    }

    return List<
        QueryDocumentSnapshot<
            Map<String, dynamic>>>.unmodifiable(
      uniqueDocuments.values,
    );
  }

  // =============================================================
  // STATUS WRITE AUTHORIZATION
  // =============================================================

  void _requireStatusWriter({
    required Map<String, dynamic> data,
    required String authenticatedUid,
    required CallStatus nextStatus,
  }) {
    switch (nextStatus) {
      case CallStatus.ringing:
      case CallStatus.accepted:
      case CallStatus.rejected:
      case CallStatus.busy:
        _requireExpectedParticipantRole(
          data: data,
          authenticatedUid:
          authenticatedUid,
          expectedRole:
          _CallParticipantRole.receiver,
        );
        return;

      case CallStatus.cancelled:
        _requireExpectedParticipantRole(
          data: data,
          authenticatedUid:
          authenticatedUid,
          expectedRole:
          _CallParticipantRole.caller,
        );
        return;

      case CallStatus.calling:
        throw StateError(
          'A call cannot transition back '
              'to calling.',
        );

      case CallStatus.ended:
      case CallStatus.missed:
      case CallStatus.connecting:
      case CallStatus.connected:
      case CallStatus.reconnecting:
      case CallStatus.failed:
        _requireParticipant(
          data,
          authenticatedUid,
        );
        return;
    }
  }

  Map<String, dynamic> _buildStatusUpdate({
    required Map<String, dynamic> data,
    required String authenticatedUid,
    required CallStatus nextStatus,
  }) {
    final Map<String, dynamic> update =
    <String, dynamic>{
      'status':
      nextStatus.name,
      'updatedAt':
      FieldValue.serverTimestamp(),
    };

    switch (nextStatus) {
      case CallStatus.ringing:
        if (data['ringingAt'] == null) {
          update['ringingAt'] =
              FieldValue.serverTimestamp();
        }
        break;

      case CallStatus.accepted:
        if (data['acceptedAt'] == null) {
          update['acceptedAt'] =
              FieldValue.serverTimestamp();
        }
        break;

      case CallStatus.connected:
        if (data['connectedAt'] == null) {
          update['connectedAt'] =
              FieldValue.serverTimestamp();
        }
        break;

      case CallStatus.rejected:
      case CallStatus.ended:
      case CallStatus.missed:
      case CallStatus.busy:
      case CallStatus.cancelled:
      case CallStatus.failed:
        update['endedAt'] =
            FieldValue.serverTimestamp();

        update['endedBy'] =
            authenticatedUid;
        break;

      case CallStatus.calling:
      case CallStatus.connecting:
      case CallStatus.reconnecting:
        break;
    }

    return update;
  }

  // =============================================================
  // AUTHORIZATION
  // =============================================================

  String _requireAuthenticatedUid() {
    final String? uid =
    _clean(
      auth.currentUser?.uid,
    );

    if (uid == null) {
      throw StateError(
        'Firebase authentication '
            'is required.',
      );
    }

    return uid;
  }

  void _requireParticipant(
      Map<String, dynamic> data,
      String authenticatedUid,
      ) {
    final String? callerId =
    _readString(
      data['callerId'],
    );

    final String? receiverId =
    _readString(
      data['receiverId'],
    );

    if (callerId == null ||
        receiverId == null) {
      throw StateError(
        'Call participant identity '
            'is invalid.',
      );
    }

    if (authenticatedUid != callerId &&
        authenticatedUid != receiverId) {
      throw StateError(
        'Authenticated user is not '
            'a participant of this call.',
      );
    }
  }

  void _requireExpectedParticipantRole({
    required Map<String, dynamic> data,
    required String authenticatedUid,
    required _CallParticipantRole expectedRole,
  }) {
    final String? callerId =
    _readString(
      data['callerId'],
    );

    final String? receiverId =
    _readString(
      data['receiverId'],
    );

    if (callerId == null ||
        receiverId == null) {
      throw StateError(
        'Call participant identity '
            'is invalid.',
      );
    }

    final String expectedUid =
    expectedRole ==
        _CallParticipantRole.caller
        ? callerId
        : receiverId;

    if (authenticatedUid ==
        expectedUid) {
      return;
    }

    if (expectedRole ==
        _CallParticipantRole.caller) {
      throw StateError(
        'Only the authenticated caller '
            'may perform this signaling action.',
      );
    }

    throw StateError(
      'Only the authenticated receiver '
          'may perform this signaling action.',
    );
  }

  String _requireParticipantId(
      Map<String, dynamic> data,
      String field,
      ) {
    final String? value =
    _readString(
      data[field],
    );

    if (value == null) {
      throw StateError(
        'Call participant identity '
            '"$field" is invalid.',
      );
    }

    return value;
  }

  // =============================================================
  // STATUS HELPERS
  // =============================================================

  String? _canonicalStatusOrNull(
      String value,
      ) {
    final String normalized =
    value.trim().toLowerCase();

    if (normalized.isEmpty) {
      return null;
    }

    switch (normalized) {
      case 'declined':
        return CallStatus.rejected.name;

      case 'timeout':
      case 'timed' 'out':
      case 'no' 'answer':
      case 'no_answer':
      case 'unanswered':
        return CallStatus.missed.name;

      case 'canceled':
        return CallStatus.cancelled.name;
    }

    return _validStatuses.contains(
      normalized,
    )
        ? normalized
        : null;
  }

  CallStatus _callStatusFromCanonical(
      String value,
      ) {
    for (final CallStatus status
    in CallStatus.values) {
      if (status.name == value) {
        return status;
      }
    }

    throw StateError(
      'Unsupported canonical '
          'CallStatus "$value".',
    );
  }

  // =============================================================
  // DATA HELPERS
  // =============================================================

  String _requireId(
      String value,
      String parameterName,
      ) {
    final String normalized =
    value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        parameterName,
        '$parameterName cannot be empty.',
      );
    }

    return normalized;
  }

  String _requireDocumentId(
      String value,
      String parameterName,
      ) {
    final String normalized =
    _requireId(
      value,
      parameterName,
    );

    if (normalized.contains('/')) {
      throw ArgumentError.value(
        value,
        parameterName,
        '$parameterName must be a '
            'single Firestore document ID.',
      );
    }

    return normalized;
  }

  String? _clean(
      String? value,
      ) {
    final String normalized =
        value?.trim() ?? '';

    return normalized.isEmpty
        ? null
        : normalized;
  }

  String? _readString(
      Object? value,
      ) {
    if (value is! String) {
      return null;
    }

    return _clean(
      value,
    );
  }

  bool? _readBool(
      Object? value,
      ) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      if (value == 1) {
        return true;
      }

      if (value == 0) {
        return false;
      }

      return null;
    }

    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
          return true;

        case 'false':
        case '0':
        case 'no':
          return false;
      }
    }

    return null;
  }

  int? _readNonNegativeInt(
      Object? value,
      ) {
    int? result;

    if (value is int) {
      result = value;
    } else if (value is num &&
        value.isFinite) {
      result = value.toInt();
    } else if (value is String) {
      result =
          int.tryParse(
            value.trim(),
          );
    }

    if (result == null ||
        result < 0) {
      return null;
    }

    return result;
  }

  Map<String, dynamic>? _normalizeMap(
      Object? value,
      ) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    if (value is Map) {
      final Map<String, dynamic> result =
      <String, dynamic>{};

      for (final MapEntry<dynamic, dynamic>
      entry in value.entries) {
        if (entry.key is! String) {
          return null;
        }

        result[entry.key as String] =
            entry.value;
      }

      return result;
    }

    return null;
  }

  Map<String, dynamic> _normalizeIceCandidate(
      Map<String, dynamic> candidate,
      ) {
    final String? candidateValue =
    _readString(
      candidate['candidate'],
    );

    if (candidateValue == null) {
      throw ArgumentError(
        'ICE candidate string '
            'cannot be empty.',
      );
    }

    if (candidateValue.length >
        8192) {
      throw ArgumentError(
        'ICE candidate string is too large.',
      );
    }

    final String? sdpMid =
    _readString(
      candidate['sdpMid'],
    );

    if (sdpMid != null &&
        sdpMid.length > 256) {
      throw ArgumentError(
        'ICE sdpMid is too large.',
      );
    }

    final String? usernameFragment =
    _readString(
      candidate['usernameFragment'],
    );

    if (usernameFragment != null &&
        usernameFragment.length >
            256) {
      throw ArgumentError(
        'ICE usernameFragment '
            'is too large.',
      );
    }

    final Object? rawLineIndex =
    candidate['sdpMLineIndex'];

    int? lineIndex;

    if (rawLineIndex is int) {
      lineIndex =
          rawLineIndex;
    } else if (rawLineIndex is num &&
        rawLineIndex.isFinite) {
      lineIndex =
          rawLineIndex.toInt();
    } else if (rawLineIndex is String) {
      lineIndex =
          int.tryParse(
            rawLineIndex.trim(),
          );
    }

    if (lineIndex != null &&
        (lineIndex < 0 ||
            lineIndex > 65535)) {
      lineIndex = null;
    }

    final Map<String, dynamic> result =
    <String, dynamic>{
      'candidate':
      candidateValue,
      'sdpMid':
      sdpMid,
      'sdpMLineIndex':
      lineIndex,
    };

    if (usernameFragment != null) {
      result['usernameFragment'] =
          usernameFragment;
    }

    return result;
  }

  DateTime? _timestampToDate(
      Object? value,
      ) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is num) {
      final int raw =
      value.toInt();

      try {
        if (raw.abs() <
            100000000000) {
          return DateTime
              .fromMillisecondsSinceEpoch(
            raw * 1000,
          );
        }

        if (raw.abs() >=
            100000000000000) {
          return DateTime
              .fromMicrosecondsSinceEpoch(
            raw,
          );
        }

        return DateTime
            .fromMillisecondsSinceEpoch(
          raw,
        );
      } on RangeError {
        return null;
      } on ArgumentError {
        return null;
      }
    }

    if (value is String) {
      return DateTime.tryParse(
        value.trim(),
      );
    }

    return null;
  }

  // =============================================================
  // LOGGING
  // =============================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[SignalingService/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[SignalingService/$source]',
        stackTrace:
        stackTrace,
      );
    }
  }
}

// ===============================================================
// PARTICIPANT ROLE
// ===============================================================

enum _CallParticipantRole {
  caller,
  receiver,
}

// ===============================================================
// END OF FILE
// STATUS: FILE 09 CORRECTED VERIFICATION VERSION
//
// NEXT PURE CALL ENGINE FILE:
// FILE 10
// lib/services/managers/ice_manager.dart
// ===============================================================