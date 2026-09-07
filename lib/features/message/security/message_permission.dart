// ============================================================================
// JR CALL
// File: message_permission.dart
// Location: lib/features/message/security/message_permission.dart
// Description:
// Typed client-side authorization policy for JR CALL Message Engine.
//
// Owns:
// - maySend
// - mayEdit
// - mayDelete
// - mayReact
// - mayRead
// - mayUpload
// - mayUseLiveChat
// - mayAccessConversation
//
// Security model:
// - Firebase Auth UID is the canonical internal identity.
// - Conversation membership is required for private conversation actions.
// - Sender ownership is required for sender-owned message mutations.
// - Public JR CALL ID / username / phone / email are never ownership IDs.
// - Firebase Firestore/Storage Security Rules remain final server authority.
//
// Does NOT:
// - Perform Firestore writes.
// - Perform Firebase Storage writes.
// - Authenticate users.
// - Create credentials.
// - Replace Firebase Security Rules.
// - Implement UI.
// - Implement Call Engine/WebRTC.
// ============================================================================

import '../data/conversation_entity.dart';
import '../data/message_entity.dart';
import '../data/message_type.dart';
import 'message_security.dart';

/// Messaging actions understood by the authorization layer.
enum MessagePermissionAction {
  accessConversation,
  send,
  edit,
  delete,
  react,
  read,
  upload,
  useLiveChat,
}

/// Stable permission-denial categories.
///
/// These values are domain-facing and intentionally avoid exposing raw
/// Firebase/backend error text.
enum MessagePermissionDenyReason {
  unauthenticated,
  invalidIdentity,
  invalidConversation,
  notParticipant,
  senderMismatch,
  messageConversationMismatch,
  deletedMessage,
  unsupportedMessageType,
  forbidden,
}

/// Immutable typed authorization result.
final class MessagePermissionResult {
  const MessagePermissionResult._({
    required this.action,
    required this.allowed,
    this.reason,
    this.message,
  });

  const MessagePermissionResult.allowed({
    required MessagePermissionAction action,
  }) : this._(action: action, allowed: true);

  const MessagePermissionResult.denied({
    required MessagePermissionAction action,
    required MessagePermissionDenyReason reason,
    required String message,
  }) : this._(action: action, allowed: false, reason: reason, message: message);

  final MessagePermissionAction action;
  final bool allowed;
  final MessagePermissionDenyReason? reason;

  /// Safe higher-layer description.
  final String? message;

  bool get denied => !allowed;

  /// Throws a typed permission exception when this result is denied.
  void requireAllowed() {
    if (allowed) {
      return;
    }

    throw MessagePermissionException(
      action: action,
      reason: reason ?? MessagePermissionDenyReason.forbidden,
      message: message ?? 'The requested messaging action is not allowed.',
    );
  }
}

/// Typed client authorization exception.
final class MessagePermissionException implements Exception {
  const MessagePermissionException({
    required this.action,
    required this.reason,
    required this.message,
  });

  final MessagePermissionAction action;
  final MessagePermissionDenyReason reason;
  final String message;

  @override
  String toString() {
    return 'MessagePermissionException('
        'action: ${action.name}, '
        'reason: ${reason.name}, '
        'message: $message'
        ')';
  }
}

/// JR CALL Message Engine client-side authorization policy.
///
/// This class provides defense-in-depth checks only. Firestore and Storage
/// Security Rules remain the final authorization authority.
final class MessagePermission {
  const MessagePermission({this.security = const MessageSecurity()});

  /// Shared Message Security policy used by this authorization layer.
  ///
  /// Exposed read-only so the constructor can retain the existing public
  /// `security:` named argument while using analyzer-clean initializing-formal
  /// assignment.
  final MessageSecurity security;

  // --------------------------------------------------------------------------
  // CONVERSATION ACCESS
  // --------------------------------------------------------------------------

  /// Whether [authenticatedUid] may access [conversation].
  MessagePermissionResult mayAccessConversation({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    final MessagePermissionResult identityResult = _validateIdentity(
      action: MessagePermissionAction.accessConversation,
      authenticatedUid: authenticatedUid,
    );

    if (identityResult.denied) {
      return identityResult;
    }

    final MessagePermissionResult conversationResult =
        _validateConversationMembership(
          action: MessagePermissionAction.accessConversation,
          authenticatedUid: authenticatedUid,
          conversation: conversation,
        );

    if (conversationResult.denied) {
      return conversationResult;
    }

    return const MessagePermissionResult.allowed(
      action: MessagePermissionAction.accessConversation,
    );
  }

  // --------------------------------------------------------------------------
  // SEND
  // --------------------------------------------------------------------------

  /// Whether the authenticated user may create a durable message inside
  /// [conversation].
  ///
  /// Payload validation remains FILE 31's responsibility. This method only
  /// decides authorization.
  MessagePermissionResult maySend({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    return _requireParticipantAction(
      action: MessagePermissionAction.send,
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    );
  }

  // --------------------------------------------------------------------------
  // EDIT
  // --------------------------------------------------------------------------

  /// Whether [authenticatedUid] may edit [message].
  ///
  /// Current production policy:
  /// - authenticated conversation participant,
  /// - message belongs to the conversation,
  /// - sender owns the message,
  /// - message is not deleted,
  /// - only durable text messages are editable.
  MessagePermissionResult mayEdit({
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    final MessagePermissionResult ownershipResult =
        _requireSenderOwnedMessageAction(
          action: MessagePermissionAction.edit,
          authenticatedUid: authenticatedUid,
          conversation: conversation,
          message: message,
        );

    if (ownershipResult.denied) {
      return ownershipResult;
    }

    if (message.deletedAt != null) {
      return const MessagePermissionResult.denied(
        action: MessagePermissionAction.edit,
        reason: MessagePermissionDenyReason.deletedMessage,
        message: 'Deleted messages cannot be edited.',
      );
    }

    if (message.type != MessageType.text) {
      return const MessagePermissionResult.denied(
        action: MessagePermissionAction.edit,
        reason: MessagePermissionDenyReason.unsupportedMessageType,
        message: 'Only text messages can currently be edited.',
      );
    }

    return const MessagePermissionResult.allowed(
      action: MessagePermissionAction.edit,
    );
  }

  // --------------------------------------------------------------------------
  // DELETE
  // --------------------------------------------------------------------------

  /// Whether [authenticatedUid] may perform the sender-owned server deletion
  /// policy for [message].
  ///
  /// Actual soft-delete/tombstone persistence belongs to the storage/repository
  /// layer.
  MessagePermissionResult mayDelete({
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    final MessagePermissionResult ownershipResult =
        _requireSenderOwnedMessageAction(
          action: MessagePermissionAction.delete,
          authenticatedUid: authenticatedUid,
          conversation: conversation,
          message: message,
        );

    if (ownershipResult.denied) {
      return ownershipResult;
    }

    if (message.deletedAt != null) {
      return const MessagePermissionResult.denied(
        action: MessagePermissionAction.delete,
        reason: MessagePermissionDenyReason.deletedMessage,
        message: 'This message has already been deleted.',
      );
    }

    return const MessagePermissionResult.allowed(
      action: MessagePermissionAction.delete,
    );
  }

  // --------------------------------------------------------------------------
  // REACTION
  // --------------------------------------------------------------------------

  /// Whether [authenticatedUid] may add/change/remove its own reaction on
  /// [message].
  ///
  /// Reaction ownership itself is enforced by the reacting Firebase UID in
  /// repository/storage/rules.
  MessagePermissionResult mayReact({
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    final MessagePermissionResult accessResult =
        _requireMessageParticipantAction(
          action: MessagePermissionAction.react,
          authenticatedUid: authenticatedUid,
          conversation: conversation,
          message: message,
        );

    if (accessResult.denied) {
      return accessResult;
    }

    if (message.deletedAt != null) {
      return const MessagePermissionResult.denied(
        action: MessagePermissionAction.react,
        reason: MessagePermissionDenyReason.deletedMessage,
        message: 'Deleted messages cannot receive reactions.',
      );
    }

    return const MessagePermissionResult.allowed(
      action: MessagePermissionAction.react,
    );
  }

  // --------------------------------------------------------------------------
  // READ
  // --------------------------------------------------------------------------

  /// Whether [authenticatedUid] may acknowledge [message] as read.
  ///
  /// Sender-owned messages are intentionally rejected: a user must not produce
  /// a recipient read receipt for its own outgoing message.
  MessagePermissionResult mayRead({
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    final MessagePermissionResult accessResult =
        _requireMessageParticipantAction(
          action: MessagePermissionAction.read,
          authenticatedUid: authenticatedUid,
          conversation: conversation,
          message: message,
        );

    if (accessResult.denied) {
      return accessResult;
    }

    final String currentUid;

    try {
      currentUid = security.requireAuthenticatedUid(authenticatedUid);
    } on MessageSecurityException catch (error) {
      return _fromSecurityException(
        action: MessagePermissionAction.read,
        error: error,
      );
    }

    final String senderUid;

    try {
      senderUid = security.normalizeUid(message.senderUid);
    } on MessageSecurityException catch (error) {
      return _fromSecurityException(
        action: MessagePermissionAction.read,
        error: error,
      );
    }

    if (currentUid == senderUid) {
      return const MessagePermissionResult.denied(
        action: MessagePermissionAction.read,
        reason: MessagePermissionDenyReason.senderMismatch,
        message: 'A sender cannot acknowledge its own message as read.',
      );
    }

    if (message.deletedAt != null) {
      return const MessagePermissionResult.denied(
        action: MessagePermissionAction.read,
        reason: MessagePermissionDenyReason.deletedMessage,
        message: 'Deleted messages do not require a new read acknowledgement.',
      );
    }

    return const MessagePermissionResult.allowed(
      action: MessagePermissionAction.read,
    );
  }

  // --------------------------------------------------------------------------
  // UPLOAD
  // --------------------------------------------------------------------------

  /// Whether [authenticatedUid] may upload message media for [conversation].
  ///
  /// MIME type, byte-size and attachment metadata validation remain FILE 31's
  /// responsibility. Storage Rules remain final server authority.
  MessagePermissionResult mayUpload({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    return _requireParticipantAction(
      action: MessagePermissionAction.upload,
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    );
  }

  // --------------------------------------------------------------------------
  // LIVE CHAT
  // --------------------------------------------------------------------------

  /// Whether [authenticatedUid] may publish its own ephemeral Live Chat state
  /// inside [conversation].
  ///
  /// The Live Chat document must still be owned by the authenticated Firebase
  /// UID and validated by Firebase Security Rules.
  MessagePermissionResult mayUseLiveChat({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    return _requireParticipantAction(
      action: MessagePermissionAction.useLiveChat,
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    );
  }

  // --------------------------------------------------------------------------
  // THROWING CONVENIENCE METHODS
  // --------------------------------------------------------------------------

  void requireAccessConversation({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    mayAccessConversation(
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    ).requireAllowed();
  }

  void requireSend({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    maySend(
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    ).requireAllowed();
  }

  void requireEdit({
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    mayEdit(
      authenticatedUid: authenticatedUid,
      conversation: conversation,
      message: message,
    ).requireAllowed();
  }

  void requireDelete({
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    mayDelete(
      authenticatedUid: authenticatedUid,
      conversation: conversation,
      message: message,
    ).requireAllowed();
  }

  void requireReact({
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    mayReact(
      authenticatedUid: authenticatedUid,
      conversation: conversation,
      message: message,
    ).requireAllowed();
  }

  void requireRead({
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    mayRead(
      authenticatedUid: authenticatedUid,
      conversation: conversation,
      message: message,
    ).requireAllowed();
  }

  void requireUpload({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    mayUpload(
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    ).requireAllowed();
  }

  void requireUseLiveChat({
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    mayUseLiveChat(
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    ).requireAllowed();
  }

  // --------------------------------------------------------------------------
  // INTERNAL AUTHORIZATION HELPERS
  // --------------------------------------------------------------------------

  MessagePermissionResult _requireParticipantAction({
    required MessagePermissionAction action,
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    final MessagePermissionResult identityResult = _validateIdentity(
      action: action,
      authenticatedUid: authenticatedUid,
    );

    if (identityResult.denied) {
      return identityResult;
    }

    return _validateConversationMembership(
      action: action,
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    );
  }

  MessagePermissionResult _requireMessageParticipantAction({
    required MessagePermissionAction action,
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    final MessagePermissionResult participantResult = _requireParticipantAction(
      action: action,
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    );

    if (participantResult.denied) {
      return participantResult;
    }

    try {
      security.requireValidMessageIdentity(message);
      security.requireMessageConversation(
        message: message,
        conversation: conversation,
      );
    } on MessageSecurityException catch (error) {
      return _fromSecurityException(action: action, error: error);
    }

    return MessagePermissionResult.allowed(action: action);
  }

  MessagePermissionResult _requireSenderOwnedMessageAction({
    required MessagePermissionAction action,
    required String? authenticatedUid,
    required ConversationEntity conversation,
    required MessageEntity message,
  }) {
    final MessagePermissionResult participantResult = _requireParticipantAction(
      action: action,
      authenticatedUid: authenticatedUid,
      conversation: conversation,
    );

    if (participantResult.denied) {
      return participantResult;
    }

    try {
      security.requireSenderOwnedConversationMessage(
        authenticatedUid: authenticatedUid,
        conversation: conversation,
        message: message,
      );
    } on MessageSecurityException catch (error) {
      return _fromSecurityException(action: action, error: error);
    }

    return MessagePermissionResult.allowed(action: action);
  }

  MessagePermissionResult _validateIdentity({
    required MessagePermissionAction action,
    required String? authenticatedUid,
  }) {
    try {
      security.requireAuthenticatedUid(authenticatedUid);

      return MessagePermissionResult.allowed(action: action);
    } on MessageSecurityException catch (error) {
      return _fromSecurityException(action: action, error: error);
    }
  }

  MessagePermissionResult _validateConversationMembership({
    required MessagePermissionAction action,
    required String? authenticatedUid,
    required ConversationEntity conversation,
  }) {
    try {
      security.requireValidConversationIdentity(conversation);
      security.requireConversationParticipant(
        authenticatedUid: authenticatedUid,
        conversation: conversation,
      );

      return MessagePermissionResult.allowed(action: action);
    } on MessageSecurityException catch (error) {
      return _fromSecurityException(action: action, error: error);
    }
  }

  static MessagePermissionResult _fromSecurityException({
    required MessagePermissionAction action,
    required MessageSecurityException error,
  }) {
    return MessagePermissionResult.denied(
      action: action,
      reason: _mapSecurityReason(error.code),
      message: error.message,
    );
  }

  static MessagePermissionDenyReason _mapSecurityReason(
    MessageSecurityErrorCode code,
  ) {
    switch (code) {
      case MessageSecurityErrorCode.unauthenticated:
        return MessagePermissionDenyReason.unauthenticated;

      case MessageSecurityErrorCode.invalidUid:
      case MessageSecurityErrorCode.invalidIdentifier:
        return MessagePermissionDenyReason.invalidIdentity;

      case MessageSecurityErrorCode.invalidConversation:
        return MessagePermissionDenyReason.invalidConversation;

      case MessageSecurityErrorCode.notParticipant:
        return MessagePermissionDenyReason.notParticipant;

      case MessageSecurityErrorCode.senderMismatch:
        return MessagePermissionDenyReason.senderMismatch;

      case MessageSecurityErrorCode.sensitiveContent:
      case MessageSecurityErrorCode.invalidText:
      case MessageSecurityErrorCode.malformedData:
      case MessageSecurityErrorCode.forbidden:
      case MessageSecurityErrorCode.unknown:
        return MessagePermissionDenyReason.forbidden;
    }
  }
}

// ============================================================================
// END OF FILE: lib/features/message/security/message_permission.dart
// ============================================================================
