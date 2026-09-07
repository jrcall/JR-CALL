// ============================================================================
// JR CALL
// File: typing_indicator.dart
// Location: lib/features/message/widgets/typing_indicator.dart
//
// Realtime typing + Live Chat presentation component.
// Pure UI only: no Firestore, Storage, repository, or engine access.
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

enum TypingIndicatorMode { typing, liveChat }

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    super.key,
    this.mode = TypingIndicatorMode.typing,
    this.isTyping = false,
    this.liveText = '',
    this.styleSeed = 0,
    this.liveVersion = 0,
    this.active = true,
    this.expiry,
    this.typingLabel = 'Typing',
    this.liveLabel = 'LIVE CHAT',
    this.maxParticles = 96,
  });

  final TypingIndicatorMode mode;
  final bool isTyping;

  /// Peer Live Chat text only.
  final String liveText;

  /// Deterministic visual seed supplied by the Live Chat state.
  final int styleSeed;

  /// Incrementing peer Live Chat version/session value.
  final int liveVersion;

  final bool active;

  /// Optional server-derived Live Chat expiry.
  final DateTime? expiry;

  final String typingLabel;
  final String liveLabel;

  /// Visual particle cap. No independent particle widgets are created.
  final int maxParticles;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  static const Duration _typingCycle = Duration(milliseconds: 1100);
  static const Duration _disintegrationDuration = Duration(milliseconds: 1800);

  late final AnimationController _typingController;
  late final AnimationController _liveController;

  final List<_LiveParticle> _particles = <_LiveParticle>[];

  DateTime? _liveStartedAt;
  Duration _dwellDuration = Duration.zero;

  String _displayedText = '';
  int _displayedSeed = 0;
  int _displayedVersion = 0;

  @override
  void initState() {
    super.initState();

    _typingController = AnimationController(
      vsync: this,
      duration: _typingCycle,
    );

    _liveController = AnimationController(
      vsync: this,
      duration: _disintegrationDuration,
    )..addStatusListener(_handleLiveAnimationStatus);

    _syncTypingAnimation();
    _syncLiveDraft(force: true);
  }

  @override
  void didUpdateWidget(covariant TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isTyping != widget.isTyping ||
        oldWidget.mode != widget.mode ||
        oldWidget.active != widget.active) {
      _syncTypingAnimation();
    }

    final bool liveChanged =
        oldWidget.liveText != widget.liveText ||
        oldWidget.styleSeed != widget.styleSeed ||
        oldWidget.liveVersion != widget.liveVersion ||
        oldWidget.active != widget.active ||
        oldWidget.expiry != widget.expiry ||
        oldWidget.mode != widget.mode;

    if (liveChanged) {
      _syncLiveDraft();
    }
  }

  void _syncTypingAnimation() {
    final bool shouldAnimate =
        widget.mode == TypingIndicatorMode.typing &&
        widget.isTyping &&
        widget.active;

    if (shouldAnimate) {
      if (!_typingController.isAnimating) {
        _typingController.repeat();
      }
    } else {
      _typingController.stop();
      _typingController.value = 0;
    }
  }

  void _syncLiveDraft({bool force = false}) {
    if (widget.mode != TypingIndicatorMode.liveChat ||
        !widget.active ||
        widget.liveText.trim().isEmpty ||
        _isExpired(widget.expiry)) {
      _clearLiveVisual();
      return;
    }

    final String normalized = widget.liveText.trim();

    final bool sameDraft =
        !force &&
        normalized == _displayedText &&
        widget.styleSeed == _displayedSeed &&
        widget.liveVersion == _displayedVersion;

    if (sameDraft) {
      return;
    }

    _liveController.stop();
    _liveController.reset();

    _displayedText = normalized;
    _displayedSeed = widget.styleSeed;
    _displayedVersion = widget.liveVersion;

    _dwellDuration = _calculateDwell(text: normalized, expiry: widget.expiry);

    _liveStartedAt = DateTime.now();

    _buildParticles(text: normalized, seed: widget.styleSeed);

    if (mounted) {
      setState(() {});
    }

    _startLiveAnimationAfterDwell();
  }

  Future<void> _startLiveAnimationAfterDwell() async {
    final DateTime? startedAt = _liveStartedAt;
    if (startedAt == null) {
      return;
    }

    final Duration dwell = _dwellDuration;

    if (dwell > Duration.zero) {
      await Future<void>.delayed(dwell);
    }

    if (!mounted ||
        _liveStartedAt != startedAt ||
        widget.mode != TypingIndicatorMode.liveChat ||
        !widget.active ||
        _displayedText.isEmpty) {
      return;
    }

    if (_isExpired(widget.expiry)) {
      _clearLiveVisual();
      return;
    }

    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      _clearLiveVisual();
      return;
    }

    await _liveController.forward(from: 0);
  }

  Duration _calculateDwell({required String text, required DateTime? expiry}) {
    const int baseMilliseconds = 5000;
    const int maximumMilliseconds = 9000;

    final int extraCharacters = math.max(0, text.runes.length - 40);
    final int extraMilliseconds = math.min(4000, extraCharacters * 28);

    int milliseconds = math.min(
      maximumMilliseconds,
      baseMilliseconds + extraMilliseconds,
    );

    if (expiry != null) {
      final int remaining = expiry.difference(DateTime.now()).inMilliseconds;

      if (remaining <= 0) {
        return Duration.zero;
      }

      milliseconds = math.min(milliseconds, remaining);
    }

    return Duration(milliseconds: milliseconds);
  }

  bool _isExpired(DateTime? expiry) {
    if (expiry == null) {
      return false;
    }
    return !expiry.isAfter(DateTime.now());
  }

  void _buildParticles({required String text, required int seed}) {
    _particles.clear();

    final int safeCap = widget.maxParticles.clamp(24, 160);
    final int count = math.min(safeCap, math.max(32, text.runes.length * 2));

    final math.Random random = math.Random(
      seed ^ text.hashCode ^ widget.liveVersion,
    );

    for (int index = 0; index < count; index++) {
      _particles.add(
        _LiveParticle(
          x: random.nextDouble(),
          y: random.nextDouble(),
          size: 1.6 + random.nextDouble() * 3.8,
          driftX: 10 + random.nextDouble() * 38,
          driftY: -14 + random.nextDouble() * 28,
          rotation: random.nextDouble() * math.pi * 2,
          rotationSpeed: (-1.2 + random.nextDouble() * 2.4) * math.pi,
          delay: random.nextDouble() * 0.38,
          colorIndex: random.nextInt(_particlePalette.length),
          wingRatio: 0.55 + random.nextDouble() * 0.7,
        ),
      );
    }
  }

  void _handleLiveAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _clearLiveVisual();
    }
  }

  void _clearLiveVisual() {
    _liveStartedAt = null;
    _dwellDuration = Duration.zero;
    _displayedText = '';
    _displayedSeed = 0;
    _displayedVersion = 0;
    _particles.clear();

    _liveController.stop();
    _liveController.reset();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _liveStartedAt = null;
    _typingController.dispose();
    _liveController.removeStatusListener(_handleLiveAnimationStatus);
    _liveController.dispose();
    _particles.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.mode) {
      case TypingIndicatorMode.typing:
        return _buildTyping(context);
      case TypingIndicatorMode.liveChat:
        return _buildLiveChat(context);
    }
  }

  Widget _buildTyping(BuildContext context) {
    if (!widget.active || !widget.isTyping) {
      return const SizedBox.shrink();
    }

    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: '${widget.typingLabel}…',
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F1FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE7DEFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.typingLabel,
                  style: const TextStyle(
                    color: Color(0xFF7657D9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 7),
                if (reduceMotion)
                  const _StaticTypingDots()
                else
                  AnimatedBuilder(
                    animation: _typingController,
                    builder: (BuildContext context, Widget? child) {
                      return _AnimatedTypingDots(
                        progress: _typingController.value,
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveChat(BuildContext context) {
    if (!widget.active || _displayedText.isEmpty || _isExpired(widget.expiry)) {
      return const SizedBox.shrink();
    }

    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: '${widget.liveLabel}: $_displayedText',
        child: ExcludeSemantics(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 58, maxHeight: 156),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFFF5F8FF),
                  Color(0xFFFAF3FF),
                  Color(0xFFFFF3F9),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8E1F8)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF7157E8).withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE45AA7),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.liveLabel,
                      style: const TextStyle(
                        color: Color(0xFF7157E8),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Flexible(
                  child: reduceMotion
                      ? Text(
                          _displayedText,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: _liveTextStyle,
                        )
                      : AnimatedBuilder(
                          animation: _liveController,
                          builder: (BuildContext context, Widget? child) {
                            return _LiveDisintegrationView(
                              text: _displayedText,
                              progress: _liveController.value,
                              particles: _particles,
                            );
                          },
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

const TextStyle _liveTextStyle = TextStyle(
  color: Color(0xFF303344),
  fontSize: 15,
  height: 1.35,
  fontWeight: FontWeight.w500,
);

const List<Color> _particlePalette = <Color>[
  Color(0xFF3978F6),
  Color(0xFF7157E8),
  Color(0xFF9B67E8),
  Color(0xFFE45AA7),
  Color(0xFFF07DB6),
  Color(0xFF6D9DF8),
];

class _StaticTypingDots extends StatelessWidget {
  const _StaticTypingDots();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TypingDot(opacity: 0.55),
        SizedBox(width: 3),
        _TypingDot(opacity: 0.72),
        SizedBox(width: 3),
        _TypingDot(opacity: 0.9),
      ],
    );
  }
}

class _AnimatedTypingDots extends StatelessWidget {
  const _AnimatedTypingDots({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(3, (int index) {
        final double phase = (progress - (index * 0.16)) % 1.0;
        final double wave = (math.sin(phase * math.pi * 2) + 1) / 2;

        return Padding(
          padding: EdgeInsets.only(right: index == 2 ? 0 : 3),
          child: Transform.translate(
            offset: Offset(0, -1.8 * wave),
            child: _TypingDot(opacity: 0.38 + (wave * 0.62)),
          ),
        );
      }),
    );
  }
}

class _TypingDot extends StatelessWidget {
  const _TypingDot({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: const Color(
          0xFF7157E8,
        ).withValues(alpha: opacity.clamp(0.0, 1.0)),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _LiveDisintegrationView extends StatelessWidget {
  const _LiveDisintegrationView({
    required this.text,
    required this.progress,
    required this.particles,
  });

  final String text;
  final double progress;
  final List<_LiveParticle> particles;

  @override
  Widget build(BuildContext context) {
    final double clamped = progress.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (Rect bounds) {
                if (clamped <= 0) {
                  return const LinearGradient(
                    colors: <Color>[Colors.white, Colors.white],
                  ).createShader(bounds);
                }

                final double edge = clamped.clamp(0.0, 1.0);
                final double featherStart = math.max(0.0, edge - 0.08);

                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: const <Color>[
                    Colors.transparent,
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                  ],
                  stops: <double>[0, featherStart, edge, 1],
                ).createShader(bounds);
              },
              child: Text(
                text,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: _liveTextStyle,
              ),
            ),
            if (clamped > 0)
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _ButterflyParticlePainter(
                      progress: clamped,
                      particles: particles,
                      textWidth: width,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LiveParticle {
  const _LiveParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.driftX,
    required this.driftY,
    required this.rotation,
    required this.rotationSpeed,
    required this.delay,
    required this.colorIndex,
    required this.wingRatio,
  });

  final double x;
  final double y;
  final double size;
  final double driftX;
  final double driftY;
  final double rotation;
  final double rotationSpeed;
  final double delay;
  final int colorIndex;
  final double wingRatio;
}

class _ButterflyParticlePainter extends CustomPainter {
  const _ButterflyParticlePainter({
    required this.progress,
    required this.particles,
    required this.textWidth,
  });

  final double progress;
  final List<_LiveParticle> particles;
  final double textWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty || size.isEmpty) {
      return;
    }

    final double sweepX = textWidth * progress;

    for (final _LiveParticle particle in particles) {
      final double originX = particle.x * textWidth;

      if (originX > sweepX + 24) {
        continue;
      }

      final double activation = textWidth <= 0
          ? progress
          : (sweepX - originX) / math.max(1.0, textWidth * 0.28);

      final double localProgress =
          ((activation - particle.delay) / (1 - particle.delay)).clamp(
            0.0,
            1.0,
          );

      if (localProgress <= 0 || localProgress >= 1) {
        continue;
      }

      final double eased = Curves.easeOutCubic.transform(localProgress);

      final double opacity = (1 - Curves.easeIn.transform(localProgress)).clamp(
        0.0,
        1.0,
      );

      final double x = originX + particle.driftX * eased;

      final double baseY = particle.y * size.height;

      final double flutter =
          math.sin((localProgress * math.pi * 4) + particle.rotation) *
          particle.size *
          0.8;

      final double y = baseY + particle.driftY * eased + flutter;

      final Color color =
          _particlePalette[particle.colorIndex % _particlePalette.length]
              .withValues(alpha: opacity * 0.82);

      final Paint paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(particle.rotation + particle.rotationSpeed * localProgress);

      _paintButterfly(
        canvas: canvas,
        paint: paint,
        size: particle.size,
        wingRatio: particle.wingRatio,
        flap: math.sin(localProgress * math.pi * 8),
      );

      canvas.restore();
    }
  }

  void _paintButterfly({
    required Canvas canvas,
    required Paint paint,
    required double size,
    required double wingRatio,
    required double flap,
  }) {
    final double wingWidth = size * wingRatio * (0.72 + 0.18 * flap.abs());
    final double wingHeight = size * 0.72;

    final Path leftWing = Path()
      ..moveTo(-size * 0.08, 0)
      ..quadraticBezierTo(
        -wingWidth,
        -wingHeight,
        -wingWidth * 0.92,
        size * 0.08,
      )
      ..quadraticBezierTo(-wingWidth * 0.45, wingHeight, -size * 0.08, 0);

    final Path rightWing = Path()
      ..moveTo(size * 0.08, 0)
      ..quadraticBezierTo(wingWidth, -wingHeight, wingWidth * 0.92, size * 0.08)
      ..quadraticBezierTo(wingWidth * 0.45, wingHeight, size * 0.08, 0);

    canvas.drawPath(leftWing, paint);
    canvas.drawPath(rightWing, paint);

    final Paint bodyPaint = Paint()
      ..color = paint.color.withValues(
        alpha: (paint.color.a * 0.8).clamp(0.0, 1.0),
      )
      ..strokeWidth = math.max(0.7, size * 0.18)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    canvas.drawLine(Offset(0, -size * 0.32), Offset(0, size * 0.42), bodyPaint);
  }

  @override
  bool shouldRepaint(covariant _ButterflyParticlePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.particles != particles ||
        oldDelegate.textWidth != textWidth;
  }
}

// ============================================================================
// END OF FILE
// File: typing_indicator.dart
// Location: lib/features/message/widgets/typing_indicator.dart
// ============================================================================
