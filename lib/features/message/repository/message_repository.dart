// ============================================================================
// JR CALL
// File: message_repository.dart
// Location: lib/features/message/repository/message_repository.dart
// Description:
// Single message-domain repository facade for the JR CALL Message Engine.
//
// Connects the UI/controller layer with the existing Message Engine domain
// without exposing raw Firestore/Firebase Storage implementation.
//
// Owns:
// - Typed durable message operations.
// - Send/retry/edit/delete/react facade.
// - Initial page loading and older-page pagination.
// - Durable realtime timeline subscription.
// - Delivery/read acknowledgement facade.
// - Typing publication.
// - JR CALL Live Chat ephemeral draft publication/clear.
// - Stable operation guards.
// - Repository subscription lifecycle.
//
// Does NOT:
// - Own Firestore collection references.
// - Upload raw Firebase Storage data directly.
// - Invent sent/delivered/read state.
// - Duplicate Message Engine retry/sync logic.
// - Duplicate Call Engine/WebRTC.
// - Perform UI rendering.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controller/message_composer_controller.dart';
import '../data/attachment_entity.dart';
import '../data/message_entity.dart';
import '../data/reaction_entity.dart';

/// A deterministic page of durable messages.
///
/// [cursor] is intentionally opaque to controllers/presentation. The actual
/// Firestore pagination cursor remains owned by the storage/realtime layer.
@immutable
final class MessageRepositoryPage {
  const MessageRepositoryPage({
    required this.messages,
    required this.hasMore,
    this.cursor,
  });

  final List<MessageEntity> messages;
  final bool hasMore;
  final Object? cursor;

  MessageRepositoryPage copyWith({
    List<MessageEntity>? messages,
    bool? hasMore,
    Object? cursor,
    bool clearCursor = false,
  }) {
    return MessageRepositoryPage(
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      cursor: clearCursor ? null : cursor ?? this.cursor,
    );
  }
}

/// Durable text edit command.
///
/// The canonical message ID never changes.
@immutable
final class MessageEditRequest {
  const MessageEditRequest({
    required this.conversationId,
    required this.messageId,
    required this.requesterUid,
    required this.text,
  });

  final String conversationId;
  final String messageId;
  final String requesterUid;
  final String text;
}

/// Durable message delete command.
@immutable
final class MessageDeleteRequest {
  const MessageDeleteRequest({
    required this.conversationId,
    required this.messageId,
    required this.requesterUid,
  });

  final String conversationId;
  final String messageId;
  final String requesterUid;
}

/// Reaction mutation command.
///
/// A null/empty [reaction] means remove the authenticated user's current
/// reaction.
@immutable
final class MessageReactionRequest {
  const MessageReactionRequest({
    required this.conversationId,
    required this.messageId,
    required this.userUid,
    required this.reaction,
  });

  final String conversationId;
  final String messageId;
  final String userUid;
  final String? reaction;
}

/// Delivery receipt acknowledgement.
///
/// This represents a real recipient acknowledgement request. The underlying
/// Message Delivery Engine remains responsible for enforcing monotonic state.
@immutable
final class MessageDeliveryRequest {
  const MessageDeliveryRequest({
    required this.conversationId,
    required this.messageIds,
    required this.recipientUid,
  });

  final String conversationId;
  final List<String> messageIds;
  final String recipientUid;
}

/// Read receipt acknowledgement.
///
/// Messages must only be supplied after the controller/presentation has
/// determined they were actually visible/read.
@immutable
final class MessageReadRequest {
  const MessageReadRequest({
    required this.conversationId,
    required this.messageIds,
    required this.readerUid,
  });

  final String conversationId;
  final List<String> messageIds;
  final String readerUid;
}

/// Message-domain operation boundary implemented by the previously-built
/// Message Engine/storage/realtime composition root.
///
/// This is deliberately typed and Firebase-agnostic. It prevents controllers
/// from depending on raw Firestore/Storage while allowing FILE 35 to remain
/// the single repository facade.
///
/// The application composition layer binds these operations to:
/// - JRMessageEngine
/// - MessageRemoteStore
/// - MessageDatabase / MessageCacheStore
/// - MediaUploadManager
/// - MessageListener / ReceiptListener / TypingListener
abstract interface class MessageRepositoryDelegate {
  /// Creates/sends one durable composer payload.
  Future<MessageEntity> send(MessageComposerSendRequest request);

  /// Retries the same canonical message ID.
  Future<MessageEntity> retry({
    required String conversationId,
    required String messageId,
    required String requesterUid,
  });

  /// Edits one sender-owned text message without changing its canonical ID.
  Future<MessageEntity> edit(MessageEditRequest request);

  /// Applies the durable server delete/tombstone policy.
  Future<MessageEntity> delete(MessageDeleteRequest request);

  /// Creates, changes, or removes the authenticated user's reaction.
  Future<ReactionEntity?> react(MessageReactionRequest request);

  /// Loads the newest durable message page first.
  Future<MessageRepositoryPage> load({
    required String conversationId,
    required String requesterUid,
    required int limit,
  });

  /// Loads one older durable page.
  Future<MessageRepositoryPage> paginate({
    required String conversationId,
    required String requesterUid,
    required int limit,
    required Object cursor,
  });

  /// Realtime durable timeline.
  ///
  /// The underlying listener is responsible for dedupe, stale-listener
  /// rejection and deterministic ordering.
  Stream<List<MessageEntity>> listen({
    required String conversationId,
    required String requesterUid,
  });

  /// Real delivery acknowledgement.
  Future<void> markDelivered(MessageDeliveryRequest request);

  /// Real read acknowledgement.
  Future<void> markRead(MessageReadRequest request);

  /// Normal typing state publication.
  Future<void> publishTyping(MessageComposerTypingState state);

  /// JR CALL Live Chat ephemeral draft publication.
  Future<void> publishLiveDraft(MessageComposerLiveDraft draft);

  /// Clears/expires the authenticated user's ephemeral Live Chat draft.
  Future<void> clearLiveDraft({
    required String conversationId,
    required String senderUid,
    required String sessionId,
    required int version,
  });
}

/// Single JR CALL durable-message repository facade.
///
/// Controllers should depend on this class rather than raw Firebase APIs.
final class MessageRepository implements MessageComposerDelegate {
  /// Keeps the existing public construction API unchanged while allowing
  /// analyzer-clean field initialization through the private generative
  /// constructor below.
  factory MessageRepository({
    required MessageRepositoryDelegate delegate,
    int defaultPageSize = 30,
    int maximumPageSize = 100,
  }) {
    if (defaultPageSize <= 0) {
      throw ArgumentError.value(
        defaultPageSize,
        'defaultPageSize',
        'Page size must be greater than zero.',
      );
    }

    if (maximumPageSize <= 0) {
      throw ArgumentError.value(
        maximumPageSize,
        'maximumPageSize',
        'Maximum page size must be greater than zero.',
      );
    }

    if (defaultPageSize > maximumPageSize) {
      throw ArgumentError('defaultPageSize cannot exceed maximumPageSize.');
    }

    return MessageRepository._(delegate, defaultPageSize, maximumPageSize);
  }

  MessageRepository._(
    this._delegate,
    this.defaultPageSize,
    this.maximumPageSize,
  );

  final MessageRepositoryDelegate _delegate;

  final int defaultPageSize;
  final int maximumPageSize;

  final Map<String, Future<MessageEntity>> _activeSends =
      <String, Future<MessageEntity>>{};

  final Map<String, Future<MessageEntity>> _activeRetries =
      <String, Future<MessageEntity>>{};

  final Map<String, Stream<List<MessageEntity>>> _timelineStreams =
      <String, Stream<List<MessageEntity>>>{};

  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Sends one durable message request.
  ///
  /// Duplicate rapid execution is prevented when a stable message identity is
  /// already available through attachment metadata/edit identity. The deeper
  /// MessageSender remains the final stable-message-ID duplicate authority.
  Future<MessageEntity> send(MessageComposerSendRequest request) {
    _ensureActive();
    _validateSendRequest(request);

    final String operationKey = _sendOperationKey(request);

    final Future<MessageEntity>? existing = _activeSends[operationKey];

    if (existing != null) {
      return existing;
    }

    final Future<MessageEntity> operation = _delegate.send(request);

    _activeSends[operationKey] = operation;

    unawaited(
      operation.whenComplete(() {
        if (identical(_activeSends[operationKey], operation)) {
          _activeSends.remove(operationKey);
        }
      }),
    );

    return operation;
  }

  /// Retries one failed message using the same canonical message ID.
  Future<MessageEntity> retry({
    required String conversationId,
    required String messageId,
    required String requesterUid,
  }) {
    _ensureActive();

    final String normalizedConversationId = _requiredId(
      conversationId,
      'conversationId',
    );

    final String normalizedMessageId = _requiredId(messageId, 'messageId');

    final String normalizedUid = _requiredId(requesterUid, 'requesterUid');

    final String operationKey =
        '$normalizedConversationId::$normalizedMessageId';

    final Future<MessageEntity>? existing = _activeRetries[operationKey];

    if (existing != null) {
      return existing;
    }

    final Future<MessageEntity> operation = _delegate.retry(
      conversationId: normalizedConversationId,
      messageId: normalizedMessageId,
      requesterUid: normalizedUid,
    );

    _activeRetries[operationKey] = operation;

    unawaited(
      operation.whenComplete(() {
        if (identical(_activeRetries[operationKey], operation)) {
          _activeRetries.remove(operationKey);
        }
      }),
    );

    return operation;
  }

  /// Edits one sender-owned durable message.
  Future<MessageEntity> edit({
    required String conversationId,
    required String messageId,
    required String requesterUid,
    required String text,
  }) {
    _ensureActive();

    final MessageEditRequest request = MessageEditRequest(
      conversationId: _requiredId(conversationId, 'conversationId'),
      messageId: _requiredId(messageId, 'messageId'),
      requesterUid: _requiredId(requesterUid, 'requesterUid'),
      text: _normalizeText(text),
    );

    if (request.text.isEmpty) {
      throw ArgumentError.value(
        text,
        'text',
        'Edited message text must not be empty.',
      );
    }

    return _delegate.edit(request);
  }

  /// Deletes one sender-owned durable message according to server policy.
  Future<MessageEntity> delete({
    required String conversationId,
    required String messageId,
    required String requesterUid,
  }) {
    _ensureActive();

    return _delegate.delete(
      MessageDeleteRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        messageId: _requiredId(messageId, 'messageId'),
        requesterUid: _requiredId(requesterUid, 'requesterUid'),
      ),
    );
  }

  /// Creates/changes/removes the authenticated user's reaction.
  Future<ReactionEntity?> react({
    required String conversationId,
    required String messageId,
    required String userUid,
    required String? reaction,
  }) {
    _ensureActive();

    final String? normalizedReaction = _normalizeReaction(reaction);

    return _delegate.react(
      MessageReactionRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        messageId: _requiredId(messageId, 'messageId'),
        userUid: _requiredId(userUid, 'userUid'),
        reaction: normalizedReaction,
      ),
    );
  }

  /// Loads the newest page first.
  Future<MessageRepositoryPage> load({
    required String conversationId,
    required String requesterUid,
    int? limit,
  }) async {
    _ensureActive();

    final MessageRepositoryPage page = await _delegate.load(
      conversationId: _requiredId(conversationId, 'conversationId'),
      requesterUid: _requiredId(requesterUid, 'requesterUid'),
      limit: _normalizePageSize(limit),
    );

    return _normalizePage(page);
  }

  /// Loads one older page from an opaque cursor previously returned by load or
  /// paginate.
  Future<MessageRepositoryPage> paginate({
    required String conversationId,
    required String requesterUid,
    required Object cursor,
    int? limit,
  }) async {
    _ensureActive();

    final MessageRepositoryPage page = await _delegate.paginate(
      conversationId: _requiredId(conversationId, 'conversationId'),
      requesterUid: _requiredId(requesterUid, 'requesterUid'),
      limit: _normalizePageSize(limit),
      cursor: cursor,
    );

    return _normalizePage(page);
  }

  /// Returns one shared durable timeline stream per authenticated
  /// conversation/user pair.
  ///
  /// Underlying MessageListener remains the listener owner and is responsible
  /// for cancelling its Firestore subscription when that domain listener is
  /// released.
  Stream<List<MessageEntity>> listen({
    required String conversationId,
    required String requesterUid,
  }) {
    _ensureActive();

    final String normalizedConversationId = _requiredId(
      conversationId,
      'conversationId',
    );

    final String normalizedUid = _requiredId(requesterUid, 'requesterUid');

    final String key = '$normalizedConversationId::$normalizedUid';

    return _timelineStreams.putIfAbsent(key, () {
      return _delegate
          .listen(
            conversationId: normalizedConversationId,
            requesterUid: normalizedUid,
          )
          .map(_normalizeTimeline)
          .asBroadcastStream();
    });
  }

  /// Sends a real recipient delivery acknowledgement.
  Future<void> markDelivered({
    required String conversationId,
    required Iterable<String> messageIds,
    required String recipientUid,
  }) {
    _ensureActive();

    final List<String> normalizedIds = _normalizeMessageIds(messageIds);

    if (normalizedIds.isEmpty) {
      return Future<void>.value();
    }

    return _delegate.markDelivered(
      MessageDeliveryRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        messageIds: normalizedIds,
        recipientUid: _requiredId(recipientUid, 'recipientUid'),
      ),
    );
  }

  /// Sends a real read acknowledgement only for messages the recipient has
  /// actually opened/read according to controller policy.
  Future<void> markRead({
    required String conversationId,
    required Iterable<String> messageIds,
    required String readerUid,
  }) {
    _ensureActive();

    final List<String> normalizedIds = _normalizeMessageIds(messageIds);

    if (normalizedIds.isEmpty) {
      return Future<void>.value();
    }

    return _delegate.markRead(
      MessageReadRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        messageIds: normalizedIds,
        readerUid: _requiredId(readerUid, 'readerUid'),
      ),
    );
  }

  /// Normal typing publication used by MessageComposerController.
  @override
  Future<void> publishTyping(MessageComposerTypingState state) {
    _ensureActive();

    _requiredId(state.conversationId, 'state.conversationId');

    _requiredId(state.senderUid, 'state.senderUid');

    return _delegate.publishTyping(state);
  }

  /// JR CALL Live Chat ephemeral publication.
  @override
  Future<void> publishLiveDraft(MessageComposerLiveDraft draft) {
    _ensureActive();

    _requiredId(draft.conversationId, 'draft.conversationId');

    _requiredId(draft.senderUid, 'draft.senderUid');

    _requiredId(draft.sessionId, 'draft.sessionId');

    if (draft.version < 0) {
      throw ArgumentError.value(
        draft.version,
        'draft.version',
        'Live draft version cannot be negative.',
      );
    }

    if (draft.active && draft.text.trim().isEmpty) {
      throw ArgumentError('An active Live Chat draft must contain text.');
    }

    if (draft.active && !draft.expiresAt.isAfter(draft.updatedAt)) {
      throw ArgumentError('Active Live Chat expiry must be after updatedAt.');
    }

    return _delegate.publishLiveDraft(draft);
  }

  /// Clears the authenticated user's Live Chat ephemeral state.
  @override
  Future<void> clearLiveDraft({
    required String conversationId,
    required String senderUid,
    required String sessionId,
    required int version,
  }) {
    _ensureActive();

    if (version < 0) {
      throw ArgumentError.value(
        version,
        'version',
        'Live draft version cannot be negative.',
      );
    }

    return _delegate.clearLiveDraft(
      conversationId: _requiredId(conversationId, 'conversationId'),
      senderUid: _requiredId(senderUid, 'senderUid'),
      sessionId: _requiredId(sessionId, 'sessionId'),
      version: version,
    );
  }

  /// Required by FILE 34 [MessageComposerDelegate].
  @override
  Future<MessageEntity> sendComposerRequest(
    MessageComposerSendRequest request,
  ) {
    return send(request);
  }

  /// Removes a cached shared timeline stream key.
  ///
  /// The actual realtime subscription lifecycle remains owned by the
  /// underlying realtime/message listener composition.
  void releaseTimeline({
    required String conversationId,
    required String requesterUid,
  }) {
    if (_disposed) {
      return;
    }

    final String normalizedConversationId = conversationId.trim();
    final String normalizedUid = requesterUid.trim();

    if (normalizedConversationId.isEmpty || normalizedUid.isEmpty) {
      return;
    }

    _timelineStreams.remove('$normalizedConversationId::$normalizedUid');
  }

  void clearTimelineCache() {
    if (_disposed) {
      return;
    }

    _timelineStreams.clear();
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _timelineStreams.clear();
    _activeSends.clear();
    _activeRetries.clear();
  }

  void _validateSendRequest(MessageComposerSendRequest request) {
    _requiredId(request.conversationId, 'request.conversationId');

    _requiredId(request.senderUid, 'request.senderUid');

    if (!request.hasContent) {
      throw ArgumentError('A durable message requires text or an attachment.');
    }

    final String? replyId = request.replyToMessageId?.trim();
    final String? editId = request.editMessageId?.trim();

    if (replyId != null && replyId.isEmpty) {
      throw ArgumentError.value(
        request.replyToMessageId,
        'request.replyToMessageId',
        'Reply message ID cannot be blank.',
      );
    }

    if (editId != null && editId.isEmpty) {
      throw ArgumentError.value(
        request.editMessageId,
        'request.editMessageId',
        'Edit message ID cannot be blank.',
      );
    }

    if (replyId != null && editId != null) {
      throw ArgumentError(
        'A composer request cannot be reply and edit simultaneously.',
      );
    }

    if (editId != null && request.attachments.isNotEmpty) {
      throw ArgumentError('Attachments are not supported during text edit.');
    }

    final Set<String> attachmentIds = <String>{};

    for (final AttachmentEntity attachment in request.attachments) {
      final String attachmentId = _requiredId(attachment.id, 'attachment.id');

      if (!attachmentIds.add(attachmentId)) {
        throw ArgumentError('Duplicate attachment ID: $attachmentId');
      }

      if (attachment.conversationId != request.conversationId) {
        throw ArgumentError(
          'Attachment conversation ID does not match the message.',
        );
      }

      if (attachment.ownerUid != request.senderUid) {
        throw ArgumentError(
          'Attachment owner UID must match sender Firebase UID.',
        );
      }
    }
  }

  MessageRepositoryPage _normalizePage(MessageRepositoryPage page) {
    return MessageRepositoryPage(
      messages: _normalizeTimeline(page.messages),
      hasMore: page.hasMore,
      cursor: page.cursor,
    );
  }

  List<MessageEntity> _normalizeTimeline(List<MessageEntity> input) {
    if (input.isEmpty) {
      return const <MessageEntity>[];
    }

    final Map<String, MessageEntity> byId = <String, MessageEntity>{};

    for (final MessageEntity message in input) {
      final String id = message.id.trim();

      if (id.isEmpty) {
        continue;
      }

      final MessageEntity? previous = byId[id];

      if (previous == null) {
        byId[id] = message;
        continue;
      }

      byId[id] = _preferServerResolved(previous, message);
    }

    final List<MessageEntity> result = byId.values.toList(growable: false);

    result.sort(_compareMessages);

    return List<MessageEntity>.unmodifiable(result);
  }

  MessageEntity _preferServerResolved(
    MessageEntity first,
    MessageEntity second,
  ) {
    final DateTime? firstServer = first.serverCreatedAt;
    final DateTime? secondServer = second.serverCreatedAt;

    if (firstServer == null && secondServer != null) {
      return second;
    }

    if (firstServer != null && secondServer == null) {
      return first;
    }

    final DateTime firstUpdated =
        first.editedAt ??
        first.deletedAt ??
        first.serverCreatedAt ??
        first.clientCreatedAt;

    final DateTime secondUpdated =
        second.editedAt ??
        second.deletedAt ??
        second.serverCreatedAt ??
        second.clientCreatedAt;

    return secondUpdated.isAfter(firstUpdated) ? second : first;
  }

  int _compareMessages(MessageEntity left, MessageEntity right) {
    final DateTime leftTime = left.serverCreatedAt ?? left.clientCreatedAt;

    final DateTime rightTime = right.serverCreatedAt ?? right.clientCreatedAt;

    final int timestampOrder = leftTime.compareTo(rightTime);

    if (timestampOrder != 0) {
      return timestampOrder;
    }

    return left.id.compareTo(right.id);
  }

  List<String> _normalizeMessageIds(Iterable<String> ids) {
    final Set<String> unique = <String>{};

    for (final String value in ids) {
      final String normalized = value.trim();

      if (normalized.isNotEmpty) {
        unique.add(normalized);
      }
    }

    final List<String> result = unique.toList(growable: false);

    result.sort();

    return List<String>.unmodifiable(result);
  }

  int _normalizePageSize(int? requested) {
    final int value = requested ?? defaultPageSize;

    if (value <= 0) {
      throw ArgumentError.value(
        requested,
        'limit',
        'Page size must be greater than zero.',
      );
    }

    if (value > maximumPageSize) {
      return maximumPageSize;
    }

    return value;
  }

  String _requiredId(String value, String fieldName) {
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

  String _normalizeText(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  }

  String? _normalizeReaction(String? value) {
    if (value == null) {
      return null;
    }

    final String normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  String _sendOperationKey(MessageComposerSendRequest request) {
    final String? editMessageId = request.editMessageId?.trim();

    if (editMessageId != null && editMessageId.isNotEmpty) {
      return '${request.conversationId}::edit::$editMessageId';
    }

    final List<String> attachmentIds =
        request.attachments
            .map((AttachmentEntity item) => item.id)
            .where((String id) => id.trim().isNotEmpty)
            .toList(growable: false)
          ..sort();

    if (attachmentIds.isNotEmpty) {
      return '${request.conversationId}::media::'
          '${attachmentIds.join(",")}';
    }

    final String normalizedText = _normalizeText(request.text);

    final String reply = request.replyToMessageId?.trim() ?? '';

    return '${request.conversationId}::text::'
        '${request.senderUid}::$reply::$normalizedText';
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('MessageRepository has already been disposed.');
    }
  }
}

// ============================================================================
// END OF FILE: lib/features/message/repository/message_repository.dart
// ============================================================================
