// ===============================================================
// JR CALL
// File: create_account_screen.dart
// Location: lib/screens/create_account_screen.dart
//
// FINAL GUEST-FIRST SIGNUP:
// - Phone Number is required.
// - Phone OTP uses Firebase Authentication only.
// - Existing Phone account cannot become a new signup.
// - Email is optional.
// - Email + Password link to the same Firebase UID.
// - Full Name / Username / DOB are optional.
// - Profile / Cover photos are optional.
// - Profile and Cover crop/upload remain supported.
// - JR CALL public ID remains separate from Firebase UID.
// - Password / OTP are never stored in Firestore.
// - Guest protected-action return information is preserved.
// - No TURN/WebRTC logic exists here.
// ===============================================================

import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:uuid/uuid.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import '../utils/permissions.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'otp_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  // =============================================================
  // SERVICES / CONSTANTS
  // =============================================================

  final AuthService _auth = AuthService.instance;
  final FirestoreService _firestore = FirestoreService.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  static const Uuid _uuid = Uuid();

  static const int _profileLimit = 5 * 1024 * 1024;
  static const int _coverLimit = 10 * 1024 * 1024;

  static const Color _background = Color(0xFFF8FAFF);
  static const Color _surface = Colors.white;
  static const Color _blue = Color(0xFF1769F5);
  static const Color _blueLight = Color(0xFF4194FF);
  static const Color _text = Color(0xFF111827);
  static const Color _secondary = Color(0xFF68758C);
  static const Color _border = Color(0xFFE3E8F1);
  static const Color _field = Color(0xFFFBFCFF);

  // =============================================================
  // CONTROLLERS
  // =============================================================

  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _username = TextEditingController();

  // =============================================================
  // STATE
  // =============================================================

  int _step = 1;

  String _completePhone = '';
  String _phoneCountryCode = 'BD';

  String? _countryName;
  String? _countryCode;
  DateTime? _dob;

  Uint8List? _profileBytes;
  Uint8List? _coverBytes;

  bool _loading = false;
  bool _pickingMedia = false;
  bool _passwordVisible = false;
  bool _confirmVisible = false;

  bool _otpRouteOpen = false;
  bool _autoCompleting = false;

  bool _routeArgumentsResolved = false;
  bool _guestReturn = false;
  String? _requestedAction;

  late final String _jrIdCandidate = _generateJrId();

  bool get _busy => _loading || _pickingMedia;

  String get _normalizedEmail => _email.text.trim().toLowerCase();

  bool get _hasEmail => _normalizedEmail.isNotEmpty;

  String? get _normalizedUsername => _normalizeUsername(_username.text);

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();
    _initializeCountry();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_routeArgumentsResolved) {
      return;
    }

    _routeArgumentsResolved = true;

    final Object? arguments = ModalRoute.of(context)?.settings.arguments;

    if (arguments is! Map) {
      return;
    }

    final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);

    _guestReturn = data['guestReturn'] == true;

    final Object? action = data['requestedAction'];

    if (action is String && action.trim().isNotEmpty) {
      _requestedAction = action.trim();
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _name.dispose();
    _username.dispose();

    super.dispose();
  }

  // =============================================================
  // COUNTRY
  // =============================================================

  void _initializeCountry() {
    try {
      final Country? country = Country.tryParse(_phoneCountryCode);

      _countryName = country?.name;
      _countryCode = country?.countryCode.toUpperCase() ?? _phoneCountryCode;
    } catch (error) {
      debugPrint('JR CALL default country resolution skipped: $error');

      _countryCode = _phoneCountryCode;
    }
  }

  // =============================================================
  // VALIDATION
  // =============================================================

  void _continue() {
    if (_busy) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String? error = _validate();

    if (error != null) {
      _message(error);
      return;
    }

    setState(() => _step = 2);
  }

  String? _validate() {
    final String phoneNumber = _currentPhone();
    final String email = _normalizedEmail;
    final String name = _name.text.trim();
    final String? username = _normalizedUsername;

    if (!_isValidPhone(phoneNumber)) {
      return 'Enter a valid Phone Number with country code.';
    }

    if (email.isNotEmpty) {
      if (!_isValidEmail(email)) {
        return 'Enter a valid Email address.';
      }

      if (_password.text.length < 6) {
        return 'Password must contain at least 6 characters.';
      }

      if (_password.text != _confirmPassword.text) {
        return 'Password and Confirm Password do not match.';
      }
    }

    if (name.length > 80) {
      return 'Full Name cannot exceed 80 characters.';
    }

    if (username != null && !_isValidUsername(username)) {
      return 'Short Name must be 3-30 characters using letters, '
          'numbers, dots or underscores.';
    }

    if (_dob?.isAfter(DateTime.now()) == true) {
      return 'Date of Birth cannot be in the future.';
    }

    return null;
  }

  // =============================================================
  // CREATE ACCOUNT
  // =============================================================

  Future<void> _createAccount() async {
    if (_busy) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String? error = _validate();

    if (error != null) {
      _message(error);
      _goStepOne();
      return;
    }

    _otpRouteOpen = false;
    _autoCompleting = false;

    _setLoading(true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: _currentPhone(),
        verificationCompleted: (PhoneAuthCredential credential) {
          if (!mounted || _otpRouteOpen || _autoCompleting) {
            return;
          }

          _autoCompleting = true;

          unawaited(_completeAutomaticSignup(credential));
        },
        verificationFailed: (FirebaseAuthException error) {
          if (!mounted) {
            return;
          }

          _autoCompleting = false;
          _setLoading(false);
          _message(_authError(error));
        },
        codeSent: (String verificationId) {
          if (!mounted || _autoCompleting || _otpRouteOpen) {
            return;
          }

          _otpRouteOpen = true;
          _setLoading(false);

          unawaited(_openOtp(verificationId));
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted && !_otpRouteOpen && !_autoCompleting) {
            _setLoading(false);
          }
        },
      );
    } on FirebaseAuthException catch (error) {
      _message(_authError(error));
      _setLoading(false);
    } on ArgumentError catch (error) {
      _message(error.message?.toString() ?? 'Invalid account information.');
      _setLoading(false);
    } on StateError catch (error) {
      _message(error.message);
      _setLoading(false);
    } catch (error, stackTrace) {
      debugPrint('JR CALL account creation start error: $error');

      debugPrintStack(
        label: 'JR CALL account creation',
        stackTrace: stackTrace,
      );

      _message('Account creation could not be started. Please try again.');

      _setLoading(false);
    }
  }

  // =============================================================
  // MANUAL OTP
  // =============================================================

  Future<void> _openOtp(String verificationId) async {
    if (!mounted) {
      return;
    }

    try {
      final bool? verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          settings: RouteSettings(
            arguments: <String, dynamic>{
              'mode': 'phoneSignUp',
              'fullName': _name.text.trim().isEmpty ? null : _name.text.trim(),
              'username': _normalizedUsername,
              'country': _countryName,
              'countryCode': _countryCode,
              'dateOfBirth': _dob?.toIso8601String(),
              'jrCallUserIdCandidate': _jrIdCandidate,
              'guestReturn': _guestReturn,
              if (_requestedAction != null) 'requestedAction': _requestedAction,
            },
          ),
          builder: (BuildContext context) {
            return OtpScreen(
              verificationId: verificationId,
              phoneNumber: _currentPhone(),
              email: _normalizedEmail.isEmpty ? null : _normalizedEmail,
              provider: 'phone_signup',
            );
          },
        ),
      );

      if (!mounted || verified != true) {
        return;
      }

      await _finishManualSignup();
    } finally {
      _otpRouteOpen = false;
    }
  }

  Future<void> _finishManualSignup() async {
    if (!mounted) {
      return;
    }

    _setLoading(true);

    try {
      User user = _requireUser();

      if (_hasEmail) {
        try {
          await _linkEmail();
        } catch (error) {
          await _rollbackAccount(user.uid);
          rethrow;
        }

        user = _requireUser();
      }

      await _syncAuthProfile(user);
      await _uploadMediaSafely(user.uid);

      _finishSignup();
    } on FirebaseAuthException catch (error) {
      _message(_authError(error));
    } on FirebaseException catch (error) {
      _message(_firebaseError(error));
    } on StateError catch (error) {
      _message(error.message);
    } on ArgumentError catch (error) {
      _message(error.message?.toString() ?? 'Invalid account information.');
    } catch (error, stackTrace) {
      debugPrint('JR CALL manual signup finalization error: $error');

      debugPrintStack(
        label: 'JR CALL manual signup finalization',
        stackTrace: stackTrace,
      );

      _message('Account setup could not be finalized.');
    } finally {
      _setLoading(false);
    }
  }

  // =============================================================
  // AUTOMATIC PHONE SIGNUP
  // =============================================================

  Future<void> _completeAutomaticSignup(PhoneAuthCredential credential) async {
    bool createdAuthUser = false;
    bool createdProfile = false;

    if (mounted) {
      _setLoading(true);
    }

    try {
      final UserCredential result = await _auth.signInWithPhoneCredential(
        credential,
      );

      if (result.user == null && _auth.currentUser == null) {
        throw StateError('Authenticated Firebase user was not found.');
      }
      result.user ?? _requireUser();

      createdAuthUser = result.additionalUserInfo?.isNewUser == true;

      if (!createdAuthUser) {
        await _safeSignOut();

        throw StateError(
          'An account already exists with this Phone Number. '
          'Use Login instead.',
        );
      }

      if (_hasEmail) {
        await _linkEmail();
      }

      final User refreshed = _requireUser();

      final String? username = _normalizedUsername;

      if (username != null) {
        final bool available = await _firestore.isUsernameAvailable(
          username,
          forUid: refreshed.uid,
        );

        if (!available) {
          throw StateError('This Short Name is already in use.');
        }
      }

      await _createProfile(refreshed);
      createdProfile = true;

      await _uploadMediaSafely(refreshed.uid);

      _finishSignup();
    } on FirebaseAuthException catch (error) {
      if (createdAuthUser && !createdProfile) {
        await _rollbackCurrentUser();
      }

      _message(_authError(error));
    } on FirebaseException catch (error) {
      if (createdAuthUser && !createdProfile) {
        await _rollbackCurrentUser();
      }

      _message(_firebaseError(error));
    } on StateError catch (error) {
      if (createdAuthUser && !createdProfile) {
        await _rollbackCurrentUser();
      }

      _message(error.message);
    } on ArgumentError catch (error) {
      if (createdAuthUser && !createdProfile) {
        await _rollbackCurrentUser();
      }

      _message(error.message?.toString() ?? 'Invalid account information.');
    } catch (error, stackTrace) {
      if (createdAuthUser && !createdProfile) {
        await _rollbackCurrentUser();
      }

      debugPrint('JR CALL automatic signup error: $error');

      debugPrintStack(
        label: 'JR CALL automatic signup',
        stackTrace: stackTrace,
      );

      _message('Phone verification could not be completed.');
    } finally {
      _autoCompleting = false;

      if (mounted) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // EMAIL LINK
  // =============================================================

  Future<void> _linkEmail() async {
    if (!_hasEmail) {
      return;
    }

    final User before = _requireUser();

    final bool passwordLinked = before.providerData.any(
      (UserInfo provider) => provider.providerId == 'password',
    );

    if (passwordLinked) {
      final String existing = before.email?.trim().toLowerCase() ?? '';

      if (existing == _normalizedEmail) {
        return;
      }

      throw StateError('A different Email Login is already linked.');
    }

    await _auth.linkEmailPasswordToCurrentUser(
      email: _normalizedEmail,
      password: _password.text,
    );

    await _auth.reloadUser();

    final String linkedEmail = _requireUser().email?.trim().toLowerCase() ?? '';

    if (linkedEmail != _normalizedEmail) {
      throw StateError('Email Login could not be safely linked.');
    }
  }

  // =============================================================
  // FIRESTORE PROFILE
  // =============================================================

  Future<void> _createProfile(User user) async {
    const int attempts = 8;

    for (int index = 0; index < attempts; index++) {
      final String publicId = index == 0 ? _jrIdCandidate : _generateJrId();

      final DateTime now = DateTime.now();

      final UserModel model = UserModel(
        uid: user.uid,
        name: _name.text.trim(),
        phone: user.phoneNumber?.trim().isNotEmpty == true
            ? user.phoneNumber!.trim()
            : _currentPhone(),
        email: user.email?.trim().isNotEmpty == true
            ? user.email!.trim().toLowerCase()
            : (_hasEmail ? _normalizedEmail : null),
        username: _normalizedUsername,
        userAddress: publicId,
        photoUrl: null,
        coverPhoto: null,
        bio: null,
        country: _countryName,
        countryCode: _countryCode,
        dateOfBirth: _dob,
        online: true,
        verified: true,
        createdAt: now,
        updatedAt: now,
        lastSeen: now,
        lastLogin: now,
        provider: _hasEmail ? 'phone_email' : 'phone',
        isBlocked: false,
        isDeleted: false,
      );

      try {
        await _firestore.createUser(model);
        await _syncAuthProfile(user);
        return;
      } on StateError catch (error) {
        if (error.message.toLowerCase().contains('jr call user address')) {
          continue;
        }

        rethrow;
      }
    }

    throw StateError('A unique JR CALL User ID could not be generated.');
  }

  Future<void> _syncAuthProfile(User user) async {
    User effectiveUser = user;

    try {
      await user.reload();

      effectiveUser = _auth.currentUser ?? user;
    } catch (error) {
      debugPrint('JR CALL user reload skipped: $error');
    }

    await _firestore.syncAuthenticationProfile(
      uid: effectiveUser.uid,
      email: effectiveUser.email,
      phoneNumber: effectiveUser.phoneNumber,
      emailVerified: effectiveUser.emailVerified,
      phoneVerified: effectiveUser.phoneNumber?.trim().isNotEmpty == true,
      signInProviders: _auth.linkedProviderIds,
    );
  }

  // =============================================================
  // FINAL ROUTING
  // =============================================================

  void _finishSignup() {
    if (!mounted) {
      return;
    }

    TextInput.finishAutofillContext(shouldSave: true);

    if (_guestReturn && Navigator.of(context).canPop()) {
      Navigator.of(context).pop<bool>(true);
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const HomeScreen(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  // =============================================================
  // ROLLBACK
  // =============================================================

  Future<void> _rollbackCurrentUser() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      await user.delete();
    } catch (error) {
      debugPrint('JR CALL Auth rollback delete failed: $error');

      await _safeSignOut();
    }
  }

  Future<void> _rollbackAccount(String uid) async {
    try {
      await _firestore.deleteUserProfile(uid);
    } catch (error) {
      debugPrint('JR CALL Firestore rollback skipped: $error');
    }

    await _rollbackCurrentUser();
  }

  Future<void> _safeSignOut() async {
    try {
      await _auth.signOut();
    } catch (error) {
      debugPrint('JR CALL safe sign-out skipped: $error');
    }
  }

  User _requireUser() {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('Authenticated Firebase user was not found.');
    }

    return user;
  }

  // =============================================================
  // JR CALL ID
  // =============================================================

  String _generateJrId() {
    final String random = _uuid
        .v4()
        .replaceAll('-', '')
        .substring(0, 12)
        .toLowerCase();

    return 'jrcall_$random';
  }

  // =============================================================
  // MEDIA PICK
  // =============================================================

  Future<void> _chooseProfilePhoto() async {
    if (_busy) {
      return;
    }

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_supportsCamera)
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take Photo'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(ImageSource.camera),
                ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        );
      },
    );

    if (source != null) {
      await _pickProfile(source);
    }
  }

  Future<void> _pickProfile(ImageSource source) async {
    _setPicking(true);

    try {
      if (source == ImageSource.camera && _isMobile) {
        if (!await AppPermissions.requestCamera()) {
          _message('Camera permission is required.');
          return;
        }
      }

      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2400,
        maxHeight: 2400,
        requestFullMetadata: false,
      );

      if (file == null) {
        return;
      }

      final Uint8List? bytes = await _cropOrRead(
        file: file,
        title: 'Crop Profile Photo',
        ratio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (bytes == null) {
        return;
      }

      _validateBytes(bytes, _profileLimit, 'Profile Photo');

      if (mounted) {
        setState(() => _profileBytes = bytes);
      }
    } on ArgumentError catch (error) {
      _message(error.message?.toString() ?? 'Invalid Profile Photo.');
    } catch (error, stackTrace) {
      debugPrint('JR CALL Profile Photo error: $error');

      debugPrintStack(label: 'JR CALL Profile Photo', stackTrace: stackTrace);

      _message('Profile Photo could not be selected.');
    } finally {
      _setPicking(false);
    }
  }

  Future<void> _chooseCoverPhoto() async {
    if (_busy) {
      return;
    }

    _setPicking(true);

    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
        maxWidth: 3200,
        maxHeight: 2000,
        requestFullMetadata: false,
      );

      if (file == null) {
        return;
      }

      final Uint8List? bytes = await _cropOrRead(
        file: file,
        title: 'Crop Cover Photo',
        ratio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (bytes == null) {
        return;
      }

      _validateBytes(bytes, _coverLimit, 'Cover Photo');

      if (mounted) {
        setState(() => _coverBytes = bytes);
      }
    } on ArgumentError catch (error) {
      _message(error.message?.toString() ?? 'Invalid Cover Photo.');
    } catch (error, stackTrace) {
      debugPrint('JR CALL Cover Photo error: $error');

      debugPrintStack(label: 'JR CALL Cover Photo', stackTrace: stackTrace);

      _message('Cover Photo could not be selected.');
    } finally {
      _setPicking(false);
    }
  }

  Future<Uint8List?> _cropOrRead({
    required XFile file,
    required String title,
    required CropAspectRatio ratio,
    required int maxWidth,
    required int maxHeight,
  }) async {
    if (!_supportsCropper) {
      return file.readAsBytes();
    }

    final CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      aspectRatio: ratio,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: title,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: title,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(width: 520, height: 520),
        ),
      ],
    );

    return cropped?.readAsBytes();
  }

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _supportsCamera => _isMobile;

  bool get _supportsCropper => kIsWeb || _isMobile;

  void _validateBytes(Uint8List bytes, int limit, String label) {
    if (bytes.isEmpty) {
      throw ArgumentError('$label is empty.');
    }

    if (bytes.lengthInBytes > limit) {
      throw ArgumentError('$label is too large.');
    }
  }

  // =============================================================
  // MEDIA UPLOAD
  // =============================================================

  Future<void> _uploadMediaSafely(String uid) async {
    try {
      await _uploadMedia(uid);
    } catch (error, stackTrace) {
      debugPrint('JR CALL optional media upload skipped: $error');

      debugPrintStack(label: 'JR CALL signup media', stackTrace: stackTrace);
    }
  }

  Future<void> _uploadMedia(String uid) async {
    String? photoUrl;
    String? coverUrl;

    if (_profileBytes != null) {
      photoUrl = await _uploadImage(
        path: 'users/$uid/profile/profile.jpg',
        bytes: _profileBytes!,
        limit: _profileLimit,
      );
    }

    if (_coverBytes != null) {
      coverUrl = await _uploadImage(
        path: 'users/$uid/cover/cover.jpg',
        bytes: _coverBytes!,
        limit: _coverLimit,
      );
    }

    if (photoUrl == null && coverUrl == null) {
      return;
    }

    await _firestore.updateProfile(
      uid: uid,
      photoUrl: photoUrl,
      coverPhoto: coverUrl,
    );

    if (photoUrl != null) {
      try {
        await _auth.updatePhotoUrl(photoUrl);
      } catch (error) {
        debugPrint('JR CALL Auth photo sync skipped: $error');
      }
    }
  }

  Future<String> _uploadImage({
    required String path,
    required Uint8List bytes,
    required int limit,
  }) async {
    _validateBytes(bytes, limit, 'Image');

    final TaskSnapshot snapshot = await _storage
        .ref()
        .child(path)
        .putData(
          bytes,
          SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'public,max-age=86400',
          ),
        );

    if (snapshot.state != TaskState.success) {
      throw StateError('Image upload did not complete.');
    }

    final String url = await snapshot.ref.getDownloadURL();

    if (url.trim().isEmpty) {
      throw StateError('Firebase Storage returned no image URL.');
    }

    return url;
  }

  // =============================================================
  // DOB / NAVIGATION
  // =============================================================

  Future<void> _selectDob() async {
    if (_loading) {
      return;
    }

    final DateTime now = DateTime.now();

    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (selected != null && mounted) {
      setState(() {
        _dob = DateTime(selected.year, selected.month, selected.day);
      });
    }
  }

  void _goStepOne() {
    if (!_busy) {
      setState(() => _step = 1);
    }
  }

  void _openLogin() {
    if (_busy) {
      return;
    }

    TextInput.finishAutofillContext(shouldSave: false);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          arguments: <String, dynamic>{
            'guestReturn': _guestReturn,
            if (_requestedAction != null) 'requestedAction': _requestedAction,
          },
        ),
        builder: (BuildContext context) => const LoginScreen(),
      ),
    );
  }

  // =============================================================
  // NORMALIZATION
  // =============================================================

  String _currentPhone() {
    if (_phone.text.trim().isEmpty) {
      return '';
    }

    return _normalizePhone(_completePhone);
  }

  String _normalizePhone(String value) =>
      value.trim().replaceAll(RegExp(r'[\s()\-]'), '');

  String? _normalizeUsername(String value) {
    String normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized.isEmpty ? null : normalized;
  }

  bool _isValidPhone(String value) =>
      RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value);

  bool _isValidEmail(String value) =>
      value.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  bool _isValidUsername(String value) =>
      RegExp(r'^[a-z0-9._]{3,30}$').hasMatch(value) &&
      !value.startsWith('.') &&
      !value.endsWith('.') &&
      !value.contains('..');

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';

  // =============================================================
  // ERRORS
  // =============================================================

  String _authError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Enter a valid Phone Number.';
      case 'credential-already-in-use':
      case 'phone-number-already-exists':
        return 'This Phone Number is already linked to another account.';
      case 'email-already-in-use':
        return 'This Email is already linked to another JR CALL account.';
      case 'provider-already-linked':
        return 'Email Login is already linked to this account.';
      case 'operation-not-allowed':
        return 'This authentication method is currently unavailable.';
      case 'network-request-failed':
        return 'Check your Internet connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'quota-exceeded':
        return 'OTP service quota has been reached.';
      case 'app-not-authorized':
        return 'This application is not authorized for Firebase Authentication.';
      case 'invalid-app-credential':
        return 'Firebase could not verify this application.';
      case 'captcha-check-failed':
        return 'Firebase security verification failed.';
      case 'session-expired':
        return 'Verification session expired. Request a new OTP.';
      case 'invalid-verification-code':
        return 'The SMS verification code is incorrect.';
      case 'verification-in-progress':
        return 'Phone verification is already in progress.';
      case 'weak-password':
        return 'Password must contain at least 6 characters.';
      case 'invalid-email':
        return 'Enter a valid Email address.';
      default:
        return error.message ?? 'Authentication failed.';
    }
  }

  String _firebaseError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthorized':
        return 'Permission denied while updating your account.';
      case 'network-request-failed':
      case 'unavailable':
        return 'Firebase is temporarily unavailable.';
      default:
        return error.message ?? 'Firebase operation failed.';
    }
  }

  // =============================================================
  // STATE
  // =============================================================

  void _setLoading(bool value) {
    if (mounted && _loading != value) {
      setState(() => _loading = value);
    }
  }

  void _setPicking(bool value) {
    if (mounted && _pickingMedia != value) {
      setState(() => _pickingMedia = value);
    }
  }

  void _message(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  // =============================================================
  // UI
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 1 && !_busy,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _step == 2 && !_busy) {
          _goStepOne();
        }
      },
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _border),
                  ),
                  child: AutofillGroup(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _step == 1 ? _buildStepOne() : _buildStepTwo(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        IconButton.filledTonal(
          onPressed: _busy
              ? null
              : () {
                  if (_step == 2) {
                    _goStepOne();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.asset(
            'assets/images/logo.png',
            width: 58,
            height: 58,
            fit: BoxFit.cover,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) {
                  return Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    color: const Color(0xFFEAF3FF),
                    child: const Icon(Icons.phone_in_talk, color: _blue),
                  );
                },
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: 'JR ',
                      style: TextStyle(color: _text),
                    ),
                    TextSpan(
                      text: 'CALL',
                      style: TextStyle(color: _blue),
                    ),
                  ],
                ),
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              Text(
                'Premium Calling Experience',
                style: TextStyle(color: _secondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _progress() {
    return Row(
      children: <Widget>[
        _stepCircle(1),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: _step == 2 ? _blue : _border,
          ),
        ),
        _stepCircle(2),
      ],
    );
  }

  Widget _stepCircle(int number) {
    final bool active = number <= _step;

    return CircleAvatar(
      radius: 17,
      backgroundColor: active ? _blue : _border,
      child: number < _step
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
          : Text(
              '$number',
              style: TextStyle(
                color: active ? Colors.white : _secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  Widget _buildStepOne() {
    return Column(
      key: const ValueKey<String>('step1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(),
        const SizedBox(height: 28),
        _progress(),
        const SizedBox(height: 30),
        const Text(
          'Create Your Account',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _text,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Phone Number is required',
          textAlign: TextAlign.center,
          style: TextStyle(color: _secondary),
        ),
        const SizedBox(height: 26),

        IntlPhoneField(
          controller: _phone,
          initialCountryCode: _phoneCountryCode,
          enabled: !_busy,
          disableLengthCheck: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            label: 'Phone Number *',
            icon: Icons.phone_outlined,
          ),
          onChanged: (phone) {
            _completePhone = _phone.text.trim().isEmpty
                ? ''
                : _normalizePhone(phone.completeNumber);
          },
          onCountryChanged: (country) {
            _phoneCountryCode = country.code;
            _countryCode = country.code.toUpperCase();

            try {
              _countryName = Country.tryParse(country.code)?.name;
            } catch (error) {
              debugPrint('JR CALL country resolution skipped: $error');
              _countryName = null;
            }
          },
        ),

        const SizedBox(height: 14),

        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.email],
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (String value) {
            if (mounted) {
              setState(() {});
            }
          },
          decoration: _decoration(
            label: 'Email Address (Optional)',
            icon: Icons.email_outlined,
          ),
        ),

        if (_hasEmail) ...<Widget>[
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: !_passwordVisible,
            autofillHints: const <String>[AutofillHints.newPassword],
            decoration: _decoration(
              label: 'Password *',
              icon: Icons.lock_outline,
              suffix: IconButton(
                onPressed: _busy
                    ? null
                    : () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                icon: Icon(
                  _passwordVisible ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmPassword,
            enabled: !_busy,
            obscureText: !_confirmVisible,
            autofillHints: const <String>[AutofillHints.newPassword],
            decoration: _decoration(
              label: 'Confirm Password *',
              icon: Icons.lock_reset,
              suffix: IconButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _confirmVisible = !_confirmVisible),
                icon: Icon(
                  _confirmVisible ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),

        TextField(
          controller: _name,
          enabled: !_busy,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: 80,
          decoration: _decoration(
            label: 'Full Name (Optional)',
            icon: Icons.person_outline,
          ).copyWith(counterText: ''),
        ),

        const SizedBox(height: 14),

        TextField(
          controller: _username,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 30,
          decoration: _decoration(
            label: 'Short Name (Optional)',
            icon: Icons.person_add_alt_1_outlined,
          ).copyWith(counterText: ''),
        ),

        const SizedBox(height: 14),

        InkWell(
          onTap: _busy ? null : _selectDob,
          borderRadius: BorderRadius.circular(18),
          child: InputDecorator(
            decoration: _decoration(
              label: 'Date of Birth (Optional)',
              icon: Icons.calendar_month_outlined,
              suffix: _dob == null
                  ? null
                  : IconButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _dob = null),
                      icon: const Icon(Icons.close),
                    ),
            ),
            child: Text(
              _dob == null ? 'Select Date of Birth' : _formatDate(_dob!),
              style: TextStyle(color: _dob == null ? _secondary : _text),
            ),
          ),
        ),

        const SizedBox(height: 26),

        _PrimaryButton(
          label: 'Continue',
          loading: false,
          enabled: !_busy,
          onPressed: _continue,
        ),

        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Already have an account?',
              style: TextStyle(color: _secondary),
            ),
            TextButton(
              onPressed: _busy ? null : _openLogin,
              child: const Text('Login'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepTwo() {
    return Column(
      key: const ValueKey<String>('step2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(),
        const SizedBox(height: 28),
        _progress(),
        const SizedBox(height: 30),
        const Text(
          'Your Profile',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _text,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Profile & Cover Photos are optional',
          textAlign: TextAlign.center,
          style: TextStyle(color: _secondary),
        ),
        const SizedBox(height: 28),

        Center(child: _profileSelector()),

        const SizedBox(height: 28),

        _coverSelector(),

        const SizedBox(height: 28),

        _PrimaryButton(
          label: 'Create Account',
          loading: _loading,
          enabled: !_busy,
          onPressed: _createAccount,
        ),

        const SizedBox(height: 8),

        TextButton(
          onPressed: _busy ? null : _createAccount,
          child: const Text(
            'Skip for now',
            style: TextStyle(color: _blue, fontWeight: FontWeight.w700),
          ),
        ),

        if (_pickingMedia)
          const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _profileSelector() {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        InkWell(
          onTap: _busy ? null : _chooseProfilePhoto,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 70,
            backgroundColor: const Color(0xFFF1F5FB),
            backgroundImage: _profileBytes == null
                ? null
                : MemoryImage(_profileBytes!),
            child: _profileBytes == null
                ? const Icon(
                    Icons.person_rounded,
                    size: 70,
                    color: Color(0xFF9AA7B8),
                  )
                : null,
          ),
        ),
        Positioned(
          right: -5,
          bottom: 5,
          child: IconButton.filled(
            onPressed: _busy ? null : _chooseProfilePhoto,
            icon: const Icon(Icons.camera_alt),
          ),
        ),
        if (_profileBytes != null)
          Positioned(
            left: -5,
            bottom: 5,
            child: IconButton.filledTonal(
              onPressed: _busy
                  ? null
                  : () => setState(() => _profileBytes = null),
              icon: const Icon(Icons.close),
            ),
          ),
      ],
    );
  }

  Widget _coverSelector() {
    return AspectRatio(
      aspectRatio: 16 / 7,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          InkWell(
            onTap: _busy ? null : _chooseCoverPhoto,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6FC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
              ),
              child: _coverBytes == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.landscape_outlined, color: _blue, size: 42),
                        SizedBox(height: 6),
                        Text(
                          'Add Cover Photo',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    )
                  : Image.memory(_coverBytes!, fit: BoxFit.cover),
            ),
          ),
          if (_coverBytes != null)
            Positioned(
              left: 10,
              bottom: 10,
              child: IconButton.filledTonal(
                onPressed: _busy
                    ? null
                    : () => setState(() => _coverBytes = null),
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder makeBorder(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _blue),
      suffixIcon: suffix,
      filled: true,
      fillColor: _field,
      border: makeBorder(_border),
      enabledBorder: makeBorder(_border),
      focusedBorder: makeBorder(_blue, 1.5),
      disabledBorder: makeBorder(_border),
    );
  }
}

// ===============================================================
// PRIMARY BUTTON
// ===============================================================

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: <Color>[
              _CreateAccountScreenState._blueLight,
              _CreateAccountScreenState._blue,
            ],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled && !loading ? onPressed : null,
            borderRadius: BorderRadius.circular(18),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// END OF FILE
// ===============================================================
