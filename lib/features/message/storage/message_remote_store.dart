// ============================================================================
// JR CALL
// File: message_remote_store.dart
// Location: lib/features/message/storage/message_remote_store.dart
// Description:
// Sole Cloud Firestore persistence owner for JR CALL Message Engine.
//
// Owns:
// - conversations/{conversationId}
// - conversations/{conversationId}/messages/{messageId}
// - conversations/{conversationId}/typing/{uid}
// - conversations/{conversationId}/live/{uid}
// - conversations/{conversationId}/receipts/{uid}
// - conversations/{conversationId}/messages/{messageId}/reactions/{uid}
//
// Guarantees:
// - Firebase UID remains canonical internal user identity.
// - Direct conversations use deterministic participant-pair identity.
// - Durable message ID is never replaced during retry/reconciliation.
// - Message creation + conversation summary update is atomic.
// - Delivered/read state is never fabricated by elapsed time.
// - Typing and Live Chat remain ephemeral state.
// - One reaction document exists per reacting UID/message.
// - Pagination uses deterministic timestamp + document-ID ordering.
// - No Firebase Storage binary upload logic.
// - No UI logic.
// - No Call Engine/WebRTC logic.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/conversation_entity.dart';
import '../data/message_entity.dart';
import '../data/message_status.dart';
import '../data/message_type.dart';
import '../data/reaction_entity.dart';

/// Cursor for durable-message pagination.
final class MessagePageCursor {
  const MessagePageCursor({
    required this.serverCreatedAt,
    required this.messageId,
  });

  final DateTime serverCreatedAt;
  final String messageId;
}

/// One immutable durable-message page.
final class MessageRemotePage {
  const MessageRemotePage({
    required this.messages,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<MessageEntity> messages;
  final MessagePageCursor? nextCursor;
  final bool hasMore;
}

/// Cursor for conversation-list pagination.
final class ConversationPageCursor {
  const ConversationPageCursor({
    required this.lastMessageAt,
    required this.conversationId,
  });

  final DateTime lastMessageAt;
  final String conversationId;
}

/// One immutable conversation page.
final class ConversationRemotePage {
  const ConversationRemotePage({
    required this.conversations,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<ConversationEntity> conversations;
  final ConversationPageCursor? nextCursor;
  final bool hasMore;
}

/// Canonical typing-state record.
final class MessageTypingState {
  const MessageTypingState({
    required this.conversationId,
    required this.userUid,
    required this.isTyping,
    required this.updatedAt,
    required this.expiresAt,
  });

  final String conversationId;
  final String userUid;
  final bool isTyping;
  final DateTime updatedAt;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  bool get isActive => isTyping && !isExpired;
}

/// Canonical JR CALL Live Chat ephemeral state.
final class MessageLiveDraftState {
  const MessageLiveDraftState({
    required this.conversationId,
    required this.senderUid,
    required this.sessionId,
    required this.version,
    required this.text,
    required this.styleSeed,
    required this.updatedAt,
    required this.expiresAt,
    required this.active,
  });

  final String conversationId;
  final String senderUid;
  final String sessionId;
  final int version;
  final String text;
  final int styleSeed;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final bool active;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  bool get isActive => active && text.isNotEmpty && !isExpired;
}

/// Delivery/read acknowledgement boundary produced by one participant.
///
/// These values represent actual receipt writes. They are not inferred from
/// listener time or wall-clock delays.
final class MessageReceiptState {
  const MessageReceiptState({
    required this.conversationId,
    required this.userUid,
    this.deliveredMessageId,
    this.deliveredThroughAt,
    this.readMessageId,
    this.readThroughAt,
    this.updatedAt,
  });

  final String conversationId;
  final String userUid;

  final String? deliveredMessageId;
  final DateTime? deliveredThroughAt;

  final String? readMessageId;
  final DateTime? readThroughAt;

  final DateTime? updatedAt;
}

/// Firestore persistence implementation for the JR CALL Message feature.
final class MessageRemoteStore {
  MessageRemoteStore({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const String conversationsCollection = 'conversations';
  static const String messagesCollection = 'messages';
  static const String typingCollection = 'typing';
  static const String liveCollection = 'live';
  static const String receiptsCollection = 'receipts';
  static const String reactionsCollection = 'reactions';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, Object?>> get _conversations =>
      _firestore.collection(conversationsCollection);

  // --------------------------------------------------------------------------
  // DIRECT CONVERSATION IDENTITY
  // --------------------------------------------------------------------------

  /// Returns one deterministic direct-conversation ID for the exact UID pair.
  ///
  /// Public JR CALL IDs, usernames, email addresses and phone numbers are
  /// never accepted here.
  static String directConversationId(String firstUid, String secondUid) {
    final String first = _normalizeId(firstUid, fieldName: 'firstUid');
    final String second = _normalizeId(secondUid, fieldName: 'secondUid');

    if (first == second) {
      throw ArgumentError(
        'A direct conversation requires two different Firebase UIDs.',
      );
    }

    final List<String> participants = <String>[first, second]..sort();

    final String payload = '${participants[0]}\u0000${participants[1]}';

    final String encoded = base64UrlEncode(
      utf8.encode(payload),
    ).replaceAll('=', '');

    return 'direct_$encoded';
  }

  /// Finds or atomically creates the canonical direct conversation.
  Future<ConversationEntity> findOrCreateDirectConversation({
    required String currentUid,
    required String peerUid,
  }) async {
    final String current = _requireAuthenticatedUid(currentUid);
    final String peer = _normalizeId(peerUid, fieldName: 'peerUid');

    if (current == peer) {
      throw ArgumentError(
        'A user cannot create a direct conversation with themselves.',
      );
    }

    final List<String> participants = <String>[current, peer]..sort();

    final String conversationId = directConversationId(
      participants[0],
      participants[1],
    );

    final DocumentReference<Map<String, Object?>> reference = _conversations
        .doc(conversationId);

    await _firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, Object?>> snapshot = await transaction
          .get(reference);

      if (snapshot.exists) {
        final Map<String, Object?> data =
            snapshot.data() ?? <String, Object?>{};

        final List<String> existingParticipants = _readStringList(
          data['participantUids'],
        )..sort();

        if (!_sameStringList(existingParticipants, participants)) {
          throw StateError(
            'Existing direct conversation participant identity mismatch.',
          );
        }

        return;
      }

      final Map<String, int> unreadCounts = <String, int>{
        for (final String uid in participants) uid: 0,
      };

      transaction.set(reference, <String, Object?>{
        'id': conversationId,
        'type': 'direct',
        'participantUids': participants,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessageId': null,
        'lastMessageType': null,
        'lastMessagePreview': null,
        'lastSenderUid': null,
        'lastMessageAt': null,
        'unreadCounts': unreadCounts,
        'archivedBy': <String>[],
        'mutedBy': <String>[],
        'pinnedBy': <String>[],
        'hiddenBy': <String>[],
        'deleted': false,
      });
    });

    final ConversationEntity? conversation = await getConversation(
      conversationId,
    );

    if (conversation == null) {
      throw StateError(
        'Direct conversation was created but could not be loaded.',
      );
    }

    return conversation;
  }

  // --------------------------------------------------------------------------
  // CONVERSATION
  // --------------------------------------------------------------------------

  Future<ConversationEntity?> getConversation(String conversationId) async {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final DocumentSnapshot<Map<String, Object?>> snapshot = await _conversations
        .doc(id)
        .get();

    if (!snapshot.exists) {
      return null;
    }

    final Map<String, Object?> data = snapshot.data() ?? <String, Object?>{};

    return ConversationEntity.fromMap(<String, Object?>{
      ...data,
      'id': snapshot.id,
    });
  }

  Future<bool> isConversationParticipant({
    required String conversationId,
    required String userUid,
  }) async {
    final String uid = _normalizeId(userUid, fieldName: 'userUid');

    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final DocumentSnapshot<Map<String, Object?>> snapshot = await _conversations
        .doc(id)
        .get();

    if (!snapshot.exists) {
      return false;
    }

    final List<String> participants = _readStringList(
      snapshot.data()?['participantUids'],
    );

    return participants.contains(uid);
  }

  Future<ConversationRemotePage> loadConversations({
    required String userUid,
    int limit = 30,
    ConversationPageCursor? cursor,
  }) async {
    final String uid = _requireAuthenticatedUid(userUid);
    _validateLimit(limit);

    Query<Map<String, Object?>> query = _conversations
        .where('participantUids', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);

    if (cursor != null) {
      query = query.startAfter(<Object?>[
        Timestamp.fromDate(cursor.lastMessageAt.toUtc()),
        cursor.conversationId,
      ]);
    }

    final QuerySnapshot<Map<String, Object?>> snapshot = await query
        .limit(limit + 1)
        .get();

    final bool hasMore = snapshot.docs.length > limit;

    final List<QueryDocumentSnapshot<Map<String, Object?>>> docs = snapshot.docs
        .take(limit)
        .toList(growable: false);

    final List<ConversationEntity> conversations = docs
        .map(_conversationFromSnapshot)
        .toList(growable: false);

    ConversationPageCursor? nextCursor;

    if (docs.isNotEmpty) {
      final QueryDocumentSnapshot<Map<String, Object?>> last = docs.last;

      nextCursor = ConversationPageCursor(
        lastMessageAt: _requiredDateTime(
          last.data()['lastMessageAt'] ??
              last.data()['updatedAt'] ??
              last.data()['createdAt'],
          fieldName: 'lastMessageAt',
        ),
        conversationId: last.id,
      );
    }

    return ConversationRemotePage(
      conversations: List<ConversationEntity>.unmodifiable(conversations),
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  Stream<List<ConversationEntity>> watchConversations({
    required String userUid,
    int limit = 30,
  }) {
    final String uid = _requireAuthenticatedUid(userUid);
    _validateLimit(limit);

    return _conversations
        .where('participantUids', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (QuerySnapshot<Map<String, Object?>> snapshot) =>
              List<ConversationEntity>.unmodifiable(
                snapshot.docs.map(_conversationFromSnapshot),
              ),
        );
  }

  // --------------------------------------------------------------------------
  // DURABLE MESSAGE CREATE
  // --------------------------------------------------------------------------

  /// Atomically creates one durable message and updates conversation summary.
  ///
  /// Stable [MessageEntity.id] prevents duplicate sends during retry.
  Future<void> createMessage(MessageEntity message) async {
    final String senderUid = _requireAuthenticatedUid(message.senderUid);

    final String conversationId = _normalizeId(
      message.conversationId,
      fieldName: 'message.conversationId',
    );

    final String messageId = _normalizeId(message.id, fieldName: 'message.id');

    final DocumentReference<Map<String, Object?>> conversationRef =
        _conversations.doc(conversationId);

    final DocumentReference<Map<String, Object?>> messageRef = conversationRef
        .collection(messagesCollection)
        .doc(messageId);

    await _firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, Object?>> conversationSnapshot =
          await transaction.get(conversationRef);

      if (!conversationSnapshot.exists) {
        throw StateError('Conversation does not exist.');
      }

      final Map<String, Object?> conversationData =
          conversationSnapshot.data() ?? <String, Object?>{};

      final List<String> participants = _readStringList(
        conversationData['participantUids'],
      );

      if (!participants.contains(senderUid)) {
        throw StateError(
          'Authenticated sender is not a conversation participant.',
        );
      }

      final DocumentSnapshot<Map<String, Object?>> existingMessage =
          await transaction.get(messageRef);

      if (existingMessage.exists) {
        final Map<String, Object?> existingData =
            existingMessage.data() ?? <String, Object?>{};

        final String existingSender = _readString(existingData['senderUid']);

        final String existingConversation = _readString(
          existingData['conversationId'],
        );

        if (existingSender != senderUid ||
            existingConversation != conversationId) {
          throw StateError(
            'Stable message ID conflicts with another durable message.',
          );
        }

        // Idempotent retry: the exact canonical message already exists.
        return;
      }

      final Map<String, Object?> messageData = _durableMessageMap(message);

      transaction.set(messageRef, messageData);

      final Map<String, int> unreadCounts = _readIntMap(
        conversationData['unreadCounts'],
      );

      for (final String participantUid in participants) {
        unreadCounts.putIfAbsent(participantUid, () => 0);

        if (participantUid != senderUid) {
          unreadCounts[participantUid] = unreadCounts[participantUid]! + 1;
        }
      }

      final String preview = _messagePreview(message);

      transaction.update(conversationRef, <String, Object?>{
        'lastMessageId': messageId,
        'lastSenderUid': senderUid,
        'lastMessageType': message.type.serialized,
        'lastMessagePreview': preview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'unreadCounts': unreadCounts,
      });
    });
  }

  // --------------------------------------------------------------------------
  // MESSAGE READ / QUERY / PAGINATION
  // --------------------------------------------------------------------------

  Future<MessageEntity?> getMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizeId(messageId, fieldName: 'messageId');

    final DocumentSnapshot<Map<String, Object?>> snapshot =
        await _messageReference(conversation, message).get();

    if (!snapshot.exists) {
      return null;
    }

    return _messageFromSnapshot(snapshot, conversationId: conversation);
  }

  Future<MessageRemotePage> loadMessages({
    required String conversationId,
    required String userUid,
    int limit = 40,
    MessagePageCursor? cursor,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String uid = _requireAuthenticatedUid(userUid);

    await _requireParticipant(conversationId: conversation, userUid: uid);

    _validateLimit(limit);

    Query<Map<String, Object?>> query = _messagesReference(conversation)
        .orderBy('serverCreatedAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);

    if (cursor != null) {
      query = query.startAfter(<Object?>[
        Timestamp.fromDate(cursor.serverCreatedAt.toUtc()),
        cursor.messageId,
      ]);
    }

    final QuerySnapshot<Map<String, Object?>> snapshot = await query
        .limit(limit + 1)
        .get();

    final bool hasMore = snapshot.docs.length > limit;

    final List<QueryDocumentSnapshot<Map<String, Object?>>> docs = snapshot.docs
        .take(limit)
        .toList(growable: false);

    // Firestore query is newest -> oldest.
    // Timeline/domain output remains oldest -> newest.
    final List<MessageEntity> messages =
        docs
            .map(
              (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
                  _messageFromSnapshot(snapshot, conversationId: conversation),
            )
            .toList(growable: true)
          ..sort(_compareMessages);

    MessagePageCursor? nextCursor;

    if (docs.isNotEmpty) {
      final QueryDocumentSnapshot<Map<String, Object?>> last = docs.last;

      nextCursor = MessagePageCursor(
        serverCreatedAt: _requiredDateTime(
          last.data()['serverCreatedAt'] ?? last.data()['clientCreatedAt'],
          fieldName: 'serverCreatedAt',
        ),
        messageId: last.id,
      );
    }

    return MessageRemotePage(
      messages: List<MessageEntity>.unmodifiable(messages),
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  Stream<List<MessageEntity>> watchLatestMessages({
    required String conversationId,
    required String userUid,
    int limit = 50,
  }) async* {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String uid = _requireAuthenticatedUid(userUid);

    await _requireParticipant(conversationId: conversation, userUid: uid);

    _validateLimit(limit);

    yield* _messagesReference(conversation)
        .orderBy('serverCreatedAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, Object?>> snapshot) {
          final List<MessageEntity> messages =
              snapshot.docs
                  .map(
                    (QueryDocumentSnapshot<Map<String, Object?>> document) =>
                        _messageFromSnapshot(
                          document,
                          conversationId: conversation,
                        ),
                  )
                  .toList(growable: true)
                ..sort(_compareMessages);

          return List<MessageEntity>.unmodifiable(messages);
        });
  }

  // --------------------------------------------------------------------------
  // EDIT
  // --------------------------------------------------------------------------

  Future<void> editTextMessage({
    required String conversationId,
    required String messageId,
    required String actorUid,
    required String text,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizeId(messageId, fieldName: 'messageId');

    final String actor = _requireAuthenticatedUid(actorUid);
    final String normalizedText = text.trim();

    if (normalizedText.isEmpty) {
      throw ArgumentError('Edited text must not be empty.');
    }

    final DocumentReference<Map<String, Object?>> conversationRef =
        _conversations.doc(conversation);

    final DocumentReference<Map<String, Object?>> messageRef =
        _messageReference(conversation, message);

    await _firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, Object?>> conversationSnapshot =
          await transaction.get(conversationRef);

      final DocumentSnapshot<Map<String, Object?>> messageSnapshot =
          await transaction.get(messageRef);

      if (!conversationSnapshot.exists) {
        throw StateError('Conversation does not exist.');
      }

      if (!messageSnapshot.exists) {
        throw StateError('Message does not exist.');
      }

      final Map<String, Object?> conversationData =
          conversationSnapshot.data() ?? <String, Object?>{};

      final Map<String, Object?> messageData =
          messageSnapshot.data() ?? <String, Object?>{};

      _requireParticipantData(conversationData, actor);

      if (_readString(messageData['senderUid']) != actor) {
        throw StateError('Only the sender may edit this message.');
      }

      final MessageType type = MessageType.fromValue(messageData['type']);

      if (type != MessageType.text) {
        throw StateError('Only text messages may be edited.');
      }

      if (messageData['deletedAt'] != null) {
        throw StateError('Deleted messages cannot be edited.');
      }

      transaction.update(messageRef, <String, Object?>{
        'text': normalizedText,
        'editedAt': FieldValue.serverTimestamp(),
      });

      if (_readNullableString(conversationData['lastMessageId']) == message) {
        transaction.update(conversationRef, <String, Object?>{
          'lastMessagePreview': _truncatePreview(normalizedText),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // --------------------------------------------------------------------------
  // SOFT DELETE
  // --------------------------------------------------------------------------

  Future<void> softDeleteMessage({
    required String conversationId,
    required String messageId,
    required String actorUid,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizeId(messageId, fieldName: 'messageId');

    final String actor = _requireAuthenticatedUid(actorUid);

    final DocumentReference<Map<String, Object?>> conversationRef =
        _conversations.doc(conversation);

    final DocumentReference<Map<String, Object?>> messageRef =
        _messageReference(conversation, message);

    await _firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, Object?>> conversationSnapshot =
          await transaction.get(conversationRef);

      final DocumentSnapshot<Map<String, Object?>> messageSnapshot =
          await transaction.get(messageRef);

      if (!conversationSnapshot.exists) {
        throw StateError('Conversation does not exist.');
      }

      if (!messageSnapshot.exists) {
        throw StateError('Message does not exist.');
      }

      final Map<String, Object?> conversationData =
          conversationSnapshot.data() ?? <String, Object?>{};

      final Map<String, Object?> messageData =
          messageSnapshot.data() ?? <String, Object?>{};

      _requireParticipantData(conversationData, actor);

      if (_readString(messageData['senderUid']) != actor) {
        throw StateError('Only the sender may delete this message.');
      }

      if (messageData['deletedAt'] != null) {
        return;
      }

      transaction.update(messageRef, <String, Object?>{
        'text': '',
        'deletedAt': FieldValue.serverTimestamp(),
        'editedAt': null,
      });

      if (_readNullableString(conversationData['lastMessageId']) == message) {
        transaction.update(conversationRef, <String, Object?>{
          'lastMessagePreview': 'Message deleted',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // --------------------------------------------------------------------------
  // TYPING STATE
  // --------------------------------------------------------------------------

  Future<void> setTypingState({
    required String conversationId,
    required String userUid,
    required bool isTyping,
    required DateTime expiresAt,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String uid = _requireAuthenticatedUid(userUid);

    await _requireParticipant(conversationId: conversation, userUid: uid);

    await _typingReference(conversation, uid).set(<String, Object?>{
      'conversationId': conversation,
      'userUid': uid,
      'isTyping': isTyping,
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt.toUtc()),
    }, SetOptions(merge: true));
  }

  Future<void> clearTypingState({
    required String conversationId,
    required String userUid,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String uid = _requireAuthenticatedUid(userUid);

    await _typingReference(conversation, uid).delete();
  }

  Stream<List<MessageTypingState>> watchTyping({
    required String conversationId,
    required String userUid,
  }) async* {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String uid = _requireAuthenticatedUid(userUid);

    await _requireParticipant(conversationId: conversation, userUid: uid);

    yield* _typingCollection(conversation).snapshots().map((
      QuerySnapshot<Map<String, Object?>> snapshot,
    ) {
      final List<MessageTypingState> states = <MessageTypingState>[];

      for (final QueryDocumentSnapshot<Map<String, Object?>> document
          in snapshot.docs) {
        if (document.id == uid) {
          continue;
        }

        final MessageTypingState? state = _typingFromSnapshot(
          document,
          conversationId: conversation,
        );

        if (state != null && state.isActive) {
          states.add(state);
        }
      }

      return List<MessageTypingState>.unmodifiable(states);
    });
  }

  // --------------------------------------------------------------------------
  // LIVE CHAT
  // --------------------------------------------------------------------------

  Future<void> setLiveDraft({
    required String conversationId,
    required String senderUid,
    required String sessionId,
    required int version,
    required String text,
    required int styleSeed,
    required DateTime expiresAt,
    required bool active,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String sender = _requireAuthenticatedUid(senderUid);

    final String session = _normalizeId(sessionId, fieldName: 'sessionId');

    if (version < 0) {
      throw ArgumentError.value(
        version,
        'version',
        'Live Chat version cannot be negative.',
      );
    }

    await _requireParticipant(conversationId: conversation, userUid: sender);

    await _liveReference(conversation, sender).set(<String, Object?>{
      'conversationId': conversation,
      'senderUid': sender,
      'sessionId': session,
      'version': version,
      'text': text,
      'styleSeed': styleSeed,
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt.toUtc()),
      'active': active,
    }, SetOptions(merge: true));
  }

  Future<void> clearLiveDraft({
    required String conversationId,
    required String senderUid,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String sender = _requireAuthenticatedUid(senderUid);

    await _liveReference(conversation, sender).delete();
  }

  Stream<List<MessageLiveDraftState>> watchLiveDrafts({
    required String conversationId,
    required String userUid,
  }) async* {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String uid = _requireAuthenticatedUid(userUid);

    await _requireParticipant(conversationId: conversation, userUid: uid);

    yield* _liveCollection(conversation).snapshots().map((
      QuerySnapshot<Map<String, Object?>> snapshot,
    ) {
      final List<MessageLiveDraftState> drafts = <MessageLiveDraftState>[];

      for (final QueryDocumentSnapshot<Map<String, Object?>> document
          in snapshot.docs) {
        if (document.id == uid) {
          continue;
        }

        final MessageLiveDraftState? draft = _liveFromSnapshot(
          document,
          conversationId: conversation,
        );

        if (draft != null && draft.isActive) {
          drafts.add(draft);
        }
      }

      drafts.sort(
        (MessageLiveDraftState a, MessageLiveDraftState b) =>
            a.senderUid.compareTo(b.senderUid),
      );

      return List<MessageLiveDraftState>.unmodifiable(drafts);
    });
  }

  // --------------------------------------------------------------------------
  // DELIVERY RECEIPT
  // --------------------------------------------------------------------------

  Future<void> markDelivered({
    required String conversationId,
    required String userUid,
    required String messageId,
    required DateTime messageCreatedAt,
  }) {
    return _advanceReceipt(
      conversationId: conversationId,
      userUid: userUid,
      messageId: messageId,
      messageCreatedAt: messageCreatedAt,
      read: false,
    );
  }

  // --------------------------------------------------------------------------
  // READ RECEIPT
  // --------------------------------------------------------------------------

  Future<void> markRead({
    required String conversationId,
    required String userUid,
    required String messageId,
    required DateTime messageCreatedAt,
  }) async {
    await _advanceReceipt(
      conversationId: conversationId,
      userUid: userUid,
      messageId: messageId,
      messageCreatedAt: messageCreatedAt,
      read: true,
    );

    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String uid = _requireAuthenticatedUid(userUid);

    final DocumentReference<Map<String, Object?>> conversationRef =
        _conversations.doc(conversation);

    await _firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, Object?>> snapshot = await transaction
          .get(conversationRef);

      if (!snapshot.exists) {
        throw StateError('Conversation does not exist.');
      }

      final Map<String, Object?> data = snapshot.data() ?? <String, Object?>{};

      _requireParticipantData(data, uid);

      final Map<String, int> unreadCounts = _readIntMap(data['unreadCounts']);

      unreadCounts[uid] = 0;

      transaction.update(conversationRef, <String, Object?>{
        'unreadCounts': unreadCounts,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<List<MessageReceiptState>> watchReceipts({
    required String conversationId,
    required String userUid,
  }) async* {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String uid = _requireAuthenticatedUid(userUid);

    await _requireParticipant(conversationId: conversation, userUid: uid);

    yield* _receiptsCollection(conversation).snapshots().map(
      (QuerySnapshot<Map<String, Object?>> snapshot) =>
          List<MessageReceiptState>.unmodifiable(
            snapshot.docs.map(
              (QueryDocumentSnapshot<Map<String, Object?>> document) =>
                  _receiptFromSnapshot(document, conversationId: conversation),
            ),
          ),
    );
  }

  // --------------------------------------------------------------------------
  // REACTIONS
  // --------------------------------------------------------------------------

  Future<void> setReaction(ReactionEntity reaction) async {
    final String uid = _requireAuthenticatedUid(reaction.userUid);

    await _requireParticipant(
      conversationId: reaction.conversationId,
      userUid: uid,
    );

    await _reactionReference(
      reaction.conversationId,
      reaction.messageId,
      uid,
    ).set(reaction.toMap());
  }

  Future<void> removeReaction({
    required String conversationId,
    required String messageId,
    required String userUid,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizeId(messageId, fieldName: 'messageId');

    final String uid = _requireAuthenticatedUid(userUid);

    await _requireParticipant(conversationId: conversation, userUid: uid);

    await _reactionReference(conversation, message, uid).delete();
  }

  Stream<List<ReactionEntity>> watchReactions({
    required String conversationId,
    required String messageId,
    required String userUid,
  }) async* {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizeId(messageId, fieldName: 'messageId');

    final String uid = _requireAuthenticatedUid(userUid);

    await _requireParticipant(conversationId: conversation, userUid: uid);

    yield* _reactionsCollection(conversation, message).snapshots().map(
      (QuerySnapshot<Map<String, Object?>> snapshot) =>
          List<ReactionEntity>.unmodifiable(
            snapshot.docs.map(
              (QueryDocumentSnapshot<Map<String, Object?>> document) =>
                  ReactionEntity.fromMap(<String, Object?>{
                    ...document.data(),
                    'messageId': message,
                    'conversationId': conversation,
                  }, userUid: document.id),
            ),
          ),
    );
  }

  // --------------------------------------------------------------------------
  // INTERNAL RECEIPT TRANSACTION
  // --------------------------------------------------------------------------

  Future<void> _advanceReceipt({
    required String conversationId,
    required String userUid,
    required String messageId,
    required DateTime messageCreatedAt,
    required bool read,
  }) async {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String uid = _requireAuthenticatedUid(userUid);

    final String message = _normalizeId(messageId, fieldName: 'messageId');

    final DateTime boundary = messageCreatedAt.toUtc();

    final DocumentReference<Map<String, Object?>> conversationRef =
        _conversations.doc(conversation);

    final DocumentReference<Map<String, Object?>> messageRef =
        _messageReference(conversation, message);

    final DocumentReference<Map<String, Object?>> receiptRef =
        _receiptReference(conversation, uid);

    await _firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, Object?>> conversationSnapshot =
          await transaction.get(conversationRef);

      final DocumentSnapshot<Map<String, Object?>> messageSnapshot =
          await transaction.get(messageRef);

      final DocumentSnapshot<Map<String, Object?>> receiptSnapshot =
          await transaction.get(receiptRef);

      if (!conversationSnapshot.exists) {
        throw StateError('Conversation does not exist.');
      }

      if (!messageSnapshot.exists) {
        throw StateError('Message does not exist.');
      }

      final Map<String, Object?> conversationData =
          conversationSnapshot.data() ?? <String, Object?>{};

      final Map<String, Object?> messageData =
          messageSnapshot.data() ?? <String, Object?>{};

      _requireParticipantData(conversationData, uid);

      if (_readString(messageData['senderUid']) == uid) {
        throw StateError(
          'A sender cannot acknowledge delivery/read of their own message.',
        );
      }

      final Map<String, Object?> existing =
          receiptSnapshot.data() ?? <String, Object?>{};

      final DateTime? currentDelivered = _optionalDateTime(
        existing['deliveredThroughAt'],
      );

      final DateTime? currentRead = _optionalDateTime(
        existing['readThroughAt'],
      );

      final Map<String, Object?> update = <String, Object?>{
        'conversationId': conversation,
        'userUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (currentDelivered == null || boundary.isAfter(currentDelivered)) {
        update['deliveredMessageId'] = message;
        update['deliveredThroughAt'] = Timestamp.fromDate(boundary);
      }

      if (read && (currentRead == null || boundary.isAfter(currentRead))) {
        update['readMessageId'] = message;
        update['readThroughAt'] = Timestamp.fromDate(boundary);

        // Read necessarily confirms real delivery too.
        if (currentDelivered == null || boundary.isAfter(currentDelivered)) {
          update['deliveredMessageId'] = message;
          update['deliveredThroughAt'] = Timestamp.fromDate(boundary);
        }
      }

      transaction.set(receiptRef, update, SetOptions(merge: true));
    });
  }

  // --------------------------------------------------------------------------
  // FIRESTORE REFERENCES
  // --------------------------------------------------------------------------

  CollectionReference<Map<String, Object?>> _messagesReference(
    String conversationId,
  ) {
    return _conversations.doc(conversationId).collection(messagesCollection);
  }

  DocumentReference<Map<String, Object?>> _messageReference(
    String conversationId,
    String messageId,
  ) {
    return _messagesReference(conversationId).doc(messageId);
  }

  CollectionReference<Map<String, Object?>> _typingCollection(
    String conversationId,
  ) {
    return _conversations.doc(conversationId).collection(typingCollection);
  }

  DocumentReference<Map<String, Object?>> _typingReference(
    String conversationId,
    String uid,
  ) {
    return _typingCollection(conversationId).doc(uid);
  }

  CollectionReference<Map<String, Object?>> _liveCollection(
    String conversationId,
  ) {
    return _conversations.doc(conversationId).collection(liveCollection);
  }

  DocumentReference<Map<String, Object?>> _liveReference(
    String conversationId,
    String uid,
  ) {
    return _liveCollection(conversationId).doc(uid);
  }

  CollectionReference<Map<String, Object?>> _receiptsCollection(
    String conversationId,
  ) {
    return _conversations.doc(conversationId).collection(receiptsCollection);
  }

  DocumentReference<Map<String, Object?>> _receiptReference(
    String conversationId,
    String uid,
  ) {
    return _receiptsCollection(conversationId).doc(uid);
  }

  CollectionReference<Map<String, Object?>> _reactionsCollection(
    String conversationId,
    String messageId,
  ) {
    return _messageReference(
      conversationId,
      messageId,
    ).collection(reactionsCollection);
  }

  DocumentReference<Map<String, Object?>> _reactionReference(
    String conversationId,
    String messageId,
    String uid,
  ) {
    return _reactionsCollection(conversationId, messageId).doc(uid);
  }

  // --------------------------------------------------------------------------
  // AUTH / PARTICIPANT INVARIANTS
  // --------------------------------------------------------------------------

  String _requireAuthenticatedUid(String requestedUid) {
    final String uid = _normalizeId(requestedUid, fieldName: 'userUid');

    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('Authentication is required for JR CALL messaging.');
    }

    if (user.uid != uid) {
      throw StateError(
        'Authenticated Firebase UID does not match requested message identity.',
      );
    }

    return uid;
  }

  Future<void> _requireParticipant({
    required String conversationId,
    required String userUid,
  }) async {
    final DocumentSnapshot<Map<String, Object?>> snapshot = await _conversations
        .doc(conversationId)
        .get();

    if (!snapshot.exists) {
      throw StateError('Conversation does not exist.');
    }

    _requireParticipantData(snapshot.data() ?? <String, Object?>{}, userUid);
  }

  static void _requireParticipantData(
    Map<String, Object?> conversationData,
    String uid,
  ) {
    final List<String> participants = _readStringList(
      conversationData['participantUids'],
    );

    if (!participants.contains(uid)) {
      throw StateError(
        'Firebase UID is not a participant of this conversation.',
      );
    }
  }

  // --------------------------------------------------------------------------
  // SERIALIZATION
  // --------------------------------------------------------------------------

  static Map<String, Object?> _durableMessageMap(MessageEntity message) {
    final Map<String, Object?> data = Map<String, Object?>.from(
      message.toMap(),
    );

    data
      ..['id'] = message.id
      ..['conversationId'] = message.conversationId
      ..['senderUid'] = message.senderUid
      ..['type'] = message.type.serialized
      ..['status'] = MessageStatus.sent.serialized
      ..['clientCreatedAt'] = Timestamp.fromDate(
        message.clientCreatedAt.toUtc(),
      )
      ..['serverCreatedAt'] = FieldValue.serverTimestamp();

    // Local-only execution/retry information must not become durable message
    // history.
    data.remove('localOnly');
    data.remove('optimistic');
    data.remove('isOptimistic');
    data.remove('failure');
    data.remove('failureCode');
    data.remove('failureMessage');
    data.remove('localError');

    return data;
  }

  static MessageEntity _messageFromSnapshot(
    DocumentSnapshot<Map<String, Object?>> snapshot, {
    required String conversationId,
  }) {
    final Map<String, Object?> data = snapshot.data() ?? <String, Object?>{};

    return MessageEntity.fromMap(<String, Object?>{
      ...data,
      'id': snapshot.id,
      'conversationId': conversationId,
    });
  }

  static ConversationEntity _conversationFromSnapshot(
    DocumentSnapshot<Map<String, Object?>> snapshot,
  ) {
    return ConversationEntity.fromMap(<String, Object?>{
      ...?snapshot.data(),
      'id': snapshot.id,
    });
  }

  static MessageTypingState? _typingFromSnapshot(
    DocumentSnapshot<Map<String, Object?>> snapshot, {
    required String conversationId,
  }) {
    final Map<String, Object?> data = snapshot.data() ?? <String, Object?>{};

    final DateTime? updatedAt = _optionalDateTime(data['updatedAt']);

    final DateTime? expiresAt = _optionalDateTime(data['expiresAt']);

    if (updatedAt == null || expiresAt == null) {
      return null;
    }

    return MessageTypingState(
      conversationId: conversationId,
      userUid: snapshot.id,
      isTyping: data['isTyping'] == true,
      updatedAt: updatedAt,
      expiresAt: expiresAt,
    );
  }

  static MessageLiveDraftState? _liveFromSnapshot(
    DocumentSnapshot<Map<String, Object?>> snapshot, {
    required String conversationId,
  }) {
    final Map<String, Object?> data = snapshot.data() ?? <String, Object?>{};

    final String? sessionId = _readNullableString(data['sessionId']);

    final DateTime? updatedAt = _optionalDateTime(data['updatedAt']);

    final DateTime? expiresAt = _optionalDateTime(data['expiresAt']);

    if (sessionId == null || updatedAt == null || expiresAt == null) {
      return null;
    }

    return MessageLiveDraftState(
      conversationId: conversationId,
      senderUid: snapshot.id,
      sessionId: sessionId,
      version: _readInt(data['version']),
      text: _readString(data['text']),
      styleSeed: _readInt(data['styleSeed']),
      updatedAt: updatedAt,
      expiresAt: expiresAt,
      active: data['active'] == true,
    );
  }

  static MessageReceiptState _receiptFromSnapshot(
    DocumentSnapshot<Map<String, Object?>> snapshot, {
    required String conversationId,
  }) {
    final Map<String, Object?> data = snapshot.data() ?? <String, Object?>{};

    return MessageReceiptState(
      conversationId: conversationId,
      userUid: snapshot.id,
      deliveredMessageId: _readNullableString(data['deliveredMessageId']),
      deliveredThroughAt: _optionalDateTime(data['deliveredThroughAt']),
      readMessageId: _readNullableString(data['readMessageId']),
      readThroughAt: _optionalDateTime(data['readThroughAt']),
      updatedAt: _optionalDateTime(data['updatedAt']),
    );
  }

  // --------------------------------------------------------------------------
  // PREVIEW / ORDERING
  // --------------------------------------------------------------------------

  static String _messagePreview(MessageEntity message) {
    if (message.type == MessageType.text) {
      final String text = (message.text ?? '').trim();

      if (text.isNotEmpty) {
        return _truncatePreview(text);
      }
    }

    return message.type.previewLabel;
  }

  static String _truncatePreview(String value, {int maxLength = 160}) {
    final String normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (normalized.length <= maxLength) {
      return normalized;
    }

    return '${normalized.substring(0, maxLength - 1)}…';
  }

  static int _compareMessages(MessageEntity first, MessageEntity second) {
    final DateTime firstTime = (first.serverCreatedAt ?? first.clientCreatedAt)
        .toUtc();

    final DateTime secondTime =
        (second.serverCreatedAt ?? second.clientCreatedAt).toUtc();

    final int timeComparison = firstTime.compareTo(secondTime);

    if (timeComparison != 0) {
      return timeComparison;
    }

    return first.id.compareTo(second.id);
  }

  // --------------------------------------------------------------------------
  // VALUE HELPERS
  // --------------------------------------------------------------------------

  static String _normalizeId(String value, {required String fieldName}) {
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

  static String _readString(Object? value) {
    return value is String ? value.trim() : '';
  }

  static String? _readNullableString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return 0;
  }

  static List<String> _readStringList(Object? value) {
    if (value is! Iterable<Object?>) {
      return <String>[];
    }

    return value
        .whereType<String>()
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toSet()
        .toList(growable: true);
  }

  static Map<String, int> _readIntMap(Object? value) {
    final Map<String, int> result = <String, int>{};

    if (value is! Map<Object?, Object?>) {
      return result;
    }

    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        continue;
      }

      final String key = (entry.key! as String).trim();

      if (key.isEmpty) {
        continue;
      }

      final Object? count = entry.value;

      if (count is int) {
        result[key] = count < 0 ? 0 : count;
      } else if (count is num) {
        final int converted = count.toInt();
        result[key] = converted < 0 ? 0 : converted;
      }
    }

    return result;
  }

  static DateTime _requiredDateTime(
    Object? value, {
    required String fieldName,
  }) {
    final DateTime? date = _optionalDateTime(value);

    if (date == null) {
      throw FormatException('Missing or invalid $fieldName timestamp.');
    }

    return date;
  }

  static DateTime? _optionalDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }

    if (value is DateTime) {
      return value.toUtc();
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }

    return null;
  }

  static bool _sameStringList(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }

    for (int index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }

    return true;
  }

  static void _validateLimit(int limit) {
    if (limit <= 0 || limit > 200) {
      throw ArgumentError.value(
        limit,
        'limit',
        'limit must be between 1 and 200.',
      );
    }
  }
}

// ============================================================================
// END OF FILE: lib/features/message/storage/message_remote_store.dart
// ============================================================================
