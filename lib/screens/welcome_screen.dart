// ===============================================================
// JR CALL
// File: welcome_screen.dart
// Location: lib/screens/welcome_screen.dart
//
// PRODUCTION REFERENCE-MATCH WELCOME
// - Premium white / glass visual system.
// - JR CALL branding preserved.
// - Login / Create Account / Guest routing preserved.
// - No fake/demo authentication.
// - Responsive and overflow-safe.
// - Call Engine / WebRTC untouched.
// ===============================================================

import 'package:flutter/material.dart';

import '../core/theme/jr_colors.dart';
import '../core/theme/jr_typography.dart';
import 'create_account_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _openLogin(BuildContext context) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  Future<void> _openCreateAccount(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CreateAccountScreen()),
    );
  }

  Future<void> _continueAsGuest(BuildContext context) {
    return Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => const HomeScreen(initialIndex: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JrColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxHeight < 720;

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(24, compact ? 20 : 34, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (compact ? 40 : 58),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 470),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _Logo(compact: compact),

                        SizedBox(height: compact ? 14 : 18),

                        Text(
                          'JR CALL',
                          textAlign: TextAlign.center,
                          style: JrTypography.brandTitle,
                        ),

                        const SizedBox(height: 3),

                        Text(
                          'Premium Calling Experience',
                          textAlign: TextAlign.center,
                          style: JrTypography.bodySecondary,
                        ),

                        SizedBox(height: compact ? 50 : 68),

                        const Text(
                          'Welcome to JR CALL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: JrColors.textPrimary,
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'Connect with anyone, anywhere',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: JrColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),

                        const SizedBox(height: 20),

                        const _PageDots(),

                        SizedBox(height: compact ? 42 : 58),

                        _PrimaryAction(
                          icon: Icons.login_rounded,
                          label: 'Log In',
                          onTap: () => _openLogin(context),
                        ),

                        const SizedBox(height: 14),

                        _SecondaryAction(
                          icon: Icons.person_add_alt_1_rounded,
                          label: 'Create Account',
                          onTap: () => _openCreateAccount(context),
                        ),

                        const SizedBox(height: 14),

                        _SecondaryAction(
                          icon: Icons.visibility_rounded,
                          label: 'Continue as Guest',
                          onTap: () => _continueAsGuest(context),
                        ),

                        SizedBox(height: compact ? 36 : 58),

                        const _FooterNote(),
                      ],
                    ),
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

// ===============================================================
// LOGO
// ===============================================================

class _Logo extends StatelessWidget {
  const _Logo({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double size = compact ? 118 : 138;

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: JrColors.primaryBlue.withValues(alpha: 0.09)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: JrColors.primaryBlue.withValues(alpha: 0.13),
            blurRadius: 34,
            offset: const Offset(0, 13),
          ),
          const BoxShadow(
            color: Color(0x0A17233B),
            blurRadius: 15,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) {
                return Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(27),
                    color: JrColors.primaryBlue.withValues(alpha: 0.08),
                  ),
                  child: const Icon(
                    Icons.phone_in_talk_rounded,
                    color: JrColors.primaryBlue,
                    size: 58,
                  ),
                );
              },
        ),
      ),
    );
  }
}

// ===============================================================
// PAGE DOTS
// ===============================================================

class _PageDots extends StatelessWidget {
  const _PageDots();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _Dot(active: false),
        SizedBox(width: 9),
        _Dot(active: true),
        SizedBox(width: 9),
        _Dot(active: false),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: active ? 10 : 8,
      height: active ? 10 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? JrColors.primaryBlue
            : JrColors.primaryBlue.withValues(alpha: 0.16),
      ),
    );
  }
}

// ===============================================================
// PRIMARY ACTION
// ===============================================================

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[Color(0xFF2458F5), Color(0xFF139FF7)],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: JrColors.primaryBlue.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17),
            child: Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: Text(
                    label,
                    style: JrTypography.buttonLabel.copyWith(
                      color: Colors.white,
                      fontSize: 17,
                    ),
                  ),
                ),

                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// SECONDARY ACTION
// ===============================================================

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: JrColors.primaryBlue.withValues(alpha: 0.12),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0C17233B),
                blurRadius: 18,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: JrColors.primaryBlue.withValues(alpha: 0.10),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: JrColors.primaryBlue.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: JrColors.primaryBlue, size: 23),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: JrColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const Icon(
                Icons.chevron_right_rounded,
                color: JrColors.textPrimary,
                size: 27,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// FOOTER
// ===============================================================

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.shield_outlined,
          color: JrColors.primaryBlue.withValues(alpha: 0.72),
          size: 15,
        ),
        const SizedBox(width: 6),
        const Flexible(
          child: Text(
            'Secure • Private • Global',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: JrColors.textSecondary,
              fontSize: 10,
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
// COMPLETED: 10/11
// REMAINING: 1/11
//
// NEXT FILE: 11 — main.dart
// Location: lib/main.dart
// ===============================================================
