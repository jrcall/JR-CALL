import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// ===========================================================
/// JR CALL
/// File: storage_service.dart
/// Location: lib/services/firebase/storage_service.dart
///
/// Description:
/// Canonical Firebase Storage repository for JR CALL profile media.
///
/// Responsibilities:
/// - Upload profile photos
/// - Upload cover photos
/// - Return Firebase Storage download URLs
/// - Replace existing profile/cover media safely
/// - Delete owned profile/cover media
/// - Keep Storage paths centralized and predictable
///
/// Ownership:
/// - Firebase Authentication -> AuthService
/// - Firestore profile data -> FirestoreService
/// - Binary profile/cover media -> StorageService
///
/// IMPORTANT:
/// - Passwords are NEVER stored here.
/// - OTP values are NEVER stored here.
/// - This service does NOT update Firestore profile fields.
/// - Firebase Storage rules remain the final authorization layer.
/// ===========================================================

class StorageService {
  // ===========================================================
  // Singleton
  // ===========================================================

  StorageService._();

  static final StorageService instance = StorageService._();

  // ===========================================================
  // Firebase Storage
  // ===========================================================

  final FirebaseStorage _storage = FirebaseStorage.instance;

  FirebaseStorage get storage => _storage;

  // ===========================================================
  // Limits
  // ===========================================================

  static const int maxProfilePhotoBytes = 8 * 1024 * 1024;

  static const int maxCoverPhotoBytes = 12 * 1024 * 1024;

  // ===========================================================
  // Canonical Storage Paths
  // ===========================================================

  static String profilePhotoPath(String uid) {
    final String normalizedUid = _normalizeUid(uid);

    return 'users/$normalizedUid/profile/profile.jpg';
  }

  static String coverPhotoPath(String uid) {
    final String normalizedUid = _normalizeUid(uid);

    return 'users/$normalizedUid/cover/cover.jpg';
  }

  // ===========================================================
  // References
  // ===========================================================

  Reference profilePhotoReference(String uid) {
    return _storage.ref(profilePhotoPath(uid));
  }

  Reference coverPhotoReference(String uid) {
    return _storage.ref(coverPhotoPath(uid));
  }

  // ===========================================================
  // Upload Profile Photo
  // ===========================================================

  Future<String> uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    _validateImage(
      bytes: bytes,
      maximumBytes: maxProfilePhotoBytes,
      contentType: contentType,
      fieldName: 'Profile photo',
    );

    final Reference reference = profilePhotoReference(uid);

    return _uploadImage(
      reference: reference,
      bytes: bytes,
      contentType: contentType,
      customMetadata: <String, String>{
        'ownerUid': _normalizeUid(uid),
        'mediaType': 'profilePhoto',
      },
    );
  }

  // ===========================================================
  // Upload Cover Photo
  // ===========================================================

  Future<String> uploadCoverPhoto({
    required String uid,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    _validateImage(
      bytes: bytes,
      maximumBytes: maxCoverPhotoBytes,
      contentType: contentType,
      fieldName: 'Cover photo',
    );

    final Reference reference = coverPhotoReference(uid);

    return _uploadImage(
      reference: reference,
      bytes: bytes,
      contentType: contentType,
      customMetadata: <String, String>{
        'ownerUid': _normalizeUid(uid),
        'mediaType': 'coverPhoto',
      },
    );
  }

  // ===========================================================
  // Generic Internal Upload
  // ===========================================================

  Future<String> _uploadImage({
    required Reference reference,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  }) async {
    try {
      final SettableMetadata metadata = SettableMetadata(
        contentType: contentType,
        cacheControl: 'public,max-age=3600',
        customMetadata: customMetadata,
      );

      final UploadTask task = reference.putData(bytes, metadata);

      final TaskSnapshot snapshot = await task;

      if (snapshot.state != TaskState.success) {
        throw StateError(
          'Firebase Storage upload did not complete successfully.',
        );
      }

      final String downloadUrl = await snapshot.ref.getDownloadURL();

      final String normalizedUrl = downloadUrl.trim();

      if (normalizedUrl.isEmpty) {
        throw StateError(
          'Firebase Storage did not return a valid download URL.',
        );
      }

      return normalizedUrl;
    } on FirebaseException {
      rethrow;
    } catch (error) {
      throw StateError('Media upload failed: $error');
    }
  }

  // ===========================================================
  // Delete Profile Photo
  // ===========================================================

  Future<void> deleteProfilePhoto({required String uid}) {
    return _deleteReferenceSafely(profilePhotoReference(uid));
  }

  // ===========================================================
  // Delete Cover Photo
  // ===========================================================

  Future<void> deleteCoverPhoto({required String uid}) {
    return _deleteReferenceSafely(coverPhotoReference(uid));
  }

  // ===========================================================
  // Delete All Profile Media
  // ===========================================================

  Future<void> deleteUserProfileMedia({required String uid}) async {
    await Future.wait<void>(<Future<void>>[
      deleteProfilePhoto(uid: uid),
      deleteCoverPhoto(uid: uid),
    ]);
  }

  // ===========================================================
  // Delete Using Existing Download URL
  // ===========================================================

  Future<void> deleteByDownloadUrl(String? downloadUrl) async {
    final String normalized = downloadUrl?.trim() ?? '';

    if (normalized.isEmpty) {
      return;
    }

    try {
      final Reference reference = _storage.refFromURL(normalized);

      await reference.delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found' ||
          error.code == 'storage/object-not-found') {
        return;
      }

      rethrow;
    } catch (_) {
      return;
    }
  }

  // ===========================================================
  // Download URLs
  // ===========================================================

  Future<String?> getProfilePhotoUrl(String uid) {
    return _getDownloadUrlSafely(profilePhotoReference(uid));
  }

  Future<String?> getCoverPhotoUrl(String uid) {
    return _getDownloadUrlSafely(coverPhotoReference(uid));
  }

  Future<String?> _getDownloadUrlSafely(Reference reference) async {
    try {
      final String url = await reference.getDownloadURL();

      final String normalized = url.trim();

      return normalized.isEmpty ? null : normalized;
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found' ||
          error.code == 'storage/object-not-found') {
        return null;
      }

      rethrow;
    }
  }

  // ===========================================================
  // Safe Delete
  // ===========================================================

  Future<void> _deleteReferenceSafely(Reference reference) async {
    try {
      await reference.delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found' ||
          error.code == 'storage/object-not-found') {
        return;
      }

      rethrow;
    }
  }

  // ===========================================================
  // Validation
  // ===========================================================

  static void _validateImage({
    required Uint8List bytes,
    required int maximumBytes,
    required String contentType,
    required String fieldName,
  }) {
    if (bytes.isEmpty) {
      throw ArgumentError('$fieldName image data cannot be empty.');
    }

    if (bytes.lengthInBytes > maximumBytes) {
      throw ArgumentError('$fieldName exceeds the allowed file size.');
    }

    final String normalizedType = contentType.trim().toLowerCase();

    const Set<String> supportedTypes = <String>{
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif',
    };

    if (!supportedTypes.contains(normalizedType)) {
      throw ArgumentError('$fieldName has an unsupported image type.');
    }
  }

  // ===========================================================
  // UID Validation
  // ===========================================================

  static String _normalizeUid(String uid) {
    final String normalized = uid.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'Firebase UID cannot be empty.');
    }

    if (normalized.contains('/') || normalized.contains('\\')) {
      throw ArgumentError.value(
        uid,
        'uid',
        'Firebase UID contains invalid path characters.',
      );
    }

    return normalized;
  }
}
