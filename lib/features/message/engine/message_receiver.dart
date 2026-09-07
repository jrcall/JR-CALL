// ============================================================================
// JR CALL
// File: message_receiver.dart
// Location: lib/features/message/engine/message_receiver.dart
// Description:
// Production incoming durable-message processing engine.
//
// Responsibilities:
// - Validates authenticated conversation context.
// - Validates and safely normalizes incoming durable messages.
// - Rejects malformed, stale and duplicate incoming events.
// - Merges server entities with matching local optimistic entities.
// - Preserves canonical Firebase UID/message/conversation identity.
// - Maintains monotonic message status.
// - Feeds normalized entities into local/cache synchronization state.
// - Triggers REAL recipient-side delivery acknowledgement.
// - Protects against stale callbacks after reset/conversation change.
//
// Important:
// - Does NOT render UI.
// - Does NOT mark messages as read.
// - Does NOT fabricate delivered/read states.
// - Does NOT persist media binary.
// - Does NOT own Firestore collection references.
// - Does NOT contain Call Engine/WebRTC logic.
// ============================================================================

import 'dart:async';
import 'dart:collection';

import '../data/message_entity.dart';
import '../data/message_status.dart';

/// Source classification for an incoming durable-message event.
///
/// This helps the receiver distinguish authoritative remote entities from
/// reconciliation/cache events without coupling it to Firestore APIs.
enum MessageReceiveSource { realtime, initialSync, pagination, reconciliation }

/// Result of processing an incoming durable message.
enum MessageReceiveDisposition {
  accepted,
  merged,
  duplicate,
  stale,
  ignoredSelf,
}

/// Immutable receiver result.
///
/// [message] is populated when a canonical entity was accepted or merged.
final class MessageReceiveResult {
  const MessageReceiveResult({required this.disposition, this.message});

  final MessageReceiveDisposition disposition;
  final MessageEntity? message;

  bool get changed =>
      disposition == MessageReceiveDisposition.accepted ||
      disposition == MessageReceiveDisposition.merged;
}

/// Validation/security adapter required by [MessageReceiver].
///
/// FILE 29 / FILE 31 may provide the concrete implementation later.
abstract interface class MessageReceiverValidator {
  /// Validates that the authenticated Firebase UID may access the conversation.
  FutureOr<void> validateReceiveContext({
    required String authenticatedUid,
    required String conversationId,
  });

  /// Validates and safely normalizes an incoming durable entity.
  ///
  /// Implementations must not replace canonical identity fields with public
  /// JR CALL IDs, names, phone numbers, usernames or email addresses.
  FutureOr<MessageEntity> validateAndNormalizeIncoming(
    MessageEntity message, {
    required String authenticatedUid,
    required String conversationId,
  });
}

/// Local/cache state bridge used by [MessageReceiver].
///
/// MessageSyncEngine / repository/cache infrastructure owns the concrete
/// implementation.
abstract interface class MessageReceiverStateSink {
  /// Returns the locally known canonical entity for [messageId], if any.
  MessageEntity? findMessage(String messageId);

  /// Inserts or replaces one normalized canonical durable message.
  FutureOr<void> upsertMessage(MessageEntity message);
}

/// Real delivery acknowledgement bridge.
///
/// The concrete implementation is expected to route through
/// MessageDeliveryEngine / repository infrastructure.
///
/// Calling this method means recipient-side delivery has genuinely occurred.
/// Implementations must never manufacture delivery based on elapsed time.
abstract interface class MessageReceiverDeliverySink {
  FutureOr<void> acknowledgeDelivered({
    required String authenticatedUid,
    required String conversationId,
    required String messageId,
  });
}

/// Production incoming durable-message processor.
final class MessageReceiver {
  factory MessageReceiver({
    required MessageReceiverValidator validator,
    required MessageReceiverStateSink stateSink,
    required MessageReceiverDeliverySink deliverySink,
    int rememberedMessageLimit = 1024,
  }) {
    return MessageReceiver._(
      validator,
      stateSink,
      deliverySink,
      _validateRememberedMessageLimit(rememberedMessageLimit),
    );
  }

  MessageReceiver._(
    this._validator,
    this._stateSink,
    this._deliverySink,
    this._rememberedMessageLimit,
  );

  final MessageReceiverValidator _validator;
  final MessageReceiverStateSink _stateSink;
  final MessageReceiverDeliverySink _deliverySink;

  final int _rememberedMessageLimit;

  final LinkedHashMap<String, _MessageFingerprint> _recentFingerprints =
      LinkedHashMap<String, _MessageFingerprint>();

  final Set<String> _deliveryAcknowledgementInFlight = <String>{};
  final Set<String> _deliveryAcknowledged = <String>{};

  String? _authenticatedUid;
  String? _conversationId;

  int _sessionGeneration = 0;

  bool _initialized = false;
  bool _disposed = false;

  /// True while configured for an authenticated conversation.
  bool get isInitialized => _initialized && !_disposed;

  /// True after permanent disposal.
  bool get isDisposed => _disposed;

  /// Initializes this receiver for one authenticated conversation.
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

    await _validator.validateReceiveContext(
      authenticatedUid: uid,
      conversationId: conversation,
    );

    ++_sessionGeneration;

    _authenticatedUid = uid;
    _conversationId = conversation;
    _initialized = true;
  }

  /// Processes one durable incoming entity.
  ///
  /// The canonical message ID is used for deduplication and optimistic/server
  /// reconciliation.
  Future<MessageReceiveResult> receive(
    MessageEntity incoming, {
    MessageReceiveSource source = MessageReceiveSource.realtime,
  }) async {
    final _ReceiverSession session = _requireActiveSession();
    final int generation = session.generation;

    _validateRawIdentity(incoming, session: session);

    final MessageEntity normalized = await _validator
        .validateAndNormalizeIncoming(
          incoming,
          authenticatedUid: session.authenticatedUid,
          conversationId: session.conversationId,
        );

    _assertGeneration(generation);

    _validateNormalizedIdentity(
      original: incoming,
      normalized: normalized,
      session: session,
    );

    final MessageEntity? local = _stateSink.findMessage(normalized.id);

    final MessageEntity canonical;

    final MessageReceiveDisposition disposition;

    if (local == null) {
      final _MessageFingerprint fingerprint = _MessageFingerprint.fromMessage(
        normalized,
      );

      final _MessageFingerprint? previous = _recentFingerprints[normalized.id];

      if (previous == fingerprint) {
        await _acknowledgeDeliveryIfRequired(
          message: normalized,
          session: session,
          generation: generation,
        );

        return const MessageReceiveResult(
          disposition: MessageReceiveDisposition.duplicate,
        );
      }

      canonical = normalized;
      disposition = MessageReceiveDisposition.accepted;
    } else {
      _validateLocalIdentity(local, incoming: normalized);

      final _MergeResult merge = _mergeLocalAndRemote(
        local: local,
        remote: normalized,
        source: source,
      );

      if (!merge.shouldApply) {
        await _acknowledgeDeliveryIfRequired(
          message: local,
          session: session,
          generation: generation,
        );

        _rememberFingerprint(local);

        return MessageReceiveResult(
          disposition: merge.stale
              ? MessageReceiveDisposition.stale
              : MessageReceiveDisposition.duplicate,
          message: local,
        );
      }

      canonical = merge.message;
      disposition = MessageReceiveDisposition.merged;
    }

    _assertGeneration(generation);

    await _stateSink.upsertMessage(canonical);

    _assertGeneration(generation);

    _rememberFingerprint(canonical);

    await _acknowledgeDeliveryIfRequired(
      message: canonical,
      session: session,
      generation: generation,
    );

    return MessageReceiveResult(disposition: disposition, message: canonical);
  }

  /// Processes multiple durable entities in deterministic order.
  ///
  /// Input ordering is preserved. Timeline ordering itself remains the
  /// responsibility of MessageSyncEngine.
  Future<List<MessageReceiveResult>> receiveAll(
    Iterable<MessageEntity> messages, {
    MessageReceiveSource source = MessageReceiveSource.realtime,
  }) async {
    _requireActiveSession();

    final List<MessageReceiveResult> results = <MessageReceiveResult>[];

    for (final MessageEntity message in messages) {
      results.add(await receive(message, source: source));
    }

    return List<MessageReceiveResult>.unmodifiable(results);
  }

  Future<void> _acknowledgeDeliveryIfRequired({
    required MessageEntity message,
    required _ReceiverSession session,
    required int generation,
  }) async {
    // A user never acknowledges delivery of their own outgoing message.
    if (message.senderUid == session.authenticatedUid) {
      return;
    }

    // Once server receipt state is already delivered/read, no duplicate
    // acknowledgement is necessary.
    if (_statusRank(message.status) >= _statusRank(MessageStatus.delivered)) {
      _deliveryAcknowledged.add(message.id);
      _trimAcknowledgementMemory();
      return;
    }

    if (_deliveryAcknowledged.contains(message.id) ||
        _deliveryAcknowledgementInFlight.contains(message.id)) {
      return;
    }

    _deliveryAcknowledgementInFlight.add(message.id);

    try {
      await _deliverySink.acknowledgeDelivered(
        authenticatedUid: session.authenticatedUid,
        conversationId: session.conversationId,
        messageId: message.id,
      );

      _assertGeneration(generation);

      _deliveryAcknowledged.add(message.id);
      _trimAcknowledgementMemory();
    } finally {
      _deliveryAcknowledgementInFlight.remove(message.id);
    }
  }

  _MergeResult _mergeLocalAndRemote({
    required MessageEntity local,
    required MessageEntity remote,
    required MessageReceiveSource source,
  }) {
    if (_isExactDuplicate(local, remote)) {
      return _MergeResult.unchanged(message: local, stale: false);
    }

    final DateTime? localServerTime = local.serverCreatedAt?.toUtc();
    final DateTime? remoteServerTime = remote.serverCreatedAt?.toUtc();

    if (localServerTime != null &&
        remoteServerTime != null &&
        remoteServerTime.isBefore(localServerTime) &&
        source != MessageReceiveSource.reconciliation) {
      return _MergeResult.unchanged(message: local, stale: true);
    }

    final MessageStatus mergedStatus = _maxStatus(local.status, remote.status);

    final DateTime clientCreatedAt = _earliestDate(
      local.clientCreatedAt,
      remote.clientCreatedAt,
    );

    final DateTime? serverCreatedAt = _preferredServerTimestamp(
      local.serverCreatedAt,
      remote.serverCreatedAt,
    );

    final DateTime? editedAt = _latestNullableDate(
      local.editedAt,
      remote.editedAt,
    );

    final DateTime? deletedAt = _latestNullableDate(
      local.deletedAt,
      remote.deletedAt,
    );

    final bool remoteIsAuthoritative =
        remote.serverCreatedAt != null ||
        source == MessageReceiveSource.realtime ||
        source == MessageReceiveSource.initialSync ||
        source == MessageReceiveSource.pagination ||
        source == MessageReceiveSource.reconciliation;

    final MessageEntity base = remoteIsAuthoritative ? remote : local;

    final MessageEntity merged = base.copyWith(
      status: mergedStatus,
      clientCreatedAt: clientCreatedAt,
      serverCreatedAt: serverCreatedAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      localOnly: false,
      clearFailureCode:
          _statusRank(mergedStatus) >= _statusRank(MessageStatus.sent),
      clearFailureMessage:
          _statusRank(mergedStatus) >= _statusRank(MessageStatus.sent),
    );

    if (_isExactDuplicate(local, merged)) {
      return _MergeResult.unchanged(message: local, stale: false);
    }

    return _MergeResult.changed(merged);
  }

  static MessageStatus _maxStatus(MessageStatus first, MessageStatus second) {
    if (first == MessageStatus.failed) {
      return second == MessageStatus.queued || second == MessageStatus.sending
          ? first
          : second;
    }

    if (second == MessageStatus.failed) {
      return first;
    }

    return _statusRank(first) >= _statusRank(second) ? first : second;
  }

  static int _statusRank(MessageStatus status) {
    switch (status) {
      case MessageStatus.failed:
        return -1;
      case MessageStatus.queued:
        return 0;
      case MessageStatus.sending:
        return 1;
      case MessageStatus.sent:
        return 2;
      case MessageStatus.delivered:
        return 3;
      case MessageStatus.read:
        return 4;
    }
  }

  static DateTime _earliestDate(DateTime first, DateTime second) {
    final DateTime firstUtc = first.toUtc();
    final DateTime secondUtc = second.toUtc();

    return firstUtc.isBefore(secondUtc) ? firstUtc : secondUtc;
  }

  static DateTime? _preferredServerTimestamp(
    DateTime? local,
    DateTime? remote,
  ) {
    if (remote != null) {
      return remote.toUtc();
    }

    return local?.toUtc();
  }

  static DateTime? _latestNullableDate(DateTime? first, DateTime? second) {
    if (first == null) {
      return second?.toUtc();
    }

    if (second == null) {
      return first.toUtc();
    }

    final DateTime firstUtc = first.toUtc();
    final DateTime secondUtc = second.toUtc();

    return firstUtc.isAfter(secondUtc) ? firstUtc : secondUtc;
  }

  static bool _isExactDuplicate(MessageEntity first, MessageEntity second) {
    return _MessageFingerprint.fromMessage(first) ==
        _MessageFingerprint.fromMessage(second);
  }

  void _validateRawIdentity(
    MessageEntity incoming, {
    required _ReceiverSession session,
  }) {
    final String messageId = _normalizeRequiredIdentifier(
      incoming.id,
      fieldName: 'message.id',
    );

    if (messageId != incoming.id.trim()) {
      throw StateError(
        'Incoming canonical message ID contains invalid outer whitespace.',
      );
    }

    if (incoming.conversationId != session.conversationId) {
      throw StateError('Incoming message belongs to another conversation.');
    }

    _normalizeRequiredIdentifier(
      incoming.senderUid,
      fieldName: 'message.senderUid',
    );
  }

  static void _validateNormalizedIdentity({
    required MessageEntity original,
    required MessageEntity normalized,
    required _ReceiverSession session,
  }) {
    if (normalized.id != original.id) {
      throw StateError('Incoming validation changed the canonical message ID.');
    }

    if (normalized.conversationId != original.conversationId ||
        normalized.conversationId != session.conversationId) {
      throw StateError(
        'Incoming validation changed the canonical conversation ID.',
      );
    }

    if (normalized.senderUid != original.senderUid) {
      throw StateError(
        'Incoming validation changed the canonical sender Firebase UID.',
      );
    }

    if (normalized.type != original.type) {
      throw StateError(
        'Incoming validation changed the canonical durable message type.',
      );
    }
  }

  static void _validateLocalIdentity(
    MessageEntity local, {
    required MessageEntity incoming,
  }) {
    if (local.id != incoming.id) {
      throw StateError(
        'Local reconciliation returned an invalid canonical message ID.',
      );
    }

    if (local.conversationId != incoming.conversationId) {
      throw StateError('Canonical message ID conflicts across conversations.');
    }

    if (local.senderUid != incoming.senderUid) {
      throw StateError(
        'Canonical message ID conflicts across sender Firebase UIDs.',
      );
    }

    if (local.type != incoming.type) {
      throw StateError(
        'Canonical message ID conflicts across durable message types.',
      );
    }
  }

  void _rememberFingerprint(MessageEntity message) {
    _recentFingerprints.remove(message.id);
    _recentFingerprints[message.id] = _MessageFingerprint.fromMessage(message);

    while (_recentFingerprints.length > _rememberedMessageLimit) {
      _recentFingerprints.remove(_recentFingerprints.keys.first);
    }
  }

  void _trimAcknowledgementMemory() {
    if (_deliveryAcknowledged.length <= _rememberedMessageLimit) {
      return;
    }

    final Set<String> retained = _recentFingerprints.keys
        .where(_deliveryAcknowledged.contains)
        .toSet();

    _deliveryAcknowledged
      ..clear()
      ..addAll(retained);
  }

  _ReceiverSession _requireActiveSession() {
    _ensureNotDisposed();

    if (!_initialized) {
      throw StateError('MessageReceiver is not initialized.');
    }

    final String? uid = _authenticatedUid;
    final String? conversation = _conversationId;

    if (uid == null ||
        uid.isEmpty ||
        conversation == null ||
        conversation.isEmpty) {
      throw StateError(
        'MessageReceiver has no valid authenticated conversation session.',
      );
    }

    return _ReceiverSession(
      authenticatedUid: uid,
      conversationId: conversation,
      generation: _sessionGeneration,
    );
  }

  void _assertGeneration(int generation) {
    if (_disposed || !_initialized || generation != _sessionGeneration) {
      throw StateError('MessageReceiver operation belongs to a stale session.');
    }
  }

  /// Resets active per-conversation receiver state.
  Future<void> reset() async {
    _ensureNotDisposed();

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _recentFingerprints.clear();
    _deliveryAcknowledgementInFlight.clear();
    _deliveryAcknowledged.clear();
  }

  /// Permanently disposes this receiver.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _recentFingerprints.clear();
    _deliveryAcknowledgementInFlight.clear();
    _deliveryAcknowledged.clear();

    _disposed = true;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'MessageReceiver has already been disposed and cannot be reused.',
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
    if (value < 32 || value > 8192) {
      throw ArgumentError.value(
        value,
        'rememberedMessageLimit',
        'rememberedMessageLimit must be between 32 and 8192.',
      );
    }

    return value;
  }
}

final class _ReceiverSession {
  const _ReceiverSession({
    required this.authenticatedUid,
    required this.conversationId,
    required this.generation,
  });

  final String authenticatedUid;
  final String conversationId;
  final int generation;
}

final class _MergeResult {
  const _MergeResult._({
    required this.message,
    required this.shouldApply,
    required this.stale,
  });

  factory _MergeResult.changed(MessageEntity message) {
    return _MergeResult._(message: message, shouldApply: true, stale: false);
  }

  factory _MergeResult.unchanged({
    required MessageEntity message,
    required bool stale,
  }) {
    return _MergeResult._(message: message, shouldApply: false, stale: stale);
  }

  final MessageEntity message;
  final bool shouldApply;
  final bool stale;
}

/// Lightweight deterministic fingerprint used only for duplicate suppression.
///
/// It deliberately avoids storing message text/media bytes in the receiver's
/// dedupe memory.
final class _MessageFingerprint {
  const _MessageFingerprint({
    required this.id,
    required this.conversationId,
    required this.senderUid,
    required this.type,
    required this.status,
    required this.clientCreatedAtMicros,
    required this.serverCreatedAtMicros,
    required this.editedAtMicros,
    required this.deletedAtMicros,
    required this.localOnly,
  });

  factory _MessageFingerprint.fromMessage(MessageEntity message) {
    return _MessageFingerprint(
      id: message.id,
      conversationId: message.conversationId,
      senderUid: message.senderUid,
      type: message.type,
      status: message.status,
      clientCreatedAtMicros: message.clientCreatedAt
          .toUtc()
          .microsecondsSinceEpoch,
      serverCreatedAtMicros: message.serverCreatedAt
          ?.toUtc()
          .microsecondsSinceEpoch,
      editedAtMicros: message.editedAt?.toUtc().microsecondsSinceEpoch,
      deletedAtMicros: message.deletedAt?.toUtc().microsecondsSinceEpoch,
      localOnly: message.localOnly,
    );
  }

  final String id;
  final String conversationId;
  final String senderUid;
  final Object type;
  final MessageStatus status;
  final int clientCreatedAtMicros;
  final int? serverCreatedAtMicros;
  final int? editedAtMicros;
  final int? deletedAtMicros;
  final bool localOnly;

  @override
  bool operator ==(Object other) {
    return other is _MessageFingerprint &&
        other.id == id &&
        other.conversationId == conversationId &&
        other.senderUid == senderUid &&
        other.type == type &&
        other.status == status &&
        other.clientCreatedAtMicros == clientCreatedAtMicros &&
        other.serverCreatedAtMicros == serverCreatedAtMicros &&
        other.editedAtMicros == editedAtMicros &&
        other.deletedAtMicros == deletedAtMicros &&
        other.localOnly == localOnly;
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    senderUid,
    type,
    status,
    clientCreatedAtMicros,
    serverCreatedAtMicros,
    editedAtMicros,
    deletedAtMicros,
    localOnly,
  );
}

// ============================================================================
// END OF FILE: lib/features/message/engine/message_receiver.dart
// ============================================================================
