// ===============================================================
// JR CALL
// File: background_call_service.dart
// Location: lib/services/call/background_call_service.dart
//
// MASTER PRODUCTION BACKGROUND CALL ORCHESTRATOR
//
// RESPONSIBILITIES:
//
// - Coordinate native Android/iOS incoming-call presentation.
// - Validate background/restore payloads against signaling truth.
// - Coordinate native answer/reject/end actions with CallService.
// - Restore pending incoming-call presentation after app resume.
// - Prevent duplicate/stale native call actions.
// - Expire incoming-call PRESENTATION safely.
// - Bridge localized NotificationService metadata to native layer.
// - Serialize native action ownership per call.
// - Keep platform-channel payloads codec-safe.
//
// OWNERSHIP:
//
// Native Android/iOS:
// - System incoming-call UI / full-screen presentation.
// - Native notification/call integration.
//
// SignalingService:
// - Server/signaling truth.
// - Read validation from this service is allowed.
//
// CallService:
// - Actual call lifecycle.
// - Answer / reject / end.
// - Canonical timeout/history/signaling mutation.
//
// NotificationService:
// - Notification presentation state.
// - Locale-ready title/body and localization resource metadata.
//
// BackgroundCallService:
// - Background/native orchestration only.
//
// IMPORTANT:
//
// - This service does NOT create PeerConnection.
// - This service does NOT own media.
// - This service does NOT own ICE.
// - This service does NOT own recovery.
// - This service does NOT directly write call history.
// - This service does NOT directly mutate signaling status.
// - Native presentation timeout NEVER ends the actual call.
// - FCM background handler registration does NOT belong here.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'call_service.dart';
import 'notification_service.dart';
import 'signaling_service.dart';

// ===============================================================
// BACKGROUND EVENT TYPE
// ===============================================================

enum BackgroundCallEventType {
  incoming,
  accepted,
  rejected,
  cancelled,
  ended,
  timeout,
  restored,
  error,
}

// ===============================================================
// BACKGROUND EVENT
// ===============================================================

@immutable
class BackgroundCallEvent {
  const BackgroundCallEvent({
    required this.type,
    required this.callId,
    this.payload,
    this.error,
  });

  final BackgroundCallEventType type;

  final String callId;

  final BackgroundCallPayload? payload;

  final Object? error;
}

// ===============================================================
// BACKGROUND CALL PAYLOAD
// ===============================================================

@immutable
class BackgroundCallPayload {
  const BackgroundCallPayload({
    required this.callId,
    required this.callerId,
    required this.receiverId,
    required this.callerName,
    required this.isVideoCall,
    this.callerAvatarUrl,
    this.createdAt,
    this.extra = const <String, dynamic>{},
  });

  final String callId;

  final String callerId;

  final String receiverId;

  final String callerName;

  final String? callerAvatarUrl;

  final bool isVideoCall;

  final DateTime? createdAt;

  final Map<String, dynamic> extra;

  // =============================================================
  // FROM MAP
  // =============================================================

  factory BackgroundCallPayload.fromMap(
      Map<String, dynamic> map,
      ) {
    final String callId = _readRequiredString(
      map['callId'],
      fieldName: 'callId',
    );

    final String callerId = _readRequiredString(
      map['callerId'] ??
          map['callerUid'] ??
          map['senderId'],
      fieldName: 'callerId',
    );

    final String receiverId = _readRequiredString(
      map['receiverId'] ??
          map['receiverUid'],
      fieldName: 'receiverId',
    );

    final String callerName =
        _readOptionalString(
          map['callerName'],
        ) ??
            _readOptionalString(
              map['senderName'],
            ) ??
            'JR CALL User';

    final String? avatarUrl =
        _readOptionalString(
          map['callerAvatarUrl'],
        ) ??
            _readOptionalString(
              map['callerPhotoUrl'],
            ) ??
            _readOptionalString(
              map['photoUrl'],
            );

    final String? callType =
    _readOptionalString(
      map['callType'],
    )?.toLowerCase();

    final bool isVideoCall = _readBoolean(
      map['isVideoCall'] ??
          map['video'],
      fallback:
      callType == 'video',
    );

    return BackgroundCallPayload(
      callId: callId,
      callerId: callerId,
      receiverId: receiverId,
      callerName: callerName,
      callerAvatarUrl: avatarUrl,
      isVideoCall: isVideoCall,
      createdAt: _readDateTime(
        map['createdAt'],
      ),
      extra: Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(
          map,
        ),
      ),
    );
  }

  // =============================================================
  // TO MAP
  // =============================================================

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      ...extra,
      'callId': callId,
      'callerId': callerId,
      'receiverId': receiverId,
      'callerName': callerName,
      'callerAvatarUrl':
      callerAvatarUrl,
      'isVideoCall':
      isVideoCall,
      'callType':
      isVideoCall
          ? 'video'
          : 'voice',
      'createdAt':
      createdAt?.toIso8601String(),
    };
  }

  // =============================================================
  // PARSING
  // =============================================================

  static String _readRequiredString(
      Object? value, {
        required String fieldName,
      }) {
    final String? result =
    _readOptionalString(
      value,
    );

    if (result == null) {
      throw FormatException(
        'Background call payload field '
            '"$fieldName" is missing.',
      );
    }

    return result;
  }

  static String? _readOptionalString(
      Object? value,
      ) {
    if (value is! String) {
      return null;
    }

    final String normalized =
    value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  static bool _readBoolean(
      Object? value, {
        required bool fallback,
      }) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      switch (value
          .trim()
          .toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
        case 'video':
          return true;

        case 'false':
        case '0':
        case 'no':
        case 'voice':
          return false;
      }
    }

    return fallback;
  }

  static DateTime? _readDateTime(
      Object? value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime
          .fromMillisecondsSinceEpoch(
        value,
      );
    }

    if (value is num) {
      return DateTime
          .fromMillisecondsSinceEpoch(
        value.toInt(),
      );
    }

    if (value is String) {
      final String normalized =
      value.trim();

      if (normalized.isEmpty) {
        return null;
      }

      final int? milliseconds =
      int.tryParse(
        normalized,
      );

      if (milliseconds != null &&
          normalized.length >= 11) {
        return DateTime
            .fromMillisecondsSinceEpoch(
          milliseconds,
        );
      }

      return DateTime.tryParse(
        normalized,
      );
    }

    // Firestore Timestamp-style compatibility without forcing
    // this orchestration file to own a cloud_firestore import.
    try {
      final dynamic dynamicValue =
          value;

      final Object? converted =
      dynamicValue.toDate();

      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {
      // Unsupported date-like object.
    }

    return null;
  }
}

// ===============================================================
// BACKGROUND CALL SERVICE
// ===============================================================

class BackgroundCallService
    with WidgetsBindingObserver {
  BackgroundCallService._();

  static final BackgroundCallService
  instance =
  BackgroundCallService._();

  // =============================================================
  // PLATFORM CHANNEL
  // =============================================================

  static const MethodChannel
  _platformChannel =
  MethodChannel(
    'jr_call/background_call',
  );

  // =============================================================
  // POLICY
  // =============================================================

  static const Duration
  _defaultIncomingCallTimeout =
  Duration(
    seconds: 45,
  );

  static const int
  _completedCallCacheLimit =
  64;

  // =============================================================
  // DEPENDENCIES
  // =============================================================

  final CallService _callService =
  CallService();

  final SignalingService
  _signalingService =
      SignalingService.instance;

  final NotificationService
  _notificationService =
      NotificationService.instance;

  // =============================================================
  // EVENTS
  // =============================================================

  final StreamController<
      BackgroundCallEvent>
  _eventController =
  StreamController<
      BackgroundCallEvent>.broadcast();

  // =============================================================
  // INITIALIZATION
  // =============================================================

  Future<void>?
  _initializationFuture;

  bool _isInitialized = false;

  bool _isDisposed = false;

  // =============================================================
  // SESSION STATE
  // =============================================================

  bool _isShowingIncomingCall =
  false;

  String? _activeActionCallId;

  int _sessionGeneration = 0;

  BackgroundCallPayload?
  _pendingCall;

  Timer?
  _incomingCallTimeoutTimer;

  String? _lastPresentedCallId;

  final List<String>
  _completedCallIds =
  <String>[];

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  Stream<BackgroundCallEvent>
  get events =>
      _eventController.stream;

  bool get isInitialized =>
      _isInitialized;

  bool get isDisposed =>
      _isDisposed;

  bool get hasPendingCall =>
      _pendingCall != null;

  BackgroundCallPayload?
  get pendingCall =>
      _pendingCall;

  String? get pendingCallId =>
      _pendingCall?.callId;

  // =============================================================
  // INITIALIZATION
  // =============================================================

  Future<void> initialize() {
    if (_isDisposed) {
      return Future<void>.error(
        StateError(
          'BackgroundCallService '
              'has been disposed.',
        ),
      );
    }

    if (_isInitialized) {
      return Future<void>.value();
    }

    final Future<void>?
    existing =
        _initializationFuture;

    if (existing != null) {
      return existing;
    }

    final Future<void> future =
    _initializeInternal();

    _initializationFuture =
        future;

    return future;
  }

  Future<void>
  _initializeInternal() async {
    bool observerAttached =
    false;

    bool handlerAttached =
    false;

    try {
      if (_isDisposed ||
          _isInitialized) {
        return;
      }

      WidgetsBinding.instance
          .addObserver(
        this,
      );

      observerAttached = true;

      _platformChannel
          .setMethodCallHandler(
        _handleNativeMethodCall,
      );

      handlerAttached = true;

      // Existing CallService initialization contract.
      await _callService.initialize();

      if (_isDisposed) {
        return;
      }

      _isInitialized = true;

      await _notifyNativeServiceReady();

      if (_isDisposed) {
        return;
      }

      await restorePendingCall();

      debugPrint(
        'JR CALL: '
            'BackgroundCallService initialized.',
      );
    } catch (error, stackTrace) {
      _reportError(
        'Initialize',
        error,
        stackTrace,
      );

      if (!_isInitialized) {
        if (observerAttached) {
          WidgetsBinding.instance
              .removeObserver(
            this,
          );
        }

        if (handlerAttached) {
          _platformChannel
              .setMethodCallHandler(
            null,
          );
        }
      }

      rethrow;
    } finally {
      if (!_isInitialized) {
        _initializationFuture =
        null;
      }
    }
  }

  Future<void>
  _ensureInitialized() async {
    if (_isDisposed) {
      throw StateError(
        'BackgroundCallService '
            'has been disposed.',
      );
    }

    if (!_isInitialized) {
      await initialize();
    }
  }

  // =============================================================
  // APP LIFECYCLE
  // =============================================================

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state,
      ) {
    if (_isDisposed ||
        !_isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(
          restorePendingCall(),
        );
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  // =============================================================
  // INCOMING PUSH / DATA PAYLOAD
  //
  // IMPORTANT:
  //
  // This is an application-runtime entry API.
  //
  // FirebaseMessaging.onBackgroundMessage registration must remain
  // a top-level @pragma('vm:entry-point') function in application
  // bootstrap according to FlutterFire requirements.
  // =============================================================

  Future<bool>
  handleIncomingCallData(
      Map<String, dynamic> data,
      ) async {
    await _ensureInitialized();

    try {
      final BackgroundCallPayload
      payload =
      BackgroundCallPayload
          .fromMap(
        data,
      );

      return presentIncomingCall(
        payload,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Incoming call payload',
        error,
        stackTrace,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .error,
          callId:
          _readCallIdSafely(
            data,
          ),
          error:
          error,
        ),
      );

      return false;
    }
  }

  // =============================================================
  // PRESENT INCOMING CALL
  // =============================================================

  Future<bool> presentIncomingCall(
      BackgroundCallPayload payload,
      ) async {
    await _ensureInitialized();

    if (_isDisposed) {
      return false;
    }

    final String callId =
    payload.callId.trim();

    if (callId.isEmpty) {
      return false;
    }

    if (_isCallCompleted(
      callId,
    )) {
      await _dismissNativeCall(
        callId,
      );

      return false;
    }

    // Exact duplicate already pending.
    if (_pendingCall?.callId ==
        callId &&
        _lastPresentedCallId ==
            callId) {
      return true;
    }

    // Call has already moved into CallService lifecycle.
    if (_callService.isCallActive &&
        _callService.currentCallId ==
            callId) {
      await _dismissNativeCall(
        callId,
      );

      return false;
    }

    // Another real call is active.
    if (_callService.isCallActive &&
        _callService.currentCallId !=
            callId) {
      await _rejectBusyIncomingCall(
        callId,
      );

      return false;
    }

    if (_isShowingIncomingCall) {
      return false;
    }

    if (_activeActionCallId !=
        null) {
      return false;
    }

    _isShowingIncomingCall =
    true;

    final int sessionToken =
    ++_sessionGeneration;

    try {
      final bool active =
      await _validateCallIsActive(
        callId,
      );

      if (!_isSessionCurrent(
        sessionToken,
      ) ||
          !active) {
        return false;
      }

      final Map<String, dynamic>
      callData =
      await _signalingService
          .getCallDocument(
        callId,
      );

      if (!_isSessionCurrent(
        sessionToken,
      )) {
        return false;
      }

      final BackgroundCallPayload
      normalizedPayload =
      _mergePayloadWithCallDocument(
        payload,
        callData,
      );

      if (_isPayloadPresentationExpired(
        normalizedPayload,
      )) {
        _markCallCompleted(
          normalizedPayload.callId,
        );

        await _dismissNativeCall(
          normalizedPayload.callId,
        );

        return false;
      }

      _pendingCall =
          normalizedPayload;

      _lastPresentedCallId =
          normalizedPayload.callId;

      _removeCompletedCall(
        normalizedPayload.callId,
      );

      _startIncomingCallTimeout(
        normalizedPayload,
        sessionToken,
      );

      final Map<String, dynamic>
      nativeArguments =
      await _buildIncomingNativeArguments(
        normalizedPayload,
      );

      if (!_isSessionCurrent(
        sessionToken,
      )) {
        return false;
      }

      await _invokeNativeMethod(
        'showIncomingCall',
        nativeArguments,
      );

      if (!_isSessionCurrent(
        sessionToken,
      )) {
        return false;
      }

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .incoming,
          callId:
          normalizedPayload
              .callId,
          payload:
          normalizedPayload,
        ),
      );

      return true;
    } catch (error, stackTrace) {
      _reportError(
        'Present incoming call',
        error,
        stackTrace,
      );

      await _clearPendingCall(
        dismissNativeUi:
        true,
        callIdOverride:
        callId,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .error,
          callId:
          callId,
          payload:
          payload,
          error:
          error,
        ),
      );

      return false;
    } finally {
      _isShowingIncomingCall =
      false;
    }
  }

  // =============================================================
  // SIGNALING READ VALIDATION
  // =============================================================

  Future<bool> _validateCallIsActive(
      String callId,
      ) async {
    final String normalizedCallId =
    callId.trim();

    if (normalizedCallId.isEmpty) {
      return false;
    }

    try {
      return await _signalingService
          .checkCallActiveStatus(
        normalizedCallId,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Validate active call',
        error,
        stackTrace,
      );

      return false;
    }
  }

  BackgroundCallPayload
  _mergePayloadWithCallDocument(
      BackgroundCallPayload payload,
      Map<String, dynamic> callData,
      ) {
    final Map<String, dynamic>
    merged =
    <String, dynamic>{
      ...payload.toMap(),
      ...callData,

      // Never permit a malformed/stale document merge to replace
      // the push/session identifier being validated.
      'callId':
      payload.callId,
    };

    return BackgroundCallPayload
        .fromMap(
      merged,
    );
  }

  // =============================================================
  // ACCEPT
  // =============================================================

  Future<void> acceptPendingCall({
    String? callId,
  }) async {
    await _ensureInitialized();

    final String? targetCallId =
    _resolveActionCallId(
      callId,
    );

    if (targetCallId == null ||
        !_beginAction(
          targetCallId,
        )) {
      return;
    }

    final BackgroundCallPayload?
    payload =
    _pendingCall?.callId ==
        targetCallId
        ? _pendingCall
        : null;

    try {
      _cancelIncomingCallTimeout();

      final bool active =
      await _validateCallIsActive(
        targetCallId,
      );

      if (!active) {
        await _clearPendingCall(
          dismissNativeUi:
          true,
          callIdOverride:
          targetCallId,
        );

        _notificationService.dismiss(
          targetCallId,
        );

        return;
      }

      await _notificationService
          .showConnecting(
        callId:
        targetCallId,
      );

      await _invokeNativeMethod(
        'setCallConnecting',
        <String, dynamic>{
          'callId':
          targetCallId,
        },
      );

      // CallService owns the real accept lifecycle.
      await _callService.acceptCall(
        callId:
        targetCallId,
      );

      if (_callService.currentCallId ==
          targetCallId) {
        await _invokeNativeMethod(
          'setCallOngoing',
          <String, dynamic>{
            'callId':
            targetCallId,
            'isVideoCall':
            payload?.isVideoCall ??
                false,
          },
        );

        _emitEvent(
          BackgroundCallEvent(
            type:
            BackgroundCallEventType
                .accepted,
            callId:
            targetCallId,
            payload:
            payload,
          ),
        );

        _pendingCall = null;

        _lastPresentedCallId =
        null;

        _sessionGeneration++;

        _cancelIncomingCallTimeout();

        // Do NOT call showConnected() here.
        //
        // Accept completion is not proof that the native WebRTC
        // transport has reached connected state.
      } else {
        await _invokeNativeMethod(
          'endNativeCall',
          <String, dynamic>{
            'callId':
            targetCallId,
            'reason':
            'connection_failed',
          },
        );

        await _notificationService
            .showCallFailed(
          callId:
          targetCallId,
        );

        await _clearPendingCall(
          dismissNativeUi:
          false,
          callIdOverride:
          targetCallId,
        );
      }
    } catch (error, stackTrace) {
      _reportError(
        'Accept background call',
        error,
        stackTrace,
      );

      await _invokeNativeMethod(
        'endNativeCall',
        <String, dynamic>{
          'callId':
          targetCallId,
          'reason':
          'accept_failed',
        },
      );

      await _notificationService
          .showCallFailed(
        callId:
        targetCallId,
      );

      await _clearPendingCall(
        dismissNativeUi:
        false,
        callIdOverride:
        targetCallId,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .error,
          callId:
          targetCallId,
          payload:
          payload,
          error:
          error,
        ),
      );
    } finally {
      _endAction(
        targetCallId,
      );
    }
  }

  // =============================================================
  // REJECT
  // =============================================================

  Future<void> rejectPendingCall({
    String? callId,
  }) async {
    await _ensureInitialized();

    final String? targetCallId =
    _resolveActionCallId(
      callId,
    );

    if (targetCallId == null ||
        !_beginAction(
          targetCallId,
        )) {
      return;
    }

    final BackgroundCallPayload?
    payload =
    _pendingCall?.callId ==
        targetCallId
        ? _pendingCall
        : null;

    bool rejectedSuccessfully =
    false;

    try {
      _cancelIncomingCallTimeout();

      // CallService owns rejection/status/history.
      await _callService.rejectCall(
        callId:
        targetCallId,
      );

      rejectedSuccessfully =
      true;

      _markCallCompleted(
        targetCallId,
      );

      await _notificationService
          .showRejected(
        callId:
        targetCallId,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .rejected,
          callId:
          targetCallId,
          payload:
          payload,
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'Reject background call',
        error,
        stackTrace,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .error,
          callId:
          targetCallId,
          payload:
          payload,
          error:
          error,
        ),
      );
    } finally {
      await _clearPendingCall(
        dismissNativeUi:
        true,
        callIdOverride:
        targetCallId,
      );

      if (!rejectedSuccessfully) {
        _removeCompletedCall(
          targetCallId,
        );
      }

      _endAction(
        targetCallId,
      );
    }
  }

  // =============================================================
  // CANCEL INCOMING PRESENTATION
  //
  // This method owns PRESENTATION cancellation only.
  // It does not mutate signaling/call lifecycle.
  // =============================================================

  Future<void>
  cancelIncomingPresentation({
    String? callId,
  }) async {
    final String? targetCallId =
    _resolveActionCallId(
      callId,
    );

    if (targetCallId == null) {
      return;
    }

    _markCallCompleted(
      targetCallId,
    );

    await _notificationService
        .showCancelled(
      callId:
      targetCallId,
    );

    _emitEvent(
      BackgroundCallEvent(
        type:
        BackgroundCallEventType
            .cancelled,
        callId:
        targetCallId,
        payload:
        _pendingCall,
      ),
    );

    await _clearPendingCall(
      dismissNativeUi:
      true,
      callIdOverride:
      targetCallId,
    );
  }

  // =============================================================
  // END ACTIVE CALL
  // =============================================================

  Future<void> endBackgroundCall({
    required String callId,
    String status = 'COMPLETED',
  }) async {
    await _ensureInitialized();

    final String normalizedCallId =
    callId.trim();

    if (normalizedCallId.isEmpty) {
      return;
    }

    if (_isCallCompleted(
      normalizedCallId,
    )) {
      return;
    }

    if (!_beginAction(
      normalizedCallId,
    )) {
      return;
    }

    bool endedSuccessfully =
    false;

    try {
      // CallService owns real terminal signaling/history.
      await _callService.endCall(
        callId:
        normalizedCallId,
        status:
        status,
      );

      endedSuccessfully =
      true;

      _markCallCompleted(
        normalizedCallId,
      );

      await _notificationService
          .showCallEnded(
        callId:
        normalizedCallId,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .ended,
          callId:
          normalizedCallId,
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'End background call',
        error,
        stackTrace,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .error,
          callId:
          normalizedCallId,
          error:
          error,
        ),
      );

      rethrow;
    } finally {
      if (endedSuccessfully) {
        await _clearPendingCall(
          dismissNativeUi:
          true,
          callIdOverride:
          normalizedCallId,
        );
      }

      _endAction(
        normalizedCallId,
      );
    }
  }

  // =============================================================
  // NATIVE METHOD HANDLER
  // =============================================================

  Future<Object?>
  _handleNativeMethodCall(
      MethodCall call,
      ) async {
    if (_isDisposed) {
      return null;
    }

    final Map<String, dynamic>
    arguments =
    _normalizeArguments(
      call.arguments,
    );

    final String? callId =
    _readOptionalString(
      arguments['callId'],
    );

    switch (call.method) {
      case 'incomingCallAccepted':
        await acceptPendingCall(
          callId:
          callId,
        );

        return true;

      case 'incomingCallRejected':
        await rejectPendingCall(
          callId:
          callId,
        );

        return true;

      case 'incomingCallTimedOut':
        await _handleIncomingTimeout(
          callId ??
              pendingCallId,
        );

        return true;

      case 'nativeCallEnded':
        final String? targetCallId =
            callId ??
                _callService
                    .currentCallId ??
                pendingCallId;

        if (targetCallId != null) {
          await endBackgroundCall(
            callId:
            targetCallId,
          );
        }

        return true;

      case 'appLaunchedForCall':
      case 'restoreIncomingCall':
        await restorePendingCall(
          nativeArguments:
          arguments,
        );

        return true;

      default:
        debugPrint(
          'JR CALL: Unknown '
              'background-call native method: '
              '${call.method}',
        );

        return null;
    }
  }

  // =============================================================
  // RESTORE PENDING CALL
  // =============================================================

  Future<void> restorePendingCall({
    Map<String, dynamic>?
    nativeArguments,
  }) async {
    if (_isDisposed) {
      return;
    }

    try {
      final Map<String, dynamic>
      arguments =
          nativeArguments ??
              await _getNativePendingCall();

      if (arguments.isEmpty) {
        return;
      }

      final BackgroundCallPayload
      rawPayload =
      BackgroundCallPayload.fromMap(
        arguments,
      );

      if (_isCallCompleted(
        rawPayload.callId,
      )) {
        await _dismissNativeCall(
          rawPayload.callId,
        );

        return;
      }

      if (_callService.isCallActive &&
          _callService.currentCallId ==
              rawPayload.callId) {
        await _dismissNativeCall(
          rawPayload.callId,
        );

        return;
      }

      if (_callService.isCallActive &&
          _callService.currentCallId !=
              rawPayload.callId) {
        await _rejectBusyIncomingCall(
          rawPayload.callId,
        );

        await _dismissNativeCall(
          rawPayload.callId,
        );

        return;
      }

      if (_pendingCall?.callId ==
          rawPayload.callId &&
          _lastPresentedCallId ==
              rawPayload.callId) {
        return;
      }

      final bool active =
      await _validateCallIsActive(
        rawPayload.callId,
      );

      if (!active) {
        await _dismissNativeCall(
          rawPayload.callId,
        );

        return;
      }

      final Map<String, dynamic>
      callData =
      await _signalingService
          .getCallDocument(
        rawPayload.callId,
      );

      final BackgroundCallPayload
      payload =
      _mergePayloadWithCallDocument(
        rawPayload,
        callData,
      );

      if (_isPayloadPresentationExpired(
        payload,
      )) {
        _markCallCompleted(
          payload.callId,
        );

        await _dismissNativeCall(
          payload.callId,
        );

        _notificationService.dismiss(
          payload.callId,
        );

        return;
      }

      _pendingCall =
          payload;

      _lastPresentedCallId =
          payload.callId;

      final int sessionToken =
      ++_sessionGeneration;

      _startIncomingCallTimeout(
        payload,
        sessionToken,
      );

      await _notificationService
          .showIncomingCall(
        callId:
        payload.callId,
        callerId:
        payload.callerId,
        callerName:
        payload.callerName,
        callerPhotoUrl:
        payload.callerAvatarUrl,
        isVideoCall:
        payload.isVideoCall,
        data:
        payload.extra,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .restored,
          callId:
          payload.callId,
          payload:
          payload,
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'Restore pending call',
        error,
        stackTrace,
      );
    }
  }

  Future<Map<String, dynamic>>
  _getNativePendingCall() async {
    final Object? result =
    await _invokeNativeMethod(
      'getPendingCall',
    );

    return _normalizeArguments(
      result,
    );
  }

  // =============================================================
  // PRESENTATION TIMEOUT
  //
  // CRITICAL:
  //
  // This timer only controls incoming-call presentation.
  //
  // It MUST NOT:
  // - update signaling status;
  // - write call history;
  // - mark the call missed;
  // - terminate PeerConnection.
  //
  // CallService owns canonical timeout/history behavior.
  // =============================================================

  void _startIncomingCallTimeout(
      BackgroundCallPayload payload,
      int sessionToken,
      ) {
    _cancelIncomingCallTimeout();

    final Duration remaining =
    _remainingIncomingPresentationTime(
      payload,
    );

    if (remaining <=
        Duration.zero) {
      unawaited(
        _handleIncomingTimeout(
          payload.callId,
        ),
      );

      return;
    }

    _incomingCallTimeoutTimer =
        Timer(
          remaining,
              () {
            if (!_isSessionCurrent(
              sessionToken,
            ) ||
                _pendingCall?.callId !=
                    payload.callId ||
                _isCallCompleted(
                  payload.callId,
                )) {
              return;
            }

            unawaited(
              _handleIncomingTimeout(
                payload.callId,
              ),
            );
          },
        );
  }

  Duration
  _remainingIncomingPresentationTime(
      BackgroundCallPayload payload,
      ) {
    final DateTime? createdAt =
        payload.createdAt;

    if (createdAt == null) {
      return _defaultIncomingCallTimeout;
    }

    final DateTime expiresAt =
    createdAt.add(
      _defaultIncomingCallTimeout,
    );

    final Duration remaining =
    expiresAt.difference(
      DateTime.now(),
    );

    if (remaining <=
        Duration.zero) {
      return Duration.zero;
    }

    // If server/client clock skew places createdAt in the future,
    // never grant more than the configured presentation window.
    if (remaining >
        _defaultIncomingCallTimeout) {
      return _defaultIncomingCallTimeout;
    }

    return remaining;
  }

  bool _isPayloadPresentationExpired(
      BackgroundCallPayload payload,
      ) {
    return _remainingIncomingPresentationTime(
      payload,
    ) <=
        Duration.zero;
  }

  Future<void>
  _handleIncomingTimeout(
      String? callId,
      ) async {
    final String? normalizedCallId =
    _readOptionalString(
      callId,
    );

    if (normalizedCallId == null) {
      return;
    }

    if (_isCallCompleted(
      normalizedCallId,
    )) {
      return;
    }

    if (_activeActionCallId ==
        normalizedCallId) {
      return;
    }

    if (!_beginAction(
      normalizedCallId,
    )) {
      return;
    }

    final BackgroundCallPayload?
    payload =
    _pendingCall?.callId ==
        normalizedCallId
        ? _pendingCall
        : null;

    try {
      _cancelIncomingCallTimeout();

      _markCallCompleted(
        normalizedCallId,
      );

      // Presentation-only cleanup.
      //
      // CallService already owns canonical timeout/missed/history.
      _notificationService.dismiss(
        normalizedCallId,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .timeout,
          callId:
          normalizedCallId,
          payload:
          payload,
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'Incoming presentation timeout',
        error,
        stackTrace,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .error,
          callId:
          normalizedCallId,
          payload:
          payload,
          error:
          error,
        ),
      );
    } finally {
      await _clearPendingCall(
        dismissNativeUi:
        true,
        callIdOverride:
        normalizedCallId,
      );

      _endAction(
        normalizedCallId,
      );
    }
  }

  void _cancelIncomingCallTimeout() {
    _incomingCallTimeoutTimer
        ?.cancel();

    _incomingCallTimeoutTimer =
    null;
  }

  // =============================================================
  // BUSY HANDLING
  //
  // CallService owns lifecycle mutation/history.
  // =============================================================

  Future<void>
  _rejectBusyIncomingCall(
      String callId,
      ) async {
    final String normalizedCallId =
    callId.trim();

    if (normalizedCallId.isEmpty ||
        _isCallCompleted(
          normalizedCallId,
        )) {
      return;
    }

    try {
      await _callService.rejectCall(
        callId:
        normalizedCallId,
      );

      _markCallCompleted(
        normalizedCallId,
      );

      _emitEvent(
        BackgroundCallEvent(
          type:
          BackgroundCallEventType
              .rejected,
          callId:
          normalizedCallId,
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'Reject busy incoming call',
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // NOTIFICATION / LOCALIZATION BRIDGE
  // =============================================================

  Future<Map<String, dynamic>>
  _buildIncomingNativeArguments(
      BackgroundCallPayload payload,
      ) async {
    await _notificationService
        .showIncomingCall(
      callId:
      payload.callId,
      callerId:
      payload.callerId,
      callerName:
      payload.callerName,
      callerPhotoUrl:
      payload.callerAvatarUrl,
      isVideoCall:
      payload.isVideoCall,
      data:
      payload.extra,
    );

    final CallNotification?
    notification =
    _findNotification(
      payload.callId,
    );

    final Map<String, dynamic>
    result =
    <String, dynamic>{
      ...payload.toMap(),
    };

    if (notification != null) {
      result.addAll(
        <String, dynamic>{
          // Current localized/fallback presentation.
          'notificationTitle':
          notification.title,
          'notificationBody':
          notification.body,

          // Stable resource metadata for Android/iOS mapping.
          'notificationTitleLocKey':
          notification
              .titleLocalizationKey,
          'notificationBodyLocKey':
          notification
              .bodyLocalizationKey,
          'notificationTitleLocArgs':
          notification
              .titleLocalizationArgs,
          'notificationBodyLocArgs':
          notification
              .bodyLocalizationArgs,
        },
      );
    }

    return result;
  }

  CallNotification?
  _findNotification(
      String callId,
      ) {
    for (final CallNotification
    notification
    in _notificationService
        .activeNotifications) {
      if (notification.callId ==
          callId) {
        return notification;
      }
    }

    return null;
  }

  // =============================================================
  // NATIVE SERVICE READY
  // =============================================================

  Future<void>
  _notifyNativeServiceReady() async {
    await _invokeNativeMethod(
      'initializeBackgroundCallService',
      <String, dynamic>{
        'supportsVideo':
        true,
        'incomingTimeoutSeconds':
        _defaultIncomingCallTimeout
            .inSeconds,
      },
    );
  }

  // =============================================================
  // NATIVE METHOD INVOCATION
  // =============================================================

  Future<Object?> _invokeNativeMethod(
      String method, [
        Map<String, dynamic>?
        arguments,
      ]) async {
    if (kIsWeb ||
        _isDisposed) {
      return null;
    }

    final Map<String, dynamic>?
    safeArguments =
    arguments == null
        ? null
        : _toPlatformSafeMap(
      arguments,
    );

    try {
      return await _platformChannel
          .invokeMethod<Object?>(
        method,
        safeArguments,
      );
    } on MissingPluginException {
      debugPrint(
        'JR CALL: Native background-call '
            'implementation is not connected '
            'for this platform.',
      );

      return null;
    } on PlatformException
    catch (error, stackTrace) {
      _reportError(
        'Native method $method',
        error,
        stackTrace,
      );

      return null;
    }
  }

  Future<void> _dismissNativeCall(
      String callId,
      ) async {
    final String normalized =
    callId.trim();

    if (normalized.isEmpty) {
      return;
    }

    await _invokeNativeMethod(
      'dismissIncomingCall',
      <String, dynamic>{
        'callId':
        normalized,
      },
    );
  }

  // =============================================================
  // PLATFORM CODEC SAFETY
  //
  // Firestore Timestamp and arbitrary plugin objects cannot be sent
  // directly through StandardMethodCodec.
  // =============================================================

  Map<String, dynamic>
  _toPlatformSafeMap(
      Map<String, dynamic> map,
      ) {
    final Map<String, dynamic>
    result =
    <String, dynamic>{};

    for (final MapEntry<
        String,
        dynamic>
    entry
    in map.entries) {
      result[entry.key] =
          _toPlatformSafeValue(
            entry.value,
          );
    }

    return result;
  }

  dynamic _toPlatformSafeValue(
      Object? value,
      ) {
    if (value == null ||
        value is String ||
        value is bool ||
        value is int ||
        value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is DateTime) {
      return value
          .toIso8601String();
    }

    if (value is Duration) {
      return value
          .inMilliseconds;
    }

    if (value is Map) {
      final Map<String, dynamic>
      normalized =
      <String, dynamic>{};

      for (final MapEntry<dynamic, dynamic>
      entry
      in value.entries) {
        normalized[
        entry.key.toString()] =
            _toPlatformSafeValue(
              entry.value,
            );
      }

      return normalized;
    }

    if (value is Iterable) {
      return value
          .map<dynamic>(
        _toPlatformSafeValue,
      )
          .toList(
        growable: false,
      );
    }

    // Firestore Timestamp-style object.
    try {
      final dynamic dynamicValue =
          value;

      final Object? converted =
      dynamicValue.toDate();

      if (converted is DateTime) {
        return converted
            .toIso8601String();
      }
    } catch (_) {
      // Not a supported date-like object.
    }

    // Never allow an unsupported platform-channel value to crash
    // incoming-call presentation.
    return value.toString();
  }

  // =============================================================
  // ACTION / CONCURRENCY PROTECTION
  // =============================================================

  bool _beginAction(
      String callId,
      ) {
    final String normalizedCallId =
    callId.trim();

    if (_isDisposed ||
        normalizedCallId.isEmpty) {
      return false;
    }

    if (_activeActionCallId !=
        null) {
      return false;
    }

    _activeActionCallId =
        normalizedCallId;

    return true;
  }

  void _endAction(
      String callId,
      ) {
    if (_activeActionCallId ==
        callId.trim()) {
      _activeActionCallId =
      null;
    }
  }

  // =============================================================
  // COMPLETED CALL DEDUPE
  // =============================================================

  bool _isCallCompleted(
      String callId,
      ) {
    return _completedCallIds
        .contains(
      callId.trim(),
    );
  }

  void _markCallCompleted(
      String callId,
      ) {
    final String normalizedCallId =
    callId.trim();

    if (normalizedCallId.isEmpty) {
      return;
    }

    _completedCallIds.remove(
      normalizedCallId,
    );

    _completedCallIds.add(
      normalizedCallId,
    );

    while (_completedCallIds.length >
        _completedCallCacheLimit) {
      _completedCallIds.removeAt(
        0,
      );
    }
  }

  void _removeCompletedCall(
      String callId,
      ) {
    _completedCallIds.remove(
      callId.trim(),
    );
  }

  // =============================================================
  // ACTION CALL-ID RESOLUTION
  // =============================================================

  String? _resolveActionCallId(
      String? callId,
      ) {
    final String? normalizedCallId =
    _readOptionalString(
      callId,
    );

    if (normalizedCallId != null) {
      if (_pendingCall?.callId ==
          normalizedCallId ||
          _callService.currentCallId ==
              normalizedCallId) {
        return normalizedCallId;
      }

      // Ignore stale/native actions for a different call.
      return null;
    }

    return _pendingCall?.callId ??
        _callService.currentCallId;
  }

  bool _isSessionCurrent(
      int sessionToken,
      ) {
    return !_isDisposed &&
        sessionToken ==
            _sessionGeneration;
  }

  // =============================================================
  // PENDING CALL CLEANUP
  // =============================================================

  Future<void> _clearPendingCall({
    required bool dismissNativeUi,
    String? callIdOverride,
  }) async {
    final String? callId =
        _readOptionalString(
          callIdOverride,
        ) ??
            _pendingCall?.callId;

    _sessionGeneration++;

    _cancelIncomingCallTimeout();

    _pendingCall = null;

    _lastPresentedCallId =
    null;

    _isShowingIncomingCall =
    false;

    if (dismissNativeUi &&
        callId != null) {
      await _dismissNativeCall(
        callId,
      );
    }
  }

  // =============================================================
  // RESET
  // =============================================================

  void reset() {
    final String? pendingId =
        _pendingCall?.callId;

    _sessionGeneration++;

    _cancelIncomingCallTimeout();

    _pendingCall = null;

    _lastPresentedCallId =
    null;

    _completedCallIds.clear();

    _activeActionCallId =
    null;

    _isShowingIncomingCall =
    false;

    if (pendingId != null) {
      _notificationService.dismiss(
        pendingId,
      );
    }
  }

  // =============================================================
  // EVENT EMITTER
  // =============================================================

  void _emitEvent(
      BackgroundCallEvent event,
      ) {
    if (_isDisposed ||
        _eventController.isClosed) {
      return;
    }

    _eventController.add(
      event,
    );
  }

  // =============================================================
  // ARGUMENT NORMALIZATION
  // =============================================================

  Map<String, dynamic>
  _normalizeArguments(
      Object? arguments,
      ) {
    if (arguments
    is Map<String, dynamic>) {
      return Map<String, dynamic>.from(
        arguments,
      );
    }

    if (arguments is Map) {
      final Map<String, dynamic>
      normalized =
      <String, dynamic>{};

      for (final MapEntry<dynamic, dynamic>
      entry
      in arguments.entries) {
        normalized[
        entry.key.toString()] =
            entry.value;
      }

      return normalized;
    }

    return <String, dynamic>{};
  }

  String _readCallIdSafely(
      Map<String, dynamic> map,
      ) {
    return _readOptionalString(
      map['callId'],
    ) ??
        '';
  }

  String? _readOptionalString(
      Object? value,
      ) {
    if (value is! String) {
      return null;
    }

    final String normalized =
    value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  // =============================================================
  // ERROR LOGGING
  // =============================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL BackgroundCallService '
          '[$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL BackgroundCallService '
            '[$source]',
        stackTrace:
        stackTrace,
      );
    }
  }

  // =============================================================
  // DISPOSE
  // =============================================================

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    WidgetsBinding.instance
        .removeObserver(
      this,
    );

    _platformChannel
        .setMethodCallHandler(
      null,
    );

    _sessionGeneration++;

    _cancelIncomingCallTimeout();

    _pendingCall = null;

    _lastPresentedCallId =
    null;

    _completedCallIds.clear();

    _activeActionCallId =
    null;

    _isShowingIncomingCall =
    false;

    if (!_eventController.isClosed) {
      await _eventController.close();
    }

    _isInitialized = false;

    _initializationFuture =
    null;

    debugPrint(
      'JR CALL: '
          'BackgroundCallService disposed.',
    );
  }
}

// ===============================================================
// END OF FILE
//
// FILE 36 PRODUCTION CONTRACT:
//
// ✓ Existing BackgroundCallService.instance preserved.
// ✓ Existing MethodChannel name preserved.
// ✓ Existing event types preserved.
// ✓ Existing payload public API preserved.
// ✓ Existing events stream preserved.
// ✓ Existing initialization API preserved.
// ✓ Existing incoming-data API preserved.
// ✓ Existing accept/reject/end APIs preserved.
// ✓ Existing restore/reset/dispose APIs preserved.
//
// ✓ SignalingService used READ-ONLY here.
// ✓ No direct updateCallStatus() from background service.
// ✓ No direct saveCallHistory() from background service.
// ✓ CallService remains lifecycle/history owner.
//
// ✓ Presentation timeout no longer writes TIMEOUT status.
// ✓ Presentation timeout no longer writes history.
// ✓ Presentation timeout never ends actual call.
// ✓ Original createdAt controls remaining presentation time.
// ✓ Delayed push cannot receive a fresh extra 45 seconds.
// ✓ Restored push cannot receive a fresh extra 45 seconds.
// ✓ Future clock skew cannot extend beyond 45 seconds.
//
// ✓ Busy rejection delegates to CallService.
// ✓ Native stale action IDs are rejected.
// ✓ Completed-call dedupe supports multiple recent calls.
// ✓ Duplicate incoming presentation protected.
// ✓ Accepted call is not falsely labeled WebRTC-connected.
//
// ✓ NotificationService FILE 35 integration added.
// ✓ Current localized title/body bridged to native.
// ✓ Stable native localization keys bridged.
// ✓ Ordered localization arguments bridged.
// ✓ No country-specific language hardcoding.
// ✓ Native platform can map keys to Android/iOS resources.
//
// ✓ Firestore Timestamp-like values normalized safely.
// ✓ Unsupported MethodChannel values cannot break codec encoding.
// ✓ Platform payload is recursively codec-safe.
//
// ✓ No FCM background-handler ownership added.
// ✓ No PeerConnection ownership added.
// ✓ No media ownership added.
// ✓ No ICE ownership added.
// ✓ No RecoveryManager ownership added.
// ✓ No UI/design ownership added.
// ===============================================================