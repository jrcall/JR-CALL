import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// ===========================================================
/// JR CALL
/// File: permissions.dart
/// Location: lib/utils/permissions.dart
///
/// Description:
/// Central production runtime-permission coordinator.
///
/// Responsibilities:
/// - Camera permission
/// - Microphone permission
/// - Voice/video call media permission
/// - Profile/gallery media permission
/// - Contacts permission
/// - Notification permission
/// - Bluetooth connection permission
/// - Optional Bluetooth discovery permission
/// - Optional nearby Wi-Fi devices permission
/// - Legacy compatibility APIs
/// - Permanent-denial detection
/// - Restricted-status detection
/// - Safe application-settings access
///
/// Production Rules:
/// - Request permissions only when the relevant feature is used.
/// - Never request every sensitive permission at app startup.
/// - No broad Android storage permission for profile/gallery media.
/// - Android Photo Picker / scoped picker is preferred.
/// - Firebase Phone Auth does not use Permission.phone.
/// - Bluetooth scanning is separated from Bluetooth connection.
/// - Contacts permission remains optional.
/// - No Firebase/WebRTC/media-acquisition ownership here.
///
/// Native declarations remain separate:
/// - AndroidManifest.xml
/// - iOS Info.plist
/// - macOS native configuration when supported
/// ===========================================================
class AppPermissions {
  AppPermissions._();

  // ===========================================================
  // Platform Helpers
  // ===========================================================

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get _isMobile => _isAndroid || _isIOS;

  static bool get _supportsNativeCameraAndMicrophone {
    return _isAndroid || _isIOS || _isMacOS;
  }

  // ===========================================================
  // Permission Status Helpers
  // ===========================================================

  static bool _isUsableStatus(
    PermissionStatus status, {
    bool allowProvisional = false,
  }) {
    if (status == PermissionStatus.granted ||
        status == PermissionStatus.limited) {
      return true;
    }

    if (allowProvisional && status == PermissionStatus.provisional) {
      return true;
    }

    return false;
  }

  static Future<PermissionStatus> _safeStatus(Permission permission) async {
    if (kIsWeb) {
      return PermissionStatus.granted;
    }

    try {
      return await permission.status;
    } catch (error) {
      debugPrint(
        'JR CALL [Permissions] '
        '${permission.toString()} status failed: $error',
      );

      return PermissionStatus.denied;
    }
  }

  static Future<bool> _request(
    Permission permission, {
    bool allowProvisional = false,
  }) async {
    if (kIsWeb) {
      // Web permissions are controlled by the browser/API that
      // actually accesses the camera, microphone or other data.
      return true;
    }

    try {
      final currentStatus = await permission.status;

      if (_isUsableStatus(currentStatus, allowProvisional: allowProvisional)) {
        return true;
      }

      if (currentStatus == PermissionStatus.permanentlyDenied ||
          currentStatus == PermissionStatus.restricted) {
        return false;
      }

      final requestedStatus = await permission.request();

      return _isUsableStatus(
        requestedStatus,
        allowProvisional: allowProvisional,
      );
    } catch (error) {
      debugPrint(
        'JR CALL [Permissions] '
        '${permission.toString()} request failed: $error',
      );

      return false;
    }
  }

  static Future<bool> _has(
    Permission permission, {
    bool allowProvisional = false,
  }) async {
    if (kIsWeb) {
      return true;
    }

    final status = await _safeStatus(permission);

    return _isUsableStatus(status, allowProvisional: allowProvisional);
  }

  static Future<bool> _isPermanentlyDenied(Permission permission) async {
    if (kIsWeb) {
      return false;
    }

    final status = await _safeStatus(permission);

    return status == PermissionStatus.permanentlyDenied;
  }

  // ===========================================================
  // Camera
  // ===========================================================

  static Future<bool> requestCamera() async {
    if (!_supportsNativeCameraAndMicrophone) {
      return true;
    }

    return _request(Permission.camera);
  }

  static Future<bool> hasCameraPermission() async {
    if (!_supportsNativeCameraAndMicrophone) {
      return true;
    }

    return _has(Permission.camera);
  }

  static Future<bool> isCameraPermanentlyDenied() async {
    if (!_supportsNativeCameraAndMicrophone) {
      return false;
    }

    return _isPermanentlyDenied(Permission.camera);
  }

  // ===========================================================
  // Microphone
  // ===========================================================

  static Future<bool> requestMicrophone() async {
    if (!_supportsNativeCameraAndMicrophone) {
      return true;
    }

    return _request(Permission.microphone);
  }

  static Future<bool> hasMicrophonePermission() async {
    if (!_supportsNativeCameraAndMicrophone) {
      return true;
    }

    return _has(Permission.microphone);
  }

  static Future<bool> isMicrophonePermanentlyDenied() async {
    if (!_supportsNativeCameraAndMicrophone) {
      return false;
    }

    return _isPermanentlyDenied(Permission.microphone);
  }

  // ===========================================================
  // Call Permissions
  // ===========================================================

  /// Voice:
  /// microphone only.
  ///
  /// Video:
  /// microphone + camera.
  ///
  /// Does NOT request notifications, contacts, Bluetooth,
  /// phone-state, storage or nearby-device permissions.
  static Future<bool> requestCallPermissions({bool videoCall = true}) async {
    final microphoneGranted = await requestMicrophone();

    if (!microphoneGranted) {
      return false;
    }

    if (!videoCall) {
      return true;
    }

    return requestCamera();
  }

  static Future<bool> hasCallPermissions({bool videoCall = true}) async {
    final microphoneGranted = await hasMicrophonePermission();

    if (!microphoneGranted) {
      return false;
    }

    if (!videoCall) {
      return true;
    }

    return hasCameraPermission();
  }

  // ===========================================================
  // Photos / Gallery
  // ===========================================================

  /// Profile/cover media permission.
  ///
  /// Android:
  /// JR CALL should use system/scoped image picker.
  /// No READ_EXTERNAL_STORAGE / broad media permission is
  /// requested here.
  ///
  /// iOS:
  /// Photo Library authorization is coordinated here.
  ///
  /// Web/Desktop:
  /// Picker/file authorization belongs to the platform picker.
  static Future<bool> requestPhotos() async {
    if (kIsWeb) {
      return true;
    }

    if (_isAndroid) {
      return true;
    }

    if (_isIOS) {
      return _request(Permission.photos);
    }

    return true;
  }

  static Future<bool> hasPhotosPermission() async {
    if (kIsWeb) {
      return true;
    }

    if (_isAndroid) {
      return true;
    }

    if (_isIOS) {
      return _has(Permission.photos);
    }

    return true;
  }

  static Future<bool> isPhotosPermanentlyDenied() async {
    if (!_isIOS) {
      return false;
    }

    return _isPermanentlyDenied(Permission.photos);
  }

  /// Existing compatibility alias.
  static Future<bool> requestGallery() {
    return requestPhotos();
  }

  /// Existing compatibility alias.
  static Future<bool> hasGalleryPermission() {
    return hasPhotosPermission();
  }

  // ===========================================================
  // Profile Media
  // ===========================================================

  /// Requests only the permission corresponding to the source
  /// explicitly selected by the user.
  static Future<bool> requestProfileMediaPermission({
    required bool sourceCamera,
  }) {
    if (sourceCamera) {
      return requestCamera();
    }

    return requestPhotos();
  }

  /// Legacy compatibility API.
  ///
  /// New profile UI should prefer:
  /// requestProfileMediaPermission(sourceCamera: ...)
  ///
  /// This method is preserved for existing callers.
  static Future<bool> requestProfileMediaPermissions() async {
    final cameraGranted = await requestCamera();

    if (!cameraGranted) {
      return false;
    }

    return requestPhotos();
  }

  // ===========================================================
  // Contacts
  // ===========================================================

  /// Optional contact-sync permission.
  ///
  /// Never call this automatically during startup.
  static Future<bool> requestContacts() async {
    if (!_isMobile) {
      return true;
    }

    return _request(Permission.contacts);
  }

  static Future<bool> hasContactsPermission() async {
    if (!_isMobile) {
      return true;
    }

    return _has(Permission.contacts);
  }

  static Future<bool> isContactsPermanentlyDenied() async {
    if (!_isMobile) {
      return false;
    }

    return _isPermanentlyDenied(Permission.contacts);
  }

  // ===========================================================
  // Notifications
  // ===========================================================

  /// Request when notification/incoming-call functionality
  /// actually requires notification authorization.
  static Future<bool> requestNotification() async {
    if (!_isMobile) {
      return true;
    }

    return _request(Permission.notification, allowProvisional: true);
  }

  /// Existing compatibility alias.
  static Future<bool> requestNotifications() {
    return requestNotification();
  }

  static Future<bool> hasNotificationPermission() async {
    if (!_isMobile) {
      return true;
    }

    return _has(Permission.notification, allowProvisional: true);
  }

  static Future<bool> isNotificationPermanentlyDenied() async {
    if (!_isMobile) {
      return false;
    }

    return _isPermanentlyDenied(Permission.notification);
  }

  // ===========================================================
  // Bluetooth Connection
  // ===========================================================

  /// Permission for communicating with an already paired/
  /// connected Bluetooth device.
  ///
  /// IMPORTANT:
  /// This method deliberately does NOT request Bluetooth Scan.
  /// Scanning is a separate user-visible operation.
  static Future<bool> requestBluetooth() async {
    if (kIsWeb) {
      return true;
    }

    if (_isAndroid) {
      return _request(Permission.bluetoothConnect);
    }

    if (_isIOS) {
      return _request(Permission.bluetooth);
    }

    return true;
  }

  static Future<bool> hasBluetoothPermission() async {
    if (kIsWeb) {
      return true;
    }

    if (_isAndroid) {
      return _has(Permission.bluetoothConnect);
    }

    if (_isIOS) {
      return _has(Permission.bluetooth);
    }

    return true;
  }

  static Future<bool> isBluetoothPermanentlyDenied() async {
    if (kIsWeb) {
      return false;
    }

    if (_isAndroid) {
      return _isPermanentlyDenied(Permission.bluetoothConnect);
    }

    if (_isIOS) {
      return _isPermanentlyDenied(Permission.bluetooth);
    }

    return false;
  }

  // ===========================================================
  // Bluetooth Discovery / Scan
  // ===========================================================

  /// Use ONLY when JR CALL explicitly implements a Bluetooth
  /// device discovery/pairing screen.
  ///
  /// Normal WebRTC calling should not call this automatically.
  static Future<bool> requestBluetoothScan() async {
    if (!_isAndroid) {
      return true;
    }

    return _request(Permission.bluetoothScan);
  }

  static Future<bool> hasBluetoothScanPermission() async {
    if (!_isAndroid) {
      return true;
    }

    return _has(Permission.bluetoothScan);
  }

  static Future<bool> isBluetoothScanPermanentlyDenied() async {
    if (!_isAndroid) {
      return false;
    }

    return _isPermanentlyDenied(Permission.bluetoothScan);
  }

  /// Convenience method for a future explicit Bluetooth-device
  /// discovery screen.
  static Future<bool> requestBluetoothDiscoveryPermissions() async {
    if (!_isAndroid) {
      return requestBluetooth();
    }

    final scanGranted = await requestBluetoothScan();

    if (!scanGranted) {
      return false;
    }

    return requestBluetooth();
  }

  // ===========================================================
  // Android Phone Permission — Legacy Only
  // ===========================================================

  /// Legacy compatibility API.
  ///
  /// IMPORTANT:
  /// Firebase Phone Authentication / SMS OTP does not call this.
  ///
  /// JR CALL Internet voice/video calling also does not require
  /// Android phone-state permission merely to make a WebRTC call.
  ///
  /// Keep this API only for any verified future native telephony
  /// feature that genuinely needs it.
  static Future<bool> requestPhone() async {
    if (!_isAndroid) {
      return true;
    }

    return _request(Permission.phone);
  }

  static Future<bool> hasPhonePermission() async {
    if (!_isAndroid) {
      return true;
    }

    return _has(Permission.phone);
  }

  static Future<bool> isPhonePermanentlyDenied() async {
    if (!_isAndroid) {
      return false;
    }

    return _isPermanentlyDenied(Permission.phone);
  }

  // ===========================================================
  // Nearby Wi-Fi Devices
  // ===========================================================

  /// Optional Android permission.
  ///
  /// Use only when a future JR CALL feature really discovers or
  /// communicates with nearby Wi-Fi devices.
  ///
  /// Ordinary Internet access, Firebase and WebRTC calls must not
  /// call this automatically.
  static Future<bool> requestNearbyDevices() async {
    if (!_isAndroid) {
      return true;
    }

    return _request(Permission.nearbyWifiDevices);
  }

  static Future<bool> hasNearbyDevicesPermission() async {
    if (!_isAndroid) {
      return true;
    }

    return _has(Permission.nearbyWifiDevices);
  }

  static Future<bool> isNearbyDevicesPermanentlyDenied() async {
    if (!_isAndroid) {
      return false;
    }

    return _isPermanentlyDenied(Permission.nearbyWifiDevices);
  }

  // ===========================================================
  // Storage — Legacy Compatibility
  // ===========================================================

  /// Legacy compatibility API.
  ///
  /// JR CALL deliberately does NOT request broad Android storage
  /// access for profile pictures, cover photos, normal document
  /// picking or app-owned files.
  ///
  /// Modern code should use scoped/system pickers.
  static Future<bool> requestStorage() async {
    return true;
  }

  /// Legacy compatibility counterpart.
  static Future<bool> hasStoragePermission() async {
    return true;
  }

  // ===========================================================
  // Recording Permissions
  // ===========================================================

  /// Microphone authorization only.
  ///
  /// Recording consent/UI/legal requirements belong to the
  /// dedicated recording feature and are not permission-handler
  /// responsibilities.
  static Future<bool> requestRecordingPermissions() {
    return requestMicrophone();
  }

  // ===========================================================
  // Screen Share
  // ===========================================================

  /// Screen-capture authorization is controlled by the native
  /// operating-system/WebRTC screen-capture flow.
  ///
  /// Microphone is requested separately only when requested.
  static Future<bool> requestScreenSharePermissions({
    bool withMicrophone = false,
  }) async {
    if (!withMicrophone) {
      return true;
    }

    return requestMicrophone();
  }

  // ===========================================================
  // Essential Foreground Communication Permissions
  // ===========================================================

  /// Existing public compatibility API.
  ///
  /// IMPORTANT:
  /// Despite the legacy method name "requestAll", production
  /// behavior intentionally requests ONLY the essential
  /// foreground voice/video permissions:
  ///
  /// - Microphone
  /// - Camera
  ///
  /// It intentionally does NOT request:
  /// - Contacts
  /// - Photos
  /// - Notification
  /// - Bluetooth
  /// - Bluetooth Scan
  /// - Nearby Wi-Fi
  /// - Phone
  /// - Storage
  ///
  /// Those permissions must be requested at the moment their
  /// related feature is used.
  static Future<bool> requestAll() {
    return requestCallPermissions(videoCall: true);
  }

  // ===========================================================
  // Permission Rationale
  // ===========================================================

  /// Returns whether Android recommends showing an explanatory
  /// permission rationale before requesting again.
  static Future<bool> shouldShowRationale(Permission permission) async {
    if (!_isAndroid) {
      return false;
    }

    try {
      return await permission.shouldShowRequestRationale;
    } catch (error) {
      debugPrint(
        'JR CALL [Permissions] '
        '${permission.toString()} rationale check failed: $error',
      );

      return false;
    }
  }

  // ===========================================================
  // Generic Permanent Denial
  // ===========================================================

  static Future<bool> isPermanentlyDenied(Permission permission) {
    return _isPermanentlyDenied(permission);
  }

  // ===========================================================
  // Generic Restricted Permission
  // ===========================================================

  static Future<bool> isRestricted(Permission permission) async {
    if (kIsWeb) {
      return false;
    }

    final status = await _safeStatus(permission);

    return status == PermissionStatus.restricted;
  }

  // ===========================================================
  // Generic Current Status
  // ===========================================================

  static Future<PermissionStatus> statusOf(Permission permission) {
    return _safeStatus(permission);
  }

  // ===========================================================
  // App Settings
  // ===========================================================

  static Future<void> openSettings() async {
    if (kIsWeb) {
      return;
    }

    try {
      final opened = await openAppSettings();

      if (!opened) {
        debugPrint(
          'JR CALL [Permissions] '
          'Application settings could not be opened.',
        );
      }
    } catch (error) {
      debugPrint(
        'JR CALL [Permissions] '
        'Unable to open application settings: $error',
      );
    }
  }

  /// Existing compatibility alias.
  static Future<void> openApplicationSettings() {
    return openSettings();
  }
}
