import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/call_status.dart';

class CallModel {
  final String callId;

  final String callerId;
  final String callerName;
  final String callerNumber;

  final String receiverId;
  final String receiverName;
  final String receiverNumber;

  final bool video;
  final CallStatus status;

  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? ringingAt;
  final DateTime? acceptedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final DateTime? expiresAt;

  final String? endedBy;
  final String? originDeviceId;
  final String? answeredByDeviceId;
  final String? failureReason;

  final int revision;
  final int schemaVersion;

  const CallModel({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerNumber,
    required this.receiverId,
    required this.receiverName,
    required this.receiverNumber,
    required this.video,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.ringingAt,
    this.acceptedAt,
    this.connectedAt,
    this.endedAt,
    this.expiresAt,
    this.endedBy,
    this.originDeviceId,
    this.answeredByDeviceId,
    this.failureReason,
    this.revision = 0,
    this.schemaVersion = 1,
  });

  String get callerUid => callerId;

  String get receiverUid => receiverId;

  bool get isVideo => video;

  bool get isAudio => !video;

  bool get isTerminal {
    return switch (status) {
      CallStatus.rejected ||
      CallStatus.ended ||
      CallStatus.missed ||
      CallStatus.busy ||
      CallStatus.cancelled ||
      CallStatus.failed =>
      true,
      _ => false,
    };
  }

  bool get isActive => !isTerminal;

  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{
      "callId": callId,
      "callerId": callerId,
      "callerName": callerName,
      "callerNumber": callerNumber,
      "receiverId": receiverId,
      "receiverName": receiverName,
      "receiverNumber": receiverNumber,
      "video": video,
      "status": status.name,
      "createdAt": Timestamp.fromDate(createdAt),
      "updatedAt":
      updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      "ringingAt":
      ringingAt == null ? null : Timestamp.fromDate(ringingAt!),
      "acceptedAt":
      acceptedAt == null ? null : Timestamp.fromDate(acceptedAt!),
      "connectedAt":
      connectedAt == null ? null : Timestamp.fromDate(connectedAt!),
      "endedAt": endedAt == null ? null : Timestamp.fromDate(endedAt!),
      "expiresAt":
      expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
      "endedBy": endedBy,
      "originDeviceId": originDeviceId,
      "answeredByDeviceId": answeredByDeviceId,
      "failureReason": failureReason,
      "revision": revision,
      "schemaVersion": schemaVersion,
    };

    data.removeWhere((_, value) => value == null);

    return data;
  }

  factory CallModel.fromMap(
      Map<String, dynamic> map, {
        String? documentId,
      }) {
    final callId = _requiredString(
      map["callId"],
      fieldName: "callId",
      fallback: documentId,
    );

    final callerId = _requiredString(
      map["callerId"] ?? map["callerUid"],
      fieldName: "callerId",
    );

    final receiverId = _requiredString(
      map["receiverId"] ?? map["receiverUid"] ?? map["calleeUid"],
      fieldName: "receiverId",
    );

    final createdAt = _requiredDateTime(
      map["createdAt"],
      fieldName: "createdAt",
    );

    return CallModel(
      callId: callId,
      callerId: callerId,
      callerName: _stringOrEmpty(map["callerName"]),
      callerNumber: _stringOrEmpty(map["callerNumber"]),
      receiverId: receiverId,
      receiverName: _stringOrEmpty(map["receiverName"]),
      receiverNumber: _stringOrEmpty(map["receiverNumber"]),
      video: map["video"] == true,
      status: _statusFromValue(map["status"]),
      createdAt: createdAt,
      updatedAt: _dateTimeOrNull(map["updatedAt"]),
      ringingAt: _dateTimeOrNull(map["ringingAt"]),
      acceptedAt: _dateTimeOrNull(map["acceptedAt"]),
      connectedAt: _dateTimeOrNull(map["connectedAt"]),
      endedAt: _dateTimeOrNull(map["endedAt"]),
      expiresAt: _dateTimeOrNull(map["expiresAt"]),
      endedBy: _nullableString(map["endedBy"]),
      originDeviceId: _nullableString(map["originDeviceId"]),
      answeredByDeviceId: _nullableString(map["answeredByDeviceId"]),
      failureReason: _nullableString(map["failureReason"]),
      revision: _intOrDefault(map["revision"], 0),
      schemaVersion: _intOrDefault(map["schemaVersion"], 1),
    );
  }

  CallModel copyWith({
    String? callId,
    String? callerId,
    String? callerName,
    String? callerNumber,
    String? receiverId,
    String? receiverName,
    String? receiverNumber,
    bool? video,
    CallStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? ringingAt,
    DateTime? acceptedAt,
    DateTime? connectedAt,
    DateTime? endedAt,
    DateTime? expiresAt,
    String? endedBy,
    String? originDeviceId,
    String? answeredByDeviceId,
    String? failureReason,
    int? revision,
    int? schemaVersion,
  }) {
    return CallModel(
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      callerNumber: callerNumber ?? this.callerNumber,
      receiverId: receiverId ?? this.receiverId,
      receiverName: receiverName ?? this.receiverName,
      receiverNumber: receiverNumber ?? this.receiverNumber,
      video: video ?? this.video,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ringingAt: ringingAt ?? this.ringingAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      endedBy: endedBy ?? this.endedBy,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      answeredByDeviceId:
      answeredByDeviceId ?? this.answeredByDeviceId,
      failureReason: failureReason ?? this.failureReason,
      revision: revision ?? this.revision,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  static String _requiredString(
      dynamic value, {
        required String fieldName,
        String? fallback,
      }) {
    final candidate = value is String && value.trim().isNotEmpty
        ? value.trim()
        : fallback?.trim();

    if (candidate == null || candidate.isEmpty) {
      throw FormatException("Missing or invalid $fieldName");
    }

    return candidate;
  }

  static String _stringOrEmpty(dynamic value) {
    if (value is! String) {
      return "";
    }

    return value.trim();
  }

  static String? _nullableString(dynamic value) {
    if (value is! String) {
      return null;
    }

    final cleaned = value.trim();

    return cleaned.isEmpty ? null : cleaned;
  }

  static DateTime _requiredDateTime(
      dynamic value, {
        required String fieldName,
      }) {
    final parsed = _dateTimeOrNull(value);

    if (parsed == null) {
      throw FormatException("Missing or invalid $fieldName");
    }

    return parsed;
  }

  static DateTime? _dateTimeOrNull(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  static int _intOrDefault(dynamic value, int fallback) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return fallback;
  }

  static CallStatus _statusFromValue(dynamic value) {
    if (value is String) {
      for (final status in CallStatus.values) {
        if (status.name == value) {
          return status;
        }
      }
    }

    if (value is num) {
      final index = value.toInt();

      if (index >= 0 && index < CallStatus.values.length) {
        return CallStatus.values[index];
      }
    }

    return CallStatus.calling;
  }
}