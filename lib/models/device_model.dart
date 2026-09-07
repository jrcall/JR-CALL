import 'dart:convert';

/// ===========================================================
/// JR CALL
/// File: device_model.dart
/// Location: lib/models/device_model.dart
///
/// FINAL PRODUCTION CONTRACT:
/// - Existing fields, constructor and APIs preserved.
/// - Existing DevicePlatform enum ordering preserved.
/// - Safe legacy / malformed data parsing.
/// - Call-capability snapshot only.
/// - Runtime audio routing remains owned by call audio managers.
/// - Camera switching remains owned by camera/video managers.
/// - Screen-share runtime remains owned by screen_share_service.dart.
/// - No WebRTC / signaling / connection ownership.
/// ===========================================================

enum DevicePlatform {
  android,
  ios,
  windows,
  macos,
  linux,
  web,
  unknown,
}

class DeviceModel {
  /// Stable app/device installation identifier.
  final String deviceId;

  /// Canonical authenticated Firebase UID.
  final String userId;

  final String deviceName;
  final String brand;
  final String model;
  final String operatingSystem;
  final DevicePlatform platform;
  final String osVersion;
  final String appVersion;

  final double screenWidth;
  final double screenHeight;
  final double pixelRatio;

  final String language;
  final String timeZone;

  final bool isPhysicalDevice;

  /// Device capability snapshot.
  final bool hasCamera;
  final bool hasMicrophone;
  final bool hasSpeaker;
  final bool hasBluetooth;

  /// Optional production capability extensions.
  ///
  /// These defaults preserve all existing constructor call sites.
  final bool hasEarpiece;
  final bool hasWiredHeadset;
  final bool supportsScreenShare;

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
    this.hasEarpiece = false,
    this.hasWiredHeadset = false,
    this.supportsScreenShare = false,
    required this.lastActive,
  });

  // =============================================================
  // INITIAL
  // =============================================================

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
      hasEarpiece: false,
      hasWiredHeadset: false,
      supportsScreenShare: false,
      lastActive: DateTime.now(),
    );
  }

  // =============================================================
  // CALL CAPABILITY HELPERS
  // =============================================================

  /// Whether this device exposes at least one known audio-output path.
  ///
  /// Bluetooth here means hardware/platform capability only.
  /// The currently connected Bluetooth route is owned by
  /// bluetooth_manager.dart.
  bool get hasAudioOutput =>
      hasSpeaker || hasEarpiece || hasBluetooth || hasWiredHeadset;

  /// Basic device-side requirements for a voice call.
  bool get supportsVoiceCall => hasMicrophone && hasAudioOutput;

  /// Basic device-side requirements for a video call.
  bool get supportsVideoCall => supportsVoiceCall && hasCamera;

  bool get supportsBluetoothAudio => hasBluetooth;

  bool get hasValidScreenMetrics =>
      screenWidth > 0 && screenHeight > 0 && pixelRatio > 0;

  bool get hasIdentity =>
      deviceId.trim().isNotEmpty && userId.trim().isNotEmpty;

  // =============================================================
  // COPY
  // =============================================================

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
    bool? hasEarpiece,
    bool? hasWiredHeadset,
    bool? supportsScreenShare,
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
      hasEarpiece: hasEarpiece ?? this.hasEarpiece,
      hasWiredHeadset: hasWiredHeadset ?? this.hasWiredHeadset,
      supportsScreenShare:
      supportsScreenShare ?? this.supportsScreenShare,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  // =============================================================
  // SERIALIZATION
  // =============================================================

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'userId': userId,
      'deviceName': deviceName,
      'brand': brand,
      'model': model,
      'operatingSystem': operatingSystem,
      'platform': platform.name,
      'osVersion': osVersion,
      'appVersion': appVersion,
      'screenWidth': screenWidth,
      'screenHeight': screenHeight,
      'pixelRatio': pixelRatio,
      'language': language,
      'timeZone': timeZone,
      'isPhysicalDevice': isPhysicalDevice,
      'hasCamera': hasCamera,
      'hasMicrophone': hasMicrophone,
      'hasSpeaker': hasSpeaker,
      'hasBluetooth': hasBluetooth,
      'hasEarpiece': hasEarpiece,
      'hasWiredHeadset': hasWiredHeadset,
      'supportsScreenShare': supportsScreenShare,
      'lastActive': lastActive.toUtc().toIso8601String(),
    };
  }

  factory DeviceModel.fromMap(Map<String, dynamic> map) {
    return DeviceModel(
      deviceId: _string(
        _firstValue(
          map,
          const <String>[
            'deviceId',
            'device_id',
            'installationId',
          ],
        ),
      ),
      userId: _string(
        _firstValue(
          map,
          const <String>[
            'userId',
            'uid',
            'user_id',
          ],
        ),
      ),
      deviceName: _string(
        _firstValue(
          map,
          const <String>[
            'deviceName',
            'name',
            'device_name',
          ],
        ),
      ),
      brand: _string(map['brand']),
      model: _string(map['model']),
      operatingSystem: _string(
        _firstValue(
          map,
          const <String>[
            'operatingSystem',
            'os',
            'operating_system',
          ],
        ),
      ),
      platform: _devicePlatform(map['platform']),
      osVersion: _string(
        _firstValue(
          map,
          const <String>[
            'osVersion',
            'os_version',
          ],
        ),
      ),
      appVersion: _string(
        map['appVersion'],
        fallback: '',
      ),
      screenWidth: _nonNegativeDouble(
        map['screenWidth'],
      ),
      screenHeight: _nonNegativeDouble(
        map['screenHeight'],
      ),
      pixelRatio: _positiveDouble(
        map['pixelRatio'],
        fallback: 1,
      ),
      language: _string(
        map['language'],
        fallback: 'en',
      ),
      timeZone: _string(
        _firstValue(
          map,
          const <String>[
            'timeZone',
            'timezone',
          ],
        ),
        fallback: 'UTC',
      ),
      isPhysicalDevice: _boolean(
        map['isPhysicalDevice'],
      ),
      hasCamera: _boolean(
        map['hasCamera'],
      ),
      hasMicrophone: _boolean(
        map['hasMicrophone'],
      ),
      hasSpeaker: _boolean(
        map['hasSpeaker'],
      ),
      hasBluetooth: _boolean(
        map['hasBluetooth'],
      ),
      hasEarpiece: _boolean(
        map['hasEarpiece'],
      ),
      hasWiredHeadset: _boolean(
        map['hasWiredHeadset'],
      ),
      supportsScreenShare: _boolean(
        _firstValue(
          map,
          const <String>[
            'supportsScreenShare',
            'canScreenShare',
          ],
        ),
      ),
      lastActive: _dateTime(
        _firstValue(
          map,
          const <String>[
            'lastActive',
            'last_active',
            'updatedAt',
          ],
        ),
      ),
    );
  }

  // =============================================================
  // JSON
  // =============================================================

  String toJson() => jsonEncode(toMap());

  factory DeviceModel.fromJson(String source) {
    try {
      final dynamic decoded = jsonDecode(source);

      if (decoded is Map<String, dynamic>) {
        return DeviceModel.fromMap(decoded);
      }

      if (decoded is Map) {
        final Map<String, dynamic> normalized = <String, dynamic>{};

        for (final MapEntry<dynamic, dynamic> entry in decoded.entries) {
          normalized[entry.key.toString()] = entry.value;
        }

        return DeviceModel.fromMap(normalized);
      }
    } on FormatException {
      // Invalid legacy JSON falls through to safe defaults.
    } catch (_) {
      // Malformed persisted device data must not crash Call Engine.
    }

    return DeviceModel.fromMap(const <String, dynamic>{});
  }

  // =============================================================
  // SAFE PARSING
  // =============================================================

  static dynamic _firstValue(
      Map<String, dynamic> map,
      List<String> keys,
      ) {
    for (final String key in keys) {
      if (!map.containsKey(key)) {
        continue;
      }

      final dynamic value = map[key];

      if (value == null) {
        continue;
      }

      if (value is String && value.trim().isEmpty) {
        continue;
      }

      return value;
    }

    return null;
  }

  static String _string(
      dynamic value, {
        String fallback = '',
      }) {
    if (value == null) {
      return fallback;
    }

    final String parsed = value.toString().trim();

    return parsed.isEmpty ? fallback : parsed;
  }

  static double _safeDouble(
      dynamic value, {
        double fallback = 0,
      }) {
    double? parsed;

    if (value is num) {
      parsed = value.toDouble();
    } else {
      parsed = double.tryParse(
        value?.toString().trim() ?? '',
      );
    }

    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return fallback;
    }

    return parsed;
  }

  static double _nonNegativeDouble(dynamic value) {
    final double parsed = _safeDouble(value);

    return parsed < 0 ? 0 : parsed;
  }

  static double _positiveDouble(
      dynamic value, {
        double fallback = 1,
      }) {
    final double parsed = _safeDouble(
      value,
      fallback: fallback,
    );

    return parsed > 0 ? parsed : fallback;
  }

  static bool _boolean(
      dynamic value, {
        bool fallback = false,
      }) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    switch (value?.toString().trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'y':
        return true;

      case 'false':
      case '0':
      case 'no':
      case 'n':
        return false;

      default:
        return fallback;
    }
  }

  static DateTime _dateTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    if (value is num) {
      try {
        final int raw = value.toInt();
        final int absolute = raw.abs();

        if (absolute < 100000000000) {
          return DateTime.fromMillisecondsSinceEpoch(
            raw * 1000,
          );
        }

        if (absolute >= 100000000000000) {
          return DateTime.fromMicrosecondsSinceEpoch(raw);
        }

        return DateTime.fromMillisecondsSinceEpoch(raw);
      } on RangeError {
        return DateTime.fromMillisecondsSinceEpoch(
          0,
          isUtc: true,
        );
      } on ArgumentError {
        return DateTime.fromMillisecondsSinceEpoch(
          0,
          isUtc: true,
        );
      }
    }

    if (value != null) {
      try {
        final dynamic converted = value.toDate();

        if (converted is DateTime) {
          return converted;
        }
      } catch (_) {
        // Not Timestamp-compatible.
      }

      final String text = value.toString().trim();

      if (text.isNotEmpty) {
        final DateTime? parsed = DateTime.tryParse(text);

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return DateTime.fromMillisecondsSinceEpoch(
      0,
      isUtc: true,
    );
  }

  static DevicePlatform _devicePlatform(dynamic value) {
    if (value is num) {
      final int index = value.toInt();

      if (index >= 0 && index < DevicePlatform.values.length) {
        return DevicePlatform.values[index];
      }
    }

    final String raw =
        value?.toString().trim().toLowerCase() ?? '';

    if (raw.isEmpty) {
      return DevicePlatform.unknown;
    }

    final int dot = raw.lastIndexOf('.');

    final String normalized =
    dot >= 0 ? raw.substring(dot + 1) : raw;

    for (final DevicePlatform platform in DevicePlatform.values) {
      if (platform.name == normalized) {
        return platform;
      }
    }

    return DevicePlatform.unknown;
  }

  // =============================================================
  // OBJECT
  // =============================================================

  @override
  String toString() {
    return 'DeviceModel('
        'deviceId: $deviceId, '
        'deviceName: $deviceName, '
        'platform: ${platform.name}'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceModel &&
        other.deviceId == deviceId &&
        other.userId == userId &&
        other.platform == platform &&
        other.lastActive == lastActive;
  }

  @override
  int get hashCode {
    return Object.hash(
      deviceId,
      userId,
      platform,
      lastActive,
    );
  }
}