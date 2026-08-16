// ===============================================================
// JR CALL
// File: incoming_call_screen.dart
// Location: lib/screens/incoming_call_screen.dart
// Fixes: BUG 07, BUG 08
// Production-safe replacement
// Existing APIs preserved
//
// IMPORTANT:
// - Incoming-call presentation only.
// - No WebRTC ownership.
// - No Firestore ownership.
// - No ICE ownership.
// - No signaling ownership.
// - No fake CONNECTED state.
// - Accept/Reject callbacks execute at most once after success.
// ===============================================================

import 'dart:async';

import 'package:flutter/material.dart';

typedef IncomingCallAction = FutureOr<void> Function();

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.callerName,
    required this.onAccept,
    required this.onReject,
    this.callerId,
    this.callerPhotoUrl,
    this.isVideoCall = false,
    this.subtitle,
  });

  final String callerName;
  final String? callerId;
  final String? callerPhotoUrl;
  final bool isVideoCall;
  final String? subtitle;

  final IncomingCallAction onAccept;
  final IncomingCallAction onReject;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  // =============================================================
  // DESIGN
  // =============================================================

  static const Color _background = Color(0xFFF5F8FE);
  static const Color _surface = Color(0xFFFFFFFF);

  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _deepBlue = Color(0xFF1557D9);

  static const Color _callGreen = Color(0xFF00D99B);
  static const Color _cyan = Color(0xFF04BDF5);
  static const Color _danger = Color(0xFFFF1744);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF58677F);
  static const Color _border = Color(0xFFDCE7F5);

  // =============================================================
  // STATE
  // =============================================================

  bool _isProcessing = false;
  bool _accepting = false;

  /// Once Accept/Decline succeeds, the same incoming screen must
  /// never fire another call action.
  bool _actionCompleted = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );

    _pulseAnimation = Tween<double>(begin: 0.97, end: 1.035).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // =============================================================
  // SAFE DISPLAY DATA
  // =============================================================

  String get _safeCallerName {
    final String value = widget.callerName.trim();

    return value.isEmpty ? 'Unknown Caller' : value;
  }

  String? get _safeCallerPhotoUrl {
    final String value = widget.callerPhotoUrl?.trim() ?? '';

    return value.isEmpty ? null : value;
  }

  String? get _safeCallerId {
    final String value = widget.callerId?.trim() ?? '';

    return value.isEmpty ? null : value;
  }

  String get _callLabel {
    final String customSubtitle = widget.subtitle?.trim() ?? '';

    if (customSubtitle.isNotEmpty) {
      return customSubtitle;
    }

    return widget.isVideoCall ? 'Incoming Video Call' : 'Incoming Voice Call';
  }

  String get _callerInitial {
    final String name = _safeCallerName;

    if (name == 'Unknown Caller') {
      return '?';
    }

    return name.characters.first.toUpperCase();
  }

  // =============================================================
  // ACCEPT CALL
  // =============================================================

  Future<void> _acceptCall() async {
    if (!mounted || _isProcessing || _actionCompleted) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _accepting = true;
    });

    bool succeeded = false;

    try {
      await Future<void>.sync(widget.onAccept);

      succeeded = true;
      _actionCompleted = true;
    } catch (error, stackTrace) {
      _reportError(source: 'Accept call', error: error, stackTrace: stackTrace);

      if (mounted) {
        _showActionError('Unable to accept the call. Please try again.');
      }
    } finally {
      // Never return from finally.
      // This keeps Dart analyzer clean and preserves thrown errors.
      if (mounted) {
        setState(() {
          _isProcessing = false;

          if (!succeeded) {
            _accepting = false;
          }
        });
      }
    }
  }

  // =============================================================
  // REJECT CALL
  // =============================================================

  Future<void> _rejectCall() async {
    if (!mounted || _isProcessing || _actionCompleted) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _accepting = false;
    });

    try {
      await Future<void>.sync(widget.onReject);

      _actionCompleted = true;
    } catch (error, stackTrace) {
      _reportError(source: 'Reject call', error: error, stackTrace: stackTrace);

      if (mounted) {
        _showActionError('Unable to decline the call. Please try again.');
      }
    } finally {
      // Never return from finally.
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // =============================================================
  // ERROR HANDLING
  // =============================================================

  void _showActionError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  void _reportError({
    required String source,
    required Object error,
    required StackTrace stackTrace,
  }) {
    debugPrint('JR CALL [IncomingCallScreen/$source] error: $error');

    debugPrintStack(
      label: 'JR CALL [IncomingCallScreen/$source]',
      stackTrace: stackTrace,
    );
  }

  // =============================================================
  // MAIN BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Incoming-call screen must be handled with Accept/Decline,
      // preventing accidental system-back dismissal.
      canPop: false,
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compact = constraints.maxHeight < 690;

              final double horizontalPadding = constraints.maxWidth < 360
                  ? 18
                  : 24;

              return Stack(
                children: <Widget>[
                  const Positioned.fill(child: _IncomingBackground()),
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      compact ? 14 : 20,
                      horizontalPadding,
                      compact ? 18 : 28,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - (compact ? 32 : 48),
                      ),
                      child: Column(
                        children: <Widget>[
                          _buildBrandHeader(),

                          SizedBox(height: compact ? 22 : 42),

                          _buildIncomingBadge(),

                          SizedBox(height: compact ? 20 : 34),

                          _buildCallerCard(compact: compact),

                          SizedBox(height: compact ? 22 : 34),

                          _buildCallInformation(),

                          SizedBox(height: compact ? 20 : 30),

                          if (_isProcessing) _buildProcessingState(),

                          if (_isProcessing)
                            SizedBox(height: compact ? 16 : 24),

                          _buildCallActions(compact: compact),

                          SizedBox(height: compact ? 18 : 26),

                          const _SecurityMessage(),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // =============================================================
  // JR CALL HEADER
  // =============================================================

  Widget _buildBrandHeader() {
    return Row(
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22087AF5),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    return const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[_primaryBlue, _deepBlue],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.phone_in_talk_rounded,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                    );
                  },
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'JR CALL',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Incoming Call',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: _border),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14087AF5),
                blurRadius: 13,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            widget.isVideoCall ? Icons.videocam_rounded : Icons.call_rounded,
            color: _primaryBlue,
            size: 21,
          ),
        ),
      ],
    );
  }

  // =============================================================
  // INCOMING BADGE
  // =============================================================

  Widget _buildIncomingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: const Color(0xFFBFEFE3)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2200D99B),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: _callGreen,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0x6600D99B),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              widget.isVideoCall
                  ? 'INCOMING VIDEO CALL'
                  : 'INCOMING VOICE CALL',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF11745E),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // CALLER CARD
  // =============================================================

  Widget _buildCallerCard({required bool compact}) {
    final double avatarSize = compact ? 136 : 164;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 22 : 30,
      ),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A087AF5),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: Color(0x1200D99B),
            blurRadius: 32,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          ScaleTransition(
            scale: _pulseAnimation,
            child: _buildCallerAvatar(size: avatarSize),
          ),
          SizedBox(height: compact ? 18 : 24),
          Text(
            _safeCallerName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize: compact ? 25 : 29,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          if (_safeCallerId != null) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxWidth: 270),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F6FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                _safeCallerId!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _deepBlue,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =============================================================
  // CALLER AVATAR
  // =============================================================

  Widget _buildCallerAvatar({required double size}) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_cyan, _primaryBlue, _callGreen],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x44087AF5), blurRadius: 30, spreadRadius: 3),
          BoxShadow(color: Color(0x3300D99B), blurRadius: 40, spreadRadius: 3),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: ClipOval(
          child: _safeCallerPhotoUrl == null
              ? _buildAvatarFallback()
              : Image.network(
                  _safeCallerPhotoUrl!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder:
                      (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                      ) {
                        return _buildAvatarFallback();
                      },
                ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFEAF5FF), Color(0xFFDDF9F4)],
        ),
      ),
      child: Text(
        _callerInitial,
        style: const TextStyle(
          color: _deepBlue,
          fontSize: 52,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  // =============================================================
  // CALL INFORMATION
  // =============================================================

  Widget _buildCallInformation() {
    return Column(
      children: <Widget>[
        Text(
          _callLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),

        // Do not claim connection before CallService/WebRTC
        // actually reports CONNECTED.
        const Text(
          'Choose Accept or Decline',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // =============================================================
  // PROCESSING
  // =============================================================

  Widget _buildProcessingState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: _primaryBlue,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _accepting ? 'Accepting call...' : 'Declining call...',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // ACCEPT / REJECT
  // =============================================================

  Widget _buildCallActions({required bool compact}) {
    final bool actionsEnabled = !_isProcessing && !_actionCompleted;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: _PremiumCallAction(
            semanticsLabel: 'Reject call',
            label: 'Decline',
            icon: Icons.call_end_rounded,
            foregroundColor: _danger,
            glowColor: _danger,
            enabled: actionsEnabled,
            compact: compact,
            onPressed: () {
              unawaited(_rejectCall());
            },
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _PremiumCallAction(
            semanticsLabel: widget.isVideoCall
                ? 'Accept video call'
                : 'Accept voice call',
            label: 'Accept',
            icon: widget.isVideoCall
                ? Icons.videocam_rounded
                : Icons.call_rounded,
            foregroundColor: _callGreen,
            glowColor: _callGreen,
            enabled: actionsEnabled,
            compact: compact,
            onPressed: () {
              unawaited(_acceptCall());
            },
          ),
        ),
      ],
    );
  }
}

// ===============================================================
// PREMIUM INCOMING CALL ACTION
// ===============================================================

class _PremiumCallAction extends StatelessWidget {
  const _PremiumCallAction({
    required this.semanticsLabel,
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.glowColor,
    required this.enabled,
    required this.compact,
    required this.onPressed,
  });

  final String semanticsLabel;
  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color glowColor;
  final bool enabled;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final double buttonSize = compact ? 68 : 76;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.45,
        duration: const Duration(milliseconds: 160),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onPressed : null,
                child: Container(
                  width: buttonSize,
                  height: buttonSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: foregroundColor.withValues(alpha: 0.32),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.24),
                        blurRadius: 23,
                        spreadRadius: 2,
                      ),
                      const BoxShadow(
                        color: Color(0x18000000),
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    size: compact ? 29 : 33,
                    color: foregroundColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===============================================================
// BACKGROUND DECORATION
// ===============================================================

class _IncomingBackground extends StatelessWidget {
  const _IncomingBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF8FBFF),
            Color(0xFFF3F7FE),
            Color(0xFFF5FCFA),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -90,
            right: -80,
            child: _GlowOrb(size: 240, color: Color(0x20087AF5)),
          ),
          Positioned(
            bottom: 90,
            left: -100,
            child: _GlowOrb(size: 260, color: Color(0x1800D99B)),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ===============================================================
// SECURITY MESSAGE
// ===============================================================

class _SecurityMessage extends StatelessWidget {
  const _SecurityMessage();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.shield_outlined, size: 15, color: Color(0xFF728199)),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'Call transport is handled by JR CALL Call Engine',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF728199),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ===============================================================
// END OF FILE
//
// FIXED: BUG 07, BUG 08
//
// ALSO FIXED:
// - Analyzer warning: no return inside finally.
// - Duplicate Accept blocked.
// - Duplicate Decline blocked.
// - Accept/Decline race blocked.
// - Failed action safely unlocks UI for retry.
// - Successful action cannot execute twice.
// - No fake CONNECTED message before WebRTC connection.
// - Existing constructor preserved.
// - Existing callback signatures preserved.
// - Existing incoming voice/video presentation preserved.
// - Small-screen scroll/overflow protection preserved.
// - No WebRTC/Firestore/ICE/signaling duplication.
//
// STATUS: READY FOR FORMAT + ANALYZE
//
// NEXT FILE: outgoing_call_screen.dart
// Location: lib/screens/outgoing_call_screen.dart
// ===============================================================
