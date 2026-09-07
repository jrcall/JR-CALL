// ============================================================================
// JR CALL
// File: message_type.dart
// Location: lib/features/message/data/message_type.dart
// Description:
// Single canonical durable-message type definition for JR CALL Message Engine.
//
// Durable types:
// - text
// - image
// - video
// - audio
// - voice
// - file
// - system
//
// Important:
// - Live Chat draft is NOT a durable MessageType.
// - This file contains no Firestore, Storage, UI or Call Engine logic.
// - All durable message type serialization must use this definition.
// ============================================================================

/// Canonical JR CALL durable message type.
enum MessageType {
  text,
  image,
  video,
  audio,
  voice,
  file,
  system;

  /// Canonical persisted representation.
  String get serialized => name;

  /// True for durable attachment-based messages.
  bool get isMedia {
    switch (this) {
      case MessageType.image:
      case MessageType.video:
      case MessageType.audio:
      case MessageType.voice:
      case MessageType.file:
        return true;

      case MessageType.text:
      case MessageType.system:
        return false;
    }
  }

  /// True when this message type normally carries textual content.
  bool get isText {
    switch (this) {
      case MessageType.text:
      case MessageType.system:
        return true;

      case MessageType.image:
      case MessageType.video:
      case MessageType.audio:
      case MessageType.voice:
      case MessageType.file:
        return false;
    }
  }

  /// True for visual media.
  bool get isVisualMedia =>
      this == MessageType.image || this == MessageType.video;

  /// True for audio-based durable messages.
  bool get isAudioMedia =>
      this == MessageType.audio || this == MessageType.voice;

  /// True for general document/file messages.
  bool get isFile => this == MessageType.file;

  /// True for recorded voice messages.
  bool get isVoice => this == MessageType.voice;

  /// True for application/system-generated timeline messages.
  bool get isSystem => this == MessageType.system;

  /// Human-readable fallback preview label.
  ///
  /// This contains no sender-specific or fake message data. Presentation may
  /// replace/localize these labels later while preserving canonical type.
  String get previewLabel {
    switch (this) {
      case MessageType.text:
        return 'Message';
      case MessageType.image:
        return 'Photo';
      case MessageType.video:
        return 'Video';
      case MessageType.audio:
        return 'Audio';
      case MessageType.voice:
        return 'Voice message';
      case MessageType.file:
        return 'File';
      case MessageType.system:
        return 'System message';
    }
  }

  /// Deserializes canonical durable message type data.
  ///
  /// Accepted:
  /// - MessageType instance
  /// - canonical String representation
  ///
  /// Missing/unknown values are rejected instead of silently selecting a
  /// different durable message type.
  static MessageType fromValue(Object? value) {
    if (value is MessageType) {
      return value;
    }

    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'text':
          return MessageType.text;
        case 'image':
          return MessageType.image;
        case 'video':
          return MessageType.video;
        case 'audio':
          return MessageType.audio;
        case 'voice':
          return MessageType.voice;
        case 'file':
        case 'document':
          return MessageType.file;
        case 'system':
          return MessageType.system;
      }
    }

    throw FormatException('Unsupported MessageType value: $value');
  }

  /// Serialization-oriented alias.
  static MessageType deserialize(Object? value) {
    return fromValue(value);
  }

  /// Returns the canonical serialized representation.
  static String serialize(MessageType value) {
    return value.serialized;
  }

  @override
  String toString() => serialized;
}

// ============================================================================
// END OF FILE: lib/features/message/data/message_type.dart
// ============================================================================
