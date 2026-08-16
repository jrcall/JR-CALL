import 'package:flutter/material.dart';

import '../core/theme/jr_colors.dart';
import '../core/theme/jr_typography.dart';

/// ===============================================================
/// JR CALL — Premium Global Bottom Navigation
/// File: jr_bottom_navigation.dart
/// Location: lib/widgets/jr_bottom_navigation.dart
///
/// DESIGN:
/// Modern Glassmorphism
/// Soft Neon Gradient
/// Premium Light JR CALL UI
///
/// DESTINATIONS:
/// 0 = Call
/// 1 = Message
/// 2 = Public Media
/// 3 = Video Reels
/// 4 = AI Tools
///
/// IMPORTANT:
/// - Shared UI component only.
/// - Does NOT contain Call Engine logic.
/// - Does NOT contain Message/Media/Reels/AI backend logic.
/// - Parent screen owns navigation/routing.
/// - Exactly five destinations.
/// ===============================================================
class JrBottomNavigation extends StatelessWidget {
  const JrBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.callBadge = 0,
    this.messageBadge = 0,
    this.publicMediaBadge = 0,
    this.videoReelsBadge = 0,
    this.aiToolsBadge = 0,
    this.safeArea = true,
  }) : assert(
         currentIndex >= 0 && currentIndex < 5,
         'currentIndex must be between 0 and 4.',
       );

  /// Selected destination.
  final int currentIndex;

  /// Parent controls routing/navigation.
  final ValueChanged<int> onDestinationSelected;

  /// Optional notification counters.
  final int callBadge;
  final int messageBadge;
  final int publicMediaBadge;
  final int videoReelsBadge;
  final int aiToolsBadge;

  /// Keep navigation above Android/iOS system navigation.
  final bool safeArea;

  static const List<_JrNavigationItem> _items = [
    _JrNavigationItem(
      label: 'Call',
      icon: Icons.call_rounded,
      activeIcon: Icons.call_rounded,
      color: JrColors.callGreen,
    ),
    _JrNavigationItem(
      label: 'Message',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      color: JrColors.messagePurple,
    ),
    _JrNavigationItem(
      label: 'Public Media',
      icon: Icons.grid_view_rounded,
      activeIcon: Icons.grid_view_rounded,
      color: JrColors.mediaOrange,
    ),
    _JrNavigationItem(
      label: 'Video Reels',
      icon: Icons.videocam_outlined,
      activeIcon: Icons.videocam_rounded,
      color: JrColors.reelsCyan,
    ),
    _JrNavigationItem(
      label: 'AI Tools',
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome_rounded,
      color: JrColors.aiPurple,
    ),
  ];

  List<int> get _badges => [
    callBadge,
    messageBadge,
    publicMediaBadge,
    videoReelsBadge,
    aiToolsBadge,
  ];

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;

    final compact = width < 370;
    final veryCompact = width < 340;

    final horizontalPadding = veryCompact
        ? 6.0
        : compact
        ? 8.0
        : 12.0;

    final navigation = Container(
      margin: EdgeInsets.fromLTRB(horizontalPadding, 6, horizontalPadding, 6),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 5,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: JrColors.surfaceGlass.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: JrColors.border.withValues(alpha: 0.72),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: JrColors.primaryBlue.withValues(alpha: 0.045),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_items.length, (index) {
          return Expanded(
            child: _NavigationDestination(
              item: _items[index],
              selected: currentIndex == index,
              badge: _badges[index],
              compact: compact,
              onTap: () {
                if (currentIndex == index) {
                  return;
                }
                onDestinationSelected(index);
              },
            ),
          );
        }),
      ),
    );

    if (!safeArea) {
      return navigation;
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 2),
      child: navigation,
    );
  }
}

/// ===============================================================
/// SINGLE DESTINATION
/// ===============================================================
class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.item,
    required this.selected,
    required this.badge,
    required this.compact,
    required this.onTap,
  });

  final _JrNavigationItem item;
  final bool selected;
  final int badge;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 23.0 : 27.0;
    final boxSize = compact ? 44.0 : 50.0;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      value: badge > 0 ? '$badge notifications' : null,
      child: Tooltip(
        message: item.label,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: boxSize,
                        height: boxSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          color: selected
                              ? item.color.withValues(alpha: 0.105)
                              : Colors.white.withValues(alpha: 0.56),
                          border: Border.all(
                            color: selected
                                ? item.color.withValues(alpha: 0.32)
                                : JrColors.border.withValues(alpha: 0.42),
                            width: selected ? 1.1 : 0.7,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: item.color.withValues(alpha: 0.22),
                                    blurRadius: 17,
                                    spreadRadius: 0.5,
                                  ),
                                  BoxShadow(
                                    color: item.color.withValues(alpha: 0.10),
                                    blurRadius: 28,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.025,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                        ),
                        child: AnimatedScale(
                          scale: selected ? 1.06 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          child: Icon(
                            selected ? item.activeIcon : item.icon,
                            size: iconSize,
                            color: selected
                                ? item.color
                                : JrColors.textSecondary,
                          ),
                        ),
                      ),

                      // =================================================
                      // BADGE
                      // =================================================
                      if (badge > 0)
                        Positioned(
                          top: -5,
                          right: -6,
                          child: _Badge(count: badge),
                        ),
                    ],
                  ),

                  SizedBox(height: compact ? 4 : 5),

                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: selected
                        ? JrTypography.navigationLabelSelected.copyWith(
                            color: item.color,
                            fontSize: compact ? 9.5 : null,
                          )
                        : JrTypography.navigationLabel.copyWith(
                            fontSize: compact ? 9.5 : null,
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

/// ===============================================================
/// BADGE
/// ===============================================================
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  String get _text {
    if (count > 99) {
      return '99+';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count notifications',
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: JrColors.error,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: JrColors.error.withValues(alpha: 0.28),
              blurRadius: 8,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: Text(
          _text,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// NAVIGATION ITEM MODEL
/// ===============================================================
class _JrNavigationItem {
  const _JrNavigationItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color color;
}
