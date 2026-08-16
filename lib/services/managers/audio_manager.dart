import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: audio_manager.dart
/// Location: lib/services/managers/audio_manager.dart
///
/// Manages active-call microphone and speaker state.
/// ===========================================================

class AudioManager extends ChangeNotifier {
  AudioManager._();

  static final AudioManager instance = AudioManager._();

  MediaStream? _stream;

  bool _microphoneEnabled = true;
  bool _speakerEnabled = false;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  bool get microphoneEnabled => _microphoneEnabled;

  bool get speakerEnabled => _speakerEnabled;

  MediaStream? get stream => _stream;

  Future<void> initialize([MediaStream? stream]) async {
    if (stream != null) {
      _stream = stream;
    }

    _initialized = true;

    _syncMicrophoneState();

    notifyListeners();
  }

  void attachStream(MediaStream? stream) {
    _stream = stream;

    if (stream != null) {
      _initialized = true;
      _syncMicrophoneState();
    }

    notifyListeners();
  }

  void _syncMicrophoneState() {
    final audioTracks = _stream?.getAudioTracks() ?? const <MediaStreamTrack>[];

    if (audioTracks.isNotEmpty) {
      _microphoneEnabled = audioTracks.first.enabled;
    }
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    final stream = _stream;

    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = enabled;
      }
    }

    _microphoneEnabled = enabled;

    notifyListeners();
  }

  Future<void> toggleMicrophone() async {
    await setMicrophoneEnabled(!_microphoneEnabled);
  }

  Future<void> setSpeakerEnabled(bool enabled) async {
    try {
      await Helper.setSpeakerphoneOn(enabled);

      _speakerEnabled = enabled;

      notifyListeners();
    } catch (error) {
      debugPrint(
        'AudioManager speaker routing failed: '
        '$error',
      );

      rethrow;
    }
  }

  Future<void> toggleSpeaker() async {
    await setSpeakerEnabled(!_speakerEnabled);
  }

  Future<List<MediaDeviceInfo>> getAudioInputDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();

      return devices
          .where((device) => device.kind == 'audioinput')
          .toList(growable: false);
    } catch (error) {
      debugPrint(
        'AudioManager audio-device query failed: '
        '$error',
      );

      return const <MediaDeviceInfo>[];
    }
  }

  Future<List<MediaDeviceInfo>> getAudioOutputDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();

      return devices
          .where((device) => device.kind == 'audiooutput')
          .toList(growable: false);
    } catch (error) {
      debugPrint(
        'AudioManager output-device query failed: '
        '$error',
      );

      return const <MediaDeviceInfo>[];
    }
  }

  Future<void> reset() async {
    _stream = null;

    _microphoneEnabled = true;
    _speakerEnabled = false;
    _initialized = false;

    notifyListeners();
  }

  @override
  void dispose() {
    _stream = null;
    super.dispose();
  }
}
