// ===============================================================
// JR CALL
// File: ai_tools_demo_screen.dart
// Location: lib/features/ai_tools/presentation/ai_tools_demo_screen.dart
// Fixes: BUG 10
// Production-safe replacement
// Existing APIs preserved
//
// ALSO FIXED:
// - Removed blurry/double-layer tool-icon glow.
// - Preserved premium app-style colored tool icons.
// - Removed fake notification counters from bottom destinations.
// - Preserved all five bottom destinations.
// - Settings opens the real JR CALL SettingsScreen.
// - Privacy & Security opens the real SettingsScreen.
// - Public tool search is protected from credential autofill.
// - Search remains local and responsive.
// - Existing AiToolsDemoScreen constructor/API preserved.
// - No fake AI backend introduced.
// - No Call/WebRTC/Firestore ownership introduced.
// ===============================================================

import 'package:flutter/material.dart';

import '../../../screens/settings_screen.dart';

/// ===========================================================
/// JR CALL
/// File: ai_tools_demo_screen.dart
///
/// Description:
/// Premium AI Edit Post / All Tools hub.
///
/// CURRENT PHASE:
/// - Production-quality presentation surface
/// - AI creation tools remain UI/demo until real backend integration
/// - Real application Settings route is connected
/// - No fake cloud/backend/payment state
///
/// DESIGN:
/// - Premium white/light JR CALL UI
/// - Soft glass/neumorphic tool cards
/// - Clean application-style icons
/// - No blurry nested icon glow
/// - Responsive 2-column layout
/// - Five JR CALL destination preview buttons
/// ===========================================================

class AiToolsDemoScreen extends StatefulWidget {
  const AiToolsDemoScreen({super.key});

  @override
  State<AiToolsDemoScreen> createState() => _AiToolsDemoScreenState();
}

class _AiToolsDemoScreenState extends State<AiToolsDemoScreen> {
  // ===========================================================
  // DESIGN
  // ===========================================================

  static const Color _background = Color(0xFFF7F9FD);
  static const Color _surface = Color(0xFFFFFFFF);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF667085);

  static const Color _border = Color(0xFFE3EAF4);
  static const Color _primaryBlue = Color(0xFF087AF5);

  // ===========================================================
  // SEARCH
  // ===========================================================

  final TextEditingController _searchController = TextEditingController();

  String _query = '';

  // ===========================================================
  // TOOLS
  // ===========================================================

  static const List<_ToolItem> _tools = <_ToolItem>[
    _ToolItem(
      title: 'Text to Video',
      subtitle: 'AI Powered',
      icon: Icons.video_camera_front_rounded,
      color: Color(0xFF168CFF),
      secondaryColor: Color(0xFF42C8FF),
      aiBadge: true,
    ),
    _ToolItem(
      title: 'Video to Video',
      subtitle: 'AI Powered',
      icon: Icons.video_call_rounded,
      color: Color(0xFFE51AD5),
      secondaryColor: Color(0xFFB700CC),
      aiBadge: true,
    ),
    _ToolItem(
      title: 'Photo to Video',
      subtitle: 'AI Powered',
      icon: Icons.photo_library_rounded,
      color: Color(0xFF00C9A7),
      secondaryColor: Color(0xFF00A98F),
      aiBadge: true,
    ),
    _ToolItem(
      title: 'Music to Video',
      subtitle: 'AI Powered',
      icon: Icons.music_note_rounded,
      color: Color(0xFFFF8A00),
      secondaryColor: Color(0xFFFF5A00),
      aiBadge: true,
    ),
    _ToolItem(
      title: 'Voice to Video',
      subtitle: 'AI Powered',
      icon: Icons.mic_rounded,
      color: Color(0xFF8B3DFF),
      secondaryColor: Color(0xFF5D16DF),
      aiBadge: true,
    ),
    _ToolItem(
      title: 'Video Editing',
      subtitle: 'Pro Tools',
      icon: Icons.video_settings_rounded,
      color: Color(0xFF20B8FF),
      secondaryColor: Color(0xFF1377E9),
    ),
    _ToolItem(
      title: 'My Profile',
      subtitle: 'View & Manage',
      icon: Icons.person_rounded,
      color: Color(0xFF12C7D9),
      secondaryColor: Color(0xFF00A7C0),
    ),
    _ToolItem(
      title: 'Settings',
      subtitle: 'App Preferences',
      icon: Icons.settings_rounded,
      color: Color(0xFF3987FF),
      secondaryColor: Color(0xFF3154F5),
      realSettings: true,
    ),
    _ToolItem(
      title: 'Messages',
      subtitle: 'Your Conversations',
      icon: Icons.chat_bubble_rounded,
      color: Color(0xFFFF2E78),
      secondaryColor: Color(0xFFE70050),
    ),
    _ToolItem(
      title: 'My Files',
      subtitle: 'Documents & Media',
      icon: Icons.folder_rounded,
      color: Color(0xFFFFB020),
      secondaryColor: Color(0xFFFF8200),
    ),
    _ToolItem(
      title: 'Cloud Storage',
      subtitle: 'Save & Sync',
      icon: Icons.cloud_upload_rounded,
      color: Color(0xFF27B9FF),
      secondaryColor: Color(0xFF087AF5),
    ),
    _ToolItem(
      title: 'Contacts',
      subtitle: 'All Contacts',
      icon: Icons.contacts_rounded,
      color: Color(0xFF15D59B),
      secondaryColor: Color(0xFF00A86B),
    ),
    _ToolItem(
      title: 'Live Streaming',
      subtitle: 'Go Live Now',
      icon: Icons.podcasts_rounded,
      color: Color(0xFF9C45FF),
      secondaryColor: Color(0xFF6824E6),
    ),
    _ToolItem(
      title: 'Events',
      subtitle: 'Upcoming Events',
      icon: Icons.calendar_month_rounded,
      color: Color(0xFFFF3974),
      secondaryColor: Color(0xFFDC1554),
    ),
    _ToolItem(
      title: 'Marketplace',
      subtitle: 'Buy & Sell',
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFFFF9B16),
      secondaryColor: Color(0xFFFF6600),
    ),
    _ToolItem(
      title: 'Privacy & Security',
      subtitle: 'Stay Protected',
      icon: Icons.shield_rounded,
      color: Color(0xFF27BBFF),
      secondaryColor: Color(0xFF087AF5),
      realSettings: true,
    ),
  ];

  // ===========================================================
  // FILTERING
  // ===========================================================

  List<_ToolItem> get _visibleTools {
    final String value = _query.trim().toLowerCase();

    if (value.isEmpty) {
      return _tools;
    }

    return _tools
        .where((_ToolItem tool) {
          return tool.title.toLowerCase().contains(value) ||
              tool.subtitle.toLowerCase().contains(value);
        })
        .toList(growable: false);
  }

  // ===========================================================
  // NAVIGATION
  // ===========================================================

  Future<void> _openTool(_ToolItem tool) async {
    if (!mounted) {
      return;
    }

    if (tool.realSettings) {
      await _openSettings();
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _DemoToolPage(tool: tool),
      ),
    );
  }

  Future<void> _openSettings() async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SettingsScreen(),
      ),
    );
  }

  // ===========================================================
  // MESSAGE
  // ===========================================================

  void _showMessage(String message) {
    final String value = message.trim();

    if (!mounted || value.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(value),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  // ===========================================================
  // SEARCH SHEET
  // ===========================================================

  void _openSearch() {
    if (!mounted) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _border),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1A101828),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Search Tools',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,

                  // Public search field.
                  // Never advertise credential semantics.
                  autofillHints: const <String>[],
                  autocorrect: true,
                  enableSuggestions: true,
                  keyboardType: TextInputType.text,

                  onChanged: (String value) {
                    if (!mounted || value == _query) {
                      return;
                    }

                    setState(() {
                      _query = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search AI Tools...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();

                        if (!mounted) {
                          return;
                        }

                        setState(() {
                          _query = '';
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                    filled: true,
                    fillColor: _background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: _primaryBlue,
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text(
                      'View Results',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================
  // MENU
  // ===========================================================

  void _openMenu() {
    if (!mounted) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _border),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14101828),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'All Tools Menu',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              _MenuTile(
                icon: Icons.auto_awesome_rounded,
                title: 'AI Tools',
                color: const Color(0xFF8B3DFF),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                },
              ),
              _MenuTile(
                icon: Icons.settings_rounded,
                title: 'App Settings',
                color: _primaryBlue,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openSettings();
                },
              ),
              _MenuTile(
                icon: Icons.security_rounded,
                title: 'Privacy & Security',
                color: const Color(0xFF16A3F5),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openSettings();
                },
              ),
              _MenuTile(
                icon: Icons.info_outline_rounded,
                title: 'About Tools',
                color: const Color(0xFF16A34A),
                onTap: () {
                  Navigator.of(sheetContext).pop();

                  _showMessage(
                    'AI creation tools are presentation-ready. '
                    'Real AI processing is connected only when its '
                    'production backend is implemented.',
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================
  // BUILD
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    final List<_ToolItem> tools = _visibleTools;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double horizontalPadding = constraints.maxWidth < 380
                      ? 12
                      : 16;

                  return CustomScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: <Widget>[
                      if (_query.trim().isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              12,
                              horizontalPadding,
                              0,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    'Results for “$_query”',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _textSecondary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _searchController.clear();

                                    setState(() {
                                      _query = '';
                                    });
                                  },
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (tools.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptySearch(),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            18,
                            horizontalPadding,
                            24,
                          ),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate((
                              BuildContext context,
                              int index,
                            ) {
                              final _ToolItem tool = tools[index];

                              return _ToolCard(
                                tool: tool,
                                onTap: () {
                                  _openTool(tool);
                                },
                              );
                            }, childCount: tools.length),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: constraints.maxWidth < 380
                                      ? 10
                                      : 14,
                                  crossAxisSpacing: constraints.maxWidth < 380
                                      ? 10
                                      : 14,
                                  childAspectRatio: constraints.maxWidth < 380
                                      ? 1.40
                                      : 1.48,
                                ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            _buildBottomNavigationPreview(),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // HEADER
  // ===========================================================

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x09101828),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    return const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[Color(0xFF0569E8), Color(0xFF7A32E8)],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'JR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    );
                  },
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: <Widget>[
                      Text(
                        'JR ',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'CALL',
                        style: TextStyle(
                          color: _primaryBlue,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'AI Edit Post • All Tools',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF475467),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            icon: Icons.search_rounded,
            tooltip: 'Search tools',
            onTap: _openSearch,
          ),
          const SizedBox(width: 5),
          _HeaderAction(
            icon: Icons.settings_rounded,
            tooltip: 'Settings',
            onTap: _openSettings,
          ),
          const SizedBox(width: 5),
          _HeaderAction(
            icon: Icons.menu_rounded,
            tooltip: 'Menu',
            onTap: _openMenu,
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // FIVE DESTINATIONS
  // ===========================================================

  Widget _buildBottomNavigationPreview() {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x10101828),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _BottomItem(
              icon: Icons.call_rounded,
              label: 'Call',
              color: const Color(0xFF11C992),
              onTap: () {
                _showMessage(
                  'Call navigation is controlled by the main JR CALL shell.',
                );
              },
            ),
          ),
          Expanded(
            child: _BottomItem(
              icon: Icons.chat_bubble_rounded,
              label: 'Message',
              color: const Color(0xFFC438EE),
              onTap: () {
                _showMessage(
                  'Message navigation is controlled by the main JR CALL shell.',
                );
              },
            ),
          ),
          Expanded(
            child: _BottomItem(
              icon: Icons.grid_view_rounded,
              label: 'Public Media',
              color: const Color(0xFFF58220),
              onTap: () {
                _showMessage(
                  'Public Media navigation is controlled by '
                  'the main JR CALL shell.',
                );
              },
            ),
          ),
          Expanded(
            child: _BottomItem(
              icon: Icons.videocam_rounded,
              label: 'Video Reels',
              color: const Color(0xFF16B9F6),
              onTap: () {
                _showMessage(
                  'Video Reels navigation is controlled by '
                  'the main JR CALL shell.',
                );
              },
            ),
          ),
          Expanded(
            child: _BottomItem(
              icon: Icons.auto_awesome_rounded,
              label: 'All Tools',
              color: const Color(0xFF9C45FF),
              selected: true,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // DISPOSE
  // ===========================================================

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

/// ===========================================================
/// TOOL CARD
/// ===========================================================

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.tool, required this.onTap});

  final _ToolItem tool;
  final VoidCallback onTap;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final _ToolItem tool = widget.tool;

    return Semantics(
      button: true,
      label: tool.title,
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                tool.color.withValues(alpha: 0.070),
                Colors.white,
              ],
            ),
            border: Border.all(color: tool.color.withValues(alpha: 0.16)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0D101828),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: widget.onTap,
              onTapDown: (_) {
                if (mounted) {
                  setState(() {
                    _pressed = true;
                  });
                }
              },
              onTapUp: (_) {
                if (mounted) {
                  setState(() {
                    _pressed = false;
                  });
                }
              },
              onTapCancel: () {
                if (mounted) {
                  setState(() {
                    _pressed = false;
                  });
                }
              },
              splashColor: tool.color.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    _ToolIcon(tool: tool),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            tool.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color.lerp(
                                const Color(0xFF11315A),
                                tool.color,
                                0.25,
                              ),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.08,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            tool.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF475467),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tool.aiBadge) ...<Widget>[
                      const SizedBox(width: 4),
                      Text(
                        'AI',
                        style: TextStyle(
                          color: tool.color,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                    if (tool.realSettings) ...<Widget>[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: tool.color,
                        size: 18,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===========================================================
/// CLEAN APP-STYLE TOOL ICON
///
/// BUG 10 FIX:
/// - No surrounding mini-card glow.
/// - No white halo.
/// - No extra border layer.
/// - No secondary shadow layer.
/// - Icon remains crisp.
/// - Premium app-style gradient preserved.
/// ===========================================================

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({required this.tool, this.size = 50});

  final _ToolItem tool;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.26),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[tool.color, tool.secondaryColor],
            ),
          ),
          child: Icon(tool.icon, color: Colors.white, size: size * 0.52),
        ),
      ),
    );
  }
}

/// ===========================================================
/// DEMO TOOL PAGE
/// ===========================================================

class _DemoToolPage extends StatefulWidget {
  const _DemoToolPage({required this.tool});

  final _ToolItem tool;

  @override
  State<_DemoToolPage> createState() => _DemoToolPageState();
}

class _DemoToolPageState extends State<_DemoToolPage> {
  bool _demoActivated = false;

  double _progress = 0;

  Future<void> _runDemo() async {
    if (_demoActivated) {
      setState(() {
        _demoActivated = false;
        _progress = 0;
      });

      return;
    }

    setState(() {
      _demoActivated = true;
      _progress = 0.18;
    });

    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (!mounted) {
      return;
    }

    setState(() {
      _progress = 0.58;
    });

    await Future<void>.delayed(const Duration(milliseconds: 280));

    if (!mounted) {
      return;
    }

    setState(() {
      _progress = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final _ToolItem tool = widget.tool;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101828),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        title: Text(
          tool.title,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      tool.color.withValues(alpha: 0.10),
                      Colors.white,
                    ],
                  ),
                  border: Border.all(color: tool.color.withValues(alpha: 0.18)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x0E101828),
                      blurRadius: 22,
                      offset: Offset(0, 9),
                    ),
                  ],
                ),
                child: Column(
                  children: <Widget>[
                    _ToolIcon(tool: tool, size: 78),
                    const SizedBox(height: 18),
                    Text(
                      tool.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      tool.subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'INTERACTIVE DEMO',
                      style: TextStyle(
                        color: tool.color,
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE3EAF4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Demo Workspace',
                      style: TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'This preview demonstrates the interaction '
                      'and visual workflow only. No production AI '
                      'generation is performed until its real '
                      'backend is connected.',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        height: 1.45,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      height: 120,
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE3EAF4)),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _demoActivated
                            ? Column(
                                key: const ValueKey<String>('active'),
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    _progress >= 1
                                        ? Icons.check_circle_rounded
                                        : Icons.auto_awesome_rounded,
                                    size: 40,
                                    color: tool.color,
                                  ),
                                  const SizedBox(height: 9),
                                  Text(
                                    _progress >= 1
                                        ? 'Demo completed'
                                        : 'Demo running...',
                                    style: TextStyle(
                                      color: tool.color,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                key: const ValueKey<String>('idle'),
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(tool.icon, size: 38, color: tool.color),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Ready for demo',
                                    style: TextStyle(
                                      color: Color(0xFF475467),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 7,
                        backgroundColor: tool.color.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(tool.color),
                      ),
                    ),
                    const SizedBox(height: 17),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: tool.color,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        onPressed: _runDemo,
                        icon: Icon(
                          _demoActivated
                              ? Icons.restart_alt_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          _demoActivated ? 'Reset Demo' : 'Start Demo',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
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

/// ===========================================================
/// HEADER ACTION
/// ===========================================================

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFF8FAFC),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 41,
            height: 41,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE7ECF3)),
            ),
            child: Icon(icon, size: 23, color: const Color(0xFF101828)),
          ),
        ),
      ),
    );
  }
}

/// ===========================================================
/// BOTTOM NAVIGATION PREVIEW
/// ===========================================================

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: selected ? 46 : 43,
                  height: selected ? 42 : 39,
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.12)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: color.withValues(alpha: selected ? 0.22 : 0.10),
                    ),
                    boxShadow: selected
                        ? <BoxShadow>[
                            BoxShadow(
                              color: color.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  child: Icon(icon, color: color, size: selected ? 24 : 22),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF101828)
                        : const Color(0xFF475467),
                    fontSize: 8.3,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===========================================================
/// MENU TILE
/// ===========================================================

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 42,
                height: 42,
                child: Icon(icon, color: color, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF98A2B3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===========================================================
/// EMPTY SEARCH
/// ===========================================================

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off_rounded, color: Color(0xFF98A2B3), size: 46),
            SizedBox(height: 12),
            Text(
              'No tools found',
              style: TextStyle(
                color: Color(0xFF101828),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Try another search.',
              style: TextStyle(color: Color(0xFF667085), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===========================================================
/// INTERNAL TOOL MODEL
/// ===========================================================

class _ToolItem {
  const _ToolItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.secondaryColor,
    this.aiBadge = false,
    this.realSettings = false,
  });

  final String title;
  final String subtitle;

  final IconData icon;

  final Color color;
  final Color secondaryColor;

  final bool aiBadge;

  /// True when the tile must open the real application SettingsScreen
  /// instead of a local tool-demo page.
  final bool realSettings;
}

// ===============================================================
// END OF FILE
//
// FIXED: BUG 10
//
// ALSO FIXED:
// - AI tool icons are now crisp and single-layer.
// - Tool cards retain premium glass/neumorphic appearance.
// - Every tool remains app-style and individually colored.
// - Fake bottom notification numbers removed.
// - All five destination buttons preserved.
// - Fifth destination remains All Tools.
// - Real SettingsScreen connected.
// - Privacy & Security connected to real SettingsScreen.
// - Search autofill credential semantics disabled.
// - Existing AiToolsDemoScreen public API preserved.
// - No Call Engine/WebRTC/Firebase signaling changes.
//
// STATUS: READY FOR FORMAT + ANALYZE
//
// RUN:
// dart format lib/features/ai_tools/presentation/ai_tools_demo_screen.dart
// flutter analyze
//
// FINAL REQUIRED FILE: COMPLETE
// NEXT: FINAL PROJECT VALIDATION
// ===============================================================
