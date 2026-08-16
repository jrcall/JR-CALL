import 'dart:async';

import 'package:flutter/material.dart';

/// ===========================================================
/// JR CALL
/// File: video_reels_demo_screen.dart
/// Location:
/// lib/features/video_reels/presentation/video_reels_demo_screen.dart
///
/// Description:
/// Premium interactive Video Reels demo screen.
///
/// CURRENT PHASE:
/// - UI / interactive demo only
/// - No Firebase writes
/// - No real video streaming
/// - No fake production analytics
/// - No Call Engine modification
///
/// DEMO INTERACTIONS:
/// - For You / Following / Trending / Nearby tabs
/// - Search
/// - Menu
/// - Follow / Unfollow
/// - Like / Unlike
/// - Comments preview
/// - Share preview
/// - More actions
/// - 1-second simulated video playback
/// - Bottom feature navigation demo feedback
///
/// The real video/backend implementation will be added later.
/// ===========================================================

class VideoReelsDemoScreen extends StatefulWidget {
  const VideoReelsDemoScreen({super.key});

  @override
  State<VideoReelsDemoScreen> createState() => _VideoReelsDemoScreenState();
}

class _VideoReelsDemoScreenState extends State<VideoReelsDemoScreen> {
  // ===========================================================
  // JR CALL premium design colors
  // ===========================================================

  static const Color _background = Color(0xFFF7FAFF);
  static const Color _surfaceSoft = Color(0xFFF8FBFF);

  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _reelsCyan = Color(0xFF00B8FF);
  static const Color _purple = Color(0xFF8B5CF6);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF667085);
  static const Color _border = Color(0xFFE7EDF6);

  static const Color _likeRed = Color(0xFFFF416C);

  // ===========================================================
  // Demo state
  // ===========================================================

  int _selectedTab = 0;
  int _selectedBottomItem = 3;

  bool _isFollowing = false;
  bool _isLiked = false;
  bool _isPlaying = false;

  int _likeCount = 12500;
  int _commentCount = 346;
  int _shareCount = 1200;

  double _videoProgress = 0.54;

  Timer? _playbackTimer;
  Timer? _progressTimer;

  final List<String> _tabs = const <String>[
    'For You',
    'Following',
    'Trending',
    'Nearby',
  ];

  // ===========================================================
  // Lifecycle
  // ===========================================================

  @override
  void dispose() {
    _cancelPlaybackTimers();
    super.dispose();
  }

  void _cancelPlaybackTimers() {
    _playbackTimer?.cancel();
    _progressTimer?.cancel();

    _playbackTimer = null;
    _progressTimer = null;
  }

  // ===========================================================
  // Demo playback
  // ===========================================================

  void _togglePlayback() {
    if (_isPlaying) {
      _stopPlayback();
      return;
    }

    _startPlayback();
  }

  void _startPlayback() {
    _cancelPlaybackTimers();

    setState(() {
      _isPlaying = true;
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _videoProgress += 0.012;

        if (_videoProgress >= 0.96) {
          _videoProgress = 0.54;
        }
      });
    });

    // Demo requirement:
    // play only briefly so the screen feels alive,
    // without pretending a real video backend exists.
    _playbackTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) {
        return;
      }

      _stopPlayback();
    });
  }

  void _stopPlayback() {
    _cancelPlaybackTimers();

    if (!mounted) {
      return;
    }

    setState(() {
      _isPlaying = false;
    });
  }

  // ===========================================================
  // Reels actions
  // ===========================================================

  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;

      if (_isLiked) {
        _likeCount += 1;
      } else if (_likeCount > 0) {
        _likeCount -= 1;
      }
    });
  }

  void _toggleFollow() {
    setState(() {
      _isFollowing = !_isFollowing;
    });

    _showSnackBar(
      _isFollowing
          ? 'Following @Anika_Official • Demo'
          : 'Unfollowed @Anika_Official • Demo',
    );
  }

  void _openComments() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DemoBottomSheet(
          title: 'Comments',
          subtitle: 'Interactive preview • Demo only',
          icon: Icons.chat_bubble_rounded,
          accentColor: _reelsCyan,
          child: Column(
            children: [
              _CommentPreview(
                initials: 'RH',
                name: 'Rakib Hasan',
                comment: 'Beautiful reel! 🔥',
                time: '2m',
                accentColor: _primaryBlue,
              ),
              const SizedBox(height: 12),
              _CommentPreview(
                initials: 'SA',
                name: 'Sarah Ahmed',
                comment: 'Love the vibe ✨',
                time: '5m',
                accentColor: _purple,
              ),
              const SizedBox(height: 18),
              TextField(
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Write a demo comment...',
                  prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Send demo comment',
                    onPressed: () {
                      Navigator.of(sheetContext).pop();

                      setState(() {
                        _commentCount += 1;
                      });

                      _showSnackBar(
                        'Demo comment added locally — nothing uploaded.',
                      );
                    },
                    icon: const Icon(Icons.send_rounded),
                  ),
                  filled: true,
                  fillColor: _surfaceSoft,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openShareSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DemoBottomSheet(
          title: 'Share Reel',
          subtitle: 'Choose a demo destination',
          icon: Icons.share_rounded,
          accentColor: _primaryBlue,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 14,
            children: [
              _ShareDestination(
                icon: Icons.message_rounded,
                label: 'Message',
                color: _purple,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _completeDemoShare('Message');
                },
              ),
              _ShareDestination(
                icon: Icons.link_rounded,
                label: 'Copy Link',
                color: _primaryBlue,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _completeDemoShare('Copy Link');
                },
              ),
              _ShareDestination(
                icon: Icons.people_alt_rounded,
                label: 'Friends',
                color: const Color(0xFF00BFA6),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _completeDemoShare('Friends');
                },
              ),
              _ShareDestination(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                color: const Color(0xFFFF8A00),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _completeDemoShare('More');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _completeDemoShare(String destination) {
    setState(() {
      _shareCount += 1;
    });

    _showSnackBar('$destination selected • Demo share only, nothing was sent.');
  }

  void _openMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DemoBottomSheet(
          title: 'More',
          subtitle: 'Video Reel demo actions',
          icon: Icons.more_horiz_rounded,
          accentColor: _textPrimary,
          child: Column(
            children: [
              _DemoActionTile(
                icon: Icons.bookmark_border_rounded,
                title: 'Save Reel',
                subtitle: 'Preview only',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showSnackBar('Saved locally for demo preview.');
                },
              ),
              _DemoActionTile(
                icon: Icons.not_interested_rounded,
                title: 'Not Interested',
                subtitle: 'Demo preference only',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showSnackBar('Demo preference updated locally.');
                },
              ),
              _DemoActionTile(
                icon: Icons.flag_outlined,
                title: 'Report',
                subtitle: 'No real report is submitted',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showSnackBar('Report flow preview only.');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================
  // Header demo actions
  // ===========================================================

  void _openProfileDemo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) {
          return const _SimpleDemoDestination(
            icon: Icons.person_rounded,
            title: 'Creator Profile',
            subtitle:
                '@Anika_Official\nProfile navigation preview for Video Reels.',
            accentColor: _purple,
          );
        },
      ),
    );
  }

  void _openSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DemoBottomSheet(
          title: 'Search Reels',
          subtitle: 'Demo local search experience',
          icon: Icons.search_rounded,
          accentColor: _primaryBlue,
          child: TextField(
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search creators, reels or hashtags',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _showSnackBar('Demo search completed locally.');
                },
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              filled: true,
              fillColor: _surfaceSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        );
      },
    );
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DemoBottomSheet(
          title: 'Video Reels',
          subtitle: 'Demo menu',
          icon: Icons.menu_rounded,
          accentColor: _primaryBlue,
          child: Column(
            children: [
              _DemoActionTile(
                icon: Icons.history_rounded,
                title: 'Watch History',
                subtitle: 'Coming in future Reels phase',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showSnackBar('Watch History preview.');
                },
              ),
              _DemoActionTile(
                icon: Icons.bookmark_rounded,
                title: 'Saved Reels',
                subtitle: 'Demo navigation',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showSnackBar('Saved Reels preview.');
                },
              ),
              _DemoActionTile(
                icon: Icons.tune_rounded,
                title: 'Reels Preferences',
                subtitle: 'Demo controls',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showSnackBar('Reels Preferences preview.');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DemoBottomSheet(
          title: 'Reels Filters',
          subtitle: 'Demo content preferences',
          icon: Icons.tune_rounded,
          accentColor: _reelsCyan,
          child: Column(
            children: [
              _FilterPreviewChip(
                icon: Icons.music_note_rounded,
                label: 'Music',
                color: _purple,
              ),
              const SizedBox(height: 10),
              _FilterPreviewChip(
                icon: Icons.sports_esports_rounded,
                label: 'Gaming',
                color: _primaryBlue,
              ),
              const SizedBox(height: 10),
              _FilterPreviewChip(
                icon: Icons.travel_explore_rounded,
                label: 'Travel',
                color: const Color(0xFF00BFA6),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================
  // Bottom demo navigation
  // ===========================================================

  void _handleBottomNavigation(int index) {
    if (index == _selectedBottomItem) {
      _showSnackBar('Video Reels is already open.');
      return;
    }

    setState(() {
      _selectedBottomItem = index;
    });

    final destination = switch (index) {
      0 => 'Call',
      1 => 'Message',
      2 => 'Public Media',
      3 => 'Video Reels',
      4 => 'AI Tools',
      _ => 'JR CALL',
    };

    if (index == 3) {
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (pageContext) {
              return _SimpleDemoDestination(
                icon: _bottomIcon(index),
                title: destination,
                subtitle:
                    '$destination navigation preview.\n'
                    'The shared Home/App Shell will own the final navigation.',
                accentColor: _bottomColor(index),
              );
            },
          ),
        )
        .then((value) {
          if (!mounted) {
            return;
          }

          setState(() {
            _selectedBottomItem = 3;
          });
        });
  }

  // ===========================================================
  // Utility
  // ===========================================================

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  String _compactCount(int value) {
    if (value >= 1000000) {
      final number = value / 1000000;
      return '${number.toStringAsFixed(number >= 10 ? 0 : 1)}M';
    }

    if (value >= 1000) {
      final number = value / 1000;
      return '${number.toStringAsFixed(number >= 10 ? 1 : 1)}K';
    }

    return value.toString();
  }

  IconData _bottomIcon(int index) {
    switch (index) {
      case 0:
        return Icons.call_rounded;
      case 1:
        return Icons.chat_bubble_rounded;
      case 2:
        return Icons.grid_view_rounded;
      case 3:
        return Icons.videocam_rounded;
      case 4:
        return Icons.auto_fix_high_rounded;
      default:
        return Icons.circle;
    }
  }

  Color _bottomColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFF00CFA5);
      case 1:
        return const Color(0xFFB93CFF);
      case 2:
        return const Color(0xFFFF8A00);
      case 3:
        return _reelsCyan;
      case 4:
        return const Color(0xFF9C4DFF);
      default:
        return _primaryBlue;
    }
  }

  String _bottomLabel(int index) {
    switch (index) {
      case 0:
        return 'Call';
      case 1:
        return 'Message';
      case 2:
        return 'Public Media';
      case 3:
        return 'Video Reels';
      case 4:
        return 'AI Tools';
      default:
        return '';
    }
  }

  int _bottomBadge(int index) {
    switch (index) {
      case 0:
        return 5;
      case 1:
        return 20;
      case 2:
        return 50;
      case 3:
        return 10;
      case 4:
        return 30;
      default:
        return 0;
    }
  }

  // ===========================================================
  // Build
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (layoutContext, constraints) {
            final double width = constraints.maxWidth;
            final bool compact = width < 380;

            return Column(
              children: [
                _buildHeader(compact),
                _buildCategoryTabs(compact),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 10 : 14,
                      8,
                      compact ? 10 : 14,
                      8,
                    ),
                    child: _buildReelCard(),
                  ),
                ),
                _buildBottomNavigation(compact),
              ],
            );
          },
        ),
      ),
    );
  }

  // ===========================================================
  // Header
  // ===========================================================

  Widget _buildHeader(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 10 : 14, 8),
      child: Row(
        children: [
          Container(
            width: compact ? 46 : 54,
            height: compact ? 46 : 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: _primaryBlue.withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF006DFF), Color(0xFF753BFF)],
                    ),
                  ),
                  child: const Text(
                    'JR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      const TextSpan(
                        text: 'JR ',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.7,
                        ),
                      ),
                      TextSpan(
                        text: 'CALL',
                        style: TextStyle(
                          color: _primaryBlue,
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Video Reels',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _HeaderCircleButton(
            tooltip: 'Creator profile',
            icon: Icons.person_rounded,
            accentColor: _purple,
            onTap: _openProfileDemo,
          ),
          const SizedBox(width: 8),
          _HeaderCircleButton(
            tooltip: 'Search',
            icon: Icons.search_rounded,
            accentColor: _textPrimary,
            onTap: _openSearch,
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Menu',
            onPressed: _openMenu,
            icon: const Icon(Icons.menu_rounded, color: _textPrimary, size: 30),
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // Tabs
  // ===========================================================

  Widget _buildCategoryTabs(bool compact) {
    return Container(
      margin: EdgeInsets.fromLTRB(compact ? 10 : 14, 5, compact ? 10 : 14, 8),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _primaryBlue.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (int index = 0; index < _tabs.length; index++)
            Expanded(
              child: _TabButton(
                label: _tabs[index],
                selected: _selectedTab == index,
                onTap: () {
                  setState(() {
                    _selectedTab = index;
                  });

                  _showSnackBar('${_tabs[index]} feed selected • Demo');
                },
              ),
            ),
          IconButton(
            tooltip: 'Filters',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: _openFilters,
            icon: const Icon(Icons.tune_rounded, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // Reel
  // ===========================================================

  Widget _buildReelCard() {
    return LayoutBuilder(
      builder: (cardContext, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _togglePlayback,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildReelVisual(),
                  _buildVisualOverlay(),
                  _buildPlayButton(),
                  _buildRightActions(),
                  _buildBottomMetadata(),
                  _buildPlaybackIndicator(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReelVisual() {
    return AnimatedScale(
      scale: _isPlaying ? 1.018 : 1,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF3E9F4),
              Color(0xFFF9D6D2),
              Color(0xFFC5DCF0),
              Color(0xFF73899F),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 42,
              left: 26,
              right: 26,
              bottom: 80,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                transform: Matrix4.translationValues(0, _isPlaying ? -4 : 0, 0),
                child: const _DemoPersonArtwork(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualOverlay() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.46, 1],
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.54),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    return Center(
      child: AnimatedScale(
        scale: _isPlaying ? 0.84 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _isPlaying ? 0.40 : 1,
          duration: const Duration(milliseconds: 180),
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: const Color(0xFF16243A).withValues(alpha: 0.78),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightActions() {
    return Positioned(
      right: 11,
      bottom: 108,
      child: Column(
        children: [
          GestureDetector(
            onTap: _toggleFollow,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.92),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: _purple.withValues(alpha: 0.32),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: _purple,
                        size: 31,
                      ),
                    ),
                    if (!_isFollowing)
                      Positioned(
                        bottom: -7,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: _purple,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 11),
                Text(
                  _isFollowing ? 'Following' : 'Follow',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _ReelActionButton(
            icon: _isLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            iconColor: _isLiked ? _likeRed : Colors.white,
            label: _compactCount(_likeCount),
            onTap: _toggleLike,
          ),
          const SizedBox(height: 16),
          _ReelActionButton(
            icon: Icons.chat_bubble_rounded,
            iconColor: Colors.white,
            label: _compactCount(_commentCount),
            onTap: _openComments,
          ),
          const SizedBox(height: 16),
          _ReelActionButton(
            icon: Icons.reply_rounded,
            iconColor: Colors.white,
            label: _compactCount(_shareCount),
            flipHorizontally: true,
            onTap: _openShareSheet,
          ),
          const SizedBox(height: 12),
          _ReelActionButton(
            icon: Icons.more_horiz_rounded,
            iconColor: Colors.white,
            label: '',
            onTap: _openMoreSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomMetadata() {
    return Positioned(
      left: 18,
      right: 76,
      bottom: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Flexible(
                child: Text(
                  '@Anika_Official',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: _primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Feel the beat! 💃✨',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '#Dance #Vibes #FYP',
            style: TextStyle(
              color: Color(0xFF65B5FF),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.music_note_rounded, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Original Sound - Anika_Official',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackIndicator() {
    return Positioned(
      left: 17,
      right: 17,
      bottom: 9,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: _videoProgress,
                  backgroundColor: Colors.white.withValues(alpha: 0.35),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            _isPlaying ? '00:16 / 00:28' : '00:15 / 00:28',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // Bottom navigation
  // ===========================================================

  Widget _buildBottomNavigation(bool compact) {
    return Container(
      margin: EdgeInsets.fromLTRB(compact ? 7 : 10, 0, compact ? 7 : 10, 7),
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (int index = 0; index < 5; index++)
            Expanded(
              child: _BottomFeatureButton(
                label: _bottomLabel(index),
                icon: _bottomIcon(index),
                color: _bottomColor(index),
                badge: _bottomBadge(index),
                selected: index == 3,
                compact: compact,
                onTap: () {
                  _handleBottomNavigation(index);
                },
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================
// Header circle button
// =============================================================

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.tooltip,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: accentColor.withValues(alpha: 0.22),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: accentColor, size: 25),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// Tab
// =============================================================

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFE4F1FF) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF087AF5).withValues(alpha: 0.12),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF087AF5)
                    : const Color(0xFF667085),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// Reel right-side action
// =============================================================

class _ReelActionButton extends StatelessWidget {
  const _ReelActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.flipHorizontally = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool flipHorizontally;

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(
      icon,
      color: iconColor,
      size: 31,
      shadows: const [Shadow(color: Colors.black38, blurRadius: 8)],
    );

    if (flipHorizontally) {
      iconWidget = Transform.flip(flipX: true, child: iconWidget);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Column(
            children: [
              iconWidget,
              if (label.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// Bottom navigation item
// =============================================================

class _BottomFeatureButton extends StatelessWidget {
  const _BottomFeatureButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.badge,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int badge;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: compact ? 42 : 46,
                    height: compact ? 42 : 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: color.withValues(alpha: selected ? 0.18 : 0.10),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(
                            alpha: selected ? 0.27 : 0.13,
                          ),
                          blurRadius: selected ? 18 : 10,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: color, size: compact ? 24 : 27),
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF304B),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badge.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF101828)
                      : const Color(0xFF667085),
                  fontSize: compact ? 9 : 9.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// Demo person artwork
// =============================================================

class _DemoPersonArtwork extends StatelessWidget {
  const _DemoPersonArtwork();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 260,
        height: 560,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 25,
              child: Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(
                  color: Color(0xFF3A2E37),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              top: 55,
              child: Container(
                width: 72,
                height: 82,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1C9B5),
                  borderRadius: BorderRadius.circular(36),
                ),
              ),
            ),
            Positioned(
              top: 120,
              child: Container(
                width: 182,
                height: 164,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5A8C1),
                  borderRadius: BorderRadius.circular(44),
                ),
              ),
            ),
            Positioned(
              top: 245,
              child: Container(
                width: 138,
                height: 126,
                decoration: BoxDecoration(
                  color: const Color(0xFF87A7C8),
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
            Positioned(
              top: 350,
              left: 64,
              child: Transform.rotate(
                angle: 0.04,
                child: Container(
                  width: 55,
                  height: 170,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9CB7D2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 350,
              right: 64,
              child: Transform.rotate(
                angle: -0.08,
                child: Container(
                  width: 55,
                  height: 170,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9CB7D2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 505,
              left: 49,
              child: Container(
                width: 75,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F6),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            Positioned(
              top: 505,
              right: 43,
              child: Container(
                width: 75,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F6),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// Generic modal sheet
// =============================================================

class _DemoBottomSheet extends StatelessWidget {
  const _DemoBottomSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        18 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D5DD),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF101828),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

// =============================================================
// Comment preview
// =============================================================

class _CommentPreview extends StatelessWidget {
  const _CommentPreview({
    required this.initials,
    required this.name,
    required this.comment,
    required this.time,
    required this.accentColor,
  });

  final String initials;
  final String name;
  final String comment;
  final String time;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: accentColor.withValues(alpha: 0.12),
          child: Text(
            initials,
            style: TextStyle(color: accentColor, fontWeight: FontWeight.w800),
          ),
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
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101828),
                      ),
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(comment, style: const TextStyle(color: Color(0xFF475467))),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================
// Share destination
// =============================================================

class _ShareDestination extends StatelessWidget {
  const _ShareDestination({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// Demo action tile
// =============================================================

class _DemoActionTile extends StatelessWidget {
  const _DemoActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: const Color(0xFF344054)),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF101828),
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF98A2B3),
      ),
      onTap: onTap,
    );
  }
}

// =============================================================
// Filter preview
// =============================================================

class _FilterPreviewChip extends StatelessWidget {
  const _FilterPreviewChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Color(0xFF98A2B3),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// Local demo destination
// =============================================================

class _SimpleDemoDestination extends StatelessWidget {
  const _SimpleDemoDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF101828),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE7EDF6)),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.12),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accentColor, size: 38),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF101828),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back to Video Reels'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
