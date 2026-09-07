// ============================================================================
// JR CALL
// File: message_validation.dart
// Location: lib/features/message/security/message_validation.dart
// Description:
// Central validation contract for JR CALL Message Engine.
//
// Owns:
// - Text validation.
// - Message/conversation/user ID validation.
// - Reply-reference validation.
// - Reaction validation.
// - Attachment validation.
// - File-size/MIME validation.
// - Metadata validation.
// - Live Chat draft validation.
// - Edit-payload validation.
// - Safe normalized validation failures.
//
// Does NOT:
// - Authenticate users.
// - Authorize conversation membership.
// - Perform Firestore/Storage writes.
// - Replace Firebase Security Rules.
// - Implement encryption.
// - Render UI.
// - Implement Call Engine/WebRTC.
// ============================================================================

import '../data/attachment_entity.dart';
import '../data/message_entity.dart';
import '../data/message_type.dart';

/// Stable message-validation failure categories.
enum MessageValidationErrorCode {
  emptyValue,
  invalidIdentifier,
  invalidText,
  textTooLong,
  invalidReply,
  invalidReaction,
  invalidAttachment,
  invalidMimeType,
  unsupportedMimeType,
  invalidFileSize,
  fileTooLarge,
  invalidMetadata,
  invalidLiveDraft,
  invalidEdit,
  invalidMessage,
}

/// Immutable typed validation result.
final class MessageValidationResult {
  const MessageValidationResult._({
    required this.isValid,
    this.code,
    this.message,
    this.field,
  });

  const MessageValidationResult.valid() : this._(isValid: true);

  const MessageValidationResult.invalid({
    required MessageValidationErrorCode code,
    required String message,
    String? field,
  }) : this._(isValid: false, code: code, message: message, field: field);

  final bool isValid;
  final MessageValidationErrorCode? code;

  /// Safe description suitable for propagation to higher layers.
  final String? message;

  /// Optional logical field that failed validation.
  final String? field;

  bool get isInvalid => !isValid;

  void requireValid() {
    if (isValid) {
      return;
    }

    throw MessageValidationException(
      code: code ?? MessageValidationErrorCode.invalidMetadata,
      message: message ?? 'Message data is invalid.',
      field: field,
    );
  }
}

/// Safe typed validation exception.
final class MessageValidationException implements Exception {
  const MessageValidationException({
    required this.code,
    required this.message,
    this.field,
  });

  final MessageValidationErrorCode code;
  final String message;
  final String? field;

  @override
  String toString() {
    return 'MessageValidationException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

/// Canonical JR CALL Message Engine validation policy.
///
/// This class deliberately centralizes durable-message input limits so widgets,
/// controllers, repositories and storage layers do not create contradictory
/// validation rules.
///
/// Firebase Firestore/Storage Security Rules must independently enforce all
/// server-side authorization and upload restrictions.
final class MessageValidation {
  const MessageValidation();

  // --------------------------------------------------------------------------
  // CENTRAL LIMITS
  // --------------------------------------------------------------------------

  /// Maximum durable text message length.
  static const int maxTextLength = 10000;

  /// Maximum editable durable text length.
  static const int maxEditTextLength = maxTextLength;

  /// Maximum ephemeral Live Chat draft length.
  static const int maxLiveDraftLength = 4000;

  /// Maximum reaction Unicode/code-unit safety bound.
  static const int maxReactionLength = 32;

  /// Identifier length boundary for Firebase UID, conversation, message,
  /// attachment and session/version IDs.
  static const int maxIdentifierLength = 512;

  /// Maximum safe normalized original filename length.
  static const int maxFileNameLength = 255;

  /// General file/document upload ceiling.
  static const int maxFileBytes = 100 * 1024 * 1024;

  /// Image upload ceiling.
  static const int maxImageBytes = 25 * 1024 * 1024;

  /// Audio-file upload ceiling.
  static const int maxAudioBytes = 50 * 1024 * 1024;

  /// Recorded voice-message upload ceiling.
  static const int maxVoiceBytes = 50 * 1024 * 1024;

  /// Video upload ceiling.
  static const int maxVideoBytes = 250 * 1024 * 1024;

  static final RegExp _identifierPattern = RegExp(
    r'^[^\u0000-\u001F\u007F\s/]+$',
  );

  static final RegExp _mimePattern = RegExp(
    r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$',
    caseSensitive: false,
  );

  static final RegExp _controlCharacterPattern = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
  );

  static const Set<String> _blockedExecutableMimeTypes = <String>{
    'application/x-ms'
        'download',
    'application/x-ms'
        'dos-program',
    'application/x-executable',
    'application/x-sh',
    'application/x-shell'
        'script',
    'application/x-bat',
    'application/x-com',
    'application/vnd.microsoft.portable-executable',
  };

  static const Set<String> _blockedExecutableExtensions = <String>{
    'apk',
    'app',
    'bat',
    'bin',
    'cmd',
    'com',
    'cpl',
    'dll',
    'dmg',
    'exe',
    'ipa',
    'jar',
    'js',
    'jse',
    'msi',
    'msp',
    'ps1',
    'scr',
    'sh',
    'vbe',
    'vbs',
    'wsf',
  };

  // --------------------------------------------------------------------------
  // IDENTIFIERS
  // --------------------------------------------------------------------------

  MessageValidationResult validateMessageId(String value) {
    return _validateIdentifier(value, field: 'messageId');
  }

  MessageValidationResult validateConversationId(String value) {
    return _validateIdentifier(value, field: 'conversationId');
  }

  MessageValidationResult validateUserUid(String value) {
    return _validateIdentifier(value, field: 'userUid');
  }

  MessageValidationResult validateAttachmentId(String value) {
    return _validateIdentifier(value, field: 'attachmentId');
  }

  MessageValidationResult validateSessionId(String value) {
    return _validateIdentifier(value, field: 'sessionId');
  }

  String requireMessageId(String value) {
    validateMessageId(value).requireValid();
    return value.trim();
  }

  String requireConversationId(String value) {
    validateConversationId(value).requireValid();
    return value.trim();
  }

  String requireUserUid(String value) {
    validateUserUid(value).requireValid();
    return value.trim();
  }

  String requireAttachmentId(String value) {
    validateAttachmentId(value).requireValid();
    return value.trim();
  }

  String requireSessionId(String value) {
    validateSessionId(value).requireValid();
    return value.trim();
  }

  // --------------------------------------------------------------------------
  // TEXT
  // --------------------------------------------------------------------------

  MessageValidationResult validateText(
    String value, {
    bool allowEmpty = false,
    int maxLength = maxTextLength,
  }) {
    if (maxLength <= 0) {
      throw ArgumentError.value(
        maxLength,
        'maxLength',
        'maxLength must be greater than zero.',
      );
    }

    if (_controlCharacterPattern.hasMatch(value)) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidText,
        field: 'text',
        message: 'Message text contains unsupported control characters.',
      );
    }

    final String normalized = normalizeText(value);

    if (!allowEmpty && normalized.isEmpty) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.emptyValue,
        field: 'text',
        message: 'Message text must not be empty.',
      );
    }

    if (normalized.length > maxLength) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.textTooLong,
        field: 'text',
        message: 'Message text exceeds the allowed length.',
      );
    }

    return const MessageValidationResult.valid();
  }

  String requireText(
    String value, {
    bool allowEmpty = false,
    int maxLength = maxTextLength,
  }) {
    validateText(
      value,
      allowEmpty: allowEmpty,
      maxLength: maxLength,
    ).requireValid();

    return normalizeText(value);
  }

  /// Safe normalization used consistently by message creation/edit flows.
  String normalizeText(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  }

  // --------------------------------------------------------------------------
  // REPLY
  // --------------------------------------------------------------------------

  MessageValidationResult validateReplyReference({
    required String conversationId,
    required String replyToMessageId,
    String? replyToSenderUid,
  }) {
    final MessageValidationResult conversationResult = validateConversationId(
      conversationId,
    );

    if (conversationResult.isInvalid) {
      return conversationResult;
    }

    final MessageValidationResult messageResult = validateMessageId(
      replyToMessageId,
    );

    if (messageResult.isInvalid) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidReply,
        field: 'replyToMessageId',
        message: 'Reply message reference is invalid.',
      );
    }

    if (replyToSenderUid != null) {
      final MessageValidationResult senderResult = validateUserUid(
        replyToSenderUid,
      );

      if (senderResult.isInvalid) {
        return const MessageValidationResult.invalid(
          code: MessageValidationErrorCode.invalidReply,
          field: 'replyToSenderUid',
          message: 'Reply sender reference is invalid.',
        );
      }
    }

    return const MessageValidationResult.valid();
  }

  // --------------------------------------------------------------------------
  // REACTION
  // --------------------------------------------------------------------------

  MessageValidationResult validateReaction(String value) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidReaction,
        field: 'reaction',
        message: 'Reaction must not be empty.',
      );
    }

    if (_controlCharacterPattern.hasMatch(normalized) ||
        normalized.length > maxReactionLength) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidReaction,
        field: 'reaction',
        message: 'Reaction value is invalid.',
      );
    }

    if (RegExp(r'\s').hasMatch(normalized)) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidReaction,
        field: 'reaction',
        message: 'Reaction value is invalid.',
      );
    }

    return const MessageValidationResult.valid();
  }

  String requireReaction(String value) {
    validateReaction(value).requireValid();
    return value.trim();
  }

  // --------------------------------------------------------------------------
  // MIME TYPE
  // --------------------------------------------------------------------------

  MessageValidationResult validateMimeType(
    String value, {
    MessageType? messageType,
  }) {
    final String mimeType = normalizeMimeType(value);

    if (mimeType.isEmpty || !_mimePattern.hasMatch(mimeType)) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidMimeType,
        field: 'mimeType',
        message: 'Attachment MIME type is invalid.',
      );
    }

    if (_blockedExecutableMimeTypes.contains(mimeType)) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.unsupportedMimeType,
        field: 'mimeType',
        message: 'This attachment type is not supported.',
      );
    }

    if (messageType == null) {
      return const MessageValidationResult.valid();
    }

    switch (messageType) {
      case MessageType.image:
        if (!mimeType.startsWith('image/')) {
          return const MessageValidationResult.invalid(
            code: MessageValidationErrorCode.unsupportedMimeType,
            field: 'mimeType',
            message: 'Image messages require an image MIME type.',
          );
        }

      case MessageType.video:
        if (!mimeType.startsWith('video/')) {
          return const MessageValidationResult.invalid(
            code: MessageValidationErrorCode.unsupportedMimeType,
            field: 'mimeType',
            message: 'Video messages require a video MIME type.',
          );
        }

      case MessageType.audio:
      case MessageType.voice:
        if (!mimeType.startsWith('audio/')) {
          return const MessageValidationResult.invalid(
            code: MessageValidationErrorCode.unsupportedMimeType,
            field: 'mimeType',
            message: 'Audio messages require an audio MIME type.',
          );
        }

      case MessageType.file:
        break;

      case MessageType.text:
      case MessageType.system:
        return const MessageValidationResult.invalid(
          code: MessageValidationErrorCode.unsupportedMimeType,
          field: 'mimeType',
          message: 'This message type does not accept an attachment.',
        );
    }

    return const MessageValidationResult.valid();
  }

  String normalizeMimeType(String value) {
    return value.trim().toLowerCase();
  }

  // --------------------------------------------------------------------------
  // FILE NAME
  // --------------------------------------------------------------------------

  MessageValidationResult validateFileName(String value) {
    final String normalized = normalizeFileName(value);

    if (normalized.isEmpty) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidAttachment,
        field: 'fileName',
        message: 'Attachment filename must not be empty.',
      );
    }

    if (normalized.length > maxFileNameLength) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidAttachment,
        field: 'fileName',
        message: 'Attachment filename is too long.',
      );
    }

    if (_controlCharacterPattern.hasMatch(normalized) ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.contains('/') ||
        normalized.contains('\\')) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidAttachment,
        field: 'fileName',
        message: 'Attachment filename is invalid.',
      );
    }

    final int dotIndex = normalized.lastIndexOf('.');

    if (dotIndex >= 0 && dotIndex < normalized.length - 1) {
      final String extension = normalized.substring(dotIndex + 1).toLowerCase();

      if (_blockedExecutableExtensions.contains(extension)) {
        return const MessageValidationResult.invalid(
          code: MessageValidationErrorCode.invalidAttachment,
          field: 'fileName',
          message: 'Executable attachments are not supported.',
        );
      }
    }

    return const MessageValidationResult.valid();
  }

  String normalizeFileName(String value) {
    return value.trim();
  }

  // --------------------------------------------------------------------------
  // FILE SIZE
  // --------------------------------------------------------------------------

  MessageValidationResult validateFileSize({
    required int byteSize,
    required MessageType messageType,
  }) {
    if (byteSize <= 0) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidFileSize,
        field: 'byteSize',
        message: 'Attachment file size must be greater than zero.',
      );
    }

    final int maxBytes = maxBytesForType(messageType);

    if (byteSize > maxBytes) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.fileTooLarge,
        field: 'byteSize',
        message: 'Attachment exceeds the allowed file-size limit.',
      );
    }

    return const MessageValidationResult.valid();
  }

  int maxBytesForType(MessageType type) {
    switch (type) {
      case MessageType.image:
        return maxImageBytes;
      case MessageType.video:
        return maxVideoBytes;
      case MessageType.audio:
        return maxAudioBytes;
      case MessageType.voice:
        return maxVoiceBytes;
      case MessageType.file:
        return maxFileBytes;
      case MessageType.text:
      case MessageType.system:
        return 0;
    }
  }

  // --------------------------------------------------------------------------
  // ATTACHMENT
  // --------------------------------------------------------------------------

  MessageValidationResult validateAttachment(
    AttachmentEntity attachment, {
    MessageType? expectedMessageType,
  }) {
    final Map<String, Object?> map = attachment.toMap();

    final String? attachmentId = _readString(map, const <String>[
      'id',
      'attachmentId',
    ]);

    final String? messageId = _readString(map, const <String>['messageId']);

    final String? conversationId = _readString(map, const <String>[
      'conversationId',
    ]);

    final String? ownerUid = _readString(map, const <String>['ownerUid']);

    final String? fileName = _readString(map, const <String>[
      'fileName',
      'originalFileName',
    ]);

    final String? mimeType = _readString(map, const <String>['mimeType']);

    final int? byteSize = _readInt(map, const <String>['byteSize']);

    if (attachmentId == null || validateAttachmentId(attachmentId).isInvalid) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidAttachment,
        field: 'attachmentId',
        message: 'Attachment ID is invalid.',
      );
    }

    if (messageId == null || validateMessageId(messageId).isInvalid) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidAttachment,
        field: 'messageId',
        message: 'Attachment message ID is invalid.',
      );
    }

    if (conversationId == null ||
        validateConversationId(conversationId).isInvalid) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidAttachment,
        field: 'conversationId',
        message: 'Attachment conversation ID is invalid.',
      );
    }

    if (ownerUid == null || validateUserUid(ownerUid).isInvalid) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidAttachment,
        field: 'ownerUid',
        message: 'Attachment owner UID is invalid.',
      );
    }

    if (fileName == null || validateFileName(fileName).isInvalid) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidAttachment,
        field: 'fileName',
        message: 'Attachment filename is invalid.',
      );
    }

    if (mimeType == null) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidMimeType,
        field: 'mimeType',
        message: 'Attachment MIME type is required.',
      );
    }

    final MessageValidationResult mimeResult = validateMimeType(
      mimeType,
      messageType: expectedMessageType,
    );

    if (mimeResult.isInvalid) {
      return mimeResult;
    }

    if (byteSize == null) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidFileSize,
        field: 'byteSize',
        message: 'Attachment byte size is required.',
      );
    }

    if (expectedMessageType != null) {
      final MessageValidationResult sizeResult = validateFileSize(
        byteSize: byteSize,
        messageType: expectedMessageType,
      );

      if (sizeResult.isInvalid) {
        return sizeResult;
      }
    } else if (byteSize <= 0 || byteSize > maxVideoBytes) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidFileSize,
        field: 'byteSize',
        message: 'Attachment file size is invalid.',
      );
    }

    final Object? width = map['width'];
    final Object? height = map['height'];
    final Object? duration = map['duration'];

    if (!_isNullablePositiveNumber(width) ||
        !_isNullablePositiveNumber(height) ||
        !_isNullableNonNegativeDuration(duration)) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidMetadata,
        field: 'attachment',
        message: 'Attachment media metadata is invalid.',
      );
    }

    return const MessageValidationResult.valid();
  }

  // --------------------------------------------------------------------------
  // MESSAGE ENTITY
  // --------------------------------------------------------------------------

  MessageValidationResult validateMessage(MessageEntity message) {
    final MessageValidationResult idResult = validateMessageId(message.id);

    if (idResult.isInvalid) {
      return idResult;
    }

    final MessageValidationResult conversationResult = validateConversationId(
      message.conversationId,
    );

    if (conversationResult.isInvalid) {
      return conversationResult;
    }

    final MessageValidationResult senderResult = validateUserUid(
      message.senderUid,
    );

    if (senderResult.isInvalid) {
      return senderResult;
    }

    if (message.clientCreatedAt.year < 2000) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidMessage,
        field: 'clientCreatedAt',
        message: 'Message creation timestamp is invalid.',
      );
    }

    final DateTime? serverCreatedAt = message.serverCreatedAt;

    if (serverCreatedAt != null && serverCreatedAt.year < 2000) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidMessage,
        field: 'serverCreatedAt',
        message: 'Message server timestamp is invalid.',
      );
    }

    final DateTime? editedAt = message.editedAt;

    if (editedAt != null && editedAt.year < 2000) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidMessage,
        field: 'editedAt',
        message: 'Message edit timestamp is invalid.',
      );
    }

    final DateTime? deletedAt = message.deletedAt;

    if (deletedAt != null && deletedAt.year < 2000) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidMessage,
        field: 'deletedAt',
        message: 'Message deletion timestamp is invalid.',
      );
    }

    if (deletedAt != null) {
      return const MessageValidationResult.valid();
    }

    final String safeText = message.text ?? '';

    switch (message.type) {
      case MessageType.text:
        return validateText(safeText);

      case MessageType.image:
      case MessageType.video:
      case MessageType.audio:
      case MessageType.voice:
      case MessageType.file:
        final AttachmentEntity? attachment = message.attachment;

        if (attachment == null) {
          return const MessageValidationResult.invalid(
            code: MessageValidationErrorCode.invalidAttachment,
            field: 'attachment',
            message: 'Media messages require attachment metadata.',
          );
        }

        return validateAttachment(
          attachment,
          expectedMessageType: message.type,
        );

      case MessageType.system:
        return validateText(
          safeText,
          allowEmpty: false,
          maxLength: maxTextLength,
        );
    }
  }

  // --------------------------------------------------------------------------
  // EDIT PAYLOAD
  // --------------------------------------------------------------------------

  MessageValidationResult validateEditPayload({
    required MessageEntity message,
    required String newText,
  }) {
    if (message.deletedAt != null) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidEdit,
        field: 'message',
        message: 'Deleted messages cannot be edited.',
      );
    }

    if (message.type != MessageType.text) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidEdit,
        field: 'message.type',
        message: 'Only text messages can currently be edited.',
      );
    }

    final MessageValidationResult textResult = validateText(
      newText,
      maxLength: maxEditTextLength,
    );

    if (textResult.isInvalid) {
      return MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidEdit,
        field: 'text',
        message: textResult.message ?? 'Edited message text is invalid.',
      );
    }

    final String normalizedCurrent = normalizeText(message.text ?? '');

    final String normalizedNew = normalizeText(newText);

    if (normalizedCurrent == normalizedNew) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidEdit,
        field: 'text',
        message: 'Edited text must differ from the current message.',
      );
    }

    return const MessageValidationResult.valid();
  }

  String requireEditPayload({
    required MessageEntity message,
    required String newText,
  }) {
    validateEditPayload(message: message, newText: newText).requireValid();

    return normalizeText(newText);
  }

  // --------------------------------------------------------------------------
  // LIVE CHAT
  // --------------------------------------------------------------------------

  MessageValidationResult validateLiveDraft({
    required String conversationId,
    required String senderUid,
    required String sessionId,
    required int version,
    required String text,
    required int styleSeed,
    required DateTime updatedAt,
    required DateTime expiresAt,
    required bool active,
  }) {
    final MessageValidationResult conversationResult = validateConversationId(
      conversationId,
    );

    if (conversationResult.isInvalid) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidLiveDraft,
        field: 'conversationId',
        message: 'Live Chat conversation ID is invalid.',
      );
    }

    final MessageValidationResult senderResult = validateUserUid(senderUid);

    if (senderResult.isInvalid) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidLiveDraft,
        field: 'senderUid',
        message: 'Live Chat sender UID is invalid.',
      );
    }

    final MessageValidationResult sessionResult = validateSessionId(sessionId);

    if (sessionResult.isInvalid) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidLiveDraft,
        field: 'sessionId',
        message: 'Live Chat session ID is invalid.',
      );
    }

    if (version < 0) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidLiveDraft,
        field: 'version',
        message: 'Live Chat version must not be negative.',
      );
    }

    if (styleSeed < 0) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidLiveDraft,
        field: 'styleSeed',
        message: 'Live Chat style seed must not be negative.',
      );
    }

    if (updatedAt.year < 2000 || expiresAt.year < 2000) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidLiveDraft,
        field: 'updatedAt',
        message: 'Live Chat timestamps are invalid.',
      );
    }

    if (active) {
      if (!expiresAt.isAfter(updatedAt)) {
        return const MessageValidationResult.invalid(
          code: MessageValidationErrorCode.invalidLiveDraft,
          field: 'expiresAt',
          message: 'Active Live Chat state must have a future expiry.',
        );
      }

      final MessageValidationResult textResult = validateText(
        text,
        maxLength: maxLiveDraftLength,
      );

      if (textResult.isInvalid) {
        return MessageValidationResult.invalid(
          code: MessageValidationErrorCode.invalidLiveDraft,
          field: 'text',
          message: textResult.message ?? 'Live Chat text is invalid.',
        );
      }
    } else {
      final MessageValidationResult textResult = validateText(
        text,
        allowEmpty: true,
        maxLength: maxLiveDraftLength,
      );

      if (textResult.isInvalid) {
        return MessageValidationResult.invalid(
          code: MessageValidationErrorCode.invalidLiveDraft,
          field: 'text',
          message: textResult.message ?? 'Live Chat text is invalid.',
        );
      }
    }

    return const MessageValidationResult.valid();
  }

  // --------------------------------------------------------------------------
  // GENERAL METADATA
  // --------------------------------------------------------------------------

  MessageValidationResult validateMetadata(
    Map<String, Object?> metadata, {
    int maxDepth = 6,
    int maxEntries = 100,
    int maxStringLength = 4096,
  }) {
    if (maxDepth <= 0 || maxEntries <= 0 || maxStringLength <= 0) {
      throw ArgumentError(
        'Metadata validation limits must be greater than zero.',
      );
    }

    int entryCount = 0;

    bool validateValue(Object? value, int depth) {
      if (depth > maxDepth) {
        return false;
      }

      if (value == null || value is bool || value is num || value is DateTime) {
        return true;
      }

      if (value is String) {
        return value.length <= maxStringLength &&
            !_controlCharacterPattern.hasMatch(value);
      }

      if (value is Map) {
        for (final MapEntry<Object?, Object?> entry in value.entries) {
          entryCount++;

          if (entryCount > maxEntries ||
              entry.key is! String ||
              (entry.key as String).trim().isEmpty ||
              (entry.key as String).length > maxIdentifierLength ||
              !validateValue(entry.value, depth + 1)) {
            return false;
          }
        }

        return true;
      }

      if (value is Iterable) {
        for (final Object? item in value) {
          entryCount++;

          if (entryCount > maxEntries || !validateValue(item, depth + 1)) {
            return false;
          }
        }

        return true;
      }

      return false;
    }

    if (!validateValue(metadata, 0)) {
      return const MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidMetadata,
        field: 'metadata',
        message: 'Message metadata is invalid or exceeds safe limits.',
      );
    }

    return const MessageValidationResult.valid();
  }

  // --------------------------------------------------------------------------
  // PRIVATE HELPERS
  // --------------------------------------------------------------------------

  MessageValidationResult _validateIdentifier(
    String value, {
    required String field,
  }) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      return MessageValidationResult.invalid(
        code: MessageValidationErrorCode.emptyValue,
        field: field,
        message: '$field must not be empty.',
      );
    }

    if (normalized.length > maxIdentifierLength ||
        !_identifierPattern.hasMatch(normalized)) {
      return MessageValidationResult.invalid(
        code: MessageValidationErrorCode.invalidIdentifier,
        field: field,
        message: '$field is invalid.',
      );
    }

    return const MessageValidationResult.valid();
  }

  static String? _readString(Map<String, Object?> map, List<String> keys) {
    for (final String key in keys) {
      final Object? value = map[key];

      if (value is String) {
        final String normalized = value.trim();

        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }

    return null;
  }

  static int? _readInt(Map<String, Object?> map, List<String> keys) {
    for (final String key in keys) {
      final Object? value = map[key];

      if (value is int) {
        return value;
      }

      if (value is num && value.isFinite) {
        final int converted = value.toInt();

        if (converted.toDouble() == value.toDouble()) {
          return converted;
        }
      }
    }

    return null;
  }

  static bool _isNullablePositiveNumber(Object? value) {
    if (value == null) {
      return true;
    }

    if (value is num) {
      return value.isFinite && value > 0;
    }

    return false;
  }

  static bool _isNullableNonNegativeDuration(Object? value) {
    if (value == null) {
      return true;
    }

    if (value is Duration) {
      return !value.isNegative;
    }

    if (value is num) {
      return value.isFinite && value >= 0;
    }

    return false;
  }
}

// ============================================================================
// END OF FILE: lib/features/message/security/message_validation.dart
// ============================================================================
