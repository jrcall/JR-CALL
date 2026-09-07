// ============================================================================
// JR CALL
// File: message_composer_controller.dart
// Location: lib/features/message/controller/message_composer_controller.dart
// Description:
// UI-facing state owner for the JR CALL durable message composer.
//
// Owns:
// - Composer text.
// - Reply target.
// - Edit target.
// - Selected attachment metadata.
// - Sending lock.
// - Typing state lifecycle.
// - Throttled typing publication.
// - JR CALL Live Chat enabled state.
// - Throttled Live Chat draft publication.
// - Live Chat session/version/style identity.
// - Composer clear/reset lifecycle.
// - Timer cancellation and disposal safety.
//
// Does NOT:
// - Call Firestore directly.
// - Call Firebase Storage directly.
// - Render particle/butterfly animation.
// - Invent message delivery/read state.
// - Own authentication credentials.
// - Recreate Call Engine/WebRTC.
// ============================================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/attachment_entity.dart';
import '../data/message_entity.dart';

/// Composer attachment action selected by presentation.
///
/// Actual picker/permission/media preparation remains outside this controller.
enum MessageComposerAttachmentAction { image, video, audio, voice, file }

/// Current composer operating mode.
enum MessageComposerMode { compose, reply, edit }

/// Immutable live-draft payload emitted by [MessageComposerController].
///
/// This is ephemeral state only and must never be persisted as a durable
/// MessageEntity.
@immutable
final class MessageComposerLiveDraft {
  const MessageComposerLiveDraft({
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

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'conversationId': conversationId,
      'senderUid': senderUid,
      'sessionId': sessionId,
      'version': version,
      'text': text,
      'styleSeed': styleSeed,
      'updatedAt': updatedAt.toUtc(),
      'expiresAt': expiresAt.toUtc(),
      'active': active,
    };
  }

  MessageComposerLiveDraft copyWith({
    String? conversationId,
    String? senderUid,
    String? sessionId,
    int? version,
    String? text,
    int? styleSeed,
    DateTime? updatedAt,
    DateTime? expiresAt,
    bool? active,
  }) {
    return MessageComposerLiveDraft(
      conversationId: conversationId ?? this.conversationId,
      senderUid: senderUid ?? this.senderUid,
      sessionId: sessionId ?? this.sessionId,
      version: version ?? this.version,
      text: text ?? this.text,
      styleSeed: styleSeed ?? this.styleSeed,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      active: active ?? this.active,
    );
  }
}

/// Immutable typing publication payload.
@immutable
final class MessageComposerTypingState {
  const MessageComposerTypingState({
    required this.conversationId,
    required this.senderUid,
    required this.isTyping,
    required this.updatedAt,
    required this.expiresAt,
  });

  final String conversationId;
  final String senderUid;
  final bool isTyping;
  final DateTime updatedAt;
  final DateTime expiresAt;
}

/// Immutable durable-send request produced by the composer.
///
/// The repository/engine remains responsible for creating/persisting the final
/// canonical MessageEntity and assigning its durable status lifecycle.
@immutable
final class MessageComposerSendRequest {
  const MessageComposerSendRequest({
    required this.conversationId,
    required this.senderUid,
    required this.text,
    required this.attachments,
    required this.replyToMessageId,
    required this.editMessageId,
  });

  final String conversationId;
  final String senderUid;
  final String text;
  final List<AttachmentEntity> attachments;
  final String? replyToMessageId;
  final String? editMessageId;

  bool get isEdit => editMessageId != null;

  bool get isReply => replyToMessageId != null && editMessageId == null;

  bool get hasContent => text.trim().isNotEmpty || attachments.isNotEmpty;
}

/// Required integration boundary for composer actions.
///
/// Presentation/controller code can bind these operations to FILE 35
/// MessageRepository without allowing this controller to access Firestore or
/// Firebase Storage directly.
abstract interface class MessageComposerDelegate {
  Future<void> publishTyping(MessageComposerTypingState state);

  Future<void> publishLiveDraft(MessageComposerLiveDraft draft);

  Future<void> clearLiveDraft({
    required String conversationId,
    required String senderUid,
    required String sessionId,
    required int version,
  });

  Future<MessageEntity> sendComposerRequest(MessageComposerSendRequest request);
}

/// Immutable UI-facing composer state.
@immutable
final class MessageComposerState {
  const MessageComposerState({
    required this.text,
    required this.replyTarget,
    required this.editTarget,
    required this.attachments,
    required this.attachmentAction,
    required this.liveChatEnabled,
    required this.isTyping,
    required this.isSending,
    required this.liveVersion,
    required this.errorMessage,
  });

  const MessageComposerState.initial()
    : text = '',
      replyTarget = null,
      editTarget = null,
      attachments = const <AttachmentEntity>[],
      attachmentAction = null,
      liveChatEnabled = false,
      isTyping = false,
      isSending = false,
      liveVersion = 0,
      errorMessage = null;

  final String text;
  final MessageEntity? replyTarget;
  final MessageEntity? editTarget;
  final List<AttachmentEntity> attachments;
  final MessageComposerAttachmentAction? attachmentAction;
  final bool liveChatEnabled;
  final bool isTyping;
  final bool isSending;
  final int liveVersion;

  /// Safe UI-facing error only.
  final String? errorMessage;

  MessageComposerMode get mode {
    if (editTarget != null) {
      return MessageComposerMode.edit;
    }

    if (replyTarget != null) {
      return MessageComposerMode.reply;
    }

    return MessageComposerMode.compose;
  }

  bool get hasText => text.trim().isNotEmpty;

  bool get hasAttachments => attachments.isNotEmpty;

  bool get hasContent => hasText || hasAttachments;

  bool get canSend => hasContent && !isSending;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  MessageComposerState copyWith({
    String? text,
    MessageEntity? replyTarget,
    bool clearReplyTarget = false,
    MessageEntity? editTarget,
    bool clearEditTarget = false,
    List<AttachmentEntity>? attachments,
    MessageComposerAttachmentAction? attachmentAction,
    bool clearAttachmentAction = false,
    bool? liveChatEnabled,
    bool? isTyping,
    bool? isSending,
    int? liveVersion,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MessageComposerState(
      text: text ?? this.text,
      replyTarget: clearReplyTarget ? null : replyTarget ?? this.replyTarget,
      editTarget: clearEditTarget ? null : editTarget ?? this.editTarget,
      attachments: attachments ?? this.attachments,
      attachmentAction: clearAttachmentAction
          ? null
          : attachmentAction ?? this.attachmentAction,
      liveChatEnabled: liveChatEnabled ?? this.liveChatEnabled,
      isTyping: isTyping ?? this.isTyping,
      isSending: isSending ?? this.isSending,
      liveVersion: liveVersion ?? this.liveVersion,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// JR CALL chat composer controller.
final class MessageComposerController extends ChangeNotifier {
  MessageComposerController({
    required this._delegate,
    required String currentUserUid,
    required String conversationId,
    Duration typingThrottle = const Duration(milliseconds: 850),
    Duration typingIdleTimeout = const Duration(seconds: 4),
    Duration liveDraftThrottle = const Duration(milliseconds: 450),
    Duration liveDraftBaseLifetime = const Duration(seconds: 7),
    Duration liveDraftMaximumLifetime = const Duration(seconds: 15),
  }) : currentUserUid = currentUserUid.trim(),
       conversationId = conversationId.trim(),
       typingThrottle = typingThrottle,
       typingIdleTimeout = typingIdleTimeout,
       liveDraftThrottle = liveDraftThrottle,
       liveDraftBaseLifetime = liveDraftBaseLifetime,
       liveDraftMaximumLifetime = liveDraftMaximumLifetime {
    if (this.currentUserUid.isEmpty) {
      throw ArgumentError.value(
        currentUserUid,
        'currentUserUid',
        'Firebase UID must not be empty.',
      );
    }

    if (this.conversationId.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'Conversation ID must not be empty.',
      );
    }

    if (typingThrottle <= Duration.zero) {
      throw ArgumentError.value(
        typingThrottle,
        'typingThrottle',
        'Typing throttle must be greater than zero.',
      );
    }

    if (typingIdleTimeout <= Duration.zero) {
      throw ArgumentError.value(
        typingIdleTimeout,
        'typingIdleTimeout',
        'Typing idle timeout must be greater than zero.',
      );
    }

    if (liveDraftThrottle <= Duration.zero) {
      throw ArgumentError.value(
        liveDraftThrottle,
        'liveDraftThrottle',
        'Live draft throttle must be greater than zero.',
      );
    }

    if (liveDraftBaseLifetime <= Duration.zero) {
      throw ArgumentError.value(
        liveDraftBaseLifetime,
        'liveDraftBaseLifetime',
        'Live draft lifetime must be greater than zero.',
      );
    }

    if (liveDraftMaximumLifetime < liveDraftBaseLifetime) {
      throw ArgumentError.value(
        liveDraftMaximumLifetime,
        'liveDraftMaximumLifetime',
        'Maximum live lifetime cannot be shorter than base lifetime.',
      );
    }

    _startNewLiveSession();
  }

  final MessageComposerDelegate _delegate;

  final String currentUserUid;
  final String conversationId;

  final Duration typingThrottle;
  final Duration typingIdleTimeout;
  final Duration liveDraftThrottle;
  final Duration liveDraftBaseLifetime;
  final Duration liveDraftMaximumLifetime;

  MessageComposerState _state = const MessageComposerState.initial();

  Timer? _typingThrottleTimer;
  Timer? _typingIdleTimer;
  Timer? _liveDraftThrottleTimer;

  DateTime? _lastTypingPublishAt;
  DateTime? _lastLivePublishAt;

  String? _pendingLiveText;

  late String _liveSessionId;
  late int _liveStyleSeed;

  int _liveVersion = 0;

  bool _disposed = false;
  bool _typingPublishInFlight = false;
  bool _livePublishInFlight = false;
  bool _sending = false;

  MessageComposerState get state => _state;

  String get text => _state.text;

  MessageEntity? get replyTarget => _state.replyTarget;

  MessageEntity? get editTarget => _state.editTarget;

  List<AttachmentEntity> get attachments => _state.attachments;

  MessageComposerAttachmentAction? get attachmentAction =>
      _state.attachmentAction;

  bool get liveChatEnabled => _state.liveChatEnabled;

  bool get isTyping => _state.isTyping;

  bool get isSending => _state.isSending;

  bool get canSend => _state.canSend;

  bool get isDisposed => _disposed;

  String? get errorMessage => _state.errorMessage;

  String get liveSessionId => _liveSessionId;

  int get liveStyleSeed => _liveStyleSeed;

  int get liveVersion => _liveVersion;

  /// Applies composer text and schedules real typing/live publications.
  void setText(String value) {
    _ensureNotDisposed();

    if (_state.isSending) {
      return;
    }

    if (_state.text == value) {
      return;
    }

    _setState(_state.copyWith(text: value, clearError: true));

    final bool containsText = value.trim().isNotEmpty;

    if (containsText) {
      _beginTyping();
    } else {
      unawaited(_stopTyping());

      if (_state.liveChatEnabled) {
        unawaited(_clearLiveDraftInternal());
      }
    }

    if (_state.liveChatEnabled) {
      _scheduleLiveDraft(value);
    }
  }

  /// Starts reply mode for one canonical timeline item.
  void setReplyTarget(MessageEntity? message) {
    _ensureNotDisposed();

    if (_state.isSending) {
      return;
    }

    if (message == null) {
      clearReplyTarget();
      return;
    }

    _assertConversationMessage(message);

    _setState(
      _state.copyWith(
        replyTarget: message,
        clearEditTarget: true,
        clearError: true,
      ),
    );
  }

  void clearReplyTarget() {
    _ensureNotDisposed();

    if (_state.replyTarget == null) {
      return;
    }

    _setState(_state.copyWith(clearReplyTarget: true));
  }

  /// Starts edit mode while preserving the canonical original message ID.
  void setEditTarget(MessageEntity? message) {
    _ensureNotDisposed();

    if (_state.isSending) {
      return;
    }

    if (message == null) {
      clearEditTarget();
      return;
    }

    _assertConversationMessage(message);

    if (message.senderUid != currentUserUid) {
      _setError('You can only edit your own message.');
      return;
    }

    if (message.deletedAt != null) {
      _setError('Deleted messages cannot be edited.');
      return;
    }

    _setState(
      _state.copyWith(
        text: message.text ?? '',
        editTarget: message,
        clearReplyTarget: true,
        attachments: const <AttachmentEntity>[],
        clearAttachmentAction: true,
        clearError: true,
      ),
    );

    if (_state.liveChatEnabled) {
      _scheduleLiveDraft(_state.text);
    }
  }

  void clearEditTarget({bool clearText = false}) {
    _ensureNotDisposed();

    if (_state.editTarget == null) {
      return;
    }

    _setState(
      _state.copyWith(
        text: clearText ? '' : _state.text,
        clearEditTarget: true,
      ),
    );
  }

  /// Presentation uses this only to report which attachment option was chosen.
  void selectAttachmentAction(MessageComposerAttachmentAction? action) {
    _ensureNotDisposed();

    if (_state.isSending) {
      return;
    }

    _setState(
      _state.copyWith(
        attachmentAction: action,
        clearAttachmentAction: action == null,
        clearError: true,
      ),
    );
  }

  /// Adds already prepared/validated attachment metadata.
  ///
  /// Binary picking/upload logic remains in the media/repository layer.
  void addAttachment(AttachmentEntity attachment) {
    _ensureNotDisposed();

    if (_state.isSending) {
      return;
    }

    if (_state.editTarget != null) {
      _setError('Attachments cannot be added while editing this message.');
      return;
    }

    _assertAttachmentOwnership(attachment);

    final Map<String, AttachmentEntity> unique = <String, AttachmentEntity>{
      for (final AttachmentEntity item in _state.attachments) item.id: item,
      attachment.id: attachment,
    };

    _setState(
      _state.copyWith(
        attachments: List<AttachmentEntity>.unmodifiable(unique.values),
        clearAttachmentAction: true,
        clearError: true,
      ),
    );
  }

  void addAttachments(Iterable<AttachmentEntity> attachments) {
    _ensureNotDisposed();

    for (final AttachmentEntity attachment in attachments) {
      addAttachment(attachment);
    }
  }

  void removeAttachment(String attachmentId) {
    _ensureNotDisposed();

    if (_state.isSending) {
      return;
    }

    final String normalizedId = attachmentId.trim();

    if (normalizedId.isEmpty) {
      return;
    }

    final List<AttachmentEntity> updated = _state.attachments
        .where((AttachmentEntity item) => item.id != normalizedId)
        .toList(growable: false);

    if (updated.length == _state.attachments.length) {
      return;
    }

    _setState(
      _state.copyWith(
        attachments: List<AttachmentEntity>.unmodifiable(updated),
      ),
    );
  }

  void clearAttachments() {
    _ensureNotDisposed();

    if (_state.attachments.isEmpty && _state.attachmentAction == null) {
      return;
    }

    _setState(
      _state.copyWith(
        attachments: const <AttachmentEntity>[],
        clearAttachmentAction: true,
      ),
    );
  }

  /// Enables/disables JR CALL Live Chat.
  ///
  /// Disabling immediately clears the authenticated user's ephemeral remote
  /// live draft.
  Future<void> setLiveChatEnabled(bool enabled) async {
    _ensureNotDisposed();

    if (_state.liveChatEnabled == enabled) {
      return;
    }

    if (!enabled) {
      _cancelLiveDraftTimer();

      _setState(_state.copyWith(liveChatEnabled: false));

      await _clearLiveDraftInternal();
      _startNewLiveSession();
      return;
    }

    _startNewLiveSession();

    _setState(_state.copyWith(liveChatEnabled: true, clearError: true));

    if (_state.text.trim().isNotEmpty) {
      _scheduleLiveDraft(_state.text);
    }
  }

  /// Sends the current composer payload once.
  ///
  /// Rapid repeated taps are ignored while a send is in progress.
  Future<MessageEntity?> send() async {
    _ensureNotDisposed();

    if (_sending || !_state.hasContent) {
      return null;
    }

    if (_state.editTarget != null && _state.attachments.isNotEmpty) {
      _setError('Attachments cannot be added while editing this message.');
      return null;
    }

    _sending = true;

    _setState(_state.copyWith(isSending: true, clearError: true));

    final String normalizedText = _normalizeComposerText(_state.text);

    final MessageComposerSendRequest request = MessageComposerSendRequest(
      conversationId: conversationId,
      senderUid: currentUserUid,
      text: normalizedText,
      attachments: List<AttachmentEntity>.unmodifiable(_state.attachments),
      replyToMessageId: _state.editTarget == null
          ? _state.replyTarget?.id
          : null,
      editMessageId: _state.editTarget?.id,
    );

    if (!request.hasContent) {
      _sending = false;

      _setState(_state.copyWith(isSending: false));

      return null;
    }

    try {
      await _stopTyping();

      if (_state.liveChatEnabled) {
        await _clearLiveDraftInternal();
      }

      final MessageEntity sent = await _delegate.sendComposerRequest(request);

      if (_disposed) {
        return sent;
      }

      await _clearAfterSuccessfulSend();

      return sent;
    } catch (_) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            isSending: false,
            errorMessage: 'Unable to send message.',
          ),
        );
      }

      return null;
    } finally {
      _sending = false;

      if (!_disposed && _state.isSending) {
        _setState(_state.copyWith(isSending: false));
      }
    }
  }

  /// Clears composer content and all ephemeral typing/live state.
  Future<void> clear() async {
    _ensureNotDisposed();

    _cancelTypingTimers();
    _cancelLiveDraftTimer();

    await _stopTyping(forcePublish: true);

    if (_state.liveChatEnabled) {
      await _clearLiveDraftInternal();
    }

    if (_disposed) {
      return;
    }

    _startNewLiveSession();

    _setState(
      _state.copyWith(
        text: '',
        clearReplyTarget: true,
        clearEditTarget: true,
        attachments: const <AttachmentEntity>[],
        clearAttachmentAction: true,
        isTyping: false,
        liveVersion: _liveVersion,
        clearError: true,
      ),
    );
  }

  /// Call when the user leaves the conversation.
  Future<void> leaveConversation() async {
    _ensureNotDisposed();

    _cancelTypingTimers();
    _cancelLiveDraftTimer();

    await _stopTyping(forcePublish: true);

    if (_state.liveChatEnabled) {
      await _clearLiveDraftInternal();
    }

    if (_disposed) {
      return;
    }

    _setState(_state.copyWith(isTyping: false));
  }

  void clearError() {
    _ensureNotDisposed();

    if (!_state.hasError) {
      return;
    }

    _setState(_state.copyWith(clearError: true));
  }

  void _beginTyping() {
    if (_disposed) {
      return;
    }

    if (!_state.isTyping) {
      _setState(_state.copyWith(isTyping: true));
    }

    _scheduleTypingPublish();

    _typingIdleTimer?.cancel();

    _typingIdleTimer = Timer(typingIdleTimeout, () {
      if (_disposed) {
        return;
      }

      unawaited(_stopTyping());
    });
  }

  void _scheduleTypingPublish() {
    if (_disposed || _typingPublishInFlight) {
      return;
    }

    final DateTime now = DateTime.now().toUtc();
    final DateTime? previous = _lastTypingPublishAt;

    if (previous == null || now.difference(previous) >= typingThrottle) {
      unawaited(_publishTyping(true));
      return;
    }

    final Duration remaining = typingThrottle - now.difference(previous);

    _typingThrottleTimer?.cancel();

    _typingThrottleTimer = Timer(remaining, () {
      if (_disposed || !_state.isTyping) {
        return;
      }

      unawaited(_publishTyping(true));
    });
  }

  Future<void> _publishTyping(bool typing) async {
    if (_disposed || _typingPublishInFlight) {
      return;
    }

    _typingPublishInFlight = true;

    final DateTime now = DateTime.now().toUtc();

    final MessageComposerTypingState payload = MessageComposerTypingState(
      conversationId: conversationId,
      senderUid: currentUserUid,
      isTyping: typing,
      updatedAt: now,
      expiresAt: typing ? now.add(typingIdleTimeout) : now,
    );

    try {
      await _delegate.publishTyping(payload);

      if (!_disposed) {
        _lastTypingPublishAt = now;
      }
    } catch (_) {
      if (!_disposed) {
        _setError('Unable to update typing state.');
      }
    } finally {
      _typingPublishInFlight = false;
    }
  }

  Future<void> _stopTyping({bool forcePublish = false}) async {
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;

    _typingThrottleTimer?.cancel();
    _typingThrottleTimer = null;

    final bool wasTyping = _state.isTyping;

    if (!_disposed && wasTyping) {
      _setState(_state.copyWith(isTyping: false));
    }

    if (forcePublish || wasTyping) {
      await _publishTyping(false);
    }
  }

  void _scheduleLiveDraft(String rawText) {
    if (_disposed || !_state.liveChatEnabled) {
      return;
    }

    final String normalized = _normalizeLiveText(rawText);

    _pendingLiveText = normalized;

    if (normalized.isEmpty) {
      _cancelLiveDraftTimer();
      unawaited(_clearLiveDraftInternal());
      return;
    }

    final DateTime now = DateTime.now().toUtc();
    final DateTime? previous = _lastLivePublishAt;

    if (previous == null || now.difference(previous) >= liveDraftThrottle) {
      unawaited(_flushLiveDraft());
      return;
    }

    final Duration remaining = liveDraftThrottle - now.difference(previous);

    _liveDraftThrottleTimer?.cancel();

    _liveDraftThrottleTimer = Timer(remaining, () {
      if (_disposed || !_state.liveChatEnabled) {
        return;
      }

      unawaited(_flushLiveDraft());
    });
  }

  Future<void> _flushLiveDraft() async {
    if (_disposed || !_state.liveChatEnabled || _livePublishInFlight) {
      return;
    }

    final String text = _pendingLiveText?.trim() ?? '';

    if (text.isEmpty) {
      return;
    }

    _livePublishInFlight = true;
    _liveDraftThrottleTimer?.cancel();
    _liveDraftThrottleTimer = null;

    final DateTime now = DateTime.now().toUtc();
    final int version = ++_liveVersion;
    final Duration lifetime = _liveLifetimeForText(text);

    final MessageComposerLiveDraft draft = MessageComposerLiveDraft(
      conversationId: conversationId,
      senderUid: currentUserUid,
      sessionId: _liveSessionId,
      version: version,
      text: text,
      styleSeed: _liveStyleSeed,
      updatedAt: now,
      expiresAt: now.add(lifetime),
      active: true,
    );

    try {
      await _delegate.publishLiveDraft(draft);

      if (!_disposed) {
        _lastLivePublishAt = now;

        _setState(_state.copyWith(liveVersion: version, clearError: true));
      }
    } catch (_) {
      if (!_disposed) {
        _setError('Unable to update Live Chat.');
      }
    } finally {
      _livePublishInFlight = false;

      final String latest = _pendingLiveText?.trim() ?? '';

      if (!_disposed &&
          _state.liveChatEnabled &&
          latest.isNotEmpty &&
          latest != text) {
        _scheduleLiveDraft(latest);
      }
    }
  }

  Future<void> _clearLiveDraftInternal() async {
    _cancelLiveDraftTimer();

    _pendingLiveText = null;

    final int version = ++_liveVersion;

    try {
      await _delegate.clearLiveDraft(
        conversationId: conversationId,
        senderUid: currentUserUid,
        sessionId: _liveSessionId,
        version: version,
      );

      if (!_disposed) {
        _lastLivePublishAt = DateTime.now().toUtc();

        _setState(_state.copyWith(liveVersion: version));
      }
    } catch (_) {
      if (!_disposed) {
        _setError('Unable to clear Live Chat.');
      }
    }
  }

  Future<void> _clearAfterSuccessfulSend() async {
    _cancelTypingTimers();
    _cancelLiveDraftTimer();

    final bool keepLiveEnabled = _state.liveChatEnabled;

    _startNewLiveSession();

    _setState(
      _state.copyWith(
        text: '',
        clearReplyTarget: true,
        clearEditTarget: true,
        attachments: const <AttachmentEntity>[],
        clearAttachmentAction: true,
        liveChatEnabled: keepLiveEnabled,
        isTyping: false,
        isSending: false,
        liveVersion: _liveVersion,
        clearError: true,
      ),
    );
  }

  Duration _liveLifetimeForText(String text) {
    final int readableCharacters = text.runes.length;

    if (readableCharacters <= 80) {
      return liveDraftBaseLifetime;
    }

    final int additionalCharacters = readableCharacters - 80;

    final int extraMilliseconds = ((additionalCharacters / 20).ceil() * 500);

    final Duration calculated = Duration(
      milliseconds: liveDraftBaseLifetime.inMilliseconds + extraMilliseconds,
    );

    if (calculated > liveDraftMaximumLifetime) {
      return liveDraftMaximumLifetime;
    }

    return calculated;
  }

  String _normalizeComposerText(String value) {
    final String normalizedNewLines = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    return normalizedNewLines.trim();
  }

  String _normalizeLiveText(String value) {
    String result = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    result = result.trim();

    const int maxLiveRunes = 2000;

    if (result.runes.length <= maxLiveRunes) {
      return result;
    }

    return String.fromCharCodes(result.runes.take(maxLiveRunes));
  }

  void _assertConversationMessage(MessageEntity message) {
    if (message.id.trim().isEmpty) {
      throw ArgumentError.value(
        message.id,
        'message.id',
        'Message ID must not be empty.',
      );
    }

    if (message.conversationId != conversationId) {
      throw ArgumentError(
        'Message does not belong to the active conversation.',
      );
    }
  }

  void _assertAttachmentOwnership(AttachmentEntity attachment) {
    if (attachment.id.trim().isEmpty) {
      throw ArgumentError.value(
        attachment.id,
        'attachment.id',
        'Attachment ID must not be empty.',
      );
    }

    if (attachment.conversationId != conversationId) {
      throw ArgumentError(
        'Attachment does not belong to the active conversation.',
      );
    }

    if (attachment.ownerUid != currentUserUid) {
      throw ArgumentError(
        'Attachment owner must match the authenticated Firebase UID.',
      );
    }
  }

  void _startNewLiveSession() {
    final DateTime now = DateTime.now().toUtc();

    final int entropy = Random.secure().nextInt(0x7fffffff);

    _liveSessionId = '${currentUserUid}_${now.microsecondsSinceEpoch}_$entropy';

    _liveStyleSeed = Random.secure().nextInt(0x7fffffff);

    _liveVersion = 0;
    _lastLivePublishAt = null;
    _pendingLiveText = null;
  }

  void _cancelTypingTimers() {
    _typingThrottleTimer?.cancel();
    _typingThrottleTimer = null;

    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
  }

  void _cancelLiveDraftTimer() {
    _liveDraftThrottleTimer?.cancel();
    _liveDraftThrottleTimer = null;
  }

  void _setError(String message) {
    if (_disposed) {
      return;
    }

    _setState(_state.copyWith(errorMessage: message));
  }

  void _setState(MessageComposerState next) {
    if (_disposed) {
      return;
    }

    _state = next;
    notifyListeners();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MessageComposerController has already been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _cancelTypingTimers();
    _cancelLiveDraftTimer();

    if (_state.isTyping) {
      final DateTime now = DateTime.now().toUtc();

      unawaited(
        _delegate.publishTyping(
          MessageComposerTypingState(
            conversationId: conversationId,
            senderUid: currentUserUid,
            isTyping: false,
            updatedAt: now,
            expiresAt: now,
          ),
        ),
      );
    }

    if (_state.liveChatEnabled) {
      final int version = ++_liveVersion;

      unawaited(
        _delegate.clearLiveDraft(
          conversationId: conversationId,
          senderUid: currentUserUid,
          sessionId: _liveSessionId,
          version: version,
        ),
      );
    }

    super.dispose();
  }
}

// ============================================================================
// END OF FILE: lib/features/message/controller/message_composer_controller.dart
// ============================================================================
