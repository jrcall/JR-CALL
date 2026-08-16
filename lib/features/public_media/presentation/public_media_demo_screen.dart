import 'package:flutter/material.dart';

/// ===========================================================
/// JR CALL
/// File: public_media_demo_screen.dart
/// Location:
/// lib/features/public_media/presentation/public_media_demo_screen.dart
///
/// Description:
/// Premium Public Media demo experience for JR CALL.
///
/// CURRENT PHASE:
/// - UI / interaction demo only
/// - No Firestore post writes
/// - No real media upload
/// - No real live streaming
/// - No fake production analytics
///
/// DESIGN:
/// - Premium light JR CALL UI
/// - Modern glassmorphism
/// - Soft orange / amber Public Media glow
/// - Rounded cards
/// - Responsive / SafeArea friendly
///
/// DEMO INTERACTIONS:
/// - Composer text input
/// - Text / Photo / Video / Live / More actions
/// - Feed tabs
/// - Like
/// - Comment
/// - Share
/// - Follow / Following
/// - Local demo post creation
///
/// IMPORTANT:
/// This file does NOT touch:
/// - CallService
/// - WebRTC
/// - Firebase
/// - Authentication
/// - Message backend
/// ===========================================================

class PublicMediaDemoScreen extends StatefulWidget {
  const PublicMediaDemoScreen({super.key});

  @override
  State<PublicMediaDemoScreen> createState() => _PublicMediaDemoScreenState();
}

class _PublicMediaDemoScreenState extends State<PublicMediaDemoScreen> {
  static const Color _background = Color(0xFFF8FAFD);
  static const Color _surface = Color(0xFFFFFFFF);

  static const Color _primaryOrange = Color(0xFFF97316);
  static const Color _secondaryAmber = Color(0xFFF59E0B);

  static const Color _primaryBlue = Color(0xFF087AF5);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF667085);
  static const Color _border = Color(0xFFE7EBF2);

  final TextEditingController _composerController = TextEditingController();

  int _selectedTab = 0;

  final List<String> _tabs = const [
    'For You',
    'Following',
    'Trending',
    'Nearby',
    'Live',
  ];

  final List<_PublicDemoPost> _posts = [
    _PublicDemoPost(
      author: 'Rakib Hasan',
      username: '@rakib.hasan',
      location: 'Dhaka, Bangladesh',
      avatarText: 'RH',
      time: '5m',
      text:
          'জীবনের আনন্দ ছোট ছোট মুহূর্তে। ❤️\n'
          'আজকের সুন্দর বিকেলটা সবার জন্য।',
      hashtags: '#PositiveVibes #Life',
      mediaType: _DemoMediaType.photo,
      mediaTitle: 'Nature • Sunset',
      likes: 128,
      comments: 24,
      shares: 12,
      isVerified: true,
      isFollowing: true,
    ),
    _PublicDemoPost(
      author: 'Sarah Ahmed',
      username: '@sarah',
      location: 'London, UK',
      avatarText: 'SA',
      time: '15m',
      text:
          'Beautiful sunset view today! 🌅✨\n'
          'Nature is truly amazing.',
      hashtags: '#Nature #Travel',
      mediaType: _DemoMediaType.photo,
      mediaTitle: 'Golden Hour',
      likes: 96,
      comments: 18,
      shares: 8,
      isVerified: false,
      isFollowing: false,
    ),
    _PublicDemoPost(
      author: 'JR Creators',
      username: '@jrcreators',
      location: 'Public Media',
      avatarText: 'JR',
      time: '1h',
      text: 'Short video creator preview inside JR CALL Public Media.',
      hashtags: '#Creator #Video',
      mediaType: _DemoMediaType.video,
      mediaTitle: 'Creator Video Preview',
      likes: 245,
      comments: 39,
      shares: 21,
      isVerified: true,
      isFollowing: false,
    ),
  ];

  List<_PublicDemoPost> get _visiblePosts {
    switch (_selectedTab) {
      case 1:
        return _posts.where((post) => post.isFollowing).toList();

      case 2:
        final result = List<_PublicDemoPost>.from(_posts);
        result.sort((a, b) => b.likes.compareTo(a.likes));
        return result;

      case 4:
        return _posts
            .where((post) => post.mediaType == _DemoMediaType.live)
            .toList();

      case 3:
      case 0:
      default:
        return _posts;
    }
  }

  void _showDemoNotice(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  void _selectComposerMode(_ComposerMode mode) {
    switch (mode) {
      case _ComposerMode.text:
        FocusScope.of(context).requestFocus(FocusNode());

        _showDemoNotice('Text composer is available in demo mode.');
        break;

      case _ComposerMode.photo:
        _showDemoNotice(
          'Photo selection will connect in the real Public Media backend phase.',
        );
        break;

      case _ComposerMode.video:
        _showDemoNotice(
          'Video selection will connect in the real Public Media backend phase.',
        );
        break;

      case _ComposerMode.live:
        _showDemoNotice('Live streaming is a demo preview in this phase.');
        break;

      case _ComposerMode.more:
        _showMoreActions();
        break;
    }
  }

  void _showMoreActions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
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
                const Text(
                  'More Public Media Options',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                _MoreActionTile(
                  icon: Icons.location_on_outlined,
                  label: 'Add Location',
                  color: _primaryOrange,
                  onTap: () {
                    Navigator.pop(context);
                    _showDemoNotice('Location is a demo action for now.');
                  },
                ),
                _MoreActionTile(
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'Tag People',
                  color: _primaryBlue,
                  onTap: () {
                    Navigator.pop(context);
                    _showDemoNotice('Tag People is a demo action for now.');
                  },
                ),
                _MoreActionTile(
                  icon: Icons.sentiment_satisfied_alt_rounded,
                  label: 'Feeling / Activity',
                  color: const Color(0xFFEAB308),
                  onTap: () {
                    Navigator.pop(context);
                    _showDemoNotice(
                      'Feeling / Activity selected in demo mode.',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _createDemoPost() {
    final text = _composerController.text.trim();

    if (text.isEmpty) {
      _showDemoNotice('Write something first.');
      return;
    }

    setState(() {
      _posts.insert(
        0,
        _PublicDemoPost(
          author: 'You',
          username: '@jrcall_user',
          location: 'JR CALL',
          avatarText: 'ME',
          time: 'Now',
          text: text,
          hashtags: '#JRCall',
          mediaType: _DemoMediaType.none,
          mediaTitle: '',
          likes: 0,
          comments: 0,
          shares: 0,
          isVerified: false,
          isFollowing: true,
        ),
      );

      _selectedTab = 0;
    });

    _composerController.clear();

    _showDemoNotice(
      'Demo post added locally. Nothing was uploaded to Firebase.',
    );
  }

  void _toggleLike(_PublicDemoPost post) {
    setState(() {
      post.liked = !post.liked;

      if (post.liked) {
        post.likes++;
      } else if (post.likes > 0) {
        post.likes--;
      }
    });
  }

  void _toggleFollow(_PublicDemoPost post) {
    setState(() {
      post.isFollowing = !post.isFollowing;
    });
  }

  void _openCommentSheet(_PublicDemoPost post) {
    final controller = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _border),
            ),
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
                const SizedBox(height: 16),
                const Text(
                  'Add Demo Comment',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Write a comment...',
                    filled: true,
                    fillColor: _background,
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
                      borderSide: const BorderSide(color: _primaryOrange),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      final value = controller.text.trim();

                      if (value.isEmpty) {
                        return;
                      }

                      setState(() {
                        post.comments++;
                      });

                      Navigator.pop(context);

                      _showDemoNotice('Demo comment added locally.');
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Comment',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                color: _primaryOrange,
                onRefresh: () async {
                  await Future<void>.delayed(const Duration(milliseconds: 550));

                  if (mounted) {
                    _showDemoNotice('Demo feed refreshed.');
                  }
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildComposer()),
                    SliverToBoxAdapter(child: _buildTabs()),
                    if (_visiblePosts.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        sliver: SliverList.separated(
                          itemCount: _visiblePosts.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final post = _visiblePosts[index];

                            return _PostCard(
                              post: post,
                              onLike: () {
                                _toggleLike(post);
                              },
                              onComment: () {
                                _openCommentSheet(post);
                              },
                              onShare: () {
                                setState(() {
                                  post.shares++;
                                });

                                _showDemoNotice('Demo share action completed.');
                              },
                              onFollow: () {
                                _toggleFollow(post);
                              },
                              onMediaTap: () {
                                _showDemoNotice(
                                  post.mediaType == _DemoMediaType.video
                                      ? 'Demo video preview selected.'
                                      : 'Demo media preview selected.',
                                );
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 12, 10),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.96),
        border: const Border(bottom: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
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
                  color: _primaryBlue.withValues(alpha: 0.18),
                  blurRadius: 15,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: _primaryBlue,
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
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Public Media',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _HeaderButton(
            icon: Icons.account_circle_rounded,
            color: _primaryOrange,
            tooltip: 'Profile',
            onTap: () {
              _showDemoNotice(
                'Profile navigation is controlled by the main JR CALL shell.',
              );
            },
          ),
          const SizedBox(width: 7),
          _HeaderButton(
            icon: Icons.search_rounded,
            color: _primaryBlue,
            tooltip: 'Search',
            onTap: () {
              _showDemoNotice(
                'Public Media search is demo-only in this phase.',
              );
            },
          ),
          const SizedBox(width: 7),
          _HeaderButton(
            icon: Icons.menu_rounded,
            color: _textPrimary,
            tooltip: 'Menu',
            onTap: _showMoreActions,
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _secondaryAmber.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _DemoAvatar(text: 'ME', size: 39),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _composerController,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: "What's on your mind?",
                    hintStyle: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: _background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: _primaryOrange,
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _primaryBlue,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _createDemoPost,
                  child: const SizedBox(
                    width: 48,
                    height: 44,
                    child: Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ComposerAction(
                  icon: Icons.text_fields_rounded,
                  label: 'Text',
                  color: _primaryBlue,
                  onTap: () {
                    _selectComposerMode(_ComposerMode.text);
                  },
                ),
                _ComposerAction(
                  icon: Icons.photo_outlined,
                  label: 'Photo',
                  color: const Color(0xFF16A34A),
                  onTap: () {
                    _selectComposerMode(_ComposerMode.photo);
                  },
                ),
                _ComposerAction(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  color: const Color(0xFF7C3AED),
                  onTap: () {
                    _selectComposerMode(_ComposerMode.video);
                  },
                ),
                _ComposerAction(
                  icon: Icons.live_tv_rounded,
                  label: 'Live',
                  color: const Color(0xFFE11D48),
                  onTap: () {
                    _selectComposerMode(_ComposerMode.live);
                  },
                ),
                _ComposerAction(
                  icon: Icons.more_horiz_rounded,
                  label: 'More',
                  color: _primaryOrange,
                  onTap: () {
                    _selectComposerMode(_ComposerMode.more);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_tabs.length, (index) {
            final selected = _selectedTab == index;

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setState(() {
                      _selectedTab = index;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? _primaryOrange.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: selected
                          ? Border.all(
                              color: _primaryOrange.withValues(alpha: 0.25),
                            )
                          : null,
                    ),
                    child: Text(
                      _tabs[index],
                      style: TextStyle(
                        color: selected ? _primaryOrange : _textSecondary,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryOrange.withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.dynamic_feed_outlined,
                color: _primaryOrange,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Nothing here yet',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This section is currently a polished demo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }
}

/// ===========================================================
/// Post Card
/// ===========================================================

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onFollow,
    required this.onMediaTap,
  });

  final _PublicDemoPost post;

  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onFollow;
  final VoidCallback onMediaTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: _PublicMediaDemoScreenState._surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _PublicMediaDemoScreenState._border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DemoAvatar(text: post.avatarText, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            post.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _PublicMediaDemoScreenState._textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (post.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            color: _PublicMediaDemoScreenState._primaryBlue,
                            size: 15,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${post.location} · ${post.time}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _PublicMediaDemoScreenState._textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: post.isFollowing
                    ? const Color(0xFFF2F4F7)
                    : _PublicMediaDemoScreenState._primaryBlue.withValues(
                        alpha: 0.08,
                      ),
                borderRadius: BorderRadius.circular(100),
                child: InkWell(
                  borderRadius: BorderRadius.circular(100),
                  onTap: onFollow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    child: Text(
                      post.isFollowing ? 'Following' : 'Follow',
                      style: TextStyle(
                        color: post.isFollowing
                            ? _PublicMediaDemoScreenState._textSecondary
                            : _PublicMediaDemoScreenState._primaryBlue,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                Icons.more_horiz_rounded,
                color: Color(0xFF98A2B3),
                size: 21,
              ),
            ],
          ),
          if (post.text.trim().isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              post.text,
              style: const TextStyle(
                color: _PublicMediaDemoScreenState._textPrimary,
                fontSize: 13,
                height: 1.38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (post.hashtags.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              post.hashtags,
              style: const TextStyle(
                color: _PublicMediaDemoScreenState._primaryBlue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (post.mediaType != _DemoMediaType.none) ...[
            const SizedBox(height: 11),
            _DemoMediaPreview(
              type: post.mediaType,
              title: post.mediaTitle,
              onTap: onMediaTap,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _PostAction(
                icon: post.liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: '${post.likes}',
                active: post.liked,
                activeColor: const Color(0xFFE11D48),
                onTap: onLike,
              ),
              const SizedBox(width: 18),
              _PostAction(
                icon: Icons.mode_comment_outlined,
                label: '${post.comments}',
                onTap: onComment,
              ),
              const Spacer(),
              _PostAction(
                icon: Icons.share_outlined,
                label: '${post.shares}',
                onTap: onShare,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ===========================================================
/// Demo Media Preview
/// ===========================================================

class _DemoMediaPreview extends StatelessWidget {
  const _DemoMediaPreview({
    required this.type,
    required this.title,
    required this.onTap,
  });

  final _DemoMediaType type;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    IconData icon;

    switch (type) {
      case _DemoMediaType.video:
        icon = Icons.play_circle_fill_rounded;
        break;

      case _DemoMediaType.live:
        icon = Icons.live_tv_rounded;
        break;

      case _DemoMediaType.photo:
        icon = Icons.photo_rounded;
        break;

      case _DemoMediaType.none:
        icon = Icons.image_not_supported_outlined;
        break;
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 165,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF3E6), Color(0xFFFFE0B2), Color(0xFFFDBA74)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: -20,
                bottom: -35,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
              ),
              Positioned(
                right: -35,
                top: -45,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _PublicMediaDemoScreenState._primaryOrange
                        .withValues(alpha: 0.13),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: type == _DemoMediaType.video ? 52 : 42,
                      color: _PublicMediaDemoScreenState._primaryOrange,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        color: _PublicMediaDemoScreenState._textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Demo media preview',
                      style: TextStyle(
                        color: _PublicMediaDemoScreenState._textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
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
/// Composer Action
/// ===========================================================

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
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
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Material(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 17),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
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
/// Header Button
/// ===========================================================

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.07),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: color, size: 19),
          ),
        ),
      ),
    );
  }
}

/// ===========================================================
/// Post Action
/// ===========================================================

class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor = _PublicMediaDemoScreenState._primaryOrange,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? activeColor
        : _PublicMediaDemoScreenState._textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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
/// Demo Avatar
/// ===========================================================

class _DemoAvatar extends StatelessWidget {
  const _DemoAvatar({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF087AF5), Color(0xFF7C3AED)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: _PublicMediaDemoScreenState._primaryBlue.withValues(
              alpha: 0.16,
            ),
            blurRadius: 12,
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.29,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// ===========================================================
/// More Action
/// ===========================================================

class _MoreActionTile extends StatelessWidget {
  const _MoreActionTile({
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _PublicMediaDemoScreenState._textPrimary,
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
/// Demo Models
/// ===========================================================

enum _ComposerMode { text, photo, video, live, more }

enum _DemoMediaType { none, photo, video, live }

class _PublicDemoPost {
  _PublicDemoPost({
    required this.author,
    required this.username,
    required this.location,
    required this.avatarText,
    required this.time,
    required this.text,
    required this.hashtags,
    required this.mediaType,
    required this.mediaTitle,
    required this.likes,
    required this.comments,
    required this.shares,
    required this.isVerified,
    required this.isFollowing,
  });

  final String author;
  final String username;
  final String location;
  final String avatarText;
  final String time;
  final String text;
  final String hashtags;

  final _DemoMediaType mediaType;
  final String mediaTitle;

  int likes;
  int comments;
  int shares;

  final bool isVerified;

  bool isFollowing;
  bool liked = false;
}
