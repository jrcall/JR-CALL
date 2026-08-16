import 'package:flutter/material.dart';

import '../core/theme/jr_colors.dart';
import '../core/theme/jr_typography.dart';

/// ===============================================================
/// JR CALL — Premium Shared Application Header
/// File: jr_app_header.dart
/// Location: lib/widgets/jr_app_header.dart
///
/// DESIGN:
/// Premium Light UI
/// Modern Glassmorphism
/// Soft Neon Gradient
///
/// PURPOSE:
/// Authenticated JR CALL screens-এর জন্য একটিমাত্র shared header.
///
/// Used by:
/// - Call
/// - Message
/// - Public Media
/// - Video Reels
/// - AI Tools
/// - Profile
/// - Contacts
/// - Call History
///
/// VISUAL CONTRACT:
/// [JR Logo]  JR CALL                 [Profile] [Search] [Menu]
///            Section Subtitle
///
/// IMPORTANT:
/// - UI only
/// - No authentication business logic
/// - No Firestore business logic
/// - No Call Engine business logic
/// - Profile/Search/Menu behavior callbacks দিয়ে parent screen নিয়ন্ত্রণ করবে
/// ===============================================================
class JrAppHeader extends StatelessWidget {
  const JrAppHeader({
    super.key,
    required this.subtitle,
    this.profilePhotoUrl,
    this.onProfile,
    this.onSearch,
    this.onMenu,
    this.showProfile = true,
    this.showSearch = true,
    this.showMenu = true,
    this.logoAsset = 'assets/images/logo.png',
  });

  /// Current section subtitle.
  ///
  /// Examples:
  /// Premium Calling Experience
  /// Premium Messaging Experience
  /// Public Media
  /// Video Reels
  /// All-in-One Tools
  final String subtitle;

  /// Current authenticated user's profile photo.
  ///
  /// Null/empty হলে premium fallback profile icon দেখাবে।
  final String? profilePhotoUrl;

  /// Opens real Profile screen.
  final VoidCallback? onProfile;

  /// Opens Search / Discovery.
  final VoidCallback? onSearch;

  /// Opens menu / drawer / options.
  final VoidCallback? onMenu;

  final bool showProfile;
  final bool showSearch;
  final bool showMenu;

  /// JR CALL logo asset.
  final String logoAsset;

  static const double _logoDesktop = 62;
  static const double _logoCompact = 52;

  static const double _avatarDesktop = 54;
  static const double _avatarCompact = 48;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 390;

    final horizontalPadding = compact ? 16.0 : 20.0;
    final logoSize = compact ? _logoCompact : _logoDesktop;
    final avatarSize = compact ? _avatarCompact : _avatarDesktop;

    return Semantics(
      container: true,
      header: true,
      label: 'JR CALL $subtitle',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          12,
          horizontalPadding,
          12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // =====================================================
            // JR CALL LOGO
            // =====================================================
            _Logo(assetPath: logoAsset, size: logoSize),

            SizedBox(width: compact ? 10 : 13),

            // =====================================================
            // BRAND + SECTION
            // =====================================================
            Expanded(
              child: _BrandBlock(subtitle: subtitle, compact: compact),
            ),

            SizedBox(width: compact ? 5 : 8),

            // =====================================================
            // PROFILE
            // =====================================================
            if (showProfile) ...[
              _ProfileButton(
                profilePhotoUrl: profilePhotoUrl,
                size: avatarSize,
                onTap: onProfile,
              ),
              SizedBox(width: compact ? 5 : 8),
            ],

            // =====================================================
            // SEARCH
            // =====================================================
            if (showSearch) ...[
              _HeaderActionButton(
                tooltip: 'Search',
                semanticLabel: 'Search JR CALL',
                icon: Icons.search_rounded,
                onTap: onSearch,
                compact: compact,
              ),
              SizedBox(width: compact ? 2 : 5),
            ],

            // =====================================================
            // MENU
            // =====================================================
            if (showMenu)
              _HeaderActionButton(
                tooltip: 'Menu',
                semanticLabel: 'Open JR CALL menu',
                icon: Icons.menu_rounded,
                onTap: onMenu,
                compact: compact,
                transparent: true,
              ),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================
/// LOGO
/// ===============================================================
class _Logo extends StatelessWidget {
  const _Logo({required this.assetPath, required this.size});

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'JR CALL logo',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.23),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: JrColors.primaryBlue.withValues(alpha: 0.16),
              blurRadius: 18,
              spreadRadius: 0.5,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    JrColors.primaryBlue,
                    JrColors.primaryBlue.withValues(alpha: 0.72),
                  ],
                ),
              ),
              child: const Center(
                child: Text(
                  'JR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ===============================================================
/// BRAND
/// ===============================================================
class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.subtitle, required this.compact});

  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'JR ',
                  style: JrTypography.headerBrand.copyWith(
                    fontSize: compact ? 21 : null,
                    color: JrColors.textPrimary,
                  ),
                ),
                TextSpan(
                  text: 'CALL',
                  style: JrTypography.headerBrand.copyWith(
                    fontSize: compact ? 21 : null,
                    color: JrColors.primaryBlue,
                  ),
                ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: JrTypography.headerSubtitle.copyWith(
            fontSize: compact ? 10.5 : null,
          ),
        ),
      ],
    );
  }
}

/// ===============================================================
/// PROFILE BUTTON
/// ===============================================================
class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.profilePhotoUrl,
    required this.size,
    required this.onTap,
  });

  final String? profilePhotoUrl;
  final double size;
  final VoidCallback? onTap;

  bool get _hasPhoto {
    final value = profilePhotoUrl?.trim();
    return value != null && value.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open profile',
      child: Tooltip(
        message: 'Profile',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(2.4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFF00D9FF),
                    Color(0xFF1769FF),
                    Color(0xFF7B2DFF),
                    Color(0xFFFF42E8),
                    Color(0xFF00D9FF),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1769FF).withValues(alpha: 0.25),
                    blurRadius: 15,
                    spreadRadius: 0.5,
                  ),
                  BoxShadow(
                    color: const Color(0xFFB43CFF).withValues(alpha: 0.17),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: ClipOval(
                  child: _hasPhoto
                      ? Image.network(
                          profilePhotoUrl!.trim(),
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const _ProfileFallback();
                          },
                        )
                      : const _ProfileFallback(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// PROFILE FALLBACK
/// ===============================================================
class _ProfileFallback extends StatelessWidget {
  const _ProfileFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14245D), Color(0xFF4523A9), Color(0xFFA72AF5)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.person_rounded, color: Colors.white, size: 31),
      ),
    );
  }
}

/// ===============================================================
/// SEARCH / MENU BUTTON
/// ===============================================================
class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.tooltip,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    required this.compact,
    this.transparent = false,
  });

  final String tooltip;
  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 43.0 : 48.0;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: transparent
                  ? null
                  : BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: JrColors.border.withValues(alpha: 0.70),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.055),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
              child: Icon(
                icon,
                size: compact ? 26 : 29,
                color: JrColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
