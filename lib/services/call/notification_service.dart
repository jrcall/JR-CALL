import 'dart:async';

/// ===========================================================
/// JR CALL
/// File: notification_service.dart
/// Location: lib/services/call/notification_service.dart
///
/// Description:
/// JR CALL-এর centralized Call Notification Coordinator.
///
/// এই service-এর দায়িত্ব:
/// - Incoming call notification state
/// - Outgoing call notification state
/// - Connected call notification state
/// - Missed call notification state
/// - Rejected / Cancelled / Failed notification state
/// - Network lost / recovered call notification state
/// - Duplicate notification protection
/// - Notification action handling
/// - Automatic expiration
/// - Safe stream lifecycle
///
/// গুরুত্বপূর্ণ:
/// এই file CallService/WebRTC/Signaling logic পরিবর্তন করে না।
/// এটি শুধুমাত্র notification state-এর centralized owner.
///
/// Native Android/iOS tray notification বা background push
/// পরবর্তীতে FCM/native notification layer-এর সাথে এই service
/// connect করতে পারবে।
///
/// কোনো fake OTP, authentication বা Firestore ownership
/// এই service-এর ভিতরে নেই.
/// ===========================================================

/// ===========================================================
/// Notification Type
/// ===========================================================

enum CallNotificationType {
  incoming,
  outgoing,
  connecting,
  connected,
  missed,
  rejected,
  cancelled,
  ended,
  failed,
  networkLost,
  networkRecovered,
}

/// ===========================================================
/// Notification Action
/// ===========================================================

enum CallNotificationAction { answer, reject, cancel, open, dismiss }

/// ===========================================================
/// Immutable Notification Model
/// ===========================================================

class CallNotification {
  final String id;
  final String callId;

  final CallNotificationType type;

  final String title;
  final String body;

  final String? peerId;
  final String? peerName;
  final String? peerPhotoUrl;

  final bool isVideoCall;
  final bool isIncoming;

  final DateTime createdAt;
  final DateTime? expiresAt;

  final Map<String, dynamic> data;

  const CallNotification({
    required this.id,
    required this.callId,
    required this.type,
    required this.title,
    required this.body,
    required this.isVideoCall,
    required this.isIncoming,
    required this.createdAt,
    this.peerId,
    this.peerName,
    this.peerPhotoUrl,
    this.expiresAt,
    this.data = const <String, dynamic>{},
  });

  /// ---------------------------------------------------------
  /// Notification expire হয়েছে কি না
  /// ---------------------------------------------------------

  bool get isExpired {
    final expiry = expiresAt;

    if (expiry == null) {
      return false;
    }

    return DateTime.now().isAfter(expiry);
  }

  /// ---------------------------------------------------------
  /// Existing notification safely modify করার জন্য copyWith
  /// ---------------------------------------------------------

  CallNotification copyWith({
    String? id,
    String? callId,
    CallNotificationType? type,
    String? title,
    String? body,
    String? peerId,
    String? peerName,
    String? peerPhotoUrl,
    bool? isVideoCall,
    bool? isIncoming,
    DateTime? createdAt,
    DateTime? expiresAt,
    Map<String, dynamic>? data,
  }) {
    return CallNotification(
      id: id ?? this.id,
      callId: callId ?? this.callId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      peerPhotoUrl: peerPhotoUrl ?? this.peerPhotoUrl,
      isVideoCall: isVideoCall ?? this.isVideoCall,
      isIncoming: isIncoming ?? this.isIncoming,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      data: data ?? this.data,
    );
  }
}

/// ===========================================================
/// Notification Action Event
/// ===========================================================

class CallNotificationActionEvent {
  final String callId;
  final CallNotificationAction action;
  final DateTime timestamp;

  const CallNotificationActionEvent({
    required this.callId,
    required this.action,
    required this.timestamp,
  });
}

/// ===========================================================
/// Notification Service
/// ===========================================================

class NotificationService {
  /// ---------------------------------------------------------
  /// Singleton
  /// ---------------------------------------------------------

  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();

  /// ---------------------------------------------------------
  /// Incoming call notification maximum waiting time
  ///
  /// CallService-এর 45-second timeout-এর সাথে safe alignment।
  /// ---------------------------------------------------------

  static const Duration incomingNotificationTimeout = Duration(seconds: 45);

  /// ---------------------------------------------------------
  /// Active notification memory
  ///
  /// callId দিয়ে notification track করা হয়।
  /// একই call-এর duplicate notification তৈরি হতে দেওয়া হয় না।
  /// ---------------------------------------------------------

  final Map<String, CallNotification> _activeNotifications =
      <String, CallNotification>{};

  /// ---------------------------------------------------------
  /// Expiry timers
  /// ---------------------------------------------------------

  final Map<String, Timer> _expiryTimers = <String, Timer>{};

  /// ---------------------------------------------------------
  /// Notification State Stream
  ///
  /// UI / IncomingCallScreen / HomeScreen এই stream listen
  /// করতে পারবে।
  /// ---------------------------------------------------------

  final StreamController<List<CallNotification>> _notificationController =
      StreamController<List<CallNotification>>.broadcast();

  /// ---------------------------------------------------------
  /// Notification Action Stream
  ///
  /// Answer / Reject / Cancel action centralizedভাবে
  /// CallService বা UI consume করতে পারবে।
  /// ---------------------------------------------------------

  final StreamController<CallNotificationActionEvent> _actionController =
      StreamController<CallNotificationActionEvent>.broadcast();

  bool _disposed = false;

  /// =========================================================
  /// Public Streams
  /// =========================================================

  Stream<List<CallNotification>> get notificationStream =>
      _notificationController.stream;

  Stream<CallNotificationActionEvent> get actionStream =>
      _actionController.stream;

  /// =========================================================
  /// Active Notifications
  /// =========================================================

  List<CallNotification> get activeNotifications {
    _removeExpiredSilently();

    final notifications = _activeNotifications.values.toList(growable: false);

    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return List<CallNotification>.unmodifiable(notifications);
  }

  /// =========================================================
  /// Incoming Call
  /// =========================================================

  Future<void> showIncomingCall({
    required String callId,
    required String callerId,
    String? callerName,
    String? callerPhotoUrl,
    bool isVideoCall = false,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) async {
    _ensureAlive();

    final normalizedCallId = _requiredValue(callId, 'callId');

    final normalizedCallerId = _requiredValue(callerId, 'callerId');

    final displayName = _displayName(callerName, fallback: 'JR CALL User');

    final now = DateTime.now();

    final notification = CallNotification(
      id: _notificationId(normalizedCallId, CallNotificationType.incoming),
      callId: normalizedCallId,
      type: CallNotificationType.incoming,
      title: isVideoCall ? 'Incoming Video Call' : 'Incoming Voice Call',
      body: '$displayName is calling you',
      peerId: normalizedCallerId,
      peerName: _nullableTrim(callerName),
      peerPhotoUrl: _nullableTrim(callerPhotoUrl),
      isVideoCall: isVideoCall,
      isIncoming: true,
      createdAt: now,
      expiresAt: now.add(incomingNotificationTimeout),
      data: Map<String, dynamic>.unmodifiable(<String, dynamic>{
        ...data,
        'callId': normalizedCallId,
        'callerId': normalizedCallerId,
        'isVideoCall': isVideoCall,
      }),
    );

    _upsert(notification);

    _scheduleExpiry(normalizedCallId, incomingNotificationTimeout);
  }

  /// =========================================================
  /// Outgoing Call
  /// =========================================================

  Future<void> showOutgoingCall({
    required String callId,
    required String receiverId,
    String? receiverName,
    String? receiverPhotoUrl,
    bool isVideoCall = false,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) async {
    _ensureAlive();

    final normalizedCallId = _requiredValue(callId, 'callId');

    final normalizedReceiverId = _requiredValue(receiverId, 'receiverId');

    final displayName = _displayName(receiverName, fallback: 'JR CALL User');

    final notification = CallNotification(
      id: _notificationId(normalizedCallId, CallNotificationType.outgoing),
      callId: normalizedCallId,
      type: CallNotificationType.outgoing,
      title: isVideoCall ? 'Video Calling' : 'Voice Calling',
      body: 'Calling $displayName…',
      peerId: normalizedReceiverId,
      peerName: _nullableTrim(receiverName),
      peerPhotoUrl: _nullableTrim(receiverPhotoUrl),
      isVideoCall: isVideoCall,
      isIncoming: false,
      createdAt: DateTime.now(),
      data: Map<String, dynamic>.unmodifiable(<String, dynamic>{
        ...data,
        'callId': normalizedCallId,
        'receiverId': normalizedReceiverId,
        'isVideoCall': isVideoCall,
      }),
    );

    _upsert(notification);
  }

  /// =========================================================
  /// Connecting
  /// =========================================================

  Future<void> showConnecting({required String callId}) async {
    _ensureAlive();

    final existing = _find(callId);

    if (existing == null) {
      return;
    }

    _upsert(
      existing.copyWith(
        id: _notificationId(existing.callId, CallNotificationType.connecting),
        type: CallNotificationType.connecting,
        title: 'Connecting',
        body: 'Securing your JR CALL connection…',
      ),
    );
  }

  /// =========================================================
  /// Connected
  /// =========================================================

  Future<void> showConnected({required String callId}) async {
    _ensureAlive();

    final existing = _find(callId);

    if (existing == null) {
      return;
    }

    _cancelExpiry(callId);

    final peerName = _displayName(existing.peerName, fallback: 'JR CALL User');

    _upsert(
      existing.copyWith(
        id: _notificationId(existing.callId, CallNotificationType.connected),
        type: CallNotificationType.connected,
        title: existing.isVideoCall
            ? 'Video Call Connected'
            : 'Voice Call Connected',
        body: 'Connected with $peerName',
        expiresAt: null,
      ),
    );
  }

  /// =========================================================
  /// Missed Call
  /// =========================================================

  Future<void> showMissedCall({
    required String callId,
    String? callerId,
    String? callerName,
    String? callerPhotoUrl,
    bool isVideoCall = false,
  }) async {
    _ensureAlive();

    final normalizedCallId = _requiredValue(callId, 'callId');

    _cancelExpiry(normalizedCallId);

    final displayName = _displayName(callerName, fallback: 'JR CALL User');

    final notification = CallNotification(
      id: _notificationId(normalizedCallId, CallNotificationType.missed),
      callId: normalizedCallId,
      type: CallNotificationType.missed,
      title: 'Missed Call',
      body: 'Missed call from $displayName',
      peerId: _nullableTrim(callerId),
      peerName: _nullableTrim(callerName),
      peerPhotoUrl: _nullableTrim(callerPhotoUrl),
      isVideoCall: isVideoCall,
      isIncoming: true,
      createdAt: DateTime.now(),
    );

    _upsert(notification);
  }

  /// =========================================================
  /// Rejected
  /// =========================================================

  Future<void> showRejected({required String callId}) async {
    await _replaceCallStatus(
      callId: callId,
      type: CallNotificationType.rejected,
      title: 'Call Rejected',
      body: 'The call was rejected.',
    );
  }

  /// =========================================================
  /// Cancelled
  /// =========================================================

  Future<void> showCancelled({required String callId}) async {
    await _replaceCallStatus(
      callId: callId,
      type: CallNotificationType.cancelled,
      title: 'Call Cancelled',
      body: 'The call was cancelled.',
    );
  }

  /// =========================================================
  /// Call Ended
  /// =========================================================

  Future<void> showCallEnded({
    required String callId,
    Duration? duration,
  }) async {
    final durationText = duration == null
        ? 'Call ended.'
        : 'Call ended • ${_formatDuration(duration)}';

    await _replaceCallStatus(
      callId: callId,
      type: CallNotificationType.ended,
      title: 'Call Ended',
      body: durationText,
    );
  }

  /// =========================================================
  /// Call Failed
  /// =========================================================

  Future<void> showCallFailed({required String callId, String? reason}) async {
    await _replaceCallStatus(
      callId: callId,
      type: CallNotificationType.failed,
      title: 'Call Failed',
      body:
          _nullableTrim(reason) ??
          'JR CALL could not establish the connection.',
    );
  }

  /// =========================================================
  /// Network Lost
  /// =========================================================

  Future<void> showNetworkLost({required String callId}) async {
    await _replaceCallStatus(
      callId: callId,
      type: CallNotificationType.networkLost,
      title: 'Connection Interrupted',
      body: 'Network lost. JR CALL is trying to reconnect…',
      cancelExpiry: false,
    );
  }

  /// =========================================================
  /// Network Recovered
  /// =========================================================

  Future<void> showNetworkRecovered({required String callId}) async {
    await _replaceCallStatus(
      callId: callId,
      type: CallNotificationType.networkRecovered,
      title: 'Connection Restored',
      body: 'JR CALL connection has been restored.',
      cancelExpiry: false,
    );
  }

  /// =========================================================
  /// Notification Actions
  /// =========================================================

  void answer(String callId) {
    _emitAction(callId, CallNotificationAction.answer);
  }

  void reject(String callId) {
    _emitAction(callId, CallNotificationAction.reject);
  }

  void cancel(String callId) {
    _emitAction(callId, CallNotificationAction.cancel);
  }

  void open(String callId) {
    _emitAction(callId, CallNotificationAction.open);
  }

  void dismissAction(String callId) {
    _emitAction(callId, CallNotificationAction.dismiss);

    dismiss(callId);
  }

  /// =========================================================
  /// Dismiss One Notification
  /// =========================================================

  void dismiss(String callId) {
    if (_disposed) {
      return;
    }

    final normalized = callId.trim();

    if (normalized.isEmpty) {
      return;
    }

    _cancelExpiry(normalized);

    final removed = _activeNotifications.remove(normalized);

    if (removed != null) {
      _emitNotifications();
    }
  }

  /// =========================================================
  /// Clear All
  /// =========================================================

  void clearAll() {
    if (_disposed) {
      return;
    }

    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }

    _expiryTimers.clear();
    _activeNotifications.clear();

    _emitNotifications();
  }

  /// =========================================================
  /// Compatibility Aliases
  ///
  /// অন্য file যদি "Notification" suffix method expect করে,
  /// future integration সহজ করার জন্য wrapper রাখা হয়েছে।
  /// =========================================================

  Future<void> showIncomingCallNotification({
    required String callId,
    required String callerId,
    String? callerName,
    String? callerPhotoUrl,
    bool isVideoCall = false,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    return showIncomingCall(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      callerPhotoUrl: callerPhotoUrl,
      isVideoCall: isVideoCall,
      data: data,
    );
  }

  Future<void> showOutgoingCallNotification({
    required String callId,
    required String receiverId,
    String? receiverName,
    String? receiverPhotoUrl,
    bool isVideoCall = false,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    return showOutgoingCall(
      callId: callId,
      receiverId: receiverId,
      receiverName: receiverName,
      receiverPhotoUrl: receiverPhotoUrl,
      isVideoCall: isVideoCall,
      data: data,
    );
  }

  Future<void> showMissedCallNotification({
    required String callId,
    String? callerId,
    String? callerName,
    String? callerPhotoUrl,
    bool isVideoCall = false,
  }) {
    return showMissedCall(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      callerPhotoUrl: callerPhotoUrl,
      isVideoCall: isVideoCall,
    );
  }

  Future<void> cancelNotification(String callId) async {
    dismiss(callId);
  }

  Future<void> cancelAllNotifications() async {
    clearAll();
  }

  /// =========================================================
  /// Internal Status Update
  /// =========================================================

  Future<void> _replaceCallStatus({
    required String callId,
    required CallNotificationType type,
    required String title,
    required String body,
    bool cancelExpiry = true,
  }) async {
    _ensureAlive();

    final normalizedCallId = _requiredValue(callId, 'callId');

    if (cancelExpiry) {
      _cancelExpiry(normalizedCallId);
    }

    final existing = _activeNotifications[normalizedCallId];

    if (existing != null) {
      _upsert(
        existing.copyWith(
          id: _notificationId(normalizedCallId, type),
          type: type,
          title: title,
          body: body,
          expiresAt: null,
        ),
      );

      return;
    }

    _upsert(
      CallNotification(
        id: _notificationId(normalizedCallId, type),
        callId: normalizedCallId,
        type: type,
        title: title,
        body: body,
        isVideoCall: false,
        isIncoming: false,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// =========================================================
  /// Internal Action Emitter
  /// =========================================================

  void _emitAction(String callId, CallNotificationAction action) {
    if (_disposed) {
      return;
    }

    final normalized = callId.trim();

    if (normalized.isEmpty) {
      return;
    }

    _actionController.add(
      CallNotificationActionEvent(
        callId: normalized,
        action: action,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// =========================================================
  /// Insert / Replace
  /// =========================================================

  void _upsert(CallNotification notification) {
    if (_disposed) {
      return;
    }

    _activeNotifications[notification.callId] = notification;

    _emitNotifications();
  }

  /// =========================================================
  /// Find
  /// =========================================================

  CallNotification? _find(String callId) {
    final normalized = callId.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return _activeNotifications[normalized];
  }

  /// =========================================================
  /// Expiry
  /// =========================================================

  void _scheduleExpiry(String callId, Duration duration) {
    _cancelExpiry(callId);

    _expiryTimers[callId] = Timer(duration, () {
      _expiryTimers.remove(callId);

      final notification = _activeNotifications[callId];

      if (notification == null) {
        return;
      }

      if (notification.type == CallNotificationType.incoming) {
        _activeNotifications.remove(callId);

        _emitNotifications();
      }
    });
  }

  void _cancelExpiry(String callId) {
    final timer = _expiryTimers.remove(callId.trim());

    timer?.cancel();
  }

  void _removeExpiredSilently() {
    final expiredCallIds = <String>[];

    for (final entry in _activeNotifications.entries) {
      if (entry.value.isExpired) {
        expiredCallIds.add(entry.key);
      }
    }

    for (final callId in expiredCallIds) {
      _activeNotifications.remove(callId);
      _cancelExpiry(callId);
    }
  }

  /// =========================================================
  /// State Broadcast
  /// =========================================================

  void _emitNotifications() {
    if (_disposed) {
      return;
    }

    _removeExpiredSilently();

    final current = _activeNotifications.values.toList();

    current.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _notificationController.add(List<CallNotification>.unmodifiable(current));
  }

  /// =========================================================
  /// Helpers
  /// =========================================================

  String _notificationId(String callId, CallNotificationType type) {
    return 'jr_call_${type.name}_$callId';
  }

  String _requiredValue(String value, String fieldName) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        fieldName,
        '$fieldName cannot be empty.',
      );
    }

    return normalized;
  }

  String? _nullableTrim(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  String _displayName(String? value, {required String fallback}) {
    return _nullableTrim(value) ?? fallback;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;

    final hours = totalSeconds ~/ 3600;

    final minutes = (totalSeconds % 3600) ~/ 60;

    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('NotificationService has already been disposed.');
    }
  }

  /// =========================================================
  /// Dispose
  ///
  /// সাধারণ application runtime-এ singleton dispose করার
  /// প্রয়োজন নেই। Test/app final shutdown-এর জন্য রাখা হয়েছে।
  /// =========================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }

    _expiryTimers.clear();
    _activeNotifications.clear();

    await _notificationController.close();
    await _actionController.close();
  }
}
