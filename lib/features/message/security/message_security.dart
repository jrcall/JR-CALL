// ============================================================================
// JR CALL
// File: message_security.dart
// Location: lib/features/message/security/message_security.dart
// Description:
// Client-side security boundary for JR CALL Message Engine.
//
// Owns:
// - Authenticated Firebase UID verification.
// - Sender ownership verification.
// - Conversation participant-membership checks.
// - Canonical identifier normalization.
// - Safe message-text normalization.
// - Sensitive-field / secret rejection.
// - Diagnostic log redaction.
// - Safe error exposure.
// - Security-oriented domain invariants.
//
// Does NOT:
// - Replace Firebase Firestore/Storage Security Rules.
// - Create Firebase credentials.
// - Perform authentication.
// - Implement cryptography.
// - Claim end-to-end encryption.
// - Perform Firestore/Storage writes.
// - Own UI authorization policy.
// - Own Call Engine / WebRTC.
//
// Firebase UID remains the canonical INTERNAL identity.
// Public JR CALL IDs, usernames, email addresses, phone numbers and display
// names must never replace Firebase UID for message ownership.
// ============================================================================

import '../data/conversation_entity.dart';
import '../data/message_entity.dart';

/// Stable security-boundary error categories.
enum MessageSecurityErrorCode {
  unauthenticated,
  invalidUid,
  invalidIdentifier,
  senderMismatch,
  notParticipant,
  invalidConversation,
  sensitiveContent,
  invalidText,
  malformedData,
  forbidden,
  unknown,
}

/// Immutable security-check result.
///
/// Security helpers return this where callers need a non-throwing decision.
/// [requireAllowed] can convert a denied result into a typed exception.
final class MessageSecurityResult {
  const MessageSecurityResult._({
    required this.allowed,
    this.code,
    this.message,
  });

  const MessageSecurityResult.allowed() : this._(allowed: true);

  const MessageSecurityResult.denied({
    required MessageSecurityErrorCode code,
    required String message,
  }) : this._(allowed: false, code: code, message: message);

  final bool allowed;
  final MessageSecurityErrorCode? code;

  /// Safe higher-layer description.
  ///
  /// Raw Firebase/backend exception text is intentionally not stored here.
  final String? message;

  bool get denied => !allowed;

  void requireAllowed() {
    if (allowed) {
      return;
    }

    throw MessageSecurityException(
      code: code ?? MessageSecurityErrorCode.forbidden,
      message: message ?? 'The requested messaging action is not allowed.',
    );
  }
}

/// Safe normalized security exception.
///
/// [cause] and [stackTrace] exist only for trusted internal diagnostics.
/// Presentation code must not blindly expose them to users.
final class MessageSecurityException implements Exception {
  const MessageSecurityException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final MessageSecurityErrorCode code;
  final String message;

  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'MessageSecurityException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

/// JR CALL Message Engine client security boundary.
///
/// This class intentionally contains no Firebase Security Rules substitute.
/// All client checks are defense-in-depth only. Server-side Firestore and
/// Storage Rules remain the final authorization authority.
final class MessageSecurity {
  const MessageSecurity();

  static const int _maxNormalizedTextLength = 20000;

  static const String _redacted = '[REDACTED]';

  /// Field-name tokens that must never be accepted as message-domain payload
  /// keys when they represent secrets or credentials.
  static const Set<String> _sensitiveFieldTokens = <String>{
    'password',
    'passwd',
    'passcode',
    'otp',
    'onetimepassword',
    'verificationcode',
    'credential',
    'credentials',
    'firebasecredential',
    'accesstoken',
    'refreshtoken',
    'authtoken',
    'idtoken',
    'bearertoken',
    'authorization',
    'authorizationtoken',
    'secret',
    'secretkey',
    'privatekey',
    'apikey',
  };

  // --------------------------------------------------------------------------
  // AUTHENTICATED UID
  // --------------------------------------------------------------------------

  /// Normalizes and validates the authenticated Firebase UID.
  ///
  /// The caller must provide the UID obtained from the existing authentication
  /// owner/session. This helper intentionally does not create or own Firebase
  /// authentication state.
  String requireAuthenticatedUid(String? authenticatedUid) {
    final String uid = authenticatedUid?.trim() ?? '';

    if (uid.isEmpty) {
      throw const MessageSecurityException(
        code: MessageSecurityErrorCode.unauthenticated,
        message: 'Authentication is required to use messaging.',
      );
    }

    _requireSafeIdentifier(
      uid,
      fieldName: 'authenticatedUid',
      errorCode: MessageSecurityErrorCode.invalidUid,
    );

    return uid;
  }

  /// Non-throwing authenticated UID validation.
  MessageSecurityResult validateAuthenticatedUid(String? authenticatedUid) {
    try {
      requireAuthenticatedUid(authenticatedUid);
      return const MessageSecurityResult.allowed();
    } on MessageSecurityException catch (error) {
      return MessageSecurityResult.denied(
        code: error.code,
        message: error.message,
      );
    }
  }

  /// Confirms [claimedUid] is exactly the authenticated Firebase UID.
  ///
  /// This is used for sender/receipt/reaction/typing/live ownership boundaries.
  MessageSecurityResult verifyCurrentUid({
    required String? authenticatedUid,
    required String claimedUid,
  }) {
    String currentUid;

    try {
      currentUid = requireAuthenticatedUid(authenticatedUid);
    } on MessageSecurityException catch (error) {
      return MessageSecurityResult.denied(
        code: error.code,
        message: error.message,
      );
    }

    final String normalizedClaimedUid = claimedUid.trim();

    if (normalizedClaimedUid.isEmpty) {
      return const MessageSecurityResult.denied(
        code: MessageSecurityErrorCode.invalidUid,
        message: 'User identity is invalid.',
      );
    }

    if (currentUid != normalizedClaimedUid) {
      return const MessageSecurityResult.denied(
        code: MessageSecurityErrorCode.senderMismatch,
        message: 'Authenticated user identity does not match ownership.',
      );
    }

    return const MessageSecurityResult.allowed();
  }

  // --------------------------------------------------------------------------
  // MESSAGE OWNERSHIP
  // --------------------------------------------------------------------------

  /// Returns whether [authenticatedUid] owns [message].
  bool isMessageOwner({
    required String? authenticatedUid,
    required MessageEntity message,
  }) {
    final String currentUid;

    try {
      currentUid = requireAuthenticatedUid(authenticatedUid);
    } on MessageSecurityException {
      return false;
    }

    return currentUid == message.senderUid.trim();
  }

  /// Requires that [message] belongs to the authenticated Firebase UID.
  void requireMessageOwner({
    required String? authenticatedUid,
    required MessageEntity message,
  }) {
    final String currentUid = requireAuthenticatedUid(authenticatedUid);
    final String senderUid = normalizeUid(message.senderUid);

    if (senderUid != currentUid) {
      throw const MessageSecurityException(
        code: MessageSecurityErrorCode.senderMismatch,
        message: 'Only the message sender may perform this action.',
      );
    }
  }

  /// Verifies sender ownership without throwing.
  MessageSecurityResult verifyMessageOwner({
    required String? authenticatedUid,
    required MessageEntity message,
  }) {
    try {
      requireMessageOwner(authenticatedUid: authenticatedUid, message: message);

      return const MessageSecurityResult.allowed();
    } on MessageSecurityException catch (error) {
      return MessageSecurityResult.denied(
        code: error.code,
        message: error.message,
      );
    }
  }

  // --------------------------------------------------------------------------
  // CONVERSATION MEMBERSHIP
  // --------------------------------------------------------------------------

  /// Returns whether [authenticatedUid] is a canonical participant.
  bool isConversationParticipant({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    final String currentUid;

    try {
      currentUid = requireAuthenticatedUid(authenticatedUid);
    } on MessageSecurityException {
      return false;
    }

    for (final String participantUid in conversation.participantUids) {
      if (participantUid.trim() == currentUid) {
        return true;
      }
    }

    return false;
  }

  /// Requires authenticated user membership in [conversation].
  void requireConversationParticipant({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    final String currentUid = requireAuthenticatedUid(authenticatedUid);

    final String conversationId = normalizeConversationId(conversation.id);

    if (conversation.participantUids.isEmpty) {
      throw MessageSecurityException(
        code: MessageSecurityErrorCode.invalidConversation,
        message: 'Conversation participant data is invalid.',
        cause: conversationId,
      );
    }

    bool found = false;

    for (final String rawParticipantUid in conversation.participantUids) {
      final String participantUid = rawParticipantUid.trim();

      if (participantUid.isEmpty) {
        throw MessageSecurityException(
          code: MessageSecurityErrorCode.invalidConversation,
          message: 'Conversation participant data is invalid.',
          cause: conversationId,
        );
      }

      if (participantUid == currentUid) {
        found = true;
      }
    }

    if (!found) {
      throw const MessageSecurityException(
        code: MessageSecurityErrorCode.notParticipant,
        message: 'You do not have access to this conversation.',
      );
    }
  }

  /// Non-throwing participant membership verification.
  MessageSecurityResult verifyConversationParticipant({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    try {
      requireConversationParticipant(
        authenticatedUid: authenticatedUid,
        conversation: conversation,
      );

      return const MessageSecurityResult.allowed();
    } on MessageSecurityException catch (error) {
      return MessageSecurityResult.denied(
        code: error.code,
        message: error.message,
      );
    }
  }

  /// Requires that [message] belongs to [conversation].
  void requireMessageConversation({
    required MessageEntity message,
    required ConversationEntity conversation,
  }) {
    final String messageConversationId = normalizeConversationId(
      message.conversationId,
    );

    final String conversationId = normalizeConversationId(conversation.id);

    if (messageConversationId != conversationId) {
      throw const MessageSecurityException(
        code: MessageSecurityErrorCode.invalidConversation,
        message: 'Message does not belong to this conversation.',
      );
    }
  }

  /// Strong invariant for sender-owned conversation mutations.
  ///
  /// Requires:
  /// - valid authenticated Firebase UID,
  /// - participant membership,
  /// - message/conversation identity match,
  /// - authenticated sender ownership.
  void requireSenderOwnedConversationMessage({
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    requireConversationParticipant(
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    );

    requireMessageConversation(message: message, conversation: conversation);

    requireMessageOwner(authenticatedUid: authenticatedUid, message: message);
  }

  // --------------------------------------------------------------------------
  // IDENTIFIER NORMALIZATION
  // --------------------------------------------------------------------------

  String normalizeUid(String value) {
    final String normalized = value.trim();

    _requireSafeIdentifier(
      normalized,
      fieldName: 'uid',
      errorCode: MessageSecurityErrorCode.invalidUid,
    );

    return normalized;
  }

  String normalizeMessageId(String value) {
    final String normalized = value.trim();

    _requireSafeIdentifier(
      normalized,
      fieldName: 'messageId',
      errorCode: MessageSecurityErrorCode.invalidIdentifier,
    );

    return normalized;
  }

  String normalizeConversationId(String value) {
    final String normalized = value.trim();

    _requireSafeIdentifier(
      normalized,
      fieldName: 'conversationId',
      errorCode: MessageSecurityErrorCode.invalidConversation,
    );

    return normalized;
  }

  /// Rejects identifiers that could accidentally be interpreted as Firestore
  /// path fragments rather than one canonical document identity.
  void _requireSafeIdentifier(
    String value, {
    required String fieldName,
    required MessageSecurityErrorCode errorCode,
  }) {
    if (value.isEmpty) {
      throw MessageSecurityException(
        code: errorCode,
        message: '$fieldName must not be empty.',
      );
    }

    if (value.contains('/') ||
        value.contains('\\') ||
        value.contains('\u0000')) {
      throw MessageSecurityException(
        code: errorCode,
        message: '$fieldName contains invalid characters.',
      );
    }

    if (_containsControlCharacters(value)) {
      throw MessageSecurityException(
        code: errorCode,
        message: '$fieldName contains invalid control characters.',
      );
    }
  }

  // --------------------------------------------------------------------------
  // SAFE TEXT NORMALIZATION
  // --------------------------------------------------------------------------

  /// Normalizes user-authored message/live text without altering legitimate
  /// Unicode, emoji or multiline content.
  ///
  /// Behavior:
  /// - normalizes CRLF/CR to LF,
  /// - removes NUL characters,
  /// - removes unsupported ASCII control characters,
  /// - trims only outer whitespace,
  /// - preserves internal whitespace/newlines,
  /// - applies a defensive absolute bound.
  ///
  /// FILE 31 remains the canonical product validation owner and may apply a
  /// stricter policy/limit.
  String normalizeText(String value, {bool allowEmpty = false}) {
    String normalized = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u0000', '');

    normalized = _removeUnsafeControlCharacters(normalized).trim();

    if (!allowEmpty && normalized.isEmpty) {
      throw const MessageSecurityException(
        code: MessageSecurityErrorCode.invalidText,
        message: 'Message text must not be empty.',
      );
    }

    if (normalized.length > _maxNormalizedTextLength) {
      throw const MessageSecurityException(
        code: MessageSecurityErrorCode.invalidText,
        message: 'Message text exceeds the safe processing limit.',
      );
    }

    return normalized;
  }

  static String _removeUnsafeControlCharacters(String value) {
    final StringBuffer buffer = StringBuffer();

    for (final int rune in value.runes) {
      final bool allowedWhitespace = rune == 0x09 || rune == 0x0A;

      final bool unsafeAsciiControl = rune < 0x20 && !allowedWhitespace;

      final bool deleteControl = rune == 0x7F;

      if (!unsafeAsciiControl && !deleteControl) {
        buffer.writeCharCode(rune);
      }
    }

    return buffer.toString();
  }

  static bool _containsControlCharacters(String value) {
    for (final int rune in value.runes) {
      if (rune < 0x20 || rune == 0x7F) {
        return true;
      }
    }

    return false;
  }

  // --------------------------------------------------------------------------
  // SENSITIVE FIELD / SECRET PROTECTION
  // --------------------------------------------------------------------------

  /// Throws when a payload contains credential-like field names.
  ///
  /// Nested maps and iterables are recursively inspected. This protects
  /// message-domain persistence from accidentally receiving password/OTP/token
  /// material.
  void rejectSensitiveFields(Map<String, Object?> payload) {
    _inspectSensitiveValue(payload, path: 'payload');
  }

  /// Returns true when a payload contains a credential-like field name.
  bool containsSensitiveFields(Map<String, Object?> payload) {
    try {
      rejectSensitiveFields(payload);
      return false;
    } on MessageSecurityException catch (error) {
      if (error.code == MessageSecurityErrorCode.sensitiveContent) {
        return true;
      }

      rethrow;
    }
  }

  void _inspectSensitiveValue(Object? value, {required String path}) {
    if (value is Map<String, Object?>) {
      for (final MapEntry<String, Object?> entry in value.entries) {
        final String normalizedKey = _normalizeFieldToken(entry.key);

        if (_sensitiveFieldTokens.contains(normalizedKey)) {
          throw MessageSecurityException(
            code: MessageSecurityErrorCode.sensitiveContent,
            message: 'Sensitive credential fields are not allowed in messages.',
            cause: path,
          );
        }

        _inspectSensitiveValue(entry.value, path: '$path.${entry.key}');
      }

      return;
    }

    if (value is Map) {
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final Object? rawKey = entry.key;

        if (rawKey is! String) {
          continue;
        }

        final String normalizedKey = _normalizeFieldToken(rawKey);

        if (_sensitiveFieldTokens.contains(normalizedKey)) {
          throw MessageSecurityException(
            code: MessageSecurityErrorCode.sensitiveContent,
            message: 'Sensitive credential fields are not allowed in messages.',
            cause: path,
          );
        }

        _inspectSensitiveValue(entry.value, path: '$path.$rawKey');
      }

      return;
    }

    if (value is Iterable) {
      int index = 0;

      for (final Object? item in value) {
        _inspectSensitiveValue(item, path: '$path[$index]');

        index++;
      }
    }
  }

  static String _normalizeFieldToken(String value) {
    final String lower = value.trim().toLowerCase();
    final StringBuffer buffer = StringBuffer();

    for (final int rune in lower.runes) {
      final bool isAlphaNumeric =
          (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7A);

      if (isAlphaNumeric) {
        buffer.writeCharCode(rune);
      }
    }

    return buffer.toString();
  }

  // --------------------------------------------------------------------------
  // REDACTION
  // --------------------------------------------------------------------------

  /// Produces a diagnostic-safe map.
  ///
  /// Sensitive values are replaced recursively while preserving enough shape
  /// for internal debugging.
  Map<String, Object?> redactForLog(Map<String, Object?> source) {
    final Map<String, Object?> result = <String, Object?>{};

    for (final MapEntry<String, Object?> entry in source.entries) {
      final String normalizedKey = _normalizeFieldToken(entry.key);

      if (_sensitiveFieldTokens.contains(normalizedKey)) {
        result[entry.key] = _redacted;
        continue;
      }

      result[entry.key] = _redactValue(entry.value);
    }

    return Map<String, Object?>.unmodifiable(result);
  }

  Object? _redactValue(Object? value) {
    if (value is Map<String, Object?>) {
      return redactForLog(value);
    }

    if (value is Map) {
      final Map<String, Object?> converted = <String, Object?>{};

      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final Object? rawKey = entry.key;

        if (rawKey is! String) {
          continue;
        }

        final String normalizedKey = _normalizeFieldToken(rawKey);

        if (_sensitiveFieldTokens.contains(normalizedKey)) {
          converted[rawKey] = _redacted;
        } else {
          converted[rawKey] = _redactValue(entry.value);
        }
      }

      return Map<String, Object?>.unmodifiable(converted);
    }

    if (value is Iterable) {
      return List<Object?>.unmodifiable(value.map<Object?>(_redactValue));
    }

    if (value is String) {
      return redactTextForLog(value);
    }

    return value;
  }

  /// Redacts common credential-shaped text fragments for diagnostics.
  ///
  /// This is a defensive log helper, not a content classifier or encryption
  /// mechanism.
  String redactTextForLog(String value) {
    String result = value;

    const List<String> labels = <String>[
      'password',
      'passcode',
      'otp',
      'verification code',
      'access token',
      'refresh token',
      'id token',
      'bearer token',
      'authorization',
      'api key',
      'secret key',
      'private key',
    ];

    for (final String label in labels) {
      result = _redactLabeledValue(result, label);
    }

    result = _redactBearerTokens(result);

    return result;
  }

  static String _redactLabeledValue(String input, String label) {
    final String lowerInput = input.toLowerCase();
    final String lowerLabel = label.toLowerCase();

    final StringBuffer output = StringBuffer();

    int cursor = 0;

    while (cursor < input.length) {
      final int match = lowerInput.indexOf(lowerLabel, cursor);

      if (match < 0) {
        output.write(input.substring(cursor));
        break;
      }

      output.write(input.substring(cursor, match));

      final int labelEnd = match + lowerLabel.length;
      output.write(input.substring(match, labelEnd));

      int valueStart = labelEnd;

      while (valueStart < input.length) {
        final String character = input[valueStart];

        if (character == ' ' ||
            character == '\t' ||
            character == ':' ||
            character == '=') {
          output.write(character);
          valueStart++;
          continue;
        }

        break;
      }

      if (valueStart >= input.length) {
        cursor = valueStart;
        continue;
      }

      int valueEnd = valueStart;

      while (valueEnd < input.length) {
        final int codeUnit = input.codeUnitAt(valueEnd);

        final bool endsValue =
            codeUnit == 0x0A ||
            codeUnit == 0x0D ||
            codeUnit == 0x2C ||
            codeUnit == 0x3B;

        if (endsValue) {
          break;
        }

        valueEnd++;
      }

      output.write(_redacted);
      cursor = valueEnd;
    }

    return output.toString();
  }

  static String _redactBearerTokens(String input) {
    final String lower = input.toLowerCase();
    final StringBuffer output = StringBuffer();

    int cursor = 0;

    while (cursor < input.length) {
      final int match = lower.indexOf('bearer ', cursor);

      if (match < 0) {
        output.write(input.substring(cursor));
        break;
      }

      output.write(input.substring(cursor, match));

      final int tokenStart = match + 7;

      output.write(input.substring(match, tokenStart));
      output.write(_redacted);

      int tokenEnd = tokenStart;

      while (tokenEnd < input.length) {
        final int codeUnit = input.codeUnitAt(tokenEnd);

        final bool whitespace =
            codeUnit == 0x20 ||
            codeUnit == 0x09 ||
            codeUnit == 0x0A ||
            codeUnit == 0x0D;

        if (whitespace) {
          break;
        }

        tokenEnd++;
      }

      cursor = tokenEnd;
    }

    return output.toString();
  }

  // --------------------------------------------------------------------------
  // SAFE ERROR EXPOSURE
  // --------------------------------------------------------------------------

  /// Converts arbitrary internal errors into a safe message-domain security
  /// exception suitable for propagation to higher layers.
  MessageSecurityException exposeSafeError(
    Object error, {
    StackTrace? stackTrace,
  }) {
    if (error is MessageSecurityException) {
      return error;
    }

    if (error is ArgumentError || error is FormatException) {
      return MessageSecurityException(
        code: MessageSecurityErrorCode.malformedData,
        message: 'Messaging data is invalid.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is StateError) {
      return MessageSecurityException(
        code: MessageSecurityErrorCode.forbidden,
        message: 'The messaging operation is not currently allowed.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return MessageSecurityException(
      code: MessageSecurityErrorCode.unknown,
      message: 'The messaging operation could not be completed securely.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Returns only the safe public text from an internal error.
  String safeErrorMessage(Object error) {
    return exposeSafeError(error).message;
  }

  // --------------------------------------------------------------------------
  // DOMAIN INVARIANTS
  // --------------------------------------------------------------------------

  /// Validates the minimum identity invariants of a durable message.
  ///
  /// Detailed product validation remains FILE 31's responsibility.
  void requireValidMessageIdentity(MessageEntity message) {
    normalizeMessageId(message.id);
    normalizeConversationId(message.conversationId);
    normalizeUid(message.senderUid);
  }

  /// Validates the minimum identity invariants of a conversation.
  void requireValidConversationIdentity(ConversationEntity conversation) {
    normalizeConversationId(conversation.id);

    if (conversation.participantUids.isEmpty) {
      throw const MessageSecurityException(
        code: MessageSecurityErrorCode.invalidConversation,
        message: 'Conversation must contain participants.',
      );
    }

    final Set<String> uniqueParticipants = <String>{};

    for (final String rawUid in conversation.participantUids) {
      final String uid = normalizeUid(rawUid);

      if (!uniqueParticipants.add(uid)) {
        throw const MessageSecurityException(
          code: MessageSecurityErrorCode.invalidConversation,
          message: 'Conversation contains duplicate participants.',
        );
      }
    }
  }

  /// Validates that a durable message has valid identity and belongs to the
  /// supplied conversation.
  void requireMessageConversationInvariant({
    required MessageEntity message,
    required ConversationEntity conversation,
  }) {
    requireValidMessageIdentity(message);
    requireValidConversationIdentity(conversation);
    requireMessageConversation(message: message, conversation: conversation);

    final String senderUid = normalizeUid(message.senderUid);

    bool senderIsParticipant = false;

    for (final String participantUid in conversation.participantUids) {
      if (participantUid.trim() == senderUid) {
        senderIsParticipant = true;
        break;
      }
    }

    if (!senderIsParticipant) {
      throw const MessageSecurityException(
        code: MessageSecurityErrorCode.notParticipant,
        message: 'Message sender is not a conversation participant.',
      );
    }
  }
}

// ============================================================================
// END OF FILE: lib/features/message/security/message_security.dart
// ============================================================================
