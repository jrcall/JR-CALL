// ===============================================================
// JR CALL
// File: profile_studio_screen.dart
// Location: lib/screens/profile_studio_screen.dart
//
// PRODUCTION PROFILE STUDIO UI
//
// CONTRACT:
// - Presentation/UI only.
// - Receives real UserModel from ProfileScreen.
// - No Firebase ownership.
// - No Firestore writes.
// - No Storage ownership.
// - No Call Engine / WebRTC / signaling ownership.
// - All edit/media/account actions callback to ProfileScreen.
// - No fake followers/views/earnings/content numbers.
// - Premium creator-profile layout.
// - Secondary profile/account controls live inside Edit / More.
// ===============================================================

import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../widgets/caller_avatar.dart';

class ProfileStudioScreen extends StatelessWidget {
  const ProfileStudioScreen({
    super.key,
    required this.user,
    required this.busy,
    required this.onRefresh,
    required this.onEditName,
    required this.onEditUsername,
    required this.onEditJrCallId,
    required this.onEditBio,
    required this.onEditDateOfBirth,
    required this.onEditCountry,
    required this.onChangeProfilePhoto,
    required this.onRemoveProfilePhoto,
    required this.onChangeCoverPhoto,
    required this.onRemoveCoverPhoto,
    required this.onRemoveName,
    required this.onRemoveUsername,
    required this.onRemoveBio,
    required this.onRemoveDateOfBirth,
    required this.onRemoveCountry,
    required this.onEmailTap,
    required this.onPhoneTap,
    required this.onVerificationTap,
    required this.onProviderTap,
  });

  // =============================================================
  // DATA
  // =============================================================

  final UserModel user;
  final bool busy;

  // =============================================================
  // CALLBACKS
  // =============================================================

  final Future<void> Function() onRefresh;

  final VoidCallback onEditName;
  final VoidCallback onEditUsername;
  final VoidCallback onEditJrCallId;
  final VoidCallback onEditBio;
  final VoidCallback onEditDateOfBirth;
  final VoidCallback onEditCountry;

  final VoidCallback onChangeProfilePhoto;
  final VoidCallback onRemoveProfilePhoto;
  final VoidCallback onChangeCoverPhoto;
  final VoidCallback onRemoveCoverPhoto;

  final VoidCallback onRemoveName;
  final VoidCallback onRemoveUsername;
  final VoidCallback onRemoveBio;
  final VoidCallback onRemoveDateOfBirth;
  final VoidCallback onRemoveCountry;

  final VoidCallback onEmailTap;
  final VoidCallback onPhoneTap;
  final VoidCallback onVerificationTap;
  final VoidCallback onProviderTap;

  // =============================================================
  // DESIGN
  // =============================================================

  static const double _maxContentWidth = 820;

  static const Color _background = Color(0xFFF7F9FE);
  static const Color _surface = Colors.white;

  static const Color _primary = Color(0xFF1769F5);
  static const Color _violet = Color(0xFF8B3DFF);
  static const Color _pink = Color(0xFFFF3F87);
  static const Color _success = Color(0xFF12B76A);
  static const Color _error = Color(0xFFDC2626);

  static const Color _text = Color(0xFF111827);
  static const Color _secondary = Color(0xFF64748B);
  static const Color _border = Color(0xFFE3E9F3);

  // =============================================================
  // ROOT
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: _buildAppBar(context),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 36),
              children: <Widget>[
                _buildProfileHero(context),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: <Widget>[
                      _buildHeadlineMetrics(),
                      const SizedBox(height: 14),
                      _buildStudioOverview(),
                      const SizedBox(height: 16),
                      _buildContentFilters(),
                      const SizedBox(height: 14),
                      _buildCreatorFeedPlaceholder(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // APP BAR
  // =============================================================

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _background,
      foregroundColor: _text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: const Text(
        'Profile Studio',
        style: TextStyle(
          color: _text,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.4,
        ),
      ),
      actions: <Widget>[
        if (busy)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ),
        IconButton(
          tooltip: 'More',
          onPressed: busy
              ? null
              : () {
                  _showMoreSheet(context);
                },
          icon: const Icon(Icons.more_horiz_rounded, size: 27),
        ),
        const SizedBox(width: 5),
      ],
    );
  }

  // =============================================================
  // PROFILE HERO
  // =============================================================

  Widget _buildProfileHero(BuildContext context) {
    final String displayName = _displayName();
    final String? coverUrl = _clean(user.coverPhoto);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 250,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(child: _buildCover(coverUrl)),

                // -------------------------------------------------
                // COVER CAMERA
                // -------------------------------------------------
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _RoundGlassButton(
                    tooltip: 'Change cover photo',
                    icon: Icons.photo_camera_rounded,
                    iconColor: _violet,
                    onTap: busy ? null : onChangeCoverPhoto,
                  ),
                ),
              ],
            ),
          ),

          // =======================================================
          // AVATAR / NAME / EDIT
          // =======================================================
          Transform.translate(
            offset: const Offset(0, -48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      _buildAvatar(displayName),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () {
                                _showEditProfileSheet(context);
                              },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit Profile'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _text,
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: _border),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RoundGlassButton(
                        tooltip: 'Profile options',
                        icon: Icons.more_horiz_rounded,
                        iconColor: _secondary,
                        onTap: busy
                            ? null
                            : () {
                                _showMoreSheet(context);
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // -------------------------------------------------
                  // IDENTITY
                  // -------------------------------------------------
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 25,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      if (user.verified) ...<Widget>[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          color: _primary,
                          size: 21,
                        ),
                      ],
                    ],
                  ),

                  if (_hasValue(user.username))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '@${_normalizeUsername(user.username!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _secondary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                  if (_hasValue(user.userAddress))
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.badge_outlined,
                            size: 16,
                            color: _secondary,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'JR ID: ${user.userAddress!.trim()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: const TextStyle(
                                color: _secondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_hasValue(user.bio))
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        user.bio!.trim(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _secondary,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildAvatar(String displayName) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF60A5FA), width: 3),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x2A1769F5),
                blurRadius: 22,
                spreadRadius: 1,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: CallerAvatar(
            name: displayName,
            imageUrl: user.photoUrl,
            radius: 58,
            isOnline: user.online,
          ),
        ),
        Positioned(
          right: -3,
          bottom: 3,
          child: Material(
            color: _primary,
            elevation: 5,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: busy ? null : onChangeProfilePhoto,
              child: const Padding(
                padding: EdgeInsets.all(11),
                child: Icon(
                  Icons.photo_camera_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // =============================================================
  // COVER
  // =============================================================

  Widget _buildCover(String? coverUrl) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: coverUrl == null
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFFDCEAFF),
                  Color(0xFFE9E5FF),
                  Color(0xFFDDF8FF),
                ],
              )
            : null,
        image: coverUrl == null
            ? null
            : DecorationImage(image: NetworkImage(coverUrl), fit: BoxFit.cover),
      ),
      child: coverUrl == null
          ? const Center(
              child: Icon(
                Icons.landscape_rounded,
                size: 64,
                color: Color(0x553B82F6),
              ),
            )
          : const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0x33000000)],
                ),
              ),
            ),
    );
  }

  // =============================================================
  // HEADLINE METRICS
  // =============================================================

  Widget _buildHeadlineMetrics() {
    return _glassCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: const Row(
        children: <Widget>[
          Expanded(
            child: _HeadlineMetric(
              icon: Icons.visibility_rounded,
              value: '—',
              label: 'Total Views',
              color: _primary,
            ),
          ),
          _MetricDivider(),
          Expanded(
            child: _HeadlineMetric(
              icon: Icons.favorite_rounded,
              value: '—',
              label: 'Total Likes',
              color: _pink,
            ),
          ),
          _MetricDivider(),
          Expanded(
            child: _HeadlineMetric(
              icon: Icons.mode_comment_rounded,
              value: '—',
              label: 'Comments',
              color: _violet,
            ),
          ),
          _MetricDivider(),
          Expanded(
            child: _HeadlineMetric(
              icon: Icons.attach_money_rounded,
              value: '—',
              label: 'Earnings',
              color: _success,
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // STUDIO OVERVIEW
  // =============================================================

  Widget _buildStudioOverview() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFFFF7FE),
            Color(0xFFF8F9FF),
            Color(0xFFF3FCFF),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9DEFF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F7C3AED),
            blurRadius: 26,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Studio Overview',
                  style: TextStyle(
                    color: _text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD7E3F5)),
                ),
                child: const Text(
                  'Last 28 Days',
                  style: TextStyle(
                    color: _primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (constraints.maxWidth < 520) {
                return const Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _OverviewMetric(
                            label: 'Earnings',
                            value: '—',
                            color: _success,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _OverviewMetric(
                            label: 'Views',
                            value: '—',
                            color: _primary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _OverviewMetric(
                            label: 'Likes',
                            value: '—',
                            color: _pink,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _OverviewMetric(
                            label: 'Comments',
                            value: '—',
                            color: _violet,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return const Row(
                children: <Widget>[
                  Expanded(
                    child: _OverviewMetric(
                      label: 'Earnings',
                      value: '—',
                      color: _success,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _OverviewMetric(
                      label: 'Views',
                      value: '—',
                      color: _primary,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _OverviewMetric(
                      label: 'Likes',
                      value: '—',
                      color: _pink,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _OverviewMetric(
                      label: 'Comments',
                      value: '—',
                      color: _violet,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Row(
              children: <Widget>[
                Expanded(
                  child: _MiniMetric(label: 'Shares', value: '—'),
                ),
                Expanded(
                  child: _MiniMetric(label: 'Clicks', value: '—'),
                ),
                Expanded(
                  child: _MiniMetric(label: 'CTR', value: '—'),
                ),
                Expanded(
                  child: _MiniMetric(label: 'Retention', value: '—'),
                ),
                Expanded(
                  child: _MiniMetric(label: 'RPM', value: '—'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 11),

          const Text(
            'Real creator analytics will appear automatically when '
            'JR CALL Creator analytics is connected.',
            style: TextStyle(color: _secondary, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // CONTENT FILTERS
  // =============================================================

  Widget _buildContentFilters() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: const <Widget>[
          _ContentFilterChip(
            icon: Icons.grid_view_rounded,
            label: 'All Posts',
            selected: true,
          ),
          SizedBox(width: 8),
          _ContentFilterChip(icon: Icons.text_fields_rounded, label: 'Text'),
          SizedBox(width: 8),
          _ContentFilterChip(icon: Icons.image_outlined, label: 'Photo'),
          SizedBox(width: 8),
          _ContentFilterChip(
            icon: Icons.play_circle_fill_rounded,
            label: 'Short Videos',
          ),
          SizedBox(width: 8),
          _ContentFilterChip(
            icon: Icons.videocam_rounded,
            label: 'Long Videos',
          ),
        ],
      ),
    );
  }

  // =============================================================
  // CREATOR FEED PLACEHOLDER
  // =============================================================

  Widget _buildCreatorFeedPlaceholder() {
    return _glassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: <Color>[
                  _primary.withValues(alpha: 0.12),
                  _violet.withValues(alpha: 0.10),
                ],
              ),
            ),
            child: const Icon(
              Icons.dynamic_feed_outlined,
              color: _primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'Your Creator Feed',
            style: TextStyle(
              color: _text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Your real text posts, photos, short videos and long videos '
            'will appear here when Public Media and Creator repositories '
            'are activated.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _secondary, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // EDIT PROFILE SHEET
  // =============================================================

  Future<void> _showEditProfileSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return _ProfileBottomSheet(
          title: 'Edit Profile',
          child: Column(
            children: <Widget>[
              _sheetAction(
                sheetContext,
                icon: Icons.person_outline_rounded,
                title: 'Full Name',
                subtitle: _display(user.name),
                onTap: onEditName,
              ),
              _sheetAction(
                sheetContext,
                icon: Icons.alternate_email_rounded,
                title: 'Username',
                subtitle: _hasValue(user.username)
                    ? '@${_normalizeUsername(user.username!)}'
                    : 'Not added',
                onTap: onEditUsername,
              ),
              _sheetAction(
                sheetContext,
                icon: Icons.badge_outlined,
                title: 'JR CALL User ID',
                subtitle: _display(user.userAddress),
                onTap: onEditJrCallId,
              ),
              _sheetAction(
                sheetContext,
                icon: Icons.notes_rounded,
                title: 'Bio',
                subtitle: _display(user.bio),
                onTap: onEditBio,
              ),
              _sheetAction(
                sheetContext,
                icon: Icons.calendar_month_outlined,
                title: 'Date of Birth',
                subtitle: user.dateOfBirth == null
                    ? 'Not added'
                    : _formatDate(user.dateOfBirth!),
                onTap: onEditDateOfBirth,
              ),
              _sheetAction(
                sheetContext,
                icon: Icons.public_rounded,
                title: 'Country',
                subtitle: _country(),
                onTap: onEditCountry,
              ),
            ],
          ),
        );
      },
    );
  }

  // =============================================================
  // MORE / SETTINGS SHEET
  // =============================================================

  Future<void> _showMoreSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return _ProfileBottomSheet(
          title: 'Profile Settings',
          child: Column(
            children: <Widget>[
              _sheetSectionLabel('PROFILE MEDIA'),

              _sheetAction(
                sheetContext,
                icon: Icons.account_circle_outlined,
                title: user.hasProfilePhoto
                    ? 'Change Profile Photo'
                    : 'Add Profile Photo',
                subtitle: 'Profile picture',
                onTap: onChangeProfilePhoto,
              ),

              if (user.hasProfilePhoto)
                _sheetAction(
                  sheetContext,
                  icon: Icons.delete_outline_rounded,
                  title: 'Remove Profile Photo',
                  subtitle: 'Remove current profile image',
                  color: _error,
                  onTap: onRemoveProfilePhoto,
                ),

              _sheetAction(
                sheetContext,
                icon: Icons.image_outlined,
                title: user.hasCoverPhoto
                    ? 'Change Cover Photo'
                    : 'Add Cover Photo',
                subtitle: 'Profile background',
                onTap: onChangeCoverPhoto,
              ),

              if (user.hasCoverPhoto)
                _sheetAction(
                  sheetContext,
                  icon: Icons.delete_outline_rounded,
                  title: 'Remove Cover Photo',
                  subtitle: 'Remove current cover image',
                  color: _error,
                  onTap: onRemoveCoverPhoto,
                ),

              const Divider(height: 28),

              _sheetSectionLabel('ACCOUNT & SECURITY'),

              _sheetAction(
                sheetContext,
                icon: Icons.email_outlined,
                title: 'Email',
                subtitle: _emailSummary(),
                onTap: onEmailTap,
              ),

              _sheetAction(
                sheetContext,
                icon: Icons.phone_outlined,
                title: 'Phone Number',
                subtitle: _phoneSummary(),
                onTap: onPhoneTap,
              ),

              _sheetAction(
                sheetContext,
                icon: Icons.verified_user_outlined,
                title: 'Verification',
                subtitle: _verificationSummary(),
                onTap: onVerificationTap,
              ),

              _sheetAction(
                sheetContext,
                icon: Icons.key_outlined,
                title: 'Sign-in Provider',
                subtitle: _providerSummary(),
                onTap: onProviderTap,
              ),

              const Divider(height: 28),

              _sheetSectionLabel('REMOVE PROFILE INFORMATION'),

              if (_hasValue(user.name))
                _sheetAction(
                  sheetContext,
                  icon: Icons.person_remove_outlined,
                  title: 'Remove Full Name',
                  subtitle: 'Clear public name',
                  color: _error,
                  onTap: onRemoveName,
                ),

              if (user.hasUsername)
                _sheetAction(
                  sheetContext,
                  icon: Icons.alternate_email_rounded,
                  title: 'Remove Username',
                  subtitle: 'Release current username',
                  color: _error,
                  onTap: onRemoveUsername,
                ),

              if (_hasValue(user.bio))
                _sheetAction(
                  sheetContext,
                  icon: Icons.notes_rounded,
                  title: 'Remove Bio',
                  subtitle: 'Clear profile bio',
                  color: _error,
                  onTap: onRemoveBio,
                ),

              if (user.dateOfBirth != null)
                _sheetAction(
                  sheetContext,
                  icon: Icons.event_busy_outlined,
                  title: 'Remove Date of Birth',
                  subtitle: 'Clear date of birth',
                  color: _error,
                  onTap: onRemoveDateOfBirth,
                ),

              if (_hasValue(user.country) || _hasValue(user.countryCode))
                _sheetAction(
                  sheetContext,
                  icon: Icons.public_off_outlined,
                  title: 'Remove Country',
                  subtitle: 'Clear country information',
                  color: _error,
                  onTap: onRemoveCountry,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: _secondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _sheetAction(
    BuildContext sheetContext, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color color = _primary,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.09),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color == _error ? _error : _text,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _secondary, fontSize: 12, height: 1.3),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF94A3B8),
      ),
      onTap: busy
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              onTap();
            },
    );
  }

  // =============================================================
  // COMMON CARD
  // =============================================================

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  // =============================================================
  // HELPERS
  // =============================================================

  String? _clean(String? value) {
    final String normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  bool _hasValue(String? value) {
    return _clean(value) != null;
  }

  String _display(String? value) {
    return _clean(value) ?? 'Not added';
  }

  String _displayName() {
    return _clean(user.name) ??
        _clean(user.username) ??
        _clean(user.userAddress) ??
        'JR CALL User';
  }

  String _normalizeUsername(String value) {
    String normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized.trim();
  }

  String _formatDate(DateTime date) {
    final String day = date.day.toString().padLeft(2, '0');
    final String month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  String _country() {
    final String? country = _clean(user.country);
    final String? code = _clean(user.countryCode);

    if (country == null && code == null) {
      return 'Not added';
    }

    if (country != null && code != null) {
      return '$country ($code)';
    }

    return country ?? code!;
  }

  String _emailSummary() {
    final String? email = _clean(user.email);

    if (email == null) {
      return 'No email linked';
    }

    return user.emailVerified
        ? '$email • Verified'
        : '$email • Verification pending';
  }

  String _phoneSummary() {
    final String? phone = _clean(user.phone);

    if (phone == null) {
      return 'No phone linked';
    }

    return user.phoneVerified
        ? '$phone • Verified'
        : '$phone • Verification pending';
  }

  String _verificationSummary() {
    final bool hasEmail = _hasValue(user.email);
    final bool hasPhone = _hasValue(user.phone);

    if (hasEmail && user.emailVerified && hasPhone && user.phoneVerified) {
      return 'Email and Phone verified';
    }

    if (hasEmail && user.emailVerified) {
      if (hasPhone && !user.phoneVerified) {
        return 'Email verified • Phone pending';
      }

      return 'Email verified';
    }

    if (hasPhone && user.phoneVerified) {
      if (hasEmail && !user.emailVerified) {
        return 'Phone verified • Email pending';
      }

      return 'Phone verified';
    }

    if (hasEmail && hasPhone) {
      return 'Email and Phone verification pending';
    }

    if (hasEmail) {
      return 'Email verification pending';
    }

    if (hasPhone) {
      return 'Phone verification pending';
    }

    return 'No verified identity';
  }

  String _providerSummary() {
    final List<String> providers = user.signInProviders
        .map(_providerLabel)
        .where((String value) => value.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (providers.isNotEmpty) {
      return providers.join(', ');
    }

    final String? provider = _clean(user.provider);

    return provider == null ? 'Not available' : _providerLabel(provider);
  }

  String _providerLabel(String providerId) {
    switch (providerId.trim()) {
      case 'password':
        return 'Email / Password';

      case 'phone':
        return 'Phone';

      case 'google.com':
        return 'Google';

      case 'apple.com':
        return 'Apple';

      case 'facebook.com':
        return 'Facebook';

      default:
        return providerId.trim();
    }
  }
}

// ===============================================================
// HEADLINE METRIC
// ===============================================================

class _HeadlineMetric extends StatelessWidget {
  const _HeadlineMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// METRIC DIVIDER
// ===============================================================

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 54, color: const Color(0xFFE7ECF4));
  }
}

// ===============================================================
// OVERVIEW METRIC
// ===============================================================

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE8EBF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// MINI METRIC
// ===============================================================

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ===============================================================
// CONTENT FILTER
// ===============================================================

class _ContentFilterChip extends StatelessWidget {
  const _ContentFilterChip({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEEF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: selected ? const Color(0xFF66A7FF) : const Color(0xFFE5EAF2),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x090F172A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: 17,
            color: selected ? const Color(0xFF1769F5) : const Color(0xFF64748B),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF1769F5)
                  : const Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// ROUND GLASS BUTTON
// ===============================================================

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.tooltip,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              icon,
              color: onTap == null ? const Color(0xFFB6BFCC) : iconColor,
              size: 23,
            ),
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// PROFILE BOTTOM SHEET
// ===============================================================

class _ProfileBottomSheet extends StatelessWidget {
  const _ProfileBottomSheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFD8DEE8),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 17, 12, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// END OF FILE
//
// FINAL PROFILE STUDIO UI CONTRACT:
//
// ✓ Premium creator-profile appearance
// ✓ Cover photo preserved
// ✓ Profile photo preserved
// ✓ Camera actions preserved
// ✓ Full Name preserved
// ✓ Username preserved
// ✓ JR CALL User ID preserved
// ✓ JR ID horizontal overflow-safe
// ✓ Bio preserved
// ✓ Verified badge preserved
// ✓ Edit Profile retained
// ✓ More / Settings menu added
// ✓ Email / Phone / Verification / Provider retained
// ✓ Remove Profile/Cover retained
// ✓ Remove public fields retained
// ✓ Creator overview layout retained without fake numbers
// ✓ Content category UI added
// ✓ Real creator feed placeholder only
// ✓ No Firebase logic duplicated
// ✓ No Firestore writes added
// ✓ No Storage logic duplicated
// ✓ No Call Engine changes
// ✓ No WebRTC changes
// ✓ Existing ProfileScreen callback API preserved
//
// AFTER REPLACE:
//
// dart format lib/screens/profile_studio_screen.dart
// flutter analyze
//
// ===============================================================
