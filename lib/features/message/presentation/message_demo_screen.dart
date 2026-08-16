import 'package:flutter/material.dart';

/// ===========================================================
/// JR CALL
/// File: message_demo_screen.dart
/// Location: lib/features/message/presentation/message_demo_screen.dart
///
/// Description:
/// Premium JR CALL Messaging demo screen.
///
/// Current phase:
/// - UI / interaction demo only
/// - No Firestore message writes
/// - No real messaging backend
/// - No Call Engine changes
///
/// Design:
/// - Premium light background
/// - Glassmorphism surfaces
/// - Soft purple / pink message glow
/// - Responsive mobile layout
/// - Safe-area friendly
///
/// Demo interactions:
/// - Search conversations
/// - Select conversation
/// - Filter recent / unread
/// - Type message
/// - Send local demo message
/// - Quick emoji action
/// - Attachment demo feedback
/// ===========================================================

class MessageDemoScreen extends StatefulWidget {
  const MessageDemoScreen({super.key});

  @override
  State<MessageDemoScreen> createState() => _MessageDemoScreenState();
}

class _MessageDemoScreenState extends State<MessageDemoScreen> {
  static const Color _background = Color(0xFFF7F9FD);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceSoft = Color(0xFFFDFBFF);

  static const Color _primary = Color(0xFF7C3AED);
  static const Color _secondary = Color(0xFFEC4899);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF667085);

  static const Color _border = Color(0xFFE8ECF4);

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  int _selectedConversationIndex = 0;
  int _selectedFilter = 0;

  final List<_DemoConversation> _conversations = [
    _DemoConversation(
      name: 'Sarah Ahmed',
      username: '@sarah',
      lastMessage: 'See you tomorrow ✨',
      time: '10:42',
      unreadCount: 2,
      online: true,
      avatarText: 'SA',
    ),
    _DemoConversation(
      name: 'Rakib Hasan',
      username: '@rakib',
      lastMessage: 'The video looks great!',
      time: '09:18',
      unreadCount: 0,
      online: true,
      avatarText: 'RH',
    ),
    _DemoConversation(
      name: 'Nadia Rahman',
      username: '@nadia',
      lastMessage: 'Thank you so much 💜',
      time: 'Yesterday',
      unreadCount: 1,
      online: false,
      avatarText: 'NR',
    ),
    _DemoConversation(
      name: 'JR Team',
      username: '@jrcall',
      lastMessage: 'Welcome to premium messaging.',
      time: 'Mon',
      unreadCount: 0,
      online: true,
      avatarText: 'JR',
    ),
  ];

  final Map<int, List<_DemoMessage>> _messages = {
    0: [
      _DemoMessage(
        text: 'Hi! Are you free tomorrow?',
        isMine: false,
        time: '10:39',
      ),
      _DemoMessage(
        text: 'Yes, I should be free after 4 PM.',
        isMine: true,
        time: '10:40',
      ),
      _DemoMessage(
        text: 'Perfect. See you tomorrow ✨',
        isMine: false,
        time: '10:42',
      ),
    ],
    1: [
      _DemoMessage(
        text: 'I checked the latest design.',
        isMine: false,
        time: '09:12',
      ),
      _DemoMessage(text: 'How does it look?', isMine: true, time: '09:15'),
      _DemoMessage(
        text: 'The video looks great!',
        isMine: false,
        time: '09:18',
      ),
    ],
    2: [
      _DemoMessage(
        text: 'Your help was really useful.',
        isMine: false,
        time: '18:20',
      ),
      _DemoMessage(text: 'Happy to help!', isMine: true, time: '18:22'),
      _DemoMessage(text: 'Thank you so much 💜', isMine: false, time: '18:25'),
    ],
    3: [
      _DemoMessage(
        text: 'Welcome to JR CALL Messaging.',
        isMine: false,
        time: '08:00',
      ),
      _DemoMessage(
        text: 'This screen is currently a polished demo.',
        isMine: false,
        time: '08:01',
      ),
    ],
  };

  List<_DemoConversation> get _visibleConversations {
    final query = _searchController.text.trim().toLowerCase();

    return _conversations.where((conversation) {
      final matchesSearch =
          query.isEmpty ||
          conversation.name.toLowerCase().contains(query) ||
          conversation.username.toLowerCase().contains(query) ||
          conversation.lastMessage.toLowerCase().contains(query);

      final matchesFilter =
          _selectedFilter == 0 ||
          (_selectedFilter == 1 && conversation.unreadCount > 0);

      return matchesSearch && matchesFilter;
    }).toList();
  }

  _DemoConversation get _activeConversation {
    return _conversations[_selectedConversationIndex];
  }

  List<_DemoMessage> get _activeMessages {
    return _messages.putIfAbsent(_selectedConversationIndex, () => []);
  }

  void _selectConversation(_DemoConversation conversation) {
    final index = _conversations.indexOf(conversation);

    if (index < 0) {
      return;
    }

    setState(() {
      _selectedConversationIndex = index;
      conversation.unreadCount = 0;
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();

    if (text.isEmpty) {
      return;
    }

    setState(() {
      _activeMessages.add(
        _DemoMessage(text: text, isMine: true, time: _currentTimeLabel()),
      );

      _activeConversation.lastMessage = text;
      _activeConversation.time = 'Now';
    });

    _messageController.clear();
  }

  void _sendQuickEmoji() {
    _messageController.text += ' 😊';
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );
  }

  String _currentTimeLabel() {
    final now = TimeOfDay.now();
    final hour = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final minute = now.minute.toString().padLeft(2, '0');
    final suffix = now.period == DayPeriod.am ? 'AM' : 'PM';

    return '$hour:$minute $suffix';
  }

  void _showDemoNotice(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;

            return Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: isWide
                      ? Row(
                          children: [
                            SizedBox(
                              width: 330,
                              child: _buildConversationPanel(),
                            ),
                            const VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: _border,
                            ),
                            Expanded(child: _buildChatPanel()),
                          ],
                        )
                      : _buildMobileLayout(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        SizedBox(height: 280, child: _buildConversationPanel()),
        const Divider(height: 1, thickness: 1, color: _border),
        Expanded(child: _buildChatPanel()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.16),
                  blurRadius: 18,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: _primary,
                  alignment: Alignment.center,
                  child: const Text(
                    'JR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JR CALL',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Premium Messaging Experience',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _HeaderIcon(
            icon: Icons.search_rounded,
            onTap: () {
              _showDemoNotice('Conversation search is active in this demo.');
            },
          ),
          const SizedBox(width: 8),
          _HeaderIcon(
            icon: Icons.more_vert_rounded,
            onTap: () {
              _showDemoNotice(
                'More messaging options will activate in the real backend phase.',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConversationPanel() {
    final conversations = _visibleConversations;

    return Container(
      color: _background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: _buildSearchField(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Recent',
                  selected: _selectedFilter == 0,
                  onTap: () {
                    setState(() {
                      _selectedFilter = 0;
                    });
                  },
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Unread',
                  selected: _selectedFilter == 1,
                  onTap: () {
                    setState(() {
                      _selectedFilter = 1;
                    });
                  },
                ),
                const Spacer(),
                Text(
                  '${conversations.length} chats',
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: conversations.isEmpty
                ? const Center(
                    child: Text(
                      'No conversations found',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: conversations.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];

                      final selected =
                          _conversations.indexOf(conversation) ==
                          _selectedConversationIndex;

                      return _ConversationTile(
                        conversation: conversation,
                        selected: selected,
                        onTap: () {
                          _selectConversation(conversation);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) {
        setState(() {});
      },
      decoration: InputDecoration(
        hintText: 'Search messages or people',
        hintStyle: const TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: _primary, size: 21),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
              )
            : null,
        filled: true,
        fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: _primary.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildChatPanel() {
    final conversation = _activeConversation;

    return Container(
      color: _surfaceSoft,
      child: Column(
        children: [
          _buildChatHeader(conversation),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              itemCount: _activeMessages.length,
              itemBuilder: (context, index) {
                return _MessageBubble(message: _activeMessages[index]);
              },
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildChatHeader(_DemoConversation conversation) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          _Avatar(
            text: conversation.avatarText,
            online: conversation.online,
            size: 42,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  conversation.online ? 'Online now' : conversation.username,
                  style: TextStyle(
                    color: conversation.online
                        ? const Color(0xFF16A34A)
                        : _textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _ChatActionButton(
            icon: Icons.call_rounded,
            color: const Color(0xFF16A34A),
            onTap: () {
              _showDemoNotice(
                'Voice call action is reserved for the real Call module.',
              );
            },
          ),
          const SizedBox(width: 7),
          _ChatActionButton(
            icon: Icons.videocam_rounded,
            color: const Color(0xFF0891B2),
            onTap: () {
              _showDemoNotice(
                'Video call action is reserved for the real Call module.',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ComposerIconButton(
            icon: Icons.add_rounded,
            onTap: () {
              _showDemoNotice(
                'Attachment picker will connect in the real messaging phase.',
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) {
                _sendMessage();
              },
              decoration: InputDecoration(
                hintText: 'Write a message...',
                hintStyle: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: _primary.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ComposerIconButton(
            icon: Icons.emoji_emotions_outlined,
            onTap: _sendQuickEmoji,
          ),
          const SizedBox(width: 8),
          _SendButton(onTap: _sendMessage),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
  });

  final _DemoConversation conversation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected
                ? _MessageDemoScreenState._primary.withValues(alpha: 0.08)
                : _MessageDemoScreenState._surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? _MessageDemoScreenState._primary.withValues(alpha: 0.25)
                  : _MessageDemoScreenState._border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              _Avatar(
                text: conversation.avatarText,
                online: conversation.online,
                size: 46,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _MessageDemoScreenState._textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          conversation.time,
                          style: const TextStyle(
                            color: _MessageDemoScreenState._textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: conversation.unreadCount > 0
                                  ? _MessageDemoScreenState._textPrimary
                                  : _MessageDemoScreenState._textSecondary,
                              fontSize: 12,
                              fontWeight: conversation.unreadCount > 0
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (conversation.unreadCount > 0) ...[
                          const SizedBox(width: 7),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: _MessageDemoScreenState._secondary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${conversation.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _DemoMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          gradient: mine
              ? const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                )
              : null,
          color: mine ? null : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 5),
            bottomRight: Radius.circular(mine ? 5 : 18),
          ),
          border: mine
              ? null
              : Border.all(color: _MessageDemoScreenState._border),
          boxShadow: [
            BoxShadow(
              color: mine
                  ? _MessageDemoScreenState._primary.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message.text,
                style: TextStyle(
                  color: mine
                      ? Colors.white
                      : _MessageDemoScreenState._textPrimary,
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.time,
              style: TextStyle(
                color: mine
                    ? Colors.white.withValues(alpha: 0.72)
                    : _MessageDemoScreenState._textSecondary,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.text, required this.online, required this.size});

  final String text;
  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
            ),
            boxShadow: [
              BoxShadow(
                color: _MessageDemoScreenState._primary.withValues(alpha: 0.16),
                blurRadius: 14,
              ),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.31,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6F4FF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: _MessageDemoScreenState._primary),
        ),
      ),
    );
  }
}

class _ChatActionButton extends StatelessWidget {
  const _ChatActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F3FF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(width: 40, height: 40, child: Center()),
      ),
    )._withIcon(icon);
  }
}

extension on Widget {
  Widget _withIcon(IconData icon) {
    return Stack(
      alignment: Alignment.center,
      children: [
        this,
        Icon(icon, color: _MessageDemoScreenState._primary, size: 21),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
            ),
            boxShadow: [
              BoxShadow(
                color: _MessageDemoScreenState._primary.withValues(alpha: 0.24),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? _MessageDemoScreenState._primary.withValues(alpha: 0.10)
                : Colors.white,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected
                  ? _MessageDemoScreenState._primary.withValues(alpha: 0.32)
                  : _MessageDemoScreenState._border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? _MessageDemoScreenState._primary
                  : _MessageDemoScreenState._textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoConversation {
  _DemoConversation({
    required this.name,
    required this.username,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
    required this.online,
    required this.avatarText,
  });

  final String name;
  final String username;

  String lastMessage;
  String time;

  int unreadCount;

  final bool online;
  final String avatarText;
}

class _DemoMessage {
  const _DemoMessage({
    required this.text,
    required this.isMine,
    required this.time,
  });

  final String text;
  final bool isMine;
  final String time;
}
