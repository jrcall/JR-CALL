// ===============================================================
// JR CALL
// File: call_repository.dart
// Location: lib/services/call/call_repository.dart
// Fixes: BUG 03, BUG 04, BUG 07, BUG 08
// Production-safe replacement
// Existing APIs preserved
//
// PRODUCTION CONTRACT:
// - Firebase UID is the only Call Engine identity.
// - Public JR CALL identity is resolved before CallService.
// - Ambiguous names never silently resolve to a random user.
// - Legacy createCall(CallModel) remains compatible.
// - Firestore call creation matches current security rules.
// - New calls are created only with canonical `calling` status.
// - Caller ownership and self-call guards enforced.
// - No fake call/history/connected state.
// - No duplicate WebRTC/ICE/signaling ownership.
// - Signaling lifecycle operations remain in SignalingService.
// ===============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
       _discoveryService = discoveryService ?? UserDiscoveryService.instance,
       _signalingService = signalingService ?? SignalingService.instance;

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

  CollectionReference<Map<String, dynamic>> get _calls =>
      firestore.collection(callsCollection);

  // =============================================================
  // LEGACY CALL CREATION
  // =============================================================

  /// Compatibility API.
  ///
  /// Production call creation should normally be:
  ///
  /// CallService.startCall()
  /// -> SignalingService.createCall()
  ///
  /// This method remains for existing callers.
  ///
  /// Current Firestore rules permit CREATE only when:
  /// status == calling
  /// callerId == authenticated Firebase UID
  /// receiverId != callerId
  /// isVideoCall is bool
  Future<void> createCall(CallModel call) async {
    final String callId = _requireId(call.callId, 'call.callId');

    final String callerId = _requireId(call.callerId, 'call.callerId');

    final String receiverId = _requireId(call.receiverId, 'call.receiverId');

    if (callerId == receiverId) {
      throw ArgumentError('JR CALL cannot call the same Firebase user.');
    }

    final User currentUser = _requireAuthenticatedUser();

    if (currentUser.uid != callerId) {
      throw StateError(
        'Authenticated Firebase UID does not match '
        'CallModel.callerId.',
      );
    }

    final String suppliedStatus = call.status.name.trim().toLowerCase();

    if (!_isSupportedCallStatus(suppliedStatus)) {
      throw ArgumentError.value(
        suppliedStatus,
        'call.status',
        'Unsupported JR CALL call status.',
      );
    }

    // Current Firestore CREATE rules explicitly require
    // status == "calling".
    //
    // Do not silently change another lifecycle state into calling.
    // Doing so could manufacture incorrect call state.
    if (suppliedStatus != CallRepositoryStatus.calling) {
      throw StateError(
        'A new JR CALL call must begin with status "calling". '
        'Received "$suppliedStatus".',
      );
    }

    final DocumentReference<Map<String, dynamic>> reference = _calls.doc(
      callId,
    );

    final Map<String, dynamic> legacyData = Map<String, dynamic>.from(
      call.toMap(),
    );

    await firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> existing = await transaction
          .get(reference);

      if (existing.exists) {
        final Map<String, dynamic> data =
            existing.data() ?? const <String, dynamic>{};

        final String? existingCallerId = _readString(data['callerId']);

        final String? existingReceiverId = _readString(data['receiverId']);

        final bool? existingVideo =
            _readBool(data['isVideoCall']) ?? _readBool(data['video']);

        // Exact retry of the same call creation is idempotent.
        if (existingCallerId == callerId &&
            existingReceiverId == receiverId &&
            (existingVideo == null || existingVideo == call.video)) {
          return;
        }

        throw StateError(
          'A different JR CALL session already exists '
          'with callId "$callId".',
        );
      }

      transaction.set(reference, <String, dynamic>{
        ...legacyData,

        // ---------------------------------------------------
        // Canonical identity
        // ---------------------------------------------------
        'callId': callId,
        'callerId': callerId,
        'receiverId': receiverId,

        // ---------------------------------------------------
        // Call type compatibility
        // ---------------------------------------------------
        'video': call.video,
        'isVideoCall': call.video,

        // ---------------------------------------------------
        // Canonical initial lifecycle
        // ---------------------------------------------------
        'status': CallRepositoryStatus.calling,

        // ---------------------------------------------------
        // Timestamps
        // ---------------------------------------------------
        'createdAt': Timestamp.fromDate(call.createdAt),
        'updatedAt': FieldValue.serverTimestamp(),

        // ---------------------------------------------------
        // Signaling
        // ---------------------------------------------------
        'offer': null,
        'answer': null,

        // ---------------------------------------------------
        // ICE
        // ---------------------------------------------------
        'callerCandidates': <Map<String, dynamic>>[],
        'receiverCandidates': <Map<String, dynamic>>[],

        // ---------------------------------------------------
        // Connection state
        // ---------------------------------------------------
        'connectionState': 'new',
        'iceConnectionState': 'new',
        'signalingState': 'stable',
        'iceGatheringState': 'new',

        // ---------------------------------------------------
        // Recovery
        // ---------------------------------------------------
        'networkRecovered': false,
        'iceRestartCount': 0,
      });
    });
  }

  // =============================================================
  // STATUS UPDATE
  // =============================================================

  /// Existing public API preserved.
  ///
  /// Lifecycle mutation stays owned by SignalingService.
  Future<void> updateStatus(String callId, String status) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    final String normalizedStatus = status.trim().toLowerCase();

    if (!_isSupportedCallStatus(normalizedStatus)) {
      throw ArgumentError.value(
        status,
        'status',
        'Unsupported JR CALL call status.',
      );
    }

    await _signalingService.updateCallStatus(
      normalizedCallId,
      normalizedStatus,
    );
  }

  // =============================================================
  // LEGACY END CALL
  // =============================================================

  /// Existing API preserved.
  ///
  /// IMPORTANT:
  /// Normal production completion must use CallService.endCall()
  /// because CallService coordinates:
  /// - final status
  /// - duration
  /// - call history
  /// - WebRTC cleanup
  /// - ICE cleanup
  /// - recovery cleanup
  ///
  /// Historical repository behavior deletes the signaling
  /// document, therefore this compatibility method continues
  /// delegating deletion to SignalingService.
  Future<void> endCall(String callId) async {
    final String normalizedCallId = _requireId(callId, 'callId');

    await _signalingService.deleteCall(normalizedCallId);
  }

  // =============================================================
  // CALL LISTENER
  // =============================================================

  /// Existing API preserved.
  Stream<DocumentSnapshot<Map<String, dynamic>>> listenCall(String callId) {
    final String normalizedCallId = _requireId(callId, 'callId');

    return _signalingService.listenCall(normalizedCallId);
  }

  // =============================================================
  // PUBLIC IDENTITY -> FIREBASE UID
  // =============================================================

  /// Resolves public identity to one canonical Firebase UID.
  ///
  /// Supported by UserDiscoveryService:
  /// - JR CALL ID
  /// - username
  /// - discoverable email
  /// - discoverable phone
  /// - name
  /// - automatic detection
  ///
  /// Ambiguous results deliberately return null.
  Future<String?> resolveTargetUid(
    String publicIdentity, {
    DiscoverySearchType type = DiscoverySearchType.automatic,
  }) async {
    final String value = publicIdentity.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryPage page = await _discoveryService.search(
      value,
      type: type,

      // Two records are sufficient to prove ambiguity.
      limit: 2,

      // Self-call rejection is also enforced later at
      // CallService boundary.
      excludeCurrentUser: false,
    );

    if (page.users.length != 1 || page.hasMore) {
      return null;
    }

    return _validatedResolvedUid(page.users.first.uid);
  }

  // =============================================================
  // JR CALL ID
  // =============================================================

  Future<String?> resolveJrCallIdToUid(String jrCallUserId) async {
    final String value = jrCallUserId.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryUser? user = await _discoveryService.searchByJrCallId(
      value,
      excludeCurrentUser: false,
    );

    return _validatedResolvedUid(user?.uid);
  }

  // =============================================================
  // USERNAME
  // =============================================================

  Future<String?> resolveUsernameToUid(String username) async {
    final String value = username.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryUser? user = await _discoveryService.searchByUsername(
      value,
      excludeCurrentUser: false,
    );

    return _validatedResolvedUid(user?.uid);
  }

  // =============================================================
  // EMAIL
  // =============================================================

  Future<String?> resolveEmailToUid(String email) async {
    final String value = email.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryUser? user = await _discoveryService.searchByEmail(
      value,
      excludeCurrentUser: false,
    );

    return _validatedResolvedUid(user?.uid);
  }

  // =============================================================
  // PHONE
  // =============================================================

  Future<String?> resolvePhoneToUid(String phoneNumber) async {
    final String value = phoneNumber.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryUser? user = await _discoveryService.searchByPhone(
      value,
      excludeCurrentUser: false,
    );

    return _validatedResolvedUid(user?.uid);
  }

  // =============================================================
  // NAME
  // =============================================================

  /// Name resolution is permitted only when exactly one
  /// discoverable result exists.
  Future<String?> resolveNameToUid(String fullName) async {
    final String value = fullName.trim();

    if (value.isEmpty) {
      return null;
    }

    final DiscoveryPage page = await _discoveryService.searchByName(
      value,
      limit: 2,
      excludeCurrentUser: false,
    );

    if (page.users.length != 1 || page.hasMore) {
      return null;
    }

    return _validatedResolvedUid(page.users.first.uid);
  }

  // =============================================================
  // SELECTED DISCOVERY USER
  // =============================================================

  /// Once the UI user explicitly selected a DiscoveryUser,
  /// no second name/public-ID lookup is needed.
  ///
  /// The resolved Firebase UID from that selected result is the
  /// correct Call Engine identity.
  String? uidFromDiscoveryUser(DiscoveryUser user) {
    return _validatedResolvedUid(user.uid);
  }

  // =============================================================
  // REQUIRED UID RESOLUTION
  // =============================================================

  Future<String> requireTargetUid(
    String publicIdentity, {
    DiscoverySearchType type = DiscoverySearchType.automatic,
  }) async {
    final String? uid = await resolveTargetUid(publicIdentity, type: type);

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

  /// Existing public API preserved.
  Future<DocumentSnapshot<Map<String, dynamic>>> getCall(String callId) {
    final String normalizedCallId = _requireId(callId, 'callId');

    return _calls.doc(normalizedCallId).get();
  }

  /// Existing public API preserved.
  Future<bool> callExists(String callId) async {
    final String normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      return false;
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _calls
        .doc(normalizedCallId)
        .get();

    return snapshot.exists;
  }

  // =============================================================
  // CALL MODEL READ
  // =============================================================

  Future<CallModel?> getCallModel(String callId) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await getCall(
      callId,
    );

    if (!snapshot.exists) {
      return null;
    }

    final Map<String, dynamic>? data = snapshot.data();

    if (data == null) {
      return null;
    }

    final Map<String, dynamic> normalizedData = Map<String, dynamic>.from(data);

    normalizedData['callId'] =
        _readString(normalizedData['callId']) ?? snapshot.id;

    // Current CallModel uses "video".
    // SignalingService uses "isVideoCall".
    if (normalizedData['video'] is! bool) {
      final bool? video = _readBool(normalizedData['isVideoCall']);

      if (video != null) {
        normalizedData['video'] = video;
      }
    }

    return CallModel.fromMap(normalizedData);
  }

  // =============================================================
  // CURRENT USER GUARDS
  // =============================================================

  bool isCurrentUser(String uid) {
    final String normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return false;
    }

    return _auth.currentUser?.uid == normalizedUid;
  }

  /// A target is valid only when:
  /// - target UID exists
  /// - authenticated user exists
  /// - target is not current user
  bool isValidCallTargetUid(String uid) {
    final String normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return false;
    }

    final User? currentUser = _auth.currentUser;

    if (currentUser == null) {
      return false;
    }

    return currentUser.uid != normalizedUid;
  }

  // =============================================================
  // AUTHENTICATED CALL TARGET
  // =============================================================

  /// Backward-compatible helper added for production call
  /// boundaries.
  ///
  /// Does not change existing APIs.
  ///
  /// Throws instead of allowing an unauthenticated/self target to
  /// enter the Call Engine.
  String requireValidCallTargetUid(String uid) {
    final String normalizedUid = _requireId(uid, 'uid');

    final User currentUser = _requireAuthenticatedUser();

    if (currentUser.uid == normalizedUid) {
      throw StateError('JR CALL cannot call the authenticated user.');
    }

    return normalizedUid;
  }

  // =============================================================
  // STATUS CONTRACT
  // =============================================================

  static const Set<String> _supportedCallStatuses = <String>{
    CallRepositoryStatus.calling,
    CallRepositoryStatus.ringing,
    CallRepositoryStatus.connecting,
    CallRepositoryStatus.connected,
    CallRepositoryStatus.reconnecting,
    CallRepositoryStatus.ended,
    CallRepositoryStatus.rejected,
    CallRepositoryStatus.declined,
    CallRepositoryStatus.cancelled,
    CallRepositoryStatus.failed,
    CallRepositoryStatus.timeout,
  };

  bool _isSupportedCallStatus(String status) {
    return _supportedCallStatuses.contains(status.trim().toLowerCase());
  }

  // =============================================================
  // INTERNAL VALIDATION
  // =============================================================

  User _requireAuthenticatedUser() {
    final User? user = _auth.currentUser;

    if (user == null || user.uid.trim().isEmpty) {
      throw StateError('Authentication is required for JR CALL.');
    }

    return user;
  }

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

  String? _validatedResolvedUid(String? uid) {
    final String normalized = uid?.trim() ?? '';

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  bool? _readBool(Object? value) {
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
// INTERNAL REPOSITORY STATUS CONSTANTS
//
// Kept private to this repository architecture except for the
// class itself; no Call Engine status API is replaced.
// ===============================================================

abstract final class CallRepositoryStatus {
  static const String calling = 'calling';
  static const String ringing = 'ringing';
  static const String connecting = 'connecting';
  static const String connected = 'connected';
  static const String reconnecting = 'reconnecting';

  static const String ended = 'ended';
  static const String rejected = 'rejected';
  static const String declined = 'declined';
  static const String cancelled = 'cancelled';
  static const String failed = 'failed';
  static const String timeout = 'timeout';
}

// ===============================================================
// END OF FILE
//
// FIXED:
// - BUG 03: resolved Firebase UID boundary hardened
// - BUG 04: history/lifecycle identity compatibility protected
// - BUG 07: voice-call target/session creation boundary hardened
// - BUG 08: video-call target/type creation boundary hardened
// - Firestore CREATE status/rules mismatch corrected
// - Self-call / unauthenticated call protection hardened
// - Ambiguous public-name calling prevented
// - Duplicate compatible creation remains idempotent
//
// STATUS: READY FOR FORMAT + ANALYZE
//
// NEXT FILE: signaling_service.dart
// Location: lib/services/call/signaling_service.dart
// ===============================================================
