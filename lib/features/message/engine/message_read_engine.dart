// ============================================================================
// JR CALL
// File: message_read_engine.dart
// Location: lib/features/message/engine/message_read_engine.dart
// Description:
// Production read-receipt lifecycle engine.
//
// Responsibilities:
// - Marks only genuinely visible/read recipient messages.
// - Prevents self-message read acknowledgement misuse.
// - Coalesces/batches read acknowledgement writes.
// - Maintains monotonic delivered -> read progression.
// - Maintains a monotonic per-user read boundary.
// - Updates local message state only after accepted receipt state.
// - Processes remote read receipts for sender-side status updates.
// - Coordinates conversation unread/read-boundary state.
// - Deduplicates repeated read writes and receipt events.
// - Rejects stale lifecycle/session callbacks.
// - Maintains bounded receipt/message memory.
//
// Important:
// - NEVER marks a message read merely because a listener received it.
// - Firebase UID is the canonical receipt owner.
// - Does NOT directly own Firestore collection references.
// - Does NOT render UI.
// - Does NOT contain Call Engine/WebRTC logic.
// ============================================================================

import 'dart:async';
import 'dart:collection';

import '../data/message_entity.dart';
import '../data/message_status.dart';

/// Canonical read receipt produced by one Firebase-authenticated participant.
final class MessageReadReceipt {
  const MessageReadReceipt({
    required this.conversationId,
    required this.userUid,
    required this.messageId,
    required this.readAt,
  });

  final String conversationId;
  final String userUid;
  final String messageId;
  final DateTime readAt;
}

/// Result returned after a read batch is durably accepted.
///
/// [receipts] contains accepted canonical receipt records.
/// [readBoundaryMessageId] may represent the participant's newest read
/// boundary after the durable write.
final class MessageReadWriteResult {
  const MessageReadWriteResult({
    required this.receipts,
    this.readBoundaryMessageId,
    this.readBoundaryAt,
  });

  final List<MessageReadReceipt> receipts;
  final String? readBoundaryMessageId;
  final DateTime? readBoundaryAt;
}

/// Validation/security boundary required by [MessageReadEngine].
abstract interface class MessageReadValidator {
  /// Validates authenticated conversation access.
  FutureOr<void> validateReadContext({
    required String authenticatedUid,
    required String conversationId,
  });

  /// Validates that the authenticated user may mark [message] as read.
  ///
  /// Implementations must reject sender-owned self messages.
  FutureOr<void> validateReadAcknowledgement({
    required String authenticatedUid,
    required String conversationId,
    required MessageEntity message,
  });

  /// Validates a read receipt received through realtime/repository layers.
  FutureOr<void> validateRemoteReadReceipt({
    required String authenticatedUid,
    required String conversationId,
    required MessageReadReceipt receipt,
  });
}

/// Durable read-receipt persistence abstraction.
///
/// FILE 15 / FILE 35 provide the concrete production implementation.
abstract interface class MessageReadPersistence {
  /// Writes a coalesced set of actual recipient read acknowledgements.
  ///
  /// Implementations must make repeated message IDs idempotent and must not
  /// reduce an existing read boundary.
  Future<MessageReadWriteResult> writeReadReceipts({
    required String authenticatedUid,
    required String conversationId,
    required List<String> messageIds,
  });

  /// Updates conversation-level unread/read-boundary information after
  /// accepted read receipt persistence.
  Future<void> updateConversationReadBoundary({
    required String authenticatedUid,
    required String conversationId,
    required String readBoundaryMessageId,
    required DateTime readAt,
  });
}

/// Local message state bridge used by [MessageReadEngine].
abstract interface class MessageReadStateStore {
  /// Returns the canonical loaded message for [messageId], when available.
  MessageEntity? findMessage(String messageId);

  /// Applies a canonical monotonic message mutation.
  FutureOr<void> upsertMessage(MessageEntity message);
}

/// Production read-receipt lifecycle engine.
final class MessageReadEngine {
  factory MessageReadEngine({
    required MessageReadValidator validator,
    required MessageReadPersistence persistence,
    required MessageReadStateStore stateStore,
    int rememberedReceiptLimit = 2048,
  }) {
    return MessageReadEngine._(
      validator,
      persistence,
      stateStore,
      _validateRememberedReceiptLimit(rememberedReceiptLimit),
    );
  }

  MessageReadEngine._(
    this._validator,
    this._persistence,
    this._stateStore,
    this._rememberedReceiptLimit,
  );

  final MessageReadValidator _validator;
  final MessageReadPersistence _persistence;
  final MessageReadStateStore _stateStore;
  final int _rememberedReceiptLimit;

  final LinkedHashMap<String, MessageReadReceipt> _receiptByMessageId =
      LinkedHashMap<String, MessageReadReceipt>();

  final Set<String> _readWriteInFlight = <String>{};

  String? _authenticatedUid;
  String? _conversationId;

  String? _readBoundaryMessageId;
  DateTime? _readBoundaryAt;

  int _sessionGeneration = 0;

  bool _initialized = false;
  bool _disposed = false;
  bool _batchWriteInProgress = false;

  /// True while configured for an authenticated conversation.
  bool get isInitialized => _initialized && !_disposed;

  /// True after permanent disposal.
  bool get isDisposed => _disposed;

  /// Latest accepted local read-boundary message ID, when known.
  String? get readBoundaryMessageId => _readBoundaryMessageId;

  /// Latest accepted read-boundary timestamp, when known.
  DateTime? get readBoundaryAt => _readBoundaryAt;

  /// Initializes this engine for one authenticated conversation.
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

    await _validator.validateReadContext(
      authenticatedUid: uid,
      conversationId: conversation,
    );

    ++_sessionGeneration;

    _authenticatedUid = uid;
    _conversationId = conversation;
    _initialized = true;
  }

  /// Marks actually visible/read recipient messages as read.
  ///
  /// FILE 01 calls this API after presentation/controller-level visibility
  /// confirmation. Listener arrival alone must never call this method.
  Future<void> markRead({
    required String authenticatedUid,
    required String conversationId,
    required Iterable<String> messageIds,
  }) async {
    final _ReadSession session = _requireMatchingSession(
      authenticatedUid: authenticatedUid,
      conversationId: conversationId,
    );

    final List<String> normalizedIds = _normalizeMessageIds(messageIds);

    if (normalizedIds.isEmpty) {
      return;
    }

    final List<MessageEntity> eligible = <MessageEntity>[];

    for (final String messageId in normalizedIds) {
      final MessageEntity? message = _stateStore.findMessage(messageId);

      if (message == null) {
        continue;
      }

      _validateMessageIdentity(message, session: session);

      // The authenticated participant never produces a read receipt for
      // their own outgoing message.
      if (message.senderUid == session.authenticatedUid) {
        continue;
      }

      if (message.status == MessageStatus.read) {
        continue;
      }

      if (_receiptByMessageId.containsKey(message.id)) {
        continue;
      }

      if (_readWriteInFlight.contains(message.id)) {
        continue;
      }

      await _validator.validateReadAcknowledgement(
        authenticatedUid: session.authenticatedUid,
        conversationId: session.conversationId,
        message: message,
      );

      _assertGeneration(session.generation);

      eligible.add(message);
    }

    if (eligible.isEmpty) {
      return;
    }

    await _writeReadBatch(session: session, messages: eligible);
  }

  Future<void> _writeReadBatch({
    required _ReadSession session,
    required List<MessageEntity> messages,
  }) async {
    final int generation = session.generation;

    if (_batchWriteInProgress) {
      // Exact message IDs remain deduplicated by _readWriteInFlight and may be
      // safely retried by a subsequent visibility/controller event.
      return;
    }

    _batchWriteInProgress = true;

    final List<String> ids = messages
        .map((MessageEntity message) => message.id)
        .toList();

    _readWriteInFlight.addAll(ids);

    try {
      final MessageReadWriteResult result = await _persistence
          .writeReadReceipts(
            authenticatedUid: session.authenticatedUid,
            conversationId: session.conversationId,
            messageIds: List<String>.unmodifiable(ids),
          );

      _assertGeneration(generation);

      final Map<String, MessageReadReceipt> accepted =
          <String, MessageReadReceipt>{};

      for (final MessageReadReceipt receipt in result.receipts) {
        _validateReceiptIdentity(
          receipt,
          session: session,
          expectedOwnerUid: session.authenticatedUid,
        );

        if (!ids.contains(receipt.messageId)) {
          throw StateError(
            'Read persistence returned an unexpected canonical message ID.',
          );
        }

        accepted[receipt.messageId] = receipt;
      }

      if (accepted.length != ids.length) {
        throw StateError(
          'Read persistence did not acknowledge every requested message.',
        );
      }

      for (final String messageId in ids) {
        final MessageReadReceipt receipt = accepted[messageId]!;

        _rememberReceipt(receipt);

        final MessageEntity? latest = _stateStore.findMessage(messageId);

        if (latest == null) {
          continue;
        }

        _validateMessageIdentity(latest, session: session);

        if (latest.senderUid == session.authenticatedUid) {
          continue;
        }

        if (latest.status != MessageStatus.read) {
          await _stateStore.upsertMessage(
            latest.copyWith(
              status: MessageStatus.read,
              localOnly: false,
              clearFailureCode: true,
              clearFailureMessage: true,
            ),
          );
        }
      }

      _assertGeneration(generation);

      final _ReadBoundary? boundary = _resolveBoundary(
        result: result,
        acceptedReceipts: accepted.values,
      );

      if (boundary != null &&
          _shouldAdvanceBoundary(
            messageId: boundary.messageId,
            readAt: boundary.readAt,
          )) {
        await _persistence.updateConversationReadBoundary(
          authenticatedUid: session.authenticatedUid,
          conversationId: session.conversationId,
          readBoundaryMessageId: boundary.messageId,
          readAt: boundary.readAt,
        );

        _assertGeneration(generation);

        _readBoundaryMessageId = boundary.messageId;
        _readBoundaryAt = boundary.readAt.toUtc();
      }
    } finally {
      _readWriteInFlight.removeAll(ids);

      if (_isGenerationCurrent(generation)) {
        _batchWriteInProgress = false;
      }
    }
  }

  /// Processes a confirmed remote read receipt.
  ///
  /// This normally advances an outgoing message owned by the authenticated
  /// sender to read after ReceiptListener confirms recipient acknowledgement.
  Future<void> processRemoteReadReceipt(MessageReadReceipt receipt) async {
    final _ReadSession session = _requireSession();
    final int generation = session.generation;

    await _validator.validateRemoteReadReceipt(
      authenticatedUid: session.authenticatedUid,
      conversationId: session.conversationId,
      receipt: receipt,
    );

    _assertGeneration(generation);

    _validateReceiptIdentity(receipt, session: session);

    final MessageReadReceipt? existing = _receiptByMessageId[receipt.messageId];

    if (existing != null &&
        !receipt.readAt.toUtc().isAfter(existing.readAt.toUtc())) {
      return;
    }

    _rememberReceipt(receipt);

    final MessageEntity? message = _stateStore.findMessage(receipt.messageId);

    if (message == null) {
      return;
    }

    _validateMessageIdentity(message, session: session);

    // Remote participant receipts advance only messages sent by the current
    // authenticated user.
    if (message.senderUid != session.authenticatedUid) {
      return;
    }

    if (message.status == MessageStatus.read) {
      return;
    }

    // A confirmed remote read receipt is stronger than delivered/sent state.
    await _stateStore.upsertMessage(
      message.copyWith(
        status: MessageStatus.read,
        localOnly: false,
        clearFailureCode: true,
        clearFailureMessage: true,
      ),
    );
  }

  /// Processes multiple remote read receipts in input order.
  Future<void> processRemoteReadReceipts(
    Iterable<MessageReadReceipt> receipts,
  ) async {
    for (final MessageReadReceipt receipt in receipts) {
      await processRemoteReadReceipt(receipt);
    }
  }

  _ReadBoundary? _resolveBoundary({
    required MessageReadWriteResult result,
    required Iterable<MessageReadReceipt> acceptedReceipts,
  }) {
    final String? explicitId = _normalizeOptionalIdentifier(
      result.readBoundaryMessageId,
    );

    final DateTime? explicitAt = result.readBoundaryAt?.toUtc();

    if (explicitId != null && explicitAt != null) {
      return _ReadBoundary(messageId: explicitId, readAt: explicitAt);
    }

    MessageReadReceipt? latest;

    for (final MessageReadReceipt receipt in acceptedReceipts) {
      if (latest == null ||
          receipt.readAt.toUtc().isAfter(latest.readAt.toUtc())) {
        latest = receipt;
      }
    }

    if (latest == null) {
      return null;
    }

    return _ReadBoundary(
      messageId: latest.messageId,
      readAt: latest.readAt.toUtc(),
    );
  }

  bool _shouldAdvanceBoundary({
    required String messageId,
    required DateTime readAt,
  }) {
    final DateTime incoming = readAt.toUtc();
    final DateTime? current = _readBoundaryAt;

    if (current == null) {
      return true;
    }

    final DateTime currentUtc = current.toUtc();

    if (incoming.isAfter(currentUtc)) {
      return true;
    }

    if (incoming.isBefore(currentUtc)) {
      return false;
    }

    if (_readBoundaryMessageId == null) {
      return true;
    }

    // Deterministic tie-break only when timestamps are equal.
    return messageId.compareTo(_readBoundaryMessageId!) > 0;
  }

  void _rememberReceipt(MessageReadReceipt receipt) {
    final MessageReadReceipt? existing = _receiptByMessageId[receipt.messageId];

    if (existing != null &&
        !receipt.readAt.toUtc().isAfter(existing.readAt.toUtc())) {
      return;
    }

    _receiptByMessageId.remove(receipt.messageId);
    _receiptByMessageId[receipt.messageId] = MessageReadReceipt(
      conversationId: receipt.conversationId,
      userUid: receipt.userUid,
      messageId: receipt.messageId,
      readAt: receipt.readAt.toUtc(),
    );

    while (_receiptByMessageId.length > _rememberedReceiptLimit) {
      _receiptByMessageId.remove(_receiptByMessageId.keys.first);
    }
  }

  _ReadSession _requireSession() {
    _ensureNotDisposed();

    if (!_initialized) {
      throw StateError('MessageReadEngine is not initialized.');
    }

    final String? uid = _authenticatedUid;
    final String? conversation = _conversationId;

    if (uid == null ||
        uid.isEmpty ||
        conversation == null ||
        conversation.isEmpty) {
      throw StateError(
        'MessageReadEngine has no valid authenticated conversation session.',
      );
    }

    return _ReadSession(
      authenticatedUid: uid,
      conversationId: conversation,
      generation: _sessionGeneration,
    );
  }

  _ReadSession _requireMatchingSession({
    required String authenticatedUid,
    required String conversationId,
  }) {
    final _ReadSession session = _requireSession();

    final String uid = _normalizeRequiredIdentifier(
      authenticatedUid,
      fieldName: 'authenticatedUid',
    );

    final String conversation = _normalizeRequiredIdentifier(
      conversationId,
      fieldName: 'conversationId',
    );

    if (uid != session.authenticatedUid) {
      throw StateError(
        'MessageReadEngine authenticated UID does not match the active '
        'session.',
      );
    }

    if (conversation != session.conversationId) {
      throw StateError(
        'MessageReadEngine conversation ID does not match the active session.',
      );
    }

    return session;
  }

  static void _validateMessageIdentity(
    MessageEntity message, {
    required _ReadSession session,
  }) {
    _normalizeRequiredIdentifier(message.id, fieldName: 'message.id');

    _normalizeRequiredIdentifier(
      message.senderUid,
      fieldName: 'message.senderUid',
    );

    if (message.conversationId != session.conversationId) {
      throw StateError('Read target message belongs to another conversation.');
    }
  }

  static void _validateReceiptIdentity(
    MessageReadReceipt receipt, {
    required _ReadSession session,
    String? expectedOwnerUid,
  }) {
    _normalizeRequiredIdentifier(
      receipt.messageId,
      fieldName: 'receipt.messageId',
    );

    final String receiptUid = _normalizeRequiredIdentifier(
      receipt.userUid,
      fieldName: 'receipt.userUid',
    );

    if (receipt.conversationId != session.conversationId) {
      throw StateError('Read receipt belongs to another conversation.');
    }

    if (expectedOwnerUid != null && receiptUid != expectedOwnerUid) {
      throw StateError(
        'Read receipt owner does not match authenticated Firebase UID.',
      );
    }
  }

  void _assertGeneration(int generation) {
    if (!_isGenerationCurrent(generation)) {
      throw StateError(
        'MessageReadEngine operation belongs to a stale session.',
      );
    }
  }

  bool _isGenerationCurrent(int generation) {
    return !_disposed && _initialized && generation == _sessionGeneration;
  }

  /// Resets active per-conversation read state.
  Future<void> reset() async {
    _ensureNotDisposed();

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _readBoundaryMessageId = null;
    _readBoundaryAt = null;

    _batchWriteInProgress = false;

    _receiptByMessageId.clear();
    _readWriteInFlight.clear();
  }

  /// Permanently disposes this read engine.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _readBoundaryMessageId = null;
    _readBoundaryAt = null;

    _batchWriteInProgress = false;

    _receiptByMessageId.clear();
    _readWriteInFlight.clear();

    _disposed = true;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'MessageReadEngine has already been disposed and cannot be reused.',
      );
    }
  }

  static List<String> _normalizeMessageIds(Iterable<String> values) {
    final LinkedHashSet<String> ids = LinkedHashSet<String>();

    for (final String value in values) {
      final String normalized = value.trim();

      if (normalized.isNotEmpty) {
        ids.add(normalized);
      }
    }

    return List<String>.unmodifiable(ids);
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

  static String? _normalizeOptionalIdentifier(String? value) {
    if (value == null) {
      return null;
    }

    final String normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  static int _validateRememberedReceiptLimit(int value) {
    if (value < 64 || value > 8192) {
      throw ArgumentError.value(
        value,
        'rememberedReceiptLimit',
        'rememberedReceiptLimit must be between 64 and 8192.',
      );
    }

    return value;
  }
}

final class _ReadSession {
  const _ReadSession({
    required this.authenticatedUid,
    required this.conversationId,
    required this.generation,
  });

  final String authenticatedUid;
  final String conversationId;
  final int generation;
}

final class _ReadBoundary {
  const _ReadBoundary({required this.messageId, required this.readAt});

  final String messageId;
  final DateTime readAt;
}

// ============================================================================
// END OF FILE: lib/features/message/engine/message_read_engine.dart
// ============================================================================
