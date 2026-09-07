// ===============================================================
// JR CALL
// File: settings_screen.dart
// Location: lib/screens/settings_screen.dart
//
// SETTINGS SCREEN — PART 1 / 2
//
// OWNS:
//
// ✓ SettingsScreen lifecycle
// ✓ Guest/Auth gate
// ✓ Profile settings
// ✓ Email settings
// ✓ Phone settings + Firebase Phone OTP
// ✓ Password settings
// ✓ Sign-in providers
// ✓ Add / Switch Account
// ✓ Logout
// ✓ Danger Zone account deletion
// ✓ Reauthentication
// ✓ Firebase profile synchronization
// ✓ Main Settings UI
//
// PART 2:
// lib/screens/settings_screen_part2.dart
//
// IMPORTANT:
//
// Firebase UID remains canonical private identity.
// Password/OTP are never stored.
// Profile editing remains owned by ProfileScreen.
// Phone OTP remains Firebase Authentication owned.
// Call Engine/WebRTC/Message Engine remain untouched.
// ===============================================================

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../services/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import 'create_account_screen.dart';
import 'login_screen.dart';
import 'otp_screen.dart';
import 'profile_screen.dart';

part 'settings_screen_part2.dart';

// ===============================================================
// SETTINGS SCREEN
// ===============================================================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // =============================================================
  // DESIGN
  // =============================================================

  static const Color _background = Color(0xFFF6F8FC);
  static const Color _surface = Colors.white;
  static const Color _primary = Color(0xFF2563EB);
  static const Color _text = Color(0xFF111827);
  static const Color _secondary = Color(0xFF64748B);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _success = Color(0xFF16A34A);
  static const Color _danger = Color(0xFFDC2626);

  // =============================================================
  // SERVICES
  // =============================================================

  final AuthService _auth = AuthService.instance;
  final FirestoreService _firestore = FirestoreService.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  StreamSubscription<User?>? _authSubscription;

  bool _busy = false;
  bool _deleting = false;
  bool _dangerExpanded = false;

  User? get _user => _auth.currentUser;

  bool get _signedIn => _user != null;

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _authSubscription = _auth.userChanges.listen(
          (User? user) {
        if (mounted) {
          setState(() {});
        }
      },
      onError: (Object error) {
        debugPrint(
          'JR CALL Settings auth stream: $error',
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  // =============================================================
  // AUTH GATE
  // =============================================================

  Future<bool> _requireAuth(String action) async {
    if (_signedIn) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final String? choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            22,
          ),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _SheetHandle(),
              const SizedBox(height: 18),
              const Icon(
                Icons.lock_person_outlined,
                color: _primary,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'JR CALL Account Required',
                style: TextStyle(
                  color: _text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Login or create an account to $action.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _secondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      sheetContext,
                      'login',
                    );
                  },
                  child: const Text('LOGIN'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(
                      sheetContext,
                      'create',
                    );
                  },
                  child: const Text(
                    'CREATE ACCOUNT',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) {
      return false;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return choice == 'create'
              ? const CreateAccountScreen()
              : const LoginScreen();
        },
        settings: RouteSettings(
          arguments: <String, dynamic>{
            'guestReturn': true,
            'requestedAction': action,
          },
        ),
      ),
    );

    return mounted && _signedIn;
  }

  // =============================================================
  // PROFILE
  // =============================================================

  Future<void> _openProfile() async {
    if (_busy ||
        !await _requireAuth(
          'manage your profile',
        )) {
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return const ProfileScreen();
        },
      ),
    );

    await _reloadAndSync();
  }

  // =============================================================
  // EMAIL SETTINGS
  // =============================================================

  Future<void> _emailSettings() async {
    if (_busy ||
        !await _requireAuth(
          'manage your Email',
        )) {
      return;
    }

    final User? user = _user;

    if (user == null || !mounted) {
      return;
    }

    final String email =
        user.email?.trim() ?? '';

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: _surface,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            20,
            16,
            20,
            24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
            CrossAxisAlignment.stretch,
            children: <Widget>[
              const _SheetHandle(),
              const SizedBox(height: 18),
              const Text(
                'Email',
                style: TextStyle(
                  color: _text,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                email.isEmpty
                    ? 'No Email added'
                    : email,
                style: const TextStyle(
                  color: _secondary,
                ),
              ),
              if (email.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _VerificationBadge(
                  verified: user.emailVerified,
                  verifiedText: 'Verified',
                  pendingText:
                  'Verification pending',
                ),
              ],
              const SizedBox(height: 20),
              if (email.isNotEmpty &&
                  !user.emailVerified)
                _sheetAction(
                  Icons.mark_email_unread_outlined,
                  'Send Verification Email',
                      () {
                    Navigator.pop(sheetContext);
                    unawaited(
                      _sendEmailVerification(),
                    );
                  },
                ),
              if (email.isNotEmpty)
                _sheetAction(
                  Icons.refresh_rounded,
                  'Refresh Verification Status',
                      () {
                    Navigator.pop(sheetContext);
                    unawaited(
                      _refreshVerification(),
                    );
                  },
                ),
              _sheetAction(
                email.isEmpty
                    ? Icons.add_circle_outline
                    : Icons.edit_outlined,
                email.isEmpty
                    ? 'Add Email'
                    : 'Change Email',
                    () {
                  Navigator.pop(sheetContext);
                  unawaited(
                    _changeEmail(email),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendEmailVerification() async {
    if (_busy) {
      return;
    }

    final User? user = _user;

    if (user == null ||
        user.email?.trim().isEmpty != false) {
      _message(
        'No Email is linked to this account.',
      );
      return;
    }

    if (user.emailVerified) {
      _message(
        'Your Email is already verified.',
      );
      return;
    }

    await _runBusy(() async {
      await _auth.sendEmailVerification();

      _message(
        'Verification Email sent.',
      );
    });
  }

  Future<void> _refreshVerification() async {
    if (!_signedIn) {
      if (!await _requireAuth(
        'check your verification status',
      )) {
        return;
      }
    }

    await _runBusy(() async {
      await _reloadAndSync();

      final User? user = _user;

      if (user == null) {
        throw StateError(
          'Authentication session is unavailable.',
        );
      }

      _message(
        _verificationText(user),
      );
    });
  }

  Future<void> _changeEmail(
      String currentEmail,
      ) async {
    if (!mounted) {
      return;
    }

    final String? value = await _textInput(
      title: currentEmail.isEmpty
          ? 'Add Email'
          : 'Change Email',
      label: 'New Email',
      initialValue: currentEmail,
      keyboardType:
      TextInputType.emailAddress,
      autofillHints: const <String>[
        AutofillHints.email,
      ],
    );

    if (value == null) {
      return;
    }

    final String email =
    value.trim().toLowerCase();

    if (!_validEmail(email)) {
      _message(
        'Enter a valid Email address.',
      );
      return;
    }

    if (email ==
        currentEmail.trim().toLowerCase()) {
      _message(
        'This Email is already linked.',
      );
      return;
    }

    await _runBusy(() async {
      await _reauthenticateIfSupported();

      await _auth.requestEmailChange(
        newEmail: email,
      );

      _message(
        'Verification was sent to the new Email. '
            'Verify it to complete the change.',
      );
    });
  }

  // =============================================================
  // PHONE SETTINGS
  // =============================================================

  Future<void> _phoneSettings() async {
    if (_busy ||
        !await _requireAuth(
          'manage your Phone Number',
        )) {
      return;
    }

    if (!mounted) {
      return;
    }

    String completePhone = '';

    final TextEditingController controller =
    TextEditingController();

    try {
      final String? phone =
      await showDialog<String>(
        context: context,
        builder:
            (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(
              _user?.phoneNumber
                  ?.trim()
                  .isNotEmpty ==
                  true
                  ? 'Change Phone Number'
                  : 'Add Phone Number',
            ),
            content: IntlPhoneField(
              controller: controller,
              initialCountryCode: 'BD',
              disableLengthCheck: true,
              keyboardType:
              TextInputType.phone,
              inputFormatters:
              <TextInputFormatter>[
                FilteringTextInputFormatter
                    .digitsOnly,
              ],
              decoration:
              const InputDecoration(
                labelText: 'Phone Number',
                border:
                OutlineInputBorder(),
              ),
              onChanged: (phone) {
                completePhone =
                controller.text
                    .trim()
                    .isEmpty
                    ? ''
                    : _normalizePhone(
                  phone.completeNumber,
                );
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child:
                const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    completePhone,
                  );
                },
                child:
                const Text('Send OTP'),
              ),
            ],
          );
        },
      );

      if (phone == null) {
        return;
      }

      final String normalized =
      _normalizePhone(phone);

      if (!_validPhone(normalized)) {
        _message(
          'Enter a valid international Phone Number.',
        );
        return;
      }

      if (normalized ==
          _normalizePhone(
            _user?.phoneNumber ?? '',
          )) {
        _message(
          'This Phone Number is already linked.',
        );
        return;
      }

      await _beginPhoneChange(normalized);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _beginPhoneChange(
      String phone,
      ) async {
    if (_busy) {
      return;
    }

    _setBusy(true);

    bool finished = false;

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted:
            (PhoneAuthCredential credential) {
          if (finished) {
            return;
          }

          finished = true;

          unawaited(
            _automaticPhoneChange(
              credential,
            ),
          );
        },
        verificationFailed:
            (FirebaseAuthException error) {
          if (finished || !mounted) {
            return;
          }

          finished = true;
          _setBusy(false);
          _message(
            _authMessage(error),
          );
        },
        codeSent:
            (String verificationId) {
          if (finished || !mounted) {
            return;
          }

          finished = true;
          _setBusy(false);

          unawaited(
            _phoneChangeOtp(
              verificationId:
              verificationId,
              phone: phone,
            ),
          );
        },
        codeAutoRetrievalTimeout:
            (String verificationId) {
          if (!finished) {
            _setBusy(false);
          }
        },
      );
    } catch (error) {
      _setBusy(false);
      _handleError(error);
    }
  }

  Future<void> _automaticPhoneChange(
      PhoneAuthCredential credential,
      ) async {
    await _runBusy(() async {
      await _auth.updatePhoneNumber(
        credential,
      );

      await _reloadAndSync();

      _message(
        'Phone Number updated successfully.',
      );
    });
  }

  Future<void> _phoneChangeOtp({
    required String verificationId,
    required String phone,
  }) async {
    if (!mounted) {
      return;
    }

    final bool? changed =
    await Navigator.of(context)
        .push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(
          arguments: <String, dynamic>{
            'mode': 'phoneChange',
          },
        ),
        builder: (BuildContext context) {
          return OtpScreen(
            verificationId:
            verificationId,
            phoneNumber: phone,
            provider: 'phone_change',
          );
        },
      ),
    );

    if (changed == true) {
      await _reloadAndSync();
    }
  }

  // =============================================================
  // PASSWORD
  // =============================================================

  Future<void> _passwordSettings() async {
    if (_busy ||
        !await _requireAuth(
          'manage your Password',
        )) {
      return;
    }

    final User? user = _user;

    if (user == null) {
      return;
    }

    final String email =
        user.email?.trim() ?? '';

    if (email.isEmpty) {
      _message(
        'Add and verify an Email first.',
      );
      return;
    }

    if (_auth.hasProvider('password')) {
      await _changePassword(email);
      return;
    }

    if (!user.emailVerified) {
      _message(
        'Verify your Email before setting a Password.',
      );
      return;
    }

    await _setPassword(email);
  }

  Future<void> _changePassword(
      String email,
      ) async {
    final _PasswordChangeData? data =
    await _passwordChangeDialog();

    if (data == null) {
      return;
    }

    if (data.current.isEmpty) {
      _message(
        'Enter your current Password.',
      );
      return;
    }

    if (data.password.length < 6) {
      _message(
        'New Password must contain at least 6 characters.',
      );
      return;
    }

    if (data.password != data.confirm) {
      _message(
        'New Password and Confirm Password do not match.',
      );
      return;
    }

    await _runBusy(() async {
      await _auth.reauthenticateWithPassword(
        email: email,
        password: data.current,
      );

      await _auth.updatePassword(
        newPassword: data.password,
      );

      TextInput.finishAutofillContext(
        shouldSave: true,
      );

      _message(
        'Password changed successfully.',
      );
    });
  }

  Future<void> _setPassword(
      String email,
      ) async {
    final _NewPasswordData? data =
    await _newPasswordDialog();

    if (data == null) {
      return;
    }

    if (data.password.length < 6) {
      _message(
        'Password must contain at least 6 characters.',
      );
      return;
    }

    if (data.password != data.confirm) {
      _message(
        'Passwords do not match.',
      );
      return;
    }

    await _runBusy(() async {
      await _auth.linkEmailPasswordToCurrentUser(
        email: email,
        password: data.password,
      );

      await _reloadAndSync();

      TextInput.finishAutofillContext(
        shouldSave: true,
      );

      _message(
        'Email/Password sign-in added successfully.',
      );
    });
  }

  // =============================================================
  // PROVIDERS
  // =============================================================

  Future<void> _providers() async {
    if (_busy ||
        !await _requireAuth(
          'view Sign-in Providers',
        )) {
      return;
    }

    await _runBusy(
          () => _auth.reloadUser(),
    );

    if (!mounted) {
      return;
    }

    final List<String> providers =
    List<String>.from(
      _auth.linkedProviderIds,
    );

    await showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) {
        return AlertDialog(
          title:
          const Text(
            'Sign-in Providers',
          ),
          content: providers.isEmpty
              ? const Text(
            'No provider information available.',
          )
              : Column(
            mainAxisSize:
            MainAxisSize.min,
            children: providers
                .map(
                  (String provider) {
                return ListTile(
                  contentPadding:
                  EdgeInsets.zero,
                  leading: Icon(
                    _providerIcon(
                      provider,
                    ),
                  ),
                  title: Text(
                    _providerLabel(
                      provider,
                    ),
                  ),
                  trailing:
                  const Icon(
                    Icons
                        .verified_rounded,
                    color:
                    _success,
                  ),
                );
              },
            )
                .toList(),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
              const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  // =============================================================
  // ADD / SWITCH ACCOUNT
  // =============================================================

  Future<void> _accountSwitcher() async {
    if (_busy || !mounted) {
      return;
    }

    if (!_signedIn) {
      await Navigator.of(context)
          .push<void>(
        MaterialPageRoute<void>(
          builder:
              (BuildContext context) {
            return const LoginScreen();
          },
        ),
      );

      return;
    }

    final bool confirmed =
    await _confirm(
      title: 'Switch Account?',
      message:
      'JR CALL currently keeps one active Firebase account at a time. '
          'Your current account will be logged out, then you can Login '
          'or Create another account.',
      confirmText: 'Continue',
    );

    if (!confirmed) {
      return;
    }

    _setBusy(true);

    try {
      await _auth.signOut();

      if (!mounted) {
        return;
      }

      await Navigator.of(context)
          .push<void>(
        MaterialPageRoute<void>(
          builder:
              (BuildContext context) {
            return const LoginScreen();
          },
        ),
      );
    } catch (error) {
      _handleError(error);
    } finally {
      _setBusy(false);
    }
  }

  // =============================================================
  // LOGOUT
  // =============================================================

  Future<void> _logout() async {
    if (_busy || !_signedIn) {
      return;
    }

    final bool confirmed =
    await _confirm(
      title: 'Log Out?',
      message:
      'You can continue browsing JR CALL in Guest Mode.',
      confirmText: 'Log Out',
    );

    if (!confirmed) {
      return;
    }

    await _runBusy(() async {
      TextInput.finishAutofillContext(
        shouldSave: false,
      );

      await _auth.signOut();

      if (mounted) {
        Navigator.of(context).popUntil(
              (Route<dynamic> route) =>
          route.isFirst,
        );
      }
    });
  }

  // =============================================================
  // DANGER ZONE / DELETE ACCOUNT
  // =============================================================

  Future<void> _deleteAccount() async {
    if (_busy ||
        _deleting ||
        !_signedIn) {
      return;
    }

    final bool first =
    await _confirm(
      title: 'Delete JR CALL Account?',
      message:
      'This permanently removes your authentication account, '
          'JR CALL profile, identity reservations and known profile media.',
      confirmText: 'Continue',
      destructive: true,
    );

    if (!first) {
      return;
    }

    final bool typed =
    await _confirmDeleteText();

    if (!typed) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _busy = true;
      _deleting = true;
    });

    try {
      await _reauthenticate();

      final User? user = _user;

      if (user == null) {
        throw StateError(
          'Authentication session is unavailable.',
        );
      }

      final String uid = user.uid;

      await _deleteStorage(
        'users/$uid/profile/profile.jpg',
      );

      await _deleteStorage(
        'users/$uid/cover/cover.jpg',
      );

      await _firestore.deleteUserProfile(
        uid,
      );

      await _auth.deleteCurrentUser();

      TextInput.finishAutofillContext(
        shouldSave: false,
      );

      if (mounted) {
        Navigator.of(context).popUntil(
              (Route<dynamic> route) =>
          route.isFirst,
        );
      }
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _deleting = false;
        });
      }
    }
  }

  Future<bool> _confirmDeleteText() async {
    if (!mounted) {
      return false;
    }

    final TextEditingController controller =
    TextEditingController();

    bool valid = false;

    try {
      final bool? result =
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (
                BuildContext context,
                StateSetter setDialogState,
                ) {
              return AlertDialog(
                title: const Text(
                  'Final Confirmation',
                ),
                content: Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Type DELETE to permanently delete your account.',
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints:
                      const <String>[],
                      decoration:
                      const InputDecoration(
                        labelText:
                        'Type DELETE',
                        border:
                        OutlineInputBorder(),
                      ),
                      onChanged:
                          (String value) {
                        final bool next =
                            value
                                .trim()
                                .toUpperCase() ==
                                'DELETE';

                        if (next != valid) {
                          setDialogState(() {
                            valid = next;
                          });
                        }
                      },
                    ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                        false,
                      );
                    },
                    child: const Text(
                      'Cancel',
                    ),
                  ),
                  FilledButton(
                    style:
                    FilledButton
                        .styleFrom(
                      backgroundColor:
                      _danger,
                    ),
                    onPressed: valid
                        ? () {
                      Navigator.pop(
                        dialogContext,
                        true,
                      );
                    }
                        : null,
                    child: const Text(
                      'Delete Permanently',
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      return result ?? false;
    } finally {
      controller.dispose();
    }
  }

  // =============================================================
  // REAUTHENTICATION
  // =============================================================

  Future<void>
  _reauthenticateIfSupported() async {
    if (_auth.hasProvider('password') ||
        _auth.hasProvider('phone')) {
      await _reauthenticate();
    }
  }

  Future<void> _reauthenticate() async {
    final User? user = _user;

    if (user == null) {
      throw StateError(
        'No authenticated Firebase user.',
      );
    }

    if (_auth.hasProvider('password')) {
      final String email =
          user.email?.trim() ?? '';

      if (email.isEmpty) {
        throw StateError(
          'Email information is unavailable.',
        );
      }

      final String? password =
      await _passwordPrompt();

      if (password == null) {
        throw StateError(
          'Account verification was cancelled.',
        );
      }

      await _auth.reauthenticateWithPassword(
        email: email,
        password: password,
      );

      return;
    }

    if (_auth.hasProvider('phone')) {
      final String phone =
          user.phoneNumber?.trim() ?? '';

      if (phone.isEmpty) {
        throw StateError(
          'Phone information is unavailable.',
        );
      }

      await _phoneReauthentication(
        phone,
      );
    }
  }

  Future<void> _phoneReauthentication(
      String phone,
      ) async {
    final Completer<void> completer =
    Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted:
          (PhoneAuthCredential credential) {
        if (completer.isCompleted) {
          return;
        }

        unawaited(
          _finishAutoReauth(
            credential,
            completer,
          ),
        );
      },
      verificationFailed:
          (FirebaseAuthException error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      codeSent:
          (String verificationId) {
        if (completer.isCompleted) {
          return;
        }

        unawaited(
          _finishManualReauth(
            verificationId,
            completer,
          ),
        );
      },
      codeAutoRetrievalTimeout:
          (String verificationId) {},
    );

    await completer.future;
  }

  Future<void> _finishAutoReauth(
      PhoneAuthCredential credential,
      Completer<void> completer,
      ) async {
    try {
      await _auth
          .reauthenticateWithPhoneCredential(
        credential,
      );

      if (!completer.isCompleted) {
        completer.complete();
      }
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(
          error,
          stackTrace,
        );
      }
    }
  }

  Future<void> _finishManualReauth(
      String verificationId,
      Completer<void> completer,
      ) async {
    try {
      final String? otp =
      await _otpPrompt();

      if (otp == null) {
        throw StateError(
          'Phone verification was cancelled.',
        );
      }

      final PhoneAuthCredential credential =
      _auth.createPhoneCredential(
        verificationId: verificationId,
        smsCode: otp,
      );

      await _auth
          .reauthenticateWithPhoneCredential(
        credential,
      );

      if (!completer.isCompleted) {
        completer.complete();
      }
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(
          error,
          stackTrace,
        );
      }
    }
  }

  // =============================================================
  // FIREBASE SYNC
  // =============================================================

  Future<void> _reloadAndSync() async {
    await _auth.reloadUser();

    final User? user = _user;

    if (user == null) {
      return;
    }

    try {
      await _firestore
          .syncAuthenticationProfile(
        uid: user.uid,
        email: user.email ?? '',
        phoneNumber:
        user.phoneNumber ?? '',
        emailVerified:
        user.emailVerified,
        phoneVerified:
        user.phoneNumber
            ?.trim()
            .isNotEmpty ==
            true,
        signInProviders:
        _auth.linkedProviderIds,
      );
    } catch (error) {
      debugPrint(
        'JR CALL Settings profile sync skipped: $error',
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _deleteStorage(
      String path,
      ) async {
    try {
      await _storage
          .ref()
          .child(path)
          .delete();
    } on FirebaseException catch (error) {
      if (error.code !=
          'object-not-found') {
        rethrow;
      }
    }
  }

  // =============================================================
  // GENERIC ASYNC WRAPPER
  // =============================================================

  Future<void> _runBusy(
      Future<void> Function() action,
      ) async {
    if (_busy) {
      return;
    }

    _setBusy(true);

    try {
      await action();
    } catch (error) {
      _handleError(error);
    } finally {
      _setBusy(false);
    }
  }

  void _handleError(Object error) {
    debugPrint(
      'JR CALL Settings error: $error',
    );

    if (error is FirebaseAuthException) {
      _message(
        _authMessage(error),
      );
      return;
    }

    if (error is FirebaseException) {
      _message(
        error.message ??
            'Firebase operation failed.',
      );
      return;
    }

    if (error is StateError) {
      _message(error.message);
      return;
    }

    if (error is ArgumentError) {
      _message(
        error.message?.toString() ??
            'Invalid information.',
      );
      return;
    }

    _message(
      'This operation could not be completed.',
    );
  }

  // =============================================================
  // STATE / MESSAGE
  // =============================================================

  void _setBusy(bool value) {
    if (!mounted || _busy == value) {
      return;
    }

    setState(() {
      _busy = value;
    });
  }

  void _message(String message) {
    if (!mounted ||
        message.trim().isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior:
          SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final User? user = _user;

    final String email =
        user?.email?.trim() ?? '';

    final String phone =
        user?.phoneNumber?.trim() ?? '';

    final List<String> providers =
    List<String>.from(
      _auth.linkedProviderIds,
    );

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _text,
        surfaceTintColor:
        Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Stack(
        children: <Widget>[
          ListView(
            padding:
            const EdgeInsets.fromLTRB(
              16,
              8,
              16,
              40,
            ),
            children: <Widget>[
              // =================================================
              // ACCOUNT STATUS
              // =================================================

              _AccountHeader(
                signedIn: _signedIn,
                user: user,
                onProfile: () {
                  unawaited(
                    _openProfile(),
                  );
                },
                onAccount: () {
                  unawaited(
                    _accountSwitcher(),
                  );
                },
              ),

              const SizedBox(height: 24),

              // =================================================
              // PROFILE
              // =================================================

              const _SectionTitle(
                'Profile & Personal Information',
              ),

              _SettingsTile(
                icon:
                Icons.person_outline_rounded,
                title: 'My Profile',
                subtitle:
                'Name, Username, JR CALL ID, Bio, Country, DOB and Photos',
                onTap: () {
                  unawaited(
                    _openProfile(),
                  );
                },
              ),

              const SizedBox(height: 24),

              // =================================================
              // ACCOUNT SECURITY
              // =================================================

              const _SectionTitle(
                'Account & Security',
              ),

              _SettingsTile(
                icon: Icons.email_outlined,
                title: 'Email',
                subtitle: email.isEmpty
                    ? 'Add Email'
                    : email,
                trailingText:
                email.isEmpty
                    ? null
                    : user
                    ?.emailVerified ==
                    true
                    ? 'Verified'
                    : 'Pending',
                onTap: () {
                  unawaited(
                    _emailSettings(),
                  );
                },
              ),

              _SettingsTile(
                icon: Icons.phone_outlined,
                title: 'Phone Number',
                subtitle: phone.isEmpty
                    ? 'Add Phone Number'
                    : phone,
                trailingText:
                phone.isEmpty
                    ? null
                    : 'Verified',
                onTap: () {
                  unawaited(
                    _phoneSettings(),
                  );
                },
              ),

              _SettingsTile(
                icon: Icons
                    .verified_user_outlined,
                title: 'Verification',
                subtitle: user == null
                    ? 'Login required'
                    : _verificationText(
                  user,
                ),
                onTap: () {
                  unawaited(
                    _refreshVerification(),
                  );
                },
              ),

              _SettingsTile(
                icon:
                Icons.password_outlined,
                title: 'Password',
                subtitle: !_signedIn
                    ? 'Login required'
                    : _auth.hasProvider(
                  'password',
                )
                    ? 'Change Password'
                    : 'Set Email/Password sign-in',
                onTap: () {
                  unawaited(
                    _passwordSettings(),
                  );
                },
              ),

              _SettingsTile(
                icon: Icons.key_outlined,
                title:
                'Sign-in Providers',
                subtitle:
                providers.isEmpty
                    ? 'Provider information unavailable'
                    : providers
                    .map(
                  _providerLabel,
                )
                    .join(', '),
                onTap: () {
                  unawaited(
                    _providers(),
                  );
                },
              ),

              const SizedBox(height: 24),

              // =================================================
              // ACCOUNT ACCESS
              // =================================================

              const _SectionTitle(
                'Account Access',
              ),

              _SettingsTile(
                icon: Icons
                    .switch_account_outlined,
                title: _signedIn
                    ? 'Add / Switch Account'
                    : 'Login / Add Account',
                subtitle: _signedIn
                    ? 'Sign out this session and Login with another JR CALL account'
                    : 'Login to an existing account or create a new account',
                onTap: () {
                  unawaited(
                    _accountSwitcher(),
                  );
                },
              ),

              if (_signedIn)
                _SettingsTile(
                  icon:
                  Icons.logout_rounded,
                  title: 'Log Out',
                  subtitle:
                  'Return to JR CALL Guest Mode',
                  onTap: () {
                    unawaited(
                      _logout(),
                    );
                  },
                ),

              const SizedBox(height: 24),

              // =================================================
              // DISCOVERY / PRIVACY
              // =================================================

              const _SectionTitle(
                'Discovery & Privacy',
              ),

              const _InformationCard(
                icon:
                Icons.manage_search_outlined,
                title:
                'JR CALL Discovery',
                description:
                'JR CALL ID, Username, Name, permitted Email and '
                    'permitted Phone are discovery inputs. '
                    'Firebase UID remains private.',
              ),

              const SizedBox(height: 14),

              const _InformationCard(
                icon:
                Icons.security_rounded,
                title:
                'Account Security',
                description:
                'Passwords and OTP codes are never stored in '
                    'your public JR CALL profile.',
              ),

              const SizedBox(height: 24),

              // =================================================
              // CALL ENGINE
              // =================================================

              const _SectionTitle(
                'Call Engine',
              ),

              const _InformationCard(
                icon: Icons.call_outlined,
                title:
                'Call Preferences',
                description:
                'Audio, Video, Network, Recovery and WebRTC remain '
                    'owned by the protected JR CALL Call Engine.',
              ),

              if (_signedIn) ...<Widget>[
                const SizedBox(height: 34),

                // ===============================================
                // DANGER ZONE
                // ===============================================

                _DangerZone(
                  expanded:
                  _dangerExpanded,
                  deleting: _deleting,
                  onToggle: () {
                    setState(() {
                      _dangerExpanded =
                      !_dangerExpanded;
                    });
                  },
                  onDelete: () {
                    unawaited(
                      _deleteAccount(),
                    );
                  },
                ),
              ],
            ],
          ),

          // =====================================================
          // BUSY OVERLAY
          // =====================================================

          if (_busy)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color:
                  const Color(
                    0x14000000,
                  ),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment:
                      Alignment.center,
                      decoration:
                      BoxDecoration(
                        color: _surface,
                        borderRadius:
                        BorderRadius
                            .circular(
                          18,
                        ),
                      ),
                      child:
                      const CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ===============================================================
// END OF SETTINGS SCREEN — PART 1 / 2
//
// PART 2:
// lib/screens/settings_screen_part2.dart
//
// DO NOT:
// - Move Part 2 to services/managers.
// - Duplicate SettingsScreen.
// - Modify Call Engine/WebRTC.
// - Change Firebase UID ownership.
//
// ===============================================================