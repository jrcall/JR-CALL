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
  });

  Map<String, dynamic> toMap() {
    return {
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
    };
  }

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      callId: map["callId"],
      callerId: map["callerId"],
      callerName: map["callerName"],
      callerNumber: map["callerNumber"],
      receiverId: map["receiverId"],
      receiverName: map["receiverName"],
      receiverNumber: map["receiverNumber"],
      video: map["video"] ?? false,
      status: CallStatus.values.firstWhere(
        (e) => e.name == map["status"],
        orElse: () => CallStatus.calling,
      ),
      createdAt: (map["createdAt"] as Timestamp).toDate(),
    );
  }
}
