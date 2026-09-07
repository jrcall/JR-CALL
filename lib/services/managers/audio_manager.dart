import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: audio_manager.dart
/// Location: lib/services/managers/audio_manager.dart
///
/// FINAL PRODUCTION ACTIVE-CALL AUDIO MANAGER
///
/// OWNERSHIP:
///
/// AudioManager:
/// - Attached active-call audio stream reference.
/// - Microphone track enabled-state compatibility.
/// - Speakerphone compatibility requests.
/// - Audio input/output device discovery.
///
/// MediaManager:
/// - Owns MediaStream acquisition/lifecycle/disposal.
///
/// MicrophoneManager:
/// - High-level microphone control.
///
/// SpeakerManager:
/// - High-level speaker/earpiece control.
///
/// BluetoothManager:
/// - Bluetooth route policy.
///
/// IMPORTANT:
///
/// AudioManager does NOT:
/// - Acquire MediaStream.
/// - Stop/dispose MediaStream.
/// - Create PeerConnection.
/// - Persist SDP/ICE.
/// - Own call lifecycle.
/// - Own recovery.
/// - Own Bluetooth/headset routing policy.
/// - Own recording.
/// ===========================================================

class AudioManager extends ChangeNotifier {
  AudioManager._();

  static final AudioManager instance = AudioManager._();

  // ===========================================================
  // DEVICE KIND CONSTANTS
  //
  // Exact platform device-kind values are preserved below.
  // Adjacent literals avoid IDE spelling-inspection noise.
  // ===========================================================

  static const String _audioInputKind =
      'audio' 'input';

  static const String _audioOutputKind =
      'audio' 'output';

  // ===========================================================
  // STREAM STATE
  // ===========================================================

  MediaStream? _stream;

  bool _microphoneEnabled = true;

  bool _speakerEnabled = false;

  bool _initialized = false;

  bool _disposed = false;

  // ===========================================================
  // SPEAKER ROUTING SERIALIZATION
  // ===========================================================

  Future<void> _speakerOperationTail =
  Future<void>.value();

  int _routeGeneration = 0;

  bool _ownsSpeakerRoute = false;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  bool get isInitialized =>
      _initialized;

  bool get microphoneEnabled =>
      _microphoneEnabled;

  bool get speakerEnabled =>
      _speakerEnabled;

  MediaStream? get stream =>
      _stream;

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize([
    MediaStream? stream,
  ]) async {
    if (_disposed) {
      return;
    }

    if (stream != null) {
      _stream = stream;
    }

    _initialized = true;

    _syncMicrophoneState();

    _notifySafely();
  }

  // ===========================================================
  // STREAM ATTACHMENT
  //
  // Stream ownership remains MediaManager.
  //
  // AudioManager only keeps a reference and NEVER stops/disposes
  // the attached stream.
  // ===========================================================

  void attachStream(
      MediaStream? stream,
      ) {
    if (_disposed) {
      return;
    }

    _stream = stream;

    if (stream == null) {
      _initialized = false;

      _notifySafely();

      return;
    }

    _initialized = true;

    _syncMicrophoneState();

    _notifySafely();
  }

  // ===========================================================
  // MICROPHONE STATE
  // ===========================================================

  void _syncMicrophoneState() {
    final List<MediaStreamTrack> audioTracks =
        _stream?.getAudioTracks() ??
            const <MediaStreamTrack>[];

    if (audioTracks.isEmpty) {
      return;
    }

    _microphoneEnabled =
        audioTracks.any(
              (MediaStreamTrack track) =>
          track.enabled,
        );
  }

  Future<void> setMicrophoneEnabled(
      bool enabled,
      ) async {
    if (_disposed) {
      return;
    }

    final MediaStream? currentStream =
        _stream;

    if (currentStream != null) {
      for (final MediaStreamTrack track
      in currentStream.getAudioTracks()) {
        track.enabled = enabled;
      }
    }

    if (_microphoneEnabled ==
        enabled) {
      return;
    }

    _microphoneEnabled = enabled;

    _notifySafely();
  }

  Future<void> toggleMicrophone() async {
    await setMicrophoneEnabled(
      !_microphoneEnabled,
    );
  }

  // ===========================================================
  // SPEAKER ROUTING
  // ===========================================================

  Future<void> setSpeakerEnabled(
      bool enabled,
      ) {
    if (_disposed) {
      return Future<void>.value();
    }

    final int generation =
        _routeGeneration;

    final Future<void> operation =
    _speakerOperationTail.then<void>(
          (_) async {
        if (!_isRouteGenerationCurrent(
          generation,
        )) {
          return;
        }

        try {
          await Helper.setSpeakerphoneOn(
            enabled,
          );
        } catch (error, stackTrace) {
          _reportError(
            'speaker routing',
            error,
            stackTrace,
          );

          rethrow;
        }

        if (!_isRouteGenerationCurrent(
          generation,
        )) {
          return;
        }

        _ownsSpeakerRoute = true;

        if (_speakerEnabled !=
            enabled) {
          _speakerEnabled = enabled;

          _notifySafely();
        }
      },
    );

    _speakerOperationTail =
        operation.then<void>(
              (_) {},
          onError: (
              Object _,
              StackTrace _,
              ) {},
        );

    return operation;
  }

  Future<void> toggleSpeaker() async {
    await setSpeakerEnabled(
      !_speakerEnabled,
    );
  }

  // ===========================================================
  // AUDIO INPUT DEVICES
  // ===========================================================

  Future<List<MediaDeviceInfo>>
  getAudioInputDevices() async {
    if (_disposed) {
      return const <MediaDeviceInfo>[];
    }

    try {
      final List<MediaDeviceInfo> devices =
      await navigator.mediaDevices
          .enumerateDevices();

      return List<MediaDeviceInfo>.unmodifiable(
        devices.where(
              (MediaDeviceInfo device) =>
          device.kind
              ?.trim()
              .toLowerCase() ==
              _audioInputKind,
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'audio-input device query',
        error,
        stackTrace,
      );

      return const <MediaDeviceInfo>[];
    }
  }

  // ===========================================================
  // AUDIO OUTPUT DEVICES
  // ===========================================================

  Future<List<MediaDeviceInfo>>
  getAudioOutputDevices() async {
    if (_disposed) {
      return const <MediaDeviceInfo>[];
    }

    try {
      final List<MediaDeviceInfo> devices =
      await navigator.mediaDevices
          .enumerateDevices();

      return List<MediaDeviceInfo>.unmodifiable(
        devices.where(
              (MediaDeviceInfo device) =>
          device.kind
              ?.trim()
              .toLowerCase() ==
              _audioOutputKind,
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'audio-output device query',
        error,
        stackTrace,
      );

      return const <MediaDeviceInfo>[];
    }
  }

  // ===========================================================
  // RESET
  //
  // AudioManager releases only its reference.
  //
  // It never stops/disposes the MediaStream because MediaManager
  // owns that resource.
  // ===========================================================

  Future<void> reset() async {
    if (_disposed) {
      return;
    }

    final bool shouldResetSpeaker =
        _ownsSpeakerRoute ||
            _speakerEnabled;

    final int generation =
    ++_routeGeneration;

    _stream = null;

    _microphoneEnabled = true;

    _speakerEnabled = false;

    _initialized = false;

    _ownsSpeakerRoute = false;

    _notifySafely();

    if (!shouldResetSpeaker) {
      return;
    }

    final Future<void> cleanup =
    _speakerOperationTail.then<void>(
          (_) async {
        if (_disposed ||
            generation !=
                _routeGeneration) {
          return;
        }

        try {
          await Helper.setSpeakerphoneOn(
            false,
          );
        } catch (error, stackTrace) {
          _reportError(
            'speaker reset',
            error,
            stackTrace,
          );
        }
      },
    );

    _speakerOperationTail =
        cleanup.then<void>(
              (_) {},
          onError: (
              Object _,
              StackTrace _,
              ) {},
        );

    await cleanup;
  }

  // ===========================================================
  // ROUTE GENERATION
  // ===========================================================

  bool _isRouteGenerationCurrent(
      int generation,
      ) {
    return !_disposed &&
        generation ==
            _routeGeneration;
  }

  // ===========================================================
  // SAFE NOTIFICATION
  // ===========================================================

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ===========================================================
  // LOGGING
  // ===========================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[AudioManager/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[AudioManager/$source]',
        stackTrace:
        stackTrace,
      );
    }
  }

  // ===========================================================
  // COMPLETE DISPOSAL
  // ===========================================================

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    final bool shouldResetSpeaker =
        _ownsSpeakerRoute ||
            _speakerEnabled;

    _disposed = true;

    _routeGeneration++;

    _stream = null;

    _microphoneEnabled = true;

    _speakerEnabled = false;

    _initialized = false;

    _ownsSpeakerRoute = false;

    if (shouldResetSpeaker) {
      final Future<void> cleanup =
      _speakerOperationTail.then<void>(
            (_) async {
          try {
            await Helper.setSpeakerphoneOn(
              false,
            );
          } catch (error, stackTrace) {
            _reportError(
              'dispose speaker cleanup',
              error,
              stackTrace,
            );
          }
        },
      );

      _speakerOperationTail =
          cleanup.then<void>(
                (_) {},
            onError: (
                Object _,
                StackTrace _,
                ) {},
          );

      unawaited(
        cleanup,
      );
    }

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 13 CORRECTED FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ Previous production logic preserved.
// ✓ No MediaStream acquisition added.
// ✓ No MediaStream stop/dispose added.
// ✓ MediaManager remains stream owner.
// ✓ attachStream(null) clears stale initialized state.
// ✓ Multiple audio tracks handled safely.
// ✓ Every attached audio track follows microphone enable state.
// ✓ Rapid speaker toggles serialized.
// ✓ Failed speaker route never falsely updates public state.
// ✓ Reset prevents stale speaker-ON winning after call cleanup.
// ✓ Dispose performs best-effort final speaker-OFF.
// ✓ Dart wildcard ignored-parameter style used.
// ✓ No unnecessary-multiple-underscore inspection.
// ✓ Exact audio input device-kind runtime value preserved.
// ✓ Exact audio output device-kind runtime value preserved.
// ✓ IDE spelling-inspection noise avoided.
// ✓ Nullable MediaDeviceInfo.kind handled safely.
// ✓ Platform device ordering preserved.
// ✓ MicrophoneManager high-level ownership preserved.
// ✓ SpeakerManager high-level ownership preserved.
// ✓ BluetoothManager routing ownership preserved.
// ✓ No PeerConnection ownership.
// ✓ No signaling ownership.
// ✓ No lifecycle/recovery/recording ownership.
//
// STATUS:
// FILE 13 CORRECTED VERIFICATION VERSION.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 14
// lib/services/managers/video_manager.dart
// ===============================================================