// ============================================================================
// JR CALL
// File: receipt_listener.dart
// Location: lib/features/message/realtime/receipt_listener.dart
// Description:
// Realtime delivery/read receipt listener for JR CALL Message Engine.
//
// Owns:
// - One active receipt stream subscription.
// - Recipient delivery acknowledgement observation.
// - Recipient read acknowledgement observation.
// - Monotonic receipt reconciliation.
// - Duplicate receipt suppression.
// - Stale subscription protection.
// - Conversation / Firebase UID validation.
// - Immutable normalized receipt snapshots.
// - Safe listener cancellation / restart / pause / resume / disposal.
//
// Does NOT own:
// - Receipt writes.
// - Firestore collection paths.
// - Message status invention.
// - Message sending.
// - UI state.
// - Call Engine / WebRTC.
//
// Firestore path/query/write ownership remains in message_remote_store.dart.
// This listener consumes a typed receipt stream supplied by the
// storage/repository layer and feeds MessageDeliveryEngine / MessageReadEngine.
// ============================================================================

import 'dart:async';

/// Canonical receipt boundary type.
///
/// A receipt is only accepted when it was produced by the real backend/client
/// receipt contract. This listener never manufactures a delivered/read event.
enum MessageReceiptType { delivered, read }

/// Immutable individual receipt acknowledgement.
///
/// [messageId] is the canonical durable Firestore message document ID.
///
/// [userUid] is the canonical Firebase Auth UID that produced the receipt.
///
/// [acknowledgedAt] is the real acknowledgement time supplied by the receipt
/// source. This listener does not derive it from elapsed client time.
final class MessageReceiptAcknowledgement {
  MessageReceiptAcknowledgement({
    required String conversationId,
    required String messageId,
    required String userUid,
    required this.type,
    required DateTime acknowledgedAt,
  }) : conversationId = _normalizeRequired(conversationId, 'conversationId'),
       messageId = _normalizeRequired(messageId, 'messageId'),
       userUid = _normalizeRequired(userUid, 'userUid'),
       acknowledgedAt = acknowledgedAt.toUtc();

  final String conversationId;
  final String messageId;
  final String userUid;
  final MessageReceiptType type;
  final DateTime acknowledgedAt;

  bool get isDelivered => type == MessageReceiptType.delivered;

  bool get isRead => type == MessageReceiptType.read;

  MessageReceiptAcknowledgement copyWith({
    String? conversationId,
    String? messageId,
    String? userUid,
    MessageReceiptType? type,
    DateTime? acknowledgedAt,
  }) {
    return MessageReceiptAcknowledgement(
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
      userUid: userUid ?? this.userUid,
      type: type ?? this.type,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'conversationId': conversationId,
      'messageId': messageId,
      'userUid': userUid,
      'type': type.name,
      'acknowledgedAt': acknowledgedAt,
    };
  }

  static String _normalizeRequired(String value, String fieldName) {
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
}

/// Immutable normalized receipt state for one recipient in one conversation.
///
/// A receipt document/source may represent cumulative acknowledgement
/// boundaries. Both values are optional because the backend must explicitly
/// confirm them.
///
/// [delivered] and [read] refer to real recipient acknowledgements only.
final class MessageReceiptState {
  MessageReceiptState({
    required String conversationId,
    required String userUid,
    MessageReceiptAcknowledgement? delivered,
    MessageReceiptAcknowledgement? read,
    required DateTime updatedAt,
  }) : conversationId = _normalizeRequired(conversationId, 'conversationId'),
       userUid = _normalizeRequired(userUid, 'userUid'),
       delivered = _validateReceipt(
         receipt: delivered,
         expectedConversationId: conversationId.trim(),
         expectedUserUid: userUid.trim(),
         expectedType: MessageReceiptType.delivered,
         fieldName: 'delivered',
       ),
       read = _validateReceipt(
         receipt: read,
         expectedConversationId: conversationId.trim(),
         expectedUserUid: userUid.trim(),
         expectedType: MessageReceiptType.read,
         fieldName: 'read',
       ),
       updatedAt = updatedAt.toUtc();

  final String conversationId;

  /// Firebase UID that owns/produced this receipt state.
  final String userUid;

  /// Real delivery acknowledgement boundary, when confirmed.
  final MessageReceiptAcknowledgement? delivered;

  /// Real read acknowledgement boundary, when confirmed.
  final MessageReceiptAcknowledgement? read;

  /// Freshness marker for this receipt state.
  final DateTime updatedAt;

  String? get deliveredMessageId => delivered?.messageId;

  String? get readMessageId => read?.messageId;

  DateTime? get deliveredAt => delivered?.acknowledgedAt;

  DateTime? get readAt => read?.acknowledgedAt;

  bool get hasDelivered => delivered != null;

  bool get hasRead => read != null;

  MessageReceiptState copyWith({
    String? conversationId,
    String? userUid,
    MessageReceiptAcknowledgement? delivered,
    bool clearDelivered = false,
    MessageReceiptAcknowledgement? read,
    bool clearRead = false,
    DateTime? updatedAt,
  }) {
    return MessageReceiptState(
      conversationId: conversationId ?? this.conversationId,
      userUid: userUid ?? this.userUid,
      delivered: clearDelivered ? null : (delivered ?? this.delivered),
      read: clearRead ? null : (read ?? this.read),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'conversationId': conversationId,
      'userUid': userUid,
      'delivered': delivered?.toMap(),
      'read': read?.toMap(),
      'updatedAt': updatedAt,
    };
  }

  static MessageReceiptAcknowledgement? _validateReceipt({
    required MessageReceiptAcknowledgement? receipt,
    required String expectedConversationId,
    required String expectedUserUid,
    required MessageReceiptType expectedType,
    required String fieldName,
  }) {
    if (receipt == null) {
      return null;
    }

    if (receipt.conversationId != expectedConversationId) {
      throw ArgumentError.value(
        receipt.conversationId,
        fieldName,
        '$fieldName conversation does not match receipt state.',
      );
    }

    if (receipt.userUid != expectedUserUid) {
      throw ArgumentError.value(
        receipt.userUid,
        fieldName,
        '$fieldName Firebase UID does not match receipt state.',
      );
    }

    if (receipt.type != expectedType) {
      throw ArgumentError.value(
        receipt.type,
        fieldName,
        '$fieldName has the wrong receipt type.',
      );
    }

    return receipt;
  }

  static String _normalizeRequired(String value, String fieldName) {
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
}

/// Immutable listener snapshot.
///
/// Higher layers may use [generation] as additional stale-event protection.
final class ReceiptListenerSnapshot {
  ReceiptListenerSnapshot({
    required String conversationId,
    required String recipientUid,
    required this.receipt,
    required int generation,
  }) : conversationId = _normalizeRequired(conversationId, 'conversationId'),
       recipientUid = _normalizeRequired(recipientUid, 'recipientUid'),
       generation = _validateGeneration(generation);

  final String conversationId;

  /// Canonical Firebase UID whose acknowledgements are being observed.
  final String recipientUid;

  final MessageReceiptState? receipt;

  final int generation;

  bool get hasReceipt => receipt != null;

  MessageReceiptAcknowledgement? get delivered => receipt?.delivered;

  MessageReceiptAcknowledgement? get read => receipt?.read;

  String? get deliveredMessageId => delivered?.messageId;

  String? get readMessageId => read?.messageId;

  static String _normalizeRequired(String value, String fieldName) {
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

  static int _validateGeneration(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'generation',
        'Generation must not be negative.',
      );
    }

    return value;
  }
}

/// Realtime receipt listener.
///
/// The stream supplied to [startListening] must represent the real receipt
/// state for exactly one recipient UID inside exactly one conversation.
///
/// Receipt ownership/path creation remains outside this class.
///
/// Guarantees:
/// - one active subscription,
/// - Firebase UID identity,
/// - no delivery/read invention,
/// - stale callback rejection,
/// - monotonic acknowledgement merge,
/// - duplicate suppression,
/// - immutable output,
/// - safe disposal.
final class ReceiptListener {
  ReceiptListener();

  final StreamController<ReceiptListenerSnapshot> _snapshotController =
      StreamController<ReceiptListenerSnapshot>.broadcast(sync: true);

  final StreamController<MessageReceiptAcknowledgement> _deliveryController =
      StreamController<MessageReceiptAcknowledgement>.broadcast(sync: true);

  final StreamController<MessageReceiptAcknowledgement> _readController =
      StreamController<MessageReceiptAcknowledgement>.broadcast(sync: true);

  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast(sync: true);

  StreamSubscription<MessageReceiptState?>? _subscription;

  String? _conversationId;
  String? _recipientUid;

  MessageReceiptState? _receipt;

  int _generation = 0;

  bool _isListening = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  // --------------------------------------------------------------------------
  // PUBLIC STATE
  // --------------------------------------------------------------------------

  String? get conversationId => _conversationId;

  String? get recipientUid => _recipientUid;

  MessageReceiptState? get receipt => _receipt;

  MessageReceiptAcknowledgement? get delivered => _receipt?.delivered;

  MessageReceiptAcknowledgement? get read => _receipt?.read;

  String? get deliveredMessageId => delivered?.messageId;

  String? get readMessageId => read?.messageId;

  int get generation => _generation;

  bool get isListening => _isListening;

  bool get isPaused => _isPaused;

  bool get isDisposed => _isDisposed;

  Stream<ReceiptListenerSnapshot> get snapshots => _snapshotController.stream;

  /// Emits only confirmed recipient delivery acknowledgements.
  Stream<MessageReceiptAcknowledgement> get deliveries =>
      _deliveryController.stream;

  /// Emits only confirmed recipient read acknowledgements.
  Stream<MessageReceiptAcknowledgement> get reads => _readController.stream;

  Stream<Object> get errors => _errorController.stream;

  // --------------------------------------------------------------------------
  // LISTENER LIFECYCLE
  // --------------------------------------------------------------------------

  Future<void> startListening({
    required String conversationId,
    required String recipientUid,
    required Stream<MessageReceiptState?> stream,
  }) async {
    _ensureNotDisposed();

    final String normalizedConversationId = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String normalizedRecipientUid = _normalizeId(
      recipientUid,
      fieldName: 'recipientUid',
    );

    // Critical stale callback protection:
    // invalidate old generation before cancellation/replacement.
    final int listenerGeneration = ++_generation;

    final StreamSubscription<MessageReceiptState?>? previous = _subscription;

    _subscription = null;
    _isListening = false;
    _isPaused = false;

    if (previous != null) {
      await previous.cancel();
    }

    _conversationId = normalizedConversationId;
    _recipientUid = normalizedRecipientUid;
    _receipt = null;

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    late final StreamSubscription<MessageReceiptState?> subscription;

    subscription = stream.listen(
      (MessageReceiptState? incoming) {
        _handleReceipt(
          incoming,
          expectedConversationId: normalizedConversationId,
          expectedRecipientUid: normalizedRecipientUid,
          listenerGeneration: listenerGeneration,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _handleError(
          error,
          stackTrace: stackTrace,
          listenerGeneration: listenerGeneration,
        );
      },
      onDone: () {
        _handleDone(subscription, listenerGeneration: listenerGeneration);
      },
      cancelOnError: false,
    );

    if (!_isCurrentGeneration(listenerGeneration)) {
      await subscription.cancel();
      return;
    }

    _subscription = subscription;
    _isListening = true;
  }

  Future<void> restartListening({
    required String conversationId,
    required String recipientUid,
    required Stream<MessageReceiptState?> stream,
  }) {
    return startListening(
      conversationId: conversationId,
      recipientUid: recipientUid,
      stream: stream,
    );
  }

  Future<void> stopListening() async {
    if (_isDisposed) {
      return;
    }

    ++_generation;

    final StreamSubscription<MessageReceiptState?>? subscription =
        _subscription;

    _subscription = null;
    _isListening = false;
    _isPaused = false;

    _conversationId = null;
    _recipientUid = null;
    _receipt = null;

    if (subscription != null) {
      await subscription.cancel();
    }
  }

  void pauseListening() {
    _ensureNotDisposed();

    final StreamSubscription<MessageReceiptState?>? subscription =
        _subscription;

    if (subscription == null || !_isListening || _isPaused) {
      return;
    }

    subscription.pause();
    _isPaused = true;
  }

  void resumeListening() {
    _ensureNotDisposed();

    final StreamSubscription<MessageReceiptState?>? subscription =
        _subscription;

    if (subscription == null || !_isListening || !_isPaused) {
      return;
    }

    subscription.resume();
    _isPaused = false;
  }

  /// Clears only locally accepted receipt state.
  ///
  /// This does not delete or modify any backend receipt.
  void clearSnapshot() {
    _ensureNotDisposed();

    if (_receipt == null) {
      return;
    }

    _receipt = null;
    _emitSnapshot(_generation);
  }

  // --------------------------------------------------------------------------
  // RECEIPT PROCESSING
  // --------------------------------------------------------------------------

  void _handleReceipt(
    MessageReceiptState? incoming, {
    required String expectedConversationId,
    required String expectedRecipientUid,
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    if (incoming == null) {
      // A null source value must never move a confirmed receipt backwards.
      //
      // Receipt deletion/absence may be caused by transient snapshot state,
      // cache transitions, permissions, or remote cleanup. Previously
      // confirmed delivered/read acknowledgement therefore remains accepted
      // for the lifetime of this listener generation.
      return;
    }

    final String incomingConversationId = _normalizeId(
      incoming.conversationId,
      fieldName: 'receipt.conversationId',
    );

    final String incomingUserUid = _normalizeId(
      incoming.userUid,
      fieldName: 'receipt.userUid',
    );

    if (incomingConversationId != expectedConversationId) {
      _emitSafeError(
        ReceiptListenerException(
          code: ReceiptListenerErrorCode.invalidConversation,
          message: 'Receipt update belongs to a different conversation.',
          conversationId: expectedConversationId,
          expectedUserUid: expectedRecipientUid,
          receivedUserUid: incomingUserUid,
        ),
        listenerGeneration: listenerGeneration,
      );
      return;
    }

    if (incomingUserUid != expectedRecipientUid) {
      _emitSafeError(
        ReceiptListenerException(
          code: ReceiptListenerErrorCode.invalidUser,
          message: 'Receipt update belongs to a different Firebase user.',
          conversationId: expectedConversationId,
          expectedUserUid: expectedRecipientUid,
          receivedUserUid: incomingUserUid,
        ),
        listenerGeneration: listenerGeneration,
      );
      return;
    }

    final MessageReceiptState normalized = _normalizeState(incoming);

    final MessageReceiptState? previous = _receipt;

    final MessageReceiptState merged = previous == null
        ? normalized
        : _mergeMonotonically(previous, normalized);

    if (_receiptEquivalent(previous, merged)) {
      return;
    }

    final MessageReceiptAcknowledgement? previousDelivered =
        previous?.delivered;

    final MessageReceiptAcknowledgement? previousRead = previous?.read;

    _receipt = merged;

    _emitSnapshot(listenerGeneration);

    final MessageReceiptAcknowledgement? nextDelivered = merged.delivered;

    if (nextDelivered != null &&
        !_ackEquivalent(previousDelivered, nextDelivered)) {
      if (_isCurrentGeneration(listenerGeneration)) {
        _deliveryController.add(nextDelivered);
      }
    }

    final MessageReceiptAcknowledgement? nextRead = merged.read;

    if (nextRead != null && !_ackEquivalent(previousRead, nextRead)) {
      if (_isCurrentGeneration(listenerGeneration)) {
        _readController.add(nextRead);
      }
    }
  }

  static MessageReceiptState _normalizeState(MessageReceiptState state) {
    final MessageReceiptAcknowledgement? delivered = state.delivered == null
        ? null
        : MessageReceiptAcknowledgement(
            conversationId: state.delivered!.conversationId,
            messageId: state.delivered!.messageId,
            userUid: state.delivered!.userUid,
            type: MessageReceiptType.delivered,
            acknowledgedAt: state.delivered!.acknowledgedAt,
          );

    final MessageReceiptAcknowledgement? read = state.read == null
        ? null
        : MessageReceiptAcknowledgement(
            conversationId: state.read!.conversationId,
            messageId: state.read!.messageId,
            userUid: state.read!.userUid,
            type: MessageReceiptType.read,
            acknowledgedAt: state.read!.acknowledgedAt,
          );

    return MessageReceiptState(
      conversationId: state.conversationId,
      userUid: state.userUid,
      delivered: delivered,
      read: read,
      updatedAt: state.updatedAt,
    );
  }

  /// Monotonic merge contract.
  ///
  /// Confirmed acknowledgement is never removed or moved to an older
  /// acknowledgement time.
  ///
  /// A newer acknowledgement timestamp replaces an older boundary.
  ///
  /// Equal timestamps are resolved deterministically by canonical message ID
  /// so multi-device duplicate snapshots cannot cause oscillation.
  static MessageReceiptState _mergeMonotonically(
    MessageReceiptState previous,
    MessageReceiptState incoming,
  ) {
    final MessageReceiptAcknowledgement? delivered = _mergeAcknowledgement(
      previous.delivered,
      incoming.delivered,
    );

    final MessageReceiptAcknowledgement? read = _mergeAcknowledgement(
      previous.read,
      incoming.read,
    );

    final DateTime updatedAt = incoming.updatedAt.isAfter(previous.updatedAt)
        ? incoming.updatedAt
        : previous.updatedAt;

    return MessageReceiptState(
      conversationId: previous.conversationId,
      userUid: previous.userUid,
      delivered: delivered,
      read: read,
      updatedAt: updatedAt,
    );
  }

  static MessageReceiptAcknowledgement? _mergeAcknowledgement(
    MessageReceiptAcknowledgement? previous,
    MessageReceiptAcknowledgement? incoming,
  ) {
    if (previous == null) {
      return incoming;
    }

    if (incoming == null) {
      return previous;
    }

    if (incoming.acknowledgedAt.isAfter(previous.acknowledgedAt)) {
      return incoming;
    }

    if (incoming.acknowledgedAt.isBefore(previous.acknowledgedAt)) {
      return previous;
    }

    if (incoming.messageId == previous.messageId) {
      return previous;
    }

    // Deterministic tie resolution only.
    //
    // Message chronology itself is owned by MessageEntity/server ordering,
    // therefore this does NOT claim that lexicographically larger ID means
    // "later message". It only prevents equal-time multi-device receipt
    // oscillation.
    return incoming.messageId.compareTo(previous.messageId) > 0
        ? incoming
        : previous;
  }

  // --------------------------------------------------------------------------
  // STREAM ERROR / COMPLETION
  // --------------------------------------------------------------------------

  void _handleError(
    Object error, {
    required StackTrace stackTrace,
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    _emitSafeError(
      ReceiptListenerException(
        code: ReceiptListenerErrorCode.stream,
        message: 'The realtime receipt stream reported an error.',
        conversationId: _conversationId,
        expectedUserUid: _recipientUid,
        cause: error,
        stackTrace: stackTrace,
      ),
      listenerGeneration: listenerGeneration,
    );
  }

  void _handleDone(
    StreamSubscription<MessageReceiptState?> subscription, {
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    if (!identical(_subscription, subscription)) {
      return;
    }

    _subscription = null;
    _isListening = false;
    _isPaused = false;
  }

  void _emitSafeError(Object error, {required int listenerGeneration}) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    _errorController.add(error);
  }

  // --------------------------------------------------------------------------
  // EMISSION
  // --------------------------------------------------------------------------

  void _emitSnapshot(int listenerGeneration) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final String? activeConversationId = _conversationId;
    final String? activeRecipientUid = _recipientUid;

    if (activeConversationId == null || activeRecipientUid == null) {
      return;
    }

    _snapshotController.add(
      ReceiptListenerSnapshot(
        conversationId: activeConversationId,
        recipientUid: activeRecipientUid,
        receipt: _receipt,
        generation: listenerGeneration,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // DUPLICATE SUPPRESSION
  // --------------------------------------------------------------------------

  static bool _receiptEquivalent(
    MessageReceiptState? first,
    MessageReceiptState? second,
  ) {
    if (identical(first, second)) {
      return true;
    }

    if (first == null || second == null) {
      return false;
    }

    return first.conversationId == second.conversationId &&
        first.userUid == second.userUid &&
        first.updatedAt == second.updatedAt &&
        _ackEquivalent(first.delivered, second.delivered) &&
        _ackEquivalent(first.read, second.read);
  }

  static bool _ackEquivalent(
    MessageReceiptAcknowledgement? first,
    MessageReceiptAcknowledgement? second,
  ) {
    if (identical(first, second)) {
      return true;
    }

    if (first == null || second == null) {
      return false;
    }

    return first.conversationId == second.conversationId &&
        first.messageId == second.messageId &&
        first.userUid == second.userUid &&
        first.type == second.type &&
        first.acknowledgedAt == second.acknowledgedAt;
  }

  // --------------------------------------------------------------------------
  // INTERNAL VALIDATION
  // --------------------------------------------------------------------------

  bool _isCurrentGeneration(int listenerGeneration) {
    return !_isDisposed && listenerGeneration == _generation;
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('ReceiptListener has already been disposed.');
    }
  }

  static String _normalizeId(String value, {required String fieldName}) {
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

  // --------------------------------------------------------------------------
  // DISPOSAL
  // --------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    // Invalidate stale callbacks before cancelling.
    ++_generation;

    _isDisposed = true;
    _isListening = false;
    _isPaused = false;

    final StreamSubscription<MessageReceiptState?>? subscription =
        _subscription;

    _subscription = null;

    _conversationId = null;
    _recipientUid = null;
    _receipt = null;

    if (subscription != null) {
      await subscription.cancel();
    }

    await _snapshotController.close();
    await _deliveryController.close();
    await _readController.close();
    await _errorController.close();
  }
}

/// Stable receipt-listener error categories.
enum ReceiptListenerErrorCode { invalidConversation, invalidUser, stream }

/// Safe normalized realtime-receipt exception.
///
/// Raw backend errors remain available through [cause] for internal
/// diagnostics only. UI layers must not blindly expose them.
final class ReceiptListenerException implements Exception {
  const ReceiptListenerException({
    required this.code,
    required this.message,
    this.conversationId,
    this.expectedUserUid,
    this.receivedUserUid,
    this.cause,
    this.stackTrace,
  });

  final ReceiptListenerErrorCode code;

  /// Safe higher-layer description.
  final String message;

  final String? conversationId;
  final String? expectedUserUid;
  final String? receivedUserUid;

  /// Internal diagnostic source error.
  final Object? cause;

  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'ReceiptListenerException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/realtime/receipt_listener.dart
// ============================================================================
