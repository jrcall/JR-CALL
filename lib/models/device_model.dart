import 'dart:convert';

/// ===========================================================
/// JR CALL
/// File: device_model.dart
/// Description:
/// Stores device information for AI Call Engine,
/// Call Security, Connection Manager and Analytics.
/// ===========================================================

enum DevicePlatform { android, ios, windows, macos, linux, web, unknown }

class DeviceModel {
  /// Device ID
  final String deviceId;

  /// User ID
  final String userId;

  /// Device Name
  final String deviceName;

  /// Brand
  final String brand;

  /// Model
  final String model;

  /// Operating System
  final String operatingSystem;

  /// Platform
  final DevicePlatform platform;

  /// OS Version
  final String osVersion;

  /// App Version
  final String appVersion;

  /// Screen Width
  final double screenWidth;

  /// Screen Height
  final double screenHeight;

  /// Screen Density
  final double pixelRatio;

  /// Device Language
  final String language;

  /// Time Zone
  final String timeZone;

  /// Physical Device
  final bool isPhysicalDevice;

  /// Camera Available
  final bool hasCamera;

  /// Microphone Available
  final bool hasMicrophone;

  /// Speaker Available
  final bool hasSpeaker;

  /// Bluetooth Available
  final bool hasBluetooth;

  /// Last Active
  final DateTime lastActive;

  const DeviceModel({
    required this.deviceId,
    required this.userId,
    required this.deviceName,
    required this.brand,
    required this.model,
    required this.operatingSystem,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    required this.screenWidth,
    required this.screenHeight,
    required this.pixelRatio,
    required this.language,
    required this.timeZone,
    required this.isPhysicalDevice,
    required this.hasCamera,
    required this.hasMicrophone,
    required this.hasSpeaker,
    required this.hasBluetooth,
    required this.lastActive,
  });

  factory DeviceModel.initial() {
    return DeviceModel(
      deviceId: '',
      userId: '',
      deviceName: '',
      brand: '',
      model: '',
      operatingSystem: '',
      platform: DevicePlatform.unknown,
      osVersion: '',
      appVersion: '1.0.0',
      screenWidth: 0,
      screenHeight: 0,
      pixelRatio: 1,
      language: 'en',
      timeZone: 'UTC',
      isPhysicalDevice: false,
      hasCamera: false,
      hasMicrophone: false,
      hasSpeaker: false,
      hasBluetooth: false,
      lastActive: DateTime.now(),
    );
  }

  DeviceModel copyWith({
    String? deviceId,
    String? userId,
    String? deviceName,
    String? brand,
    String? model,
    String? operatingSystem,
    DevicePlatform? platform,
    String? osVersion,
    String? appVersion,
    double? screenWidth,
    double? screenHeight,
    double? pixelRatio,
    String? language,
    String? timeZone,
    bool? isPhysicalDevice,
    bool? hasCamera,
    bool? hasMicrophone,
    bool? hasSpeaker,
    bool? hasBluetooth,
    DateTime? lastActive,
  }) {
    return DeviceModel(
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      deviceName: deviceName ?? this.deviceName,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      operatingSystem: operatingSystem ?? this.operatingSystem,
      platform: platform ?? this.platform,
      osVersion: osVersion ?? this.osVersion,
      appVersion: appVersion ?? this.appVersion,
      screenWidth: screenWidth ?? this.screenWidth,
      screenHeight: screenHeight ?? this.screenHeight,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      language: language ?? this.language,
      timeZone: timeZone ?? this.timeZone,
      isPhysicalDevice: isPhysicalDevice ?? this.isPhysicalDevice,
      hasCamera: hasCamera ?? this.hasCamera,
      hasMicrophone: hasMicrophone ?? this.hasMicrophone,
      hasSpeaker: hasSpeaker ?? this.hasSpeaker,
      hasBluetooth: hasBluetooth ?? this.hasBluetooth,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "deviceId": deviceId,
      "userId": userId,
      "deviceName": deviceName,
      "brand": brand,
      "model": model,
      "operatingSystem": operatingSystem,
      "platform": platform.name,
      "osVersion": osVersion,
      "appVersion": appVersion,
      "screenWidth": screenWidth,
      "screenHeight": screenHeight,
      "pixelRatio": pixelRatio,
      "language": language,
      "timeZone": timeZone,
      "isPhysicalDevice": isPhysicalDevice,
      "hasCamera": hasCamera,
      "hasMicrophone": hasMicrophone,
      "hasSpeaker": hasSpeaker,
      "hasBluetooth": hasBluetooth,
      "lastActive": lastActive.toIso8601String(),
    };
  }

  factory DeviceModel.fromMap(Map<String, dynamic> map) {
    return DeviceModel(
      deviceId: map["deviceId"] ?? '',
      userId: map["userId"] ?? '',
      deviceName: map["deviceName"] ?? '',
      brand: map["brand"] ?? '',
      model: map["model"] ?? '',
      operatingSystem: map["operatingSystem"] ?? '',
      platform: DevicePlatform.values.firstWhere(
        (e) => e.name == map["platform"],
        orElse: () => DevicePlatform.unknown,
      ),
      osVersion: map["osVersion"] ?? '',
      appVersion: map["appVersion"] ?? '',
      screenWidth: (map["screenWidth"] ?? 0).toDouble(),
      screenHeight: (map["screenHeight"] ?? 0).toDouble(),
      pixelRatio: (map["pixelRatio"] ?? 1).toDouble(),
      language: map["language"] ?? 'en',
      timeZone: map["timeZone"] ?? 'UTC',
      isPhysicalDevice: map["isPhysicalDevice"] ?? false,
      hasCamera: map["hasCamera"] ?? false,
      hasMicrophone: map["hasMicrophone"] ?? false,
      hasSpeaker: map["hasSpeaker"] ?? false,
      hasBluetooth: map["hasBluetooth"] ?? false,
      lastActive: DateTime.parse(map["lastActive"]),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DeviceModel.fromJson(String source) =>
      DeviceModel.fromMap(jsonDecode(source));

  @override
  String toString() {
    return 'DeviceModel(deviceId: $deviceId, deviceName: $deviceName, platform: ${platform.name})';
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceModel &&
      other.deviceId == deviceId &&
      other.userId == userId &&
      other.platform == platform &&
      other.lastActive == lastActive;

  @override
  int get hashCode => Object.hash(deviceId, userId, platform, lastActive);
}
