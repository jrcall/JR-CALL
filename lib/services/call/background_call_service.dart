// ===========================================================
// JR CALL
// File: background_call_service.dart
// Location: lib/services/call/background_call_service.dart
//
// Production background-call orchestration.
//
// Ownership:
// - Native Android/iOS -> incoming call presentation
// - SignalingService -> server/signaling truth
// - CallService -> WebRTC call lifecycle
// - This service -> background/native orchestration only
// ===========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'call_service.dart';
import 'signaling_service.dart';

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

  factory BackgroundCallPayload.fromMap(Map<String, dynamic> map) {
    final callId = _readRequiredString(map['callId'], fieldName: 'callId');

    final callerId = _readRequiredString(
      map['callerId'] ?? map['senderId'],
      fieldName: 'callerId',
    );

    final receiverId = _readRequiredString(
      map['receiverId'],
      fieldName: 'receiverId',
    );

    final callerName =
        _readOptionalString(map['callerName']) ??
        _readOptionalString(map['senderName']) ??
        'JR CALL User';

    final avatarUrl =
        _readOptionalString(map['callerAvatarUrl']) ??
        _readOptionalString(map['callerPhotoUrl']) ??
        _readOptionalString(map['photoUrl']);

    final callType = _readOptionalString(map['callType'])?.toLowerCase();

    final isVideoCall = _readBoolean(
      map['isVideoCall'],
      fallback: callType == 'video',
    );

    return BackgroundCallPayload(
      callId: callId,
      callerId: callerId,
      receiverId: receiverId,
      callerName: callerName,
      callerAvatarUrl: avatarUrl,
      isVideoCall: isVideoCall,
      createdAt: _readDateTime(map['createdAt']),
      extra: Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(map)),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      ...extra,
      'callId': callId,
      'callerId': callerId,
      'receiverId': receiverId,
      'callerName': callerName,
      'callerAvatarUrl': callerAvatarUrl,
      'isVideoCall': isVideoCall,
      'callType': isVideoCall ? 'video' : 'voice',
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  static String _readRequiredString(
    Object? value, {
    required String fieldName,
  }) {
    final result = _readOptionalString(value);

    if (result == null) {
      throw FormatException(
        'Background call payload field "$fieldName" is missing.',
      );
    }

    return result;
  }

  static String? _readOptionalString(Object? value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  static bool _readBoolean(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      switch (value.trim().toLowerCase()) {
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

  static DateTime? _readDateTime(Object? value) {
    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }

    if (value is String) {
      final normalized = value.trim();

      if (normalized.isEmpty) {
        return null;
      }

      return DateTime.tryParse(normalized);
    }

    return null;
  }
}

class BackgroundCallService with WidgetsBindingObserver {
  BackgroundCallService._();

  static final BackgroundCallService instance = BackgroundCallService._();

  static const MethodChannel _platformChannel = MethodChannel(
    'jr_call/background_call',
  );

  static const Duration _defaultIncomingCallTimeout = Duration(seconds: 45);

  final CallService _callService = CallService();

  final SignalingService _signalingService = SignalingService.instance;

  final StreamController<BackgroundCallEvent> _eventController =
      StreamController<BackgroundCallEvent>.broadcast();

  Future<void>? _initializationFuture;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isShowingIncomingCall = false;

  String? _activeActionCallId;

  int _sessionGeneration = 0;

  BackgroundCallPayload? _pendingCall;

  Timer? _incomingCallTimeoutTimer;

  String? _lastPresentedCallId;
  String? _lastCompletedCallId;

  Stream<BackgroundCallEvent> get events => _eventController.stream;

  bool get isInitialized => _isInitialized;

  bool get isDisposed => _isDisposed;

  bool get hasPendingCall => _pendingCall != null;

  BackgroundCallPayload? get pendingCall => _pendingCall;

  String? get pendingCallId => _pendingCall?.callId;

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize() {
    if (_isDisposed) {
      return Future<void>.error(
        StateError('BackgroundCallService has been disposed.'),
      );
    }

    if (_isInitialized) {
      return Future<void>.value();
    }

    final existing = _initializationFuture;

    if (existing != null) {
      return existing;
    }

    final future = _initializeInternal();

    _initializationFuture = future;

    return future;
  }

  Future<void> _initializeInternal() async {
    try {
      if (_isDisposed || _isInitialized) {
        return;
      }

      WidgetsBinding.instance.addObserver(this);

      _platformChannel.setMethodCallHandler(_handleNativeMethodCall);

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

      debugPrint('JR CALL: BackgroundCallService initialized.');
    } catch (_) {
      if (!_isInitialized) {
        WidgetsBinding.instance.removeObserver(this);

        _platformChannel.setMethodCallHandler(null);
      }

      rethrow;
    } finally {
      if (!_isInitialized) {
        _initializationFuture = null;
      }
    }
  }

  Future<void> _ensureInitialized() async {
    if (_isDisposed) {
      throw StateError('BackgroundCallService has been disposed.');
    }

    if (!_isInitialized) {
      await initialize();
    }
  }

  // ===========================================================
  // App Lifecycle
  // ===========================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || !_isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(restorePendingCall());
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  // ===========================================================
  // Incoming Push / Background Payload
  // ===========================================================

  Future<bool> handleIncomingCallData(Map<String, dynamic> data) async {
    await _ensureInitialized();

    try {
      final payload = BackgroundCallPayload.fromMap(data);

      return presentIncomingCall(payload);
    } catch (error, stackTrace) {
      _reportError('Incoming call payload', error, stackTrace);

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.error,
          callId: _readCallIdSafely(data),
          error: error,
        ),
      );

      return false;
    }
  }

  // ===========================================================
  // Incoming Call Presentation
  // ===========================================================

  Future<bool> presentIncomingCall(BackgroundCallPayload payload) async {
    await _ensureInitialized();

    if (_isDisposed) {
      return false;
    }

    if (_isShowingIncomingCall) {
      return false;
    }

    if (_activeActionCallId != null) {
      return false;
    }

    if (_callService.isCallActive &&
        _callService.currentCallId != payload.callId) {
      await _rejectBusyIncomingCall(payload.callId);

      return false;
    }

    if (_lastPresentedCallId == payload.callId &&
        _pendingCall?.callId == payload.callId) {
      return true;
    }

    _isShowingIncomingCall = true;

    final sessionToken = ++_sessionGeneration;

    try {
      final active = await _validateCallIsActive(payload.callId);

      if (!_isSessionCurrent(sessionToken) || !active) {
        return false;
      }

      final callData = await _signalingService.getCallDocument(payload.callId);

      if (!_isSessionCurrent(sessionToken)) {
        return false;
      }

      final normalizedPayload = _mergePayloadWithCallDocument(
        payload,
        callData,
      );

      _pendingCall = normalizedPayload;

      _lastPresentedCallId = normalizedPayload.callId;

      if (_lastCompletedCallId == normalizedPayload.callId) {
        _lastCompletedCallId = null;
      }

      _startIncomingCallTimeout(normalizedPayload.callId, sessionToken);

      await _invokeNativeMethod('showIncomingCall', normalizedPayload.toMap());

      if (!_isSessionCurrent(sessionToken)) {
        return false;
      }

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.incoming,
          callId: normalizedPayload.callId,
          payload: normalizedPayload,
        ),
      );

      return true;
    } catch (error, stackTrace) {
      _reportError('Present incoming call', error, stackTrace);

      await _clearPendingCall(dismissNativeUi: true);

      return false;
    } finally {
      _isShowingIncomingCall = false;
    }
  }

  Future<bool> _validateCallIsActive(String callId) async {
    final normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      return false;
    }

    try {
      return await _signalingService.checkCallActiveStatus(normalizedCallId);
    } catch (error, stackTrace) {
      _reportError('Validate active call', error, stackTrace);

      return false;
    }
  }

  BackgroundCallPayload _mergePayloadWithCallDocument(
    BackgroundCallPayload payload,
    Map<String, dynamic> callData,
  ) {
    final merged = <String, dynamic>{
      ...payload.toMap(),
      ...callData,
      'callId': payload.callId,
    };

    return BackgroundCallPayload.fromMap(merged);
  }

  // ===========================================================
  // Accept Call
  // ===========================================================

  Future<void> acceptPendingCall({String? callId}) async {
    await _ensureInitialized();

    final targetCallId = _resolveActionCallId(callId);

    if (targetCallId == null || !_beginAction(targetCallId)) {
      return;
    }

    final payload = _pendingCall;

    try {
      _cancelIncomingCallTimeout();

      final active = await _validateCallIsActive(targetCallId);

      if (!active) {
        await _clearPendingCall(dismissNativeUi: true);

        return;
      }

      await _invokeNativeMethod('setCallConnecting', <String, dynamic>{
        'callId': targetCallId,
      });

      await _callService.acceptCall(callId: targetCallId);

      if (_callService.currentCallId == targetCallId) {
        await _invokeNativeMethod('setCallOngoing', <String, dynamic>{
          'callId': targetCallId,
          'isVideoCall': payload?.isVideoCall ?? false,
        });

        _emitEvent(
          BackgroundCallEvent(
            type: BackgroundCallEventType.accepted,
            callId: targetCallId,
            payload: payload,
          ),
        );

        _pendingCall = null;
        _lastPresentedCallId = null;
      } else {
        await _invokeNativeMethod('endNativeCall', <String, dynamic>{
          'callId': targetCallId,
          'reason': 'connection_failed',
        });

        await _clearPendingCall(dismissNativeUi: false);
      }
    } catch (error, stackTrace) {
      _reportError('Accept background call', error, stackTrace);

      await _invokeNativeMethod('endNativeCall', <String, dynamic>{
        'callId': targetCallId,
        'reason': 'accept_failed',
      });

      await _clearPendingCall(dismissNativeUi: false);

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.error,
          callId: targetCallId,
          payload: payload,
          error: error,
        ),
      );
    } finally {
      _endAction(targetCallId);
    }
  }

  // ===========================================================
  // Reject Call
  // ===========================================================

  Future<void> rejectPendingCall({String? callId}) async {
    await _ensureInitialized();

    final targetCallId = _resolveActionCallId(callId);

    if (targetCallId == null || !_beginAction(targetCallId)) {
      return;
    }

    final payload = _pendingCall;

    var rejectedSuccessfully = false;

    try {
      _cancelIncomingCallTimeout();

      await _callService.rejectCall(callId: targetCallId);

      rejectedSuccessfully = true;

      _markCallCompleted(targetCallId);

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.rejected,
          callId: targetCallId,
          payload: payload,
        ),
      );
    } catch (error, stackTrace) {
      _reportError('Reject background call', error, stackTrace);

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.error,
          callId: targetCallId,
          payload: payload,
          error: error,
        ),
      );
    } finally {
      await _clearPendingCall(dismissNativeUi: true);

      if (!rejectedSuccessfully && _lastCompletedCallId == targetCallId) {
        _lastCompletedCallId = null;
      }

      _endAction(targetCallId);
    }
  }

  // ===========================================================
  // Cancel Incoming Presentation
  // ===========================================================

  Future<void> cancelIncomingPresentation({String? callId}) async {
    final targetCallId = _resolveActionCallId(callId);

    if (targetCallId == null) {
      return;
    }

    _markCallCompleted(targetCallId);

    _emitEvent(
      BackgroundCallEvent(
        type: BackgroundCallEventType.cancelled,
        callId: targetCallId,
        payload: _pendingCall,
      ),
    );

    await _clearPendingCall(dismissNativeUi: true);
  }

  // ===========================================================
  // End Active Call
  // ===========================================================

  Future<void> endBackgroundCall({
    required String callId,
    String status = 'COMPLETED',
  }) async {
    await _ensureInitialized();

    final normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      return;
    }

    if (_lastCompletedCallId == normalizedCallId) {
      return;
    }

    if (!_beginAction(normalizedCallId)) {
      return;
    }

    var endedSuccessfully = false;

    try {
      await _callService.endCall(callId: normalizedCallId, status: status);

      endedSuccessfully = true;

      _markCallCompleted(normalizedCallId);

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.ended,
          callId: normalizedCallId,
        ),
      );
    } catch (error, stackTrace) {
      _reportError('End background call', error, stackTrace);

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.error,
          callId: normalizedCallId,
          error: error,
        ),
      );

      rethrow;
    } finally {
      if (endedSuccessfully) {
        await _clearPendingCall(dismissNativeUi: true);
      }

      _endAction(normalizedCallId);
    }
  }

  // ===========================================================
  // Native Method Handler
  // ===========================================================

  Future<Object?> _handleNativeMethodCall(MethodCall call) async {
    if (_isDisposed) {
      return null;
    }

    final arguments = _normalizeArguments(call.arguments);

    final callId = _readOptionalString(arguments['callId']);

    switch (call.method) {
      case 'incomingCallAccepted':
        await acceptPendingCall(callId: callId);
        return true;

      case 'incomingCallRejected':
        await rejectPendingCall(callId: callId);
        return true;

      case 'incomingCallTimedOut':
        await _handleIncomingTimeout(callId ?? pendingCallId);
        return true;

      case 'nativeCallEnded':
        final targetCallId =
            callId ?? _callService.currentCallId ?? pendingCallId;

        if (targetCallId != null) {
          await endBackgroundCall(callId: targetCallId);
        }

        return true;

      case 'appLaunchedForCall':
      case 'restoreIncomingCall':
        await restorePendingCall(nativeArguments: arguments);

        return true;

      default:
        debugPrint(
          'JR CALL: Unknown background-call native method: '
          '${call.method}',
        );

        return null;
    }
  }

  // ===========================================================
  // Restore Pending Call
  // ===========================================================

  Future<void> restorePendingCall({
    Map<String, dynamic>? nativeArguments,
  }) async {
    if (_isDisposed) {
      return;
    }

    try {
      final Map<String, dynamic> arguments =
          nativeArguments ?? await _getNativePendingCall();

      if (arguments.isEmpty) {
        return;
      }

      final payload = BackgroundCallPayload.fromMap(arguments);

      if (_lastCompletedCallId == payload.callId) {
        await _invokeNativeMethod('dismissIncomingCall', <String, dynamic>{
          'callId': payload.callId,
        });

        return;
      }

      if (_pendingCall?.callId == payload.callId &&
          _lastPresentedCallId == payload.callId) {
        return;
      }

      final active = await _validateCallIsActive(payload.callId);

      if (!active) {
        await _invokeNativeMethod('dismissIncomingCall', <String, dynamic>{
          'callId': payload.callId,
        });

        return;
      }

      _pendingCall = payload;

      _lastPresentedCallId = payload.callId;

      final sessionToken = ++_sessionGeneration;

      _startIncomingCallTimeout(payload.callId, sessionToken);

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.restored,
          callId: payload.callId,
          payload: payload,
        ),
      );
    } catch (error, stackTrace) {
      _reportError('Restore pending call', error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> _getNativePendingCall() async {
    final result = await _invokeNativeMethod('getPendingCall');

    return _normalizeArguments(result);
  }

  // ===========================================================
  // Incoming Timeout
  // ===========================================================

  void _startIncomingCallTimeout(String callId, int sessionToken) {
    _cancelIncomingCallTimeout();

    _incomingCallTimeoutTimer = Timer(_defaultIncomingCallTimeout, () {
      if (!_isSessionCurrent(sessionToken) ||
          _pendingCall?.callId != callId ||
          _lastCompletedCallId == callId) {
        return;
      }

      unawaited(_handleIncomingTimeout(callId));
    });
  }

  Future<void> _handleIncomingTimeout(String? callId) async {
    final normalizedCallId = _readOptionalString(callId);

    if (normalizedCallId == null) {
      return;
    }

    if (_lastCompletedCallId == normalizedCallId) {
      return;
    }

    if (_activeActionCallId == normalizedCallId) {
      return;
    }

    if (!_beginAction(normalizedCallId)) {
      return;
    }

    final payload = _pendingCall;

    try {
      _cancelIncomingCallTimeout();

      final active = await _validateCallIsActive(normalizedCallId);

      if (active) {
        await _signalingService.updateCallStatus(normalizedCallId, 'timeout');

        await _signalingService.saveCallHistory(
          callId: normalizedCallId,
          duration: 0,
          status: 'TIMEOUT',
          callType: payload?.isVideoCall == true ? 'video' : 'voice',
        );
      }

      _markCallCompleted(normalizedCallId);

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.timeout,
          callId: normalizedCallId,
          payload: payload,
        ),
      );
    } catch (error, stackTrace) {
      _reportError('Incoming call timeout', error, stackTrace);

      _emitEvent(
        BackgroundCallEvent(
          type: BackgroundCallEventType.error,
          callId: normalizedCallId,
          payload: payload,
          error: error,
        ),
      );
    } finally {
      await _clearPendingCall(dismissNativeUi: true);

      _endAction(normalizedCallId);
    }
  }

  void _cancelIncomingCallTimeout() {
    _incomingCallTimeoutTimer?.cancel();

    _incomingCallTimeoutTimer = null;
  }

  // ===========================================================
  // Busy Handling
  // ===========================================================

  Future<void> _rejectBusyIncomingCall(String callId) async {
    final normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      return;
    }

    try {
      await _signalingService.updateCallStatus(normalizedCallId, 'rejected');

      await _signalingService.saveCallHistory(
        callId: normalizedCallId,
        duration: 0,
        status: 'BUSY',
      );

      _markCallCompleted(normalizedCallId);
    } catch (error, stackTrace) {
      _reportError('Reject busy incoming call', error, stackTrace);
    }
  }

  // ===========================================================
  // Native Calls
  // ===========================================================

  Future<void> _notifyNativeServiceReady() async {
    await _invokeNativeMethod(
      'initializeBackgroundCallService',
      <String, dynamic>{
        'supportsVideo': true,
        'incomingTimeoutSeconds': _defaultIncomingCallTimeout.inSeconds,
      },
    );
  }

  Future<Object?> _invokeNativeMethod(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (kIsWeb || _isDisposed) {
      return null;
    }

    try {
      return await _platformChannel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      debugPrint(
        'JR CALL: Native background-call implementation '
        'is not connected for this platform.',
      );

      return null;
    } on PlatformException catch (error, stackTrace) {
      _reportError('Native method $method', error, stackTrace);

      return null;
    }
  }

  // ===========================================================
  // Action / Concurrency Protection
  // ===========================================================

  bool _beginAction(String callId) {
    final normalizedCallId = callId.trim();

    if (_isDisposed || normalizedCallId.isEmpty) {
      return false;
    }

    if (_activeActionCallId != null) {
      return false;
    }

    _activeActionCallId = normalizedCallId;

    return true;
  }

  void _endAction(String callId) {
    if (_activeActionCallId == callId.trim()) {
      _activeActionCallId = null;
    }
  }

  void _markCallCompleted(String callId) {
    final normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      return;
    }

    _lastCompletedCallId = normalizedCallId;
  }

  String? _resolveActionCallId(String? callId) {
    final normalizedCallId = _readOptionalString(callId);

    return normalizedCallId ??
        _pendingCall?.callId ??
        _callService.currentCallId;
  }

  bool _isSessionCurrent(int sessionToken) {
    return !_isDisposed && sessionToken == _sessionGeneration;
  }

  // ===========================================================
  // Pending Call Cleanup
  // ===========================================================

  Future<void> _clearPendingCall({required bool dismissNativeUi}) async {
    final callId = _pendingCall?.callId;

    _sessionGeneration++;

    _cancelIncomingCallTimeout();

    _pendingCall = null;

    _lastPresentedCallId = null;

    _isShowingIncomingCall = false;

    if (dismissNativeUi && callId != null) {
      await _invokeNativeMethod('dismissIncomingCall', <String, dynamic>{
        'callId': callId,
      });
    }
  }

  void reset() {
    _sessionGeneration++;

    _cancelIncomingCallTimeout();

    _pendingCall = null;

    _lastPresentedCallId = null;

    _lastCompletedCallId = null;

    _activeActionCallId = null;

    _isShowingIncomingCall = false;
  }

  // ===========================================================
  // Helpers
  // ===========================================================

  void _emitEvent(BackgroundCallEvent event) {
    if (_isDisposed || _eventController.isClosed) {
      return;
    }

    _eventController.add(event);
  }

  Map<String, dynamic> _normalizeArguments(Object? arguments) {
    if (arguments is Map<String, dynamic>) {
      return Map<String, dynamic>.from(arguments);
    }

    if (arguments is Map) {
      final normalized = <String, dynamic>{};

      for (final entry in arguments.entries) {
        normalized[entry.key.toString()] = entry.value;
      }

      return normalized;
    }

    return <String, dynamic>{};
  }

  String _readCallIdSafely(Map<String, dynamic> map) {
    return _readOptionalString(map['callId']) ?? '';
  }

  String? _readOptionalString(Object? value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint(
      'JR CALL BackgroundCallService '
      '[$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL BackgroundCallService [$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // Dispose
  // ===========================================================

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    WidgetsBinding.instance.removeObserver(this);

    _platformChannel.setMethodCallHandler(null);

    _sessionGeneration++;

    _cancelIncomingCallTimeout();

    _pendingCall = null;
    _lastPresentedCallId = null;
    _lastCompletedCallId = null;
    _activeActionCallId = null;
    _isShowingIncomingCall = false;

    if (!_eventController.isClosed) {
      await _eventController.close();
    }

    _isInitialized = false;
    _initializationFuture = null;

    debugPrint('JR CALL: BackgroundCallService disposed.');
  }
}
