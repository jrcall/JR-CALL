import 'package:flutter/material.dart';

import 'caller_avatar.dart';

/// ===========================================================
/// JR CALL
/// File: incoming_call_card.dart
/// Location: lib/widgets/incoming_call_card.dart
///
/// Description:
/// Production-ready reusable premium incoming-call card.
///
/// Responsibilities:
/// - Display incoming caller identity
/// - Display voice/video call type
/// - Display caller avatar
/// - Accept incoming call
/// - Decline incoming call
///
/// Architecture:
/// - Presentation only
/// - No CallService logic
/// - No signaling logic
/// - No WebRTC logic
/// - No ICE logic
/// - No Firebase logic
///
/// Backward Compatibility:
/// Existing public constructor and parameters are preserved.
/// ===========================================================

class IncomingCallCard extends StatelessWidget {
  const IncomingCallCard({
    super.key,
    required this.callerName,
    this.callerImage,
    this.isVideoCall = false,
    required this.onAccept,
    required this.onDecline,
  });

  /// Caller display name.
  final String callerName;

  /// Optional caller profile image URL.
  final String? callerImage;

  /// False = voice call.
  /// True = video call.
  final bool isVideoCall;

  /// Parent owns actual call acceptance.
  final VoidCallback onAccept;

  /// Parent owns actual call rejection.
  final VoidCallback onDecline;

  // ===========================================================
  // JR CALL Design Tokens
  // ===========================================================

  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceSoft = Color(0xFFF8FBFF);

  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _secondaryBlue = Color(0xFF1557D9);

  static const Color _callGreen = Color(0xFF00D99B);
  static const Color _callGreenDark = Color(0xFF16A66F);

  static const Color _danger = Color(0xFFFF4D5A);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF58677F);

  static const Color _border = Color(0xFFDCE7F5);

  // ===========================================================
  // Safe Data
  // ===========================================================

  String get _safeCallerName {
    final String value = callerName.trim();

    if (value.isEmpty) {
      return 'JR CALL User';
    }

    return value;
  }

  String? get _safeCallerImage {
    final String? value = callerImage?.trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  String get _callTypeText {
    return isVideoCall ? 'Incoming Video Call' : 'Incoming Voice Call';
  }

  IconData get _callTypeIcon {
    return isVideoCall ? Icons.videocam_rounded : Icons.call_rounded;
  }

  // ===========================================================
  // Build
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$_callTypeText from $_safeCallerName',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFFFFFFF),
              Color(0xFFF8FBFF),
              Color(0xFFF4FCFF),
            ],
          ),
          border: Border.all(color: _border, width: 1),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x16087AF5),
              blurRadius: 30,
              spreadRadius: 1,
              offset: Offset(0, 12),
            ),
            BoxShadow(
              color: Color(0x0D00D99B),
              blurRadius: 30,
              spreadRadius: 2,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: <Widget>[
              const Positioned(
                top: -70,
                right: -55,
                child: _SoftGlow(size: 170, color: Color(0x18087AF5)),
              ),
              const Positioned(
                bottom: -70,
                left: -65,
                child: _SoftGlow(size: 160, color: Color(0x1400D99B)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _buildTopStatus(),

                    const SizedBox(height: 22),

                    CallerAvatar(
                      name: _safeCallerName,
                      imageUrl: _safeCallerImage,
                      radius: 50,
                      isOnline: true,
                      borderColor: _primaryBlue,
                      onlineColor: _callGreen,
                    ),

                    const SizedBox(height: 18),

                    Text(
                      _safeCallerName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 23,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(_callTypeIcon, size: 17, color: _primaryBlue),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            _callTypeText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    _buildActions(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // Incoming Status
  // ===========================================================

  Widget _buildTopStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _primaryBlue.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _callGreen,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0x5500D99B),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'JR CALL',
            style: TextStyle(
              color: _secondaryBlue,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // Actions
  // ===========================================================

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Expanded(
          child: _IncomingCallAction(
            semanticsLabel: 'Decline incoming call',
            label: 'Decline',
            icon: Icons.call_end_rounded,
            foregroundColor: _danger,
            backgroundColor: const Color(0xFFFFF2F3),
            borderColor: const Color(0xFFFFD4D8),
            glowColor: _danger,
            onTap: onDecline,
          ),
        ),

        const SizedBox(width: 24),

        Expanded(
          child: _IncomingCallAction(
            semanticsLabel: isVideoCall
                ? 'Accept incoming video call'
                : 'Accept incoming voice call',
            label: 'Accept',
            icon: isVideoCall ? Icons.videocam_rounded : Icons.call_rounded,
            foregroundColor: _surface,
            backgroundColor: _callGreenDark,
            borderColor: _callGreen,
            glowColor: _callGreen,
            onTap: onAccept,
          ),
        ),
      ],
    );
  }
}

/// ===========================================================
/// Premium Incoming Call Action
/// ===========================================================

class _IncomingCallAction extends StatelessWidget {
  const _IncomingCallAction({
    required this.semanticsLabel,
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.glowColor,
    required this.onTap,
  });

  final String semanticsLabel;
  final String label;

  final IconData icon;

  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
  final Color glowColor;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: backgroundColor,
                  border: Border.all(color: borderColor, width: 1.4),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.20),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Icon(icon, color: foregroundColor, size: 30),
              ),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: IncomingCallCard._textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// ===========================================================
/// Decorative Soft Glow
/// ===========================================================

class _SoftGlow extends StatelessWidget {
  const _SoftGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
