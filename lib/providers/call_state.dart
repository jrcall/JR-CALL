import 'package:flutter/foundation.dart';

/// ===========================================================
/// JR CALL
/// File: call_state.dart
/// Location: lib/providers/call_state.dart
///
/// MASTER IMMUTABLE CALL PRESENTATION STATE
///
/// Responsibilities:
/// - Provider/UI call-state snapshot
/// - Media-control presentation state
/// - Network-quality presentation state
/// - Remote-user presentation state
/// - Call statistics presentation state
/// - Safe immutable state copying
/// - Derived lifecycle helpers
/// - Value equality / diagnostics
///
/// IMPORTANT:
/// - This file does NOT control CallService.
/// - This file does NOT control WebRTC.
/// - This file does NOT control signaling.
/// - This file does NOT control ICE.
/// - This file does NOT control recovery.
/// - This file does NOT mutate media managers.
/// - This file does NOT replace canonical CallStatus.
///
/// CallConnectionState is provider/UI state only.
/// ===========================================================

/// ===========================================================
/// CURRENT CALL CONNECTION STATE
/// ===========================================================

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

/// ===========================================================
/// CURRENT NETWORK QUALITY
///
/// Provider/UI presentation state only.
/// Actual monitoring remains NetworkManager / quality layer-owned.
/// ===========================================================

enum NetworkQuality {
  excellent,
  good,
  fair,
  poor,
  offline,
}

/// ===========================================================
/// IMMUTABLE CALL STATE
/// ===========================================================

@immutable
class CallState {
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

  // ===========================================================
  // LIFECYCLE STATE
  // ===========================================================

  final CallConnectionState connectionState;

  // ===========================================================
  // NETWORK STATE
  // ===========================================================

  final NetworkQuality networkQuality;

  // ===========================================================
  // AUDIO STATE
  // ===========================================================

  final bool microphoneEnabled;

  final bool speakerEnabled;

  final bool bluetoothEnabled;

  // ===========================================================
  // VIDEO STATE
  // ===========================================================

  final bool cameraEnabled;

  final bool frontCamera;

  final bool screenSharing;

  // ===========================================================
  // RECORDING / AI / SECURITY STATE
  // ===========================================================

  final bool recording;

  final bool aiVoiceEnabled;

  final bool aiVideoEnabled;

  final bool encrypted;

  // ===========================================================
  // CALL DURATION
  ///
  /// Stored in seconds.
  /// The authoritative timer remains CallTimer/CallService-owned.
  // ===========================================================

  final int duration;

  // ===========================================================
  // PARTICIPANT STATE
  // ===========================================================

  final String localUid;

  final String remoteUid;

  final String remoteName;

  final String remotePhoto;

  // ===========================================================
  // NETWORK / MEDIA STATISTICS
  // ===========================================================

  final double uploadBitrate;

  final double downloadBitrate;

  final int ping;

  // ===========================================================
  // COPY
  // ===========================================================

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
      connectionState:
      connectionState ?? this.connectionState,
      networkQuality:
      networkQuality ?? this.networkQuality,
      microphoneEnabled:
      microphoneEnabled ?? this.microphoneEnabled,
      speakerEnabled:
      speakerEnabled ?? this.speakerEnabled,
      bluetoothEnabled:
      bluetoothEnabled ?? this.bluetoothEnabled,
      cameraEnabled:
      cameraEnabled ?? this.cameraEnabled,
      frontCamera:
      frontCamera ?? this.frontCamera,
      screenSharing:
      screenSharing ?? this.screenSharing,
      recording:
      recording ?? this.recording,
      aiVoiceEnabled:
      aiVoiceEnabled ?? this.aiVoiceEnabled,
      aiVideoEnabled:
      aiVideoEnabled ?? this.aiVideoEnabled,
      encrypted:
      encrypted ?? this.encrypted,
      duration:
      duration ?? this.duration,
      localUid:
      localUid ?? this.localUid,
      remoteUid:
      remoteUid ?? this.remoteUid,
      remoteName:
      remoteName ?? this.remoteName,
      remotePhoto:
      remotePhoto ?? this.remotePhoto,
      uploadBitrate:
      uploadBitrate ?? this.uploadBitrate,
      downloadBitrate:
      downloadBitrate ?? this.downloadBitrate,
      ping:
      ping ?? this.ping,
    );
  }

  // ===========================================================
  // EXISTING LIFECYCLE HELPERS
  // ===========================================================

  bool get isConnected =>
      connectionState ==
          CallConnectionState.connected;

  /// Existing compatibility behavior preserved.
  ///
  /// This means the call is currently in the
  /// dialing/ringing/incoming setup phase.
  bool get isCalling =>
      connectionState ==
          CallConnectionState.connecting ||
          connectionState ==
              CallConnectionState.ringing ||
          connectionState ==
              CallConnectionState.outgoing ||
          connectionState ==
              CallConnectionState.incoming;

  bool get hasEnded =>
      connectionState ==
          CallConnectionState.ended;

  bool get hasFailed =>
      connectionState ==
          CallConnectionState.failed;

  // ===========================================================
  // EXTENDED LIFECYCLE HELPERS
  // ===========================================================

  bool get isIdle =>
      connectionState ==
          CallConnectionState.idle;

  bool get isInitializing =>
      connectionState ==
          CallConnectionState.initializing;

  bool get isConnecting =>
      connectionState ==
          CallConnectionState.connecting;

  bool get isRinging =>
      connectionState ==
          CallConnectionState.ringing;

  bool get isIncoming =>
      connectionState ==
          CallConnectionState.incoming;

  bool get isOutgoing =>
      connectionState ==
          CallConnectionState.outgoing;

  bool get isReconnecting =>
      connectionState ==
          CallConnectionState.reconnecting;

  bool get isDisconnected =>
      connectionState ==
          CallConnectionState.disconnected;

  /// True only for final provider/UI states.
  bool get isTerminal =>
      connectionState ==
          CallConnectionState.ended ||
          connectionState ==
              CallConnectionState.failed;

  /// Broader lifecycle helper than [isCalling].
  ///
  /// Includes setup, connected and reconnecting phases.
  bool get isCallInProgress {
    switch (connectionState) {
      case CallConnectionState.initializing:
      case CallConnectionState.connecting:
      case CallConnectionState.ringing:
      case CallConnectionState.incoming:
      case CallConnectionState.outgoing:
      case CallConnectionState.connected:
      case CallConnectionState.reconnecting:
        return true;

      case CallConnectionState.idle:
      case CallConnectionState.disconnected:
      case CallConnectionState.ended:
      case CallConnectionState.failed:
        return false;
    }
  }

  bool get canShowActiveCallControls =>
      connectionState ==
          CallConnectionState.connected ||
          connectionState ==
              CallConnectionState.reconnecting;

  // ===========================================================
  // NETWORK HELPERS
  // ===========================================================

  bool get isOffline =>
      networkQuality ==
          NetworkQuality.offline;

  bool get hasUsableNetwork =>
      networkQuality !=
          NetworkQuality.offline;

  bool get isNetworkHealthy =>
      networkQuality ==
          NetworkQuality.excellent ||
          networkQuality ==
              NetworkQuality.good;

  bool get isNetworkDegraded =>
      networkQuality ==
          NetworkQuality.fair ||
          networkQuality ==
              NetworkQuality.poor;

  bool get hasMeasuredBitrate =>
      uploadBitrate > 0 ||
          downloadBitrate > 0;

  bool get hasMeasuredPing =>
      ping > 0;

  // ===========================================================
  // PARTICIPANT HELPERS
  // ===========================================================

  bool get hasLocalUid =>
      localUid.trim().isNotEmpty;

  bool get hasRemoteUid =>
      remoteUid.trim().isNotEmpty;

  bool get hasRemoteName =>
      remoteName.trim().isNotEmpty;

  bool get hasRemotePhoto =>
      remotePhoto.trim().isNotEmpty;

  bool get hasRemoteParticipant =>
      hasRemoteUid ||
          hasRemoteName;

  // ===========================================================
  // AUDIO / VIDEO HELPERS
  // ===========================================================

  bool get isMicrophoneMuted =>
      !microphoneEnabled;

  bool get isUsingSpeaker =>
      speakerEnabled &&
          !bluetoothEnabled;

  bool get isUsingBluetooth =>
      bluetoothEnabled;

  bool get isUsingEarpiece =>
      !speakerEnabled &&
          !bluetoothEnabled;

  bool get hasVideoOutput =>
      cameraEnabled ||
          screenSharing;

  bool get isPresentingScreen =>
      screenSharing;

  // ===========================================================
  // DURATION HELPERS
  // ===========================================================

  Duration get elapsedDuration {
    final int seconds =
    duration < 0
        ? 0
        : duration;

    return Duration(
      seconds: seconds,
    );
  }

  String get formattedDuration {
    final int safeSeconds =
    duration < 0
        ? 0
        : duration;

    final int hours =
        safeSeconds ~/ 3600;

    final int minutes =
        (safeSeconds % 3600) ~/ 60;

    final int seconds =
        safeSeconds % 60;

    final String minuteText =
    minutes
        .toString()
        .padLeft(
      2,
      '0',
    );

    final String secondText =
    seconds
        .toString()
        .padLeft(
      2,
      '0',
    );

    if (hours > 0) {
      final String hourText =
      hours
          .toString()
          .padLeft(
        2,
        '0',
      );

      return '$hourText:'
          '$minuteText:'
          '$secondText';
    }

    return '$minuteText:$secondText';
  }

  // ===========================================================
  // VALUE EQUALITY
  // ===========================================================

  @override
  bool operator ==(
      Object other,
      ) {
    if (identical(
      this,
      other,
    )) {
      return true;
    }

    return other is CallState &&
        other.connectionState ==
            connectionState &&
        other.networkQuality ==
            networkQuality &&
        other.microphoneEnabled ==
            microphoneEnabled &&
        other.speakerEnabled ==
            speakerEnabled &&
        other.bluetoothEnabled ==
            bluetoothEnabled &&
        other.cameraEnabled ==
            cameraEnabled &&
        other.frontCamera ==
            frontCamera &&
        other.screenSharing ==
            screenSharing &&
        other.recording ==
            recording &&
        other.aiVoiceEnabled ==
            aiVoiceEnabled &&
        other.aiVideoEnabled ==
            aiVideoEnabled &&
        other.encrypted ==
            encrypted &&
        other.duration ==
            duration &&
        other.localUid ==
            localUid &&
        other.remoteUid ==
            remoteUid &&
        other.remoteName ==
            remoteName &&
        other.remotePhoto ==
            remotePhoto &&
        other.uploadBitrate ==
            uploadBitrate &&
        other.downloadBitrate ==
            downloadBitrate &&
        other.ping ==
            ping;
  }

  @override
  int get hashCode {
    return Object.hashAll(
      <Object?>[
        connectionState,
        networkQuality,
        microphoneEnabled,
        speakerEnabled,
        bluetoothEnabled,
        cameraEnabled,
        frontCamera,
        screenSharing,
        recording,
        aiVoiceEnabled,
        aiVideoEnabled,
        encrypted,
        duration,
        localUid,
        remoteUid,
        remoteName,
        remotePhoto,
        uploadBitrate,
        downloadBitrate,
        ping,
      ],
    );
  }

  // ===========================================================
  // DIAGNOSTICS
  // ===========================================================

  @override
  String toString() {
    return 'CallState('
        'connectionState: $connectionState, '
        'networkQuality: $networkQuality, '
        'microphoneEnabled: $microphoneEnabled, '
        'speakerEnabled: $speakerEnabled, '
        'bluetoothEnabled: $bluetoothEnabled, '
        'cameraEnabled: $cameraEnabled, '
        'screenSharing: $screenSharing, '
        'recording: $recording, '
        'duration: $duration, '
        'remoteUid: $remoteUid, '
        'uploadBitrate: $uploadBitrate, '
        'downloadBitrate: $downloadBitrate, '
        'ping: $ping'
        ')';
  }
}

// ===============================================================
// END OF FILE
//
// FILE 40 PRODUCTION CONTRACT:
//
// ✓ Existing CallConnectionState enum preserved.
// ✓ Existing NetworkQuality enum preserved.
// ✓ Existing constructor fields/defaults preserved.
// ✓ Existing copyWith API preserved.
// ✓ Existing isConnected preserved.
// ✓ Existing isCalling semantics preserved.
// ✓ Existing hasEnded preserved.
// ✓ Existing hasFailed preserved.
//
// ✓ Pure immutable state model.
// ✓ No lifecycle mutation ownership.
// ✓ No WebRTC ownership.
// ✓ No signaling ownership.
// ✓ No ICE ownership.
// ✓ No recovery ownership.
// ✓ No media-manager ownership.
// ✓ No network-monitor ownership.
//
// ✓ Extended lifecycle helpers added.
// ✓ Network-health helpers added.
// ✓ Participant helpers added.
// ✓ Audio-route helpers added.
// ✓ Video/screen-share helpers added.
// ✓ Safe elapsed Duration helper added.
// ✓ Safe formatted-duration helper added.
// ✓ Value equality added.
// ✓ Stable hashCode added.
// ✓ Rich diagnostics added.
//
// ✓ Provider-local state remains separate from canonical CallStatus.
// ===============================================================