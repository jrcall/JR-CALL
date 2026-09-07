// ============================================================================
// JR CALL
// File: message_integration_service.dart
// Location: lib/services/message/message_integration_service.dart
// Description:
// Application-level composition bridge between existing JR CALL app actions
// and the finalized Message feature.
//
// Owns:
// - Authenticated Firebase UID validation at Message composition boundary.
// - ConversationRepository / MessageRepository ownership references.
// - ConversationController creation.
// - MessageController creation.
// - MessageComposerController creation.
// - MessageEntryService creation.
// - Stable per-conversation controller lifecycle.
// - Shared Message feature reset/disposal coordination.
// - Guest-safe integration boundary.
//
// Does NOT:
// - Call Firestore directly.
// - Call Firebase Storage directly.
// - Parse FCM payloads.
// - Search JR CALL users.
// - Replace UserDiscoveryService.
// - Create Firebase Auth credentials.
// - Use public JR CALL ID/username/email/phone as internal identity.
// - Recreate Message Engine.
// - Recreate Call Engine/WebRTC.
// - Own Navigator/BuildContext.
// ============================================================================

import '../../features/message/controller/conversation_controller.dart';
import '../../features/message/controller/message_composer_controller.dart';
import '../../features/message/controller/message_controller.dart';
import '../../features/message/repository/conversation_repository.dart';
import '../../features/message/repository/message_repository.dart';
import 'message_entry_service.dart';

/// Supplies the current canonical Firebase Auth UID.
///
/// Existing AuthService/Firebase session remains the authentication owner.
/// A null or blank value means the current app session is a guest session.
typedef MessageIntegrationUidProvider = String? Function();

/// Creates a MessageController for one authenticated conversation.
///
/// This factory boundary keeps the integration service independent from any
/// future composition-root dependencies required by MessageController.
typedef MessageControllerFactory =
    MessageController Function({
      required MessageRepository repository,
      required String conversationId,
      required String currentUserUid,
    });

/// Creates a MessageComposerController for one authenticated conversation.
typedef MessageComposerControllerFactory =
    MessageComposerController Function({
      required MessageComposerDelegate delegate,
      required String conversationId,
      required String currentUserUid,
    });

/// Creates the authenticated inbox controller.
typedef ConversationControllerFactory =
    ConversationController Function({
      required ConversationRepository repository,
      required String currentUserUid,
    });

/// Complete controller bundle for one chat screen.
///
/// The bundle owns only controllers created specifically for this conversation.
/// Shared repositories/services are not disposed by this object.
final class MessageConversationControllers {
  MessageConversationControllers({
    required this.messageController,
    required this.composerController,
    required this.conversationId,
    required this.currentUserUid,
  });

  final MessageController messageController;
  final MessageComposerController composerController;
  final String conversationId;
  final String currentUserUid;

  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Disposes only conversation-scoped controllers.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    messageController.dispose();
    composerController.dispose();
  }
}

/// Safe integration-layer exception.
///
/// Raw Firebase exception messages must not be surfaced through this type.
final class MessageIntegrationException implements Exception {
  const MessageIntegrationException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() {
    return 'MessageIntegrationException: $safeMessage';
  }
}

/// JR CALL Message application integration service.
///
/// This class is the application-side composition bridge:
///
/// Existing JR CALL application
///   -> MessageIntegrationService
///   -> MessageEntryService / repositories
///   -> Message controllers
///   -> finalized Message presentation
///
/// Firebase UID remains the canonical internal identity throughout.
final class MessageIntegrationService {
  /// Public production constructor.
  ///
  /// Public parameter names remain unchanged so existing JR CALL composition
  /// code does not break. Internal field assignment is delegated to the
  /// initializing-formal constructor below.
  factory MessageIntegrationService({
    required MessageRepository messageRepository,
    required ConversationRepository conversationRepository,
    required MessageIntegrationUidProvider currentUidProvider,
    required MessageAuthenticationRequiredHandler onAuthenticationRequired,
    required MessageConversationOpenHandler onOpenConversation,
    required MessageInboxOpenHandler onOpenInbox,
    MessageControllerFactory? messageControllerFactory,
    MessageComposerControllerFactory? composerControllerFactory,
    ConversationControllerFactory? conversationControllerFactory,
  }) {
    return MessageIntegrationService._(
      messageRepository,
      conversationRepository,
      currentUidProvider,
      messageControllerFactory ?? _defaultMessageControllerFactory,
      composerControllerFactory ?? _defaultComposerControllerFactory,
      conversationControllerFactory ?? _defaultConversationControllerFactory,
      onAuthenticationRequired,
      onOpenConversation,
      onOpenInbox,
    );
  }

  MessageIntegrationService._(
    this._messageRepository,
    this._conversationRepository,
    this._currentUidProvider,
    this._messageControllerFactory,
    this._composerControllerFactory,
    this._conversationControllerFactory,
    MessageAuthenticationRequiredHandler onAuthenticationRequired,
    MessageConversationOpenHandler onOpenConversation,
    MessageInboxOpenHandler onOpenInbox,
  ) {
    _entryService = MessageEntryService(
      conversationRepository: _conversationRepository,
      currentUidProvider: _currentUidProvider,
      onAuthenticationRequired: onAuthenticationRequired,
      onOpenConversation: onOpenConversation,
      onOpenInbox: onOpenInbox,
    );
  }

  final MessageRepository _messageRepository;
  final ConversationRepository _conversationRepository;
  final MessageIntegrationUidProvider _currentUidProvider;

  final MessageControllerFactory _messageControllerFactory;
  final MessageComposerControllerFactory _composerControllerFactory;
  final ConversationControllerFactory _conversationControllerFactory;

  late final MessageEntryService _entryService;

  ConversationController? _conversationController;

  final Map<String, MessageConversationControllers> _conversationControllers =
      <String, MessageConversationControllers>{};

  final Map<String, Future<MessageConversationControllers>>
  _activeConversationControllerCreations =
      <String, Future<MessageConversationControllers>>{};

  bool _disposed = false;

  /// Application-level Message entry service.
  MessageEntryService get entryService {
    _ensureActive();
    return _entryService;
  }

  /// Shared durable-message repository.
  MessageRepository get messageRepository {
    _ensureActive();
    return _messageRepository;
  }

  /// Shared conversation-domain repository.
  ConversationRepository get conversationRepository {
    _ensureActive();
    return _conversationRepository;
  }

  bool get isDisposed => _disposed;

  /// Returns whether the application currently has an authenticated Firebase
  /// UID available for protected Message operations.
  bool get isAuthenticated {
    if (_disposed) {
      return false;
    }

    return _normalizedCurrentUid() != null;
  }

  /// Current canonical Firebase UID, or null for guest session.
  String? get currentUserUid {
    if (_disposed) {
      return null;
    }

    return _normalizedCurrentUid();
  }

  /// Returns the authenticated inbox controller.
  ///
  /// One controller is retained for the current authenticated UID. If the
  /// authenticated Firebase UID changes, the old controller is disposed and
  /// a new one is created for the new session.
  ConversationController getOrCreateConversationController() {
    _ensureActive();

    final String uid = _requireAuthenticatedUid();
    final ConversationController? existing = _conversationController;

    if (existing != null) {
      if (!existing.isDisposed && existing.currentUserUid == uid) {
        return existing;
      }

      existing.dispose();
      _conversationController = null;
    }

    final ConversationController controller = _conversationControllerFactory(
      repository: _conversationRepository,
      currentUserUid: uid,
    );

    _conversationController = controller;

    return controller;
  }

  /// Returns a chat-screen controller bundle for one canonical conversation.
  ///
  /// A single live bundle is retained for:
  ///
  /// authenticatedUid + conversationId
  ///
  /// Rapid duplicate requests share the same creation operation.
  Future<MessageConversationControllers> getOrCreateConversationControllers({
    required String conversationId,
  }) {
    _ensureActive();

    final String uid = _requireAuthenticatedUid();

    final String normalizedConversationId = _requiredId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String key = _conversationControllerKey(
      currentUserUid: uid,
      conversationId: normalizedConversationId,
    );

    final MessageConversationControllers? existing =
        _conversationControllers[key];

    if (existing != null && !existing.isDisposed) {
      return Future<MessageConversationControllers>.value(existing);
    }

    final Future<MessageConversationControllers>? activeCreation =
        _activeConversationControllerCreations[key];

    if (activeCreation != null) {
      return activeCreation;
    }

    final Future<MessageConversationControllers> operation =
        _createConversationControllers(
          currentUserUid: uid,
          conversationId: normalizedConversationId,
        );

    _activeConversationControllerCreations[key] = operation;

    operation.whenComplete(() {
      if (identical(_activeConversationControllerCreations[key], operation)) {
        _activeConversationControllerCreations.remove(key);
      }
    });

    return operation;
  }

  Future<MessageConversationControllers> _createConversationControllers({
    required String currentUserUid,
    required String conversationId,
  }) async {
    _ensureActive();

    final bool isParticipant = await _conversationRepository.isParticipant(
      conversationId: conversationId,
      requesterUid: currentUserUid,
    );

    if (_disposed) {
      throw const MessageIntegrationException(
        'Messages are no longer available.',
      );
    }

    final String? activeUid = _normalizedCurrentUid();

    if (activeUid == null || activeUid != currentUserUid) {
      throw const MessageIntegrationException(
        'The authenticated Message session has changed.',
      );
    }

    if (!isParticipant) {
      throw const MessageIntegrationException(
        'You do not have access to this conversation.',
      );
    }

    final String key = _conversationControllerKey(
      currentUserUid: currentUserUid,
      conversationId: conversationId,
    );

    final MessageConversationControllers? existing =
        _conversationControllers[key];

    if (existing != null && !existing.isDisposed) {
      return existing;
    }

    final MessageController messageController = _messageControllerFactory(
      repository: _messageRepository,
      conversationId: conversationId,
      currentUserUid: currentUserUid,
    );

    MessageComposerController? composerController;

    try {
      composerController = _composerControllerFactory(
        delegate: _messageRepository,
        conversationId: conversationId,
        currentUserUid: currentUserUid,
      );

      final MessageConversationControllers controllers =
          MessageConversationControllers(
            messageController: messageController,
            composerController: composerController,
            conversationId: conversationId,
            currentUserUid: currentUserUid,
          );

      if (_disposed) {
        controllers.dispose();

        throw const MessageIntegrationException(
          'Messages are no longer available.',
        );
      }

      final String? currentUidAfterCreation = _normalizedCurrentUid();

      if (currentUidAfterCreation == null ||
          currentUidAfterCreation != currentUserUid) {
        controllers.dispose();

        throw const MessageIntegrationException(
          'The authenticated Message session has changed.',
        );
      }

      _conversationControllers[key] = controllers;

      return controllers;
    } catch (_) {
      messageController.dispose();
      composerController?.dispose();
      rethrow;
    }
  }

  /// Opens the main Message destination through MessageEntryService.
  Future<MessageEntryResult> openInbox({
    MessageEntrySource source = MessageEntrySource.home,
  }) {
    _ensureActive();

    return _entryService.openInbox(source: source);
  }

  /// Opens an already-known canonical conversation.
  Future<MessageEntryResult> openConversation({
    required String conversationId,
    MessageEntrySource source = MessageEntrySource.inbox,
  }) {
    _ensureActive();

    return _entryService.openConversation(
      conversationId: conversationId,
      source: source,
    );
  }

  /// Opens/finds/creates a direct chat from an already-resolved Firebase UID.
  ///
  /// Name, username, JR CALL public ID, phone and email must first be resolved
  /// by the existing UserDiscoveryService. Only the resulting Firebase UID is
  /// accepted here.
  Future<MessageEntryResult> openDirectPeer({
    required String peerUid,
    MessageEntrySource source = MessageEntrySource.discovery,
  }) {
    _ensureActive();

    return _entryService.openDirectPeer(peerUid: peerUid, source: source);
  }

  /// Releases one chat-screen controller bundle.
  ///
  /// Use this when the owning conversation screen/application integration
  /// explicitly ends that scoped controller lifecycle.
  void releaseConversationControllers({required String conversationId}) {
    if (_disposed) {
      return;
    }

    final String? uid = _normalizedCurrentUid();

    if (uid == null) {
      _releaseConversationIdAcrossSessions(conversationId);
      return;
    }

    final String normalizedConversationId = conversationId.trim();

    if (normalizedConversationId.isEmpty) {
      return;
    }

    final String key = _conversationControllerKey(
      currentUserUid: uid,
      conversationId: normalizedConversationId,
    );

    final MessageConversationControllers? controllers = _conversationControllers
        .remove(key);

    controllers?.dispose();

    _messageRepository.releaseTimeline(
      conversationId: normalizedConversationId,
      requesterUid: uid,
    );
  }

  /// Clears all conversation-scoped Message controllers.
  ///
  /// Shared repositories remain alive because they are application/domain
  /// dependencies and may have owners outside this integration service.
  void releaseAllConversationControllers() {
    if (_disposed) {
      return;
    }

    final List<MessageConversationControllers> controllers =
        _conversationControllers.values.toList(growable: false);

    _conversationControllers.clear();
    _activeConversationControllerCreations.clear();

    for (final MessageConversationControllers item in controllers) {
      item.dispose();
    }

    _messageRepository.clearTimelineCache();
  }

  /// Resets Message UI/controller state after authentication-session change.
  ///
  /// Call this when the Firebase authenticated UID changes or the user signs
  /// out. Shared Message repositories remain application-owned.
  void resetSession() {
    if (_disposed) {
      return;
    }

    final ConversationController? inboxController = _conversationController;

    _conversationController = null;

    inboxController?.dispose();

    final List<MessageConversationControllers> controllers =
        _conversationControllers.values.toList(growable: false);

    _conversationControllers.clear();
    _activeConversationControllerCreations.clear();

    for (final MessageConversationControllers item in controllers) {
      item.dispose();
    }

    _messageRepository.clearTimelineCache();
    _conversationRepository.clearListenerCache();
  }

  void _releaseConversationIdAcrossSessions(String conversationId) {
    final String normalizedConversationId = conversationId.trim();

    if (normalizedConversationId.isEmpty) {
      return;
    }

    final List<String> matchingKeys = _conversationControllers.entries
        .where(
          (MapEntry<String, MessageConversationControllers> entry) =>
              entry.value.conversationId == normalizedConversationId,
        )
        .map(
          (MapEntry<String, MessageConversationControllers> entry) => entry.key,
        )
        .toList(growable: false);

    for (final String key in matchingKeys) {
      final MessageConversationControllers? controllers =
          _conversationControllers.remove(key);

      if (controllers == null) {
        continue;
      }

      controllers.dispose();

      _messageRepository.releaseTimeline(
        conversationId: controllers.conversationId,
        requesterUid: controllers.currentUserUid,
      );
    }
  }

  String _requireAuthenticatedUid() {
    final String? uid = _normalizedCurrentUid();

    if (uid == null) {
      throw const MessageIntegrationException(
        'Login is required to use Messages.',
      );
    }

    return uid;
  }

  String? _normalizedCurrentUid() {
    final String normalized = _currentUidProvider()?.trim() ?? '';

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  String _requiredId(String value, {required String fieldName}) {
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

  String _conversationControllerKey({
    required String currentUserUid,
    required String conversationId,
  }) {
    return '$currentUserUid::$conversationId';
  }

  static MessageController _defaultMessageControllerFactory({
    required MessageRepository repository,
    required String conversationId,
    required String currentUserUid,
  }) {
    return MessageController(
      repository: repository,
      conversationId: conversationId,
      currentUserUid: currentUserUid,
    );
  }

  static MessageComposerController _defaultComposerControllerFactory({
    required MessageComposerDelegate delegate,
    required String conversationId,
    required String currentUserUid,
  }) {
    return MessageComposerController(
      delegate: delegate,
      currentUserUid: currentUserUid,
      conversationId: conversationId,
    );
  }

  static ConversationController _defaultConversationControllerFactory({
    required ConversationRepository repository,
    required String currentUserUid,
  }) {
    return ConversationController(
      repository: repository,
      currentUserUid: currentUserUid,
    );
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('MessageIntegrationService has already been disposed.');
    }
  }

  /// Disposes resources owned specifically by this integration service.
  ///
  /// Shared MessageRepository and ConversationRepository are deliberately NOT
  /// disposed here because their lifetime belongs to the application
  /// composition root unless that root explicitly owns and disposes them.
  void dispose() {
    if (_disposed) {
      return;
    }

    final ConversationController? inboxController = _conversationController;

    _conversationController = null;

    inboxController?.dispose();

    final List<MessageConversationControllers> controllers =
        _conversationControllers.values.toList(growable: false);

    _conversationControllers.clear();
    _activeConversationControllerCreations.clear();

    for (final MessageConversationControllers item in controllers) {
      item.dispose();
    }

    _entryService.dispose();

    _disposed = true;
  }
}

// ============================================================================
// END OF FILE:
// lib/services/message/message_integration_service.dart
// ============================================================================
