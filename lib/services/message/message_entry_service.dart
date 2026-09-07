// ============================================================================
// JR CALL
// File: message_entry_service.dart
// Location: lib/services/message/message_entry_service.dart
// Description:
// Central authenticated entry bridge from the existing JR CALL application
// into the finalized Message feature.
//
// Owns:
// - Message destination entry validation.
// - Existing-conversation entry.
// - Firebase-UID based direct-chat entry.
// - Stable direct-conversation resolution through ConversationRepository.
// - Guest/authentication protection.
// - Duplicate rapid-entry protection.
// - Safe typed navigation handoff.
//
// Does NOT:
// - Search users.
// - Replace UserDiscoveryService.
// - Use username/public JR CALL ID/email/phone as ownership identity.
// - Call Firestore directly.
// - Call Firebase Storage directly.
// - Handle raw FCM parsing.
// - Render Message/Chat screens.
// - Recreate Message Engine.
// - Recreate Call Engine/WebRTC.
// - Create Firebase authentication credentials.
// ============================================================================

import 'dart:async';

import '../../features/message/data/conversation_entity.dart';
import '../../features/message/repository/conversation_repository.dart';

/// Returns the currently authenticated canonical Firebase UID.
///
/// Existing AuthService/application session remains the authentication owner.
/// This service only consumes the already-authenticated UID.
typedef MessageCurrentUidProvider = String? Function();

/// Called when an unauthenticated user attempts a protected Message action.
///
/// Existing app navigation/auth flow decides whether Login/Create Account is
/// shown and how the pending action is resumed.
typedef MessageAuthenticationRequiredHandler =
    FutureOr<void> Function(MessageEntryRequest request);

/// Final navigation handoff after a conversation has been validated/resolved.
///
/// message_navigation_service.dart can implement this boundary without this
/// entry service importing presentation widgets or Navigator directly.
typedef MessageConversationOpenHandler =
    FutureOr<void> Function(MessageConversationEntry entry);

/// Opens the main authenticated Message inbox.
///
/// The actual screen/navigation implementation remains outside this service.
typedef MessageInboxOpenHandler = FutureOr<void> Function();

/// Supported application entry sources.
///
/// These values describe where a Message action originated; they never become
/// database ownership identity.
enum MessageEntrySource {
  home,
  contacts,
  profile,
  discovery,
  notification,
  deepLink,
  inbox,
  unknown,
}

/// Type of Message feature entry requested.
enum MessageEntryType { inbox, conversation, directPeer }

/// Immutable request entering the Message integration boundary.
final class MessageEntryRequest {
  const MessageEntryRequest._({
    required this.type,
    required this.source,
    this.conversationId,
    this.peerUid,
  });

  /// Opens the main Message destination.
  const MessageEntryRequest.inbox({
    MessageEntrySource source = MessageEntrySource.home,
  }) : this._(type: MessageEntryType.inbox, source: source);

  /// Opens one known canonical conversation.
  const MessageEntryRequest.conversation({
    required String conversationId,
    MessageEntrySource source = MessageEntrySource.unknown,
  }) : this._(
         type: MessageEntryType.conversation,
         source: source,
         conversationId: conversationId,
       );

  /// Finds/creates the canonical direct conversation for [peerUid].
  ///
  /// [peerUid] MUST already be the user's Firebase Auth UID.
  /// UserDiscoveryService must resolve public username/JR CALL ID/email/phone
  /// before this request is constructed.
  const MessageEntryRequest.directPeer({
    required String peerUid,
    MessageEntrySource source = MessageEntrySource.discovery,
  }) : this._(
         type: MessageEntryType.directPeer,
         source: source,
         peerUid: peerUid,
       );

  final MessageEntryType type;
  final MessageEntrySource source;

  /// Canonical conversation document ID when opening an existing conversation.
  final String? conversationId;

  /// Canonical Firebase UID when creating/opening a direct conversation.
  final String? peerUid;

  String get operationKey {
    switch (type) {
      case MessageEntryType.inbox:
        return 'inbox';

      case MessageEntryType.conversation:
        return 'conversation::${conversationId?.trim() ?? ''}';

      case MessageEntryType.directPeer:
        return 'peer::${peerUid?.trim() ?? ''}';
    }
  }
}

/// Validated conversation navigation payload.
///
/// Both [currentUserUid] and participant values inside [conversation] remain
/// canonical Firebase Auth UIDs.
final class MessageConversationEntry {
  const MessageConversationEntry({
    required this.conversation,
    required this.currentUserUid,
    required this.source,
  });

  final ConversationEntity conversation;
  final String currentUserUid;
  final MessageEntrySource source;

  String get conversationId => conversation.id;

  /// Returns the other participant UID for a direct conversation when one can
  /// be determined safely.
  String? get peerUid {
    for (final String uid in conversation.participantUids) {
      final String normalized = uid.trim();

      if (normalized.isNotEmpty && normalized != currentUserUid) {
        return normalized;
      }
    }

    return null;
  }
}

/// Result of one Message entry attempt.
final class MessageEntryResult {
  const MessageEntryResult._({
    required this.status,
    required this.request,
    this.conversation,
    this.safeMessage,
  });

  factory MessageEntryResult.openedInbox(MessageEntryRequest request) {
    return MessageEntryResult._(
      status: MessageEntryStatus.openedInbox,
      request: request,
    );
  }

  factory MessageEntryResult.openedConversation(
    MessageEntryRequest request,
    ConversationEntity conversation,
  ) {
    return MessageEntryResult._(
      status: MessageEntryStatus.openedConversation,
      request: request,
      conversation: conversation,
    );
  }

  factory MessageEntryResult.authenticationRequired(
    MessageEntryRequest request,
  ) {
    return MessageEntryResult._(
      status: MessageEntryStatus.authenticationRequired,
      request: request,
    );
  }

  factory MessageEntryResult.rejected(
    MessageEntryRequest request,
    String safeMessage,
  ) {
    return MessageEntryResult._(
      status: MessageEntryStatus.rejected,
      request: request,
      safeMessage: safeMessage,
    );
  }

  factory MessageEntryResult.failed(
    MessageEntryRequest request,
    String safeMessage,
  ) {
    return MessageEntryResult._(
      status: MessageEntryStatus.failed,
      request: request,
      safeMessage: safeMessage,
    );
  }

  final MessageEntryStatus status;
  final MessageEntryRequest request;
  final ConversationEntity? conversation;

  /// Safe application-facing text only.
  final String? safeMessage;

  bool get succeeded =>
      status == MessageEntryStatus.openedInbox ||
      status == MessageEntryStatus.openedConversation;
}

/// Outcome categories for Message feature entry.
enum MessageEntryStatus {
  openedInbox,
  openedConversation,
  authenticationRequired,
  rejected,
  failed,
}

/// Safe integration-layer failure.
final class MessageEntryException implements Exception {
  const MessageEntryException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => 'MessageEntryException: $safeMessage';
}

/// JR CALL Message feature entry service.
///
/// Typical flow:
///
/// Existing Home/Contacts/Profile/Discovery action
///   -> MessageEntryService
///   -> authentication validation
///   -> ConversationRepository
///   -> MessageNavigationService callback
///   -> finalized Message presentation/controller stack.
///
/// Public IDs are never accepted as internal identity here.
final class MessageEntryService {
  /// Public constructor.
  ///
  /// Parameter names remain unchanged for existing JR CALL integration code.
  /// Assignment is delegated to the private initializing-formal constructor so
  /// analyzer style rules remain clean without changing any public API.
  factory MessageEntryService({
    required ConversationRepository conversationRepository,
    required MessageCurrentUidProvider currentUidProvider,
    required MessageAuthenticationRequiredHandler onAuthenticationRequired,
    required MessageConversationOpenHandler onOpenConversation,
    required MessageInboxOpenHandler onOpenInbox,
  }) {
    return MessageEntryService._(
      conversationRepository,
      currentUidProvider,
      onAuthenticationRequired,
      onOpenConversation,
      onOpenInbox,
    );
  }

  MessageEntryService._(
    this._conversationRepository,
    this._currentUidProvider,
    this._onAuthenticationRequired,
    this._onOpenConversation,
    this._onOpenInbox,
  );

  final ConversationRepository _conversationRepository;
  final MessageCurrentUidProvider _currentUidProvider;
  final MessageAuthenticationRequiredHandler _onAuthenticationRequired;
  final MessageConversationOpenHandler _onOpenConversation;
  final MessageInboxOpenHandler _onOpenInbox;

  final Map<String, Future<MessageEntryResult>> _activeEntries =
      <String, Future<MessageEntryResult>>{};

  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// General application entry point.
  ///
  /// Rapid repeated taps for the same target share the same active operation.
  Future<MessageEntryResult> enter(MessageEntryRequest request) {
    _ensureActive();

    final String key = _entryOperationKey(request);

    final Future<MessageEntryResult>? active = _activeEntries[key];

    if (active != null) {
      return active;
    }

    final Future<MessageEntryResult> operation = _performEntry(request);

    _activeEntries[key] = operation;

    operation.whenComplete(() {
      if (identical(_activeEntries[key], operation)) {
        _activeEntries.remove(key);
      }
    });

    return operation;
  }

  /// Opens the main Message destination.
  Future<MessageEntryResult> openInbox({
    MessageEntrySource source = MessageEntrySource.home,
  }) {
    return enter(MessageEntryRequest.inbox(source: source));
  }

  /// Opens an already-known canonical conversation.
  Future<MessageEntryResult> openConversation({
    required String conversationId,
    MessageEntrySource source = MessageEntrySource.inbox,
  }) {
    return enter(
      MessageEntryRequest.conversation(
        conversationId: conversationId,
        source: source,
      ),
    );
  }

  /// Opens/creates a stable direct conversation for a Firebase UID.
  ///
  /// UserDiscoveryService must perform name/username/JR CALL ID/email/phone
  /// lookup first and pass the resolved Firebase UID here.
  Future<MessageEntryResult> openDirectPeer({
    required String peerUid,
    MessageEntrySource source = MessageEntrySource.discovery,
  }) {
    return enter(
      MessageEntryRequest.directPeer(peerUid: peerUid, source: source),
    );
  }

  Future<MessageEntryResult> _performEntry(MessageEntryRequest request) async {
    final String? currentUid = _authenticatedUid();

    if (currentUid == null) {
      try {
        await _onAuthenticationRequired(request);
      } catch (_) {
        return MessageEntryResult.failed(
          request,
          'Unable to open the account sign-in flow.',
        );
      }

      return MessageEntryResult.authenticationRequired(request);
    }

    try {
      switch (request.type) {
        case MessageEntryType.inbox:
          await _onOpenInbox();

          return MessageEntryResult.openedInbox(request);

        case MessageEntryType.conversation:
          return await _openExistingConversation(
            request: request,
            currentUid: currentUid,
          );

        case MessageEntryType.directPeer:
          return await _openDirectConversation(
            request: request,
            currentUid: currentUid,
          );
      }
    } on MessageEntryException catch (error) {
      return MessageEntryResult.rejected(request, error.safeMessage);
    } catch (_) {
      return MessageEntryResult.failed(
        request,
        'Unable to open Messages right now.',
      );
    }
  }

  Future<MessageEntryResult> _openExistingConversation({
    required MessageEntryRequest request,
    required String currentUid,
  }) async {
    final String conversationId = _requiredId(
      request.conversationId,
      fieldName: 'conversationId',
      safeMessage: 'Conversation is unavailable.',
    );

    final ConversationEntity? conversation = await _conversationRepository
        .getConversation(
          conversationId: conversationId,
          requesterUid: currentUid,
        );

    if (conversation == null) {
      throw const MessageEntryException('Conversation is no longer available.');
    }

    _validateConversationAccess(
      conversation: conversation,
      currentUid: currentUid,
    );

    await _onOpenConversation(
      MessageConversationEntry(
        conversation: conversation,
        currentUserUid: currentUid,
        source: request.source,
      ),
    );

    return MessageEntryResult.openedConversation(request, conversation);
  }

  Future<MessageEntryResult> _openDirectConversation({
    required MessageEntryRequest request,
    required String currentUid,
  }) async {
    final String peerUid = _requiredId(
      request.peerUid,
      fieldName: 'peerUid',
      safeMessage: 'Unable to open this user conversation.',
    );

    if (peerUid == currentUid) {
      throw const MessageEntryException(
        'You cannot start a direct conversation with yourself.',
      );
    }

    final ConversationEntity conversation = await _conversationRepository
        .findOrCreateDirect(currentUid: currentUid, peerUid: peerUid);

    _validateConversationAccess(
      conversation: conversation,
      currentUid: currentUid,
    );

    final bool containsPeer = conversation.participantUids.any(
      (String participantUid) => participantUid.trim() == peerUid,
    );

    if (!containsPeer) {
      throw const MessageEntryException(
        'Unable to validate this direct conversation.',
      );
    }

    await _onOpenConversation(
      MessageConversationEntry(
        conversation: conversation,
        currentUserUid: currentUid,
        source: request.source,
      ),
    );

    return MessageEntryResult.openedConversation(request, conversation);
  }

  void _validateConversationAccess({
    required ConversationEntity conversation,
    required String currentUid,
  }) {
    final String conversationId = conversation.id.trim();

    if (conversationId.isEmpty) {
      throw const MessageEntryException('Conversation is unavailable.');
    }

    final bool containsCurrentUser = conversation.participantUids.any(
      (String participantUid) => participantUid.trim() == currentUid,
    );

    if (!containsCurrentUser) {
      throw const MessageEntryException(
        'You do not have access to this conversation.',
      );
    }
  }

  String? _authenticatedUid() {
    final String normalized = _currentUidProvider()?.trim() ?? '';

    return normalized.isEmpty ? null : normalized;
  }

  String _entryOperationKey(MessageEntryRequest request) {
    final String uid = _authenticatedUid() ?? 'guest';

    return '$uid::${request.operationKey}';
  }

  String _requiredId(
    String? value, {
    required String fieldName,
    required String safeMessage,
  }) {
    final String normalized = value?.trim() ?? '';

    if (normalized.isEmpty) {
      throw MessageEntryException(safeMessage);
    }

    if (_looksLikeUnsupportedPublicIdentity(normalized, fieldName: fieldName)) {
      throw const MessageEntryException(
        'A Firebase user identity is required for this Message action.',
      );
    }

    return normalized;
  }

  bool _looksLikeUnsupportedPublicIdentity(
    String value, {
    required String fieldName,
  }) {
    if (fieldName != 'peerUid') {
      return false;
    }

    final String normalized = value.trim();

    return normalized.contains('@') || normalized.startsWith('+');
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('MessageEntryService has already been disposed.');
    }
  }

  /// Releases only this integration service's operation bookkeeping.
  ///
  /// It intentionally does NOT dispose shared repositories/navigation/auth
  /// services that it does not own.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _activeEntries.clear();
  }
}

// ============================================================================
// END OF FILE:
// lib/services/message/message_entry_service.dart
// ============================================================================
