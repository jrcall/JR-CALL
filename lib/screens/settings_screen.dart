// ===============================================================
// JR CALL
// File: settings_screen.dart
// Location: lib/screens/settings_screen.dart
//
// FINAL SETTINGS — GUEST + ACCOUNT SECURITY
//
// GUEST:
// - Settings screen visible.
// - Account actions request Login/Create Account.
//
// AUTHENTICATED:
// - Profile / personal information.
// - Email.
// - Phone.
// - Verification.
// - Password.
// - Sign-in providers.
// - Add / Switch Account.
// - Logout.
//
// DANGER ZONE:
// - Delete Account is intentionally hidden inside Danger Zone.
// - Requires expansion + confirmation + typing DELETE.
// - Storage + Firestore cleanup happens before Firebase Auth delete.
//
// IMPORTANT:
// - Firebase UID remains canonical private identity.
// - Password/OTP are never stored.
// - Profile editing remains owned by ProfileScreen.
// - Call Engine logic is not duplicated here.
// - FirebaseAuth supports one active session at a time.
//   "Switch Account" securely signs out current session first.
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
        if (mounted) setState(() {});
      },
      onError: (Object error) {
        debugPrint('JR CALL Settings auth stream: $error');
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
    if (_signedIn) return true;
    if (!mounted) return false;

    final String? choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
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
              const Icon(Icons.lock_person_outlined, color: _primary, size: 44),
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
                style: const TextStyle(color: _secondary, height: 1.45),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, 'login'),
                  child: const Text('LOGIN'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, 'create'),
                  child: const Text('CREATE ACCOUNT'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return false;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => choice == 'create'
            ? const CreateAccountScreen()
            : const LoginScreen(),
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
    if (_busy || !await _requireAuth('manage your profile')) return;
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ProfileScreen(),
      ),
    );

    await _reloadAndSync();
  }

  // =============================================================
  // EMAIL
  // =============================================================

  Future<void> _emailSettings() async {
    if (_busy || !await _requireAuth('manage your Email')) return;

    final User? user = _user;
    if (user == null || !mounted) return;

    final String email = user.email?.trim() ?? '';

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: _surface,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                email.isEmpty ? 'No Email added' : email,
                style: const TextStyle(color: _secondary),
              ),
              if (email.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _VerificationBadge(
                  verified: user.emailVerified,
                  verifiedText: 'Verified',
                  pendingText: 'Verification pending',
                ),
              ],
              const SizedBox(height: 20),
              if (email.isNotEmpty && !user.emailVerified)
                _sheetAction(
                  Icons.mark_email_unread_outlined,
                  'Send Verification Email',
                  () {
                    Navigator.pop(sheetContext);
                    unawaited(_sendEmailVerification());
                  },
                ),
              if (email.isNotEmpty)
                _sheetAction(
                  Icons.refresh_rounded,
                  'Refresh Verification Status',
                  () {
                    Navigator.pop(sheetContext);
                    unawaited(_refreshVerification());
                  },
                ),
              _sheetAction(
                email.isEmpty ? Icons.add_circle_outline : Icons.edit_outlined,
                email.isEmpty ? 'Add Email' : 'Change Email',
                () {
                  Navigator.pop(sheetContext);
                  unawaited(_changeEmail(email));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendEmailVerification() async {
    if (_busy) return;

    final User? user = _user;

    if (user == null || user.email?.trim().isEmpty != false) {
      _message('No Email is linked to this account.');
      return;
    }

    if (user.emailVerified) {
      _message('Your Email is already verified.');
      return;
    }

    await _runBusy(() async {
      await _auth.sendEmailVerification();
      _message('Verification Email sent.');
    });
  }

  Future<void> _refreshVerification() async {
    await _runBusy(() async {
      await _reloadAndSync();

      final User? user = _user;
      if (user == null) {
        throw StateError('Authentication session is unavailable.');
      }

      _message(_verificationText(user));
    });
  }

  Future<void> _changeEmail(String currentEmail) async {
    if (!mounted) return;

    final String? value = await _textInput(
      title: currentEmail.isEmpty ? 'Add Email' : 'Change Email',
      label: 'New Email',
      initialValue: currentEmail,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const <String>[AutofillHints.email],
    );

    if (value == null) return;

    final String email = value.trim().toLowerCase();

    if (!_validEmail(email)) {
      _message('Enter a valid Email address.');
      return;
    }

    if (email == currentEmail.toLowerCase()) {
      _message('This Email is already linked.');
      return;
    }

    await _runBusy(() async {
      await _reauthenticateIfSupported();
      await _auth.requestEmailChange(newEmail: email);

      _message(
        'Verification was sent to the new Email. '
        'Verify it to complete the change.',
      );
    });
  }

  // =============================================================
  // PHONE
  // =============================================================

  Future<void> _phoneSettings() async {
    if (_busy || !await _requireAuth('manage your Phone Number')) return;
    if (!mounted) return;

    String completePhone = '';
    final TextEditingController controller = TextEditingController();

    final String? phone = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            _user?.phoneNumber?.trim().isNotEmpty == true
                ? 'Change Phone Number'
                : 'Add Phone Number',
          ),
          content: IntlPhoneField(
            controller: controller,
            initialCountryCode: 'BD',
            disableLengthCheck: true,
            keyboardType: TextInputType.phone,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              border: OutlineInputBorder(),
            ),
            onChanged: (phone) {
              completePhone = controller.text.trim().isEmpty
                  ? ''
                  : _normalizePhone(phone.completeNumber);
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, completePhone),
              child: const Text('Send OTP'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (phone == null) return;

    final String normalized = _normalizePhone(phone);

    if (!_validPhone(normalized)) {
      _message('Enter a valid international Phone Number.');
      return;
    }

    if (normalized == _normalizePhone(_user?.phoneNumber ?? '')) {
      _message('This Phone Number is already linked.');
      return;
    }

    await _beginPhoneChange(normalized);
  }

  Future<void> _beginPhoneChange(String phone) async {
    if (_busy) return;

    _setBusy(true);

    bool finished = false;

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) {
          if (finished) return;
          finished = true;
          unawaited(_automaticPhoneChange(credential));
        },
        verificationFailed: (FirebaseAuthException error) {
          if (finished || !mounted) return;
          finished = true;
          _setBusy(false);
          _message(_authMessage(error));
        },
        codeSent: (String verificationId) {
          if (finished || !mounted) return;
          finished = true;
          _setBusy(false);

          unawaited(
            _phoneChangeOtp(verificationId: verificationId, phone: phone),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!finished) _setBusy(false);
        },
      );
    } catch (error) {
      _setBusy(false);
      _handleError(error);
    }
  }

  Future<void> _automaticPhoneChange(PhoneAuthCredential credential) async {
    await _runBusy(() async {
      await _auth.updatePhoneNumber(credential);
      await _reloadAndSync();
      _message('Phone Number updated successfully.');
    });
  }

  Future<void> _phoneChangeOtp({
    required String verificationId,
    required String phone,
  }) async {
    if (!mounted) return;

    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(
          arguments: <String, dynamic>{'mode': 'phoneChange'},
        ),
        builder: (BuildContext context) => OtpScreen(
          verificationId: verificationId,
          phoneNumber: phone,
          provider: 'phone_change',
        ),
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
    if (_busy || !await _requireAuth('manage your Password')) return;

    final User? user = _user;
    if (user == null) return;

    final String email = user.email?.trim() ?? '';

    if (email.isEmpty) {
      _message('Add and verify an Email first.');
      return;
    }

    if (_auth.hasProvider('password')) {
      await _changePassword(email);
      return;
    }

    if (!user.emailVerified) {
      _message('Verify your Email before setting a Password.');
      return;
    }

    await _setPassword(email);
  }

  Future<void> _changePassword(String email) async {
    final _PasswordChangeData? data = await _passwordChangeDialog();

    if (data == null) return;

    if (data.current.isEmpty) {
      _message('Enter your current Password.');
      return;
    }

    if (data.password.length < 6) {
      _message('New Password must contain at least 6 characters.');
      return;
    }

    if (data.password != data.confirm) {
      _message('New Password and Confirm Password do not match.');
      return;
    }

    await _runBusy(() async {
      await _auth.reauthenticateWithPassword(
        email: email,
        password: data.current,
      );

      await _auth.updatePassword(newPassword: data.password);

      TextInput.finishAutofillContext(shouldSave: true);
      _message('Password changed successfully.');
    });
  }

  Future<void> _setPassword(String email) async {
    final _NewPasswordData? data = await _newPasswordDialog();

    if (data == null) return;

    if (data.password.length < 6) {
      _message('Password must contain at least 6 characters.');
      return;
    }

    if (data.password != data.confirm) {
      _message('Passwords do not match.');
      return;
    }

    await _runBusy(() async {
      await _auth.linkEmailPasswordToCurrentUser(
        email: email,
        password: data.password,
      );

      await _reloadAndSync();

      TextInput.finishAutofillContext(shouldSave: true);

      _message('Email/Password sign-in added successfully.');
    });
  }

  // =============================================================
  // PROVIDERS
  // =============================================================

  Future<void> _providers() async {
    if (_busy || !await _requireAuth('view Sign-in Providers')) return;

    await _runBusy(() => _auth.reloadUser());

    if (!mounted) return;

    final List<String> providers = List<String>.from(_auth.linkedProviderIds);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Sign-in Providers'),
          content: providers.isEmpty
              ? const Text('No provider information available.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: providers
                      .map(
                        (String provider) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(_providerIcon(provider)),
                          title: Text(_providerLabel(provider)),
                          trailing: const Icon(
                            Icons.verified_rounded,
                            color: _success,
                          ),
                        ),
                      )
                      .toList(),
                ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
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
    if (_busy || !mounted) return;

    if (!_signedIn) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const LoginScreen(),
        ),
      );
      return;
    }

    final bool confirmed = await _confirm(
      title: 'Switch Account?',
      message:
          'JR CALL currently keeps one active Firebase account at a time. '
          'Your current account will be logged out, then you can Login '
          'or Create another account.',
      confirmText: 'Continue',
    );

    if (!confirmed) return;

    _setBusy(true);

    try {
      await _auth.signOut();

      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const LoginScreen(),
        ),
      );
    } finally {
      _setBusy(false);
    }
  }

  // =============================================================
  // LOGOUT
  // =============================================================

  Future<void> _logout() async {
    if (_busy || !_signedIn) return;

    final bool confirmed = await _confirm(
      title: 'Log Out?',
      message: 'You can continue browsing JR CALL in Guest Mode.',
      confirmText: 'Log Out',
    );

    if (!confirmed) return;

    await _runBusy(() async {
      TextInput.finishAutofillContext(shouldSave: false);
      await _auth.signOut();

      if (mounted) {
        Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
      }
    });
  }

  // =============================================================
  // DANGER ZONE / DELETE ACCOUNT
  // =============================================================

  Future<void> _deleteAccount() async {
    if (_busy || _deleting || !_signedIn) return;

    final bool first = await _confirm(
      title: 'Delete JR CALL Account?',
      message:
          'This permanently removes your authentication account, '
          'JR CALL profile, identity reservations and known profile media.',
      confirmText: 'Continue',
      destructive: true,
    );

    if (!first) return;

    final bool typed = await _confirmDeleteText();
    if (!typed) return;

    setState(() {
      _busy = true;
      _deleting = true;
    });

    try {
      await _reauthenticate();

      final User? user = _user;

      if (user == null) {
        throw StateError('Authentication session is unavailable.');
      }

      final String uid = user.uid;

      await _deleteStorage('users/$uid/profile/profile.jpg');
      await _deleteStorage('users/$uid/cover/cover.jpg');

      await _firestore.deleteUserProfile(uid);

      await _auth.deleteCurrentUser();

      TextInput.finishAutofillContext(shouldSave: false);

      if (mounted) {
        Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
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
    if (!mounted) return false;

    final TextEditingController controller = TextEditingController();

    bool valid = false;

    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Final Confirmation'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('Type DELETE to permanently delete your account.'),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const <String>[],
                    decoration: const InputDecoration(
                      labelText: 'Type DELETE',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (String value) {
                      final bool next = value.trim().toUpperCase() == 'DELETE';

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
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _danger),
                  onPressed: valid
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('Delete Permanently'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result ?? false;
  }

  // =============================================================
  // REAUTHENTICATION
  // =============================================================

  Future<void> _reauthenticateIfSupported() async {
    if (_auth.hasProvider('password') || _auth.hasProvider('phone')) {
      await _reauthenticate();
    }
  }

  Future<void> _reauthenticate() async {
    final User? user = _user;

    if (user == null) {
      throw StateError('No authenticated Firebase user.');
    }

    if (_auth.hasProvider('password')) {
      final String email = user.email?.trim() ?? '';

      if (email.isEmpty) {
        throw StateError('Email information is unavailable.');
      }

      final String? password = await _passwordPrompt();

      if (password == null) {
        throw StateError('Account verification was cancelled.');
      }

      await _auth.reauthenticateWithPassword(email: email, password: password);

      return;
    }

    if (_auth.hasProvider('phone')) {
      final String phone = user.phoneNumber?.trim() ?? '';

      if (phone.isEmpty) {
        throw StateError('Phone information is unavailable.');
      }

      await _phoneReauthentication(phone);
    }
  }

  Future<void> _phoneReauthentication(String phone) async {
    final Completer<void> completer = Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (PhoneAuthCredential credential) {
        if (completer.isCompleted) return;

        unawaited(_finishAutoReauth(credential, completer));
      },
      verificationFailed: (FirebaseAuthException error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      codeSent: (String verificationId) {
        if (completer.isCompleted) return;

        unawaited(_finishManualReauth(verificationId, completer));
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );

    await completer.future;
  }

  Future<void> _finishAutoReauth(
    PhoneAuthCredential credential,
    Completer<void> completer,
  ) async {
    try {
      await _auth.reauthenticateWithPhoneCredential(credential);

      if (!completer.isCompleted) completer.complete();
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  Future<void> _finishManualReauth(
    String verificationId,
    Completer<void> completer,
  ) async {
    try {
      final String? otp = await _otpPrompt();

      if (otp == null) {
        throw StateError('Phone verification was cancelled.');
      }

      final PhoneAuthCredential credential = _auth.createPhoneCredential(
        verificationId: verificationId,
        smsCode: otp,
      );

      await _auth.reauthenticateWithPhoneCredential(credential);

      if (!completer.isCompleted) completer.complete();
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  // =============================================================
  // FIREBASE SYNC
  // =============================================================

  Future<void> _reloadAndSync() async {
    await _auth.reloadUser();

    final User? user = _user;
    if (user == null) return;

    try {
      await _firestore.syncAuthenticationProfile(
        uid: user.uid,
        email: user.email ?? '',
        phoneNumber: user.phoneNumber ?? '',
        emailVerified: user.emailVerified,
        phoneVerified: user.phoneNumber?.trim().isNotEmpty == true,
        signInProviders: _auth.linkedProviderIds,
      );
    } catch (error) {
      debugPrint('JR CALL Settings profile sync skipped: $error');
    }

    if (mounted) setState(() {});
  }

  Future<void> _deleteStorage(String path) async {
    try {
      await _storage.ref().child(path).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }

  // =============================================================
  // GENERIC ASYNC WRAPPER
  // =============================================================

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;

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
    debugPrint('JR CALL Settings error: $error');

    if (error is FirebaseAuthException) {
      _message(_authMessage(error));
    } else if (error is FirebaseException) {
      _message(error.message ?? 'Firebase operation failed.');
    } else if (error is StateError) {
      _message(error.message);
    } else if (error is ArgumentError) {
      _message(error.message?.toString() ?? 'Invalid information.');
    } else {
      _message('This operation could not be completed.');
    }
  }

  // =============================================================
  // DIALOG HELPERS
  // =============================================================

  Future<String?> _textInput({
    required String title,
    required String label,
    String initialValue = '',
    TextInputType keyboardType = TextInputType.text,
    List<String>? autofillHints,
  }) async {
    if (!mounted) return null;

    final TextEditingController controller = TextEditingController(
      text: initialValue,
    );

    final String? value = await showDialog<String>(
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
            onSubmitted: (String value) =>
                Navigator.pop(dialogContext, value.trim()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return value;
  }

  Future<String?> _passwordPrompt() async {
    if (!mounted) return null;

    final TextEditingController controller = TextEditingController();

    bool visible = false;

    final String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Confirm Password'),
              content: TextField(
                controller: controller,
                autofocus: true,
                obscureText: !visible,
                keyboardType: TextInputType.visiblePassword,
                autofillHints: const <String>[AutofillHints.password],
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setDialogState(() {
                        visible = !visible;
                      });
                    },
                    icon: Icon(
                      visible ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, controller.text),
                  child: const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  Future<String?> _otpPrompt() async {
    if (!mounted) return null;

    final TextEditingController controller = TextEditingController();

    final String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Verify Phone'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            autofillHints: const <String>[AutofillHints.oneTimeCode],
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              labelText: '6 digit OTP',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final String otp = controller.text.trim();

                if (RegExp(r'^\d{6}$').hasMatch(otp)) {
                  Navigator.pop(dialogContext, otp);
                }
              },
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  Future<_PasswordChangeData?> _passwordChangeDialog() async {
    if (!mounted) return null;

    final TextEditingController current = TextEditingController();

    final TextEditingController password = TextEditingController();

    final TextEditingController confirm = TextEditingController();

    bool visible = false;

    final _PasswordChangeData? result = await showDialog<_PasswordChangeData>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Change Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _passwordField(current, 'Current Password', !visible),
                    const SizedBox(height: 12),
                    _passwordField(
                      password,
                      'New Password',
                      !visible,
                      newPassword: true,
                    ),
                    const SizedBox(height: 12),
                    _passwordField(
                      confirm,
                      'Confirm New Password',
                      !visible,
                      newPassword: true,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: visible,
                      title: const Text('Show Passwords'),
                      onChanged: (bool? value) {
                        setDialogState(() {
                          visible = value ?? false;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      _PasswordChangeData(
                        current: current.text,
                        password: password.text,
                        confirm: confirm.text,
                      ),
                    );
                  },
                  child: const Text('Change'),
                ),
              ],
            );
          },
        );
      },
    );

    current.dispose();
    password.dispose();
    confirm.dispose();

    return result;
  }

  Future<_NewPasswordData?> _newPasswordDialog() async {
    if (!mounted) return null;

    final TextEditingController password = TextEditingController();

    final TextEditingController confirm = TextEditingController();

    final _NewPasswordData? result = await showDialog<_NewPasswordData>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Set Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _passwordField(password, 'New Password', true, newPassword: true),
              const SizedBox(height: 12),
              _passwordField(
                confirm,
                'Confirm Password',
                true,
                newPassword: true,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  _NewPasswordData(
                    password: password.text,
                    confirm: confirm.text,
                  ),
                );
              },
              child: const Text('Set Password'),
            ),
          ],
        );
      },
    );

    password.dispose();
    confirm.dispose();

    return result;
  }

  Widget _passwordField(
    TextEditingController controller,
    String label,
    bool obscure, {
    bool newPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: <String>[
        newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
    bool destructive = false,
  }) async {
    if (!mounted) return false;

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(backgroundColor: _danger)
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Widget _sheetAction(IconData icon, String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            foregroundColor: _primary,
            side: const BorderSide(color: Color(0xFFDBEAFE)),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // HELPERS
  // =============================================================

  void _setBusy(bool value) {
    if (!mounted || _busy == value) return;

    setState(() {
      _busy = value;
    });
  }

  void _message(String message) {
    if (!mounted || message.trim().isEmpty) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  String _normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[\s()\-\u2013\u2014]'), '');
  }

  bool _validPhone(String value) {
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value);
  }

  bool _validEmail(String value) {
    return value.length <= 254 &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  String _verificationText(User user) {
    final bool email = user.email?.trim().isNotEmpty == true;
    final bool phone = user.phoneNumber?.trim().isNotEmpty == true;

    if (email && user.emailVerified && phone) {
      return 'Email and Phone verified';
    }

    if (email && user.emailVerified) {
      return 'Email verified';
    }

    if (phone) {
      return email ? 'Phone verified • Email pending' : 'Phone verified';
    }

    if (email) return 'Email verification pending';

    return 'No verified identity';
  }

  String _providerLabel(String id) {
    switch (id) {
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
        return id;
    }
  }

  IconData _providerIcon(String id) {
    switch (id) {
      case 'password':
        return Icons.password_rounded;
      case 'phone':
        return Icons.phone_android_rounded;
      case 'google.com':
        return Icons.account_circle_outlined;
      case 'apple.com':
        return Icons.apple;
      default:
        return Icons.security_rounded;
    }
  }

  String _authMessage(FirebaseAuthException error) {
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
      case 'quota-exceeded':
        return 'Firebase verification quota has been reached.';
      default:
        return error.message ?? 'Authentication operation failed.';
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final User? user = _user;

    final String email = user?.email?.trim() ?? '';
    final String phone = user?.phoneNumber?.trim() ?? '';

    final List<String> providers = List<String>.from(_auth.linkedProviderIds);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: <Widget>[
              // -------------------------------------------------
              // ACCOUNT STATUS
              // -------------------------------------------------
              _AccountHeader(
                signedIn: _signedIn,
                user: user,
                onProfile: () => unawaited(_openProfile()),
                onAccount: () => unawaited(_accountSwitcher()),
              ),

              const SizedBox(height: 24),

              // -------------------------------------------------
              // PROFILE
              // -------------------------------------------------
              const _SectionTitle('Profile & Personal Information'),

              _SettingsTile(
                icon: Icons.person_outline_rounded,
                title: 'My Profile',
                subtitle:
                    'Name, Username, JR CALL ID, Bio, Country, DOB and Photos',
                onTap: () => unawaited(_openProfile()),
              ),

              const SizedBox(height: 24),

              // -------------------------------------------------
              // ACCOUNT SECURITY
              // -------------------------------------------------
              const _SectionTitle('Account & Security'),

              _SettingsTile(
                icon: Icons.email_outlined,
                title: 'Email',
                subtitle: email.isEmpty ? 'Add Email' : email,
                trailingText: email.isEmpty
                    ? null
                    : user?.emailVerified == true
                    ? 'Verified'
                    : 'Pending',
                onTap: () => unawaited(_emailSettings()),
              ),

              _SettingsTile(
                icon: Icons.phone_outlined,
                title: 'Phone Number',
                subtitle: phone.isEmpty ? 'Add Phone Number' : phone,
                trailingText: phone.isEmpty ? null : 'Verified',
                onTap: () => unawaited(_phoneSettings()),
              ),

              _SettingsTile(
                icon: Icons.verified_user_outlined,
                title: 'Verification',
                subtitle: user == null
                    ? 'Login required'
                    : _verificationText(user),
                onTap: () => unawaited(_refreshVerification()),
              ),

              _SettingsTile(
                icon: Icons.password_outlined,
                title: 'Password',
                subtitle: !_signedIn
                    ? 'Login required'
                    : _auth.hasProvider('password')
                    ? 'Change Password'
                    : 'Set Email/Password sign-in',
                onTap: () => unawaited(_passwordSettings()),
              ),

              _SettingsTile(
                icon: Icons.key_outlined,
                title: 'Sign-in Providers',
                subtitle: providers.isEmpty
                    ? 'Provider information unavailable'
                    : providers.map(_providerLabel).join(', '),
                onTap: () => unawaited(_providers()),
              ),

              const SizedBox(height: 24),

              // -------------------------------------------------
              // ACCOUNT ACCESS
              // -------------------------------------------------
              const _SectionTitle('Account Access'),

              _SettingsTile(
                icon: Icons.switch_account_outlined,
                title: _signedIn
                    ? 'Add / Switch Account'
                    : 'Login / Add Account',
                subtitle: _signedIn
                    ? 'Sign out this session and Login with another JR CALL account'
                    : 'Login to an existing account or create a new account',
                onTap: () => unawaited(_accountSwitcher()),
              ),

              if (_signedIn)
                _SettingsTile(
                  icon: Icons.logout_rounded,
                  title: 'Log Out',
                  subtitle: 'Return to JR CALL Guest Mode',
                  onTap: () => unawaited(_logout()),
                ),

              const SizedBox(height: 24),

              // -------------------------------------------------
              // PRIVACY
              // -------------------------------------------------
              const _SectionTitle('Discovery & Privacy'),

              const _InformationCard(
                icon: Icons.manage_search_outlined,
                title: 'JR CALL Discovery',
                description:
                    'JR CALL ID, Username, Name, permitted Email and '
                    'permitted Phone are discovery inputs. '
                    'Firebase UID remains private.',
              ),

              const SizedBox(height: 14),

              const _InformationCard(
                icon: Icons.security_rounded,
                title: 'Account Security',
                description:
                    'Passwords and OTP codes are never stored in '
                    'your public JR CALL profile.',
              ),

              const SizedBox(height: 24),

              // -------------------------------------------------
              // CALL ENGINE
              // -------------------------------------------------
              const _SectionTitle('Call Engine'),

              const _InformationCard(
                icon: Icons.call_outlined,
                title: 'Call Preferences',
                description:
                    'Audio, Video, Network, Recovery and WebRTC remain '
                    'owned by the protected JR CALL Call Engine.',
              ),

              if (_signedIn) ...<Widget>[
                const SizedBox(height: 34),

                // -----------------------------------------------
                // DANGER ZONE — DELETE HIDDEN INSIDE
                // -----------------------------------------------
                _DangerZone(
                  expanded: _dangerExpanded,
                  deleting: _deleting,
                  onToggle: () {
                    setState(() {
                      _dangerExpanded = !_dangerExpanded;
                    });
                  },
                  onDelete: () => unawaited(_deleteAccount()),
                ),
              ],
            ],
          ),

          if (_busy)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: Color(0x14000000),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const CircularProgressIndicator(),
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
  Widget build(BuildContext context) {
    final String title = signedIn
        ? (user?.displayName?.trim().isNotEmpty == true
              ? user!.displayName!.trim()
              : 'JR CALL Account')
        : 'JR CALL Guest';

    final String subtitle = !signedIn
        ? 'Browse freely • Login when an account is required'
        : user?.email?.trim().isNotEmpty == true
        ? user!.email!.trim()
        : user?.phoneNumber?.trim().isNotEmpty == true
        ? user!.phoneNumber!.trim()
        : 'Authenticated account';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE7F5)),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 29,
            backgroundColor: const Color(0xFFEAF2FF),
            backgroundImage: user?.photoURL?.trim().isNotEmpty == true
                ? NetworkImage(user!.photoURL!.trim())
                : null,
            child: user?.photoURL?.trim().isNotEmpty == true
                ? null
                : Icon(
                    signedIn ? Icons.person_rounded : Icons.public_rounded,
                    color: const Color(0xFF2563EB),
                    size: 30,
                  ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: signedIn ? 'Profile' : 'Account',
            onPressed: signedIn ? onProfile : onAccount,
            icon: Icon(
              signedIn ? Icons.chevron_right_rounded : Icons.login_rounded,
              color: const Color(0xFF2563EB),
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
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        children: <Widget>[
          ListTile(
            onTap: onToggle,
            leading: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFDC2626),
            ),
            title: const Text(
              'Danger Zone',
              style: TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: const Text('Permanent account actions'),
            trailing: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
          ),
          if (expanded) ...<Widget>[
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Text(
                'Deleting your account permanently removes your '
                'JR CALL identity and cannot be undone.',
                style: TextStyle(
                  color: Color(0xFF7F1D1D),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: deleting ? null : onDelete,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(
                    deleting ? 'DELETING...' : 'DELETE ACCOUNT',
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Color(0xFFEFF6FF),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Color(0xFF2563EB)),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (trailingText != null) ...<Widget>[
              Text(
                trailingText!,
                style: TextStyle(
                  color: trailingText == 'Verified'
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFF59E0B),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF475569)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
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
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ===============================================================
// VERIFICATION BADGE
// ===============================================================

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({
    required this.verified,
    required this.verifiedText,
    required this.pendingText,
  });

  final bool verified;
  final String verifiedText;
  final String pendingText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          verified ? Icons.verified_outlined : Icons.schedule_outlined,
          size: 18,
          color: verified ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
        ),
        const SizedBox(width: 6),
        Text(
          verified ? verifiedText : pendingText,
          style: TextStyle(
            color: verified ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
            fontWeight: FontWeight.w700,
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
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFD1D5DB),
          borderRadius: BorderRadius.circular(99),
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
  const _NewPasswordData({required this.password, required this.confirm});

  final String password;
  final String confirm;
}

// ===============================================================
// END OF FILE
//
// NEXT FILE: firestore.rules
// Location: firestore.rules
// REMAINING: 1 FILE
// ===============================================================
