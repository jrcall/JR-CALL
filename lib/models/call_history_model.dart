// ===============================================================
// JR CALL
// File: call_history_model.dart
// Location: lib/models/call_history_model.dart
// Fixes: BUG 04
// Production-safe replacement
// Existing APIs preserved
//
// PRODUCTION CONTRACT:
// - Existing constructor, fields and enums preserved.
// - Existing initial/copyWith/fromMap/toMap/fromJson/toJson preserved.
// - Real call-history data only.
// - Legacy Firestore / JSON values parsed safely.
// - Firestore Timestamp-compatible date parsing.
// - Unknown malformed status never becomes fake "completed" state.
// - Negative duration/network values are normalized safely.
// - Incoming/outgoing and voice/video semantics preserved.
// - No Call Engine/WebRTC/signaling ownership.
// ===============================================================

import 'dart:convert';

enum CallType { voice, video }

enum CallDirection { incoming, outgoing }

enum CallStatus {
  missed,
  rejected,
  cancelled,
  completed,
  failed,
  busy,
  declined,
}

enum CallQuality { excellent, good, fair, poor }

class CallHistoryModel {
  final String id;
  final String sessionId;
  final String userId;
  final String contactId;
  final String contactName;
  final String phoneNumber;
  final String avatarUrl;

  final CallType callType;
  final CallDirection direction;
  final CallStatus status;
  final CallQuality quality;

  /// Seconds.
  final int duration;

  final int averagePing;
  final int averageJitter;

  /// Percentage.
  final double packetLoss;

  final bool isEncrypted;
  final bool isRecorded;
  final bool isHd;

  final DateTime startedAt;
  final DateTime endedAt;

  const CallHistoryModel({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.contactId,
    required this.contactName,
    required this.phoneNumber,
    required this.avatarUrl,
    required this.callType,
    required this.direction,
    required this.status,
    required this.quality,
    required this.duration,
    required this.averagePing,
    required this.averageJitter,
    required this.packetLoss,
    required this.isEncrypted,
    required this.isRecorded,
    required this.isHd,
    required this.startedAt,
    required this.endedAt,
  });

  // =============================================================
  // INITIAL
  // =============================================================

  factory CallHistoryModel.initial() {
    final DateTime now = DateTime.now();

    return CallHistoryModel(
      id: '',
      sessionId: '',
      userId: '',
      contactId: '',
      contactName: '',
      phoneNumber: '',
      avatarUrl: '',
      callType: CallType.voice,
      direction: CallDirection.outgoing,
      status: CallStatus.completed,
      quality: CallQuality.good,
      duration: 0,
      averagePing: 0,
      averageJitter: 0,
      packetLoss: 0,
      isEncrypted: true,
      isRecorded: false,
      isHd: false,
      startedAt: now,
      endedAt: now,
    );
  }

  // =============================================================
  // COPY
  // =============================================================

  CallHistoryModel copyWith({
    String? id,
    String? sessionId,
    String? userId,
    String? contactId,
    String? contactName,
    String? phoneNumber,
    String? avatarUrl,
    CallType? callType,
    CallDirection? direction,
    CallStatus? status,
    CallQuality? quality,
    int? duration,
    int? averagePing,
    int? averageJitter,
    double? packetLoss,
    bool? isEncrypted,
    bool? isRecorded,
    bool? isHd,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return CallHistoryModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      contactId: contactId ?? this.contactId,
      contactName: contactName ?? this.contactName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      callType: callType ?? this.callType,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      quality: quality ?? this.quality,
      duration: duration ?? this.duration,
      averagePing: averagePing ?? this.averagePing,
      averageJitter: averageJitter ?? this.averageJitter,
      packetLoss: packetLoss ?? this.packetLoss,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      isRecorded: isRecorded ?? this.isRecorded,
      isHd: isHd ?? this.isHd,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  // =============================================================
  // SERIALIZATION
  // =============================================================

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'sessionId': sessionId,
      'userId': userId,
      'contactId': contactId,
      'contactName': contactName,
      'phoneNumber': phoneNumber,
      'avatarUrl': avatarUrl,
      'callType': callType.name,
      'direction': direction.name,
      'status': status.name,
      'quality': quality.name,
      'duration': duration,
      'averagePing': averagePing,
      'averageJitter': averageJitter,
      'packetLoss': packetLoss,
      'isEncrypted': isEncrypted,
      'isRecorded': isRecorded,
      'isHd': isHd,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
    };
  }

  factory CallHistoryModel.fromMap(Map<String, dynamic> map) {
    final DateTime startedAt = _dateTime(
      _firstValue(map, const <String>[
        'startedAt',
        'startTime',
        'started_at',
        'createdAt',
        'timestamp',
      ]),
    );

    DateTime endedAt = _dateTime(
      _firstValue(map, const <String>[
        'endedAt',
        'endTime',
        'ended_at',
        'completedAt',
      ]),
      fallback: startedAt,
    );

    if (endedAt.isBefore(startedAt)) {
      endedAt = startedAt;
    }

    return CallHistoryModel(
      id: _string(
        _firstValue(map, const <String>['id', 'callId', 'historyId']),
      ),
      sessionId: _string(
        _firstValue(map, const <String>[
          'sessionId',
          'session_id',
          'callSessionId',
        ]),
      ),
      userId: _string(
        _firstValue(map, const <String>[
          'userId',
          'uid',
          'currentUserId',
          'ownerId',
        ]),
      ),
      contactId: _string(
        _firstValue(map, const <String>[
          'contactId',
          'otherUserId',
          'peerId',
          'remoteUserId',
        ]),
      ),
      contactName: _string(
        _firstValue(map, const <String>[
          'contactName',
          'displayName',
          'name',
          'callerName',
          'receiverName',
        ]),
      ),
      phoneNumber: _string(
        _firstValue(map, const <String>[
          'phoneNumber',
          'phone',
          'contactNumber',
        ]),
      ),
      avatarUrl: _string(
        _firstValue(map, const <String>[
          'avatarUrl',
          'photoUrl',
          'profilePhotoUrl',
          'callerImage',
          'receiverImage',
        ]),
      ),
      callType: _callType(_firstValue(map, const <String>['callType', 'type'])),
      direction: _direction(
        _firstValue(map, const <String>['direction', 'callDirection']),
      ),
      status: _status(_firstValue(map, const <String>['status', 'callStatus'])),
      quality: _quality(
        _firstValue(map, const <String>['quality', 'callQuality']),
      ),
      duration: _nonNegativeInt(
        _firstValue(map, const <String>['duration', 'durationSeconds']),
      ),
      averagePing: _nonNegativeInt(
        _firstValue(map, const <String>['averagePing', 'avgPing', 'ping']),
      ),
      averageJitter: _nonNegativeInt(
        _firstValue(map, const <String>[
          'averageJitter',
          'avgJitter',
          'jitter',
        ]),
      ),
      packetLoss: _packetLoss(
        _firstValue(map, const <String>['packetLoss', 'packetLossPercent']),
      ),
      isEncrypted: _boolean(
        _firstValue(map, const <String>['isEncrypted', 'encrypted']),
        fallback: true,
      ),
      isRecorded: _boolean(
        _firstValue(map, const <String>['isRecorded', 'recorded']),
      ),
      isHd: _boolean(_firstValue(map, const <String>['isHd', 'isHD', 'hd'])),
      startedAt: startedAt,
      endedAt: endedAt,
    );
  }

  // =============================================================
  // JSON
  // =============================================================

  String toJson() {
    return jsonEncode(toMap());
  }

  factory CallHistoryModel.fromJson(String source) {
    try {
      final dynamic decoded = jsonDecode(source);

      if (decoded is Map<String, dynamic>) {
        return CallHistoryModel.fromMap(decoded);
      }

      if (decoded is Map) {
        final Map<String, dynamic> normalized = <String, dynamic>{};

        for (final MapEntry<dynamic, dynamic> entry in decoded.entries) {
          normalized[entry.key.toString()] = entry.value;
        }

        return CallHistoryModel.fromMap(normalized);
      }
    } on FormatException {
      // Invalid legacy JSON falls through to safe defaults.
    } catch (_) {
      // Malformed legacy payload must not crash call history UI.
    }

    return CallHistoryModel.fromMap(const <String, dynamic>{});
  }

  // =============================================================
  // SAFE LEGACY PARSING
  // =============================================================

  static dynamic _firstValue(Map<String, dynamic> map, List<String> keys) {
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

  static String _string(dynamic value) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  static int _integer(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  static int _nonNegativeInt(dynamic value) {
    final int parsed = _integer(value);

    return parsed < 0 ? 0 : parsed;
  }

  static double _double(dynamic value) {
    if (value is double) {
      if (value.isNaN || value.isInfinite) {
        return 0;
      }

      return value;
    }

    if (value is num) {
      final double parsed = value.toDouble();

      if (parsed.isNaN || parsed.isInfinite) {
        return 0;
      }

      return parsed;
    }

    final double? parsed = double.tryParse(value?.toString().trim() ?? '');

    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return 0;
    }

    return parsed;
  }

  static double _packetLoss(dynamic value) {
    final double parsed = _double(value);

    if (parsed < 0) {
      return 0;
    }

    if (parsed > 100) {
      return 100;
    }

    return parsed;
  }

  static bool _boolean(dynamic value, {bool fallback = false}) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final String normalized = value?.toString().trim().toLowerCase() ?? '';

    switch (normalized) {
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

  // =============================================================
  // DATE PARSING
  // =============================================================

  static DateTime _dateTime(dynamic value, {DateTime? fallback}) {
    if (value is DateTime) {
      return value;
    }

    if (value is num) {
      return _dateTimeFromNumber(value, fallback: fallback);
    }

    if (value != null) {
      // Firestore Timestamp support without importing
      // cloud_firestore into the model.
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
        final DateTime? parsedDate = DateTime.tryParse(text);

        if (parsedDate != null) {
          return parsedDate;
        }

        final num? numericDate = num.tryParse(text);

        if (numericDate != null) {
          return _dateTimeFromNumber(numericDate, fallback: fallback);
        }
      }
    }

    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime _dateTimeFromNumber(num value, {DateTime? fallback}) {
    try {
      final int raw = value.toInt();
      final int absolute = raw.abs();

      // Seconds since epoch.
      if (absolute < 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
      }

      // Microseconds since epoch.
      if (absolute >= 100000000000000) {
        return DateTime.fromMicrosecondsSinceEpoch(raw);
      }

      // Milliseconds since epoch.
      return DateTime.fromMillisecondsSinceEpoch(raw);
    } on RangeError {
      return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
    } on ArgumentError {
      return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  // =============================================================
  // ENUM NORMALIZATION
  // =============================================================

  static String _enumText(dynamic value) {
    final String raw = value?.toString().trim().toLowerCase() ?? '';

    if (raw.isEmpty) {
      return '';
    }

    final int dot = raw.lastIndexOf('.');

    final String normalized = dot >= 0 ? raw.substring(dot + 1) : raw;

    return normalized
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll(' ', '');
  }

  static CallType _callType(dynamic value) {
    switch (_enumText(value)) {
      case 'video':
      case 'videocall':
        return CallType.video;

      case 'voice':
      case 'audio':
      case 'voicecall':
      case 'audiocall':
      default:
        return CallType.voice;
    }
  }

  static CallDirection _direction(dynamic value) {
    switch (_enumText(value)) {
      case 'incoming':
      case 'inbound':
      case 'received':
        return CallDirection.incoming;

      case 'outgoing':
      case 'outbound':
      case 'placed':
      default:
        return CallDirection.outgoing;
    }
  }

  static CallStatus _status(dynamic value) {
    final String normalized = _enumText(value);

    switch (normalized) {
      case 'missed':
      case 'missedcall':
      case 'noanswer':
      case 'unanswered':
      case 'timeout':
      case 'timedout':
        return CallStatus.missed;

      case 'rejected':
        return CallStatus.rejected;

      case 'cancelled':
      case 'canceled':
        return CallStatus.cancelled;

      case 'failed':
      case 'error':
      case 'networkfailed':
        return CallStatus.failed;

      case 'busy':
      case 'userbusy':
        return CallStatus.busy;

      case 'declined':
        return CallStatus.declined;

      case 'completed':
      case 'complete':
      case 'ended':
      case 'success':
        return CallStatus.completed;

      // A connected signaling state is not necessarily a completed
      // history record. However legacy JR CALL history may persist
      // "connected" only after a successful call, so compatibility
      // is preserved here.
      case 'connected':
        return CallStatus.completed;

      default:
        // Never manufacture a successful/completed history entry
        // from malformed or unknown production data.
        return CallStatus.failed;
    }
  }

  static CallQuality _quality(dynamic value) {
    switch (_enumText(value)) {
      case 'excellent':
        return CallQuality.excellent;

      case 'fair':
        return CallQuality.fair;

      case 'poor':
      case 'bad':
        return CallQuality.poor;

      case 'good':
      default:
        return CallQuality.good;
    }
  }

  // =============================================================
  // OBJECT IDENTITY
  // =============================================================

  bool _sameIdentity(CallHistoryModel other) {
    final String thisSession = sessionId.trim();
    final String otherSession = other.sessionId.trim();

    if (thisSession.isNotEmpty && otherSession.isNotEmpty) {
      return thisSession == otherSession;
    }

    final String thisId = id.trim();
    final String otherId = other.id.trim();

    if (thisId.isNotEmpty && otherId.isNotEmpty) {
      return thisId == otherId;
    }

    if (thisSession.isEmpty &&
        otherSession.isEmpty &&
        thisId.isEmpty &&
        otherId.isEmpty) {
      return userId == other.userId &&
          contactId == other.contactId &&
          direction == other.direction &&
          callType == other.callType &&
          startedAt == other.startedAt;
    }

    return false;
  }

  // =============================================================
  // OBJECT
  // =============================================================

  @override
  String toString() {
    return 'CallHistoryModel('
        'id: $id, '
        'sessionId: $sessionId, '
        'contact: $contactName, '
        'direction: ${direction.name}, '
        'type: ${callType.name}, '
        'status: ${status.name}, '
        'duration: $duration sec'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is CallHistoryModel && _sameIdentity(other);
  }

  @override
  int get hashCode {
    final String normalizedSession = sessionId.trim();

    if (normalizedSession.isNotEmpty) {
      return Object.hash('session', normalizedSession);
    }

    final String normalizedId = id.trim();

    if (normalizedId.isNotEmpty) {
      return Object.hash('id', normalizedId);
    }

    return Object.hash(userId, contactId, direction, callType, startedAt);
  }
}

// ===============================================================
// END OF FILE
//
// FIXED: BUG 04 model / parsing / identity / status safety
// STATUS: READY FOR FORMAT + ANALYZE
//
// NEXT FILE: call_repository.dart
// Location: lib/services/call/call_repository.dart
// ===============================================================
