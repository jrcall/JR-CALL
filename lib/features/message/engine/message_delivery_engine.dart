// ============================================================================
// JR CALL
// File: message_delivery_engine.dart
// Location: lib/features/message/engine/message_delivery_engine.dart
// Description:
// Production delivery-receipt lifecycle engine.
//
// Responsibilities:
// - Writes recipient-side delivery acknowledgements only from real evidence.
// - Enforces recipient ownership of delivery receipts.
// - Prevents self-message delivery acknowledgement misuse.
// - Deduplicates repeated delivery receipt writes.
// - Applies monotonic sent -> delivered -> read status progression.
// - Processes remote delivery/read receipt events safely.
// - Supports multi-device receipt merging.
// - Rejects stale session operations.
// - Maintains bounded receipt memory.
//
// Important:
// - NEVER marks delivered because a timer elapsed.
// - NEVER marks delivered merely because a sender-side listener fired.
// - Firebase UID is the canonical receipt owner identity.
// - Does NOT mark messages read from visibility assumptions.
// - Does NOT directly own Firestore collection references.
// - Does NOT render UI.
// - Does NOT contain Call Engine/WebRTC logic.
// ============================================================================

import 'dart:async';
import 'dart:collection';

import '../data/message_entity.dart';
import '../data/message_status.dart';

/// Canonical receipt stage understood by the delivery engine.
enum MessageReceiptStage { delivered, read }

/// Immutable remote/local delivery receipt representation.
///
/// [userUid] is always the canonical Firebase Auth UID of the participant
/// producing the receipt.
final class MessageDeliveryReceipt {
  const MessageDeliveryReceipt({
    required this.conversationId,
    required this.userUid,
    required this.messageId,
    required this.stage,
    required this.acknowledgedAt,
  });

  final String conversationId;
  final String userUid;
  final String messageId;
  final MessageReceiptStage stage;
  final DateTime acknowledgedAt;
}

/// Authorization/validation boundary required by [MessageDeliveryEngine].
abstract interface class MessageDeliveryValidator {
  /// Verifies that [authenticatedUid] may access [conversationId].
  FutureOr<void> validateDeliveryContext({
    required String authenticatedUid,
    required String conversationId,
  });

  /// Verifies that the authenticated participant may acknowledge delivery
  /// for [message].
  ///
  /// Implementations must reject sender-side self acknowledgement.
  FutureOr<void> validateDeliveryAcknowledgement({
    required String authenticatedUid,
    required String conversationId,
    required MessageEntity message,
  });

  /// Validates a receipt received from the repository/realtime layer.
  FutureOr<void> validateRemoteReceipt({
    required String authenticatedUid,
    required String conversationId,
    required MessageDeliveryReceipt receipt,
  });
}

/// Persistence abstraction for receipt writes.
///
/// FILE 15 / FILE 35 provide the concrete production adapter.
/// Implementations must make repeated identical acknowledgements idempotent.
abstract interface class MessageDeliveryPersistence {
  Future<MessageDeliveryReceipt> writeDeliveredReceipt({
    required String authenticatedUid,
    required String conversationId,
    required String messageId,
  });
}

/// Message lookup/state bridge used by [MessageDeliveryEngine].
abstract interface class MessageDeliveryStateStore {
  /// Returns the canonical currently known message.
  MessageEntity? findMessage(String messageId);

  /// Applies a canonical monotonic message state mutation.
  FutureOr<void> upsertMessage(MessageEntity message);
}

/// Production delivery lifecycle engine.
final class MessageDeliveryEngine {
  factory MessageDeliveryEngine({
    required MessageDeliveryValidator validator,
    required MessageDeliveryPersistence persistence,
    required MessageDeliveryStateStore stateStore,
    int rememberedReceiptLimit = 2048,
  }) {
    return MessageDeliveryEngine._(
      validator,
      persistence,
      stateStore,
      _validateRememberedReceiptLimit(rememberedReceiptLimit),
    );
  }

  MessageDeliveryEngine._(
    this._validator,
    this._persistence,
    this._stateStore,
    this._rememberedReceiptLimit,
  );

  final MessageDeliveryValidator _validator;
  final MessageDeliveryPersistence _persistence;
  final MessageDeliveryStateStore _stateStore;
  final int _rememberedReceiptLimit;

  final Map<String, Future<void>> _deliveryWrites = <String, Future<void>>{};

  final LinkedHashMap<String, MessageDeliveryReceipt> _receiptByMessageId =
      LinkedHashMap<String, MessageDeliveryReceipt>();

  String? _authenticatedUid;
  String? _conversationId;

  int _sessionGeneration = 0;

  bool _initialized = false;
  bool _disposed = false;

  /// True while configured for an authenticated conversation.
  bool get isInitialized => _initialized && !_disposed;

  /// True after permanent disposal.
  bool get isDisposed => _disposed;

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

    await _validator.validateDeliveryContext(
      authenticatedUid: uid,
      conversationId: conversation,
    );

    ++_sessionGeneration;

    _authenticatedUid = uid;
    _conversationId = conversation;
    _initialized = true;
  }

  /// Marks actual recipient-side message delivery.
  ///
  /// This API is intentionally high-level because FILE 01 uses it directly.
  /// Every supplied message must already exist locally and must have been sent
  /// by another Firebase UID.
  Future<void> markDelivered({
    required String authenticatedUid,
    required String conversationId,
    required Iterable<String> messageIds,
  }) async {
    final _DeliverySession session = _requireMatchingSession(
      authenticatedUid: authenticatedUid,
      conversationId: conversationId,
    );

    final List<String> ids = _normalizeMessageIds(messageIds);

    for (final String messageId in ids) {
      await _markOneDelivered(session: session, messageId: messageId);
    }
  }

  /// Convenience single-message acknowledgement used by receiver/repository
  /// adapters.
  Future<void> acknowledgeDelivered({
    required String authenticatedUid,
    required String conversationId,
    required String messageId,
  }) {
    return markDelivered(
      authenticatedUid: authenticatedUid,
      conversationId: conversationId,
      messageIds: <String>[messageId],
    );
  }

  Future<void> _markOneDelivered({
    required _DeliverySession session,
    required String messageId,
  }) {
    final MessageEntity? message = _stateStore.findMessage(messageId);

    if (message == null) {
      return Future<void>.error(
        StateError(
          'Cannot acknowledge delivery for unknown message $messageId.',
        ),
      );
    }

    _validateMessageIdentity(message, session: session);

    if (message.senderUid == session.authenticatedUid) {
      return Future<void>.error(
        StateError('A sender cannot acknowledge delivery of its own message.'),
      );
    }

    if (_statusRank(message.status) >= _statusRank(MessageStatus.delivered)) {
      return Future<void>.value();
    }

    final MessageDeliveryReceipt? remembered = _receiptByMessageId[messageId];

    if (remembered != null &&
        _receiptRank(remembered.stage) >=
            _receiptRank(MessageReceiptStage.delivered)) {
      return Future<void>.value();
    }

    final Future<void>? active = _deliveryWrites[messageId];

    if (active != null) {
      return active;
    }

    final Future<void> operation = _executeDeliveryWrite(
      session: session,
      message: message,
    );

    _deliveryWrites[messageId] = operation;

    operation.whenComplete(() {
      if (identical(_deliveryWrites[messageId], operation)) {
        _deliveryWrites.remove(messageId);
      }
    });

    return operation;
  }

  Future<void> _executeDeliveryWrite({
    required _DeliverySession session,
    required MessageEntity message,
  }) async {
    final int generation = session.generation;

    await _validator.validateDeliveryAcknowledgement(
      authenticatedUid: session.authenticatedUid,
      conversationId: session.conversationId,
      message: message,
    );

    _assertGeneration(generation);

    final MessageDeliveryReceipt receipt = await _persistence
        .writeDeliveredReceipt(
          authenticatedUid: session.authenticatedUid,
          conversationId: session.conversationId,
          messageId: message.id,
        );

    _assertGeneration(generation);

    _validateReceiptIdentity(
      receipt,
      session: session,
      expectedMessageId: message.id,
      expectedOwnerUid: session.authenticatedUid,
    );

    if (_receiptRank(receipt.stage) <
        _receiptRank(MessageReceiptStage.delivered)) {
      throw StateError(
        'Delivery persistence returned a receipt below delivered state.',
      );
    }

    _rememberReceipt(receipt);

    final MessageEntity? latest = _stateStore.findMessage(message.id);

    if (latest == null) {
      return;
    }

    _validateMessageIdentity(latest, session: session);

    final MessageStatus nextStatus = _maxMessageStatus(
      latest.status,
      receipt.stage == MessageReceiptStage.read
          ? MessageStatus.read
          : MessageStatus.delivered,
    );

    if (nextStatus == latest.status) {
      return;
    }

    await _stateStore.upsertMessage(
      latest.copyWith(
        status: nextStatus,
        localOnly: false,
        clearFailureCode: true,
        clearFailureMessage: true,
      ),
    );
  }

  /// Processes a real remote receipt event.
  ///
  /// This is used for sender-side status advancement after receipt listener
  /// confirmation. It never creates a receipt; it only consumes one.
  Future<void> processRemoteReceipt(MessageDeliveryReceipt receipt) async {
    final _DeliverySession session = _requireSession();
    final int generation = session.generation;

    await _validator.validateRemoteReceipt(
      authenticatedUid: session.authenticatedUid,
      conversationId: session.conversationId,
      receipt: receipt,
    );

    _assertGeneration(generation);

    _validateReceiptIdentity(
      receipt,
      session: session,
      expectedMessageId: receipt.messageId,
    );

    final MessageDeliveryReceipt? existingReceipt =
        _receiptByMessageId[receipt.messageId];

    if (existingReceipt != null &&
        !_isReceiptNewerOrHigher(
          existing: existingReceipt,
          incoming: receipt,
        )) {
      return;
    }

    _rememberReceipt(
      _mergeReceipts(existing: existingReceipt, incoming: receipt),
    );

    final MessageEntity? message = _stateStore.findMessage(receipt.messageId);

    if (message == null) {
      return;
    }

    _validateMessageIdentity(message, session: session);

    // Remote delivery/read receipt updates are only relevant to messages
    // sent by the currently authenticated user.
    if (message.senderUid != session.authenticatedUid) {
      return;
    }

    final MessageStatus receiptStatus =
        receipt.stage == MessageReceiptStage.read
        ? MessageStatus.read
        : MessageStatus.delivered;

    final MessageStatus nextStatus = _maxMessageStatus(
      message.status,
      receiptStatus,
    );

    if (nextStatus == message.status) {
      return;
    }

    await _stateStore.upsertMessage(
      message.copyWith(
        status: nextStatus,
        localOnly: false,
        clearFailureCode: true,
        clearFailureMessage: true,
      ),
    );
  }

  /// Processes multiple remote receipt events in input order.
  Future<void> processRemoteReceipts(
    Iterable<MessageDeliveryReceipt> receipts,
  ) async {
    for (final MessageDeliveryReceipt receipt in receipts) {
      await processRemoteReceipt(receipt);
    }
  }

  static MessageDeliveryReceipt _mergeReceipts({
    required MessageDeliveryReceipt? existing,
    required MessageDeliveryReceipt incoming,
  }) {
    if (existing == null) {
      return incoming;
    }

    final MessageReceiptStage stage =
        _receiptRank(incoming.stage) >= _receiptRank(existing.stage)
        ? incoming.stage
        : existing.stage;

    final DateTime acknowledgedAt =
        incoming.acknowledgedAt.toUtc().isAfter(existing.acknowledgedAt.toUtc())
        ? incoming.acknowledgedAt.toUtc()
        : existing.acknowledgedAt.toUtc();

    return MessageDeliveryReceipt(
      conversationId: incoming.conversationId,
      userUid: incoming.userUid,
      messageId: incoming.messageId,
      stage: stage,
      acknowledgedAt: acknowledgedAt,
    );
  }

  static bool _isReceiptNewerOrHigher({
    required MessageDeliveryReceipt existing,
    required MessageDeliveryReceipt incoming,
  }) {
    final int existingRank = _receiptRank(existing.stage);
    final int incomingRank = _receiptRank(incoming.stage);

    if (incomingRank > existingRank) {
      return true;
    }

    if (incomingRank < existingRank) {
      return false;
    }

    return incoming.acknowledgedAt.toUtc().isAfter(
      existing.acknowledgedAt.toUtc(),
    );
  }

  void _rememberReceipt(MessageDeliveryReceipt receipt) {
    final MessageDeliveryReceipt? existing =
        _receiptByMessageId[receipt.messageId];

    final MessageDeliveryReceipt merged = _mergeReceipts(
      existing: existing,
      incoming: receipt,
    );

    _receiptByMessageId.remove(receipt.messageId);
    _receiptByMessageId[receipt.messageId] = merged;

    while (_receiptByMessageId.length > _rememberedReceiptLimit) {
      _receiptByMessageId.remove(_receiptByMessageId.keys.first);
    }
  }

  static MessageStatus _maxMessageStatus(
    MessageStatus current,
    MessageStatus incoming,
  ) {
    if (current == MessageStatus.read) {
      return MessageStatus.read;
    }

    if (current == MessageStatus.delivered && incoming != MessageStatus.read) {
      return MessageStatus.delivered;
    }

    if (current == MessageStatus.failed ||
        current == MessageStatus.queued ||
        current == MessageStatus.sending) {
      if (incoming == MessageStatus.delivered ||
          incoming == MessageStatus.read) {
        return incoming;
      }

      return current;
    }

    return _statusRank(incoming) > _statusRank(current) ? incoming : current;
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

  static int _receiptRank(MessageReceiptStage stage) {
    switch (stage) {
      case MessageReceiptStage.delivered:
        return 0;
      case MessageReceiptStage.read:
        return 1;
    }
  }

  _DeliverySession _requireSession() {
    _ensureNotDisposed();

    if (!_initialized) {
      throw StateError('MessageDeliveryEngine is not initialized.');
    }

    final String? uid = _authenticatedUid;
    final String? conversation = _conversationId;

    if (uid == null ||
        uid.isEmpty ||
        conversation == null ||
        conversation.isEmpty) {
      throw StateError(
        'MessageDeliveryEngine has no valid authenticated conversation '
        'session.',
      );
    }

    return _DeliverySession(
      authenticatedUid: uid,
      conversationId: conversation,
      generation: _sessionGeneration,
    );
  }

  _DeliverySession _requireMatchingSession({
    required String authenticatedUid,
    required String conversationId,
  }) {
    final _DeliverySession session = _requireSession();

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
        'MessageDeliveryEngine authenticated UID does not match the '
        'active session.',
      );
    }

    if (conversation != session.conversationId) {
      throw StateError(
        'MessageDeliveryEngine conversation ID does not match the '
        'active session.',
      );
    }

    return session;
  }

  static void _validateMessageIdentity(
    MessageEntity message, {
    required _DeliverySession session,
  }) {
    _normalizeRequiredIdentifier(message.id, fieldName: 'message.id');

    _normalizeRequiredIdentifier(
      message.senderUid,
      fieldName: 'message.senderUid',
    );

    if (message.conversationId != session.conversationId) {
      throw StateError('Message belongs to a different conversation.');
    }
  }

  static void _validateReceiptIdentity(
    MessageDeliveryReceipt receipt, {
    required _DeliverySession session,
    required String expectedMessageId,
    String? expectedOwnerUid,
  }) {
    final String messageId = _normalizeRequiredIdentifier(
      receipt.messageId,
      fieldName: 'receipt.messageId',
    );

    final String receiptUid = _normalizeRequiredIdentifier(
      receipt.userUid,
      fieldName: 'receipt.userUid',
    );

    if (messageId != expectedMessageId) {
      throw StateError('Delivery receipt canonical message ID mismatch.');
    }

    if (receipt.conversationId != session.conversationId) {
      throw StateError('Delivery receipt belongs to another conversation.');
    }

    if (expectedOwnerUid != null && receiptUid != expectedOwnerUid) {
      throw StateError(
        'Delivery receipt owner does not match authenticated Firebase UID.',
      );
    }
  }

  void _assertGeneration(int generation) {
    if (!_isGenerationCurrent(generation)) {
      throw StateError(
        'MessageDeliveryEngine operation belongs to a stale session.',
      );
    }
  }

  bool _isGenerationCurrent(int generation) {
    return !_disposed && _initialized && generation == _sessionGeneration;
  }

  /// Resets active per-conversation receipt state.
  Future<void> reset() async {
    _ensureNotDisposed();

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _deliveryWrites.clear();
    _receiptByMessageId.clear();
  }

  /// Permanently disposes this engine.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _deliveryWrites.clear();
    _receiptByMessageId.clear();

    _disposed = true;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'MessageDeliveryEngine has already been disposed and cannot be '
        'reused.',
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

final class _DeliverySession {
  const _DeliverySession({
    required this.authenticatedUid,
    required this.conversationId,
    required this.generation,
  });

  final String authenticatedUid;
  final String conversationId;
  final int generation;
}

// ============================================================================
// END OF FILE:
// lib/features/message/engine/message_delivery_engine.dart
// ============================================================================
