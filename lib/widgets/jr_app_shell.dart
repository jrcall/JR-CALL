import 'package:flutter/material.dart';

import '../core/theme/jr_colors.dart';
import 'jr_app_header.dart';
import 'jr_bottom_navigation.dart';

/// ===============================================================
/// JR CALL — Global Authenticated Application Shell
/// File: jr_app_shell.dart
/// Location: lib/widgets/jr_app_shell.dart
///
/// MASTER STEP: 13
///
/// DESIGN:
/// Premium Light UI
/// Modern Glassmorphism
/// Soft Neon Gradient
///
/// PURPOSE:
/// Authenticated JR CALL screens-এর জন্য একটিমাত্র shared shell.
///
/// Owns:
/// - Global premium background
/// - Android/iOS top SafeArea
/// - JR CALL authenticated header
/// - Current feature body
/// - Global five-item bottom navigation
/// - Keyboard-safe layout behavior
///
/// IMPORTANT:
/// This widget contains UI coordination only.
///
/// It DOES NOT contain:
/// - Firebase Auth business logic
/// - Firestore business logic
/// - CallService/WebRTC logic
/// - Message backend logic
/// - Media backend logic
/// - AI backend logic
///
/// Parent/HomeScreen owns feature routing and actual business logic.
/// ===============================================================
class JrAppShell extends StatelessWidget {
  const JrAppShell({
    super.key,
    required this.body,
    required this.subtitle,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.profilePhotoUrl,
    this.onProfile,
    this.onSearch,
    this.onMenu,
    this.callBadge = 0,
    this.messageBadge = 0,
    this.publicMediaBadge = 0,
    this.videoReelsBadge = 0,
    this.aiToolsBadge = 0,
    this.showHeader = true,
    this.showBottomNavigation = true,
    this.bodyPadding = EdgeInsets.zero,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
  }) : assert(
         currentIndex >= 0 && currentIndex < 5,
         'currentIndex must be between 0 and 4.',
       ),
       assert(callBadge >= 0),
       assert(messageBadge >= 0),
       assert(publicMediaBadge >= 0),
       assert(videoReelsBadge >= 0),
       assert(aiToolsBadge >= 0);

  /// Current screen content.
  final Widget body;

  /// Header subtitle.
  ///
  /// Examples:
  /// Premium Calling Experience
  /// Premium Messaging Experience
  /// Public Media
  /// Video Reels
  /// All-in-One Tools
  /// Your Profile
  final String subtitle;

  /// Selected global navigation index.
  ///
  /// 0 = Call
  /// 1 = Message
  /// 2 = Public Media
  /// 3 = Video Reels
  /// 4 = AI Tools
  final int currentIndex;

  /// Parent/HomeScreen handles actual feature switching.
  final ValueChanged<int> onDestinationSelected;

  /// Authenticated user's real profile image URL.
  final String? profilePhotoUrl;

  /// Header actions.
  final VoidCallback? onProfile;
  final VoidCallback? onSearch;
  final VoidCallback? onMenu;

  /// Optional notification badges.
  final int callBadge;
  final int messageBadge;
  final int publicMediaBadge;
  final int videoReelsBadge;
  final int aiToolsBadge;

  /// Useful for special full-screen screens.
  final bool showHeader;
  final bool showBottomNavigation;

  /// Screen-specific body padding.
  final EdgeInsetsGeometry bodyPadding;

  /// Optional screen override.
  /// Normally JrColors.background is used globally.
  final Color? backgroundColor;

  /// Standard Flutter keyboard handling.
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? JrColors.background,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,

      // ===========================================================
      // MAIN AUTHENTICATED AREA
      // ===========================================================
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            // =====================================================
            // SHARED JR CALL HEADER
            // =====================================================
            if (showHeader)
              JrAppHeader(
                subtitle: subtitle,
                profilePhotoUrl: profilePhotoUrl,
                onProfile: onProfile,
                onSearch: onSearch,
                onMenu: onMenu,
              ),

            // =====================================================
            // CURRENT FEATURE BODY
            // =====================================================
            Expanded(
              child: RepaintBoundary(
                child: Padding(padding: bodyPadding, child: body),
              ),
            ),
          ],
        ),
      ),

      // ===========================================================
      // GLOBAL FIVE-DESTINATION NAVIGATION
      // ===========================================================
      bottomNavigationBar: showBottomNavigation
          ? JrBottomNavigation(
              currentIndex: currentIndex,
              onDestinationSelected: onDestinationSelected,
              callBadge: callBadge,
              messageBadge: messageBadge,
              publicMediaBadge: publicMediaBadge,
              videoReelsBadge: videoReelsBadge,
              aiToolsBadge: aiToolsBadge,
            )
          : null,
    );
  }
}
