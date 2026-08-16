// ===============================================================
// JR CALL
// File: create_profile_setup_screen.dart
// Location: lib/screens/create_profile_setup_screen.dart
// Master Step: 19
//
// PURPOSE:
// Canonical optional profile-personalization step after successful
// JR CALL account verification.
//
// DESIGN:
// - Premium light / glass JR CALL visual style.
// - Step indicator: Step 1 completed -> Step 2 active.
// - Profile Photo (Optional).
// - Cover Photo (Optional).
// - FINISH.
// - Skip for now.
//
// ARCHITECTURE:
//
// UI
//  ↓
// CreateProfileSetupScreen
//  ↓
// ProfileService
//   ├── AuthService
//   ├── FirestoreService
//   └── StorageService
//
// IMPORTANT:
// - This screen does NOT directly write Firebase Storage.
// - This screen does NOT directly write Firestore.
// - ProfileService remains the coordinator.
// - StorageService remains binary-media owner.
// - FirestoreService remains profile-data owner.
// - Passwords and OTP values are NEVER stored here.
// - Media is optional.
// - Skip never invalidates a verified account.
// - Final authenticated routing remains owned by SessionGate.
// ===============================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme/jr_colors.dart';
import '../services/profile_service.dart';
import '../utils/permissions.dart';

class CreateProfileSetupScreen extends StatefulWidget {
  const CreateProfileSetupScreen({
    super.key,
    this.initialProfilePhotoBytes,
    this.initialCoverPhotoBytes,
  });

  /// Backward-compatible optional media.
  final Uint8List? initialProfilePhotoBytes;
  final Uint8List? initialCoverPhotoBytes;

  @override
  State<CreateProfileSetupScreen> createState() =>
      _CreateProfileSetupScreenState();
}

class _CreateProfileSetupScreenState extends State<CreateProfileSetupScreen> {
  // =============================================================
  // SERVICES
  // =============================================================

  final ProfileService _profileService = ProfileService.instance;

  final ImagePicker _imagePicker = ImagePicker();

  // =============================================================
  // MEDIA LIMITS
  //
  // These are deliberately conservative.
  //
  // Final authoritative limits also remain enforced by:
  // - StorageService
  // - Firebase Storage Rules
  // =============================================================

  static const int _maximumProfileImageBytes = 5 * 1024 * 1024;

  static const int _maximumCoverImageBytes = 10 * 1024 * 1024;

  // =============================================================
  // STATE
  // =============================================================

  Uint8List? _profilePhotoBytes;

  Uint8List? _coverPhotoBytes;

  bool _loading = false;

  bool _pickingMedia = false;

  bool _completed = false;

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _profilePhotoBytes = widget.initialProfilePhotoBytes;

    _coverPhotoBytes = widget.initialCoverPhotoBytes;
  }

  // =============================================================
  // PROFILE PHOTO SOURCE
  // =============================================================

  Future<void> _chooseProfilePhoto() async {
    if (_actionBusy) {
      return;
    }

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      backgroundColor: JrColors.surface,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: Text(
                    'Profile Photo',
                    style: TextStyle(
                      color: JrColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

                if (_supportsDirectCamera)
                  ListTile(
                    leading: const Icon(
                      Icons.camera_alt_outlined,
                      color: JrColors.primaryBlue,
                    ),
                    title: const Text(
                      'Take Photo',
                      style: TextStyle(
                        color: JrColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop(ImageSource.camera);
                    },
                  ),

                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: JrColors.primaryBlue,
                  ),
                  title: const Text(
                    'Choose from Gallery',
                    style: TextStyle(
                      color: JrColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop(ImageSource.gallery);
                  },
                ),

                if (_profilePhotoBytes != null)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: JrColors.error,
                    ),
                    title: const Text(
                      'Remove Selected Photo',
                      style: TextStyle(
                        color: JrColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();

                      if (!mounted) {
                        return;
                      }

                      setState(() {
                        _profilePhotoBytes = null;
                      });
                    },
                  ),

                ListTile(
                  leading: const Icon(
                    Icons.close_rounded,
                    color: JrColors.textSecondary,
                  ),
                  title: const Text(
                    'Cancel',
                    style: TextStyle(color: JrColors.textSecondary),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null || !mounted) {
      return;
    }

    await _pickProfilePhoto(source);
  }

  // =============================================================
  // PROFILE PHOTO PICK + CROP
  // =============================================================

  Future<void> _pickProfilePhoto(ImageSource source) async {
    if (_actionBusy) {
      return;
    }

    _setPickingMedia(true);

    try {
      if (source == ImageSource.camera && _isAndroidOrIOS) {
        final bool granted = await AppPermissions.requestCamera();

        if (!granted) {
          _showMessage(
            'Camera permission is required to take a profile photo.',
          );

          return;
        }
      }

      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2400,
        maxHeight: 2400,
        requestFullMetadata: false,
      );

      if (picked == null) {
        return;
      }

      final Uint8List? bytes = await _cropOrReadImage(
        picked: picked,
        title: 'Crop Profile Photo',
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (bytes == null) {
        return;
      }

      _validateProfileImage(bytes);

      if (!mounted) {
        return;
      }

      setState(() {
        _profilePhotoBytes = bytes;
      });
    } on ArgumentError catch (error) {
      _showMessage(
        error.message?.toString() ?? 'The selected image is invalid.',
      );
    } on StateError catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      debugPrint('JR CALL profile photo selection error: $error');

      debugPrintStack(label: 'JR CALL profile photo', stackTrace: stackTrace);

      _showMessage(
        'The profile photo could not be prepared. Please try again.',
      );
    } finally {
      _setPickingMedia(false);
    }
  }

  // =============================================================
  // COVER PHOTO
  // =============================================================

  Future<void> _chooseCoverPhoto() async {
    if (_actionBusy) {
      return;
    }

    _setPickingMedia(true);

    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
        maxWidth: 3200,
        maxHeight: 2000,
        requestFullMetadata: false,
      );

      if (picked == null) {
        return;
      }

      final Uint8List? bytes = await _cropOrReadImage(
        picked: picked,
        title: 'Crop Cover Photo',
        aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (bytes == null) {
        return;
      }

      _validateCoverImage(bytes);

      if (!mounted) {
        return;
      }

      setState(() {
        _coverPhotoBytes = bytes;
      });
    } on ArgumentError catch (error) {
      _showMessage(
        error.message?.toString() ?? 'The selected image is invalid.',
      );
    } on StateError catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      debugPrint('JR CALL cover photo selection error: $error');

      debugPrintStack(label: 'JR CALL cover photo', stackTrace: stackTrace);

      _showMessage('The cover photo could not be prepared. Please try again.');
    } finally {
      _setPickingMedia(false);
    }
  }

  // =============================================================
  // IMAGE CROPPER
  // =============================================================

  Future<Uint8List?> _cropOrReadImage({
    required XFile picked,
    required String title,
    required CropAspectRatio aspectRatio,
    required int maxWidth,
    required int maxHeight,
  }) async {
    if (!_supportsImageCropper) {
      return picked.readAsBytes();
    }

    final CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: aspectRatio,
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

    if (cropped == null) {
      return null;
    }

    return cropped.readAsBytes();
  }

  // =============================================================
  // FINISH
  // =============================================================

  Future<void> _finishProfileSetup() async {
    if (_actionBusy) {
      return;
    }

    if (!_profileService.hasAuthenticatedUser) {
      _showMessage(
        'Your authenticated session is no longer available. '
        'Please Login again.',
      );

      return;
    }

    final Uint8List? profileBytes = _profilePhotoBytes;

    final Uint8List? coverBytes = _coverPhotoBytes;

    if (profileBytes == null && coverBytes == null) {
      _completeSetup();
      return;
    }

    _setLoading(true);

    try {
      if (profileBytes != null) {
        _validateProfileImage(profileBytes);

        await _profileService.uploadProfilePhoto(
          bytes: profileBytes,
          contentType: 'image/jpeg',
        );
      }

      if (coverBytes != null) {
        _validateCoverImage(coverBytes);

        await _profileService.uploadCoverPhoto(
          bytes: coverBytes,
          contentType: 'image/jpeg',
        );
      }

      if (!mounted) {
        return;
      }

      _completeSetup();
    } on ArgumentError catch (error) {
      _showMessage(
        error.message?.toString() ?? 'The selected media is invalid.',
      );
    } on StateError catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      debugPrint('JR CALL profile setup completion error: $error');

      debugPrintStack(label: 'JR CALL profile setup', stackTrace: stackTrace);

      _showMessage('Profile setup could not be completed. Please try again.');
    } finally {
      if (mounted && !_completed) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // SKIP
  // =============================================================

  void _skipForNow() {
    if (_actionBusy) {
      return;
    }

    if (!_profileService.hasAuthenticatedUser) {
      _showMessage(
        'Your authenticated session is no longer available. '
        'Please Login again.',
      );

      return;
    }

    _completeSetup();
  }

  // =============================================================
  // COMPLETE
  // =============================================================

  void _completeSetup() {
    if (!mounted || _completed) {
      return;
    }

    _completed = true;

    FocusScope.of(context).unfocus();

    // SessionGate is the only owner of the final authenticated
    // destination. Returning to the root allows it to resolve
    // HomeScreen from the latest Firebase/Firestore state.
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  // =============================================================
  // IMAGE VALIDATION
  // =============================================================

  void _validateProfileImage(Uint8List bytes) {
    _validateImageBytes(
      bytes: bytes,
      maximumBytes: _maximumProfileImageBytes,
      mediaName: 'Profile photo',
    );
  }

  void _validateCoverImage(Uint8List bytes) {
    _validateImageBytes(
      bytes: bytes,
      maximumBytes: _maximumCoverImageBytes,
      mediaName: 'Cover photo',
    );
  }

  void _validateImageBytes({
    required Uint8List bytes,
    required int maximumBytes,
    required String mediaName,
  }) {
    if (bytes.isEmpty) {
      throw ArgumentError('$mediaName image data cannot be empty.');
    }

    if (bytes.lengthInBytes > maximumBytes) {
      final int maximumMb = maximumBytes ~/ (1024 * 1024);

      throw ArgumentError('$mediaName must be $maximumMb MB or smaller.');
    }
  }

  // =============================================================
  // PLATFORM SUPPORT
  // =============================================================

  bool get _supportsImageCropper {
    if (kIsWeb) {
      return true;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _isAndroidOrIOS {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _supportsDirectCamera => _isAndroidOrIOS;

  // =============================================================
  // STATE HELPERS
  // =============================================================

  bool get _actionBusy {
    return _loading || _pickingMedia || _completed;
  }

  void _setLoading(bool value) {
    if (!mounted || _loading == value) {
      return;
    }

    setState(() {
      _loading = value;
    });
  }

  void _setPickingMedia(bool value) {
    if (!mounted || _pickingMedia == value) {
      return;
    }

    setState(() {
      _pickingMedia = value;
    });
  }

  void _removeProfilePhoto() {
    if (_actionBusy || _profilePhotoBytes == null) {
      return;
    }

    setState(() {
      _profilePhotoBytes = null;
    });
  }

  void _removeCoverPhoto() {
    if (_actionBusy || _coverPhotoBytes == null) {
      return;
    }

    setState(() {
      _coverPhotoBytes = null;
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // =============================================================
  // STEP INDICATOR
  // =============================================================

  Widget _buildStepIndicator() {
    return Row(
      children: <Widget>[
        _buildStepCircle(number: '1', active: false, completed: true),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: JrColors.primaryBlue.withValues(alpha: 0.24),
            ),
          ),
        ),
        _buildStepCircle(number: '2', active: true, completed: false),
      ],
    );
  }

  Widget _buildStepCircle({
    required String number,
    required bool active,
    required bool completed,
  }) {
    final bool highlighted = active || completed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: highlighted ? JrColors.primaryBlue : JrColors.surface,
        border: Border.all(
          color: highlighted ? JrColors.primaryBlue : JrColors.border,
        ),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(
                  color: JrColors.primaryBlue.withValues(alpha: 0.20),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: completed
          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
          : Text(
              number,
              style: TextStyle(
                color: active ? Colors.white : JrColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }

  // =============================================================
  // BRAND HEADER
  // =============================================================

  Widget _buildBrandHeader() {
    return Row(
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: JrColors.surface,
            borderRadius: BorderRadius.circular(15),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: JrColors.primaryBlue.withValues(alpha: 0.13),
                blurRadius: 18,
                offset: const Offset(0, 6),
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
                    return Container(
                      color: JrColors.primaryBlue.withValues(alpha: 0.08),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.phone_in_talk_rounded,
                        color: JrColors.primaryBlue,
                        size: 28,
                      ),
                    );
                  },
            ),
          ),
        ),
        const SizedBox(width: 13),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'JR CALL',
                style: TextStyle(
                  color: JrColors.textPrimary,
                  fontSize: 22,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Premium Calling Experience',
                style: TextStyle(
                  color: JrColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =============================================================
  // PROFILE PHOTO UI
  // =============================================================

  Widget _buildProfilePhoto() {
    return Column(
      children: <Widget>[
        const Text(
          'Profile Photo (Optional)',
          style: TextStyle(
            color: JrColors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _actionBusy ? null : _chooseProfilePhoto,
                child: Container(
                  width: 132,
                  height: 132,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: JrColors.surface,
                    border: Border.all(color: JrColors.primaryBlue, width: 2.2),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: JrColors.primaryBlue.withValues(alpha: 0.17),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _profilePhotoBytes == null
                        ? Container(
                            color: JrColors.primaryBlue.withValues(alpha: 0.05),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 66,
                              color: JrColors.textSecondary,
                            ),
                          )
                        : Image.memory(
                            _profilePhotoBytes!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
              ),
            ),

            Positioned(
              right: -4,
              bottom: 5,
              child: Material(
                color: JrColors.surface,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _actionBusy ? null : _chooseProfilePhoto,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.camera_alt_rounded,
                      size: 22,
                      color: JrColors.primaryBlue,
                    ),
                  ),
                ),
              ),
            ),

            if (_profilePhotoBytes != null)
              Positioned(
                left: -3,
                bottom: 5,
                child: Material(
                  color: JrColors.surface,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _actionBusy ? null : _removeProfilePhoto,
                    child: const SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(
                        Icons.close_rounded,
                        size: 19,
                        color: JrColors.error,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // =============================================================
  // COVER PHOTO UI
  // =============================================================

  Widget _buildCoverPhoto() {
    return Column(
      children: <Widget>[
        const Text(
          'Cover Photo (Optional)',
          style: TextStyle(
            color: JrColors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        AspectRatio(
          aspectRatio: 16 / 7.7,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _actionBusy ? null : _chooseCoverPhoto,
                  child: Container(
                    decoration: BoxDecoration(
                      color: JrColors.primaryBlue.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: JrColors.border),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.045),
                          blurRadius: 20,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: _coverPhotoBytes != null
                        ? Image.memory(
                            _coverPhotoBytes!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: JrColors.surface,
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: JrColors.primaryBlue.withValues(
                                          alpha: 0.10,
                                        ),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 28,
                                    color: JrColors.primaryBlue,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Add Cover Photo',
                                  style: TextStyle(
                                    color: JrColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),

              Positioned(
                right: 12,
                bottom: 12,
                child: Material(
                  color: JrColors.surface,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _actionBusy ? null : _chooseCoverPhoto,
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 22,
                        color: JrColors.primaryBlue,
                      ),
                    ),
                  ),
                ),
              ),

              if (_coverPhotoBytes != null)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Material(
                    color: JrColors.surface,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _actionBusy ? null : _removeCoverPhoto,
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(
                          Icons.close_rounded,
                          size: 21,
                          color: JrColors.error,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // =============================================================
  // FINISH BUTTON
  // =============================================================

  Widget _buildFinishButton() {
    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: _actionBusy
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xFF4194FF), JrColors.primaryBlue],
              ),
        color: _actionBusy ? JrColors.disabled : null,
        boxShadow: _actionBusy
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: JrColors.primaryBlue.withValues(alpha: 0.20),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _actionBusy ? null : _finishProfileSetup,
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'FINISH',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_loading && !_pickingMedia,
      child: Scaffold(
        backgroundColor: JrColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
                  decoration: BoxDecoration(
                    color: JrColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: JrColors.border),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.045),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: JrColors.primaryBlue.withValues(alpha: 0.025),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Material(
                            color: JrColors.surface,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _actionBusy
                                  ? null
                                  : () {
                                      Navigator.of(context).maybePop();
                                    },
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: JrColors.border),
                                ),
                                child: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: JrColors.textPrimary,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 14),

                          Expanded(child: _buildBrandHeader()),
                        ],
                      ),

                      const SizedBox(height: 32),

                      _buildStepIndicator(),

                      const SizedBox(height: 30),

                      const Text(
                        'Your Profile',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: JrColors.textPrimary,
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        'Add profile & cover photos to personalize '
                        'your account (Optional)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: JrColors.textSecondary,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 32),

                      _buildProfilePhoto(),

                      const SizedBox(height: 34),

                      _buildCoverPhoto(),

                      const SizedBox(height: 34),

                      _buildFinishButton(),

                      const SizedBox(height: 10),

                      TextButton(
                        onPressed: _actionBusy ? null : _skipForNow,
                        style: TextButton.styleFrom(
                          foregroundColor: JrColors.primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Skip for now',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),

                      if (_pickingMedia) ...<Widget>[
                        const SizedBox(height: 10),
                        const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        ),
                      ],
                    ],
                  ),
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
