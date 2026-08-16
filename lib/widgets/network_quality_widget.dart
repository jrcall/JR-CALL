import 'package:flutter/material.dart';

import '../models/network_model.dart';

/// ===========================================================
/// JR CALL
/// File: network_quality_widget.dart
/// Location: lib/widgets/network_quality_widget.dart
///
/// Description:
/// Production network-quality presentation widget.
///
/// Responsibilities:
/// - Display current NetworkQuality state
/// - Show quality-specific icon
/// - Show optional quality label
/// - Match JR CALL premium light / glass UI
///
/// Architecture:
/// - Network state ownership remains outside this widget
/// - No network polling
/// - No connectivity logic
/// - No CallService logic
/// - Presentation only
///
/// Used by:
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// - call_bottom_bar.dart
/// ===========================================================

class NetworkQualityWidget extends StatelessWidget {
  const NetworkQualityWidget({
    super.key,
    required this.quality,
    this.showLabel = true,
    this.iconSize = 20,
  });

  /// Current quality supplied by NetworkProvider /
  /// CallQualityMonitor presentation binding.
  final NetworkQuality quality;

  /// Whether the text label should be rendered.
  final bool showLabel;

  /// Base icon size.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final Color accentColor = _qualityColor;
    final String qualityLabel = _qualityText;

    return Semantics(
      label: 'Network quality: $qualityLabel',
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 11 : 8,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accentColor.withValues(alpha: 0.22)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accentColor.withValues(alpha: 0.10),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SignalIndicator(
              quality: quality,
              color: accentColor,
              size: iconSize,
            ),
            if (showLabel) ...<Widget>[
              const SizedBox(width: 7),
              Text(
                qualityLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _labelColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color get _qualityColor {
    switch (quality) {
      case NetworkQuality.excellent:
        return const Color(0xFF00B884);

      case NetworkQuality.good:
        return const Color(0xFF15B8A6);

      case NetworkQuality.fair:
        return const Color(0xFFF59E0B);

      case NetworkQuality.poor:
        return const Color(0xFFF97316);

      case NetworkQuality.offline:
        return const Color(0xFFEF4444);
    }
  }

  Color get _labelColor {
    switch (quality) {
      case NetworkQuality.excellent:
      case NetworkQuality.good:
        return const Color(0xFF0F766E);

      case NetworkQuality.fair:
        return const Color(0xFFB45309);

      case NetworkQuality.poor:
        return const Color(0xFFC2410C);

      case NetworkQuality.offline:
        return const Color(0xFFB91C1C);
    }
  }

  String get _qualityText {
    switch (quality) {
      case NetworkQuality.excellent:
        return 'Excellent';

      case NetworkQuality.good:
        return 'Good';

      case NetworkQuality.fair:
        return 'Fair';

      case NetworkQuality.poor:
        return 'Poor';

      case NetworkQuality.offline:
        return 'Offline';
    }
  }
}

/// ===========================================================
/// Signal Indicator
///
/// Private presentation component.
/// Does not own or calculate network state.
/// ===========================================================

class _SignalIndicator extends StatelessWidget {
  const _SignalIndicator({
    required this.quality,
    required this.color,
    required this.size,
  });

  final NetworkQuality quality;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (quality == NetworkQuality.offline) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.signal_wifi_connected_no_internet_4_rounded,
          size: size,
          color: color,
        ),
      );
    }

    final int activeBars = _activeBarCount;

    return SizedBox(
      width: size + 2,
      height: size,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(4, (int index) {
          final bool active = index < activeBars;

          final double barWidth = (size / 7).clamp(2.0, 4.0);
          final double barHeight = size * (0.34 + (index * 0.18));

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: barWidth,
            height: barHeight,
            margin: EdgeInsets.only(right: index == 3 ? 0 : 2),
            decoration: BoxDecoration(
              color: active ? color : color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(3),
              boxShadow: active
                  ? <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: 0.15),
                        blurRadius: 5,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  int get _activeBarCount {
    switch (quality) {
      case NetworkQuality.excellent:
        return 4;

      case NetworkQuality.good:
        return 3;

      case NetworkQuality.fair:
        return 2;

      case NetworkQuality.poor:
        return 1;

      case NetworkQuality.offline:
        return 0;
    }
  }
}
