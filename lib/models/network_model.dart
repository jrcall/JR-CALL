// ===========================================================
// JR CALL
// File: network_model.dart
// Location: lib/models/network_model.dart
//
// FINAL PRODUCTION CONTRACT:
// - Existing enums, constructor fields and APIs preserved.
// - Network snapshot + media recommendation data only.
// - No connectivity detection ownership.
// - No ICE restart / handover ownership.
// - No bitrate-controller ownership.
// - Safe legacy/cache/Firestore-compatible parsing.
// - Invalid metrics normalized safely.
// - Stale/malformed timestamps never appear artificially fresh.
// ===========================================================

import 'dart:convert';

/// Network connection type.
enum NetworkType {
  wifi,
  mobile,
  ethernet,
  vpn,
  bluetooth,
  unknown,
}

/// Network quality classification.
enum NetworkQuality {
  excellent,
  good,
  fair,
  poor,
  offline,
}

/// Immutable snapshot of the current network state and the
/// media recommendations calculated from that state.
class NetworkModel {
  /// Primary/current connection type.
  final NetworkType type;

  /// Current network quality.
  final NetworkQuality quality;

  /// Whether usable internet connectivity is currently believed
  /// to be available.
  ///
  /// This must not be inferred from transport type alone.
  final bool isConnected;

  /// Estimated download speed in Mbps.
  final double downloadSpeed;

  /// Estimated upload speed in Mbps.
  final double uploadSpeed;

  /// Current round-trip latency in milliseconds.
  final int ping;

  /// Current jitter in milliseconds.
  final int jitter;

  /// Current packet-loss percentage, normalized to 0..100.
  final double packetLoss;

  /// Signal strength normalized to 0..100.
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

  // =============================================================
  // INITIAL
  // =============================================================

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

  // =============================================================
  // SEMANTIC HELPERS
  // =============================================================

  bool get isOffline =>
      !isConnected || quality == NetworkQuality.offline;

  bool get isOnline => !isOffline;

  bool get isWifi => type == NetworkType.wifi;

  bool get isCellular => type == NetworkType.mobile;

  bool get isDegraded =>
      quality == NetworkQuality.fair ||
          quality == NetworkQuality.poor ||
          quality == NetworkQuality.offline;

  bool get hasUsableMediaRecommendation =>
      recommendedBitrate > 0 &&
          recommendedFps > 0 &&
          videoWidth > 0 &&
          videoHeight > 0;

  bool isFresh(
      Duration maxAge, {
        DateTime? now,
      }) {
    final DateTime reference = now ?? DateTime.now();

    final Duration age = reference.difference(updatedAt);

    if (age.isNegative) {
      return false;
    }

    return age <= maxAge;
  }

  // =============================================================
  // COPY
  // =============================================================

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
      recommendedBitrate:
      recommendedBitrate ?? this.recommendedBitrate,
      recommendedFps:
      recommendedFps ?? this.recommendedFps,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // =============================================================
  // SERIALIZATION
  // =============================================================

  /// JSON-safe serialized map.
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
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Creates a model from serialized map data.
  ///
  /// Invalid or missing values fall back to safe defaults so stale
  /// cache / Firestore / legacy data cannot crash the Call Engine.
  factory NetworkModel.fromMap(
      Map<String, dynamic> map,
      ) {
    final bool connected = _boolValue(
      map['isConnected'],
      fallback: false,
    );

    final NetworkQuality parsedQuality =
    _networkQualityFromValue(
      map['quality'],
    );

    return NetworkModel(
      type: _networkTypeFromValue(
        map['type'],
      ),
      quality: connected
          ? parsedQuality
          : NetworkQuality.offline,
      isConnected: connected,
      downloadSpeed: _nonNegativeDouble(
        map['downloadSpeed'],
      ),
      uploadSpeed: _nonNegativeDouble(
        map['uploadSpeed'],
      ),
      ping: _nonNegativeInt(
        map['ping'],
        fallback: 999,
      ),
      jitter: _nonNegativeInt(
        map['jitter'],
        fallback: 999,
      ),
      packetLoss: _packetLoss(
        map['packetLoss'],
      ),
      signalStrength: _percentageInt(
        map['signalStrength'],
      ),
      recommendedBitrate: _positiveInt(
        map['recommendedBitrate'],
        fallback: 250000,
      ),
      recommendedFps: _positiveInt(
        map['recommendedFps'],
        fallback: 15,
      ),
      videoWidth: _positiveInt(
        map['videoWidth'],
        fallback: 640,
      ),
      videoHeight: _positiveInt(
        map['videoHeight'],
        fallback: 480,
      ),
      updatedAt: _dateTimeValue(
        map['updatedAt'],
      ),
    );
  }

  // =============================================================
  // JSON
  // =============================================================

  String toJson() {
    return jsonEncode(toMap());
  }

  factory NetworkModel.fromJson(String source) {
    final dynamic decoded = jsonDecode(source);

    if (decoded is Map<String, dynamic>) {
      return NetworkModel.fromMap(decoded);
    }

    if (decoded is Map) {
      final Map<String, dynamic> normalized =
      <String, dynamic>{};

      for (final MapEntry<dynamic, dynamic> entry
      in decoded.entries) {
        normalized[entry.key.toString()] =
            entry.value;
      }

      return NetworkModel.fromMap(normalized);
    }

    throw const FormatException(
      'NetworkModel JSON must contain an object.',
    );
  }

  // =============================================================
  // ENUM PARSING
  // =============================================================

  static NetworkType _networkTypeFromValue(
      dynamic value,
      ) {
    if (value is num) {
      final int index = value.toInt();

      if (index >= 0 &&
          index < NetworkType.values.length) {
        return NetworkType.values[index];
      }
    }

    final String normalized =
    _enumText(value);

    switch (normalized) {
      case 'wifi':
      case 'wireless':
      case 'wlan':
        return NetworkType.wifi;

      case 'mobile':
      case 'cellular':
      case 'cell':
      case 'lte':
      case '4g':
      case '5g':
        return NetworkType.mobile;

      case 'ethernet':
      case 'wired':
      case 'lan':
        return NetworkType.ethernet;

      case 'vpn':
        return NetworkType.vpn;

      case 'bluetooth':
        return NetworkType.bluetooth;

      default:
        return NetworkType.unknown;
    }
  }

  static NetworkQuality _networkQualityFromValue(
      dynamic value,
      ) {
    if (value is num) {
      final int index = value.toInt();

      if (index >= 0 &&
          index < NetworkQuality.values.length) {
        return NetworkQuality.values[index];
      }
    }

    switch (_enumText(value)) {
      case 'excellent':
        return NetworkQuality.excellent;

      case 'good':
        return NetworkQuality.good;

      case 'fair':
      case 'moderate':
        return NetworkQuality.fair;

      case 'poor':
      case 'bad':
      case 'weak':
        return NetworkQuality.poor;

      case 'offline':
      case 'none':
      case 'disconnected':
      default:
        return NetworkQuality.offline;
    }
  }

  static String _enumText(dynamic value) {
    final String raw =
        value?.toString().trim().toLowerCase() ?? '';

    if (raw.isEmpty) {
      return '';
    }

    final int dot = raw.lastIndexOf('.');

    final String normalized =
    dot >= 0
        ? raw.substring(dot + 1)
        : raw;

    return normalized
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll(' ', '');
  }

  // =============================================================
  // VALUE PARSING
  // =============================================================

  static bool _boolValue(
      dynamic value, {
        required bool fallback,
      }) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    switch (
    value?.toString().trim().toLowerCase()) {
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

  static int _intValue(
      dynamic value, {
        required int fallback,
      }) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      final String text = value.trim();

      return int.tryParse(text) ??
          double.tryParse(text)?.toInt() ??
          fallback;
    }

    return fallback;
  }

  static int _nonNegativeInt(
      dynamic value, {
        required int fallback,
      }) {
    final int parsed = _intValue(
      value,
      fallback: fallback,
    );

    return parsed < 0 ? 0 : parsed;
  }

  static int _positiveInt(
      dynamic value, {
        required int fallback,
      }) {
    final int parsed = _intValue(
      value,
      fallback: fallback,
    );

    return parsed > 0 ? parsed : fallback;
  }

  static int _percentageInt(dynamic value) {
    final int parsed = _intValue(
      value,
      fallback: 0,
    );

    if (parsed < 0) {
      return 0;
    }

    if (parsed > 100) {
      return 100;
    }

    return parsed;
  }

  static double _doubleValue(
      dynamic value, {
        required double fallback,
      }) {
    double? parsed;

    if (value is num) {
      parsed = value.toDouble();
    } else if (value is String) {
      parsed = double.tryParse(
        value.trim(),
      );
    }

    if (parsed == null ||
        parsed.isNaN ||
        parsed.isInfinite) {
      return fallback;
    }

    return parsed;
  }

  static double _nonNegativeDouble(
      dynamic value,
      ) {
    final double parsed = _doubleValue(
      value,
      fallback: 0,
    );

    return parsed < 0 ? 0 : parsed;
  }

  static double _packetLoss(dynamic value) {
    final double parsed = _doubleValue(
      value,
      fallback: 100,
    );

    if (parsed < 0) {
      return 0;
    }

    if (parsed > 100) {
      return 100;
    }

    return parsed;
  }

  // =============================================================
  // DATE PARSING
  // =============================================================

  static DateTime _dateTimeValue(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    if (value is num) {
      return _dateTimeFromNumber(value);
    }

    if (value != null) {
      try {
        final dynamic converted =
        value.toDate();

        if (converted is DateTime) {
          return converted;
        }
      } catch (_) {
        // Not Firestore Timestamp-compatible.
      }

      final String text =
      value.toString().trim();

      if (text.isNotEmpty) {
        final DateTime? parsed =
        DateTime.tryParse(text);

        if (parsed != null) {
          return parsed;
        }

        final num? numeric =
        num.tryParse(text);

        if (numeric != null) {
          return _dateTimeFromNumber(
            numeric,
          );
        }
      }
    }

    // Missing/stale data must not pretend to be current.
    return DateTime.fromMillisecondsSinceEpoch(
      0,
      isUtc: true,
    );
  }

  static DateTime _dateTimeFromNumber(
      num value,
      ) {
    try {
      final int raw = value.toInt();
      final int absolute = raw.abs();

      // Seconds since epoch.
      if (absolute < 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(
          raw * 1000,
        );
      }

      // Microseconds since epoch.
      if (absolute >= 100000000000000) {
        return DateTime.fromMicrosecondsSinceEpoch(
          raw,
        );
      }

      // Milliseconds since epoch.
      return DateTime.fromMillisecondsSinceEpoch(
        raw,
      );
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

  // =============================================================
  // OBJECT
  // =============================================================

  @override
  String toString() {
    return 'NetworkModel('
        'type: ${type.name}, '
        'quality: ${quality.name}, '
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
        other.signalStrength ==
            signalStrength &&
        other.recommendedBitrate ==
            recommendedBitrate &&
        other.recommendedFps ==
            recommendedFps &&
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