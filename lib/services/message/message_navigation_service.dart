// ============================================================================
// JR CALL
// File: message_navigation_service.dart
// Location: lib/services/message/message_navigation_service.dart
// Description:
// Central application-navigation owner for the JR CALL Message feature.
//
// Owns:
// - Message inbox navigation.
// - New-chat navigation.
// - Existing canonical conversation navigation.
// - Guest/authentication gate navigation.
// - Pending Message destination restoration after authentication.
// - Duplicate navigation suppression.
// - Navigator lifecycle safety.
//
// Does NOT:
// - Call Firestore.
// - Call Firebase Storage.
// - Create/find conversations.
// - Search users.
// - Replace UserDiscoveryService.
// - Create Firebase Auth credentials.
// - Parse Message FCM payloads.
// - Use public JR CALL ID as an internal UID.
// - Recreate Message Engine.
// - Recreate Call Engine/WebRTC.
//
// IMPORTANT:
// Concrete MessageScreen / ChatScreen / NewChatScreen construction is injected
// by the application composition layer. This keeps navigation independent from
// repository/controller construction and prevents guessed APIs.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

/// Source that requested Message navigation.
///
/// This records only the application entry source. It is never used as
/// authentication identity or database ownership identity.
enum MessageNavigationSource {
  home,
  inbox,
  contacts,
  profile,
  discovery,
  pushNotification,
  deepLink,
  internal,
}

/// Message destination type.
enum MessageNavigationDestination { inbox, newChat, conversation }

/// Navigation completion state.
enum MessageNavigationStatus {
  opened,
  authenticationRequired,
  unavailable,
  ignored,
}

/// Immutable result of one Message navigation request.
@immutable
final class MessageNavigationResult {
  const MessageNavigationResult({
    required this.status,
    required this.destination,
    required this.source,
    this.conversationId,
  });

  final MessageNavigationStatus status;
  final MessageNavigationDestination destination;
  final MessageNavigationSource source;

  /// Canonical durable Message conversation document ID when applicable.
  final String? conversationId;

  bool get opened => status == MessageNavigationStatus.opened;

  bool get requiresAuthentication =>
      status == MessageNavigationStatus.authenticationRequired;

  bool get unavailable => status == MessageNavigationStatus.unavailable;

  bool get ignored => status == MessageNavigationStatus.ignored;
}

/// Immutable Message navigation intent.
///
/// For a durable conversation, [conversationId] is the canonical conversation
/// document identity.
///
/// Firebase UID ownership remains outside this navigation layer.
@immutable
final class MessageNavigationIntent {
  const MessageNavigationIntent._({
    required this.destination,
    required this.source,
    this.conversationId,
  });

  /// Opens the authenticated Message inbox.
  const MessageNavigationIntent.inbox({
    MessageNavigationSource source = MessageNavigationSource.home,
  }) : this._(destination: MessageNavigationDestination.inbox, source: source);

  /// Opens the authenticated New Chat flow.
  const MessageNavigationIntent.newChat({
    MessageNavigationSource source = MessageNavigationSource.inbox,
  }) : this._(
         destination: MessageNavigationDestination.newChat,
         source: source,
       );

  /// Opens one already-known canonical durable Message conversation.
  MessageNavigationIntent.conversation({
    required String conversationId,
    MessageNavigationSource source = MessageNavigationSource.internal,
  }) : this._(
         destination: MessageNavigationDestination.conversation,
         source: source,
         conversationId: _normalizeRequiredId(conversationId, 'conversationId'),
       );

  final MessageNavigationDestination destination;
  final MessageNavigationSource source;

  /// Canonical Message conversation document ID.
  final String? conversationId;

  /// Stable duplicate-navigation key.
  ///
  /// It deliberately contains conversation identity only where required and
  /// never substitutes public username/email/phone/JR CALL ID for Firebase UID.
  String get dedupeKey {
    switch (destination) {
      case MessageNavigationDestination.inbox:
        return 'message::inbox';

      case MessageNavigationDestination.newChat:
        return 'message::new-chat';

      case MessageNavigationDestination.conversation:
        return 'message::conversation::${conversationId ?? ''}';
    }
  }

  static String _normalizeRequiredId(String value, String fieldName) {
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

/// Builds the finalized Message inbox destination.
///
/// The application composition layer supplies the exact production
/// MessageScreen with its finalized controllers/bindings.
typedef MessageInboxPageBuilder = Widget Function(BuildContext context);

/// Builds the finalized New Chat destination.
///
/// User discovery remains owned by the existing UserDiscoveryService and the
/// finalized NewChatScreen composition.
typedef MessageNewChatPageBuilder = Widget Function(BuildContext context);

/// Builds one finalized ChatScreen for a canonical conversation ID.
typedef MessageConversationPageBuilder =
    Widget Function(BuildContext context, String conversationId);

/// Opens the existing JR CALL Login/Create Account flow.
///
/// This service never recreates AuthService or authentication screens.
typedef MessageAuthenticationPageBuilder =
    Widget Function(BuildContext context);

/// Returns the current authenticated Firebase UID.
///
/// A null or blank value means guest.
///
/// This boundary only validates whether protected Message navigation may
/// continue. It never replaces Firebase UID with email, phone, username or
/// public JR CALL ID.
typedef MessageNavigationUidProvider = String? Function();

/// Optional observer callback for application-level integration/telemetry.
typedef MessageNavigationObserver =
    void Function(
      MessageNavigationIntent intent,
      MessageNavigationResult result,
    );

/// JR CALL Message navigation service.
///
/// Recommended lifetime:
/// one application-level instance.
///
/// Flow:
///
/// Existing Home / Contacts / Profile / Discovery / Message Push
///   -> MessageNavigationService
///   -> authenticated Firebase UID gate
///   -> already-composed Message page builder
///   -> finalized Message presentation/controller/repository stack
///
/// This service deliberately does NOT create repositories, Message Engine,
/// UserDiscoveryService, AuthService or Call Engine objects.
final class MessageNavigationService {
  /// Public constructor.
  ///
  /// Public parameter names remain stable for application integration.
  ///
  /// A private initializing-formal constructor is used internally so the
  /// service remains analyzer-clean without changing its public API.
  factory MessageNavigationService({
    required GlobalKey<NavigatorState> navigatorKey,
    required MessageNavigationUidProvider currentUidProvider,
    required MessageInboxPageBuilder inboxBuilder,
    required MessageNewChatPageBuilder newChatBuilder,
    required MessageConversationPageBuilder conversationBuilder,
    required MessageAuthenticationPageBuilder authenticationBuilder,
    MessageNavigationObserver? observer,
  }) {
    return MessageNavigationService._(
      navigatorKey,
      currentUidProvider,
      inboxBuilder,
      newChatBuilder,
      conversationBuilder,
      authenticationBuilder,
      observer,
    );
  }

  MessageNavigationService._(
    this._navigatorKey,
    this._currentUidProvider,
    this._inboxBuilder,
    this._newChatBuilder,
    this._conversationBuilder,
    this._authenticationBuilder,
    this._observer,
  );

  final GlobalKey<NavigatorState> _navigatorKey;
  final MessageNavigationUidProvider _currentUidProvider;

  final MessageInboxPageBuilder _inboxBuilder;
  final MessageNewChatPageBuilder _newChatBuilder;
  final MessageConversationPageBuilder _conversationBuilder;
  final MessageAuthenticationPageBuilder _authenticationBuilder;

  final MessageNavigationObserver? _observer;

  /// Protected Message destination waiting for successful authentication.
  MessageNavigationIntent? _pendingAfterAuthentication;

  /// Currently active navigation operation.
  ///
  /// Used to suppress rapid duplicate pushes of the same Message destination.
  String? _activeNavigationKey;

  /// Prevents multiple Login/Create Account routes opening simultaneously.
  bool _authenticationRouteOpening = false;

  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Whether this navigation boundary currently sees a canonical authenticated
  /// Firebase UID.
  bool get isAuthenticated => !_disposed && _currentFirebaseUid != null;

  /// Pending Message destination waiting for authentication.
  ///
  /// Returns null after disposal because disposed navigation state must not be
  /// consumed by application integration.
  MessageNavigationIntent? get pendingAfterAuthentication {
    if (_disposed) {
      return null;
    }

    return _pendingAfterAuthentication;
  }

  /// Opens the main authenticated Message inbox.
  Future<MessageNavigationResult> openInbox({
    MessageNavigationSource source = MessageNavigationSource.home,
  }) {
    return navigate(MessageNavigationIntent.inbox(source: source));
  }

  /// Opens New Chat.
  ///
  /// NewChatScreen/UserDiscoveryService remains responsible for resolving
  /// public profile data into the canonical Firebase UID before a durable
  /// direct conversation is created.
  Future<MessageNavigationResult> openNewChat({
    MessageNavigationSource source = MessageNavigationSource.inbox,
  }) {
    return navigate(MessageNavigationIntent.newChat(source: source));
  }

  /// Opens one already-resolved canonical conversation.
  Future<MessageNavigationResult> openConversation({
    required String conversationId,
    MessageNavigationSource source = MessageNavigationSource.internal,
  }) {
    return navigate(
      MessageNavigationIntent.conversation(
        conversationId: conversationId,
        source: source,
      ),
    );
  }

  /// Main Message navigation entry point.
  ///
  /// Every Message destination is authentication-protected.
  ///
  /// Guest flow:
  ///
  /// requested destination
  ///   -> save pending intent
  ///   -> existing authentication page
  ///   -> real Firebase UID becomes available
  ///   -> pending destination resumes
  ///
  /// Authenticated flow:
  ///
  /// requested destination
  ///   -> duplicate suppression
  ///   -> typed page builder
  ///   -> Navigator push
  Future<MessageNavigationResult> navigate(
    MessageNavigationIntent intent,
  ) async {
    _ensureActive();

    if (!_isValidIntent(intent)) {
      return _result(
        intent: intent,
        status: MessageNavigationStatus.unavailable,
      );
    }

    if (_currentFirebaseUid == null) {
      _pendingAfterAuthentication = intent;

      final MessageNavigationResult result = _result(
        intent: intent,
        status: MessageNavigationStatus.authenticationRequired,
      );

      await _openAuthenticationRoute();

      return result;
    }

    return _openAuthenticatedIntent(intent);
  }

  /// Resumes the protected Message destination after Login/Create Account.
  ///
  /// A pending destination is never opened until a genuine non-empty Firebase
  /// UID is available from [_currentUidProvider].
  Future<MessageNavigationResult?> resumePendingAfterAuthentication() async {
    _ensureActive();

    final MessageNavigationIntent? pending = _pendingAfterAuthentication;

    if (pending == null) {
      return null;
    }

    if (_currentFirebaseUid == null) {
      return _result(
        intent: pending,
        status: MessageNavigationStatus.authenticationRequired,
      );
    }

    _pendingAfterAuthentication = null;

    return _openAuthenticatedIntent(pending);
  }

  /// Clears a protected destination waiting for authentication.
  ///
  /// Use this when authentication is cancelled or application policy decides
  /// that the pending Message action must not continue.
  void clearPendingAuthenticationNavigation() {
    if (_disposed) {
      return;
    }

    _pendingAfterAuthentication = null;
  }

  /// Clears Message navigation state after an authentication-session change.
  ///
  /// This method does NOT sign the user in/out and does not manipulate
  /// FirebaseAuth. Existing AuthService remains the authentication owner.
  void resetSession() {
    if (_disposed) {
      return;
    }

    _pendingAfterAuthentication = null;
    _activeNavigationKey = null;
    _authenticationRouteOpening = false;
  }

  Future<MessageNavigationResult> _openAuthenticatedIntent(
    MessageNavigationIntent intent,
  ) async {
    if (_disposed) {
      return MessageNavigationResult(
        status: MessageNavigationStatus.unavailable,
        destination: intent.destination,
        source: intent.source,
        conversationId: intent.conversationId,
      );
    }

    /// Authentication is revalidated immediately before opening the route.
    ///
    /// This protects against a sign-out/account-session change occurring
    /// between the original navigation request and actual route creation.
    if (_currentFirebaseUid == null) {
      _pendingAfterAuthentication = intent;

      return _result(
        intent: intent,
        status: MessageNavigationStatus.authenticationRequired,
      );
    }

    final NavigatorState? navigator = _navigatorKey.currentState;

    if (navigator == null) {
      return _result(
        intent: intent,
        status: MessageNavigationStatus.unavailable,
      );
    }

    final String navigationKey = intent.dedupeKey;

    if (_activeNavigationKey == navigationKey) {
      return _result(intent: intent, status: MessageNavigationStatus.ignored);
    }

    _activeNavigationKey = navigationKey;

    try {
      final Route<void> route = MaterialPageRoute<void>(
        settings: RouteSettings(
          name: _routeName(intent),
          arguments: _routeArguments(intent),
        ),
        builder: (BuildContext context) {
          switch (intent.destination) {
            case MessageNavigationDestination.inbox:
              return _inboxBuilder(context);

            case MessageNavigationDestination.newChat:
              return _newChatBuilder(context);

            case MessageNavigationDestination.conversation:
              final String? conversationId = intent.conversationId;

              /// This condition should already have been rejected by
              /// [_isValidIntent]. Keeping this defensive guard prevents an
              /// invalid nullable identifier from reaching the production
              /// ChatScreen builder if application state is corrupted.
              if (conversationId == null || conversationId.trim().isEmpty) {
                return const SizedBox.shrink();
              }

              return _conversationBuilder(context, conversationId);
          }
        },
      );

      await navigator.push<void>(route);

      /// The navigation route may outlive the integration service. Do not emit
      /// an observer callback through disposed service state.
      if (_disposed) {
        return MessageNavigationResult(
          status: MessageNavigationStatus.unavailable,
          destination: intent.destination,
          source: intent.source,
          conversationId: intent.conversationId,
        );
      }

      return _result(intent: intent, status: MessageNavigationStatus.opened);
    } finally {
      if (_activeNavigationKey == navigationKey) {
        _activeNavigationKey = null;
      }
    }
  }

  /// Opens the existing application authentication flow.
  ///
  /// Only one authentication route may be active at once.
  Future<void> _openAuthenticationRoute() async {
    if (_authenticationRouteOpening || _disposed) {
      return;
    }

    final NavigatorState? navigator = _navigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    _authenticationRouteOpening = true;

    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/auth/message'),
          builder: _authenticationBuilder,
        ),
      );
    } finally {
      _authenticationRouteOpening = false;
    }

    if (_disposed) {
      return;
    }

    /// Authentication may have completed while the authentication route was
    /// open. Resume only when a genuine Firebase UID now exists.
    if (_currentFirebaseUid != null && _pendingAfterAuthentication != null) {
      unawaited(resumePendingAfterAuthentication());
    }
  }

  bool _isValidIntent(MessageNavigationIntent intent) {
    switch (intent.destination) {
      case MessageNavigationDestination.inbox:
      case MessageNavigationDestination.newChat:
        return true;

      case MessageNavigationDestination.conversation:
        final String? conversationId = intent.conversationId;

        return conversationId != null && conversationId.trim().isNotEmpty;
    }
  }

  String _routeName(MessageNavigationIntent intent) {
    switch (intent.destination) {
      case MessageNavigationDestination.inbox:
        return '/message';

      case MessageNavigationDestination.newChat:
        return '/message/new';

      case MessageNavigationDestination.conversation:
        final String conversationId = intent.conversationId ?? '';

        return '/message/chat/${Uri.encodeComponent(conversationId)}';
    }
  }

  Map<String, Object?> _routeArguments(MessageNavigationIntent intent) {
    final String? conversationId = intent.conversationId;

    return <String, Object?>{
      'feature': 'message',
      'destination': intent.destination.name,
      'source': intent.source.name,
      'conversationId': ?conversationId,
    };
  }

  MessageNavigationResult _result({
    required MessageNavigationIntent intent,
    required MessageNavigationStatus status,
  }) {
    final MessageNavigationResult result = MessageNavigationResult(
      status: status,
      destination: intent.destination,
      source: intent.source,
      conversationId: intent.conversationId,
    );

    _observer?.call(intent, result);

    return result;
  }

  /// Current canonical Firebase UID.
  ///
  /// Empty/whitespace-only values are normalized to null and therefore treated
  /// as guest sessions.
  String? get _currentFirebaseUid {
    final String uid = _currentUidProvider()?.trim() ?? '';

    return uid.isEmpty ? null : uid;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('MessageNavigationService has already been disposed.');
    }
  }

  /// Releases only this service's own navigation state.
  ///
  /// It deliberately does NOT dispose:
  /// - NavigatorState
  /// - Firebase Auth/AuthService
  /// - UserDiscoveryService
  /// - Message repositories
  /// - Message controllers
  /// - Message Engine
  /// - Call Engine/WebRTC
  ///
  /// Their ownership remains with their existing application composition
  /// boundaries.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _pendingAfterAuthentication = null;
    _activeNavigationKey = null;
    _authenticationRouteOpening = false;
  }
}

// ============================================================================
// END OF FILE:
// lib/services/message/message_navigation_service.dart
// ============================================================================
