// ============================================================================
// JR CALL
// File: message_composition_root.dart
// Location: lib/services/message/message_composition_root.dart
// Description:
// Production composition root for the JR CALL Message Engine.
//
// Responsibilities:
// - Owns creation/lifecycle of shared Message Engine infrastructure.
// - Creates the canonical Firestore remote store.
// - Creates the bounded local Message database.
// - Keeps Firebase UID as the canonical authenticated identity.
// - Provides one process-wide Message composition instance.
// - Prevents accidental duplicate initialization.
// - Provides deterministic shutdown/disposal.
// - Contains no UI rendering.
// - Contains no Call Engine/WebRTC logic.
// ============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../features/message/storage/message_database.dart';
import '../../features/message/storage/message_remote_store.dart';

/// Process-wide JR CALL Message Engine dependency container.
///
/// This root intentionally owns only dependencies whose public APIs are
/// already frozen and known here. Higher Message repositories/controllers may
/// consume [remoteStore] and [database] without recreating persistence owners.
final class MessageCompositionRoot {
  MessageCompositionRoot._(
    this._auth,
    this._firestore,
    this._remoteStore,
    this._database,
  );

  static MessageCompositionRoot? _instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final MessageRemoteStore _remoteStore;
  final MessageDatabase _database;

  bool _disposed = false;

  /// Returns true after the process-wide Message root has been installed.
  static bool get isInitialized {
    final MessageCompositionRoot? root = _instance;

    return root != null && !root._disposed;
  }

  /// Returns the installed Message root.
  ///
  /// Call [initialize] before accessing this getter.
  static MessageCompositionRoot get instance {
    final MessageCompositionRoot? root = _instance;

    if (root == null || root._disposed) {
      throw StateError(
        'JR CALL MessageCompositionRoot has not been initialized.',
      );
    }

    return root;
  }

  /// Creates the process-wide Message Engine composition root.
  ///
  /// Repeated calls are idempotent and return the existing active root.
  static MessageCompositionRoot initialize({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    MessageDatabase? database,
  }) {
    final MessageCompositionRoot? existing = _instance;

    if (existing != null && !existing._disposed) {
      return existing;
    }

    final FirebaseAuth resolvedAuth = auth ?? FirebaseAuth.instance;

    final FirebaseFirestore resolvedFirestore =
        firestore ?? FirebaseFirestore.instance;

    final MessageDatabase resolvedDatabase =
        database ??
        InMemoryMessageDatabase(
          maxConversations: 100,
          maxMessagesPerConversation: 300,
        );

    final MessageRemoteStore remoteStore = MessageRemoteStore(
      firestore: resolvedFirestore,
      auth: resolvedAuth,
    );

    final MessageCompositionRoot root = MessageCompositionRoot._(
      resolvedAuth,
      resolvedFirestore,
      remoteStore,
      resolvedDatabase,
    );

    _instance = root;

    return root;
  }

  /// Firebase Auth instance shared by the Message feature.
  FirebaseAuth get auth {
    _ensureActive();

    return _auth;
  }

  /// Firestore instance shared by the Message feature.
  FirebaseFirestore get firestore {
    _ensureActive();

    return _firestore;
  }

  /// Sole Firestore persistence boundary for Message Engine data.
  MessageRemoteStore get remoteStore {
    _ensureActive();

    return _remoteStore;
  }

  /// Local/offline optimistic and retry cache.
  MessageDatabase get database {
    _ensureActive();

    return _database;
  }

  /// Current authenticated Firebase UID.
  ///
  /// Returns null while the application is operating without an authenticated
  /// Firebase user.
  String? get currentUserUid {
    _ensureActive();

    final String? uid = _auth.currentUser?.uid.trim();

    if (uid == null || uid.isEmpty) {
      return null;
    }

    return uid;
  }

  /// Requires a real authenticated Firebase UID.
  ///
  /// Public JR CALL ID, username, email and phone are never substituted for
  /// Firebase UID at this infrastructure boundary.
  String requireCurrentUserUid() {
    final String? uid = currentUserUid;

    if (uid == null) {
      throw StateError('Authentication is required for JR CALL messaging.');
    }

    return uid;
  }

  /// Authentication-state stream exposed to Message integration code.
  Stream<User?> get authStateChanges {
    _ensureActive();

    return _auth.authStateChanges();
  }

  /// Clears only local Message Engine cache.
  ///
  /// Firestore conversations/messages are never deleted by this operation.
  Future<void> clearLocalData() async {
    _ensureActive();

    await _database.clear();
  }

  /// Clears local Message data after logout/account transition.
  ///
  /// This deliberately does not sign the user out. Authentication ownership
  /// remains with JR CALL's AuthService.
  Future<void> handleSignedOut() async {
    _ensureActive();

    await _database.clear();
  }

  /// Releases resources owned by this composition root.
  ///
  /// FirebaseAuth and FirebaseFirestore are application-owned singleton
  /// services and therefore are not disposed here.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _database.dispose();

    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError(
        'JR CALL MessageCompositionRoot has already been disposed.',
      );
    }
  }
}

/// Convenience accessor for the installed JR CALL Message root.
MessageCompositionRoot get messageCompositionRoot =>
    MessageCompositionRoot.instance;

/// Initializes JR CALL Message infrastructure.
///
/// This small top-level facade keeps main.dart integration simple without
/// exposing construction details.
MessageCompositionRoot initializeMessageComposition({
  FirebaseAuth? auth,
  FirebaseFirestore? firestore,
  MessageDatabase? database,
}) {
  return MessageCompositionRoot.initialize(
    auth: auth,
    firestore: firestore,
    database: database,
  );
}

/// Releases the currently installed Message composition root.
///
/// Safe to call when no root is installed.
Future<void> disposeMessageComposition() async {
  if (!MessageCompositionRoot.isInitialized) {
    return;
  }

  await MessageCompositionRoot.instance.dispose();
}

// ============================================================================
// END OF FILE:
// lib/services/message/message_composition_root.dart
// ============================================================================
