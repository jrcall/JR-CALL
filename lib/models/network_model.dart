// ===========================================================
// JR CALL
// File: network_model.dart
// Location: lib/models/network_model.dart
//
// Description:
// Stores current network information used by
// AI Call Engine, Video Engine and Bitrate Controller.
// ===========================================================

import 'dart:convert';

/// Network connection type.
enum NetworkType { wifi, mobile, ethernet, vpn, bluetooth, unknown }

/// Network quality classification.
enum NetworkQuality { excellent, good, fair, poor, offline }

/// Immutable snapshot of the current network state and the
/// media recommendations calculated from that state.
class NetworkModel {
  /// Connection type.
  final NetworkType type;

  /// Current network quality.
  final NetworkQuality quality;

  /// Whether internet connectivity is currently available.
  final bool isConnected;

  /// Estimated download speed in Mbps.
  final double downloadSpeed;

  /// Estimated upload speed in Mbps.
  final double uploadSpeed;

  /// Current round-trip latency in milliseconds.
  final int ping;

  /// Current jitter in milliseconds.
  final int jitter;

  /// Current packet loss percentage.
  final double packetLoss;

  /// Signal strength from 0 to 100.
  final int signalStrength;

  /// Recommended media bitrate in bits per second.
  final int recommendedBitrate;

  /// Recommended video frame rate.
  final int recommendedFps;

  /// Recommended video width.
  final int videoWidth;

  /// Recommended video height.
  final int videoHeight;

  /// Time when this network snapshot was last updated.
  final DateTime updatedAt;

  const NetworkModel({
    required this.type,
    required this.quality,
    required this.isConnected,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.ping,
    required this.jitter,
    required this.packetLoss,
    required this.signalStrength,
    required this.recommendedBitrate,
    required this.recommendedFps,
    required this.videoWidth,
    required this.videoHeight,
    required this.updatedAt,
  });

  /// Creates the safe initial/offline network state.
  factory NetworkModel.initial() {
    return NetworkModel(
      type: NetworkType.unknown,
      quality: NetworkQuality.offline,
      isConnected: false,
      downloadSpeed: 0.0,
      uploadSpeed: 0.0,
      ping: 999,
      jitter: 999,
      packetLoss: 100.0,
      signalStrength: 0,
      recommendedBitrate: 250000,
      recommendedFps: 15,
      videoWidth: 640,
      videoHeight: 480,
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a modified immutable copy.
  NetworkModel copyWith({
    NetworkType? type,
    NetworkQuality? quality,
    bool? isConnected,
    double? downloadSpeed,
    double? uploadSpeed,
    int? ping,
    int? jitter,
    double? packetLoss,
    int? signalStrength,
    int? recommendedBitrate,
    int? recommendedFps,
    int? videoWidth,
    int? videoHeight,
    DateTime? updatedAt,
  }) {
    return NetworkModel(
      type: type ?? this.type,
      quality: quality ?? this.quality,
      isConnected: isConnected ?? this.isConnected,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      ping: ping ?? this.ping,
      jitter: jitter ?? this.jitter,
      packetLoss: packetLoss ?? this.packetLoss,
      signalStrength: signalStrength ?? this.signalStrength,
      recommendedBitrate: recommendedBitrate ?? this.recommendedBitrate,
      recommendedFps: recommendedFps ?? this.recommendedFps,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Converts this model into a serializable map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.name,
      'quality': quality.name,
      'isConnected': isConnected,
      'downloadSpeed': downloadSpeed,
      'uploadSpeed': uploadSpeed,
      'ping': ping,
      'jitter': jitter,
      'packetLoss': packetLoss,
      'signalStrength': signalStrength,
      'recommendedBitrate': recommendedBitrate,
      'recommendedFps': recommendedFps,
      'videoWidth': videoWidth,
      'videoHeight': videoHeight,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Creates a model from serialized map data.
  ///
  /// Invalid or missing values fall back to safe defaults so that
  /// stale Firestore/cache data does not crash the call engine.
  factory NetworkModel.fromMap(Map<String, dynamic> map) {
    return NetworkModel(
      type: _networkTypeFromValue(map['type']),
      quality: _networkQualityFromValue(map['quality']),
      isConnected: _boolValue(map['isConnected'], fallback: false),
      downloadSpeed: _doubleValue(map['downloadSpeed'], fallback: 0.0),
      uploadSpeed: _doubleValue(map['uploadSpeed'], fallback: 0.0),
      ping: _intValue(map['ping'], fallback: 999),
      jitter: _intValue(map['jitter'], fallback: 999),
      packetLoss: _doubleValue(map['packetLoss'], fallback: 100.0),
      signalStrength: _intValue(map['signalStrength'], fallback: 0),
      recommendedBitrate: _intValue(
        map['recommendedBitrate'],
        fallback: 250000,
      ),
      recommendedFps: _intValue(map['recommendedFps'], fallback: 15),
      videoWidth: _intValue(map['videoWidth'], fallback: 640),
      videoHeight: _intValue(map['videoHeight'], fallback: 480),
      updatedAt: _dateTimeValue(map['updatedAt']),
    );
  }

  /// Converts this model into JSON.
  String toJson() {
    return jsonEncode(toMap());
  }

  /// Creates a model from JSON.
  ///
  /// A valid JSON object is expected. Invalid JSON still throws a
  /// [FormatException], allowing storage/network layers to detect
  /// corrupted payloads instead of silently hiding them.
  factory NetworkModel.fromJson(String source) {
    final dynamic decoded = jsonDecode(source);

    if (decoded is! Map) {
      throw const FormatException('NetworkModel JSON must contain an object.');
    }

    return NetworkModel.fromMap(Map<String, dynamic>.from(decoded));
  }

  static NetworkType _networkTypeFromValue(dynamic value) {
    final String normalized = value?.toString().trim().toLowerCase() ?? '';

    for (final NetworkType type in NetworkType.values) {
      if (type.name == normalized) {
        return type;
      }
    }

    return NetworkType.unknown;
  }

  static NetworkQuality _networkQualityFromValue(dynamic value) {
    final String normalized = value?.toString().trim().toLowerCase() ?? '';

    for (final NetworkQuality quality in NetworkQuality.values) {
      if (quality.name == normalized) {
        return quality;
      }
    }

    return NetworkQuality.offline;
  }

  static bool _boolValue(dynamic value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
          return true;

        case 'false':
        case '0':
        case 'no':
          return false;
      }
    }

    return fallback;
  }

  static int _intValue(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value.trim()) ??
          double.tryParse(value.trim())?.toInt() ??
          fallback;
    }

    return fallback;
  }

  static double _doubleValue(dynamic value, {required double fallback}) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.trim()) ?? fallback;
    }

    return fallback;
  }

  static DateTime _dateTimeValue(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);

      if (parsed != null) {
        return parsed;
      }
    }

    if (value is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } on ArgumentError {
        // Fall through to the safe current-time value.
      }
    }

    return DateTime.now();
  }

  @override
  String toString() {
    return 'NetworkModel('
        'type: $type, '
        'quality: $quality, '
        'connected: $isConnected, '
        'download: $downloadSpeed Mbps, '
        'upload: $uploadSpeed Mbps, '
        'ping: $ping ms, '
        'jitter: $jitter ms, '
        'packetLoss: $packetLoss%, '
        'signalStrength: $signalStrength, '
        'recommendedBitrate: $recommendedBitrate, '
        'recommendedFps: $recommendedFps, '
        'video: ${videoWidth}x$videoHeight, '
        'updatedAt: $updatedAt'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is NetworkModel &&
        other.type == type &&
        other.quality == quality &&
        other.isConnected == isConnected &&
        other.downloadSpeed == downloadSpeed &&
        other.uploadSpeed == uploadSpeed &&
        other.ping == ping &&
        other.jitter == jitter &&
        other.packetLoss == packetLoss &&
        other.signalStrength == signalStrength &&
        other.recommendedBitrate == recommendedBitrate &&
        other.recommendedFps == recommendedFps &&
        other.videoWidth == videoWidth &&
        other.videoHeight == videoHeight &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      type,
      quality,
      isConnected,
      downloadSpeed,
      uploadSpeed,
      ping,
      jitter,
      packetLoss,
      signalStrength,
      recommendedBitrate,
      recommendedFps,
      videoWidth,
      videoHeight,
      updatedAt,
    );
  }
}
