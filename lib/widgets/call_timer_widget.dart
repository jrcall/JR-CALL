import 'package:flutter/material.dart';

/// ===========================================================
/// JR CALL
/// File: call_timer_widget.dart
/// Location: lib/widgets/call_timer_widget.dart
///
/// Description:
/// Production-safe premium call-duration presentation widget.
///
/// Responsibilities:
/// - Display call duration received from CallService / Provider
/// - Format MM:SS or HH:MM:SS
/// - Preserve existing public API
/// - Provide JR CALL premium glass presentation
///
/// Architecture:
/// - Timer ownership -> CallService / Provider
/// - This widget owns NO timer
/// - This widget owns NO call lifecycle
/// - This widget owns NO signaling / ICE / WebRTC logic
///
/// Used by:
/// - call_screen.dart
/// - outgoing_call_screen.dart
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// ===========================================================

class CallTimerWidget extends StatelessWidget {
  const CallTimerWidget({
    super.key,
    required this.duration,
    this.textColor = Colors.white,
    this.fontSize = 22,
    this.fontWeight = FontWeight.w600,
    this.showHours = false,
  });

  /// Duration supplied by CallService / Provider.
  final Duration duration;

  /// Preserved existing presentation API.
  final Color textColor;
  final double fontSize;
  final FontWeight fontWeight;
  final bool showHours;

  // ===========================================================
  // Safe Duration
  // ===========================================================

  Duration get _safeDuration {
    if (duration.isNegative) {
      return Duration.zero;
    }

    return duration;
  }

  // ===========================================================
  // Formatting
  // ===========================================================

  String _formatDuration(Duration value) {
    final int totalHours = value.inHours;

    final String minutes = (value.inMinutes % 60).toString().padLeft(2, '0');

    final String seconds = (value.inSeconds % 60).toString().padLeft(2, '0');

    if (showHours || totalHours > 0) {
      final String hours = totalHours.toString().padLeft(2, '0');

      return '$hours:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  // ===========================================================
  // Build
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    final Duration safeDuration = _safeDuration;
    final String formattedDuration = _formatDuration(safeDuration);

    return Semantics(
      label: 'Call duration $formattedDuration',
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x1600D99B),
              blurRadius: 18,
              spreadRadius: 1,
              offset: Offset(0, 5),
            ),
            BoxShadow(
              color: Color(0x100087F5),
              blurRadius: 22,
              spreadRadius: 1,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00D99B),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color(0x5500D99B),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: Text(
                  formattedDuration,
                  key: ValueKey<int>(safeDuration.inSeconds),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    letterSpacing: 1.2,
                    height: 1.0,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
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
