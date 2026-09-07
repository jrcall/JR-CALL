// ============================================================================
// JR CALL
// File: message_sender.dart
// Location: lib/features/message/engine/message_sender.dart
// Description:
// Production durable outgoing-message pipeline.
//
// Responsibilities:
// - Generates or preserves one stable canonical message ID.
// - Validates authenticated sender/conversation/message payload.
// - Creates optimistic queued messages.
// - Transitions queued -> sending.
// - Persists through an injected durable-message persistence abstraction.
// - Transitions to sent only after durable backend acceptance.
// - Preserves canonical message ID across retries/reconciliation.
// - Coordinates attachment metadata already prepared by the media layer.
// - Prevents duplicate concurrent sends.
// - Rejects stale session completions.
//
// Important:
// - Does NOT mark delivered or read.
// - Does NOT access Firestore collections directly.
// - Does NOT access Firebase Storage directly.
// - Does NOT render UI.
// - Does NOT contain Call Engine/WebRTC logic.
// ============================================================================

import 'dart:async';
import 'dart:collection';

import 'package:uuid/uuid.dart';

import '../data/attachment_entity.dart';
import '../data/message_entity.dart';
import '../data/message_status.dart';
import '../data/message_type.dart';

/// Immutable outgoing message command consumed by [MessageSender].
///
/// [clientMessageId] may be supplied when a stable ID already exists, such as
/// a retry/recovery path. Otherwise [MessageSender] creates one exactly once.
final class MessageSendRequest {
  const MessageSendRequest({
    required this.conversationId,
    required this.type,
    this.text,
    this.attachment,
    this.replyToMessageId,
    this.replyToSenderUid,
    this.replyPreview,
    this.replyType,
    this.clientMessageId,
    this.clientCreatedAt,
  });

  final String conversationId;
  final MessageType type;

  /// Durable text body where applicable.
  final String? text;

  /// Upload-complete attachment metadata when sending media/file content.
  ///
  /// Binary upload ownership belongs to Message Media infrastructure.
  final AttachmentEntity? attachment;

  /// Canonical replied-to durable message ID.
  final String? replyToMessageId;

  /// Firebase UID of the original replied-to sender.
  final String? replyToSenderUid;

  /// Safe reply preview suitable for durable storage.
  final String? replyPreview;

  /// Durable message type of the replied-to message.
  final MessageType? replyType;

  /// Existing canonical message ID.
  ///
  /// Primarily intended for stable retry/recovery workflows.
  final String? clientMessageId;

  /// Original client creation timestamp.
  ///
  /// When absent, MessageSender assigns UTC now once.
  final DateTime? clientCreatedAt;

  MessageSendRequest copyWith({
    String? conversationId,
    MessageType? type,
    String? text,
    bool clearText = false,
    AttachmentEntity? attachment,
    bool clearAttachment = false,
    String? replyToMessageId,
    bool clearReplyToMessageId = false,
    String? replyToSenderUid,
    bool clearReplyToSenderUid = false,
    String? replyPreview,
    bool clearReplyPreview = false,
    MessageType? replyType,
    bool clearReplyType = false,
    String? clientMessageId,
    bool clearClientMessageId = false,
    DateTime? clientCreatedAt,
  }) {
    return MessageSendRequest(
      conversationId: conversationId ?? this.conversationId,
      type: type ?? this.type,
      text: clearText ? null : text ?? this.text,
      attachment: clearAttachment ? null : attachment ?? this.attachment,
      replyToMessageId: clearReplyToMessageId
          ? null
          : replyToMessageId ?? this.replyToMessageId,
      replyToSenderUid: clearReplyToSenderUid
          ? null
          : replyToSenderUid ?? this.replyToSenderUid,
      replyPreview: clearReplyPreview
          ? null
          : replyPreview ?? this.replyPreview,
      replyType: clearReplyType ? null : replyType ?? this.replyType,
      clientMessageId: clearClientMessageId
          ? null
          : clientMessageId ?? this.clientMessageId,
      clientCreatedAt: clientCreatedAt ?? this.clientCreatedAt,
    );
  }
}

/// Message-ID generator abstraction.
///
/// The default production implementation uses UUID v4.
abstract interface class MessageIdGenerator {
  String nextMessageId();
}

/// Default canonical client message ID generator.
final class UuidMessageIdGenerator implements MessageIdGenerator {
  UuidMessageIdGenerator({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  String nextMessageId() => _uuid.v4();
}

/// Validation/security boundary required by [MessageSender].
///
/// FILE 29 / FILE 31 can provide the concrete production adapter without
/// allowing MessageSender to own authentication or validation policy.
abstract interface class MessageSenderValidator {
  /// Validates sender identity and active conversation authorization context.
  FutureOr<void> validateSendContext({
    required String authenticatedUid,
    required String conversationId,
  });

  /// Validates and normalizes a complete outgoing request.
  ///
  /// The returned request must retain the same semantic conversation and may
  /// contain normalized safe text/reply metadata.
  FutureOr<MessageSendRequest> validateAndNormalize(
    MessageSendRequest request, {
    required String authenticatedUid,
    required String messageId,
  });
}

/// Durable persistence abstraction used by [MessageSender].
///
/// The concrete implementation must eventually persist through the canonical
/// Message Remote Store / Repository path. It must use [message.id] as the
/// Firestore durable message document ID so repeat persistence is idempotent.
abstract interface class MessageSenderPersistence {
  /// Durably accepts [message].
  ///
  /// Returned entity may contain resolved server fields such as
  /// serverCreatedAt, but canonical identity fields must remain unchanged.
  Future<MessageEntity> persistOutgoingMessage(MessageEntity message);
}

/// Optimistic/local state sink used by [MessageSender].
///
/// Message sync/cache infrastructure owns the concrete state implementation.
abstract interface class MessageSenderStateSink {
  /// Returns the currently known canonical entity, if loaded locally.
  MessageEntity? findMessage(String messageId);

  /// Inserts/replaces an optimistic local entity.
  FutureOr<void> upsertMessage(MessageEntity message);

  /// Records a safe failed-send representation.
  ///
  /// Raw backend exception text must not automatically be exposed to UI.
  FutureOr<void> markSendFailed({
    required MessageEntity message,
    required Object error,
    required StackTrace stackTrace,
  });
}

/// Durable outgoing-message pipeline.
final class MessageSender {
  factory MessageSender({
    required MessageSenderValidator validator,
    required MessageSenderPersistence persistence,
    required MessageSenderStateSink stateSink,
    MessageIdGenerator? messageIdGenerator,
    int rememberedMessageLimit = 512,
  }) {
    return MessageSender._(
      validator,
      persistence,
      stateSink,
      messageIdGenerator ?? UuidMessageIdGenerator(),
      _validateRememberedMessageLimit(rememberedMessageLimit),
    );
  }

  MessageSender._(
    this._validator,
    this._persistence,
    this._stateSink,
    this._messageIdGenerator,
    this._rememberedMessageLimit,
  );

  final MessageSenderValidator _validator;
  final MessageSenderPersistence _persistence;
  final MessageSenderStateSink _stateSink;
  final MessageIdGenerator _messageIdGenerator;

  final int _rememberedMessageLimit;

  final Map<String, Future<MessageEntity>> _inFlight =
      <String, Future<MessageEntity>>{};

  final LinkedHashSet<String> _recentlyAcceptedIds = LinkedHashSet<String>();

  String? _authenticatedUid;
  String? _conversationId;

  int _sessionGeneration = 0;

  bool _initialized = false;
  bool _disposed = false;

  /// True when initialized for an active authenticated conversation.
  bool get isInitialized => _initialized && !_disposed;

  /// True after permanent disposal.
  bool get isDisposed => _disposed;

  /// Number of sends currently awaiting durable persistence.
  int get inFlightCount => _inFlight.length;

  /// Initializes sender context for one Firebase-authenticated conversation.
  Future<void> initialize({
    required String authenticatedUid,
    required String conversationId,
  }) async {
    _ensureNotDisposed();

    final String uid = _normalizeRequiredIdentifier(
      authenticatedUid,
      fieldName: 'authenticatedUid',
    );

    final String conversation = _normalizeRequiredIdentifier(
      conversationId,
      fieldName: 'conversationId',
    );

    if (_initialized &&
        _authenticatedUid == uid &&
        _conversationId == conversation) {
      return;
    }

    if (_initialized || _authenticatedUid != null || _conversationId != null) {
      await reset();
    }

    await _validator.validateSendContext(
      authenticatedUid: uid,
      conversationId: conversation,
    );

    ++_sessionGeneration;

    _authenticatedUid = uid;
    _conversationId = conversation;
    _initialized = true;
  }

  /// Sends one durable JR CALL message.
  ///
  /// Pipeline:
  ///
  /// request
  /// -> canonical ID
  /// -> validation/normalization
  /// -> queued optimistic entity
  /// -> sending
  /// -> durable persistence
  /// -> sent
  ///
  /// Delivery/read states are intentionally outside this class.
  Future<MessageEntity> send({
    required String authenticatedUid,
    required String conversationId,
    required MessageSendRequest request,
  }) {
    final _SenderSession session = _requireSession(
      authenticatedUid: authenticatedUid,
      conversationId: conversationId,
    );

    final String requestConversation = _normalizeRequiredIdentifier(
      request.conversationId,
      fieldName: 'request.conversationId',
    );

    if (requestConversation != session.conversationId) {
      throw StateError(
        'Outgoing message conversation does not match the active '
        'MessageSender conversation.',
      );
    }

    final String messageId = _resolveMessageId(request.clientMessageId);

    final Future<MessageEntity>? activeSend = _inFlight[messageId];

    if (activeSend != null) {
      return activeSend;
    }

    final MessageEntity? existing = _stateSink.findMessage(messageId);

    if (existing != null) {
      _assertExistingIdentity(existing, session: session, messageId: messageId);

      if (_isDurablyAccepted(existing.status)) {
        _rememberAccepted(messageId);
        return Future<MessageEntity>.value(existing);
      }

      if (existing.status == MessageStatus.failed) {
        return Future<MessageEntity>.error(
          StateError(
            'Message $messageId is failed. Use MessageRetryEngine to retry '
            'the existing canonical message instead of creating a new send.',
          ),
        );
      }
    }

    if (_recentlyAcceptedIds.contains(messageId)) {
      final MessageEntity? accepted = _stateSink.findMessage(messageId);

      if (accepted != null && _isDurablyAccepted(accepted.status)) {
        return Future<MessageEntity>.value(accepted);
      }
    }

    final Future<MessageEntity> operation = _executeSend(
      session: session,
      request: request,
      messageId: messageId,
    );

    _inFlight[messageId] = operation;

    operation.whenComplete(() {
      if (identical(_inFlight[messageId], operation)) {
        _inFlight.remove(messageId);
      }
    });

    return operation;
  }

  Future<MessageEntity> _executeSend({
    required _SenderSession session,
    required MessageSendRequest request,
    required String messageId,
  }) async {
    final int generation = session.generation;

    try {
      final MessageSendRequest normalizedRequest = await _validator
          .validateAndNormalize(
            request.copyWith(
              conversationId: session.conversationId,
              clientMessageId: messageId,
            ),
            authenticatedUid: session.authenticatedUid,
            messageId: messageId,
          );

      _assertSessionStillCurrent(session);

      final String normalizedConversation = _normalizeRequiredIdentifier(
        normalizedRequest.conversationId,
        fieldName: 'normalizedRequest.conversationId',
      );

      if (normalizedConversation != session.conversationId) {
        throw StateError(
          'Outgoing message validation changed the canonical '
          'conversation identity.',
        );
      }

      final String? normalizedRequestId = normalizedRequest.clientMessageId
          ?.trim();

      if (normalizedRequestId != null &&
          normalizedRequestId.isNotEmpty &&
          normalizedRequestId != messageId) {
        throw StateError(
          'Outgoing message validation changed the canonical message ID.',
        );
      }

      final DateTime clientCreatedAt =
          (normalizedRequest.clientCreatedAt ?? DateTime.now().toUtc()).toUtc();

      final MessageEntity queued = MessageEntity(
        id: messageId,
        conversationId: session.conversationId,
        senderUid: session.authenticatedUid,
        type: normalizedRequest.type,
        text: normalizedRequest.text,
        status: MessageStatus.queued,
        attachment: normalizedRequest.attachment,
        replyToMessageId: normalizedRequest.replyToMessageId,
        replyToSenderUid: normalizedRequest.replyToSenderUid,
        replyPreview: normalizedRequest.replyPreview,
        replyType: normalizedRequest.replyType,
        clientCreatedAt: clientCreatedAt,
        serverCreatedAt: null,
        editedAt: null,
        deletedAt: null,
        localOnly: true,
        failureCode: null,
        failureMessage: null,
      );

      await _stateSink.upsertMessage(queued);

      _assertGeneration(generation);

      final MessageEntity sending = queued.copyWith(
        status: MessageStatus.sending,
        localOnly: true,
        clearFailureCode: true,
        clearFailureMessage: true,
      );

      await _stateSink.upsertMessage(sending);

      _assertGeneration(generation);

      final MessageEntity persisted = await _persistence.persistOutgoingMessage(
        sending,
      );

      _validatePersistedIdentity(persisted, expected: sending);

      _assertGeneration(generation);

      final MessageEntity sent = persisted.copyWith(
        status: _acceptedStatus(persisted.status),
        localOnly: false,
        clearFailureCode: true,
        clearFailureMessage: true,
      );

      await _stateSink.upsertMessage(sent);

      _rememberAccepted(messageId);

      return sent;
    } catch (error, stackTrace) {
      final MessageEntity? current = _stateSink.findMessage(messageId);

      if (_isGenerationCurrent(generation) &&
          current != null &&
          current.conversationId == session.conversationId &&
          current.senderUid == session.authenticatedUid &&
          !_isDurablyAccepted(current.status)) {
        await _stateSink.markSendFailed(
          message: current,
          error: error,
          stackTrace: stackTrace,
        );
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Resets only active sender-session state.
  ///
  /// Durable/queued records are not deleted. In-flight remote operations cannot
  /// always be physically cancelled, so session generation invalidation ensures
  /// stale completions cannot mutate the new conversation session.
  Future<void> reset() async {
    _ensureNotDisposed();

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _inFlight.clear();
    _recentlyAcceptedIds.clear();
  }

  /// Permanently disposes this sender.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _inFlight.clear();
    _recentlyAcceptedIds.clear();

    _disposed = true;
  }

  _SenderSession _requireSession({
    required String authenticatedUid,
    required String conversationId,
  }) {
    _ensureNotDisposed();

    if (!_initialized) {
      throw StateError('MessageSender is not initialized.');
    }

    final String uid = _normalizeRequiredIdentifier(
      authenticatedUid,
      fieldName: 'authenticatedUid',
    );

    final String conversation = _normalizeRequiredIdentifier(
      conversationId,
      fieldName: 'conversationId',
    );

    if (_authenticatedUid != uid) {
      throw StateError(
        'MessageSender authenticated UID does not match the active session.',
      );
    }

    if (_conversationId != conversation) {
      throw StateError(
        'MessageSender conversation ID does not match the active session.',
      );
    }

    return _SenderSession(
      authenticatedUid: uid,
      conversationId: conversation,
      generation: _sessionGeneration,
    );
  }

  void _assertSessionStillCurrent(_SenderSession session) {
    if (!_initialized ||
        _disposed ||
        session.generation != _sessionGeneration ||
        session.authenticatedUid != _authenticatedUid ||
        session.conversationId != _conversationId) {
      throw StateError('MessageSender operation belongs to a stale session.');
    }
  }

  void _assertGeneration(int generation) {
    if (!_isGenerationCurrent(generation)) {
      throw StateError(
        'MessageSender operation became stale before completion.',
      );
    }
  }

  bool _isGenerationCurrent(int generation) {
    return !_disposed && _initialized && generation == _sessionGeneration;
  }

  String _resolveMessageId(String? requestedId) {
    if (requestedId != null) {
      final String normalized = requestedId.trim();

      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    final String generated = _messageIdGenerator.nextMessageId().trim();

    if (generated.isEmpty) {
      throw StateError(
        'MessageIdGenerator returned an empty canonical message ID.',
      );
    }

    return generated;
  }

  void _assertExistingIdentity(
    MessageEntity message, {
    required _SenderSession session,
    required String messageId,
  }) {
    if (message.id != messageId) {
      throw StateError(
        'Existing local message has an invalid canonical message ID.',
      );
    }

    if (message.conversationId != session.conversationId) {
      throw StateError('Existing message ID belongs to another conversation.');
    }

    if (message.senderUid != session.authenticatedUid) {
      throw StateError('Existing message ID belongs to another sender.');
    }
  }

  static void _validatePersistedIdentity(
    MessageEntity persisted, {
    required MessageEntity expected,
  }) {
    if (persisted.id != expected.id) {
      throw StateError('Durable persistence changed the canonical message ID.');
    }

    if (persisted.conversationId != expected.conversationId) {
      throw StateError(
        'Durable persistence changed the conversation identity.',
      );
    }

    if (persisted.senderUid != expected.senderUid) {
      throw StateError('Durable persistence changed the sender Firebase UID.');
    }

    if (persisted.type != expected.type) {
      throw StateError(
        'Durable persistence changed the canonical message type.',
      );
    }
  }

  static MessageStatus _acceptedStatus(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
      case MessageStatus.delivered:
      case MessageStatus.read:
        return status;

      case MessageStatus.queued:
      case MessageStatus.sending:
      case MessageStatus.failed:
        return MessageStatus.sent;
    }
  }

  static bool _isDurablyAccepted(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
      case MessageStatus.delivered:
      case MessageStatus.read:
        return true;

      case MessageStatus.queued:
      case MessageStatus.sending:
      case MessageStatus.failed:
        return false;
    }
  }

  void _rememberAccepted(String messageId) {
    _recentlyAcceptedIds.remove(messageId);
    _recentlyAcceptedIds.add(messageId);

    while (_recentlyAcceptedIds.length > _rememberedMessageLimit) {
      _recentlyAcceptedIds.remove(_recentlyAcceptedIds.first);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'MessageSender has already been disposed and cannot be reused.',
      );
    }
  }

  static String _normalizeRequiredIdentifier(
    String value, {
    required String fieldName,
  }) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        fieldName,
        '$fieldName must not be empty.',
      );
    }

    return normalized;
  }

  static int _validateRememberedMessageLimit(int value) {
    if (value < 32 || value > 4096) {
      throw ArgumentError.value(
        value,
        'rememberedMessageLimit',
        'rememberedMessageLimit must be between 32 and 4096.',
      );
    }

    return value;
  }
}

final class _SenderSession {
  const _SenderSession({
    required this.authenticatedUid,
    required this.conversationId,
    required this.generation,
  });

  final String authenticatedUid;
  final String conversationId;
  final int generation;
}

// ============================================================================
// END OF FILE: lib/features/message/engine/message_sender.dart
// ============================================================================
