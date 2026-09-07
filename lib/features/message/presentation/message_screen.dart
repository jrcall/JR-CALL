// ============================================================================
// JR CALL
// File: message_screen.dart
// Location: lib/features/message/presentation/message_screen.dart
// Description:
// Production JR CALL Message inbox.
//
// PRESERVED:
// - Existing public API
// - ConversationController ownership
// - Real conversation list
// - Real pagination
// - Real refresh
// - Real unread state
// - Real online/verified/mute/pin presentation
// - Authentication protection
// - Real conversation/new-chat callbacks
// - Home bottom Message button/design untouched
//
// FIXED:
// - Guest -> authenticated transition now initializes Message inbox correctly
// - Controller replacement safely reinitializes
// - Duplicate pagination guarded
// - Async callbacks safely handled
// - Compact premium header moved slightly upward
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/conversation_controller.dart';
import '../data/conversation_entity.dart';

// ============================================================================
// VIEW DATA
// ============================================================================

@immutable
final class MessageConversationViewData {
  const MessageConversationViewData({
    required this.conversationId,
    required this.displayName,
    this.avatarUrl,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isVerified = false,
    this.isMuted = false,
    this.isPinned = false,
  });

  final String conversationId;
  final String displayName;
  final String? avatarUrl;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool isOnline;
  final bool isVerified;
  final bool isMuted;
  final bool isPinned;
}

@immutable
final class MessageInboxSnapshot {
  const MessageInboxSnapshot({
    required this.conversations,
    this.isLoading = false,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.errorMessage,
  });

  final List<ConversationEntity> conversations;
  final bool isLoading;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;
}

// ============================================================================
// BINDINGS
// ============================================================================

typedef MessageInboxSnapshotResolver =
    MessageInboxSnapshot Function(ConversationController controller);

typedef MessageConversationViewResolver =
    MessageConversationViewData Function(ConversationEntity conversation);

typedef ConversationControllerAction =
    FutureOr<void> Function(ConversationController controller);

typedef ConversationOpenCallback =
    FutureOr<void> Function(ConversationEntity conversation);

typedef MessageAuthenticationRequiredCallback = FutureOr<void> Function();

@immutable
final class MessageScreenBindings {
  const MessageScreenBindings({
    required this.snapshot,
    required this.initialize,
    required this.refresh,
    required this.loadMore,
  });

  final MessageInboxSnapshotResolver snapshot;
  final ConversationControllerAction initialize;
  final ConversationControllerAction refresh;
  final ConversationControllerAction loadMore;
}

// ============================================================================
// MESSAGE SCREEN
// ============================================================================

class MessageScreen extends StatefulWidget {
  const MessageScreen({
    super.key,
    required this.controller,
    required this.bindings,
    required this.resolveConversationView,
    required this.isAuthenticated,
    required this.onAuthenticationRequired,
    required this.onOpenConversation,
    required this.onNewChat,
    this.onSearch,
    this.title = 'Messages',
  });

  final ConversationController controller;
  final MessageScreenBindings bindings;
  final MessageConversationViewResolver resolveConversationView;

  final bool isAuthenticated;
  final MessageAuthenticationRequiredCallback onAuthenticationRequired;

  final ConversationOpenCallback onOpenConversation;
  final VoidCallback onNewChat;
  final VoidCallback? onSearch;

  final String title;

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  static const double _paginationTriggerExtent = 260;

  final ScrollController _scrollController = ScrollController();

  bool _initializationRequested = false;
  bool _loadMoreLocked = false;

  // ==========================================================================
  // LIFECYCLE
  // ==========================================================================

  @override
  void initState() {
    super.initState();

    widget.controller.addListener(_handleControllerChanged);
    _scrollController.addListener(_handleScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(_initialize());
    });
  }

  @override
  void didUpdateWidget(covariant MessageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );

    if (controllerChanged) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);

      _initializationRequested = false;
      _loadMoreLocked = false;
    }

    // IMPORTANT:
    // Guest -> authenticated may happen while the same controller remains
    // mounted inside HomeScreen. The previous version could remain
    // uninitialized forever in that case.
    if (!oldWidget.isAuthenticated && widget.isAuthenticated) {
      _initializationRequested = false;
      _loadMoreLocked = false;
    }

    if (oldWidget.isAuthenticated && !widget.isAuthenticated) {
      _initializationRequested = false;
      _loadMoreLocked = false;
    }

    if (controllerChanged ||
        (!oldWidget.isAuthenticated && widget.isAuthenticated)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        unawaited(_initialize());
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);

    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();

    super.dispose();
  }

  // ==========================================================================
  // CONTROLLER
  // ==========================================================================

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }

    final MessageInboxSnapshot snapshot = widget.bindings.snapshot(
      widget.controller,
    );

    if (!snapshot.isLoadingMore) {
      _loadMoreLocked = false;
    }

    setState(() {});
  }

  // ==========================================================================
  // INITIALIZATION
  // ==========================================================================

  Future<void> _initialize() async {
    if (_initializationRequested || !widget.isAuthenticated) {
      return;
    }

    _initializationRequested = true;

    try {
      await widget.bindings.initialize(widget.controller);
    } catch (_) {
      // Allow a real retry after initialization failure.
      _initializationRequested = false;

      if (mounted) {
        setState(() {});
      }
    }
  }

  // ==========================================================================
  // REFRESH
  // ==========================================================================

  Future<void> _handleRefresh() async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();
      return;
    }

    try {
      await widget.bindings.refresh(widget.controller);
    } catch (_) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  // ==========================================================================
  // PAGINATION
  // ==========================================================================

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _loadMoreLocked ||
        !widget.isAuthenticated) {
      return;
    }

    final ScrollPosition position = _scrollController.position;

    if (position.extentAfter > _paginationTriggerExtent) {
      return;
    }

    final MessageInboxSnapshot snapshot = widget.bindings.snapshot(
      widget.controller,
    );

    if (!snapshot.hasMore ||
        snapshot.isLoading ||
        snapshot.isLoadingMore ||
        snapshot.isRefreshing) {
      return;
    }

    _loadMoreLocked = true;

    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    try {
      await widget.bindings.loadMore(widget.controller);
    } catch (_) {
      _loadMoreLocked = false;

      if (mounted) {
        setState(() {});
      }
    }
  }

  // ==========================================================================
  // NAVIGATION
  // ==========================================================================

  Future<void> _openConversation(ConversationEntity conversation) async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();
      return;
    }

    await widget.onOpenConversation(conversation);
  }

  Future<void> _openNewChat() async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();
      return;
    }

    widget.onNewChat();
  }

  Future<void> _openSearch() async {
    if (!widget.isAuthenticated) {
      await widget.onAuthenticationRequired();
      return;
    }

    widget.onSearch?.call();
  }

  // ==========================================================================
  // ROOT
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final MessageInboxSnapshot snapshot = widget.bindings.snapshot(
      widget.controller,
    );

    return Scaffold(
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
                Color(0xFFFBFAFF),
              ],
            ),
          ),
          child: Column(
            children: <Widget>[
              _MessageHeader(
                title: widget.title,
                onSearch: () {
                  unawaited(_openSearch());
                },
                onNewChat: () {
                  unawaited(_openNewChat());
                },
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _buildBody(snapshot),
                ),
              ),
            ],
          ),
        ),
      ),

      // This FAB belongs only to the real Message inbox.
      // HomeScreen bottom navigation remains completely untouched.
      floatingActionButton: widget.isAuthenticated
          ? FloatingActionButton.small(
              heroTag: 'jr-message-new-chat',
              onPressed: () {
                unawaited(_openNewChat());
              },
              backgroundColor: const Color(0xFFB63CFA),
              foregroundColor: Colors.white,
              elevation: 4,
              tooltip: 'New chat',
              child: const Icon(Icons.edit_rounded, size: 20),
            )
          : null,
    );
  }

  // ==========================================================================
  // BODY
  // ==========================================================================

  Widget _buildBody(MessageInboxSnapshot snapshot) {
    if (!widget.isAuthenticated) {
      return _GuestMessageView(
        key: const ValueKey<String>('message-guest'),
        onContinue: widget.onAuthenticationRequired,
      );
    }

    if (snapshot.isLoading && snapshot.conversations.isEmpty) {
      return const _MessageLoadingView(
        key: ValueKey<String>('message-loading'),
      );
    }

    if (snapshot.conversations.isEmpty) {
      final String? error = _safeError(snapshot.errorMessage);

      if (error != null) {
        return _MessageErrorView(
          key: const ValueKey<String>('message-error'),
          message: error,
          onRetry: _handleRefresh,
        );
      }

      return _EmptyMessageView(
        key: const ValueKey<String>('message-empty'),
        onNewChat: () {
          unawaited(_openNewChat());
        },
      );
    }

    return RefreshIndicator(
      key: const ValueKey<String>('message-list'),
      onRefresh: _handleRefresh,
      color: const Color(0xFFB63CFA),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
        itemCount: snapshot.conversations.length + (snapshot.hasMore ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index >= snapshot.conversations.length) {
            return _PaginationIndicator(isLoading: snapshot.isLoadingMore);
          }

          final ConversationEntity conversation = snapshot.conversations[index];

          final MessageConversationViewData view = widget
              .resolveConversationView(conversation);

          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _ConversationCard(
              view: view,
              onTap: () {
                unawaited(_openConversation(conversation));
              },
            ),
          );
        },
      ),
    );
  }

  static String? _safeError(String? raw) {
    final String message = raw?.trim() ?? '';

    return message.isEmpty ? null : message;
  }
}

// ============================================================================
// COMPACT MESSAGE HEADER
// ============================================================================

class _MessageHeader extends StatelessWidget {
  const _MessageHeader({
    required this.title,
    required this.onSearch,
    required this.onNewChat,
  });

  final String title;
  final VoidCallback onSearch;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      // Smaller and slightly higher than previous header.
      padding: const EdgeInsets.fromLTRB(12, 3, 10, 6),

      decoration: const BoxDecoration(
        color: Color(0xFFFEFEFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE9EDF5))),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0714253D),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF9747FF), Color(0xFFB63CFA)],
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1FB63CFA),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.chat_bubble_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'JR CALL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 17,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _HeaderButton(
            tooltip: 'Search',
            icon: Icons.search_rounded,
            onPressed: onSearch,
          ),
          const SizedBox(width: 5),
          _HeaderButton(
            tooltip: 'New chat',
            icon: Icons.add_rounded,
            onPressed: onNewChat,
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            width: 35,
            height: 35,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFE8EDF5)),
            ),
            child: Icon(icon, size: 19, color: const Color(0xFF101828)),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CONVERSATION CARD
// ============================================================================

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.view, required this.onTap});

  final MessageConversationViewData view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool hasUnread = view.unreadCount > 0;

    final String preview = _normalizedPreview(view.lastMessagePreview);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasUnread
                  ? const Color(0x33B63CFA)
                  : const Color(0xFFE8EDF5),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0C24345C),
                blurRadius: 15,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _ConversationAvatar(
                displayName: view.displayName,
                avatarUrl: view.avatarUrl,
                isOnline: view.isOnline,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            _displayName(view.displayName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF101828),
                              fontSize: 14.5,
                              fontWeight: hasUnread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (view.isVerified) ...<Widget>[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: Color(0xFF087AF5),
                          ),
                        ],
                        if (view.isPinned) ...<Widget>[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.push_pin_rounded,
                            size: 13,
                            color: Color(0xFF7A8497),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        if (view.isMuted) ...<Widget>[
                          const Icon(
                            Icons.volume_off_rounded,
                            size: 14,
                            color: Color(0xFF98A2B3),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread
                                  ? const Color(0xFF344054)
                                  : const Color(0xFF7A8497),
                              fontSize: 12.5,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    _formatConversationTime(view.lastMessageAt),
                    style: TextStyle(
                      color: hasUnread
                          ? const Color(0xFFB63CFA)
                          : const Color(0xFF98A2B3),
                      fontSize: 10,
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 7),
                  if (hasUnread)
                    _UnreadBadge(count: view.unreadCount)
                  else
                    const SizedBox(height: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _displayName(String value) {
    final String normalized = value.trim();

    return normalized.isEmpty ? 'JR CALL User' : normalized;
  }

  static String _normalizedPreview(String? value) {
    final String normalized = value?.trim() ?? '';

    return normalized.isEmpty ? 'Start a conversation' : normalized;
  }

  static String _formatConversationTime(DateTime? value) {
    if (value == null) {
      return '';
    }

    final DateTime now = DateTime.now();
    final DateTime time = value.toLocal();

    final DateTime today = DateTime(now.year, now.month, now.day);

    final DateTime messageDay = DateTime(time.year, time.month, time.day);

    final int difference = today.difference(messageDay).inDays;

    if (difference == 0) {
      final int rawHour = time.hour;

      final int hour = rawHour == 0
          ? 12
          : rawHour > 12
          ? rawHour - 12
          : rawHour;

      final String minute = time.minute.toString().padLeft(2, '0');

      final String suffix = rawHour >= 12 ? 'PM' : 'AM';

      return '$hour:$minute $suffix';
    }

    if (difference == 1) {
      return 'Yesterday';
    }

    if (difference > 1 && difference < 7) {
      const List<String> weekdays = <String>[
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ];

      return weekdays[time.weekday - 1];
    }

    return '${time.day}/${time.month}/${time.year}';
  }
}

// ============================================================================
// AVATAR
// ============================================================================

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({
    required this.displayName,
    required this.avatarUrl,
    required this.isOnline,
  });

  final String displayName;
  final String? avatarUrl;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final String? url = _safeNetworkUrl(avatarUrl);

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: 50,
          height: 50,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFFEAF3FF), Color(0xFFF8E9FF)],
            ),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: url == null
              ? Center(
                  child: Text(
                    _initials(displayName),
                    style: const TextStyle(
                      color: Color(0xFFB63CFA),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : Image.network(
                  url,
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
                              color: Color(0xFFB63CFA),
                              fontSize: 14,
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
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00C98D),
                border: Border.all(color: Colors.white, width: 2.4),
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

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

// ============================================================================
// UNREAD BADGE
// ============================================================================

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final String label = count > 99 ? '99+' : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFB63CFA),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ============================================================================
// LOADING
// ============================================================================

class _MessageLoadingView extends StatelessWidget {
  const _MessageLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
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
}

class _PaginationIndicator extends StatelessWidget {
  const _PaginationIndicator({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (!isLoading) {
      return const SizedBox(height: 16);
    }

    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
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
// EMPTY STATE
// ============================================================================

class _EmptyMessageView extends StatelessWidget {
  const _EmptyMessageView({super.key, required this.onNewChat});

  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 60),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 430),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE8EDF5)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0E25385B),
                blurRadius: 20,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB63CFA).withValues(alpha: 0.08),
                  border: Border.all(
                    color: const Color(0xFFB63CFA).withValues(alpha: 0.12),
                  ),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: Color(0xFFB63CFA),
                  size: 35,
                ),
              ),
              const SizedBox(height: 17),
              const Text(
                'No conversations yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Your real conversations will appear here. '
                'Find a JR CALL user to start messaging.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onNewChat,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF087AF5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: const Text(
                    'Find People',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
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
// ERROR STATE
// ============================================================================

class _MessageErrorView extends StatelessWidget {
  const _MessageErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_rounded,
              size: 42,
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 13),
            const Text(
              'Messages unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF101828),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () {
                unawaited(onRetry());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// GUEST STATE
// ============================================================================

class _GuestMessageView extends StatelessWidget {
  const _GuestMessageView({super.key, required this.onContinue});

  final MessageAuthenticationRequiredCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 18, 26, 60),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE8EDF5)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x102D3A64),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
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
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Message with JR CALL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Log in or create an account to access your private conversations.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    unawaited(Future<void>.sync(onContinue));
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF087AF5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
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
// lib/features/message/presentation/message_screen.dart
//
// IMPORTANT:
// - HomeScreen bottom Message button untouched.
// - No demo conversations.
// - No fake messages.
// - No fake unread/read/delivery state.
// - Real ConversationController preserved.
// - Real repository-backed inbox preserved.
// - Refresh preserved.
// - Pagination preserved.
// - Conversation opening preserved.
// - New Chat preserved.
// - Authentication gate preserved.
// - Guest -> Login initialization bug fixed.
// - Header/action controls made smaller and slightly higher.
//
// NEXT:
// Do NOT change chat_screen.dart again now.
// First save this file and run flutter analyze.
// ============================================================================
