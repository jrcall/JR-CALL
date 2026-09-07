import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// ===========================================================
/// JR CALL
/// File: permissions.dart
/// Location: lib/utils/permissions.dart
///
/// MASTER PRODUCTION RUNTIME PERMISSION COORDINATOR
///
/// RESPONSIBILITIES:
///
/// - Camera permission.
/// - Microphone permission.
/// - Voice/video call media permission.
/// - Profile/gallery media permission.
/// - Contacts permission.
/// - Notification permission.
/// - Bluetooth connection permission.
/// - Bluetooth discovery permission.
/// - Optional nearby Wi-Fi permission.
/// - Legacy compatibility APIs.
/// - Permanent-denial detection.
/// - Restricted-status detection.
/// - Permission rationale checks.
/// - Application-settings access.
/// - Serialized runtime permission requests.
///
/// PRODUCTION RULES:
///
/// - Request sensitive permissions only when the related feature
///   is actually used.
/// - Never request every permission at application startup.
/// - Android profile/gallery selection uses system/scoped picker.
/// - No broad Android storage permission for normal media picking.
/// - Firebase Phone Auth never requires Permission.phone.
/// - Bluetooth scan and Bluetooth connection remain separate.
/// - Nearby Wi-Fi permission remains optional/feature-triggered.
/// - Contacts permission remains optional/feature-triggered.
/// - Recording consent is NOT owned by this utility.
/// - Screen-capture consent is NOT owned by this utility.
/// - WebRTC media acquisition is NOT owned by this utility.
///
/// NATIVE DECLARATIONS REMAIN SEPARATE:
///
/// - android/app/src/main/AndroidManifest.xml
/// - ios/Runner/Info.plist
/// - iOS permission_handler permission macros/configuration
/// - Windows/native platform configuration where applicable
///
/// IMPORTANT:
///
/// permission_handler 12.0.1 officially provides plugin support
/// for Android, iOS, Web and Windows.
///
/// On Web, the browser/media API owns the actual permission prompt.
///
/// On other unsupported Flutter desktop targets, this utility does
/// not invoke permission_handler blindly. The actual platform/media
/// API remains responsible for permission enforcement.
/// ===========================================================

class AppPermissions {
  AppPermissions._();

  // ===========================================================
  // PLATFORM
  // ===========================================================

  static bool get _isAndroid =>
      !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android;

  static bool get _isIOS =>
      !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS;

  static bool get _isWindows =>
      !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.windows;

  /// Runtime permission_handler implementation used by this
  /// project/version for native requests.
  static bool get _supportsPermissionHandlerRuntime =>
      _isAndroid || _isIOS || _isWindows;

  /// Camera/microphone runtime state can be queried through
  /// permission_handler on these supported native targets.
  static bool get _supportsCameraAndMicrophoneRuntime =>
      _supportsPermissionHandlerRuntime;

  /// Contacts are runtime-sensitive on mobile. Windows plugin
  /// safely reports the platform state where supported.
  static bool get _supportsContactsRuntime =>
      _isAndroid || _isIOS || _isWindows;

  /// Notification authorization is platform-specific.
  static bool get _supportsNotificationRuntime =>
      _isAndroid || _isIOS || _isWindows;

  /// Bluetooth permission handling used by JR CALL.
  static bool get _supportsBluetoothRuntime =>
      _isAndroid || _isIOS || _isWindows;

  // ===========================================================
  // SERIALIZED PERMISSION REQUEST ENGINE
  //
  // Operating systems should not receive multiple overlapping
  // permission dialogs caused by fast/concurrent UI actions.
  // ===========================================================

  static Future<void> _requestQueue = Future<void>.value();

  // ===========================================================
  // STATUS HELPERS
  // ===========================================================

  static bool _isUsableStatus(
      PermissionStatus status, {
        bool allowLimited = false,
        bool allowProvisional = false,
      }) {
    if (status == PermissionStatus.granted) {
      return true;
    }

    if (allowLimited &&
        status == PermissionStatus.limited) {
      return true;
    }

    if (allowProvisional &&
        status == PermissionStatus.provisional) {
      return true;
    }

    return false;
  }

  static Future<PermissionStatus> _safeStatus(
      Permission permission,
      ) async {
    // Web permissions are requested by the browser API that
    // actually accesses the resource.
    if (kIsWeb) {
      return PermissionStatus.granted;
    }

    // Do not call a platform implementation that this pinned
    // permission_handler version does not officially provide.
    if (!_supportsPermissionHandlerRuntime) {
      return PermissionStatus.granted;
    }

    try {
      return await permission.status;
    } catch (error, stackTrace) {
      _reportError(
        '${permission.toString()} status',
        error,
        stackTrace,
      );

      return PermissionStatus.denied;
    }
  }

  static Future<bool> _has(
      Permission permission, {
        bool allowLimited = false,
        bool allowProvisional = false,
      }) async {
    if (kIsWeb ||
        !_supportsPermissionHandlerRuntime) {
      return true;
    }

    final PermissionStatus status =
    await _safeStatus(
      permission,
    );

    return _isUsableStatus(
      status,
      allowLimited: allowLimited,
      allowProvisional: allowProvisional,
    );
  }

  // ===========================================================
  // CENTRAL REQUEST
  // ===========================================================

  static Future<bool> _request(
      Permission permission, {
        bool allowLimited = false,
        bool allowProvisional = false,
      }) {
    if (kIsWeb ||
        !_supportsPermissionHandlerRuntime) {
      return Future<bool>.value(true);
    }

    final Completer<bool> completer =
    Completer<bool>();

    _requestQueue = _requestQueue.then<void>(
          (_) async {
        try {
          final bool result =
          await _requestDirect(
            permission,
            allowLimited: allowLimited,
            allowProvisional: allowProvisional,
          );

          if (!completer.isCompleted) {
            completer.complete(
              result,
            );
          }
        } catch (error, stackTrace) {
          _reportError(
            '${permission.toString()} request queue',
            error,
            stackTrace,
          );

          if (!completer.isCompleted) {
            completer.complete(
              false,
            );
          }
        }
      },
    );

    return completer.future;
  }

  static Future<bool> _requestDirect(
      Permission permission, {
        required bool allowLimited,
        required bool allowProvisional,
      }) async {
    try {
      final PermissionStatus currentStatus =
      await permission.status;

      if (_isUsableStatus(
        currentStatus,
        allowLimited: allowLimited,
        allowProvisional: allowProvisional,
      )) {
        return true;
      }

      if (currentStatus ==
          PermissionStatus.permanentlyDenied ||
          currentStatus ==
              PermissionStatus.restricted) {
        return false;
      }

      final PermissionStatus requestedStatus =
      await permission.request();

      return _isUsableStatus(
        requestedStatus,
        allowLimited: allowLimited,
        allowProvisional: allowProvisional,
      );
    } catch (error, stackTrace) {
      _reportError(
        '${permission.toString()} request',
        error,
        stackTrace,
      );

      return false;
    }
  }

  static Future<bool> _isPermanentlyDenied(
      Permission permission,
      ) async {
    if (kIsWeb ||
        !_supportsPermissionHandlerRuntime) {
      return false;
    }

    final PermissionStatus status =
    await _safeStatus(
      permission,
    );

    return status ==
        PermissionStatus.permanentlyDenied;
  }

  // ===========================================================
  // CAMERA
  // ===========================================================

  static Future<bool> requestCamera() {
    if (!_supportsCameraAndMicrophoneRuntime) {
      return Future<bool>.value(true);
    }

    return _request(
      Permission.camera,
    );
  }

  static Future<bool> hasCameraPermission() {
    if (!_supportsCameraAndMicrophoneRuntime) {
      return Future<bool>.value(true);
    }

    return _has(
      Permission.camera,
    );
  }

  static Future<bool>
  isCameraPermanentlyDenied() {
    if (!_supportsCameraAndMicrophoneRuntime) {
      return Future<bool>.value(false);
    }

    return _isPermanentlyDenied(
      Permission.camera,
    );
  }

  // ===========================================================
  // MICROPHONE
  // ===========================================================

  static Future<bool> requestMicrophone() {
    if (!_supportsCameraAndMicrophoneRuntime) {
      return Future<bool>.value(true);
    }

    return _request(
      Permission.microphone,
    );
  }

  static Future<bool>
  hasMicrophonePermission() {
    if (!_supportsCameraAndMicrophoneRuntime) {
      return Future<bool>.value(true);
    }

    return _has(
      Permission.microphone,
    );
  }

  static Future<bool>
  isMicrophonePermanentlyDenied() {
    if (!_supportsCameraAndMicrophoneRuntime) {
      return Future<bool>.value(false);
    }

    return _isPermanentlyDenied(
      Permission.microphone,
    );
  }

  // ===========================================================
  // CALL MEDIA PERMISSIONS
  //
  // Voice:
  // - Microphone only.
  //
  // Video:
  // - Microphone.
  // - Camera.
  //
  // Deliberately excluded:
  // - Phone.
  // - Contacts.
  // - Notifications.
  // - Bluetooth.
  // - Storage.
  // - Photos.
  // - Nearby Wi-Fi.
  // ===========================================================

  static Future<bool> requestCallPermissions({
    bool videoCall = true,
  }) async {
    final bool microphoneGranted =
    await requestMicrophone();

    if (!microphoneGranted) {
      return false;
    }

    if (!videoCall) {
      return true;
    }

    return requestCamera();
  }

  static Future<bool> hasCallPermissions({
    bool videoCall = true,
  }) async {
    final bool microphoneGranted =
    await hasMicrophonePermission();

    if (!microphoneGranted) {
      return false;
    }

    if (!videoCall) {
      return true;
    }

    return hasCameraPermission();
  }

  // ===========================================================
  // PHOTOS / GALLERY
  //
  // Android:
  // - Use Android Photo Picker / scoped system picker.
  // - No READ_EXTERNAL_STORAGE.
  // - No broad READ_MEDIA_IMAGES request here.
  //
  // iOS:
  // - Photo Library permission may be requested when needed.
  // - Limited access is a usable user-selected state.
  //
  // Web/Desktop:
  // - File/system picker owns access.
  // ===========================================================

  static Future<bool> requestPhotos() {
    if (kIsWeb) {
      return Future<bool>.value(true);
    }

    if (_isAndroid) {
      return Future<bool>.value(true);
    }

    if (_isIOS) {
      return _request(
        Permission.photos,
        allowLimited: true,
      );
    }

    return Future<bool>.value(true);
  }

  static Future<bool> hasPhotosPermission() {
    if (kIsWeb) {
      return Future<bool>.value(true);
    }

    if (_isAndroid) {
      return Future<bool>.value(true);
    }

    if (_isIOS) {
      return _has(
        Permission.photos,
        allowLimited: true,
      );
    }

    return Future<bool>.value(true);
  }

  static Future<bool>
  isPhotosPermanentlyDenied() {
    if (!_isIOS) {
      return Future<bool>.value(false);
    }

    return _isPermanentlyDenied(
      Permission.photos,
    );
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
  // PROFILE MEDIA
  // ===========================================================

  /// Requests only the permission for the source explicitly chosen
  /// by the user.
  static Future<bool> requestProfileMediaPermission({
    required bool sourceCamera,
  }) {
    if (sourceCamera) {
      return requestCamera();
    }

    return requestPhotos();
  }

  /// Existing compatibility API.
  ///
  /// New UI should prefer requestProfileMediaPermission() so it
  /// does not ask for camera access when the user only selected
  /// gallery/photo picker.
  static Future<bool>
  requestProfileMediaPermissions() async {
    final bool cameraGranted =
    await requestCamera();

    if (!cameraGranted) {
      return false;
    }

    return requestPhotos();
  }

  // ===========================================================
  // CONTACTS
  //
  // Contacts remain optional and feature-triggered.
  //
  // Limited access can be usable on platforms that support
  // user-selected contact access.
  // ===========================================================

  static Future<bool> requestContacts() {
    if (!_supportsContactsRuntime) {
      return Future<bool>.value(true);
    }

    return _request(
      Permission.contacts,
      allowLimited: true,
    );
  }

  static Future<bool> hasContactsPermission() {
    if (!_supportsContactsRuntime) {
      return Future<bool>.value(true);
    }

    return _has(
      Permission.contacts,
      allowLimited: true,
    );
  }

  static Future<bool>
  isContactsPermanentlyDenied() {
    if (!_supportsContactsRuntime) {
      return Future<bool>.value(false);
    }

    return _isPermanentlyDenied(
      Permission.contacts,
    );
  }

  // ===========================================================
  // NOTIFICATIONS
  //
  // Provisional notification authorization is usable because the
  // operating system has explicitly granted provisional delivery.
  // ===========================================================

  static Future<bool> requestNotification() {
    if (!_supportsNotificationRuntime) {
      return Future<bool>.value(true);
    }

    return _request(
      Permission.notification,
      allowProvisional: true,
    );
  }

  /// Existing compatibility alias.
  static Future<bool> requestNotifications() {
    return requestNotification();
  }

  static Future<bool>
  hasNotificationPermission() {
    if (!_supportsNotificationRuntime) {
      return Future<bool>.value(true);
    }

    return _has(
      Permission.notification,
      allowProvisional: true,
    );
  }

  static Future<bool>
  isNotificationPermanentlyDenied() {
    if (!_supportsNotificationRuntime) {
      return Future<bool>.value(false);
    }

    return _isPermanentlyDenied(
      Permission.notification,
    );
  }

  // ===========================================================
  // BLUETOOTH CONNECTION
  //
  // Connection permission is separate from discovery/scan.
  //
  // Android:
  // - BLUETOOTH_CONNECT runtime permission on modern Android.
  //
  // iOS/Windows:
  // - General Bluetooth permission/status where supported.
  // ===========================================================

  static Future<bool> requestBluetooth() {
    if (!_supportsBluetoothRuntime) {
      return Future<bool>.value(true);
    }

    if (_isAndroid) {
      return _request(
        Permission.bluetoothConnect,
      );
    }

    return _request(
      Permission.bluetooth,
    );
  }

  static Future<bool> hasBluetoothPermission() {
    if (!_supportsBluetoothRuntime) {
      return Future<bool>.value(true);
    }

    if (_isAndroid) {
      return _has(
        Permission.bluetoothConnect,
      );
    }

    return _has(
      Permission.bluetooth,
    );
  }

  static Future<bool>
  isBluetoothPermanentlyDenied() {
    if (!_supportsBluetoothRuntime) {
      return Future<bool>.value(false);
    }

    if (_isAndroid) {
      return _isPermanentlyDenied(
        Permission.bluetoothConnect,
      );
    }

    return _isPermanentlyDenied(
      Permission.bluetooth,
    );
  }

  // ===========================================================
  // BLUETOOTH DISCOVERY / SCAN
  //
  // Request only when the user explicitly starts a Bluetooth
  // device discovery workflow.
  // ===========================================================

  static Future<bool> requestBluetoothScan() {
    if (!_supportsBluetoothRuntime) {
      return Future<bool>.value(true);
    }

    if (_isAndroid) {
      return _request(
        Permission.bluetoothScan,
      );
    }

    // Apple/Windows expose general Bluetooth authorization rather
    // than Android's separate BLUETOOTH_SCAN runtime permission.
    return _request(
      Permission.bluetooth,
    );
  }

  static Future<bool>
  hasBluetoothScanPermission() {
    if (!_supportsBluetoothRuntime) {
      return Future<bool>.value(true);
    }

    if (_isAndroid) {
      return _has(
        Permission.bluetoothScan,
      );
    }

    return _has(
      Permission.bluetooth,
    );
  }

  static Future<bool>
  isBluetoothScanPermanentlyDenied() {
    if (!_supportsBluetoothRuntime) {
      return Future<bool>.value(false);
    }

    if (_isAndroid) {
      return _isPermanentlyDenied(
        Permission.bluetoothScan,
      );
    }

    return _isPermanentlyDenied(
      Permission.bluetooth,
    );
  }

  /// Convenience API for an explicit Bluetooth-device discovery
  /// workflow.
  static Future<bool>
  requestBluetoothDiscoveryPermissions() async {
    if (!_supportsBluetoothRuntime) {
      return true;
    }

    if (!_isAndroid) {
      return requestBluetooth();
    }

    final bool scanGranted =
    await requestBluetoothScan();

    if (!scanGranted) {
      return false;
    }

    return requestBluetooth();
  }

  // ===========================================================
  // ANDROID PHONE PERMISSION — LEGACY ONLY
  //
  // IMPORTANT:
  //
  // - Firebase Phone Auth does NOT use this.
  // - Receiving Firebase SMS OTP does NOT use this.
  // - WebRTC voice/video calling does NOT use this.
  //
  // Keep only for a verified future native telephony feature.
  // ===========================================================

  static Future<bool> requestPhone() {
    if (!_isAndroid) {
      return Future<bool>.value(true);
    }

    return _request(
      Permission.phone,
    );
  }

  static Future<bool> hasPhonePermission() {
    if (!_isAndroid) {
      return Future<bool>.value(true);
    }

    return _has(
      Permission.phone,
    );
  }

  static Future<bool>
  isPhonePermanentlyDenied() {
    if (!_isAndroid) {
      return Future<bool>.value(false);
    }

    return _isPermanentlyDenied(
      Permission.phone,
    );
  }

  // ===========================================================
  // NEARBY WI-FI DEVICES
  //
  // Optional Android feature permission only.
  //
  // Ordinary Wi-Fi Internet, Firebase and WebRTC traffic do NOT
  // require this runtime permission.
  //
  // Do not request at application startup.
  // ===========================================================

  static Future<bool> requestNearbyDevices() {
    if (!_isAndroid) {
      return Future<bool>.value(true);
    }

    return _request(
      Permission.nearbyWifiDevices,
    );
  }

  static Future<bool>
  hasNearbyDevicesPermission() {
    if (!_isAndroid) {
      return Future<bool>.value(true);
    }

    return _has(
      Permission.nearbyWifiDevices,
    );
  }

  static Future<bool>
  isNearbyDevicesPermanentlyDenied() {
    if (!_isAndroid) {
      return Future<bool>.value(false);
    }

    return _isPermanentlyDenied(
      Permission.nearbyWifiDevices,
    );
  }

  // ===========================================================
  // STORAGE — LEGACY COMPATIBILITY
  //
  // Broad Android storage permission is intentionally NOT
  // requested by normal JR CALL media/file flows.
  // ===========================================================

  static Future<bool> requestStorage() async {
    return true;
  }

  static Future<bool> hasStoragePermission() async {
    return true;
  }

  // ===========================================================
  // RECORDING PERMISSION
  //
  // This method coordinates only microphone authorization.
  //
  // Explicit recording consent, recording indicator, retention,
  // applicable local law and call-recorder behavior belong to the
  // dedicated recording feature.
  // ===========================================================

  static Future<bool>
  requestRecordingPermissions() {
    return requestMicrophone();
  }

  // ===========================================================
  // SCREEN SHARE
  //
  // Screen-capture consent is owned by the operating-system /
  // WebRTC screen-capture flow.
  //
  // Microphone is requested here only when explicitly requested.
  // ===========================================================

  static Future<bool>
  requestScreenSharePermissions({
    bool withMicrophone = false,
  }) {
    if (!withMicrophone) {
      return Future<bool>.value(true);
    }

    return requestMicrophone();
  }

  // ===========================================================
  // ESSENTIAL FOREGROUND CALL PERMISSIONS
  //
  // Existing compatibility API.
  //
  // Despite its legacy name, requestAll() deliberately requests
  // only the permissions necessary for a foreground video call:
  //
  // - Microphone.
  // - Camera.
  //
  // It deliberately excludes all unrelated sensitive permissions.
  // ===========================================================

  static Future<bool> requestAll() {
    return requestCallPermissions(
      videoCall: true,
    );
  }

  // ===========================================================
  // PERMISSION RATIONALE
  // ===========================================================

  static Future<bool> shouldShowRationale(
      Permission permission,
      ) async {
    if (!_isAndroid) {
      return false;
    }

    try {
      return await permission
          .shouldShowRequestRationale;
    } catch (error, stackTrace) {
      _reportError(
        '${permission.toString()} rationale',
        error,
        stackTrace,
      );

      return false;
    }
  }

  // ===========================================================
  // GENERIC PERMANENT DENIAL
  // ===========================================================

  static Future<bool> isPermanentlyDenied(
      Permission permission,
      ) {
    return _isPermanentlyDenied(
      permission,
    );
  }

  // ===========================================================
  // GENERIC RESTRICTED STATUS
  // ===========================================================

  static Future<bool> isRestricted(
      Permission permission,
      ) async {
    if (kIsWeb ||
        !_supportsPermissionHandlerRuntime) {
      return false;
    }

    final PermissionStatus status =
    await _safeStatus(
      permission,
    );

    return status ==
        PermissionStatus.restricted;
  }

  // ===========================================================
  // GENERIC CURRENT STATUS
  // ===========================================================

  static Future<PermissionStatus> statusOf(
      Permission permission,
      ) {
    return _safeStatus(
      permission,
    );
  }

  // ===========================================================
  // APPLICATION SETTINGS
  // ===========================================================

  static Future<void> openSettings() async {
    if (kIsWeb ||
        !_supportsPermissionHandlerRuntime) {
      return;
    }

    try {
      final bool opened =
      await openAppSettings();

      if (!opened) {
        debugPrint(
          'JR CALL [Permissions] '
              'Application settings could not be opened.',
        );
      }
    } catch (error, stackTrace) {
      _reportError(
        'Open application settings',
        error,
        stackTrace,
      );
    }
  }

  /// Existing compatibility alias.
  static Future<void> openApplicationSettings() {
    return openSettings();
  }

  // ===========================================================
  // ERROR REPORTING
  // ===========================================================

  static void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [Permissions/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [Permissions/$source]',
        stackTrace: stackTrace,
      );
    }
  }
}