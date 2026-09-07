import 'dart:async';

import 'package:flutter/foundation.dart';

/// ===========================================================
/// JR CALL
/// File: notification_service.dart
/// Location: lib/services/call/notification_service.dart
///
/// MASTER PRODUCTION CALL NOTIFICATION COORDINATOR
///
/// RESPONSIBILITIES:
///
/// - Incoming-call notification state.
/// - Outgoing-call notification state.
/// - Connecting / connected notification state.
/// - Missed / rejected / cancelled / ended / failed state.
/// - Network lost / recovered notification state.
/// - Duplicate notification protection.
/// - Notification action events.
/// - Incoming notification presentation expiry.
/// - Locale-ready notification text coordination.
/// - Safe stream lifecycle.
///
/// OWNERSHIP:
///
/// NotificationService:
/// - Notification presentation state.
/// - Notification action event emission.
/// - Localization resource metadata.
///
/// CallService:
/// - Actual call lifecycle.
/// - Answer / reject / cancel execution.
///
/// WebRTCService:
/// - Media / PeerConnection.
///
/// SignalingService:
/// - Signaling / Firestore call state.
///
/// Localization layer:
/// - Actual translated strings for supported locales.
///
/// Native FCM / platform notification layer:
/// - Android/iOS system notification delivery.
///
/// IMPORTANT:
///
/// - This service does NOT send SMS.
/// - This service does NOT own FCM delivery.
/// - Notification expiry does NOT end a call.
/// - Notification actions do NOT directly mutate call state.
/// - No WebRTC / signaling / ICE / recovery ownership.
/// ===========================================================

// =============================================================
// NOTIFICATION TYPE
// =============================================================

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

// =============================================================
// NOTIFICATION ACTION
// =============================================================

enum CallNotificationAction {
  answer,
  reject,
  cancel,
  open,
  dismiss,
}

// =============================================================
// LOCALIZATION TEXT KEYS
//
// These values are intentionally stable.
//
// Flutter l10n can resolve them for in-app presentation.
// FILE 36 / native FCM integration can map the same resource keys
// to Android/iOS localized notification resources.
// =============================================================

enum CallNotificationTextKey {
  incomingVideoTitle(
    'jr_call_incoming_video_title',
  ),

  incomingVoiceTitle(
    'jr_call_incoming_voice_title',
  ),

  incomingBody(
    'jr_call_incoming_body',
  ),

  outgoingVideoTitle(
    'jr_call_outgoing_video_title',
  ),

  outgoingVoiceTitle(
    'jr_call_outgoing_voice_title',
  ),

  outgoingBody(
    'jr_call_outgoing_body',
  ),

  connectingTitle(
    'jr_call_connecting_title',
  ),

  connectingBody(
    'jr_call_connecting_body',
  ),

  connectedVideoTitle(
    'jr_call_connected_video_title',
  ),

  connectedVoiceTitle(
    'jr_call_connected_voice_title',
  ),

  connectedBody(
    'jr_call_connected_body',
  ),

  missedTitle(
    'jr_call_missed_title',
  ),

  missedBody(
    'jr_call_missed_body',
  ),

  rejectedTitle(
    'jr_call_rejected_title',
  ),

  rejectedBody(
    'jr_call_rejected_body',
  ),

  cancelledTitle(
    'jr_call_cancelled_title',
  ),

  cancelledBody(
    'jr_call_cancelled_body',
  ),

  endedTitle(
    'jr_call_ended_title',
  ),

  endedBody(
    'jr_call_ended_body',
  ),

  endedWithDurationBody(
    'jr_call_ended_with_duration_body',
  ),

  failedTitle(
    'jr_call_failed_title',
  ),

  failedBody(
    'jr_call_failed_body',
  ),

  failedReasonBody(
    'jr_call_failed_reason_body',
  ),

  networkLostTitle(
    'jr_call_network_lost_title',
  ),

  networkLostBody(
    'jr_call_network_lost_body',
  ),

  networkRecoveredTitle(
    'jr_call_network_recovered_title',
  ),

  networkRecoveredBody(
    'jr_call_network_recovered_body',
  );

  const CallNotificationTextKey(
      this.resourceKey,
      );

  final String resourceKey;
}

// =============================================================
// LOCALIZATION RESOLVER
//
// The application localization layer can bind one resolver.
// The resolver must use the CURRENT selected app/user locale.
//
// Returning an empty string or throwing never breaks a call;
// NotificationService falls back to English.
// =============================================================

typedef CallNotificationTextResolver =
String Function(
    CallNotificationTextKey key,
    Map<String, String> arguments,
    );

// =============================================================
// IMMUTABLE NOTIFICATION MODEL
// =============================================================

@immutable
class CallNotification {
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
    this.titleTextKey,
    this.bodyTextKey,
    this.titleLocalizationArgs =
    const <String>[],
    this.bodyLocalizationArgs =
    const <String>[],
    this.textArguments =
    const <String, String>{},
    this.data =
    const <String, dynamic>{},
  });

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

  /// Flutter/in-app localization key.
  final CallNotificationTextKey?
  titleTextKey;

  /// Flutter/in-app localization key.
  final CallNotificationTextKey?
  bodyTextKey;

  /// Ordered arguments suitable for a future native
  /// title_loc_args equivalent.
  final List<String>
  titleLocalizationArgs;

  /// Ordered arguments suitable for a future native
  /// body_loc_args equivalent.
  final List<String>
  bodyLocalizationArgs;

  /// Named arguments used by the application localization resolver.
  final Map<String, String>
  textArguments;

  final Map<String, dynamic> data;

  // ===========================================================
  // LOCALIZATION RESOURCE METADATA
  // ===========================================================

  String? get titleLocalizationKey =>
      titleTextKey?.resourceKey;

  String? get bodyLocalizationKey =>
      bodyTextKey?.resourceKey;

  // ===========================================================
  // EXPIRY
  // ===========================================================

  bool get isExpired {
    final DateTime? expiry =
        expiresAt;

    if (expiry == null) {
      return false;
    }

    return !DateTime.now().isBefore(
      expiry,
    );
  }

  // ===========================================================
  // COPY
  //
  // clearExpiresAt solves an important nullable-copy problem:
  //
  // expiresAt: null normally means "parameter not supplied".
  // Therefore callers need an explicit way to remove expiry.
  // ===========================================================

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
    bool clearExpiresAt = false,
    CallNotificationTextKey?
    titleTextKey,
    CallNotificationTextKey?
    bodyTextKey,
    List<String>?
    titleLocalizationArgs,
    List<String>?
    bodyLocalizationArgs,
    Map<String, String>?
    textArguments,
    Map<String, dynamic>? data,
  }) {
    return CallNotification(
      id:
      id ??
          this.id,
      callId:
      callId ??
          this.callId,
      type:
      type ??
          this.type,
      title:
      title ??
          this.title,
      body:
      body ??
          this.body,
      peerId:
      peerId ??
          this.peerId,
      peerName:
      peerName ??
          this.peerName,
      peerPhotoUrl:
      peerPhotoUrl ??
          this.peerPhotoUrl,
      isVideoCall:
      isVideoCall ??
          this.isVideoCall,
      isIncoming:
      isIncoming ??
          this.isIncoming,
      createdAt:
      createdAt ??
          this.createdAt,
      expiresAt: clearExpiresAt
          ? null
          : expiresAt ??
          this.expiresAt,
      titleTextKey:
      titleTextKey ??
          this.titleTextKey,
      bodyTextKey:
      bodyTextKey ??
          this.bodyTextKey,
      titleLocalizationArgs:
      titleLocalizationArgs ??
          this.titleLocalizationArgs,
      bodyLocalizationArgs:
      bodyLocalizationArgs ??
          this.bodyLocalizationArgs,
      textArguments:
      textArguments ??
          this.textArguments,
      data:
      data ??
          this.data,
    );
  }
}

// =============================================================
// NOTIFICATION ACTION EVENT
// =============================================================

@immutable
class CallNotificationActionEvent {
  const CallNotificationActionEvent({
    required this.callId,
    required this.action,
    required this.timestamp,
  });

  final String callId;

  final CallNotificationAction action;

  final DateTime timestamp;
}

// =============================================================
// NOTIFICATION SERVICE
// =============================================================

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance =
  NotificationService._internal();

  // ===========================================================
  // PRESENTATION TIMEOUT
  //
  // IMPORTANT:
  //
  // This ONLY expires the incoming-notification presentation.
  // It never ends the actual call.
  // ===========================================================

  static const Duration
  incomingNotificationTimeout =
  Duration(
    seconds: 45,
  );

  // ===========================================================
  // ACTIVE STATE
  // ===========================================================

  final Map<String, CallNotification>
  _activeNotifications =
  <String, CallNotification>{};

  final Map<String, Timer>
  _expiryTimers =
  <String, Timer>{};

  // ===========================================================
  // STREAMS
  // ===========================================================

  final StreamController<
      List<CallNotification>>
  _notificationController =
  StreamController<
      List<CallNotification>>.broadcast();

  final StreamController<
      CallNotificationActionEvent>
  _actionController =
  StreamController<
      CallNotificationActionEvent>.broadcast();

  // ===========================================================
  // LOCALIZATION
  // ===========================================================

  CallNotificationTextResolver?
  _textResolver;

  bool _disposed = false;

  // ===========================================================
  // PUBLIC STREAMS
  // ===========================================================

  Stream<List<CallNotification>>
  get notificationStream =>
      _notificationController.stream;

  Stream<CallNotificationActionEvent>
  get actionStream =>
      _actionController.stream;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  List<CallNotification>
  get activeNotifications {
    _removeExpiredSilently();

    final List<CallNotification>
    notifications =
    _activeNotifications.values
        .toList(
      growable: false,
    );

    notifications.sort(
          (
          CallNotification a,
          CallNotification b,
          ) =>
          b.createdAt.compareTo(
            a.createdAt,
          ),
    );

    return List<CallNotification>.unmodifiable(
      notifications,
    );
  }

  // ===========================================================
  // LOCALIZATION CONFIGURATION
  // ===========================================================

  void configureLocalization(
      CallNotificationTextResolver resolver,
      ) {
    _ensureAlive();

    _textResolver = resolver;

    _relocalizeActiveNotifications();
  }

  void clearLocalizationResolver() {
    if (_disposed) {
      return;
    }

    if (_textResolver == null) {
      return;
    }

    _textResolver = null;

    _relocalizeActiveNotifications();
  }

  /// Call this after the app changes its selected language
  /// while a call notification is already visible.
  void refreshLocalizedText() {
    if (_disposed) {
      return;
    }

    _relocalizeActiveNotifications();
  }

  // ===========================================================
  // INCOMING CALL
  // ===========================================================

  Future<void> showIncomingCall({
    required String callId,
    required String callerId,
    String? callerName,
    String? callerPhotoUrl,
    bool isVideoCall = false,
    Map<String, dynamic> data =
    const <String, dynamic>{},
  }) async {
    _ensureAlive();

    final String normalizedCallId =
    _requiredValue(
      callId,
      'callId',
    );

    final String normalizedCallerId =
    _requiredValue(
      callerId,
      'callerId',
    );

    final CallNotification?
    existing =
    _activeNotifications[
    normalizedCallId];

    // An initial incoming notification must never resurrect or
    // regress an already advanced notification for the same call.
    if (existing != null &&
        existing.type !=
            CallNotificationType.incoming) {
      return;
    }

    if (existing != null &&
        existing.isExpired) {
      _cancelExpiry(
        normalizedCallId,
      );

      _activeNotifications.remove(
        normalizedCallId,
      );

      _emitNotifications();

      return;
    }

    final String displayName =
    _displayName(
      callerName,
      fallback: 'JR CALL User',
    );

    final CallNotificationTextKey
    titleKey =
    isVideoCall
        ? CallNotificationTextKey
        .incomingVideoTitle
        : CallNotificationTextKey
        .incomingVoiceTitle;

    const CallNotificationTextKey
    bodyKey =
        CallNotificationTextKey
            .incomingBody;

    final Map<String, String>
    arguments =
    Map<String, String>.unmodifiable(
      <String, String>{
        'peerName': displayName,
      },
    );

    // Duplicate incoming event:
    // preserve original creation/expiry time instead of granting
    // the same call another 45-second presentation window.
    if (existing != null) {
      final CallNotification updated =
      existing.copyWith(
        title: _localizedText(
          titleKey,
          arguments,
        ),
        body: _localizedText(
          bodyKey,
          arguments,
        ),
        peerId:
        normalizedCallerId,
        peerName:
        _nullableTrim(
          callerName,
        ),
        peerPhotoUrl:
        _nullableTrim(
          callerPhotoUrl,
        ),
        isVideoCall:
        isVideoCall,
        isIncoming:
        true,
        titleTextKey:
        titleKey,
        bodyTextKey:
        bodyKey,
        titleLocalizationArgs:
        const <String>[],
        bodyLocalizationArgs:
        List<String>.unmodifiable(
          <String>[
            displayName,
          ],
        ),
        textArguments:
        arguments,
        data:
        _buildData(
          data,
          <String, dynamic>{
            'callId':
            normalizedCallId,
            'callerId':
            normalizedCallerId,
            'isVideoCall':
            isVideoCall,
          },
        ),
      );

      _upsert(
        updated,
      );

      final DateTime? expiry =
          updated.expiresAt;

      if (expiry != null &&
          !_expiryTimers.containsKey(
            normalizedCallId,
          )) {
        _scheduleExpiryUntil(
          normalizedCallId,
          expiry,
        );
      }

      return;
    }

    final DateTime now =
    DateTime.now();

    final DateTime expiresAt =
    now.add(
      incomingNotificationTimeout,
    );

    final CallNotification notification =
    CallNotification(
      id: _notificationId(
        normalizedCallId,
        CallNotificationType.incoming,
      ),
      callId:
      normalizedCallId,
      type:
      CallNotificationType.incoming,
      title:
      _localizedText(
        titleKey,
        arguments,
      ),
      body:
      _localizedText(
        bodyKey,
        arguments,
      ),
      peerId:
      normalizedCallerId,
      peerName:
      _nullableTrim(
        callerName,
      ),
      peerPhotoUrl:
      _nullableTrim(
        callerPhotoUrl,
      ),
      isVideoCall:
      isVideoCall,
      isIncoming:
      true,
      createdAt:
      now,
      expiresAt:
      expiresAt,
      titleTextKey:
      titleKey,
      bodyTextKey:
      bodyKey,
      bodyLocalizationArgs:
      List<String>.unmodifiable(
        <String>[
          displayName,
        ],
      ),
      textArguments:
      arguments,
      data:
      _buildData(
        data,
        <String, dynamic>{
          'callId':
          normalizedCallId,
          'callerId':
          normalizedCallerId,
          'isVideoCall':
          isVideoCall,
        },
      ),
    );

    _upsert(
      notification,
    );

    _scheduleExpiryUntil(
      normalizedCallId,
      expiresAt,
    );
  }

  // ===========================================================
  // OUTGOING CALL
  // ===========================================================

  Future<void> showOutgoingCall({
    required String callId,
    required String receiverId,
    String? receiverName,
    String? receiverPhotoUrl,
    bool isVideoCall = false,
    Map<String, dynamic> data =
    const <String, dynamic>{},
  }) async {
    _ensureAlive();

    final String normalizedCallId =
    _requiredValue(
      callId,
      'callId',
    );

    final String normalizedReceiverId =
    _requiredValue(
      receiverId,
      'receiverId',
    );

    final CallNotification?
    existing =
    _activeNotifications[
    normalizedCallId];

    // Prevent delayed duplicate signaling from regressing
    // connecting/connected/terminal presentation state.
    if (existing != null &&
        existing.type !=
            CallNotificationType.outgoing) {
      return;
    }

    final String displayName =
    _displayName(
      receiverName,
      fallback: 'JR CALL User',
    );

    final CallNotificationTextKey
    titleKey =
    isVideoCall
        ? CallNotificationTextKey
        .outgoingVideoTitle
        : CallNotificationTextKey
        .outgoingVoiceTitle;

    const CallNotificationTextKey
    bodyKey =
        CallNotificationTextKey
            .outgoingBody;

    final Map<String, String>
    arguments =
    Map<String, String>.unmodifiable(
      <String, String>{
        'peerName':
        displayName,
      },
    );

    final DateTime createdAt =
        existing?.createdAt ??
            DateTime.now();

    final CallNotification notification =
    CallNotification(
      id:
      _notificationId(
        normalizedCallId,
        CallNotificationType.outgoing,
      ),
      callId:
      normalizedCallId,
      type:
      CallNotificationType.outgoing,
      title:
      _localizedText(
        titleKey,
        arguments,
      ),
      body:
      _localizedText(
        bodyKey,
        arguments,
      ),
      peerId:
      normalizedReceiverId,
      peerName:
      _nullableTrim(
        receiverName,
      ),
      peerPhotoUrl:
      _nullableTrim(
        receiverPhotoUrl,
      ),
      isVideoCall:
      isVideoCall,
      isIncoming:
      false,
      createdAt:
      createdAt,
      titleTextKey:
      titleKey,
      bodyTextKey:
      bodyKey,
      bodyLocalizationArgs:
      List<String>.unmodifiable(
        <String>[
          displayName,
        ],
      ),
      textArguments:
      arguments,
      data:
      _buildData(
        data,
        <String, dynamic>{
          'callId':
          normalizedCallId,
          'receiverId':
          normalizedReceiverId,
          'isVideoCall':
          isVideoCall,
        },
      ),
    );

    _upsert(
      notification,
    );
  }

  // ===========================================================
  // CONNECTING
  // ===========================================================

  Future<void> showConnecting({
    required String callId,
  }) async {
    _ensureAlive();

    final CallNotification? existing =
    _find(
      callId,
    );

    if (existing == null ||
        _isTerminalType(
          existing.type,
        )) {
      return;
    }

    // A delayed connecting event must not regress an already
    // connected/recovering call presentation.
    if (existing.type ==
        CallNotificationType.connected ||
        existing.type ==
            CallNotificationType.networkLost ||
        existing.type ==
            CallNotificationType.networkRecovered) {
      return;
    }

    _cancelExpiry(
      existing.callId,
    );

    const CallNotificationTextKey
    titleKey =
        CallNotificationTextKey
            .connectingTitle;

    const CallNotificationTextKey
    bodyKey =
        CallNotificationTextKey
            .connectingBody;

    const Map<String, String>
    arguments =
    <String, String>{};

    _upsert(
      existing.copyWith(
        id:
        _notificationId(
          existing.callId,
          CallNotificationType.connecting,
        ),
        type:
        CallNotificationType.connecting,
        title:
        _localizedText(
          titleKey,
          arguments,
        ),
        body:
        _localizedText(
          bodyKey,
          arguments,
        ),
        clearExpiresAt:
        true,
        titleTextKey:
        titleKey,
        bodyTextKey:
        bodyKey,
        titleLocalizationArgs:
        const <String>[],
        bodyLocalizationArgs:
        const <String>[],
        textArguments:
        arguments,
      ),
    );
  }

  // ===========================================================
  // CONNECTED
  // ===========================================================

  Future<void> showConnected({
    required String callId,
  }) async {
    _ensureAlive();

    final CallNotification? existing =
    _find(
      callId,
    );

    if (existing == null ||
        _isTerminalType(
          existing.type,
        )) {
      return;
    }

    _cancelExpiry(
      existing.callId,
    );

    final String peerName =
    _displayName(
      existing.peerName,
      fallback: 'JR CALL User',
    );

    final CallNotificationTextKey
    titleKey =
    existing.isVideoCall
        ? CallNotificationTextKey
        .connectedVideoTitle
        : CallNotificationTextKey
        .connectedVoiceTitle;

    const CallNotificationTextKey
    bodyKey =
        CallNotificationTextKey
            .connectedBody;

    final Map<String, String>
    arguments =
    Map<String, String>.unmodifiable(
      <String, String>{
        'peerName':
        peerName,
      },
    );

    _upsert(
      existing.copyWith(
        id:
        _notificationId(
          existing.callId,
          CallNotificationType.connected,
        ),
        type:
        CallNotificationType.connected,
        title:
        _localizedText(
          titleKey,
          arguments,
        ),
        body:
        _localizedText(
          bodyKey,
          arguments,
        ),
        clearExpiresAt:
        true,
        titleTextKey:
        titleKey,
        bodyTextKey:
        bodyKey,
        titleLocalizationArgs:
        const <String>[],
        bodyLocalizationArgs:
        List<String>.unmodifiable(
          <String>[
            peerName,
          ],
        ),
        textArguments:
        arguments,
      ),
    );
  }

  // ===========================================================
  // MISSED CALL
  // ===========================================================

  Future<void> showMissedCall({
    required String callId,
    String? callerId,
    String? callerName,
    String? callerPhotoUrl,
    bool isVideoCall = false,
  }) async {
    _ensureAlive();

    final String normalizedCallId =
    _requiredValue(
      callId,
      'callId',
    );

    final CallNotification?
    existing =
    _activeNotifications[
    normalizedCallId];

    if (existing != null &&
        _isTerminalType(
          existing.type,
        ) &&
        existing.type !=
            CallNotificationType.missed) {
      return;
    }

    _cancelExpiry(
      normalizedCallId,
    );

    final String displayName =
    _displayName(
      callerName ??
          existing?.peerName,
      fallback: 'JR CALL User',
    );

    const CallNotificationTextKey
    titleKey =
        CallNotificationTextKey
            .missedTitle;

    const CallNotificationTextKey
    bodyKey =
        CallNotificationTextKey
            .missedBody;

    final Map<String, String>
    arguments =
    Map<String, String>.unmodifiable(
      <String, String>{
        'peerName':
        displayName,
      },
    );

    final CallNotification notification =
    CallNotification(
      id:
      _notificationId(
        normalizedCallId,
        CallNotificationType.missed,
      ),
      callId:
      normalizedCallId,
      type:
      CallNotificationType.missed,
      title:
      _localizedText(
        titleKey,
        arguments,
      ),
      body:
      _localizedText(
        bodyKey,
        arguments,
      ),
      peerId:
      _nullableTrim(
        callerId,
      ) ??
          existing?.peerId,
      peerName:
      _nullableTrim(
        callerName,
      ) ??
          existing?.peerName,
      peerPhotoUrl:
      _nullableTrim(
        callerPhotoUrl,
      ) ??
          existing?.peerPhotoUrl,
      isVideoCall:
      existing?.isVideoCall ??
          isVideoCall,
      isIncoming:
      true,
      createdAt:
      DateTime.now(),
      titleTextKey:
      titleKey,
      bodyTextKey:
      bodyKey,
      bodyLocalizationArgs:
      List<String>.unmodifiable(
        <String>[
          displayName,
        ],
      ),
      textArguments:
      arguments,
      data:
      existing?.data ??
          const <String, dynamic>{},
    );

    _upsert(
      notification,
    );
  }

  // ===========================================================
  // REJECTED
  // ===========================================================

  Future<void> showRejected({
    required String callId,
  }) {
    return _replaceCallStatus(
      callId:
      callId,
      type:
      CallNotificationType.rejected,
      titleKey:
      CallNotificationTextKey
          .rejectedTitle,
      bodyKey:
      CallNotificationTextKey
          .rejectedBody,
    );
  }

  // ===========================================================
  // CANCELLED
  // ===========================================================

  Future<void> showCancelled({
    required String callId,
  }) {
    return _replaceCallStatus(
      callId:
      callId,
      type:
      CallNotificationType.cancelled,
      titleKey:
      CallNotificationTextKey
          .cancelledTitle,
      bodyKey:
      CallNotificationTextKey
          .cancelledBody,
    );
  }

  // ===========================================================
  // CALL ENDED
  // ===========================================================

  Future<void> showCallEnded({
    required String callId,
    Duration? duration,
  }) {
    if (duration == null) {
      return _replaceCallStatus(
        callId:
        callId,
        type:
        CallNotificationType.ended,
        titleKey:
        CallNotificationTextKey
            .endedTitle,
        bodyKey:
        CallNotificationTextKey
            .endedBody,
      );
    }

    final String formattedDuration =
    _formatDuration(
      duration,
    );

    return _replaceCallStatus(
      callId:
      callId,
      type:
      CallNotificationType.ended,
      titleKey:
      CallNotificationTextKey
          .endedTitle,
      bodyKey:
      CallNotificationTextKey
          .endedWithDurationBody,
      arguments:
      <String, String>{
        'duration':
        formattedDuration,
      },
      bodyLocalizationArgs:
      <String>[
        formattedDuration,
      ],
    );
  }

  // ===========================================================
  // CALL FAILED
  // ===========================================================

  Future<void> showCallFailed({
    required String callId,
    String? reason,
  }) {
    final String? normalizedReason =
    _nullableTrim(
      reason,
    );

    if (normalizedReason == null) {
      return _replaceCallStatus(
        callId:
        callId,
        type:
        CallNotificationType.failed,
        titleKey:
        CallNotificationTextKey
            .failedTitle,
        bodyKey:
        CallNotificationTextKey
            .failedBody,
      );
    }

    return _replaceCallStatus(
      callId:
      callId,
      type:
      CallNotificationType.failed,
      titleKey:
      CallNotificationTextKey
          .failedTitle,
      bodyKey:
      CallNotificationTextKey
          .failedReasonBody,
      arguments:
      <String, String>{
        'reason':
        normalizedReason,
      },
      bodyLocalizationArgs:
      <String>[
        normalizedReason,
      ],
    );
  }

  // ===========================================================
  // NETWORK LOST
  // ===========================================================

  Future<void> showNetworkLost({
    required String callId,
  }) {
    return _replaceCallStatus(
      callId:
      callId,
      type:
      CallNotificationType.networkLost,
      titleKey:
      CallNotificationTextKey
          .networkLostTitle,
      bodyKey:
      CallNotificationTextKey
          .networkLostBody,
    );
  }

  // ===========================================================
  // NETWORK RECOVERED
  // ===========================================================

  Future<void> showNetworkRecovered({
    required String callId,
  }) {
    return _replaceCallStatus(
      callId:
      callId,
      type:
      CallNotificationType.networkRecovered,
      titleKey:
      CallNotificationTextKey
          .networkRecoveredTitle,
      bodyKey:
      CallNotificationTextKey
          .networkRecoveredBody,
    );
  }

  // ===========================================================
  // ACTION EVENTS
  //
  // These events are INTENT only.
  // CallService/UI must execute the real call action.
  // ===========================================================

  void answer(
      String callId,
      ) {
    _emitAction(
      callId,
      CallNotificationAction.answer,
    );
  }

  void reject(
      String callId,
      ) {
    _emitAction(
      callId,
      CallNotificationAction.reject,
    );
  }

  void cancel(
      String callId,
      ) {
    _emitAction(
      callId,
      CallNotificationAction.cancel,
    );
  }

  void open(
      String callId,
      ) {
    _emitAction(
      callId,
      CallNotificationAction.open,
    );
  }

  void dismissAction(
      String callId,
      ) {
    _emitAction(
      callId,
      CallNotificationAction.dismiss,
    );

    dismiss(
      callId,
    );
  }

  // ===========================================================
  // DISMISS ONE
  // ===========================================================

  void dismiss(
      String callId,
      ) {
    if (_disposed) {
      return;
    }

    final String normalized =
    callId.trim();

    if (normalized.isEmpty) {
      return;
    }

    _cancelExpiry(
      normalized,
    );

    final CallNotification?
    removed =
    _activeNotifications.remove(
      normalized,
    );

    if (removed != null) {
      _emitNotifications();
    }
  }

  // ===========================================================
  // CLEAR ALL
  // ===========================================================

  void clearAll() {
    if (_disposed) {
      return;
    }

    for (final Timer timer
    in _expiryTimers.values) {
      timer.cancel();
    }

    _expiryTimers.clear();

    _activeNotifications.clear();

    _emitNotifications();
  }

  // ===========================================================
  // COMPATIBILITY ALIASES
  // ===========================================================

  Future<void>
  showIncomingCallNotification({
    required String callId,
    required String callerId,
    String? callerName,
    String? callerPhotoUrl,
    bool isVideoCall = false,
    Map<String, dynamic> data =
    const <String, dynamic>{},
  }) {
    return showIncomingCall(
      callId:
      callId,
      callerId:
      callerId,
      callerName:
      callerName,
      callerPhotoUrl:
      callerPhotoUrl,
      isVideoCall:
      isVideoCall,
      data:
      data,
    );
  }

  Future<void>
  showOutgoingCallNotification({
    required String callId,
    required String receiverId,
    String? receiverName,
    String? receiverPhotoUrl,
    bool isVideoCall = false,
    Map<String, dynamic> data =
    const <String, dynamic>{},
  }) {
    return showOutgoingCall(
      callId:
      callId,
      receiverId:
      receiverId,
      receiverName:
      receiverName,
      receiverPhotoUrl:
      receiverPhotoUrl,
      isVideoCall:
      isVideoCall,
      data:
      data,
    );
  }

  Future<void>
  showMissedCallNotification({
    required String callId,
    String? callerId,
    String? callerName,
    String? callerPhotoUrl,
    bool isVideoCall = false,
  }) {
    return showMissedCall(
      callId:
      callId,
      callerId:
      callerId,
      callerName:
      callerName,
      callerPhotoUrl:
      callerPhotoUrl,
      isVideoCall:
      isVideoCall,
    );
  }

  Future<void> cancelNotification(
      String callId,
      ) async {
    dismiss(
      callId,
    );
  }

  Future<void>
  cancelAllNotifications() async {
    clearAll();
  }

  // ===========================================================
  // INTERNAL STATUS REPLACEMENT
  // ===========================================================

  Future<void> _replaceCallStatus({
    required String callId,
    required CallNotificationType type,
    required CallNotificationTextKey
    titleKey,
    required CallNotificationTextKey
    bodyKey,
    Map<String, String> arguments =
    const <String, String>{},
    List<String>
    titleLocalizationArgs =
    const <String>[],
    List<String>
    bodyLocalizationArgs =
    const <String>[],
  }) async {
    _ensureAlive();

    final String normalizedCallId =
    _requiredValue(
      callId,
      'callId',
    );

    final CallNotification?
    existing =
    _activeNotifications[
    normalizedCallId];

    // Once a terminal presentation state is reached, a delayed
    // event must not resurrect the same call into another state.
    if (existing != null &&
        _isTerminalType(
          existing.type,
        ) &&
        existing.type != type) {
      return;
    }

    _cancelExpiry(
      normalizedCallId,
    );

    final Map<String, String>
    immutableArguments =
    Map<String, String>.unmodifiable(
      arguments,
    );

    final String title =
    _localizedText(
      titleKey,
      immutableArguments,
    );

    final String body =
    _localizedText(
      bodyKey,
      immutableArguments,
    );

    if (existing != null) {
      _upsert(
        existing.copyWith(
          id:
          _notificationId(
            normalizedCallId,
            type,
          ),
          type:
          type,
          title:
          title,
          body:
          body,
          clearExpiresAt:
          true,
          titleTextKey:
          titleKey,
          bodyTextKey:
          bodyKey,
          titleLocalizationArgs:
          List<String>.unmodifiable(
            titleLocalizationArgs,
          ),
          bodyLocalizationArgs:
          List<String>.unmodifiable(
            bodyLocalizationArgs,
          ),
          textArguments:
          immutableArguments,
        ),
      );

      return;
    }

    _upsert(
      CallNotification(
        id:
        _notificationId(
          normalizedCallId,
          type,
        ),
        callId:
        normalizedCallId,
        type:
        type,
        title:
        title,
        body:
        body,
        isVideoCall:
        false,
        isIncoming:
        false,
        createdAt:
        DateTime.now(),
        titleTextKey:
        titleKey,
        bodyTextKey:
        bodyKey,
        titleLocalizationArgs:
        List<String>.unmodifiable(
          titleLocalizationArgs,
        ),
        bodyLocalizationArgs:
        List<String>.unmodifiable(
          bodyLocalizationArgs,
        ),
        textArguments:
        immutableArguments,
      ),
    );
  }

  // ===========================================================
  // TERMINAL PRESENTATION TYPES
  // ===========================================================

  bool _isTerminalType(
      CallNotificationType type,
      ) {
    switch (type) {
      case CallNotificationType.missed:
      case CallNotificationType.rejected:
      case CallNotificationType.cancelled:
      case CallNotificationType.ended:
      case CallNotificationType.failed:
        return true;

      case CallNotificationType.incoming:
      case CallNotificationType.outgoing:
      case CallNotificationType.connecting:
      case CallNotificationType.connected:
      case CallNotificationType.networkLost:
      case CallNotificationType.networkRecovered:
        return false;
    }
  }

  // ===========================================================
  // ACTION EMITTER
  // ===========================================================

  void _emitAction(
      String callId,
      CallNotificationAction action,
      ) {
    if (_disposed) {
      return;
    }

    final String normalized =
    callId.trim();

    if (normalized.isEmpty) {
      return;
    }

    _actionController.add(
      CallNotificationActionEvent(
        callId:
        normalized,
        action:
        action,
        timestamp:
        DateTime.now(),
      ),
    );
  }

  // ===========================================================
  // INSERT / REPLACE
  // ===========================================================

  void _upsert(
      CallNotification notification,
      ) {
    if (_disposed) {
      return;
    }

    _activeNotifications[
    notification.callId] =
        notification;

    _emitNotifications();
  }

  // ===========================================================
  // FIND
  // ===========================================================

  CallNotification? _find(
      String callId,
      ) {
    final String normalized =
    callId.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return _activeNotifications[
    normalized];
  }

  // ===========================================================
  // EXPIRY
  // ===========================================================

  void _scheduleExpiryUntil(
      String callId,
      DateTime expiresAt,
      ) {
    _cancelExpiry(
      callId,
    );

    final Duration remaining =
    expiresAt.difference(
      DateTime.now(),
    );

    if (remaining <= Duration.zero) {
      _expireIncomingNotification(
        callId,
      );

      return;
    }

    _expiryTimers[callId] =
        Timer(
          remaining,
              () {
            _expiryTimers.remove(
              callId,
            );

            if (_disposed) {
              return;
            }

            _expireIncomingNotification(
              callId,
            );
          },
        );
  }

  void _expireIncomingNotification(
      String callId,
      ) {
    if (_disposed) {
      return;
    }

    final CallNotification?
    notification =
    _activeNotifications[
    callId];

    if (notification == null ||
        notification.type !=
            CallNotificationType.incoming) {
      return;
    }

    _activeNotifications.remove(
      callId,
    );

    _emitNotifications();

    // IMPORTANT:
    // Notification expiry intentionally does NOT mark the call
    // missed and does NOT mutate signaling.
    //
    // CallService owns the actual timeout/missed-call lifecycle.
  }

  void _cancelExpiry(
      String callId,
      ) {
    final Timer? timer =
    _expiryTimers.remove(
      callId.trim(),
    );

    timer?.cancel();
  }

  void _removeExpiredSilently() {
    final List<String>
    expiredCallIds =
    <String>[];

    for (final MapEntry<
        String,
        CallNotification>
    entry
    in _activeNotifications.entries) {
      if (entry.value.isExpired) {
        expiredCallIds.add(
          entry.key,
        );
      }
    }

    for (final String callId
    in expiredCallIds) {
      _activeNotifications.remove(
        callId,
      );

      _cancelExpiry(
        callId,
      );
    }
  }

  // ===========================================================
  // STATE BROADCAST
  // ===========================================================

  void _emitNotifications() {
    if (_disposed) {
      return;
    }

    _removeExpiredSilently();

    final List<CallNotification>
    current =
    _activeNotifications.values
        .toList(
      growable: false,
    );

    current.sort(
          (
          CallNotification a,
          CallNotification b,
          ) =>
          b.createdAt.compareTo(
            a.createdAt,
          ),
    );

    _notificationController.add(
      List<CallNotification>.unmodifiable(
        current,
      ),
    );
  }

  // ===========================================================
  // LOCALIZATION REFRESH
  // ===========================================================

  void _relocalizeActiveNotifications() {
    if (_disposed ||
        _activeNotifications.isEmpty) {
      return;
    }

    final List<String> callIds =
    _activeNotifications.keys
        .toList(
      growable: false,
    );

    bool changed = false;

    for (final String callId
    in callIds) {
      final CallNotification?
      notification =
      _activeNotifications[
      callId];

      if (notification == null) {
        continue;
      }

      final CallNotificationTextKey?
      titleKey =
          notification.titleTextKey;

      final CallNotificationTextKey?
      bodyKey =
          notification.bodyTextKey;

      if (titleKey == null &&
          bodyKey == null) {
        continue;
      }

      final String nextTitle =
      titleKey == null
          ? notification.title
          : _localizedText(
        titleKey,
        notification
            .textArguments,
      );

      final String nextBody =
      bodyKey == null
          ? notification.body
          : _localizedText(
        bodyKey,
        notification
            .textArguments,
      );

      if (nextTitle ==
          notification.title &&
          nextBody ==
              notification.body) {
        continue;
      }

      _activeNotifications[
      callId] =
          notification.copyWith(
            title:
            nextTitle,
            body:
            nextBody,
          );

      changed = true;
    }

    if (changed) {
      _emitNotifications();
    }
  }

  // ===========================================================
  // LOCALIZED TEXT RESOLUTION
  // ===========================================================

  String _localizedText(
      CallNotificationTextKey key,
      Map<String, String> arguments,
      ) {
    final String fallback =
    _englishFallback(
      key,
      arguments,
    );

    final CallNotificationTextResolver?
    resolver =
        _textResolver;

    if (resolver == null) {
      return fallback;
    }

    try {
      final String resolved =
      resolver(
        key,
        Map<String, String>.unmodifiable(
          arguments,
        ),
      ).trim();

      if (resolved.isEmpty) {
        return fallback;
      }

      return resolved;
    } catch (error, stackTrace) {
      _reportError(
        'localization/${key.resourceKey}',
        error,
        stackTrace,
      );

      return fallback;
    }
  }

  // ===========================================================
  // ENGLISH SAFE FALLBACK
  //
  // This is NOT the global-language implementation.
  // Actual locale translations belong to Flutter l10n / native
  // localized resources. These strings prevent blank notifications
  // if a locale resource is temporarily unavailable.
  // ===========================================================

  String _englishFallback(
      CallNotificationTextKey key,
      Map<String, String> arguments,
      ) {
    final String peerName =
        arguments['peerName'] ??
            'JR CALL User';

    final String duration =
        arguments['duration'] ??
            '00:00';

    final String reason =
        arguments['reason'] ??
            'JR CALL could not establish the connection.';

    switch (key) {
      case CallNotificationTextKey
          .incomingVideoTitle:
        return 'Incoming Video Call';

      case CallNotificationTextKey
          .incomingVoiceTitle:
        return 'Incoming Voice Call';

      case CallNotificationTextKey
          .incomingBody:
        return '$peerName is calling you';

      case CallNotificationTextKey
          .outgoingVideoTitle:
        return 'Video Calling';

      case CallNotificationTextKey
          .outgoingVoiceTitle:
        return 'Voice Calling';

      case CallNotificationTextKey
          .outgoingBody:
        return 'Calling $peerName…';

      case CallNotificationTextKey
          .connectingTitle:
        return 'Connecting';

      case CallNotificationTextKey
          .connectingBody:
        return 'Securing your JR CALL connection…';

      case CallNotificationTextKey
          .connectedVideoTitle:
        return 'Video Call Connected';

      case CallNotificationTextKey
          .connectedVoiceTitle:
        return 'Voice Call Connected';

      case CallNotificationTextKey
          .connectedBody:
        return 'Connected with $peerName';

      case CallNotificationTextKey
          .missedTitle:
        return 'Missed Call';

      case CallNotificationTextKey
          .missedBody:
        return 'Missed call from $peerName';

      case CallNotificationTextKey
          .rejectedTitle:
        return 'Call Rejected';

      case CallNotificationTextKey
          .rejectedBody:
        return 'The call was rejected.';

      case CallNotificationTextKey
          .cancelledTitle:
        return 'Call Cancelled';

      case CallNotificationTextKey
          .cancelledBody:
        return 'The call was cancelled.';

      case CallNotificationTextKey
          .endedTitle:
        return 'Call Ended';

      case CallNotificationTextKey
          .endedBody:
        return 'Call ended.';

      case CallNotificationTextKey
          .endedWithDurationBody:
        return 'Call ended • $duration';

      case CallNotificationTextKey
          .failedTitle:
        return 'Call Failed';

      case CallNotificationTextKey
          .failedBody:
        return 'JR CALL could not establish the connection.';

      case CallNotificationTextKey
          .failedReasonBody:
        return reason;

      case CallNotificationTextKey
          .networkLostTitle:
        return 'Connection Interrupted';

      case CallNotificationTextKey
          .networkLostBody:
        return 'Network lost. JR CALL is trying to reconnect…';

      case CallNotificationTextKey
          .networkRecoveredTitle:
        return 'Connection Restored';

      case CallNotificationTextKey
          .networkRecoveredBody:
        return 'JR CALL connection has been restored.';
    }
  }

  // ===========================================================
  // DATA
  // ===========================================================

  Map<String, dynamic> _buildData(
      Map<String, dynamic> original,
      Map<String, dynamic> requiredData,
      ) {
    return Map<String, dynamic>.unmodifiable(
      <String, dynamic>{
        ...original,
        ...requiredData,
      },
    );
  }

  // ===========================================================
  // HELPERS
  // ===========================================================

  String _notificationId(
      String callId,
      CallNotificationType type,
      ) {
    return 'jr_call_'
        '${type.name}_'
        '$callId';
  }

  String _requiredValue(
      String value,
      String fieldName,
      ) {
    final String normalized =
    value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        fieldName,
        '$fieldName cannot be empty.',
      );
    }

    return normalized;
  }

  String? _nullableTrim(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final String normalized =
    value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  String _displayName(
      String? value, {
        required String fallback,
      }) {
    return _nullableTrim(
      value,
    ) ??
        fallback;
  }

  String _formatDuration(
      Duration duration,
      ) {
    final int totalSeconds =
    duration.inSeconds < 0
        ? 0
        : duration.inSeconds;

    final int hours =
        totalSeconds ~/ 3600;

    final int minutes =
        (totalSeconds % 3600) ~/
            60;

    final int seconds =
        totalSeconds % 60;

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
      throw StateError(
        'NotificationService has already been disposed.',
      );
    }
  }

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL '
          '[NotificationService/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[NotificationService/$source]',
        stackTrace:
        stackTrace,
      );
    }
  }

  // ===========================================================
  // DISPOSE
  //
  // Singleton disposal is application/test shutdown only.
  // Normal per-call cleanup uses dismiss()/clearAll().
  // ===========================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    for (final Timer timer
    in _expiryTimers.values) {
      timer.cancel();
    }

    _expiryTimers.clear();

    _activeNotifications.clear();

    _textResolver = null;

    await _notificationController.close();

    await _actionController.close();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 35 PRODUCTION CONTRACT:
//
// ✓ Existing singleton preserved.
// ✓ Existing notification enums preserved.
// ✓ Existing action enums preserved.
// ✓ Existing CallNotification APIs preserved.
// ✓ Existing CallNotificationActionEvent preserved.
//
// ✓ showIncomingCall preserved.
// ✓ showOutgoingCall preserved.
// ✓ showConnecting preserved.
// ✓ showConnected preserved.
// ✓ showMissedCall preserved.
// ✓ showRejected preserved.
// ✓ showCancelled preserved.
// ✓ showCallEnded preserved.
// ✓ showCallFailed preserved.
// ✓ showNetworkLost preserved.
// ✓ showNetworkRecovered preserved.
//
// ✓ answer/reject/cancel/open/dismiss actions preserved.
// ✓ Compatibility notification aliases preserved.
//
// ✓ Localization no longer belongs to hardcoded country logic.
// ✓ Stable localization resource keys added.
// ✓ Application locale resolver supported.
// ✓ Native localization argument metadata supported.
// ✓ English is fallback only.
// ✓ Runtime language refresh supported.
//
// ✓ Incoming duplicate does not restart 45-second expiry.
// ✓ Incoming duplicate does not reset createdAt.
// ✓ Outgoing duplicate does not regress advanced state.
// ✓ Stale incoming/outgoing events cannot resurrect call UI.
// ✓ Incoming expiry cleared on connecting/connected transitions.
// ✓ Nullable expiresAt copy bug fixed.
// ✓ Terminal notification resurrection blocked.
// ✓ Expiry remains notification-presentation-only.
// ✓ Expiry never marks call missed.
// ✓ Expiry never ends signaling call.
//
// ✓ Notification actions remain intent events.
// ✓ No CallService ownership duplicated.
// ✓ No WebRTC ownership duplicated.
// ✓ No signaling ownership duplicated.
// ✓ No ICE ownership duplicated.
// ✓ No recovery ownership duplicated.
// ✓ No Firestore ownership added.
// ✓ No authentication ownership added.
// ✓ No SMS ownership added.
// ===============================================================