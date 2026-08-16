import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: media_manager.dart
/// Location: lib/services/managers/media_manager.dart
///
/// Owns standalone local media acquisition and track state.
/// ===========================================================

class MediaManager extends ChangeNotifier {
  MediaManager._();

  static final MediaManager instance = MediaManager._();

  MediaStream? _localStream;

  bool _initialized = false;
  bool _audioEnabled = true;
  bool _videoEnabled = true;

  MediaStream? get localStream => _localStream;

  bool get isInitialized => _initialized;

  bool get isAudioEnabled => _audioEnabled;

  bool get isVideoEnabled => _videoEnabled;

  Future<Map<String, int>> get currentResolutionProfile async {
    final stream = _localStream;

    if (stream != null) {
      for (final track in stream.getVideoTracks()) {
        final settings = track.getSettings();

        final width = settings['width'];

        final height = settings['height'];

        if (width is num && height is num) {
          return {'width': width.toInt(), 'height': height.toInt()};
        }
      }
    }

    return {'width': 1280, 'height': 720};
  }

  Future<void> initialize() async {
    await initializeMedia(video: true, audio: true);
  }

  Future<MediaStream?> initializeMedia({
    bool video = true,
    bool audio = true,
  }) async {
    if (_localStream != null) {
      return _localStream;
    }

    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': video
            ? <String, dynamic>{
                'width': 1280,
                'height': 720,
                'frameRate': 30,
                'facingMode': 'user',
              }
            : false,
      });

      _localStream = stream;
      _initialized = true;
      _audioEnabled = audio;
      _videoEnabled = video;

      notifyListeners();

      return stream;
    } catch (error) {
      _initialized = false;

      debugPrint(
        'MediaManager initialization failed: '
        '$error',
      );

      return null;
    }
  }

  void attachStream(MediaStream? stream) {
    _localStream = stream;

    if (stream == null) {
      _initialized = false;
      notifyListeners();
      return;
    }

    _initialized = true;

    final audioTracks = stream.getAudioTracks();

    final videoTracks = stream.getVideoTracks();

    _audioEnabled = audioTracks.isEmpty || audioTracks.first.enabled;

    _videoEnabled = videoTracks.isNotEmpty && videoTracks.first.enabled;

    notifyListeners();
  }

  Future<void> setAudioEnabled(bool enabled) async {
    final stream = _localStream;

    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = enabled;
      }
    }

    _audioEnabled = enabled;

    notifyListeners();
  }

  Future<void> toggleAudio() async {
    await setAudioEnabled(!_audioEnabled);
  }

  Future<void> setVideoEnabled(bool enabled) async {
    final stream = _localStream;

    if (stream != null) {
      for (final track in stream.getVideoTracks()) {
        track.enabled = enabled;
      }
    }

    _videoEnabled = enabled;

    notifyListeners();
  }

  Future<void> toggleVideo() async {
    await setVideoEnabled(!_videoEnabled);
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks();

    if (tracks == null || tracks.isEmpty) {
      return;
    }

    try {
      await Helper.switchCamera(tracks.first);
    } catch (error) {
      debugPrint(
        'MediaManager camera switch failed: '
        '$error',
      );
    }
  }

  Future<void> setSpeakerphone(bool enable) async {
    try {
      await Helper.setSpeakerphoneOn(enable);
    } catch (error) {
      debugPrint(
        'MediaManager speaker routing failed: '
        '$error',
      );
    }
  }

  Future<List<MediaDeviceInfo>> getAudioInputDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();

      return devices
          .where((device) => device.kind == 'audioinput')
          .toList(growable: false);
    } catch (_) {
      return const <MediaDeviceInfo>[];
    }
  }

  Future<List<MediaDeviceInfo>> getVideoInputDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();

      return devices
          .where((device) => device.kind == 'videoinput')
          .toList(growable: false);
    } catch (_) {
      return const <MediaDeviceInfo>[];
    }
  }

  Future<void> refreshAudioDevices() async {
    try {
      await navigator.mediaDevices.enumerateDevices();

      notifyListeners();
    } catch (error) {
      debugPrint(
        'MediaManager device refresh failed: '
        '$error',
      );
    }
  }

  Future<void> disposeMedia() async {
    final stream = _localStream;

    _localStream = null;

    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }

      try {
        await stream.dispose();
      } catch (_) {}
    }

    _initialized = false;
    _audioEnabled = true;
    _videoEnabled = true;

    notifyListeners();
  }

  @override
  void dispose() {
    final stream = _localStream;

    _localStream = null;

    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }

      unawaited(stream.dispose());
    }

    super.dispose();
  }
}
