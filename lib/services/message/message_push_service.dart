// ============================================================================
// JR CALL
// File: message_push_service.dart
// Location: lib/services/message/message_push_service.dart
// Description:
// Production-safe Message push payload classifier/parser/router.
//
// Owns:
// - Strict Message-vs-Call payload classification.
// - Message push payload normalization.
// - Canonical conversation/message ID extraction.
// - Safe notification-open routing into MessageNavigationService.
// - Duplicate notification-open suppression.
// - Authentication-safe navigation handoff.
// - Foreground/background/opened-app Message push classification contract.
//
// Does NOT:
// - Register or refresh FCM tokens.
// - Modify main.dart Call FCM handling.
// - Handle Call Engine signaling.
// - Call Firestore.
// - Call Firebase Storage.
// - Create/read messages.
// - Mark messages delivered/read from notification receipt.
// - Search users.
// - Replace UserDiscoveryService.
// - Replace AuthService.
// - Treat username/email/phone/JR CALL public ID as Firebase UID.
// - Invent notification data.
// ============================================================================

import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'message_navigation_service.dart';

/// Classification result for an incoming push payload.
///
/// A Message payload is accepted only when it carries an explicit Message
/// discriminator. Unknown/non-Message payloads remain available for other
/// feature routers, especially the existing JR CALL Call FCM router.
enum MessagePushClassification { message, notMessage, invalidMessage }

/// Message push event/action encoded by trusted server payloads.
///
/// These values describe notification/navigation intent only.
/// They MUST NOT be interpreted as durable sent/delivered/read state.
enum MessagePushEvent {
  newMessage,
  messageUpdated,
  messageDeleted,
  reaction,
  conversation,
  unknown,
}

/// App lifecycle source from which the push is being processed.
enum MessagePushSource {
  foreground,
  background,
  initialMessage,
  notificationTap,
  internal,
}

/// High-level Message push processing result.
enum MessagePushHandlingStatus {
  handled,
  classified,
  ignored,
  invalid,
  navigationUnavailable,
  authenticationRequired,
}

/// Immutable parsed JR CALL Message push.
///
/// [conversationId] is the canonical Message conversation identity.
/// [messageId], when supplied, is the canonical durable Firestore message ID.
///
/// No value in this object is proof of delivered/read state.
@immutable
final class MessagePushPayload {
  const MessagePushPayload({
    required this.event,
    required this.conversationId,
    required this.source,
    required this.rawData,
    this.messageId,
    this.senderUid,
    this.notificationId,
  });

  final MessagePushEvent event;

  /// Canonical conversation document ID.
  final String conversationId;

  /// Canonical durable message document ID when provided by trusted backend.
  final String? messageId;

  /// Firebase Auth UID only when explicitly supplied by trusted backend data.
  ///
  /// This value is informational for routing/diagnostics here and is never
  /// replaced by username, email, phone number or public JR CALL ID.
  final String? senderUid;

  /// Stable push/notification identifier when available.
  final String? notificationId;

  final MessagePushSource source;

  /// Read-only normalized copy of the original FCM data payload.
  final Map<String, String> rawData;

  bool get hasMessageId => messageId != null && messageId!.isNotEmpty;

  MessagePushPayload copyWith({
    MessagePushEvent? event,
    String? conversationId,
    String? messageId,
    bool clearMessageId = false,
    String? senderUid,
    bool clearSenderUid = false,
    String? notificationId,
    bool clearNotificationId = false,
    MessagePushSource? source,
    Map<String, String>? rawData,
  }) {
    return MessagePushPayload(
      event: event ?? this.event,
      conversationId: conversationId ?? this.conversationId,
      messageId: clearMessageId ? null : messageId ?? this.messageId,
      senderUid: clearSenderUid ? null : senderUid ?? this.senderUid,
      notificationId: clearNotificationId
          ? null
          : notificationId ?? this.notificationId,
      source: source ?? this.source,
      rawData: rawData ?? this.rawData,
    );
  }
}

/// Result returned by [MessagePushService.handle].
@immutable
final class MessagePushHandlingResult {
  const MessagePushHandlingResult({
    required this.status,
    required this.classification,
    this.payload,
    this.navigationResult,
  });

  final MessagePushHandlingStatus status;
  final MessagePushClassification classification;
  final MessagePushPayload? payload;
  final MessageNavigationResult? navigationResult;

  bool get handled => status == MessagePushHandlingStatus.handled;

  bool get requiresAuthentication =>
      status == MessagePushHandlingStatus.authenticationRequired;
}

/// Strict JR CALL Message push classifier/parser/router.
///
/// This service accepts `Map<String, Object?>` instead of taking ownership of
/// FirebaseMessaging/RemoteMessage.
///
/// That boundary is intentional:
///
/// main.dart / shared FCM owner
///   -> existing Call classification remains intact
///   -> MessagePushService.classify(...)
///   -> only explicit Message payloads enter Message navigation
///
/// Therefore this class never creates an FCM listener and never interferes
/// with existing CALL routing.
final class MessagePushService {
  /// Public constructor.
  ///
  /// Public parameter names remain stable for existing JR CALL integration.
  /// Assignment is delegated to the private initializing-formal constructor so
  /// `prefer_initializing_formals` remains analyzer-clean without changing the
  /// frozen external API.
  factory MessagePushService({
    required MessageNavigationService navigationService,
    int maximumRememberedPushes = 128,
  }) {
    if (maximumRememberedPushes <= 0) {
      throw ArgumentError.value(
        maximumRememberedPushes,
        'maximumRememberedPushes',
        'maximumRememberedPushes must be greater than zero.',
      );
    }

    return MessagePushService._(navigationService, maximumRememberedPushes);
  }

  MessagePushService._(this._navigationService, this.maximumRememberedPushes);

  final MessageNavigationService _navigationService;

  /// Maximum number of handled notification-open keys retained in memory.
  ///
  /// This prevents duplicate initial-message/onMessageOpenedApp navigation
  /// while keeping memory strictly bounded.
  final int maximumRememberedPushes;

  final LinkedHashSet<String> _handledOpenKeys = LinkedHashSet<String>();

  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Returns true only when the payload explicitly identifies itself as a
  /// valid JR CALL Message notification.
  ///
  /// Ambiguous payloads intentionally return false. This prevents Message
  /// integration from stealing CALL or other application notifications.
  bool isMessagePayload(Map<String, Object?> data) {
    return classify(data) == MessagePushClassification.message;
  }

  /// Strictly classifies an FCM data payload.
  ///
  /// Explicit Message discriminator fields supported by this bridge:
  ///
  /// - feature
  /// - type
  /// - notificationType / notification_type
  /// - pushType / push_type
  /// - category
  ///
  /// Known CALL values always remain non-Message.
  ///
  /// A payload explicitly classified as Message but lacking a canonical
  /// conversation ID becomes [MessagePushClassification.invalidMessage]
  /// instead of being routed to ChatScreen.
  MessagePushClassification classify(Map<String, Object?> data) {
    if (data.isEmpty) {
      return MessagePushClassification.notMessage;
    }

    final Map<String, String> normalized = _normalizeData(data);

    if (normalized.isEmpty) {
      return MessagePushClassification.notMessage;
    }

    final String? discriminator = _firstNonEmpty(normalized, const <String>[
      'feature',
      'type',
      'notificationtype',
      'notification_type',
      'pushtype',
      'push_type',
      'category',
    ]);

    if (discriminator == null) {
      return MessagePushClassification.notMessage;
    }

    final String kind = _normalizeToken(discriminator);

    /// CALL rejection is deliberately checked before Message recognition.
    ///
    /// Message integration must never consume existing CALL notifications.
    if (_isCallToken(kind)) {
      return MessagePushClassification.notMessage;
    }

    if (!_isMessageToken(kind)) {
      return MessagePushClassification.notMessage;
    }

    final String? conversationId = _extractConversationId(normalized);

    if (conversationId == null) {
      return MessagePushClassification.invalidMessage;
    }

    return MessagePushClassification.message;
  }

  /// Parses one strictly classified Message payload.
  ///
  /// Returns null for:
  /// - non-Message payload
  /// - CALL payload
  /// - malformed explicit Message payload
  MessagePushPayload? parse(
    Map<String, Object?> data, {
    MessagePushSource source = MessagePushSource.internal,
  }) {
    final MessagePushClassification classification = classify(data);

    if (classification != MessagePushClassification.message) {
      return null;
    }

    final Map<String, String> normalized = _normalizeData(data);

    final String? conversationId = _extractConversationId(normalized);

    if (conversationId == null) {
      return null;
    }

    final String? messageId = _firstNonEmpty(normalized, const <String>[
      'messageid',
      'message_id',
    ]);

    final String? senderUid = _firstNonEmpty(normalized, const <String>[
      'senderuid',
      'sender_uid',
      'fromuid',
      'from_uid',
    ]);

    final String? notificationId = _firstNonEmpty(normalized, const <String>[
      'notificationid',
      'notification_id',
      'pushid',
      'push_id',
      'eventid',
      'event_id',
    ]);

    final String? eventRaw = _firstNonEmpty(normalized, const <String>[
      'event',
      'action',
      'messageevent',
      'message_event',
    ]);

    return MessagePushPayload(
      event: _parseEvent(eventRaw),
      conversationId: conversationId,
      messageId: _nullableNormalizedId(messageId),
      senderUid: _nullableNormalizedId(senderUid),
      notificationId: _nullableNormalizedId(notificationId),
      source: source,
      rawData: Map<String, String>.unmodifiable(normalized),
    );
  }

  /// Processes one FCM data payload.
  ///
  /// Foreground/background receipt normally only CLASSIFIES/parses the
  /// Message notification. It must not automatically push ChatScreen.
  ///
  /// [openConversation] should be true only when navigation is intended,
  /// primarily:
  ///
  /// - user taps a notification
  /// - app launches from an initial Message notification
  ///
  /// IMPORTANT:
  /// Receiving this push NEVER marks the durable message delivered or read.
  /// Those states remain owned by the real Message receipt engines.
  Future<MessagePushHandlingResult> handle(
    Map<String, Object?> data, {
    required MessagePushSource source,
    bool openConversation = false,
  }) async {
    _ensureActive();

    final MessagePushClassification classification = classify(data);

    if (classification == MessagePushClassification.notMessage) {
      return const MessagePushHandlingResult(
        status: MessagePushHandlingStatus.ignored,
        classification: MessagePushClassification.notMessage,
      );
    }

    if (classification == MessagePushClassification.invalidMessage) {
      return const MessagePushHandlingResult(
        status: MessagePushHandlingStatus.invalid,
        classification: MessagePushClassification.invalidMessage,
      );
    }

    final MessagePushPayload? payload = parse(data, source: source);

    if (payload == null) {
      return const MessagePushHandlingResult(
        status: MessagePushHandlingStatus.invalid,
        classification: MessagePushClassification.invalidMessage,
      );
    }

    if (!openConversation) {
      return MessagePushHandlingResult(
        status: MessagePushHandlingStatus.classified,
        classification: MessagePushClassification.message,
        payload: payload,
      );
    }

    return _openPayload(payload);
  }

  /// Handles an actual Message notification-open event.
  ///
  /// Duplicate opens are suppressed so an initial notification plus a later
  /// duplicated notification-open callback does not open ChatScreen twice.
  Future<MessagePushHandlingResult> open(
    Map<String, Object?> data, {
    MessagePushSource source = MessagePushSource.notificationTap,
  }) {
    return handle(data, source: source, openConversation: true);
  }

  Future<MessagePushHandlingResult> _openPayload(
    MessagePushPayload payload,
  ) async {
    if (_disposed) {
      return MessagePushHandlingResult(
        status: MessagePushHandlingStatus.navigationUnavailable,
        classification: MessagePushClassification.message,
        payload: payload,
      );
    }

    final String dedupeKey = _openDedupeKey(payload);

    if (_handledOpenKeys.contains(dedupeKey)) {
      return MessagePushHandlingResult(
        status: MessagePushHandlingStatus.ignored,
        classification: MessagePushClassification.message,
        payload: payload,
      );
    }

    _rememberOpenKey(dedupeKey);

    try {
      final MessageNavigationResult navigation = await _navigationService
          .openConversation(
            conversationId: payload.conversationId,
            source: MessageNavigationSource.pushNotification,
          );

      if (_disposed) {
        _handledOpenKeys.remove(dedupeKey);

        return MessagePushHandlingResult(
          status: MessagePushHandlingStatus.navigationUnavailable,
          classification: MessagePushClassification.message,
          payload: payload,
          navigationResult: navigation,
        );
      }

      if (navigation.requiresAuthentication) {
        /// Keep the dedupe key.
        ///
        /// MessageNavigationService already owns the pending-after-auth
        /// destination. A repeated notification tap should not create another
        /// competing auth/navigation operation.
        return MessagePushHandlingResult(
          status: MessagePushHandlingStatus.authenticationRequired,
          classification: MessagePushClassification.message,
          payload: payload,
          navigationResult: navigation,
        );
      }

      if (navigation.opened ||
          navigation.status == MessageNavigationStatus.ignored) {
        return MessagePushHandlingResult(
          status: MessagePushHandlingStatus.handled,
          classification: MessagePushClassification.message,
          payload: payload,
          navigationResult: navigation,
        );
      }

      /// Navigation did not complete, therefore a future user attempt should be
      /// allowed instead of remaining permanently suppressed.
      _handledOpenKeys.remove(dedupeKey);

      return MessagePushHandlingResult(
        status: MessagePushHandlingStatus.navigationUnavailable,
        classification: MessagePushClassification.message,
        payload: payload,
        navigationResult: navigation,
      );
    } catch (_) {
      /// Raw navigation/Firebase/application exceptions are deliberately not
      /// exposed as notification text from this integration boundary.
      ///
      /// Removing the key allows a future valid navigation attempt.
      _handledOpenKeys.remove(dedupeKey);

      return MessagePushHandlingResult(
        status: MessagePushHandlingStatus.navigationUnavailable,
        classification: MessagePushClassification.message,
        payload: payload,
      );
    }
  }

  /// Clears remembered notification-open identities.
  ///
  /// Useful on explicit Message/application session reset.
  ///
  /// This does NOT:
  /// - alter Firebase Messaging token state
  /// - alter Firebase Auth
  /// - clear messages
  /// - modify CALL notification state
  void clearHandledPushes() {
    if (_disposed) {
      return;
    }

    _handledOpenKeys.clear();
  }

  /// Builds the strongest stable duplicate-open key available.
  ///
  /// Priority:
  /// notification/event ID
  ///   -> canonical message ID + conversation ID
  ///   -> conversation + event fallback
  String _openDedupeKey(MessagePushPayload payload) {
    final String? notificationId = payload.notificationId;

    if (notificationId != null && notificationId.isNotEmpty) {
      return 'notification::$notificationId';
    }

    final String? messageId = payload.messageId;

    if (messageId != null && messageId.isNotEmpty) {
      return 'message::${payload.conversationId}::$messageId';
    }

    return 'conversation::${payload.conversationId}::${payload.event.name}';
  }

  /// Remembers a notification-open identity while enforcing strict memory
  /// bounds.
  void _rememberOpenKey(String key) {
    if (_handledOpenKeys.remove(key)) {
      _handledOpenKeys.add(key);
      return;
    }

    _handledOpenKeys.add(key);

    while (_handledOpenKeys.length > maximumRememberedPushes) {
      _handledOpenKeys.remove(_handledOpenKeys.first);
    }
  }

  /// Normalizes server Message event values.
  ///
  /// This mapping affects notification intent only and never modifies durable
  /// MessageEntity status.
  static MessagePushEvent _parseEvent(String? raw) {
    final String token = _normalizeToken(raw ?? '');

    switch (token) {
      case 'newmessage':
      case 'message':
      case 'messagenew':
      case 'messagecreated':
      case 'created':
        return MessagePushEvent.newMessage;

      case 'messageupdated':
      case 'updated':
      case 'edited':
      case 'messageedited':
        return MessagePushEvent.messageUpdated;

      case 'messagedeleted':
      case 'deleted':
        return MessagePushEvent.messageDeleted;

      case 'reaction':
      case 'messagereaction':
      case 'reactionupdated':
        return MessagePushEvent.reaction;

      case 'conversation':
      case 'conversationupdated':
        return MessagePushEvent.conversation;

      default:
        return MessagePushEvent.unknown;
    }
  }

  /// Explicit values accepted as Message feature discriminators.
  static bool _isMessageToken(String value) {
    switch (value) {
      case 'message':
      case 'messages':
      case 'messaging':
      case 'jrmessage':
      case 'jrcallmessage':
      case 'chat':
        return true;

      default:
        return false;
    }
  }

  /// Explicit values reserved for CALL routing.
  ///
  /// These are rejected before Message routing to protect existing main.dart
  /// CALL handling.
  static bool _isCallToken(String value) {
    switch (value) {
      case 'call':
      case 'incomingcall':
      case 'voicecall':
      case 'videocall':
      case 'callinvite':
      case 'calling':
      case 'jrcall':
        return true;

      default:
        return false;
    }
  }

  /// Extracts only the canonical conversation identity used for Message
  /// navigation.
  static String? _extractConversationId(Map<String, String> data) {
    return _nullableNormalizedId(
      _firstNonEmpty(data, const <String>[
        'conversationid',
        'conversation_id',
        'chatid',
        'chat_id',
      ]),
    );
  }

  /// Converts supported primitive FCM values into a normalized string map.
  ///
  /// Unsupported complex/object values are intentionally ignored rather than
  /// dynamically trusted or serialized into application identity.
  static Map<String, String> _normalizeData(Map<String, Object?> source) {
    final Map<String, String> result = <String, String>{};

    source.forEach((String rawKey, Object? rawValue) {
      final String key = rawKey.trim().toLowerCase();

      if (key.isEmpty || rawValue == null) {
        return;
      }

      final String value;

      if (rawValue is String) {
        value = rawValue.trim();
      } else if (rawValue is num || rawValue is bool) {
        value = rawValue.toString().trim();
      } else {
        return;
      }

      if (value.isEmpty) {
        return;
      }

      result[key] = value;
    });

    return result;
  }

  static String? _firstNonEmpty(Map<String, String> data, List<String> keys) {
    for (final String key in keys) {
      final String value = data[key]?.trim() ?? '';

      if (value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  /// Produces a comparison-safe discriminator token.
  ///
  /// Punctuation/underscores/spaces/case do not affect classification.
  static String _normalizeToken(String value) {
    final String lower = value.trim().toLowerCase();

    if (lower.isEmpty) {
      return '';
    }

    final StringBuffer buffer = StringBuffer();

    for (final int rune in lower.runes) {
      final bool numeric = rune >= 48 && rune <= 57;
      final bool alphabetic = rune >= 97 && rune <= 122;

      if (numeric || alphabetic) {
        buffer.writeCharCode(rune);
      }
    }

    return buffer.toString();
  }

  static String? _nullableNormalizedId(String? value) {
    if (value == null) {
      return null;
    }

    final String normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('MessagePushService has already been disposed.');
    }
  }

  /// Releases only MessagePushService-owned bounded state.
  ///
  /// Deliberately NOT disposed here:
  /// - MessageNavigationService
  /// - Firebase Messaging
  /// - AuthService
  /// - Message repositories/controllers
  /// - Message Engine
  /// - protected Call Engine/WebRTC
  ///
  /// They have separate application ownership.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _handledOpenKeys.clear();
  }
}

// ============================================================================
// END OF FILE:
// lib/services/message/message_push_service.dart
// ============================================================================
