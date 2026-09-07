// ===============================================================
// JR CALL
// File: call_repository.dart
// Location: lib/services/call/call_repository.dart
//
// FINAL PRODUCTION CONTRACT:
// - Firebase UID is the only Call Engine identity.
// - Public identities remain Search/Discovery-owned.
// - Existing repository APIs are preserved.
// - FILE 01 CallStatus is the canonical lifecycle vocabulary.
// - Legacy status aliases remain readable/input-compatible.
// - New calls always begin in canonical `calling` state.
// - Call creation is transactionally idempotent by callId.
// - Authenticated caller ownership and self-call guards enforced.
// - No fake connected/history state.
// - No WebRTC / ICE / SDP transport ownership.
// - Signaling lifecycle mutations remain SignalingService-owned.
// ===============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/call_status.dart';
import '../../models/call_model.dart';
import '../user_discovery_service.dart';
import 'signaling_service.dart';

class CallRepository {
  CallRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    UserDiscoveryService? discoveryService,
    SignalingService? signalingService,
  }) : firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _discoveryService =
            discoveryService ?? UserDiscoveryService.instance,
        _signalingService =
            signalingService ?? SignalingService.instance;

  // =============================================================
  // SERVICES
  // =============================================================

  /// Existing public field preserved.
  final FirebaseFirestore firestore;

  final FirebaseAuth _auth;
  final UserDiscoveryService _discoveryService;
  final SignalingService _signalingService;

  // =============================================================
  // COLLECTION
  // =============================================================

  static const String callsCollection = 'calls';

  CollectionReference<Map<String, dynamic>> get _calls {
    return firestore.collection(callsCollection);
  }

  // =============================================================
  // LEGACY / COMPATIBILITY CALL CREATION
  // =============================================================

  /// Existing public API preserved.
  ///
  /// Preferred production orchestration remains:
  ///
  /// CallService
  /// -> CallRepository / SignalingService
  /// -> WebRTC coordinator
  ///
  /// This repository owns persistence safety only.
  Future<void> createCall(CallModel call) async {
    final String callId = _requireDocumentId(
      call.callId,
      'call.callId',
    );

    final String callerId = _requireId(
      call.callerId,
      'call.callerId',
    );

    final String receiverId = _requireId(
      call.receiverId,
      'call.receiverId',
    );

    if (callerId == receiverId) {
      throw ArgumentError(
        'JR CALL cannot call the same Firebase user.',
      );
    }

    final User currentUser = _requireAuthenticatedUser();

    if (currentUser.uid != callerId) {
      throw StateError(
        'Authenticated Firebase UID does not match '
            'CallModel.callerId.',
      );
    }

    if (call.status != CallStatus.calling) {
      throw StateError(
        'A new JR CALL call must begin with status "calling". '
            'Received "${call.status.name}".',
      );
    }

    final DocumentReference<Map<String, dynamic>> reference =
    _calls.doc(callId);

    final Map<String, dynamic> data = Map<String, dynamic>.from(
      call.toMap(),
    );

    data.remove('ringingAt');
    data.remove('acceptedAt');
    data.remove('connectedAt');
    data.remove('endedAt');
    data.remove('endedBy');
    data.remove('answeredByDeviceId');
    data.remove('failureReason');

    await firestore.runTransaction<void>(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>> existing =
        await transaction.get(reference);

        if (existing.exists) {
          final Map<String, dynamic> existingData =
              existing.data() ?? const <String, dynamic>{};

          final String? existingCallerId = _readString(
            existingData['callerId'] ??
                existingData['callerUid'],
          );

          final String? existingReceiverId = _readString(
            existingData['receiverId'] ??
                existingData['receiverUid'] ??
                existingData['calleeUid'],
          );

          final bool? existingVideo =
              _readBool(
                existingData['isVideoCall'],
              ) ??
                  _readBool(
                    existingData['video'],
                  );

          if (existingCallerId == callerId &&
              existingReceiverId == receiverId &&
              (existingVideo == null ||
                  existingVideo == call.video)) {
            return;
          }

          throw StateError(
            'A different JR CALL session already exists '
                'with callId "$callId".',
          );
        }

        transaction.set(
          reference,
          <String, dynamic>{
            ...data,
            'callId': callId,
            'callerId': callerId,
            'receiverId': receiverId,
            'video': call.video,
            'isVideoCall': call.video,
            'status': CallStatus.calling.name,
            'revision': 0,
            'schemaVersion':
            call.schemaVersion > 0
                ? call.schemaVersion
                : 1,
            'createdAt': Timestamp.fromDate(
              call.createdAt,
            ),
            'serverCreatedAt':
            FieldValue.serverTimestamp(),
            'updatedAt':
            FieldValue.serverTimestamp(),
            'offer': null,
            'answer': null,
            'callerCandidates':
            <Map<String, dynamic>>[],
            'receiverCandidates':
            <Map<String, dynamic>>[],
            'connectionState': 'new',
            'iceConnectionState': 'new',
            'signalingState': 'stable',
            'iceGatheringState': 'new',
            'networkRecovered': false,
            'iceRestartCount': 0,
          },
        );
      },
    );
  }

  // =============================================================
  // STATUS UPDATE
  // =============================================================

  Future<void> updateStatus(
      String callId,
      String status,
      ) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    final String? canonicalStatus =
    _canonicalStatusOrNull(status);

    if (canonicalStatus == null) {
      throw ArgumentError.value(
        status,
        'status',
        'Unsupported JR CALL call status.',
      );
    }

    await _signalingService.updateCallStatus(
      normalizedCallId,
      canonicalStatus,
    );
  }

  // =============================================================
  // LEGACY END CALL
  // =============================================================

  Future<void> endCall(String callId) async {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    await _signalingService.deleteCall(
      normalizedCallId,
    );
  }

  // =============================================================
  // CALL LISTENER
  // =============================================================

  Stream<DocumentSnapshot<Map<String, dynamic>>> listenCall(
      String callId,
      ) {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    return _signalingService.listenCall(
      normalizedCallId,
    );
  }

  // =============================================================
  // PUBLIC IDENTITY -> FIREBASE UID
  // =============================================================

  Future<String?> resolveTargetUid(
      String publicIdentity, {
        DiscoverySearchType type =
            DiscoverySearchType.automatic,
      }) async {
    final String value =
    publicIdentity.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryPage page =
    await _discoveryService.search(
      value,
      type: type,
      limit: 2,
      excludeCurrentUser: false,
    );

    if (page.users.length != 1 ||
        page.hasMore) {
      return null;
    }

    return _validatedResolvedUid(
      page.users.first.uid,
    );
  }

  // =============================================================
  // JR CALL ID
  // =============================================================

  Future<String?> resolveJrCallIdToUid(
      String jrCallUserId,
      ) async {
    final String value =
    jrCallUserId.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryUser? user =
    await _discoveryService.searchByJrCallId(
      value,
      excludeCurrentUser: false,
    );

    return _validatedResolvedUid(
      user?.uid,
    );
  }

  // =============================================================
  // USERNAME
  // =============================================================

  Future<String?> resolveUsernameToUid(
      String username,
      ) async {
    final String value =
    username.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryUser? user =
    await _discoveryService.searchByUsername(
      value,
      excludeCurrentUser: false,
    );

    return _validatedResolvedUid(
      user?.uid,
    );
  }

  // =============================================================
  // EMAIL
  // =============================================================

  Future<String?> resolveEmailToUid(
      String email,
      ) async {
    final String value = email.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryUser? user =
    await _discoveryService.searchByEmail(
      value,
      excludeCurrentUser: false,
    );

    return _validatedResolvedUid(
      user?.uid,
    );
  }

  // =============================================================
  // PHONE
  // =============================================================

  Future<String?> resolvePhoneToUid(
      String phoneNumber,
      ) async {
    final String value =
    phoneNumber.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryUser? user =
    await _discoveryService.searchByPhone(
      value,
      excludeCurrentUser: false,
    );

    return _validatedResolvedUid(
      user?.uid,
    );
  }

  // =============================================================
  // NAME
  // =============================================================

  Future<String?> resolveNameToUid(
      String fullName,
      ) async {
    final String value =
    fullName.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryPage page =
    await _discoveryService.searchByName(
      value,
      limit: 2,
      excludeCurrentUser: false,
    );

    if (page.users.length != 1 ||
        page.hasMore) {
      return null;
    }

    return _validatedResolvedUid(
      page.users.first.uid,
    );
  }

  // =============================================================
  // SELECTED DISCOVERY USER
  // =============================================================

  String? uidFromDiscoveryUser(
      DiscoveryUser user,
      ) {
    return _validatedResolvedUid(
      user.uid,
    );
  }

  // =============================================================
  // REQUIRED UID RESOLUTION
  // =============================================================

  Future<String> requireTargetUid(
      String publicIdentity, {
        DiscoverySearchType type =
            DiscoverySearchType.automatic,
      }) async {
    final String? uid =
    await resolveTargetUid(
      publicIdentity,
      type: type,
    );

    if (uid == null) {
      throw StateError(
        'JR CALL target could not be uniquely resolved '
            'to a Firebase UID.',
      );
    }

    return uid;
  }

  // =============================================================
  // SAFE READ
  // =============================================================

  Future<DocumentSnapshot<Map<String, dynamic>>> getCall(
      String callId,
      ) {
    final String normalizedCallId =
    _requireDocumentId(
      callId,
      'callId',
    );

    return _calls
        .doc(normalizedCallId)
        .get();
  }

  Future<bool> callExists(
      String callId,
      ) async {
    final String normalizedCallId =
    callId.trim();

    if (normalizedCallId.isEmpty ||
        normalizedCallId.contains('/')) {
      return false;
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
    await _calls
        .doc(normalizedCallId)
        .get();

    return snapshot.exists;
  }

  // =============================================================
  // CALL MODEL READ
  // =============================================================

  Future<CallModel?> getCallModel(
      String callId,
      ) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
    await getCall(callId);

    if (!snapshot.exists) {
      return null;
    }

    final Map<String, dynamic>? data =
    snapshot.data();

    if (data == null) {
      return null;
    }

    final Map<String, dynamic> normalizedData =
    Map<String, dynamic>.from(data);

    normalizedData['callId'] =
        _readString(
          normalizedData['callId'],
        ) ??
            snapshot.id;

    normalizedData['callerId'] ??=
    normalizedData['callerUid'];

    normalizedData['receiverId'] ??=
        normalizedData['receiverUid'] ??
            normalizedData['calleeUid'];

    if (normalizedData['video'] is! bool) {
      final bool? video =
      _readBool(
        normalizedData['isVideoCall'],
      );

      if (video != null) {
        normalizedData['video'] = video;
      }
    }

    final Object? rawStatus =
    normalizedData['status'];

    if (rawStatus is String) {
      final String? canonical =
      _canonicalStatusOrNull(
        rawStatus,
      );

      if (canonical != null) {
        normalizedData['status'] =
            canonical;
      }
    }

    normalizedData['createdAt'] ??=
    normalizedData['serverCreatedAt'];

    return CallModel.fromMap(
      normalizedData,
      documentId: snapshot.id,
    );
  }

  // =============================================================
  // CURRENT USER GUARDS
  // =============================================================

  bool isCurrentUser(String uid) {
    final String normalizedUid =
    uid.trim();

    if (normalizedUid.isEmpty) {
      return false;
    }

    return _auth.currentUser?.uid ==
        normalizedUid;
  }

  bool isValidCallTargetUid(String uid) {
    final String normalizedUid =
    uid.trim();

    if (normalizedUid.isEmpty) {
      return false;
    }

    final User? currentUser =
        _auth.currentUser;

    if (currentUser == null ||
        currentUser.uid.trim().isEmpty) {
      return false;
    }

    return currentUser.uid !=
        normalizedUid;
  }

  String requireValidCallTargetUid(
      String uid,
      ) {
    final String normalizedUid =
    _requireId(
      uid,
      'uid',
    );

    final User currentUser =
    _requireAuthenticatedUser();

    if (currentUser.uid ==
        normalizedUid) {
      throw StateError(
        'JR CALL cannot call the authenticated user.',
      );
    }

    return normalizedUid;
  }

  // =============================================================
  // STATUS CONTRACT
  // =============================================================

  static const Set<String> _supportedCallStatuses =
  <String>{
    CallRepositoryStatus.calling,
    CallRepositoryStatus.ringing,
    CallRepositoryStatus.accepted,
    CallRepositoryStatus.rejected,
    CallRepositoryStatus.ended,
    CallRepositoryStatus.missed,
    CallRepositoryStatus.connecting,
    CallRepositoryStatus.connected,
    CallRepositoryStatus.reconnecting,
    CallRepositoryStatus.busy,
    CallRepositoryStatus.cancelled,
    CallRepositoryStatus.failed,

    // Legacy aliases accepted on input only.
    CallRepositoryStatus.declined,
    CallRepositoryStatus.timeout,
    'timed' 'out',
    'no' 'answer',
    'unanswered',
  };

  bool _isSupportedCallStatus(
      String status,
      ) {
    return _supportedCallStatuses.contains(
      status.trim().toLowerCase(),
    );
  }

  String? _canonicalStatusOrNull(
      String value,
      ) {
    final String normalized =
    value.trim().toLowerCase();

    if (normalized.isEmpty ||
        !_isSupportedCallStatus(normalized)) {
      return null;
    }

    switch (normalized) {
      case CallRepositoryStatus.declined:
        return CallStatus.rejected.name;

      case CallRepositoryStatus.timeout:
      case 'timed' 'out':
      case 'no' 'answer':
      case 'unanswered':
        return CallStatus.missed.name;
    }

    for (final CallStatus status
    in CallStatus.values) {
      if (status.name == normalized) {
        return status.name;
      }
    }

    return null;
  }

  // =============================================================
  // INTERNAL VALIDATION
  // =============================================================

  User _requireAuthenticatedUser() {
    final User? user =
        _auth.currentUser;

    if (user == null ||
        user.uid.trim().isEmpty) {
      throw StateError(
        'Authentication is required for JR CALL.',
      );
    }

    return user;
  }

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
        '$parameterName must be a single Firestore document ID.',
      );
    }

    return normalized;
  }

  String? _validatedResolvedUid(
      String? uid,
      ) {
    final String normalized =
        uid?.trim() ?? '';

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  String? _readString(
      Object? value,
      ) {
    if (value is! String) {
      return null;
    }

    final String normalized =
    value.trim();

    return normalized.isEmpty
        ? null
        : normalized;
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
}

// ===============================================================
// REPOSITORY STATUS COMPATIBILITY CONSTANTS
// ===============================================================

abstract final class CallRepositoryStatus {
  static const String calling = 'calling';
  static const String ringing = 'ringing';
  static const String accepted = 'accepted';
  static const String rejected = 'rejected';
  static const String ended = 'ended';
  static const String missed = 'missed';
  static const String connecting = 'connecting';
  static const String connected = 'connected';
  static const String reconnecting = 'reconnecting';
  static const String busy = 'busy';
  static const String cancelled = 'cancelled';
  static const String failed = 'failed';

  static const String declined = 'declined';
  static const String timeout = 'timeout';
}

// ===============================================================
// END OF FILE
// STATUS: FILE 06 CORRECTED VERIFICATION VERSION
// NEXT: lib/services/call/call_security.dart
// ===============================================================