// ============================================================================
// JR CALL
// File: message_status.dart
// Location: lib/features/message/data/message_status.dart
// Description:
// Single canonical durable-message lifecycle status definition.
//
// Lifecycle:
// queued -> sending -> sent -> delivered -> read
//
// Failure:
// queued/sending -> failed
//
// Retry:
// failed -> queued -> sending
//
// Important:
// - sent means durable backend/database acceptance.
// - delivered requires real recipient delivery acknowledgement.
// - read requires real recipient read acknowledgement.
// - Status must never move backward from delivered/read.
// - No timer may invent delivered/read state.
// - This is the only canonical Message Engine status definition.
// ============================================================================

/// Canonical JR CALL durable-message lifecycle status.
enum MessageStatus {
  queued,
  sending,
  sent,
  delivered,
  read,
  failed;

  /// Canonical persisted representation.
  String get serialized => name;

  /// Monotonic lifecycle rank.
  ///
  /// [failed] is intentionally outside the successful lifecycle and therefore
  /// has rank -1.
  int get rank {
    switch (this) {
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

  /// True while the message still represents local/pending send work.
  bool get isLocal {
    switch (this) {
      case MessageStatus.queued:
      case MessageStatus.sending:
      case MessageStatus.failed:
        return true;

      case MessageStatus.sent:
      case MessageStatus.delivered:
      case MessageStatus.read:
        return false;
    }
  }

  /// True once durable backend acceptance has been confirmed.
  bool get isCommitted {
    switch (this) {
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

  /// True when no automatic forward send transition should continue from
  /// this state.
  ///
  /// [failed] requires an explicit retry decision.
  /// [read] is the final successful receipt state.
  bool get isTerminal =>
      this == MessageStatus.failed || this == MessageStatus.read;

  bool get isFailed => this == MessageStatus.failed;

  bool get isQueued => this == MessageStatus.queued;

  bool get isSending => this == MessageStatus.sending;

  bool get isSent => this == MessageStatus.sent;

  bool get isDelivered => this == MessageStatus.delivered;

  bool get isRead => this == MessageStatus.read;

  /// True if the status represents at least durable send acceptance.
  bool get isAtLeastSent =>
      this == MessageStatus.sent ||
      this == MessageStatus.delivered ||
      this == MessageStatus.read;

  /// True if real delivery acknowledgement has been confirmed.
  bool get isAtLeastDelivered =>
      this == MessageStatus.delivered || this == MessageStatus.read;

  /// Deserializes canonical status data.
  ///
  /// Accepted input:
  /// - [MessageStatus]
  /// - canonical string values
  ///
  /// Invalid or missing persisted state is rejected rather than silently
  /// inventing a lifecycle state.
  static MessageStatus fromValue(Object? value) {
    if (value is MessageStatus) {
      return value;
    }

    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'queued':
          return MessageStatus.queued;
        case 'sending':
          return MessageStatus.sending;
        case 'sent':
          return MessageStatus.sent;
        case 'delivered':
          return MessageStatus.delivered;
        case 'read':
          return MessageStatus.read;
        case 'failed':
          return MessageStatus.failed;
      }
    }

    throw FormatException('Unsupported MessageStatus value: $value');
  }

  /// Alias for serialization-oriented callers.
  static MessageStatus deserialize(Object? value) {
    return fromValue(value);
  }

  /// Returns whether an explicit lifecycle transition is valid.
  ///
  /// Valid normal flow:
  /// queued -> sending -> sent -> delivered -> read
  ///
  /// Failure:
  /// queued/sending -> failed
  ///
  /// Retry:
  /// failed -> queued
  ///
  /// Identical states are allowed for idempotent reconciliation.
  bool canTransitionTo(MessageStatus next) {
    if (next == this) {
      return true;
    }

    switch (this) {
      case MessageStatus.queued:
        return next == MessageStatus.sending || next == MessageStatus.failed;

      case MessageStatus.sending:
        return next == MessageStatus.sent || next == MessageStatus.failed;

      case MessageStatus.sent:
        return next == MessageStatus.delivered || next == MessageStatus.read;

      case MessageStatus.delivered:
        return next == MessageStatus.read;

      case MessageStatus.read:
        return false;

      case MessageStatus.failed:
        return next == MessageStatus.queued;
    }
  }

  /// Returns the stronger successful status without permitting regression.
  ///
  /// Failed/local retry state is not automatically converted here.
  /// Retry transitions must remain explicit through [canTransitionTo].
  MessageStatus mergeMonotonic(MessageStatus incoming) {
    if (incoming == this) {
      return this;
    }

    if (this == MessageStatus.failed) {
      return this;
    }

    if (incoming == MessageStatus.failed) {
      return this;
    }

    return incoming.rank > rank ? incoming : this;
  }

  /// Compares lifecycle strength.
  ///
  /// Positive:
  /// this is ahead of [other].
  ///
  /// Zero:
  /// same lifecycle rank.
  ///
  /// Negative:
  /// this is behind [other].
  int compareRank(MessageStatus other) {
    return rank.compareTo(other.rank);
  }

  @override
  String toString() => serialized;
}

// ============================================================================
// END OF FILE: lib/features/message/data/message_status.dart
// ============================================================================
