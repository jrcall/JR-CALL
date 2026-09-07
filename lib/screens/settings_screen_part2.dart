part of 'settings_screen.dart';

// ===============================================================
// JR CALL
// File: settings_screen_part2.dart
// Location: lib/screens/settings_screen_part2.dart
//
// SETTINGS SCREEN — PART 2 / 2
//
// OWNS:
//
// ✓ Account header UI
// ✓ Settings tiles
// ✓ Information cards
// ✓ Section titles
// ✓ Verification badge
// ✓ Danger Zone UI
// ✓ Sheet handle
// ✓ Password dialog models
// ✓ Generic input dialogs
// ✓ Password dialogs
// ✓ Confirmation dialogs
// ✓ OTP prompt
// ✓ Provider display helpers
// ✓ Validation helpers
// ✓ Settings error-message helpers
//
// IMPORTANT:
//
// This file is a PART of settings_screen.dart.
// It is NOT a standalone screen.
// It is NOT a service.
// It is NOT a Call Engine manager.
//
// settings_screen.dart MUST contain:
//
// part 'settings_screen_part2.dart';
//
// Firebase UID remains canonical.
// Passwords/OTP are never persisted here.
// Call Engine / Message Engine / WebRTC remain untouched.
// ===============================================================

// ===============================================================
// SETTINGS STATE — DIALOG / UI HELPERS
// ===============================================================

extension _SettingsScreenPart2State on _SettingsScreenState {
  // =============================================================
  // TEXT INPUT
  // =============================================================

  Future<String?> _textInput({
    required String title,
    required String label,
    String initialValue = '',
    TextInputType keyboardType = TextInputType.text,
    List<String>? autofillHints,
  }) async {
    if (!mounted) {
      return null;
    }

    final TextEditingController controller =
    TextEditingController(
      text: initialValue,
    );

    try {
      return await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: keyboardType,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: autofillHints,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (String value) {
                Navigator.of(dialogContext).pop(
                  value.trim(),
                );
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    controller.text.trim(),
                  );
                },
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  // =============================================================
  // CURRENT PASSWORD PROMPT
  // =============================================================

  Future<String?> _passwordPrompt() async {
    if (!mounted) {
      return null;
    }

    final TextEditingController controller =
    TextEditingController();

    bool visible = false;

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (
                BuildContext context,
                StateSetter setDialogState,
                ) {
              return AlertDialog(
                title: const Text(
                  'Confirm Password',
                ),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: !visible,
                  keyboardType:
                  TextInputType.visiblePassword,
                  textInputAction:
                  TextInputAction.done,
                  autofillHints: const <String>[
                    AutofillHints.password,
                  ],
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    border:
                    const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setDialogState(() {
                          visible = !visible;
                        });
                      },
                      icon: Icon(
                        visible
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                  onSubmitted: (String value) {
                    if (value.isNotEmpty) {
                      Navigator.of(dialogContext)
                          .pop(value);
                    }
                  },
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext)
                          .pop();
                    },
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext)
                          .pop(controller.text);
                    },
                    child: const Text('Verify'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  // =============================================================
  // PHONE OTP PROMPT
  // =============================================================

  Future<String?> _otpPrompt() async {
    if (!mounted) {
      return null;
    }

    final TextEditingController controller =
    TextEditingController();

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text(
              'Verify Phone',
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[
                AutofillHints.oneTimeCode,
              ],
              inputFormatters:
              <TextInputFormatter>[
                FilteringTextInputFormatter
                    .digitsOnly,
                LengthLimitingTextInputFormatter(
                  6,
                ),
              ],
              decoration:
              const InputDecoration(
                labelText: '6 digit OTP',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (String value) {
                final String otp = value.trim();

                if (RegExp(
                  r'^\d{6}$',
                ).hasMatch(otp)) {
                  Navigator.of(dialogContext)
                      .pop(otp);
                }
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext)
                      .pop();
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final String otp =
                  controller.text.trim();

                  if (!RegExp(
                    r'^\d{6}$',
                  ).hasMatch(otp)) {
                    return;
                  }

                  Navigator.of(dialogContext)
                      .pop(otp);
                },
                child: const Text('Verify'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  // =============================================================
  // PASSWORD CHANGE DIALOG
  // =============================================================

  Future<_PasswordChangeData?>
  _passwordChangeDialog() async {
    if (!mounted) {
      return null;
    }

    final TextEditingController current =
    TextEditingController();

    final TextEditingController password =
    TextEditingController();

    final TextEditingController confirm =
    TextEditingController();

    bool visible = false;

    try {
      return await showDialog<
          _PasswordChangeData>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (
                BuildContext context,
                StateSetter setDialogState,
                ) {
              return AlertDialog(
                title: const Text(
                  'Change Password',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: <Widget>[
                      _passwordField(
                        current,
                        'Current Password',
                        !visible,
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      _passwordField(
                        password,
                        'New Password',
                        !visible,
                        newPassword: true,
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      _passwordField(
                        confirm,
                        'Confirm New Password',
                        !visible,
                        newPassword: true,
                      ),
                      CheckboxListTile(
                        contentPadding:
                        EdgeInsets.zero,
                        value: visible,
                        title: const Text(
                          'Show Passwords',
                        ),
                        onChanged: (bool? value) {
                          setDialogState(() {
                            visible =
                                value ?? false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.of(
                        dialogContext,
                      ).pop();
                    },
                    child:
                    const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(
                        dialogContext,
                      ).pop(
                        _PasswordChangeData(
                          current:
                          current.text,
                          password:
                          password.text,
                          confirm:
                          confirm.text,
                        ),
                      );
                    },
                    child:
                    const Text('Change'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      current.dispose();
      password.dispose();
      confirm.dispose();
    }
  }

  // =============================================================
  // NEW PASSWORD DIALOG
  // =============================================================

  Future<_NewPasswordData?>
  _newPasswordDialog() async {
    if (!mounted) {
      return null;
    }

    final TextEditingController password =
    TextEditingController();

    final TextEditingController confirm =
    TextEditingController();

    bool visible = false;

    try {
      return await showDialog<
          _NewPasswordData>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (
                BuildContext context,
                StateSetter setDialogState,
                ) {
              return AlertDialog(
                title: const Text(
                  'Set Password',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: <Widget>[
                      _passwordField(
                        password,
                        'New Password',
                        !visible,
                        newPassword: true,
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      _passwordField(
                        confirm,
                        'Confirm Password',
                        !visible,
                        newPassword: true,
                      ),
                      CheckboxListTile(
                        contentPadding:
                        EdgeInsets.zero,
                        value: visible,
                        title: const Text(
                          'Show Passwords',
                        ),
                        onChanged: (bool? value) {
                          setDialogState(() {
                            visible =
                                value ?? false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.of(
                        dialogContext,
                      ).pop();
                    },
                    child:
                    const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(
                        dialogContext,
                      ).pop(
                        _NewPasswordData(
                          password:
                          password.text,
                          confirm:
                          confirm.text,
                        ),
                      );
                    },
                    child:
                    const Text(
                      'Set Password',
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      password.dispose();
      confirm.dispose();
    }
  }

  // =============================================================
  // PASSWORD FIELD
  // =============================================================

  Widget _passwordField(
      TextEditingController controller,
      String label,
      bool obscure, {
        bool newPassword = false,
      }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType:
      TextInputType.visiblePassword,
      textInputAction:
      TextInputAction.next,
      autofillHints: <String>[
        newPassword
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        border:
        const OutlineInputBorder(),
      ),
    );
  }

  // =============================================================
  // GENERIC CONFIRMATION
  // =============================================================

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
    bool destructive = false,
  }) async {
    if (!mounted) {
      return false;
    }

    final bool? result =
    await showDialog<bool>(
      context: context,
      builder: (
          BuildContext dialogContext,
          ) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                backgroundColor:
                _SettingsScreenState
                    ._danger,
              )
                  : null,
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },
              child: Text(
                confirmText,
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  // =============================================================
  // BOTTOM-SHEET ACTION
  // =============================================================

  Widget _sheetAction(
      IconData icon,
      String label,
      VoidCallback onPressed,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 10,
      ),
      child: SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style:
          OutlinedButton.styleFrom(
            alignment:
            Alignment.centerLeft,
            foregroundColor:
            _SettingsScreenState
                ._primary,
            side: const BorderSide(
              color: Color(
                0xFFDBEAFE,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // PHONE NORMALIZATION
  // =============================================================

  String _normalizePhone(
      String value,
      ) {
    return value.replaceAll(
      RegExp(
        r'[\s()\-\u2013\u2014.]',
      ),
      '',
    );
  }

  // =============================================================
  // PHONE VALIDATION
  // =============================================================

  bool _validPhone(
      String value,
      ) {
    return RegExp(
      r'^\+[1-9]\d{7,14}$',
    ).hasMatch(value);
  }

  // =============================================================
  // EMAIL VALIDATION
  // =============================================================

  bool _validEmail(
      String value,
      ) {
    final String normalized =
    value.trim().toLowerCase();

    return normalized.isNotEmpty &&
        normalized.length <= 254 &&
        RegExp(
          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
        ).hasMatch(normalized);
  }

  // =============================================================
  // VERIFICATION DISPLAY
  // =============================================================

  String _verificationText(
      User user,
      ) {
    final bool hasEmail =
        user.email
            ?.trim()
            .isNotEmpty ==
            true;

    final bool hasPhone =
        user.phoneNumber
            ?.trim()
            .isNotEmpty ==
            true;

    if (hasEmail &&
        user.emailVerified &&
        hasPhone) {
      return 'Email and Phone verified';
    }

    if (hasEmail &&
        user.emailVerified) {
      return 'Email verified';
    }

    if (hasPhone) {
      return hasEmail
          ? 'Phone verified • Email pending'
          : 'Phone verified';
    }

    if (hasEmail) {
      return 'Email verification pending';
    }

    return 'No verified identity';
  }

  // =============================================================
  // PROVIDER LABEL
  // =============================================================

  String _providerLabel(
      String id,
      ) {
    switch (id.trim()) {
      case 'password':
        return 'Email / Password';

      case 'phone':
        return 'Phone';

      case 'google.com':
        return 'Google';

      case 'apple.com':
        return 'Apple';

      case 'facebook.com':
        return 'Facebook';

      default:
        return id.trim().isEmpty
            ? 'Unknown'
            : id.trim();
    }
  }

  // =============================================================
  // PROVIDER ICON
  // =============================================================

  IconData _providerIcon(
      String id,
      ) {
    switch (id.trim()) {
      case 'password':
        return Icons.password_rounded;

      case 'phone':
        return Icons.phone_android_rounded;

      case 'google.com':
        return Icons.account_circle_outlined;

      case 'apple.com':
        return Icons.apple;

      case 'facebook.com':
        return Icons.facebook;

      default:
        return Icons.security_rounded;
    }
  }

  // =============================================================
  // AUTH ERROR TEXT
  // =============================================================

  String _authMessage(
      FirebaseAuthException error,
      ) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
        return 'Authentication information is incorrect.';

      case 'requires-recent-login':
        return 'Please sign in again before this security change.';

      case 'email-already-in-use':
        return 'This Email belongs to another account.';

      case 'credential-already-in-use':
        return 'This credential belongs to another account.';

      case 'provider-already-linked':
        return 'This sign-in method is already linked.';

      case 'invalid-email':
        return 'The Email address is invalid.';

      case 'invalid-phone-number':
        return 'The Phone Number is invalid.';

      case 'weak-password':
        return 'The Password is too weak.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'network-request-failed':
        return 'Check your Internet connection.';

      case 'session-expired':
        return 'Verification session expired.';

      case 'invalid-verification-code':
        return 'The verification code is incorrect.';

      case 'invalid-verification-id':
        return 'The verification session is invalid. Request a new OTP.';

      case 'quota-exceeded':
        return 'Firebase verification quota has been reached.';

      case 'app-not-authorized':
        return 'This application is not authorized for Firebase Authentication.';

      case 'invalid-app-credential':
        return 'Firebase could not verify this application.';

      case 'captcha-check-failed':
        return 'Firebase security verification failed.';

      case 'operation-not-allowed':
        return 'This authentication method is not enabled.';

      case 'user-disabled':
        return 'This JR CALL account is unavailable.';

      default:
        return error.message ??
            'Authentication operation failed.';
    }
  }
}

// ===============================================================
// ACCOUNT HEADER
// ===============================================================

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.signedIn,
    required this.user,
    required this.onProfile,
    required this.onAccount,
  });

  final bool signedIn;
  final User? user;
  final VoidCallback onProfile;
  final VoidCallback onAccount;

  @override
  Widget build(
      BuildContext context,
      ) {
    final String title;

    if (!signedIn) {
      title = 'JR CALL Guest';
    } else {
      final String displayName =
          user?.displayName?.trim() ?? '';

      title = displayName.isNotEmpty
          ? displayName
          : 'JR CALL Account';
    }

    final String subtitle;

    if (!signedIn) {
      subtitle =
      'Browse freely • Login when an account is required';
    } else {
      final String email =
          user?.email?.trim() ?? '';

      final String phone =
          user?.phoneNumber?.trim() ?? '';

      if (email.isNotEmpty) {
        subtitle = email;
      } else if (phone.isNotEmpty) {
        subtitle = phone;
      } else {
        subtitle =
        'Authenticated account';
      }
    }

    final String photoUrl =
        user?.photoURL?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(22),
        border: Border.all(
          color: const Color(
            0xFFDCE7F5,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 29,
            backgroundColor:
            const Color(
              0xFFEAF2FF,
            ),
            backgroundImage:
            photoUrl.isNotEmpty
                ? NetworkImage(
              photoUrl,
            )
                : null,
            child: photoUrl.isNotEmpty
                ? null
                : Icon(
              signedIn
                  ? Icons.person_rounded
                  : Icons.public_rounded,
              color: const Color(
                0xFF2563EB,
              ),
              size: 30,
            ),
          ),
          const SizedBox(
            width: 13,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(
                      0xFF111827,
                    ),
                    fontSize: 17,
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow:
                  TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(
                      0xFF64748B,
                    ),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: signedIn
                ? 'Profile'
                : 'Account',
            onPressed: signedIn
                ? onProfile
                : onAccount,
            icon: Icon(
              signedIn
                  ? Icons.chevron_right_rounded
                  : Icons.login_rounded,
              color: const Color(
                0xFF2563EB,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// DANGER ZONE
// ===============================================================

class _DangerZone extends StatelessWidget {
  const _DangerZone({
    required this.expanded,
    required this.deleting,
    required this.onToggle,
    required this.onDelete,
  });

  final bool expanded;
  final bool deleting;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(
          0xFFFFFBFB,
        ),
        borderRadius:
        BorderRadius.circular(20),
        border: Border.all(
          color: const Color(
            0xFFFECACA,
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          ListTile(
            onTap:
            deleting ? null : onToggle,
            leading: const Icon(
              Icons.warning_amber_rounded,
              color: Color(
                0xFFDC2626,
              ),
            ),
            title: const Text(
              'Danger Zone',
              style: TextStyle(
                color: Color(
                  0xFF991B1B,
                ),
                fontWeight:
                FontWeight.w800,
              ),
            ),
            subtitle: const Text(
              'Permanent account actions',
            ),
            trailing: Icon(
              expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
          ),
          if (expanded) ...<Widget>[
            const Divider(
              height: 1,
            ),
            const Padding(
              padding:
              EdgeInsets.fromLTRB(
                18,
                16,
                18,
                14,
              ),
              child: Text(
                'Deleting your account permanently removes your '
                    'JR CALL identity and cannot be undone.',
                style: TextStyle(
                  color: Color(
                    0xFF7F1D1D,
                  ),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            Padding(
              padding:
              const EdgeInsets.fromLTRB(
                18,
                0,
                18,
                18,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child:
                FilledButton.icon(
                  onPressed:
                  deleting
                      ? null
                      : onDelete,
                  style:
                  FilledButton.styleFrom(
                    backgroundColor:
                    const Color(
                      0xFFDC2626,
                    ),
                    foregroundColor:
                    Colors.white,
                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(
                        14,
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons
                        .delete_forever_outlined,
                  ),
                  label: Text(
                    deleting
                        ? 'DELETING...'
                        : 'DELETE ACCOUNT',
                    style:
                    const TextStyle(
                      fontWeight:
                      FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ===============================================================
// SETTINGS TILE
// ===============================================================

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailingText;
  final VoidCallback onTap;

  @override
  Widget build(
      BuildContext context,
      ) {
    final String? trailing =
        trailingText;

    return Card(
      color: Colors.white,
      elevation: 0,
      margin:
      const EdgeInsets.only(
        bottom: 10,
      ),
      shape:
      RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(18),
        side: const BorderSide(
          color: Color(
            0xFFE5E7EB,
          ),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        leading: Container(
          width: 42,
          height: 42,
          decoration:
          const BoxDecoration(
            color: Color(
              0xFFEFF6FF,
            ),
            shape:
            BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: const Color(
              0xFF2563EB,
            ),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(
              0xFF111827,
            ),
            fontWeight:
            FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding:
          const EdgeInsets.only(
            top: 3,
          ),
          child: Text(
            subtitle,
            maxLines: 2,
            overflow:
            TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(
                0xFF64748B,
              ),
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize:
          MainAxisSize.min,
          children: <Widget>[
            if (trailing != null) ...<
                Widget>[
              Text(
                trailing,
                style: TextStyle(
                  color:
                  trailing ==
                      'Verified'
                      ? const Color(
                    0xFF16A34A,
                  )
                      : const Color(
                    0xFFF59E0B,
                  ),
                  fontSize: 11.5,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
              const SizedBox(
                width: 6,
              ),
            ],
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(
                0xFF94A3B8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===============================================================
// INFORMATION CARD
// ===============================================================

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color: const Color(
            0xFFE5E7EB,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration:
            const BoxDecoration(
              color: Color(
                0xFFF1F5F9,
              ),
              shape:
              BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: const Color(
                0xFF475569,
              ),
            ),
          ),
          const SizedBox(
            width: 13,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style:
                  const TextStyle(
                    color: Color(
                      0xFF111827,
                    ),
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                Text(
                  description,
                  style:
                  const TextStyle(
                    color: Color(
                      0xFF64748B,
                    ),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// SECTION TITLE
// ===============================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(
      this.title,
      );

  final String title;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        left: 4,
        bottom: 10,
      ),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(
            0xFF475569,
          ),
          fontSize: 14,
          fontWeight:
          FontWeight.w800,
        ),
      ),
    );
  }
}

// ===============================================================
// VERIFICATION BADGE
// ===============================================================

class _VerificationBadge
    extends StatelessWidget {
  const _VerificationBadge({
    required this.verified,
    required this.verifiedText,
    required this.pendingText,
  });

  final bool verified;
  final String verifiedText;
  final String pendingText;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Row(
      children: <Widget>[
        Icon(
          verified
              ? Icons.verified_outlined
              : Icons.schedule_outlined,
          size: 18,
          color: verified
              ? const Color(
            0xFF16A34A,
          )
              : const Color(
            0xFFF59E0B,
          ),
        ),
        const SizedBox(
          width: 6,
        ),
        Text(
          verified
              ? verifiedText
              : pendingText,
          style: TextStyle(
            color: verified
                ? const Color(
              0xFF16A34A,
            )
                : const Color(
              0xFFF59E0B,
            ),
            fontWeight:
            FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ===============================================================
// SHEET HANDLE
// ===============================================================

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(
      BuildContext context,
      ) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(
            0xFFD1D5DB,
          ),
          borderRadius:
          BorderRadius.circular(
            99,
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// PASSWORD MODELS
// ===============================================================

class _PasswordChangeData {
  const _PasswordChangeData({
    required this.current,
    required this.password,
    required this.confirm,
  });

  final String current;
  final String password;
  final String confirm;
}

class _NewPasswordData {
  const _NewPasswordData({
    required this.password,
    required this.confirm,
  });

  final String password;
  final String confirm;
}

// ===============================================================
// END OF FILE
//
// SETTINGS SCREEN PART 2 / 2
//
// LOCATION:
// lib/screens/settings_screen_part2.dart
//
// FIXED:
//
// ✓ _danger is correctly qualified through _SettingsScreenState.
// ✓ _primary is correctly qualified through _SettingsScreenState.
// ✓ Original Settings logic preserved.
// ✓ No helper removed.
// ✓ No authentication flow removed.
// ✓ No Email/Password flow removed.
// ✓ No Phone OTP flow removed.
// ✓ No Danger Zone logic removed.
// ✓ No service ownership changed.
// ✓ No Call Engine ownership changed.
// ✓ No Message Engine ownership changed.
// ✓ No WebRTC ownership changed.
//
// ===============================================================