// ============================================================================
// JR CALL
// File: conversation_repository.dart
// Location: lib/features/message/repository/conversation_repository.dart
// Description:
// Conversation-domain repository facade for the JR CALL Message Engine.
//
// Owns:
// - Stable direct-conversation resolution.
// - Conversation loading and pagination.
// - Realtime conversation-list access.
// - Participant validation.
// - Conversation ordering normalization.
// - Unread/read-boundary coordination.
// - Archive/mute/pin-ready mutation facade.
// - Conversation summary refresh facade.
//
// Does NOT:
// - Search users.
// - Replace UserDiscoveryService.
// - Use JR CALL public ID as internal ownership identity.
// - Own raw Firestore collection references.
// - Own durable message writes.
// - Invent unread/read/presence state.
// - Duplicate Message Engine or Call Engine logic.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/conversation_entity.dart';

/// Opaque paginated conversation result.
///
/// [cursor] belongs to the underlying storage/listener implementation.
/// Controllers must not inspect or construct Firestore cursors directly.
@immutable
final class ConversationRepositoryPage {
  const ConversationRepositoryPage({
    required this.conversations,
    required this.hasMore,
    this.cursor,
  });

  final List<ConversationEntity> conversations;
  final bool hasMore;
  final Object? cursor;

  ConversationRepositoryPage copyWith({
    List<ConversationEntity>? conversations,
    bool? hasMore,
    Object? cursor,
    bool clearCursor = false,
  }) {
    return ConversationRepositoryPage(
      conversations: conversations ?? this.conversations,
      hasMore: hasMore ?? this.hasMore,
      cursor: clearCursor ? null : cursor ?? this.cursor,
    );
  }
}

/// Stable direct-conversation command.
///
/// Both values are canonical Firebase Auth UIDs.
@immutable
final class DirectConversationRequest {
  const DirectConversationRequest({
    required this.currentUid,
    required this.peerUid,
  });

  final String currentUid;
  final String peerUid;

  List<String> get participantUids {
    final List<String> values = <String>[currentUid, peerUid]..sort();

    return List<String>.unmodifiable(values);
  }

  String get stableKey => participantUids.join('::');
}

/// Conversation access command.
@immutable
final class ConversationAccessRequest {
  const ConversationAccessRequest({
    required this.conversationId,
    required this.requesterUid,
  });

  final String conversationId;
  final String requesterUid;
}

/// Conversation archive command.
@immutable
final class ConversationArchiveRequest {
  const ConversationArchiveRequest({
    required this.conversationId,
    required this.requesterUid,
    required this.archived,
  });

  final String conversationId;
  final String requesterUid;
  final bool archived;
}

/// Conversation mute command.
@immutable
final class ConversationMuteRequest {
  const ConversationMuteRequest({
    required this.conversationId,
    required this.requesterUid,
    required this.muted,
  });

  final String conversationId;
  final String requesterUid;
  final bool muted;
}

/// Conversation pin command.
///
/// Pinning remains repository-ready and may be exposed by UI only when the
/// finalized product flow enables it.
@immutable
final class ConversationPinRequest {
  const ConversationPinRequest({
    required this.conversationId,
    required this.requesterUid,
    required this.pinned,
  });

  final String conversationId;
  final String requesterUid;
  final bool pinned;
}

/// Unread/read-boundary acknowledgement.
///
/// This must represent actual read state from the Message Read Engine.
/// It must never be created from elapsed time or mere listener delivery.
@immutable
final class ConversationReadBoundaryRequest {
  const ConversationReadBoundaryRequest({
    required this.conversationId,
    required this.readerUid,
    required this.readMessageId,
    required this.readAt,
  });

  final String conversationId;
  final String readerUid;
  final String readMessageId;
  final DateTime readAt;
}

/// Conversation summary repair/refresh request.
///
/// Durable message creation owns its atomic last-message summary update.
/// This command exists for repository-controlled reconciliation and must not
/// be used to fabricate a last-message value in presentation code.
@immutable
final class ConversationSummaryRefreshRequest {
  const ConversationSummaryRefreshRequest({
    required this.conversationId,
    required this.requesterUid,
  });

  final String conversationId;
  final String requesterUid;
}

/// Storage/realtime boundary consumed by [ConversationRepository].
///
/// The implementation is composed from the already-built Message feature
/// storage/realtime layer. This keeps FILE 36 independent from raw Firestore
/// APIs and prevents controllers from owning listener/query logic.
abstract interface class ConversationRepositoryDelegate {
  /// Finds the existing direct conversation or creates it atomically.
  ///
  /// The implementation must guarantee that the exact same two Firebase UIDs
  /// always resolve to the same direct-conversation identity.
  Future<ConversationEntity> findOrCreateDirect(
    DirectConversationRequest request,
  );

  /// Reads one conversation if [requesterUid] is authorized.
  Future<ConversationEntity?> getConversation(
    ConversationAccessRequest request,
  );

  /// Loads the newest conversation page first.
  Future<ConversationRepositoryPage> load({
    required String requesterUid,
    required int limit,
  });

  /// Loads the next older conversation page.
  Future<ConversationRepositoryPage> paginate({
    required String requesterUid,
    required int limit,
    required Object cursor,
  });

  /// Realtime authenticated inbox stream.
  Stream<List<ConversationEntity>> listen({required String requesterUid});

  /// Server-backed participant membership validation.
  Future<bool> isParticipant(ConversationAccessRequest request);

  /// Authenticated archive mutation.
  Future<ConversationEntity> setArchived(ConversationArchiveRequest request);

  /// Authenticated mute mutation.
  Future<ConversationEntity> setMuted(ConversationMuteRequest request);

  /// Authenticated pin-ready mutation.
  Future<ConversationEntity> setPinned(ConversationPinRequest request);

  /// Applies an actual read boundary and corresponding unread coordination.
  Future<void> markReadBoundary(ConversationReadBoundaryRequest request);

  /// Reconciles conversation summary from trusted durable message state.
  Future<ConversationEntity> refreshSummary(
    ConversationSummaryRefreshRequest request,
  );
}

/// Single conversation-domain repository facade.
///
/// User discovery remains external. A selected DiscoveryUser must provide its
/// canonical Firebase UID before this repository is called.
final class ConversationRepository {
  /// Public construction contract remains:
  ///
  /// ConversationRepository(
  ///   delegate: ...,
  ///   defaultPageSize: ...,
  ///   maximumPageSize: ...,
  /// )
  ///
  /// The factory preserves that frozen named API while the private generative
  /// constructor uses initializing formals, keeping analyzer output clean.
  factory ConversationRepository({
    required ConversationRepositoryDelegate delegate,
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

    return ConversationRepository._(delegate, defaultPageSize, maximumPageSize);
  }

  ConversationRepository._(
    this._delegate,
    this.defaultPageSize,
    this.maximumPageSize,
  );

  final ConversationRepositoryDelegate _delegate;

  final int defaultPageSize;
  final int maximumPageSize;

  final Map<String, Future<ConversationEntity>>
  _activeDirectConversationRequests = <String, Future<ConversationEntity>>{};

  final Map<String, Stream<List<ConversationEntity>>> _inboxStreams =
      <String, Stream<List<ConversationEntity>>>{};

  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Finds or creates a stable direct conversation.
  ///
  /// [currentUid] and [peerUid] must be Firebase Auth UIDs.
  Future<ConversationEntity> findOrCreateDirect({
    required String currentUid,
    required String peerUid,
  }) {
    _ensureActive();

    final String normalizedCurrentUid = _requiredId(currentUid, 'currentUid');

    final String normalizedPeerUid = _requiredId(peerUid, 'peerUid');

    if (normalizedCurrentUid == normalizedPeerUid) {
      throw ArgumentError(
        'A direct conversation requires two different Firebase UIDs.',
      );
    }

    final DirectConversationRequest request = DirectConversationRequest(
      currentUid: normalizedCurrentUid,
      peerUid: normalizedPeerUid,
    );

    final String operationKey = request.stableKey;

    final Future<ConversationEntity>? existing =
        _activeDirectConversationRequests[operationKey];

    if (existing != null) {
      return existing;
    }

    final Future<ConversationEntity> operation = _delegate.findOrCreateDirect(
      request,
    );

    _activeDirectConversationRequests[operationKey] = operation;

    unawaited(
      operation.whenComplete(() {
        if (identical(
          _activeDirectConversationRequests[operationKey],
          operation,
        )) {
          _activeDirectConversationRequests.remove(operationKey);
        }
      }),
    );

    return operation;
  }

  /// Loads one authorized conversation.
  Future<ConversationEntity?> getConversation({
    required String conversationId,
    required String requesterUid,
  }) {
    _ensureActive();

    return _delegate.getConversation(
      ConversationAccessRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        requesterUid: _requiredId(requesterUid, 'requesterUid'),
      ),
    );
  }

  /// Loads the newest inbox page.
  Future<ConversationRepositoryPage> load({
    required String requesterUid,
    int? limit,
  }) async {
    _ensureActive();

    final ConversationRepositoryPage result = await _delegate.load(
      requesterUid: _requiredId(requesterUid, 'requesterUid'),
      limit: _normalizePageSize(limit),
    );

    return _normalizePage(result);
  }

  /// Loads an older inbox page from an opaque cursor.
  Future<ConversationRepositoryPage> paginate({
    required String requesterUid,
    required Object cursor,
    int? limit,
  }) async {
    _ensureActive();

    final ConversationRepositoryPage result = await _delegate.paginate(
      requesterUid: _requiredId(requesterUid, 'requesterUid'),
      limit: _normalizePageSize(limit),
      cursor: cursor,
    );

    return _normalizePage(result);
  }

  /// Realtime authenticated conversation list.
  ///
  /// One shared stream is cached per Firebase UID to prevent controllers from
  /// repeatedly constructing equivalent repository streams.
  Stream<List<ConversationEntity>> listen({required String requesterUid}) {
    _ensureActive();

    final String uid = _requiredId(requesterUid, 'requesterUid');

    return _inboxStreams.putIfAbsent(uid, () {
      return _delegate
          .listen(requesterUid: uid)
          .map(_normalizeConversations)
          .asBroadcastStream();
    });
  }

  /// Validates that the authenticated Firebase UID is a participant.
  ///
  /// Firebase Security Rules remain the final server authority.
  Future<bool> isParticipant({
    required String conversationId,
    required String requesterUid,
  }) {
    _ensureActive();

    return _delegate.isParticipant(
      ConversationAccessRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        requesterUid: _requiredId(requesterUid, 'requesterUid'),
      ),
    );
  }

  /// Archives/unarchives a conversation for the authenticated user according
  /// to the finalized conversation policy.
  Future<ConversationEntity> setArchived({
    required String conversationId,
    required String requesterUid,
    required bool archived,
  }) {
    _ensureActive();

    return _delegate.setArchived(
      ConversationArchiveRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        requesterUid: _requiredId(requesterUid, 'requesterUid'),
        archived: archived,
      ),
    );
  }

  /// Mutes/unmutes a conversation for the authenticated user.
  Future<ConversationEntity> setMuted({
    required String conversationId,
    required String requesterUid,
    required bool muted,
  }) {
    _ensureActive();

    return _delegate.setMuted(
      ConversationMuteRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        requesterUid: _requiredId(requesterUid, 'requesterUid'),
        muted: muted,
      ),
    );
  }

  /// Sets pin state when enabled by the controller/product UI.
  Future<ConversationEntity> setPinned({
    required String conversationId,
    required String requesterUid,
    required bool pinned,
  }) {
    _ensureActive();

    return _delegate.setPinned(
      ConversationPinRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        requesterUid: _requiredId(requesterUid, 'requesterUid'),
        pinned: pinned,
      ),
    );
  }

  /// Coordinates actual read boundary/unread state.
  ///
  /// Calling code must only invoke this after MessageReadEngine/controller
  /// policy has determined that the durable message was actually read.
  Future<void> markReadBoundary({
    required String conversationId,
    required String readerUid,
    required String readMessageId,
    required DateTime readAt,
  }) {
    _ensureActive();

    return _delegate.markReadBoundary(
      ConversationReadBoundaryRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        readerUid: _requiredId(readerUid, 'readerUid'),
        readMessageId: _requiredId(readMessageId, 'readMessageId'),
        readAt: readAt.toUtc(),
      ),
    );
  }

  /// Reconciles the conversation summary from trusted durable server state.
  ///
  /// This does not permit UI code to provide arbitrary last-message fields.
  Future<ConversationEntity> refreshSummary({
    required String conversationId,
    required String requesterUid,
  }) {
    _ensureActive();

    return _delegate.refreshSummary(
      ConversationSummaryRefreshRequest(
        conversationId: _requiredId(conversationId, 'conversationId'),
        requesterUid: _requiredId(requesterUid, 'requesterUid'),
      ),
    );
  }

  /// Releases the repository's cached stream reference for one authenticated
  /// inbox. The underlying ConversationListener remains responsible for its
  /// own Firestore subscription cancellation/disposal.
  void releaseListener({required String requesterUid}) {
    if (_disposed) {
      return;
    }

    final String uid = requesterUid.trim();

    if (uid.isEmpty) {
      return;
    }

    _inboxStreams.remove(uid);
  }

  void clearListenerCache() {
    if (_disposed) {
      return;
    }

    _inboxStreams.clear();
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _inboxStreams.clear();
    _activeDirectConversationRequests.clear();
  }

  ConversationRepositoryPage _normalizePage(ConversationRepositoryPage page) {
    return ConversationRepositoryPage(
      conversations: _normalizeConversations(page.conversations),
      hasMore: page.hasMore,
      cursor: page.cursor,
    );
  }

  List<ConversationEntity> _normalizeConversations(
    List<ConversationEntity> input,
  ) {
    if (input.isEmpty) {
      return const <ConversationEntity>[];
    }

    final Map<String, ConversationEntity> byId = <String, ConversationEntity>{};

    for (final ConversationEntity conversation in input) {
      final String id = conversation.id.trim();

      if (id.isEmpty) {
        continue;
      }

      final ConversationEntity? previous = byId[id];

      if (previous == null) {
        byId[id] = conversation;
        continue;
      }

      byId[id] = _preferNewestConversation(previous, conversation);
    }

    final List<ConversationEntity> result = byId.values.toList(growable: false);

    result.sort(_compareConversations);

    return List<ConversationEntity>.unmodifiable(result);
  }

  ConversationEntity _preferNewestConversation(
    ConversationEntity first,
    ConversationEntity second,
  ) {
    final DateTime firstTime = _conversationSortTime(first);
    final DateTime secondTime = _conversationSortTime(second);

    if (secondTime.isAfter(firstTime)) {
      return second;
    }

    if (firstTime.isAfter(secondTime)) {
      return first;
    }

    return second.id.compareTo(first.id) >= 0 ? second : first;
  }

  int _compareConversations(ConversationEntity left, ConversationEntity right) {
    final DateTime leftTime = _conversationSortTime(left);
    final DateTime rightTime = _conversationSortTime(right);

    final int timeOrder = rightTime.compareTo(leftTime);

    if (timeOrder != 0) {
      return timeOrder;
    }

    return left.id.compareTo(right.id);
  }

  DateTime _conversationSortTime(ConversationEntity conversation) {
    // ConversationEntity.updatedAt is non-null in the finalized data model.
    //
    // Therefore:
    // - lastMessageAt is preferred when a durable last-message timestamp exists.
    // - updatedAt is the valid deterministic fallback.
    //
    // Adding `?? conversation.createdAt` after updatedAt would be unreachable
    // and causes the analyzer dead-code/unnecessary-null-aware warnings.
    return conversation.lastMessageAt ?? conversation.updatedAt;
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

  void _ensureActive() {
    if (_disposed) {
      throw StateError('ConversationRepository has already been disposed.');
    }
  }
}

// ============================================================================
// END OF FILE:
// lib/features/message/repository/conversation_repository.dart
// ============================================================================
