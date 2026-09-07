// ============================================================================
// JR CALL
// File: chat_screen.dart
// Location: lib/features/message/presentation/chat_screen.dart
//
// FINAL PRODUCTION CHAT SCREEN
//
// PRESERVED:
// - Real MessageController lifecycle
// - Real MessageComposerController lifecycle
// - Real durable timeline
// - Real pagination
// - Real read acknowledgement boundary
// - Real send/retry/edit/delete/reaction callbacks
// - Real typing / Live Chat binding
// - Authentication protection
// - Existing Call handoff callbacks
// - Existing public constructor/API
//
// UI:
// - Premium JR CALL light design
// - Compact top chat header
// - Smaller upper navigation/action controls
// - Header moved visually upward
// - Existing Home bottom Message button untouched
//
// NO:
// - Demo messages
// - Fake conversation data
// - Fake delivery/read state
// - Firestore duplication
// - Call Engine/WebRTC duplication
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/message_composer_controller.dart';
import '../controller/message_controller.dart';
import '../data/message_entity.dart';

// ============================================================================
// PARTICIPANT VIEW DATA
// ============================================================================

@immutable
final class ChatParticipantViewData {
  const ChatParticipantViewData({
    required this.uid,
    required this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    this.isOnline = false,
    this.lastSeen,
  });

  final String uid;
  final String displayName;
  final String? avatarUrl;
  final bool isVerified;
  final bool isOnline;
  final DateTime? lastSeen;
}

// ============================================================================
// CHAT SNAPSHOT
// ============================================================================

@immutable
final class ChatScreenSnapshot {
  const ChatScreenSnapshot({
    required this.messages,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.isSending = false,
    this.errorMessage,
  });

  final List<MessageEntity> messages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isSending;
  final String? errorMessage;
}

// ============================================================================
// LIVE CHAT VIEW DATA
// ============================================================================

@immutable
final class ChatLiveViewData {
  const ChatLiveViewData({
    required this.isPeerTyping,
    required this.liveChatEnabled,
    this.liveText,
    this.liveSessionId,
    this.liveVersion,
    this.styleSeed = 0,
    this.updatedAt,
    this.expiresAt,
    this.isActive = false,
  });

  final bool isPeerTyping;
  final bool liveChatEnabled;

  final String? liveText;
  final String? liveSessionId;

  final int? liveVersion;
  final int styleSeed;

  final DateTime? updatedAt;
  final DateTime? expiresAt;

  final bool isActive;
}

// ============================================================================
// BINDING TYPES
// ============================================================================

typedef ChatScreenSnapshotResolver =
    ChatScreenSnapshot Function(MessageController controller);

typedef ChatLiveViewResolver =
    ChatLiveViewData Function(MessageComposerController controller);

typedef ChatControllerAction =
    FutureOr<void> Function(MessageController controller);

typedef ChatComposerAction =
    FutureOr<void> Function(MessageComposerController controller);

typedef ChatMessageAction = FutureOr<void> Function(MessageEntity message);

typedef ChatMessageReactionAction =
    FutureOr<void> Function(MessageEntity message, String reaction);

typedef ChatAuthenticationRequiredCallback = FutureOr<void> Function();

// ============================================================================
// MESSAGE BINDINGS
// ============================================================================

@immutable
final class ChatScreenBindings {
  const ChatScreenBindings({
    required this.snapshot,
    required this.initialize,
    required this.loadMore,
    required this.markVisibleMessagesRead,
    required this.retry,
    required this.edit,
    required this.delete,
    required this.react,
  });

  final ChatScreenSnapshotResolver snapshot;

  final ChatControllerAction initialize;
  final ChatControllerAction loadMore;
  final ChatControllerAction markVisibleMessagesRead;

  final ChatMessageAction retry;
  final ChatMessageAction edit;
  final ChatMessageAction delete;

  final ChatMessageReactionAction react;
}

// ============================================================================
// COMPOSER BINDINGS
// ============================================================================

@immutable
final class ChatComposerBindings {
  const ChatComposerBindings({
    required this.liveView,
    required this.send,
    required this.clear,
    required this.leave,
  });

  final ChatLiveViewResolver liveView;

  final ChatComposerAction send;
  final ChatComposerAction clear;
  final ChatComposerAction leave;
}

// ============================================================================
// CHAT SCREEN
// ============================================================================

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.messageController,
    required this.composerController,
    required this.messageBindings,
    required this.composerBindings,
    required this.participant,
    required this.currentUserUid,
    required this.conversationId,
    required this.isAuthenticated,
    required this.onAuthenticationRequired,
    required this.messageBuilder,
    required this.inputBuilder,
    required this.typingBuilder,
    this.onVoiceCall,
    this.onVideoCall,
    this.onBack,
  });

  final MessageController messageController;
  final MessageComposerController composerController;

  final ChatScreenBindings messageBindings;
  final ChatComposerBindings composerBindings;

  final ChatParticipantViewData participant;

  final String currentUserUid;
  final String conversationId;

  final bool isAuthenticated;

  final ChatAuthenticationRequiredCallback onAuthenticationRequired;

  final Widget Function(
    BuildContext context,
    MessageEntity message,
    bool isOutgoing,
    Future<void> Function() onRetry,
    Future<void> Function() onEdit,
    Future<void> Function() onDelete,
    Future<void> Function(String reaction) onReact,
  )
  messageBuilder;

  final Widget Function(
    BuildContext context,
    MessageComposerController controller,
    bool isSending,
    Future<void> Function() onSend,
  )
  inputBuilder;

  final Widget Function(BuildContext context, ChatLiveViewData liveView)
  typingBuilder;

  final FutureOr<void> Function()? onVoiceCall;
  final FutureOr<void> Function()? onVideoCall;
  final FutureOr<void> Function()? onBack;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// ============================================================================
// CHAT SCREEN STATE
// ============================================================================

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const double _olderMessagesTrigger = 220;
  static const double _readBoundaryPadding = 140;

  final ScrollController _scrollController = ScrollController();

  bool _initializeRequested = false;
  bool _loadingOlderLocked = false;
  bool _readUpdateQueued = false;
  bool _isLeaving = false;

  int _previousMessageCount = 0;

  String? _previousNewestMessageId;

  // ==========================================================================
  // LIFECYCLE
  // ==========================================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    widget.messageController.addListener(_handleMessageControllerChanged);

    widget.composerController.addListener(_handleComposerControllerChanged);

    _scrollController.addListener(_handleScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(_initialize());
    });
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.messageController, widget.messageController)) {
      oldWidget.messageController.removeListener(
        _handleMessageControllerChanged,
      );

      widget.messageController.addListener(_handleMessageControllerChanged);

      _initializeRequested = false;
      _loadingOlderLocked = false;

      _previousMessageCount = 0;
      _previousNewestMessageId = null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_initialize());
        }
      });
    }

    if (!identical(oldWidget.composerController, widget.composerController)) {
      oldWidget.composerController.removeListener(
        _handleComposerControllerChanged,
      );

      widget.composerController.addListener(_handleComposerControllerChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        _queueReadUpdate();
        return;

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        return;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    widget.messageController.removeListener(_handleMessageControllerChanged);

    widget.composerController.removeListener(_handleComposerControllerChanged);

    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();

    unawaited(_leaveConversation());

    super.dispose();
  }

  // ==========================================================================
  // INITIALIZATION
  // ==========================================================================

  Future<void> _initialize() async {
    if (_initializeRequested || !widget.isAuthenticated) {
      return;
    }

    _initializeRequested = true;

    try {
      await widget.messageBindings.initialize(widget.messageController);

      if (!mounted) {
        return;
      }

      final ChatScreenSnapshot snapshot = widget.messageBindings.snapshot(
        widget.messageController,
      );

      _previousMessageCount = snapshot.messages.length;

      _previousNewestMessageId = _newestMessageId(snapshot.messages);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _scrollToLatest(animate: false);

        _queueReadUpdate();
      });
    } catch (_) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  // ==========================================================================
  // MESSAGE CONTROLLER
  // ==========================================================================

  void _handleMessageControllerChanged() {
    if (!mounted) {
      return;
    }

    final ChatScreenSnapshot snapshot = widget.messageBindings.snapshot(
      widget.messageController,
    );

    if (!snapshot.isLoadingMore) {
      _loadingOlderLocked = false;
    }

    final String? newestMessageId = _newestMessageId(snapshot.messages);

    final bool hasNewMessage =
        snapshot.messages.length > _previousMessageCount ||
        newestMessageId != _previousNewestMessageId;

    final bool wasNearLatest = _isNearLatest();

    _previousMessageCount = snapshot.messages.length;

    _previousNewestMessageId = newestMessageId;

    setState(() {});

    if (hasNewMessage && wasNearLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _scrollToLatest(animate: true);
      });
    }

    _queueReadUpdate();
  }

  void _handleComposerControllerChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // ==========================================================================
  // SCROLL
  // ==========================================================================

  void _handleScroll() {
    if (!_scrollController.hasClients || !widget.isAuthenticated) {
      return;
    }

    final ScrollPosition position = _scrollController.position;

    if (position.pixels <= position.minScrollExtent + _olderMessagesTrigger) {
      unawaited(_loadOlderMessages());
    }

    if (_isNearLatest()) {
      _queueReadUpdate();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlderLocked || !widget.isAuthenticated) {
      return;
    }

    final ChatScreenSnapshot snapshot = widget.messageBindings.snapshot(
      widget.messageController,
    );

    if (!snapshot.hasMore || snapshot.isLoading || snapshot.isLoadingMore) {
      return;
    }

    _loadingOlderLocked = true;

    final double previousMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0;

    try {
      await widget.messageBindings.loadMore(widget.messageController);

      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }

        final double newMaxExtent = _scrollController.position.maxScrollExtent;

        final double delta = newMaxExtent - previousMaxExtent;

        if (delta <= 0) {
          return;
        }

        final double target = (_scrollController.offset + delta).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );

        _scrollController.jumpTo(target);
      });
    } catch (_) {
      _loadingOlderLocked = false;
    }
  }

  // ==========================================================================
  // REAL READ ACKNOWLEDGEMENT
  // ==========================================================================

  void _queueReadUpdate() {
    if (_readUpdateQueued || !widget.isAuthenticated || !_isNearLatest()) {
      return;
    }

    _readUpdateQueued = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _readUpdateQueued = false;

      if (!mounted || !widget.isAuthenticated || !_isNearLatest()) {
        return;
      }

      try {
        await widget.messageBindings.markVisibleMessagesRead(
          widget.messageController,
        );
      } catch (_) {
        return;
      }
    });
  }

  bool _isNearLatest() {
    if (!_scrollController.hasClients) {
      return true;
    }

    return _scrollController.position.extentAfter <= _readBoundaryPadding;
  }

  void _scrollToLatest({required bool animate}) {
    if (!_scrollController.hasClients) {
      return;
    }

    final double target = _scrollController.position.maxScrollExtent;

    if (!animate) {
      _scrollController.jumpTo(target);

      return;
    }

    unawaited(
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ==========================================================================
  // SEND
  // ==========================================================================

  Future<void> _send() async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();

      return;
    }

    final ChatScreenSnapshot snapshot = widget.messageBindings.snapshot(
      widget.messageController,
    );

    if (snapshot.isSending) {
      return;
    }

    try {
      await widget.composerBindings.send(widget.composerController);

      if (!mounted) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToLatest(animate: true);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  // ==========================================================================
  // MESSAGE OPERATIONS
  // ==========================================================================

  Future<void> _retryMessage(MessageEntity message) async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();

      return;
    }

    await widget.messageBindings.retry(message);
  }

  Future<void> _editMessage(MessageEntity message) async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();

      return;
    }

    await widget.messageBindings.edit(message);
  }

  Future<void> _deleteMessage(MessageEntity message) async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();

      return;
    }

    await widget.messageBindings.delete(message);
  }

  Future<void> _reactToMessage(MessageEntity message, String reaction) async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();

      return;
    }

    await widget.messageBindings.react(message, reaction);
  }

  // ==========================================================================
  // LEAVE / BACK
  // ==========================================================================

  Future<void> _leaveConversation() async {
    if (_isLeaving) {
      return;
    }

    _isLeaving = true;

    try {
      await widget.composerBindings.leave(widget.composerController);
    } catch (_) {
      return;
    }
  }

  Future<void> _handleBack() async {
    await _leaveConversation();

    if (!mounted) {
      return;
    }

    if (widget.onBack != null) {
      await widget.onBack!();

      return;
    }

    await Navigator.of(context).maybePop();
  }

  // ==========================================================================
  // CALL ACTIONS
  // ==========================================================================

  Future<void> _handleVoiceCall() async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();

      return;
    }

    await widget.onVoiceCall?.call();
  }

  Future<void> _handleVideoCall() async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();

      return;
    }

    await widget.onVideoCall?.call();
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final ChatScreenSnapshot snapshot = widget.messageBindings.snapshot(
      widget.messageController,
    );

    final ChatLiveViewData liveView = widget.composerBindings.liveView(
      widget.composerController,
    );

    return PopScope(
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          unawaited(_leaveConversation());

          return;
        }

        unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFE),
        body: SafeArea(
          bottom: false,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFFFCFDFF),
                  Color(0xFFF7F9FF),
                  Color(0xFFFBF9FF),
                ],
              ),
            ),
            child: Column(
              children: <Widget>[
                _ChatHeader(
                  participant: widget.participant,
                  onBack: _handleBack,
                  onVoiceCall: widget.onVoiceCall == null
                      ? null
                      : _handleVoiceCall,
                  onVideoCall: widget.onVideoCall == null
                      ? null
                      : _handleVideoCall,
                ),

                _LiveChatSurface(
                  liveView: liveView,
                  builder: widget.typingBuilder,
                ),

                Expanded(child: _buildTimeline(snapshot)),

                _ComposerSurface(
                  child: widget.inputBuilder(
                    context,
                    widget.composerController,
                    snapshot.isSending,
                    _send,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // TIMELINE
  // ==========================================================================

  Widget _buildTimeline(ChatScreenSnapshot snapshot) {
    if (!widget.isAuthenticated) {
      return _ChatGuestView(onContinue: widget.onAuthenticationRequired);
    }

    if (snapshot.isLoading && snapshot.messages.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 27,
          height: 27,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: Color(0xFFB63CFA),
          ),
        ),
      );
    }

    if (snapshot.messages.isEmpty) {
      final String? error = _safeError(snapshot.errorMessage);

      if (error != null) {
        return _ChatErrorView(message: error);
      }

      return const _EmptyConversationView();
    }

    return Stack(
      children: <Widget>[
        ListView.builder(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 26),
          itemCount: snapshot.messages.length + (snapshot.hasMore ? 1 : 0),
          itemBuilder: (BuildContext context, int index) {
            if (snapshot.hasMore && index == 0) {
              return _OlderMessagesLoader(isLoading: snapshot.isLoadingMore);
            }

            final int messageIndex = snapshot.hasMore ? index - 1 : index;

            final MessageEntity message = snapshot.messages[messageIndex];

            final MessageEntity? previousMessage = messageIndex > 0
                ? snapshot.messages[messageIndex - 1]
                : null;

            final bool showDateSeparator = _shouldShowDateSeparator(
              previousMessage,
              message,
            );

            final bool isOutgoing = message.senderUid == widget.currentUserUid;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (showDateSeparator)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _DateSeparator(date: _messageDate(message)),
                  ),

                widget.messageBuilder(
                  context,
                  message,
                  isOutgoing,
                  () => _retryMessage(message),
                  () => _editMessage(message),
                  () => _deleteMessage(message),
                  (String reaction) => _reactToMessage(message, reaction),
                ),
              ],
            );
          },
        ),

        if (!_isNearLatest())
          Positioned(
            right: 14,
            bottom: 14,
            child: _JumpToLatestButton(
              onPressed: () {
                _scrollToLatest(animate: true);
              },
            ),
          ),
      ],
    );
  }

  static String? _safeError(String? raw) {
    final String value = raw?.trim() ?? '';

    return value.isEmpty ? null : value;
  }

  static String? _newestMessageId(List<MessageEntity> messages) {
    if (messages.isEmpty) {
      return null;
    }

    return messages.last.id;
  }

  static DateTime _messageDate(MessageEntity message) {
    return (message.serverCreatedAt ?? message.clientCreatedAt).toLocal();
  }

  static bool _shouldShowDateSeparator(
    MessageEntity? previous,
    MessageEntity current,
  ) {
    if (previous == null) {
      return true;
    }

    final DateTime previousDate = _messageDate(previous);

    final DateTime currentDate = _messageDate(current);

    return previousDate.year != currentDate.year ||
        previousDate.month != currentDate.month ||
        previousDate.day != currentDate.day;
  }
}

// ============================================================================
// COMPACT PREMIUM HEADER
// ============================================================================

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.participant,
    required this.onBack,
    required this.onVoiceCall,
    required this.onVideoCall,
  });

  final ChatParticipantViewData participant;

  final VoidCallback onBack;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;

  @override
  Widget build(BuildContext context) {
    final String presenceText = _presenceText(participant);

    return Container(
      width: double.infinity,

      // Compact / higher placement.
      padding: const EdgeInsets.fromLTRB(4, 3, 8, 6),

      decoration: const BoxDecoration(
        color: Color(0xFFFEFEFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE9EDF5))),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0814233D),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),

      child: Row(
        children: <Widget>[
          _CompactBackButton(onPressed: onBack),

          const SizedBox(width: 3),

          _ParticipantAvatar(
            displayName: participant.displayName,
            avatarUrl: participant.avatarUrl,
            isOnline: participant.isOnline,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        _normalizedName(participant.displayName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF101828),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                    ),

                    if (participant.isVerified) ...<Widget>[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        color: Color(0xFF087AF5),
                        size: 14,
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 2),

                Text(
                  presenceText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: participant.isOnline
                        ? const Color(0xFF00A86B)
                        : const Color(0xFF7B879A),
                    fontSize: 10,
                    fontWeight: participant.isOnline
                        ? FontWeight.w700
                        : FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),

          if (onVoiceCall != null)
            _CallActionButton(
              tooltip: 'Voice call',
              icon: Icons.call_rounded,
              color: const Color(0xFF00C98D),
              onPressed: onVoiceCall!,
            ),

          if (onVideoCall != null) ...<Widget>[
            const SizedBox(width: 5),
            _CallActionButton(
              tooltip: 'Video call',
              icon: Icons.videocam_rounded,
              color: const Color(0xFF008BFF),
              onPressed: onVideoCall!,
            ),
          ],
        ],
      ),
    );
  }

  static String _normalizedName(String value) {
    final String normalized = value.trim();

    return normalized.isEmpty ? 'JR CALL User' : normalized;
  }

  static String _presenceText(ChatParticipantViewData participant) {
    if (participant.isOnline) {
      return 'Online';
    }

    final DateTime? lastSeen = participant.lastSeen?.toLocal();

    if (lastSeen == null) {
      return 'Offline';
    }

    final DateTime now = DateTime.now();

    final DateTime today = DateTime(now.year, now.month, now.day);

    final DateTime seenDay = DateTime(
      lastSeen.year,
      lastSeen.month,
      lastSeen.day,
    );

    final int difference = today.difference(seenDay).inDays;

    final int rawHour = lastSeen.hour;

    final int hour = rawHour == 0
        ? 12
        : rawHour > 12
        ? rawHour - 12
        : rawHour;

    final String minute = lastSeen.minute.toString().padLeft(2, '0');

    final String suffix = rawHour >= 12 ? 'PM' : 'AM';

    final String time = '$hour:$minute $suffix';

    if (difference == 0) {
      return 'Last seen today at $time';
    }

    if (difference == 1) {
      return 'Last seen yesterday at $time';
    }

    return 'Last seen '
        '${lastSeen.day}/'
        '${lastSeen.month}/'
        '${lastSeen.year} '
        'at $time';
  }
}

// ============================================================================
// COMPACT BACK BUTTON
// ============================================================================

class _CompactBackButton extends StatelessWidget {
  const _CompactBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 17,
            color: Color(0xFF1D2939),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CALL ACTION
// ============================================================================

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.12)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.07),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 19, color: color),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PARTICIPANT AVATAR
// ============================================================================

class _ParticipantAvatar extends StatelessWidget {
  const _ParticipantAvatar({
    required this.displayName,
    required this.avatarUrl,
    required this.isOnline,
  });

  final String displayName;
  final String? avatarUrl;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final String? safeUrl = _safeNetworkUrl(avatarUrl);

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: 39,
          height: 39,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFFEAF3FF), Color(0xFFF7E9FF)],
            ),
            border: Border.all(color: Colors.white, width: 1.7),
          ),
          child: safeUrl == null
              ? Center(
                  child: Text(
                    _initials(displayName),
                    style: const TextStyle(
                      color: Color(0xFF9747FF),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : Image.network(
                  safeUrl,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder:
                      (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                      ) {
                        return Center(
                          child: Text(
                            _initials(displayName),
                            style: const TextStyle(
                              color: Color(0xFF9747FF),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      },
                ),
        ),

        if (isOnline)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00C98D),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  static String? _safeNetworkUrl(String? value) {
    final String raw = value?.trim() ?? '';

    if (raw.isEmpty) {
      return null;
    }

    final Uri? uri = Uri.tryParse(raw);

    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }

    return raw;
  }

  static String _initials(String value) {
    final List<String> parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) {
      return 'JR';
    }

    if (parts.length == 1) {
      final String word = parts.first;

      return word.substring(0, word.length > 1 ? 2 : 1).toUpperCase();
    }

    return '${parts.first[0]}'
            '${parts.last[0]}'
        .toUpperCase();
  }
}

// ============================================================================
// LIVE CHAT SURFACE
// ============================================================================

class _LiveChatSurface extends StatelessWidget {
  const _LiveChatSurface({required this.liveView, required this.builder});

  final ChatLiveViewData liveView;

  final Widget Function(BuildContext context, ChatLiveViewData liveView)
  builder;

  @override
  Widget build(BuildContext context) {
    final String text = liveView.liveText?.trim() ?? '';

    final bool shouldShowLive =
        liveView.liveChatEnabled && liveView.isActive && text.isNotEmpty;

    final bool shouldShowTyping = liveView.isPeerTyping;

    if (!shouldShowLive && !shouldShowTyping) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 170),
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          decoration: const BoxDecoration(
            color: Color(0xFFFCFAFF),
            border: Border(bottom: BorderSide(color: Color(0xFFF0E8F8))),
          ),
          child: builder(context, liveView),
        ),
      ),
    );
  }
}

// ============================================================================
// COMPOSER SURFACE
// ============================================================================

class _ComposerSurface extends StatelessWidget {
  const _ComposerSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFFEFEFF),
        border: Border(top: BorderSide(color: Color(0xFFE9EDF5))),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0B26355B),
            blurRadius: 16,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

// ============================================================================
// DATE SEPARATOR
// ============================================================================

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _formatDate(date),
          style: const TextStyle(
            color: Color(0xFF7A8497),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final DateTime now = DateTime.now();

    final DateTime today = DateTime(now.year, now.month, now.day);

    final DateTime messageDay = DateTime(value.year, value.month, value.day);

    final int difference = today.difference(messageDay).inDays;

    if (difference == 0) {
      return 'Today';
    }

    if (difference == 1) {
      return 'Yesterday';
    }

    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${value.day} '
        '${months[value.month - 1]} '
        '${value.year}';
  }
}

// ============================================================================
// OLDER MESSAGE LOADER
// ============================================================================

class _OlderMessagesLoader extends StatelessWidget {
  const _OlderMessagesLoader({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (!isLoading) {
      return const SizedBox(height: 8);
    }

    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 19,
          height: 19,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Color(0xFFB63CFA),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// JUMP TO LATEST
// ============================================================================

class _JumpToLatestButton extends StatelessWidget {
  const _JumpToLatestButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x2B9747FF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFFB63CFA),
            size: 27,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// EMPTY CONVERSATION
// ============================================================================

class _EmptyConversationView extends StatelessWidget {
  const _EmptyConversationView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB63CFA).withValues(alpha: 0.08),
                border: Border.all(
                  color: const Color(0xFFB63CFA).withValues(alpha: 0.13),
                ),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFFB63CFA),
                size: 34,
              ),
            ),

            const SizedBox(height: 15),

            const Text(
              'Start the conversation',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF101828),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Send your first JR CALL message.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF7B879A),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ERROR VIEW
// ============================================================================

class _ChatErrorView extends StatelessWidget {
  const _ChatErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFF8B93A5),
              size: 42,
            ),

            const SizedBox(height: 12),

            const Text(
              'Conversation unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF101828),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF7B879A),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// GUEST VIEW
// ============================================================================

class _ChatGuestView extends StatelessWidget {
  const _ChatGuestView({required this.onContinue});

  final ChatAuthenticationRequiredCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(23),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE8EDF5)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0F293760),
                blurRadius: 20,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFF087AF5),
                      Color(0xFF9747FF),
                      Color(0xFFB63CFA),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.lock_person_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),

              const SizedBox(height: 17),

              const Text(
                'Login required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 7),

              const Text(
                'Log in or create your JR CALL account to send and receive messages.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF7B879A),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),

              const SizedBox(height: 19),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF087AF5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Login / Create Account',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// END OF FILE:
// lib/features/message/presentation/chat_screen.dart
//
// IMPORTANT:
//
// ✓ No demo logic.
// ✓ Real MessageController preserved.
// ✓ Real MessageComposerController preserved.
// ✓ Real send preserved.
// ✓ Real receive/timeline binding preserved.
// ✓ Real pagination preserved.
// ✓ Real read boundary preserved.
// ✓ Retry/edit/delete/reaction preserved.
// ✓ Typing/Live Chat preserved.
// ✓ Voice/video callbacks preserved.
// ✓ Authentication gate preserved.
// ✓ No Firestore duplicated here.
// ✓ No Message repository duplicated here.
// ✓ No Call Engine/WebRTC touched.
// ✓ Public constructor/API preserved.
// ✓ Header smaller and visually higher.
// ✓ Home Message bottom button is NOT changed by this file.
//
// NEXT REAL UI CONNECTION FILE:
// lib/features/message/presentation/message_screen.dart
// ============================================================================
