// ============================================================================
// JR CALL
// File: message_app_coordinator.dart
// Location: lib/services/message/message_app_coordinator.dart
// Description:
// Production Message application composition coordinator.
//
// PURPOSE:
// - Single application-level boundary for the finalized JR CALL Message system.
// - Keeps main.dart / HomeScreen / ContactsScreen / ProfileScreen small.
// - Composes finalized Message repositories/integration/navigation/push.
// - Uses Firebase Auth UID as the only canonical internal user identity.
//
// IMPORTANT:
// - Frozen Message FILES 01-48 remain unchanged.
// - MessageNavigationService remains Message navigation owner.
// - MessageIntegrationService remains Message integration/controller owner.
// - MessagePushService remains strict Message push classifier/router.
// - MessageEntryService remains authenticated repository-aware entry owner.
// - Existing AuthService remains authentication/session owner.
// - Existing UserDiscoveryService remains search/discovery owner.
// - Existing Call routing/WebRTC remains completely separate.
// ============================================================================

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../features/message/repository/conversation_repository.dart';
import '../../features/message/repository/message_repository.dart';
import '../auth_service.dart';
import 'message_entry_service.dart';
import 'message_integration_service.dart';
import 'message_navigation_service.dart';
import 'message_push_service.dart';

// ============================================================================
// REPOSITORY COMPOSITION BOUNDARY
// ============================================================================

/// Final Message repositories required by the application integration layer.
///
/// Their lower-level finalized dependency graph may contain:
///
/// - JrMessageEngine
/// - MessageDatabase
/// - MessageRemoteStore
/// - MessageMediaStore
/// - MessageCacheStore
/// - realtime listeners
/// - MediaUploadManager
///
/// FILE 49 deliberately does not guess or duplicate those constructors.
@immutable
final class MessageAppRepositories {
  const MessageAppRepositories({
    required this.messageRepository,
    required this.conversationRepository,
    this.ownsMessageRepository = false,
    this.ownsConversationRepository = false,
  });

  final MessageRepository messageRepository;
  final ConversationRepository conversationRepository;

  /// True only when this coordinator owns the repository lifecycle.
  final bool ownsMessageRepository;

  /// True only when this coordinator owns the repository lifecycle.
  final bool ownsConversationRepository;
}

/// Supplies the finalized Message repository graph.
///
/// Rapid duplicate initialization calls never invoke this factory twice for
/// the same active coordinator initialization.
typedef MessageAppRepositoryFactory =
    FutureOr<MessageAppRepositories> Function();

// ============================================================================
// APPLICATION PAGE BUILDERS
// ============================================================================

/// Builds the finalized Message inbox destination.
typedef MessageAppInboxPageBuilder =
    Widget Function(
      BuildContext context,
      MessageIntegrationService integrationService,
    );

/// Builds the finalized New Chat destination.
///
/// Existing UserDiscoveryService remains the actual search owner.
typedef MessageAppNewChatPageBuilder =
    Widget Function(
      BuildContext context,
      MessageIntegrationService integrationService,
    );

/// Builds the finalized ChatScreen for one canonical conversation ID.
typedef MessageAppConversationPageBuilder =
    Widget Function(
      BuildContext context,
      String conversationId,
      MessageIntegrationService integrationService,
    );

// ============================================================================
// SAFE COORDINATOR ERROR
// ============================================================================

final class MessageAppCoordinatorException implements Exception {
  const MessageAppCoordinatorException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => 'MessageAppCoordinatorException: $safeMessage';
}

// ============================================================================
// MESSAGE APP COORDINATOR
// ============================================================================

/// Single JR CALL application-level Message composition coordinator.
///
/// Architecture:
///
/// Shared JR CALL application
///         |
///         v
/// MessageAppCoordinator
///         |
///         +--> MessageNavigationService
///         +--> MessageIntegrationService
///         +--> MessageEntryService
///         +--> MessagePushService
///         |
///         v
/// Frozen Message feature FILES 01-48
///
/// This coordinator does NOT:
///
/// - initialize Firebase
/// - create Firebase Auth credentials
/// - implement OTP
/// - search users
/// - own raw Firestore Message paths
/// - upload directly to Firebase Storage
/// - register global FirebaseMessaging listeners
/// - implement Call push classification
/// - create CallService
/// - create WebRTC / SDP / ICE / STUN / TURN
/// - render Message UI
final class MessageAppCoordinator {
  factory MessageAppCoordinator({
    required GlobalKey<NavigatorState> navigatorKey,
    required MessageAppRepositoryFactory repositoryFactory,
    required MessageAppInboxPageBuilder inboxBuilder,
    required MessageAppNewChatPageBuilder newChatBuilder,
    required MessageAppConversationPageBuilder conversationBuilder,
    required MessageAuthenticationPageBuilder authenticationBuilder,
    required MessageAuthenticationRequiredHandler onAuthenticationRequired,
    MessageNavigationObserver? navigationObserver,
    int maximumRememberedPushes = 128,
  }) {
    if (maximumRememberedPushes <= 0) {
      throw ArgumentError.value(
        maximumRememberedPushes,
        'maximumRememberedPushes',
        'maximumRememberedPushes must be greater than zero.',
      );
    }

    return MessageAppCoordinator._(
      navigatorKey,
      repositoryFactory,
      inboxBuilder,
      newChatBuilder,
      conversationBuilder,
      authenticationBuilder,
      onAuthenticationRequired,
      navigationObserver,
      maximumRememberedPushes,
    );
  }

  /// Private initializing-formal constructor.
  ///
  /// Keeps the public factory API unchanged while satisfying
  /// prefer_initializing_formals.
  MessageAppCoordinator._(
    this._navigatorKey,
    this._repositoryFactory,
    this._inboxBuilder,
    this._newChatBuilder,
    this._conversationBuilder,
    this._authenticationBuilder,
    this._onAuthenticationRequired,
    this._navigationObserver,
    this._maximumRememberedPushes,
  );

  // ==========================================================================
  // APPLICATION DEPENDENCIES
  // ==========================================================================

  final GlobalKey<NavigatorState> _navigatorKey;

  final MessageAppRepositoryFactory _repositoryFactory;

  final MessageAppInboxPageBuilder _inboxBuilder;

  final MessageAppNewChatPageBuilder _newChatBuilder;

  final MessageAppConversationPageBuilder _conversationBuilder;

  final MessageAuthenticationPageBuilder _authenticationBuilder;

  final MessageAuthenticationRequiredHandler _onAuthenticationRequired;

  final MessageNavigationObserver? _navigationObserver;

  final int _maximumRememberedPushes;

  // ==========================================================================
  // MESSAGE GRAPH
  // ==========================================================================

  MessageAppRepositories? _repositories;

  MessageNavigationService? _navigationService;

  MessageIntegrationService? _integrationService;

  MessagePushService? _pushService;

  // ==========================================================================
  // SESSION / LIFECYCLE
  // ==========================================================================

  StreamSubscription<User?>? _authSubscription;

  Future<void>? _initializationFuture;

  Future<void>? _disposeFuture;

  bool _initialized = false;

  bool _disposed = false;

  String? _lastAuthenticatedUid;

  // ==========================================================================
  // PUBLIC STATE
  // ==========================================================================

  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  bool get isInitialized => _initialized && !_disposed;

  bool get isDisposed => _disposed;

  bool get isAuthenticated => !_disposed && _currentUserUid != null;

  String? get currentUserUid {
    if (_disposed) {
      return null;
    }

    return _currentUserUid;
  }

  // ==========================================================================
  // INITIALIZATION
  // ==========================================================================

  /// Initializes the Message application composition exactly once.
  ///
  /// Guarantees:
  /// - idempotent
  /// - concurrency-safe
  /// - one repository graph
  /// - one MessageNavigationService
  /// - one MessageIntegrationService
  /// - one MessagePushService
  /// - one authentication-state subscription
  /// - no FirebaseMessaging listener registration
  /// - no Call Engine ownership
  Future<void> initialize() {
    _ensureNotDisposed();

    if (_initialized) {
      return Future<void>.value();
    }

    final Future<void>? activeInitialization = _initializationFuture;

    if (activeInitialization != null) {
      return activeInitialization;
    }

    final Future<void> operation = _initializeInternal();

    _initializationFuture = operation;

    unawaited(
      operation.whenComplete(() {
        if (identical(_initializationFuture, operation)) {
          _initializationFuture = null;
        }
      }),
    );

    return operation;
  }

  Future<void> _initializeInternal() async {
    MessageAppRepositories? repositories;
    MessageNavigationService? navigationService;
    MessageIntegrationService? integrationService;
    MessagePushService? pushService;
    StreamSubscription<User?>? authSubscription;

    bool repositoriesReleased = false;

    try {
      repositories = await _repositoryFactory();

      if (_disposed) {
        await _disposeOwnedRepositories(repositories);
        repositoriesReleased = true;

        throw const MessageAppCoordinatorException(
          'Messages are no longer available.',
        );
      }

      // ======================================================================
      // NAVIGATION
      // ======================================================================

      final MessageNavigationService createdNavigationService =
          MessageNavigationService(
            navigatorKey: _navigatorKey,
            currentUidProvider: _readCurrentUid,
            inboxBuilder: (BuildContext context) {
              return _inboxBuilder(context, _requireIntegrationService());
            },
            newChatBuilder: (BuildContext context) {
              return _newChatBuilder(context, _requireIntegrationService());
            },
            conversationBuilder: (BuildContext context, String conversationId) {
              return _conversationBuilder(
                context,
                conversationId,
                _requireIntegrationService(),
              );
            },
            authenticationBuilder: _authenticationBuilder,
            observer: _navigationObserver,
          );

      navigationService = createdNavigationService;
      _navigationService = createdNavigationService;

      // ======================================================================
      // INTEGRATION / ENTRY
      // ======================================================================

      final MessageIntegrationService createdIntegrationService =
          MessageIntegrationService(
            messageRepository: repositories.messageRepository,
            conversationRepository: repositories.conversationRepository,
            currentUidProvider: _readCurrentUid,
            onAuthenticationRequired: _onAuthenticationRequired,

            // MessageConversationOpenHandler is FutureOr<void>.
            // Await the typed navigation result instead of returning a
            // Future<MessageNavigationResult> through a void boundary.
            onOpenConversation: (MessageConversationEntry entry) async {
              await createdNavigationService.openConversation(
                conversationId: entry.conversationId,
                source: _navigationSourceFromEntry(entry.source),
              );
            },

            // MessageInboxOpenHandler is FutureOr<void>.
            onOpenInbox: () async {
              await createdNavigationService.openInbox(
                source: MessageNavigationSource.internal,
              );
            },
          );

      integrationService = createdIntegrationService;
      _integrationService = createdIntegrationService;

      // ======================================================================
      // PUSH
      // ======================================================================

      final MessagePushService createdPushService = MessagePushService(
        navigationService: createdNavigationService,
        maximumRememberedPushes: _maximumRememberedPushes,
      );

      pushService = createdPushService;
      _pushService = createdPushService;

      // ======================================================================
      // AUTHENTICATION SESSION
      // ======================================================================

      _lastAuthenticatedUid = _currentUserUid;

      authSubscription = AuthService.instance.authStateChanges.listen(
        _handleAuthenticationStateChanged,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            'JR CALL [MessageAppCoordinator/auth-session] '
            'authentication session stream interrupted.',
          );

          debugPrintStack(
            label: 'JR CALL [MessageAppCoordinator/auth-session]',
            stackTrace: stackTrace,
          );
        },
      );

      if (_disposed) {
        await authSubscription.cancel();

        createdPushService.dispose();
        createdIntegrationService.dispose();
        createdNavigationService.dispose();

        _pushService = null;
        _integrationService = null;
        _navigationService = null;

        await _disposeOwnedRepositories(repositories);
        repositoriesReleased = true;

        throw const MessageAppCoordinatorException(
          'Messages are no longer available.',
        );
      }

      _repositories = repositories;
      _authSubscription = authSubscription;

      _initialized = true;
    } catch (error, stackTrace) {
      if (!_initialized) {
        if (authSubscription != null) {
          await authSubscription.cancel();
        }

        pushService?.dispose();
        integrationService?.dispose();
        navigationService?.dispose();

        _pushService = null;
        _integrationService = null;
        _navigationService = null;
        _authSubscription = null;

        if (repositories != null &&
            !repositoriesReleased &&
            !identical(_repositories, repositories)) {
          await _disposeOwnedRepositories(repositories);
        }
      }

      debugPrint(
        'JR CALL [MessageAppCoordinator/initialize] '
        'Message composition initialization failed.',
      );

      debugPrintStack(
        label: 'JR CALL [MessageAppCoordinator/initialize]',
        stackTrace: stackTrace,
      );

      rethrow;
    }
  }

  // ==========================================================================
  // MESSAGE INBOX
  // ==========================================================================

  /// Opens the protected Message inbox.
  ///
  /// Guest protection and pending authentication navigation remain owned by
  /// MessageNavigationService.
  Future<MessageNavigationResult> openMessageInbox({
    MessageNavigationSource source = MessageNavigationSource.home,
  }) async {
    await _ensureReady();

    return _requireNavigationService().openInbox(source: source);
  }

  // ==========================================================================
  // NEW CHAT
  // ==========================================================================

  /// Opens the finalized New Chat flow.
  ///
  /// User search remains owned by existing UserDiscoveryService.
  Future<MessageNavigationResult> openNewChat({
    MessageNavigationSource source = MessageNavigationSource.inbox,
  }) async {
    await _ensureReady();

    return _requireNavigationService().openNewChat(source: source);
  }

  // ==========================================================================
  // EXISTING CONVERSATION NAVIGATION
  // ==========================================================================

  /// Opens one already-known canonical Message conversation ID.
  Future<MessageNavigationResult> openConversation({
    required String conversationId,
    MessageNavigationSource source = MessageNavigationSource.internal,
  }) async {
    await _ensureReady();

    final String normalizedConversationId = _requiredId(
      conversationId,
      fieldName: 'conversationId',
    );

    return _requireNavigationService().openConversation(
      conversationId: normalizedConversationId,
      source: source,
    );
  }

  // ==========================================================================
  // DIRECT FIREBASE UID ENTRY
  // ==========================================================================

  /// Finds/creates and opens a direct conversation for an already-resolved
  /// Firebase Auth UID.
  ///
  /// Name / username / JR CALL ID / email / phone must first be resolved by
  /// existing UserDiscoveryService.
  Future<MessageEntryResult> openDirectPeer({
    required String peerUid,
    MessageEntrySource source = MessageEntrySource.discovery,
  }) async {
    await _ensureReady();

    final String normalizedPeerUid = _requiredId(peerUid, fieldName: 'peerUid');

    final MessageIntegrationService integration = _requireIntegrationService();

    final MessageEntryResult result = await integration.openDirectPeer(
      peerUid: normalizedPeerUid,
      source: source,
    );

    // MessageEntryService may return authenticationRequired after invoking
    // the supplied application auth flow.
    //
    // If authentication genuinely completed before the callback returned,
    // retry the exact same Firebase UID operation once.
    if (result.status == MessageEntryStatus.authenticationRequired &&
        _currentUserUid != null &&
        !_disposed) {
      return integration.openDirectPeer(
        peerUid: normalizedPeerUid,
        source: source,
      );
    }

    return result;
  }

  // ==========================================================================
  // REPOSITORY-AWARE ENTRY
  // ==========================================================================

  /// Opens the Message inbox through MessageIntegrationService /
  /// MessageEntryService.
  Future<MessageEntryResult> enterMessageInbox({
    MessageEntrySource source = MessageEntrySource.home,
  }) async {
    await _ensureReady();

    return _requireIntegrationService().openInbox(source: source);
  }

  /// Validates and opens one existing canonical conversation through
  /// MessageEntryService.
  Future<MessageEntryResult> enterConversation({
    required String conversationId,
    MessageEntrySource source = MessageEntrySource.inbox,
  }) async {
    await _ensureReady();

    final String normalizedConversationId = _requiredId(
      conversationId,
      fieldName: 'conversationId',
    );

    return _requireIntegrationService().openConversation(
      conversationId: normalizedConversationId,
      source: source,
    );
  }

  // ==========================================================================
  // MESSAGE PUSH CLASSIFICATION
  // ==========================================================================

  /// Uses the frozen MessagePushService classifier.
  ///
  /// CALL classification rules are NOT duplicated here.
  MessagePushClassification classifyMessagePush(Map<String, Object?> data) {
    _ensureReadySync();

    return _requirePushService().classify(data);
  }

  /// True only for an explicit valid Message payload.
  bool isMessagePush(Map<String, Object?> data) {
    _ensureReadySync();

    return _requirePushService().isMessagePayload(data);
  }

  /// Parses an explicit valid Message push without navigating.
  MessagePushPayload? parseMessagePush(
    Map<String, Object?> data, {
    MessagePushSource source = MessagePushSource.internal,
  }) {
    _ensureReadySync();

    return _requirePushService().parse(data, source: source);
  }

  // ==========================================================================
  // MESSAGE PUSH HANDOFF
  // ==========================================================================

  /// Processes a Message push through the finalized MessagePushService.
  ///
  /// main.dart remains FirebaseMessaging lifecycle owner.
  ///
  /// Receiving an FCM payload here does NOT mark a durable message delivered
  /// or read.
  Future<MessagePushHandlingResult> handleMessagePush(
    Map<String, Object?> data, {
    required MessagePushSource source,
    bool openConversation = false,
  }) async {
    await _ensureReady();

    return _requirePushService().handle(
      data,
      source: source,
      openConversation: openConversation,
    );
  }

  /// Handles an actual Message notification-open event.
  Future<MessagePushHandlingResult> openMessagePush(
    Map<String, Object?> data, {
    MessagePushSource source = MessagePushSource.notificationTap,
  }) async {
    await _ensureReady();

    return _requirePushService().open(data, source: source);
  }

  // ==========================================================================
  // PENDING AUTH NAVIGATION
  // ==========================================================================

  /// Resumes the protected Message destination retained by
  /// MessageNavigationService after a genuine Firebase user becomes available.
  Future<MessageNavigationResult?>
  resumePendingMessageNavigationAfterAuthentication() async {
    await _ensureReady();

    return _requireNavigationService().resumePendingAfterAuthentication();
  }

  /// Clears only pending Message authentication navigation.
  void clearPendingMessageNavigation() {
    _ensureReadySync();

    _requireNavigationService().clearPendingAuthenticationNavigation();
  }

  // ==========================================================================
  // SESSION RESET
  // ==========================================================================

  /// Clears Message session-scoped state without touching durable Firestore
  /// messages or Call Engine state.
  void resetSession() {
    _ensureReadySync();

    _requireIntegrationService().resetSession();

    _requireNavigationService().resetSession();

    _requirePushService().clearHandledPushes();

    _lastAuthenticatedUid = _currentUserUid;
  }

  void _handleAuthenticationStateChanged(User? user) {
    if (_disposed || !_initialized) {
      return;
    }

    final String? newUid = _normalizeUid(user?.uid);

    final String? previousUid = _lastAuthenticatedUid;

    if (newUid == previousUid) {
      return;
    }

    _lastAuthenticatedUid = newUid;

    final MessageIntegrationService? integration = _integrationService;

    final MessageNavigationService? navigation = _navigationService;

    final MessagePushService? push = _pushService;

    // Always remove old conversation/controller/cache state when Firebase UID
    // changes.
    integration?.resetSession();

    // Push dedupe state belongs to the old authenticated session.
    push?.clearHandledPushes();

    // Guest -> authenticated:
    //
    // Keep MessageNavigationService pending state intact because it may contain
    // the protected destination that must resume after successful login.
    //
    // Authenticated -> guest OR account A -> account B:
    //
    // Clear old navigation/session identity completely.
    if (previousUid != null && previousUid != newUid) {
      navigation?.resetSession();
    }
  }

  // ==========================================================================
  // SERVICE ACCESS
  // ==========================================================================

  MessageNavigationService _requireNavigationService() {
    final MessageNavigationService? service = _navigationService;

    if (service == null || service.isDisposed) {
      throw const MessageAppCoordinatorException(
        'Message navigation is unavailable.',
      );
    }

    return service;
  }

  MessageIntegrationService _requireIntegrationService() {
    final MessageIntegrationService? service = _integrationService;

    if (service == null || service.isDisposed) {
      throw const MessageAppCoordinatorException(
        'Message integration is unavailable.',
      );
    }

    return service;
  }

  MessagePushService _requirePushService() {
    final MessagePushService? service = _pushService;

    if (service == null || service.isDisposed) {
      throw const MessageAppCoordinatorException(
        'Message notifications are unavailable.',
      );
    }

    return service;
  }

  // ==========================================================================
  // FIREBASE UID
  // ==========================================================================

  /// Existing AuthService / Firebase session is the only identity source.
  String? _readCurrentUid() {
    return _currentUserUid;
  }

  String? get _currentUserUid {
    return _normalizeUid(AuthService.instance.currentUserId);
  }

  static String? _normalizeUid(String? value) {
    final String normalized = value?.trim() ?? '';

    return normalized.isEmpty ? null : normalized;
  }

  // ==========================================================================
  // ENTRY -> NAVIGATION SOURCE
  // ==========================================================================

  static MessageNavigationSource _navigationSourceFromEntry(
    MessageEntrySource source,
  ) {
    switch (source) {
      case MessageEntrySource.home:
        return MessageNavigationSource.home;

      case MessageEntrySource.contacts:
        return MessageNavigationSource.contacts;

      case MessageEntrySource.profile:
        return MessageNavigationSource.profile;

      case MessageEntrySource.discovery:
        return MessageNavigationSource.discovery;

      case MessageEntrySource.notification:
        return MessageNavigationSource.pushNotification;

      case MessageEntrySource.deepLink:
        return MessageNavigationSource.deepLink;

      case MessageEntrySource.inbox:
        return MessageNavigationSource.inbox;

      case MessageEntrySource.unknown:
        return MessageNavigationSource.internal;
    }
  }

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  static String _requiredId(String value, {required String fieldName}) {
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

  // ==========================================================================
  // READINESS
  // ==========================================================================

  Future<void> _ensureReady() async {
    _ensureNotDisposed();

    if (!_initialized) {
      await initialize();
    }

    if (_disposed || !_initialized) {
      throw const MessageAppCoordinatorException('Messages are unavailable.');
    }
  }

  void _ensureReadySync() {
    _ensureNotDisposed();

    if (!_initialized) {
      throw const MessageAppCoordinatorException(
        'MessageAppCoordinator has not been initialized.',
      );
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const MessageAppCoordinatorException(
        'MessageAppCoordinator has already been disposed.',
      );
    }
  }

  // ==========================================================================
  // OWNED REPOSITORY DISPOSAL
  // ==========================================================================

  Future<void> _disposeOwnedRepositories(
    MessageAppRepositories repositories,
  ) async {
    // Reverse dependency order.
    //
    // Only repositories explicitly marked as coordinator-owned are released.

    if (repositories.ownsConversationRepository &&
        !repositories.conversationRepository.isDisposed) {
      repositories.conversationRepository.dispose();
    }

    if (repositories.ownsMessageRepository &&
        !repositories.messageRepository.isDisposed) {
      repositories.messageRepository.dispose();
    }
  }

  // ==========================================================================
  // DISPOSAL
  // ==========================================================================

  /// Disposes only resources owned by MessageAppCoordinator.
  ///
  /// Never disposes:
  /// - FirebaseAuth
  /// - FirebaseFirestore global singleton
  /// - FirebaseStorage global singleton
  /// - AuthService singleton
  /// - UserDiscoveryService singleton
  /// - NavigatorState
  /// - FirebaseMessaging global lifecycle
  /// - Call Engine / WebRTC / signaling
  Future<void> dispose() {
    final Future<void>? activeDispose = _disposeFuture;

    if (activeDispose != null) {
      return activeDispose;
    }

    final Future<void> operation = _disposeInternal();

    _disposeFuture = operation;

    return operation;
  }

  Future<void> _disposeInternal() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    final Future<void>? initialization = _initializationFuture;

    if (initialization != null) {
      try {
        await initialization;
      } catch (_) {
        // Initialization already logged and re-threw its original failure.
        // Continue disposal so partially-created coordinator state cannot leak.
      }
    }

    final StreamSubscription<User?>? authSubscription = _authSubscription;

    _authSubscription = null;

    if (authSubscription != null) {
      await authSubscription.cancel();
    }

    final MessagePushService? pushService = _pushService;

    final MessageIntegrationService? integrationService = _integrationService;

    final MessageNavigationService? navigationService = _navigationService;

    final MessageAppRepositories? repositories = _repositories;

    _pushService = null;
    _integrationService = null;
    _navigationService = null;
    _repositories = null;

    _initialized = false;
    _lastAuthenticatedUid = null;

    // Reverse dependency order.
    pushService?.dispose();

    integrationService?.dispose();

    navigationService?.dispose();

    if (repositories != null) {
      await _disposeOwnedRepositories(repositories);
    }
  }
}

// ============================================================================
// FILE 49 COMPLETE
// FROZEN MESSAGE FILES 01-48 PRESERVED
// NEXT SHARED INTEGRATION: lib/main.dart
// ============================================================================
