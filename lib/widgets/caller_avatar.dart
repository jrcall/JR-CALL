import 'package:flutter/material.dart';

/// ===========================================================
/// JR CALL
/// File: caller_avatar.dart
/// Location: lib/widgets/caller_avatar.dart
///
/// Description:
/// Production reusable premium caller avatar.
///
/// Used by:
/// - outgoing_call_screen.dart
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// - incoming_call_card.dart
///
/// Responsibilities:
/// - Render remote/user profile image
/// - Safe initials fallback
/// - Premium JR CALL border/glow
/// - Optional online indicator
///
/// Architecture:
/// - Presentation only
/// - No Firebase logic
/// - No CallService logic
/// - No WebRTC logic
/// - No network monitoring logic
///
/// Backward Compatibility:
/// Existing public constructor and parameters are preserved.
/// ===========================================================

class CallerAvatar extends StatelessWidget {
  const CallerAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 52,
    this.isOnline = false,
    this.showBorder = true,
    this.borderColor = const Color(0xFF3B82F6),
    this.onlineColor = const Color(0xFF22C55E),
  });

  /// Optional remote/user profile image URL.
  final String? imageUrl;

  /// Display name used for fallback initials.
  final String name;

  /// Avatar radius.
  final double radius;

  /// Whether online indicator should be visible.
  final bool isOnline;

  /// Whether premium outer border should be visible.
  final bool showBorder;

  /// Existing configurable border color.
  final Color borderColor;

  /// Existing configurable online indicator color.
  final Color onlineColor;

  // ===========================================================
  // Safe Values
  // ===========================================================

  String? get _safeImageUrl {
    final String? value = imageUrl?.trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  String get _safeName {
    final String value = name.trim();

    if (value.isEmpty) {
      return 'JR CALL User';
    }

    return value;
  }

  String get _initials {
    final List<String> parts = _safeName
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) {
      return 'JR';
    }

    if (parts.length == 1) {
      return _firstCharacter(parts.first);
    }

    return '${_firstCharacter(parts.first)}${_firstCharacter(parts.last)}';
  }

  String _firstCharacter(String value) {
    if (value.isEmpty) {
      return '';
    }

    return value.characters.first.toUpperCase();
  }

  // ===========================================================
  // Build
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    final double safeRadius = radius.clamp(18.0, 180.0);

    final double avatarDiameter = safeRadius * 2;

    final double borderWidth = safeRadius >= 52 ? 3 : 2.5;

    final double outerPadding = showBorder ? 4 : 0;

    final double onlineSize = (safeRadius * 0.32).clamp(13.0, 24.0);

    return Semantics(
      image: true,
      label: '$_safeName profile photo${isOnline ? ', online' : ''}',
      child: SizedBox(
        width: avatarDiameter + (outerPadding * 2),
        height: avatarDiameter + (outerPadding * 2),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: showBorder
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            borderColor.withValues(alpha: 0.95),
                            const Color(0xFF64BDF5),
                            const Color(0xFF00D99B),
                          ],
                        )
                      : null,
                  color: showBorder ? null : Colors.transparent,
                  boxShadow: showBorder
                      ? <BoxShadow>[
                          BoxShadow(
                            color: borderColor.withValues(alpha: 0.18),
                            blurRadius: 20,
                            spreadRadius: 1,
                          ),
                          const BoxShadow(
                            color: Color(0x1600D99B),
                            blurRadius: 26,
                            spreadRadius: 2,
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: Padding(
                  padding: EdgeInsets.all(showBorder ? borderWidth : 0),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FBFF),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(showBorder ? 2 : 0),
                      child: ClipOval(
                        child: _buildAvatarContent(
                          diameter: avatarDiameter,
                          radius: safeRadius,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (isOnline)
              Positioned(
                right: outerPadding + 2,
                bottom: outerPadding + 2,
                child: _buildOnlineIndicator(onlineSize),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // Avatar Content
  // ===========================================================

  Widget _buildAvatarContent({
    required double diameter,
    required double radius,
  }) {
    final String? url = _safeImageUrl;

    if (url == null) {
      return _buildFallback(radius);
    }

    return Image.network(
      url,
      width: diameter,
      height: diameter,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return _buildFallback(radius);
          },
      loadingBuilder:
          (
            BuildContext context,
            Widget child,
            ImageChunkEvent? loadingProgress,
          ) {
            if (loadingProgress == null) {
              return child;
            }

            return _buildLoadingState(radius);
          },
    );
  }

  // ===========================================================
  // Loading
  // ===========================================================

  Widget _buildLoadingState(double radius) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF5F9FF),
            Color(0xFFEAF4FF),
            Color(0xFFF5FFFC),
          ],
        ),
      ),
      child: Center(
        child: SizedBox(
          width: (radius * 0.38).clamp(18.0, 28.0),
          height: (radius * 0.38).clamp(18.0, 28.0),
          child: const CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Color(0xFF087AF5),
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // Fallback
  // ===========================================================

  Widget _buildFallback(double radius) {
    final double textSize = (radius * 0.52).clamp(18.0, 48.0);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFEAF3FF),
            Color(0xFFDFF5FF),
            Color(0xFFE8FFF8),
          ],
        ),
      ),
      child: Center(
        child: Text(
          _initials,
          maxLines: 1,
          style: TextStyle(
            color: const Color(0xFF1557D9),
            fontSize: textSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // Online Indicator
  // ===========================================================

  Widget _buildOnlineIndicator(double size) {
    return Semantics(
      label: 'Online',
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: onlineColor.withValues(alpha: 0.22),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: onlineColor, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
