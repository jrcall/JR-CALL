import 'package:flutter/foundation.dart';

/// Current Call Status
enum CallConnectionState {
  idle,
  initializing,
  connecting,
  ringing,
  incoming,
  outgoing,
  connected,
  reconnecting,
  disconnected,
  ended,
  failed,
}

/// Current Network Quality
enum NetworkQuality { excellent, good, fair, poor, offline }

@immutable
class CallState {
  final CallConnectionState connectionState;

  final NetworkQuality networkQuality;

  final bool microphoneEnabled;

  final bool speakerEnabled;

  final bool bluetoothEnabled;

  final bool cameraEnabled;

  final bool frontCamera;

  final bool screenSharing;

  final bool recording;

  final bool aiVoiceEnabled;

  final bool aiVideoEnabled;

  final bool encrypted;

  final int duration;

  final String localUid;

  final String remoteUid;

  final String remoteName;

  final String remotePhoto;

  final double uploadBitrate;

  final double downloadBitrate;

  final int ping;

  const CallState({
    this.connectionState = CallConnectionState.idle,
    this.networkQuality = NetworkQuality.excellent,
    this.microphoneEnabled = true,
    this.speakerEnabled = false,
    this.bluetoothEnabled = false,
    this.cameraEnabled = true,
    this.frontCamera = true,
    this.screenSharing = false,
    this.recording = false,
    this.aiVoiceEnabled = true,
    this.aiVideoEnabled = true,
    this.encrypted = true,
    this.duration = 0,
    this.localUid = '',
    this.remoteUid = '',
    this.remoteName = '',
    this.remotePhoto = '',
    this.uploadBitrate = 0,
    this.downloadBitrate = 0,
    this.ping = 0,
  });

  CallState copyWith({
    CallConnectionState? connectionState,
    NetworkQuality? networkQuality,
    bool? microphoneEnabled,
    bool? speakerEnabled,
    bool? bluetoothEnabled,
    bool? cameraEnabled,
    bool? frontCamera,
    bool? screenSharing,
    bool? recording,
    bool? aiVoiceEnabled,
    bool? aiVideoEnabled,
    bool? encrypted,
    int? duration,
    String? localUid,
    String? remoteUid,
    String? remoteName,
    String? remotePhoto,
    double? uploadBitrate,
    double? downloadBitrate,
    int? ping,
  }) {
    return CallState(
      connectionState: connectionState ?? this.connectionState,
      networkQuality: networkQuality ?? this.networkQuality,
      microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
      speakerEnabled: speakerEnabled ?? this.speakerEnabled,
      bluetoothEnabled: bluetoothEnabled ?? this.bluetoothEnabled,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
      frontCamera: frontCamera ?? this.frontCamera,
      screenSharing: screenSharing ?? this.screenSharing,
      recording: recording ?? this.recording,
      aiVoiceEnabled: aiVoiceEnabled ?? this.aiVoiceEnabled,
      aiVideoEnabled: aiVideoEnabled ?? this.aiVideoEnabled,
      encrypted: encrypted ?? this.encrypted,
      duration: duration ?? this.duration,
      localUid: localUid ?? this.localUid,
      remoteUid: remoteUid ?? this.remoteUid,
      remoteName: remoteName ?? this.remoteName,
      remotePhoto: remotePhoto ?? this.remotePhoto,
      uploadBitrate: uploadBitrate ?? this.uploadBitrate,
      downloadBitrate: downloadBitrate ?? this.downloadBitrate,
      ping: ping ?? this.ping,
    );
  }

  bool get isConnected => connectionState == CallConnectionState.connected;

  bool get isCalling =>
      connectionState == CallConnectionState.connecting ||
      connectionState == CallConnectionState.ringing ||
      connectionState == CallConnectionState.outgoing ||
      connectionState == CallConnectionState.incoming;

  bool get hasEnded => connectionState == CallConnectionState.ended;

  bool get hasFailed => connectionState == CallConnectionState.failed;

  @override
  String toString() {
    return 'CallState('
        'connectionState: $connectionState, '
        'networkQuality: $networkQuality, '
        'duration: $duration'
        ')';
  }
}
