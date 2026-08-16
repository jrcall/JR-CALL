// ===============================================================
// JR CALL
// File: profile_screen.dart
// Location: lib/screens/profile_screen.dart
// Fixes: BUG 02, BUG 03, BUG 05
// Production-safe replacement
// Existing APIs preserved
//
// PRODUCTION PROFILE CONTRACT:
// - Own profile uses Creator/Profile Studio presentation.
// - Public/contact profile remains available without login.
// - Resolved Firebase UID is used for full public-profile loading.
// - Guest public profile falls back safely to discovery/contact data.
// - Profile/Cover media use canonical ProfileService/StorageService.
// - Profile upload <= 5 MB to match current Storage rules.
// - Cover upload <= 10 MB to match current Storage rules.
// - Username/JR CALL ID uniqueness stays in ProfileService/FirestoreService.
// - Public fields never advertise credential autofill semantics.
// - No password/OTP data.
// - No fake followers/views/earnings.
// - No Call Engine/WebRTC ownership duplicated here.
// ===============================================================

import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/contact_model.dart';
import '../models/user_model.dart';
import '../services/profile_service.dart';
import '../utils/permissions.dart';
import '../widgets/caller_avatar.dart';
import 'create_account_screen.dart';
import 'login_screen.dart';
import '../services/firebase/firestore_service.dart' show UserProfileField;

typedef ProfileMediaPicker = Future<String?> Function();

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.contact,
    this.onPickProfilePhoto,
    this.onPickCoverPhoto,
    this.onVoiceCall,
    this.onVideoCall,
    this.onMessage,
    this.onBlockContact,
    this.onDeleteContact,
  });

  final ContactModel? contact;

  final ProfileMediaPicker? onPickProfilePhoto;
  final ProfileMediaPicker? onPickCoverPhoto;

  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onMessage;
  final VoidCallback? onBlockContact;
  final VoidCallback? onDeleteContact;

  bool get isContactProfile => contact != null;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // =============================================================
  // STORAGE-RULE MATCHED LIMITS
  // =============================================================

  static const int _profileMaxBytes = 5 * 1024 * 1024;
  static const int _coverMaxBytes = 10 * 1024 * 1024;

  // =============================================================
  // DESIGN
  // =============================================================

  static const double _maxContentWidth = 760;

  static const Color _background = Color(0xFFF7F9FD);
  static const Color _surface = Colors.white;

  static const Color _primary = Color(0xFF1769F5);
  static const Color _cyan = Color(0xFF03BDF5);
  static const Color _violet = Color(0xFF7C3AED);
  static const Color _success = Color(0xFF16A34A);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _error = Color(0xFFDC2626);

  static const Color _text = Color(0xFF111827);
  static const Color _secondary = Color(0xFF64748B);
  static const Color _border = Color(0xFFE5EAF2);

  // =============================================================
  // SERVICES
  // =============================================================

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ProfileService _profileService = ProfileService.instance;
  final ImagePicker _picker = ImagePicker();

  // =============================================================
  // OWN PROFILE STATE
  // =============================================================

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<UserModel?>? _profileSubscription;

  UserModel? _user;
  Object? _loadError;

  bool _loading = true;
  bool _saving = false;
  bool _pickingMedia = false;
  bool _initializing = false;

  String? _boundUid;
  int _loadGeneration = 0;

  // =============================================================
  // PUBLIC PROFILE STATE
  // =============================================================

  StreamSubscription<UserModel?>? _publicProfileSubscription;

  UserModel? _publicUser;
  bool _publicProfileLoading = false;

  // =============================================================
  // DERIVED
  // =============================================================

  User? get _firebaseUser => _auth.currentUser;

  bool get _authenticated => _firebaseUser != null;

  bool get _busy => _saving || _pickingMedia || _initializing;

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    if (widget.isContactProfile) {
      _loading = false;
      unawaited(_initializePublicProfile());
      return;
    }

    _authSubscription = _auth.userChanges().listen(
      (User? user) {
        unawaited(_handleAuthChange(user));
      },
      onError: (Object error, StackTrace stackTrace) {
        _reportError('Auth stream', error, stackTrace);
      },
    );

    unawaited(_initialize(force: true));
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.contact != widget.contact && widget.isContactProfile) {
      unawaited(_initializePublicProfile(force: true));
    }
  }

  @override
  void dispose() {
    _loadGeneration++;

    unawaited(_authSubscription?.cancel());
    unawaited(_profileSubscription?.cancel());
    unawaited(_publicProfileSubscription?.cancel());

    super.dispose();
  }

  // =============================================================
  // AUTH CHANGE
  // =============================================================

  Future<void> _handleAuthChange(User? firebaseUser) async {
    if (!mounted || widget.isContactProfile) return;

    final String? uid = _clean(firebaseUser?.uid);

    if (uid != null && uid == _boundUid && _profileSubscription != null) {
      return;
    }

    await _initialize(force: true);
  }

  // =============================================================
  // OWN PROFILE INITIALIZATION
  // =============================================================

  Future<void> _initialize({bool force = false}) async {
    if (widget.isContactProfile) return;

    if (_initializing && !force) return;

    final int generation = ++_loadGeneration;

    _initializing = true;

    try {
      await _profileSubscription?.cancel();
      _profileSubscription = null;
      _boundUid = null;

      final User? firebaseUser = _firebaseUser;

      if (firebaseUser == null) {
        if (!_validLoad(generation)) return;

        setState(() {
          _user = null;
          _loadError = null;
          _loading = false;
        });

        return;
      }

      final String uid = firebaseUser.uid.trim();

      if (uid.isEmpty) {
        throw StateError('Authenticated Firebase UID is invalid.');
      }

      if (_validLoad(generation)) {
        setState(() {
          _loading = true;
          _loadError = null;
        });
      }

      final UserModel profile = await _profileService.ensureCurrentProfile();

      if (!_validLoad(generation) || _firebaseUser?.uid != uid) {
        return;
      }

      if (profile.isDeleted) {
        throw StateError('This JR CALL profile is no longer available.');
      }

      _boundUid = uid;

      setState(() {
        _user = profile;
        _loading = false;
        _loadError = null;
      });

      _profileSubscription = _profileService
          .profileStream(uid)
          .listen(
            (UserModel? value) {
              if (!mounted || _firebaseUser?.uid != uid || value == null) {
                return;
              }

              if (value.isDeleted) {
                setState(() {
                  _user = null;
                  _loading = false;
                  _loadError = StateError(
                    'This JR CALL profile is no longer available.',
                  );
                });
                return;
              }

              setState(() {
                _user = value;
                _loading = false;
                _loadError = null;
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              _reportError('Own profile stream', error, stackTrace);

              if (!mounted || _firebaseUser?.uid != uid) {
                return;
              }

              setState(() {
                _loadError = error;
                _loading = false;
              });
            },
          );
    } catch (error, stackTrace) {
      _reportError('Own profile initialization', error, stackTrace);

      if (!_validLoad(generation)) return;

      setState(() {
        _loading = false;
        _loadError = error;
      });
    } finally {
      if (_validLoad(generation)) {
        _initializing = false;
      }
    }
  }

  bool _validLoad(int generation) {
    return mounted && generation == _loadGeneration;
  }

  // =============================================================
  // PUBLIC PROFILE INITIALIZATION
  // =============================================================

  Future<void> _initializePublicProfile({bool force = false}) async {
    final ContactModel? contact = widget.contact;

    if (contact == null || !mounted) return;

    await _publicProfileSubscription?.cancel();
    _publicProfileSubscription = null;

    final String? uid = _clean(contact.resolvedUid);

    // Current Firestore rules require authentication for users/{uid}.
    // Guest profile viewing therefore safely uses the public discovery
    // data already supplied in ContactModel without causing permission
    // errors.
    if (!_authenticated || uid == null) {
      if (mounted) {
        setState(() {
          _publicUser = null;
          _publicProfileLoading = false;
        });
      }
      return;
    }

    if (_publicProfileLoading && !force) return;

    setState(() {
      _publicProfileLoading = true;
    });

    try {
      final UserModel? profile = await _profileService.getProfile(uid);

      if (!mounted || widget.contact?.resolvedUid?.trim() != uid) {
        return;
      }

      if (profile != null && !profile.isDeleted) {
        setState(() {
          _publicUser = profile;
          _publicProfileLoading = false;
        });

        _publicProfileSubscription = _profileService
            .profileStream(uid)
            .listen(
              (UserModel? value) {
                if (!mounted ||
                    widget.contact?.resolvedUid?.trim() != uid ||
                    value == null ||
                    value.isDeleted) {
                  return;
                }

                setState(() {
                  _publicUser = value;
                });
              },
              onError: (Object error, StackTrace stackTrace) {
                _reportError('Public profile stream', error, stackTrace);
              },
            );
      } else {
        setState(() {
          _publicUser = null;
          _publicProfileLoading = false;
        });
      }
    } catch (error, stackTrace) {
      _reportError('Public profile load', error, stackTrace);

      if (mounted) {
        setState(() {
          _publicUser = null;
          _publicProfileLoading = false;
        });
      }
    }
  }

  // =============================================================
  // GUEST AUTH GATE
  // =============================================================

  Future<void> _openAuthentication() async {
    if (_authenticated || !mounted) return;

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
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x180F172A),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFD8E0EC),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Icon(
                Icons.account_circle_outlined,
                color: _primary,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'JR CALL Account Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _text,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Login or create an account to manage your profile, '
                'make calls, send messages and use private features.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _secondary, fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop('login');
                  },
                  child: const Text('LOG IN'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop('create');
                  },
                  child: const Text('CREATE ACCOUNT'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => choice == 'create'
            ? const CreateAccountScreen()
            : const LoginScreen(),
        settings: const RouteSettings(
          arguments: <String, dynamic>{
            'guestReturn': true,
            'requestedAction': 'profile',
          },
        ),
      ),
    );

    if (mounted) {
      await _initialize(force: true);
    }
  }

  // =============================================================
  // PUBLIC PROFILE TEXT EDITOR
  // =============================================================

  Future<void> _editText({
    required String title,
    required String value,
    required Future<void> Function(String value) onSave,
    int maxLength = 100,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
  }) async {
    if (_busy || !mounted) return;

    final TextEditingController controller = TextEditingController(text: value);

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            title,
            style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: keyboardType,
            textCapitalization: capitalization,
            textInputAction: maxLines > 1
                ? TextInputAction.newline
                : TextInputAction.done,
            maxLength: maxLength,
            maxLines: maxLines,
            autocorrect: maxLines > 1,
            enableSuggestions: maxLines > 1,

            // Important:
            // Full name / username / JR ID / bio are PUBLIC PROFILE
            // fields. They must not advertise credential autofill.
            autofillHints: const <String>[],

            decoration: InputDecoration(
              labelText: title,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onSubmitted: maxLines > 1
                ? null
                : (String text) {
                    Navigator.of(dialogContext).pop(text.trim());
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
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result != null) {
      await _performSave(() => onSave(result));
    }
  }

  // =============================================================
  // FIELD UPDATES
  // =============================================================

  Future<void> _updateName() async {
    final UserModel? user = _user;
    if (user == null) return;

    await _editText(
      title: 'Full Name',
      value: user.name,
      maxLength: 80,
      keyboardType: TextInputType.name,
      capitalization: TextCapitalization.words,
      onSave: (String value) async {
        final String normalized = value.trim();

        if (normalized.isEmpty) {
          await _profileService.clearProfileField(UserProfileField.name);
          return;
        }

        await _profileService.updateFullName(normalized);
      },
    );
  }

  Future<void> _updateUsername() async {
    final UserModel? user = _user;
    if (user == null) return;

    await _editText(
      title: 'Username',
      value: user.username ?? '',
      maxLength: 30,
      onSave: (String value) async {
        final String normalized = _normalizeUsername(value);

        if (normalized.isEmpty) {
          await _profileService.clearUsername();
          return;
        }

        if (!_validUsername(normalized)) {
          throw ArgumentError(
            'Username must contain 3-30 lowercase letters, '
            'numbers, dots or underscores.',
          );
        }

        await _profileService.updateUsername(normalized);
      },
    );
  }

  Future<void> _updateUserAddress() async {
    final UserModel? user = _user;
    if (user == null) return;

    await _editText(
      title: 'JR CALL User ID',
      value: user.userAddress ?? '',
      maxLength: 64,
      onSave: (String value) async {
        final String normalized = _normalizePublicId(value);

        if (!_validPublicId(normalized)) {
          throw ArgumentError(
            'JR CALL User ID must contain 3-64 lowercase letters, '
            'numbers, dots, underscores or hyphens.',
          );
        }

        await _profileService.updateJrCallUserId(normalized);
      },
    );
  }

  Future<void> _updateBio() async {
    final UserModel? user = _user;
    if (user == null) return;

    await _editText(
      title: 'Bio',
      value: user.bio ?? '',
      maxLength: 300,
      maxLines: 5,
      keyboardType: TextInputType.multiline,
      capitalization: TextCapitalization.sentences,
      onSave: (String value) async {
        final String normalized = value.trim();

        if (normalized.isEmpty) {
          await _profileService.clearBio();
          return;
        }

        await _profileService.updateBio(normalized);
      },
    );
  }

  Future<void> _updateCountry() async {
    final UserModel? user = _user;

    if (user == null || _busy || !mounted) return;

    showCountryPicker(
      context: context,
      showPhoneCode: true,
      useSafeArea: true,
      countryListTheme: CountryListThemeData(
        backgroundColor: _surface,
        bottomSheetHeight: 650,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        searchTextStyle: const TextStyle(color: _text),
        textStyle: const TextStyle(color: _text),
        inputDecoration: InputDecoration(
          labelText: 'Search Country',
          hintText: 'Country name or code',
          prefixIcon: const Icon(Icons.search_rounded, color: _primary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      onSelect: (Country country) {
        unawaited(
          _performSave(
            () => _profileService.updateCountry(
              country: country.name.trim(),
              countryCode: country.countryCode.trim().toUpperCase(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateDateOfBirth() async {
    final UserModel? user = _user;

    if (user == null || _busy || !mounted) return;

    final DateTime now = DateTime.now();
    final DateTime fallback = DateTime(now.year - 18, now.month, now.day);

    final DateTime current =
        user.dateOfBirth == null || user.dateOfBirth!.isAfter(now)
        ? fallback
        : user.dateOfBirth!;

    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (selected == null) return;

    await _performSave(
      () => _profileService.updateDateOfBirth(
        DateTime(selected.year, selected.month, selected.day),
      ),
    );
  }

  // =============================================================
  // MEDIA SOURCE
  // =============================================================

  Future<ImageSource?> _chooseProfileImageSource(UserModel user) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _surface,
      builder: (BuildContext sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_supportsCamera)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: _primary),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.of(sheetContext).pop(ImageSource.camera);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: _primary,
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.of(sheetContext).pop(ImageSource.gallery);
              },
            ),
            if (user.hasProfilePhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: _error),
                title: const Text(
                  'Remove Profile Photo',
                  style: TextStyle(color: _error),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_removeProfilePhoto());
                },
              ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Cancel'),
              onTap: () {
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // =============================================================
  // PROFILE PHOTO
  // =============================================================

  Future<void> _changeProfilePhoto() async {
    final UserModel? user = _user;

    if (user == null || _busy) return;

    final ProfileMediaPicker? external = widget.onPickProfilePhoto;

    if (external != null) {
      await _performSave(() async {
        final String? url = await external();

        if (_hasValue(url)) {
          await _profileService.updateProfile(profilePhotoUrl: url!.trim());
        }
      });
      return;
    }

    final ImageSource? source = await _chooseProfileImageSource(user);

    if (source == null || !mounted) return;

    await _pickAndUpload(user: user, source: source, profilePhoto: true);
  }

  // =============================================================
  // COVER PHOTO
  // =============================================================

  Future<void> _changeCoverPhoto() async {
    final UserModel? user = _user;

    if (user == null || _busy) return;

    final ProfileMediaPicker? external = widget.onPickCoverPhoto;

    if (external != null) {
      await _performSave(() async {
        final String? url = await external();

        if (_hasValue(url)) {
          await _profileService.updateProfile(coverPhotoUrl: url!.trim());
        }
      });
      return;
    }

    await _pickAndUpload(
      user: user,
      source: ImageSource.gallery,
      profilePhoto: false,
    );
  }

  // =============================================================
  // PICK / CROP / UPLOAD
  // =============================================================

  Future<void> _pickAndUpload({
    required UserModel user,
    required ImageSource source,
    required bool profilePhoto,
  }) async {
    if (_busy) return;

    _setPicking(true);

    try {
      _requireOwner(user.uid);

      final bool permissionGranted =
          await AppPermissions.requestProfileMediaPermission(
            sourceCamera: source == ImageSource.camera,
          );

      if (!permissionGranted) {
        _showMessage(
          source == ImageSource.camera
              ? 'Camera permission is required.'
              : 'Photo access is required.',
        );
        return;
      }

      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: profilePhoto ? 2400 : 3200,
        maxHeight: profilePhoto ? 2400 : 2200,
        requestFullMetadata: false,
      );

      if (picked == null) return;

      final Uint8List? bytes = await _cropImage(
        picked: picked,
        title: profilePhoto ? 'Crop Profile Photo' : 'Crop Cover Photo',
        ratio: profilePhoto
            ? const CropAspectRatio(ratioX: 1, ratioY: 1)
            : const CropAspectRatio(ratioX: 16, ratioY: 9),
        maxWidth: profilePhoto ? 1200 : 1920,
        maxHeight: profilePhoto ? 1200 : 1080,
      );

      if (bytes == null) return;

      _validateBytes(
        bytes,
        profilePhoto ? _profileMaxBytes : _coverMaxBytes,
        profilePhoto ? 'Profile photo' : 'Cover photo',
      );

      _requireOwner(user.uid);

      if (profilePhoto) {
        await _profileService.uploadProfilePhoto(
          bytes: bytes,
          contentType: 'image/jpeg',
        );
      } else {
        await _profileService.uploadCoverPhoto(
          bytes: bytes,
          contentType: 'image/jpeg',
        );
      }

      if (mounted) {
        _showMessage(
          profilePhoto ? 'Profile photo updated.' : 'Cover photo updated.',
        );
      }
    } on FirebaseException catch (error) {
      _showMessage(_firebaseError(error));
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? 'Invalid selected image.');
    } on StateError catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      _reportError('Profile media update', error, stackTrace);

      _showMessage('Selected image could not be updated.');
    } finally {
      _setPicking(false);
    }
  }

  Future<Uint8List?> _cropImage({
    required XFile picked,
    required String title,
    required CropAspectRatio ratio,
    required int maxWidth,
    required int maxHeight,
  }) async {
    if (!_supportsCropper) {
      return picked.readAsBytes();
    }

    final CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
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
          size: const CropperSize(width: 560, height: 560),
        ),
      ],
    );

    return cropped?.readAsBytes();
  }

  void _validateBytes(Uint8List bytes, int maximum, String label) {
    if (bytes.isEmpty) {
      throw ArgumentError('$label is empty.');
    }

    if (bytes.lengthInBytes > maximum) {
      throw ArgumentError(
        '$label must be '
        '${maximum ~/ (1024 * 1024)} MB or smaller.',
      );
    }
  }

  // =============================================================
  // REMOVE MEDIA
  // =============================================================

  Future<void> _removeProfilePhoto() async {
    final UserModel? user = _user;

    if (user == null || !user.hasProfilePhoto || _busy) {
      return;
    }

    final bool confirmed = await _confirm(
      title: 'Remove Profile Photo?',
      message: 'Your current profile photo will be removed.',
    );

    if (!confirmed) return;

    await _performSave(_profileService.deleteProfilePhoto);
  }

  Future<void> _removeCoverPhoto() async {
    final UserModel? user = _user;

    if (user == null || !user.hasCoverPhoto || _busy) {
      return;
    }

    final bool confirmed = await _confirm(
      title: 'Remove Cover Photo?',
      message: 'Your current cover photo will be removed.',
    );

    if (!confirmed) return;

    await _performSave(_profileService.deleteCoverPhoto);
  }

  // =============================================================
  // CLEAR FIELD
  // =============================================================

  Future<void> _clearField(UserProfileField field, String title) async {
    final UserModel? user = _user;

    if (user == null || _busy) return;

    final bool confirmed = await _confirm(
      title: 'Remove $title?',
      message: '$title will be removed from your profile.',
    );

    if (!confirmed) return;

    await _performSave(() async {
      switch (field) {
        case UserProfileField.username:
          await _profileService.clearUsername();
          break;

        case UserProfileField.userAddress:
          await _profileService.clearJrCallUserId();
          break;

        case UserProfileField.bio:
          await _profileService.clearBio();
          break;

        case UserProfileField.dateOfBirth:
          await _profileService.clearDateOfBirth();
          break;

        case UserProfileField.country:
        case UserProfileField.countryCode:
          await _profileService.clearCountry();
          break;

        default:
          await _profileService.clearProfileField(field);
      }
    });
  }

  // =============================================================
  // ACCOUNT INFORMATION
  // =============================================================

  Future<void> _showEmailInfo() async {
    final User? user = _firebaseUser;

    if (user == null) {
      _showMessage('No authenticated JR CALL user is available.');
      return;
    }

    final String? email = _clean(user.email);

    await _info(
      'Email',
      email == null
          ? 'No email is currently linked.\n\n'
                'Use Settings → Account & Security to add one.'
          : '${user.emailVerified ? 'Verified' : 'Verification pending'}'
                '\n\n$email\n\n'
                'Use Settings → Account & Security for email actions.',
    );
  }

  Future<void> _showPhoneInfo() async {
    final User? user = _firebaseUser;

    if (user == null) {
      _showMessage('No authenticated JR CALL user is available.');
      return;
    }

    final String? phone = _clean(user.phoneNumber);

    await _info(
      'Phone Number',
      phone == null
          ? 'No phone number is currently linked.\n\n'
                'Use Settings → Account & Security to add one.'
          : 'Firebase verified\n\n$phone\n\n'
                'Use Settings → Account & Security for phone actions.',
    );
  }

  Future<void> _showVerificationInfo() async {
    final User? user = _firebaseUser;

    if (user == null) {
      _showMessage('No authenticated JR CALL user is available.');
      return;
    }

    final List<String> lines = <String>[
      if (_hasValue(user.email))
        'Email: '
            '${user.emailVerified ? 'Verified' : 'Pending'}',
      if (_hasValue(user.phoneNumber)) 'Phone: Verified',
    ];

    if (lines.isEmpty) {
      lines.add('No email or phone verification information is available.');
    }

    await _info(
      'Verification',
      '${lines.join('\n')}\n\n'
          'Security actions are available in '
          'Settings → Account & Security.',
    );
  }

  Future<void> _showProviderInfo() async {
    final User? user = _firebaseUser;

    if (user == null) {
      _showMessage('No authenticated JR CALL user is available.');
      return;
    }

    final Set<String> providers = user.providerData
        .map((UserInfo provider) => provider.providerId.trim())
        .where((String id) => id.isNotEmpty)
        .map(_providerLabel)
        .toSet();

    await _info(
      'Sign-in Providers',
      providers.isEmpty
          ? 'No provider information is available.'
          : providers.join('\n'),
    );
  }

  Future<void> _info(String title, String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  // =============================================================
  // SAVE WRAPPER
  // =============================================================

  Future<void> _performSave(Future<void> Function() action) async {
    if (_busy || !mounted) return;

    setState(() {
      _saving = true;
    });

    try {
      final UserModel? user = _user;

      if (user != null) {
        _requireOwner(user.uid);
      }

      await action();

      if (mounted) {
        _showMessage('Profile updated successfully.');
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        _showMessage(_firebaseError(error));
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        _showMessage(
          error.message?.toString() ?? 'Invalid profile information.',
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (error, stackTrace) {
      _reportError('Profile update', error, stackTrace);

      if (mounted) {
        _showMessage('Unable to update profile.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // =============================================================
  // SECURITY / PLATFORM
  // =============================================================

  void _requireOwner(String uid) {
    final User? current = _firebaseUser;

    if (current == null) {
      throw StateError('Your authenticated session is no longer available.');
    }

    if (current.uid != uid) {
      throw StateError(
        'Authenticated Firebase user does not own this profile.',
      );
    }
  }

  bool get _supportsCropper {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _isMobile {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  bool get _supportsCamera => _isMobile;

  // =============================================================
  // CONTACT ACTION
  // =============================================================

  void _contactAction(VoidCallback? action, String unavailable) {
    if (action != null) {
      action();
      return;
    }

    _showMessage(unavailable);
  }

  // =============================================================
  // ROOT
  // =============================================================

  @override
  Widget build(BuildContext context) {
    if (widget.isContactProfile) {
      return _buildContactProfile();
    }

    if (!_authenticated) {
      return _buildGuestProfile();
    }

    return _buildCurrentProfile();
  }

  // =============================================================
  // GUEST OWN-PROFILE SCREEN
  // =============================================================

  Widget _buildGuestProfile() {
    return Scaffold(
      backgroundColor: _background,
      appBar: _simpleAppBar('My Profile'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _glassCard(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 94,
                      height: 94,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _primary.withValues(alpha: 0.08),
                      ),
                      child: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: _primary,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Create your JR CALL identity',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'You can explore JR CALL as a guest. '
                      'An account is required for your own profile, '
                      'calls, messages, uploads and private features.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _secondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _openAuthentication,
                        child: const Text('LOGIN / CREATE ACCOUNT'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // OWN PROFILE ROOT
  // =============================================================

  Widget _buildCurrentProfile() {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Profile Studio',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
        ],
      ),
      body: _buildCurrentBody(),
    );
  }

  Widget _buildCurrentBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null && _user == null) {
      return _buildLoadError();
    }

    final UserModel? user = _user;

    if (user == null) {
      return const Center(
        child: Text('Profile unavailable', style: TextStyle(color: _secondary)),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _initialize(force: true),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: <Widget>[
              _buildOwnerHero(user),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildStudioStats(),
                    const SizedBox(height: 16),
                    _buildAboutCard(user),
                    const SizedBox(height: 16),
                    _buildAccountCard(user),
                    const SizedBox(height: 16),
                    _buildStudioContentEmptyState(),
                    const SizedBox(height: 16),
                    _buildMediaActions(user),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =============================================================
  // OWNER HERO / CREATOR PROFILE
  // =============================================================

  Widget _buildOwnerHero(UserModel user) {
    final String displayName = _displayNameFromUser(user);

    final String? cover = _clean(user.coverPhoto);

    return Column(
      children: <Widget>[
        SizedBox(
          height: 250,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                bottom: 58,
                child: _coverSurface(coverUrl: cover),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _changeCoverPhoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(
                    user.hasCoverPhoto ? 'Change Cover' : 'Add Cover',
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: 0,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Color(0x220F172A),
                            blurRadius: 18,
                            offset: Offset(0, 7),
                          ),
                        ],
                      ),
                      child: CallerAvatar(
                        name: displayName,
                        imageUrl: user.photoUrl,
                        radius: 59,
                        isOnline: user.online,
                      ),
                    ),
                    Positioned(
                      right: -3,
                      bottom: 3,
                      child: Material(
                        color: _primary,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _busy ? null : _changeProfilePhoto,
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _text,
                              fontSize: 25,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (user.verified) ...<Widget>[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified_rounded,
                            color: _primary,
                            size: 20,
                          ),
                        ],
                      ],
                    ),
                    if (_hasValue(user.username))
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          '@${_normalizeUsername(user.username!)}',
                          style: const TextStyle(
                            color: _primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (_hasValue(user.userAddress))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'JR ID: '
                          '${user.userAddress!.trim()}',
                          style: const TextStyle(
                            color: _secondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_hasValue(user.bio))
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          user.bio!.trim(),
                          style: const TextStyle(
                            color: _secondary,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _updateName,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Edit Profile'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coverSurface({required String? coverUrl}) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: coverUrl == null
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFDCEAFF),
                    Color(0xFFECE7FF),
                    Color(0xFFE7FBFF),
                  ],
                )
              : null,
          image: coverUrl == null
              ? null
              : DecorationImage(
                  image: NetworkImage(coverUrl),
                  fit: BoxFit.cover,
                ),
        ),
        child: coverUrl == null
            ? const Center(
                child: Icon(
                  Icons.landscape_rounded,
                  size: 58,
                  color: Color(0x663B82F6),
                ),
              )
            : const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x05000000), Color(0x44000000)],
                  ),
                ),
              ),
      ),
    );
  }

  // =============================================================
  // CREATOR / STUDIO STATS
  // =============================================================

  Widget _buildStudioStats() {
    return _glassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.analytics_outlined, color: _violet, size: 21),
              SizedBox(width: 8),
              Text(
                'Creator Overview',
                style: TextStyle(
                  color: _text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: <Widget>[
              Expanded(
                child: _StudioMetric(
                  label: 'Followers',
                  value: '—',
                  icon: Icons.people_alt_outlined,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _StudioMetric(
                  label: 'Views',
                  value: '—',
                  icon: Icons.visibility_outlined,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _StudioMetric(
                  label: 'Content',
                  value: '—',
                  icon: Icons.play_circle_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Text(
            'Real creator statistics will appear here when '
            'JR CALL Creator analytics is connected.',
            style: TextStyle(color: _secondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // ABOUT / PUBLIC PROFILE CARD
  // =============================================================

  Widget _buildAboutCard(UserModel user) {
    return _glassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionHeader('Public Profile', Icons.public_rounded, _primary),
          _editableRow(
            icon: Icons.person_outline,
            title: 'Full Name',
            value: _display(user.name),
            onEdit: _updateName,
            onDelete: user.name.trim().isEmpty
                ? null
                : () => _clearField(UserProfileField.name, 'Full Name'),
          ),
          _editableRow(
            icon: Icons.alternate_email_rounded,
            title: 'Username',
            value: _display(
              user.username == null
                  ? null
                  : '@${_normalizeUsername(user.username!)}',
            ),
            onEdit: _updateUsername,
            onDelete: user.hasUsername
                ? () => _clearField(UserProfileField.username, 'Username')
                : null,
          ),
          _editableRow(
            icon: Icons.badge_outlined,
            title: 'JR CALL User ID',
            value: _display(user.userAddress),
            onEdit: _updateUserAddress,
          ),
          _editableRow(
            icon: Icons.notes_rounded,
            title: 'Bio',
            value: _display(user.bio),
            onEdit: _updateBio,
            onDelete: _hasValue(user.bio)
                ? () => _clearField(UserProfileField.bio, 'Bio')
                : null,
          ),
          _editableRow(
            icon: Icons.calendar_month_outlined,
            title: 'Date of Birth',
            value: user.dateOfBirth == null
                ? 'Not added'
                : _formatDate(user.dateOfBirth!),
            onEdit: _updateDateOfBirth,
            onDelete: user.dateOfBirth == null
                ? null
                : () => _clearField(
                    UserProfileField.dateOfBirth,
                    'Date of Birth',
                  ),
          ),
          _editableRow(
            icon: Icons.flag_outlined,
            title: 'Country',
            value: _country(user),
            onEdit: _updateCountry,
            onDelete: _hasValue(user.country) || _hasValue(user.countryCode)
                ? () => _clearField(UserProfileField.country, 'Country')
                : null,
          ),
        ],
      ),
    );
  }

  // =============================================================
  // ACCOUNT CARD
  // =============================================================

  Widget _buildAccountCard(UserModel user) {
    return _glassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionHeader('Account & Security', Icons.shield_outlined, _success),
          _informationRow(
            icon: Icons.email_outlined,
            title: 'Email',
            value: _display(_firebaseUser?.email ?? user.email),
            status: _firebaseUser?.email == null
                ? null
                : (_firebaseUser!.emailVerified ? 'Verified' : 'Pending'),
            onTap: _showEmailInfo,
          ),
          _informationRow(
            icon: Icons.phone_outlined,
            title: 'Phone Number',
            value: _display(_firebaseUser?.phoneNumber ?? user.phone),
            status: _hasValue(_firebaseUser?.phoneNumber ?? user.phone)
                ? 'Verified'
                : null,
            onTap: _showPhoneInfo,
          ),
          _informationRow(
            icon: Icons.verified_user_outlined,
            title: 'Verification',
            value: _verificationSummary(),
            onTap: _showVerificationInfo,
          ),
          _informationRow(
            icon: Icons.key_outlined,
            title: 'Sign-in Provider',
            value: _providerSummary(),
            onTap: _showProviderInfo,
          ),
        ],
      ),
    );
  }

  // =============================================================
  // CREATOR CONTENT EMPTY STATE
  // =============================================================

  Widget _buildStudioContentEmptyState() {
    return _glassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: <Widget>[
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: <Color>[
                  _primary.withValues(alpha: 0.12),
                  _violet.withValues(alpha: 0.10),
                ],
              ),
            ),
            child: const Icon(
              Icons.video_collection_outlined,
              color: _primary,
              size: 31,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Creator Content',
            style: TextStyle(
              color: _text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your real JR CALL posts, reels, videos, photos '
            'and documents will appear here when those production '
            'modules are connected.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _secondary, fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // MEDIA ACTIONS
  // =============================================================

  Widget _buildMediaActions(UserModel user) {
    return _glassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionHeader('Profile Media', Icons.photo_library_outlined, _cyan),
          _actionRow(
            icon: Icons.account_circle_outlined,
            title: user.hasProfilePhoto
                ? 'Change Profile Photo'
                : 'Add Profile Photo',
            color: _primary,
            onTap: _changeProfilePhoto,
          ),
          if (user.hasProfilePhoto)
            _actionRow(
              icon: Icons.delete_outline,
              title: 'Remove Profile Photo',
              color: _error,
              onTap: _removeProfilePhoto,
            ),
          _actionRow(
            icon: Icons.image_outlined,
            title: user.hasCoverPhoto
                ? 'Change Cover Photo'
                : 'Add Cover Photo',
            color: _cyan,
            onTap: _changeCoverPhoto,
          ),
          if (user.hasCoverPhoto)
            _actionRow(
              icon: Icons.delete_outline,
              title: 'Remove Cover Photo',
              color: _error,
              onTap: _removeCoverPhoto,
            ),
        ],
      ),
    );
  }

  // =============================================================
  // PUBLIC / DISCOVERED USER PROFILE
  // =============================================================

  Widget _buildContactProfile() {
    final ContactModel contact = widget.contact!;
    final UserModel? publicUser = _publicUser;

    final String displayName = _publicDisplayName(contact, publicUser);

    final String? photoUrl =
        _clean(publicUser?.photoUrl) ?? _clean(contact.photoUrl);

    final String? coverUrl = _clean(publicUser?.coverPhoto);

    final String? username =
        _clean(publicUser?.username) ?? _clean(contact.username);

    final String? jrCallId =
        _clean(publicUser?.userAddress) ?? _clean(contact.jrCallUserId);

    final String? bio = _clean(publicUser?.bio) ?? _clean(contact.bio);

    final String? country =
        _clean(publicUser?.country) ?? _clean(contact.country);

    final bool online = publicUser?.online ?? contact.isOnline;

    final bool verified = publicUser?.verified ?? contact.isVerified;

    return Scaffold(
      backgroundColor: _background,
      appBar: _simpleAppBar('Profile'),
      body: RefreshIndicator(
        onRefresh: () => _initializePublicProfile(force: true),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 36),
              children: <Widget>[
                _buildPublicHero(
                  name: displayName,
                  photoUrl: photoUrl,
                  coverUrl: coverUrl,
                  username: username,
                  jrCallId: jrCallId,
                  bio: bio,
                  online: online,
                  verified: verified,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: Column(
                    children: <Widget>[
                      _buildPublicActions(),
                      const SizedBox(height: 16),
                      _buildPublicAbout(
                        contact: contact,
                        publicUser: publicUser,
                        country: country,
                      ),
                      if (_publicProfileLoading) ...<Widget>[
                        const SizedBox(height: 14),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPublicHero({
    required String name,
    required String? photoUrl,
    required String? coverUrl,
    required String? username,
    required String? jrCallId,
    required String? bio,
    required bool online,
    required bool verified,
  }) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 230,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                bottom: 58,
                child: _coverSurface(coverUrl: coverUrl),
              ),
              Positioned(
                left: 20,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(0x220F172A),
                        blurRadius: 18,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: CallerAvatar(
                    name: name,
                    imageUrl: photoUrl,
                    radius: 58,
                    isOnline: online,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 7, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 25,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (verified) ...<Widget>[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified_rounded,
                      color: _primary,
                      size: 20,
                    ),
                  ],
                ],
              ),
              if (_hasValue(username))
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '@${_normalizeUsername(username!)}',
                    style: const TextStyle(
                      color: _primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (_hasValue(jrCallId))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'JR ID: ${jrCallId!.trim()}',
                    style: const TextStyle(
                      color: _secondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (_hasValue(bio))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    bio!.trim(),
                    style: const TextStyle(
                      color: _secondary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPublicActions() {
    return _glassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _PublicActionButton(
              icon: Icons.call_rounded,
              label: 'Voice',
              color: _success,
              onTap: () => _contactAction(
                widget.onVoiceCall,
                'Voice call action is not available.',
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _PublicActionButton(
              icon: Icons.videocam_rounded,
              label: 'Video',
              color: _primary,
              onTap: () => _contactAction(
                widget.onVideoCall,
                'Video call action is not available.',
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _PublicActionButton(
              icon: Icons.message_rounded,
              label: 'Message',
              color: _violet,
              onTap: () => _contactAction(
                widget.onMessage,
                'Message action is not available.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicAbout({
    required ContactModel contact,
    required UserModel? publicUser,
    required String? country,
  }) {
    final List<Widget> rows = <Widget>[];

    final String? username =
        _clean(publicUser?.username) ?? _clean(contact.username);

    final String? jrCallId =
        _clean(publicUser?.userAddress) ?? _clean(contact.jrCallUserId);

    final String? bio = _clean(publicUser?.bio) ?? _clean(contact.bio);

    final String? email = _clean(contact.email);

    final String? phone = _clean(contact.phoneNumber);

    void addRow(IconData icon, String title, String value) {
      rows.add(_readOnlyRow(icon: icon, title: title, value: value));
    }

    if (username != null) {
      addRow(
        Icons.alternate_email_rounded,
        'Username',
        '@${_normalizeUsername(username)}',
      );
    }

    if (jrCallId != null) {
      addRow(Icons.badge_outlined, 'JR CALL User ID', jrCallId);
    }

    if (bio != null) {
      addRow(Icons.notes_rounded, 'Bio', bio);
    }

    if (country != null) {
      addRow(Icons.public_rounded, 'Country', country);
    }

    // ContactModel receives email/phone only when discovery exposed them.
    // This screen does not independently reveal private auth data.
    if (email != null) {
      addRow(Icons.email_outlined, 'Email', email);
    }

    if (phone != null) {
      addRow(Icons.phone_outlined, 'Phone', phone);
    }

    if (rows.isEmpty) {
      rows.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(6, 8, 6, 14),
          child: Text(
            'No additional public profile information is available.',
            style: TextStyle(color: _secondary, height: 1.45),
          ),
        ),
      );
    }

    return _glassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionHeader(
            'Public Information',
            Icons.person_search_outlined,
            _primary,
          ),
          ...rows,
          if (widget.onBlockContact != null ||
              widget.onDeleteContact != null) ...<Widget>[
            const Divider(height: 24),
            if (widget.onBlockContact != null)
              _actionRow(
                icon: Icons.block_rounded,
                title: 'Block Contact',
                color: _error,
                onTap: widget.onBlockContact!,
              ),
            if (widget.onDeleteContact != null)
              _actionRow(
                icon: Icons.delete_outline,
                title: 'Delete Contact',
                color: _error,
                onTap: widget.onDeleteContact!,
              ),
          ],
        ],
      ),
    );
  }

  // =============================================================
  // COMMON UI
  // =============================================================

  PreferredSizeWidget _simpleAppBar(String title) {
    return AppBar(
      backgroundColor: _background,
      foregroundColor: _text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 24,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          _iconBubble(icon, color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onEdit,
    VoidCallback? onDelete,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: _iconBubble(icon, _primary),
      title: _tileTitle(title),
      subtitle: _tileValue(value),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onDelete != null)
            IconButton(
              tooltip: 'Remove',
              onPressed: _busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline, color: _error),
            ),
          IconButton(
            tooltip: 'Edit',
            onPressed: _busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, color: _primary),
          ),
        ],
      ),
    );
  }

  Widget _informationRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    String? status,
  }) {
    return ListTile(
      onTap: _busy ? null : onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: _iconBubble(icon, const Color(0xFF475569)),
      title: _tileTitle(title),
      subtitle: _tileValue(value),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (status != null) ...<Widget>[
            Text(
              status,
              style: TextStyle(
                color: status == 'Verified' ? _success : _warning,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
          ],
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }

  Widget _readOnlyRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: _iconBubble(icon, _primary),
      title: _tileTitle(title),
      subtitle: _tileValue(value),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      leading: _iconBubble(icon, color),
      title: _tileTitle(title),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF94A3B8),
      ),
      onTap: _busy ? null : onTap,
    );
  }

  Widget _tileTitle(String title) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
    );
  }

  Widget _tileValue(String value) {
    return Text(
      value,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: _secondary, height: 1.35),
    );
  }

  Widget _iconBubble(IconData icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.09),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }

  // =============================================================
  // LOAD ERROR
  // =============================================================

  Widget _buildLoadError() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, size: 54, color: _error),
            const SizedBox(height: 16),
            const Text(
              'Unable to load profile',
              style: TextStyle(
                color: _text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _friendlyError(_loadError!),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _secondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                unawaited(_initialize(force: true));
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // HELPERS
  // =============================================================

  void _setPicking(bool value) {
    if (!mounted || _pickingMedia == value) {
      return;
    }

    setState(() {
      _pickingMedia = value;
    });
  }

  String _display(String? value) {
    return _clean(value) ?? 'Not added';
  }

  String? _clean(String? value) {
    final String normalized = value?.trim() ?? '';

    return normalized.isEmpty ? null : normalized;
  }

  bool _hasValue(String? value) {
    return _clean(value) != null;
  }

  String _normalizeUsername(String value) {
    String normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized.trim();
  }

  String _normalizePublicId(String value) {
    String normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized.trim();
  }

  bool _validUsername(String value) {
    return RegExp(r'^[a-z0-9._]{3,30}$').hasMatch(value) &&
        !value.startsWith('.') &&
        !value.endsWith('.') &&
        !value.contains('..');
  }

  bool _validPublicId(String value) {
    return RegExp(r'^[a-z0-9._-]{3,64}$').hasMatch(value);
  }

  String _formatDate(DateTime date) {
    final String day = date.day.toString().padLeft(2, '0');

    final String month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  String _country(UserModel user) {
    final String? country = _clean(user.country);

    final String? code = _clean(user.countryCode);

    if (country == null && code == null) {
      return 'Not added';
    }

    if (country != null && code != null) {
      return '$country ($code)';
    }

    return country ?? code!;
  }

  String _displayNameFromUser(UserModel user) {
    return _clean(user.name) ??
        _clean(user.username) ??
        _clean(user.userAddress) ??
        'JR CALL User';
  }

  String _publicDisplayName(ContactModel contact, UserModel? publicUser) {
    return _clean(publicUser?.name) ??
        _clean(contact.displayName) ??
        'JR CALL User';
  }

  String _verificationSummary() {
    final User? user = _firebaseUser;

    if (user == null) {
      return 'Not available';
    }

    final bool hasEmail = _hasValue(user.email);

    final bool hasPhone = _hasValue(user.phoneNumber);

    if (hasEmail && user.emailVerified && hasPhone) {
      return 'Email and Phone verified';
    }

    if (hasEmail && user.emailVerified) {
      return 'Email verified';
    }

    if (hasPhone) {
      return hasEmail ? 'Phone verified • Email pending' : 'Phone verified';
    }

    if (hasEmail) {
      return 'Email verification pending';
    }

    return 'No verified identity';
  }

  String _providerSummary() {
    final User? user = _firebaseUser;

    if (user == null || user.providerData.isEmpty) {
      return 'Not available';
    }

    final Set<String> providers = user.providerData
        .map((UserInfo provider) => _providerLabel(provider.providerId))
        .toSet();

    return providers.join(', ');
  }

  String _providerLabel(String providerId) {
    switch (providerId.trim()) {
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
        return providerId;
    }
  }

  String _friendlyError(Object error) {
    if (error is FirebaseException) {
      return _firebaseError(error);
    }

    if (error is StateError) {
      return error.message;
    }

    return 'JR CALL could not load your profile. '
        'Please try again.';
  }

  String _firebaseError(FirebaseException error) {
    switch (error.code) {
      case 'unauthorized':
      case 'permission-denied':
      case 'storage/unauthorized':
        return 'Permission denied while accessing this account.';

      case 'canceled':
      case 'storage/canceled':
        return 'Upload was cancelled.';

      case 'retry-limit-exceeded':
      case 'storage/retry-limit-exceeded':
        return 'Upload failed because of network problems.';

      case 'quota-exceeded':
      case 'storage/quota-exceeded':
        return 'Firebase Storage quota has been exceeded.';

      case 'object-not-found':
      case 'storage/object-not-found':
        return 'The requested Storage object was not found.';

      case 'network-request-failed':
      case 'unavailable':
        return 'Firebase service is temporarily unavailable.';

      default:
        return error.message ?? 'Firebase operation failed.';
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
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
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _error),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint(
      'JR CALL [ProfileScreen/$source] '
      'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [ProfileScreen/$source]',
        stackTrace: stackTrace,
      );
    }
  }
}

// ===============================================================
// STUDIO METRIC
// ===============================================================

class _StudioMetric extends StatelessWidget {
  const _StudioMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 20, color: const Color(0xFF1769F5)),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// PUBLIC PROFILE ACTION
// ===============================================================

class _PublicActionButton extends StatelessWidget {
  const _PublicActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 70),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              color: color.withValues(alpha: 0.08),
              border: Border.all(color: color.withValues(alpha: 0.16)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
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

// ===============================================================
// END OF FILE
//
// FIXED: BUG 02, BUG 03, BUG 05
// STATUS: READY FOR FORMAT + ANALYZE
//
// NEXT FILE: call_history_provider.dart
// Location: lib/providers/call_history_provider.dart
// ===============================================================
