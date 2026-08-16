import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: video_manager.dart
/// Location: lib/services/managers/video_manager.dart
///
/// Manages local/remote RTC renderers and active video state.
/// ===========================================================

class VideoManager extends ChangeNotifier {
  VideoManager._();

  static final VideoManager instance = VideoManager._();

  RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _initialized = false;
  bool _videoEnabled = true;
  bool _frontCamera = true;
  bool _disposed = false;

  bool get isInitialized => _initialized;

  bool get isVideoEnabled => _videoEnabled;

  bool get isFrontCamera => _frontCamera;

  RTCVideoRenderer get localRenderer => _localRenderer;

  RTCVideoRenderer get remoteRenderer => _remoteRenderer;

  Future<void> initialize() async {
    await initializeRenderers();
  }

  Future<void> initializeRenderers() async {
    if (_initialized) {
      return;
    }

    if (_disposed) {
      _localRenderer = RTCVideoRenderer();

      _remoteRenderer = RTCVideoRenderer();

      _disposed = false;
    }

    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      _initialized = true;

      notifyListeners();
    } catch (error) {
      _initialized = false;

      debugPrint(
        'VideoManager renderer '
        'initialization failed: $error',
      );

      rethrow;
    }
  }

  void setLocalStream(MediaStream? stream) {
    _localRenderer.srcObject = stream;

    if (!_disposed) {
      notifyListeners();
    }
  }

  void setRemoteStream(MediaStream? stream) {
    _remoteRenderer.srcObject = stream;

    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> enableVideo(MediaStream? stream) async {
    await setVideoEnabled(stream, true);
  }

  Future<void> disableVideo(MediaStream? stream) async {
    await setVideoEnabled(stream, false);
  }

  Future<void> setVideoEnabled(MediaStream? stream, bool enabled) async {
    if (stream != null) {
      for (final track in stream.getVideoTracks()) {
        track.enabled = enabled;
      }
    }

    _videoEnabled = enabled;

    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> toggleVideo(MediaStream? stream) async {
    await setVideoEnabled(stream, !_videoEnabled);
  }

  Future<void> switchCamera(MediaStream? stream) async {
    if (stream == null) {
      return;
    }

    final tracks = stream.getVideoTracks();

    if (tracks.isEmpty) {
      return;
    }

    try {
      await Helper.switchCamera(tracks.first);

      _frontCamera = !_frontCamera;

      if (!_disposed) {
        notifyListeners();
      }
    } catch (error) {
      debugPrint(
        'VideoManager camera switch failed: '
        '$error',
      );
    }
  }

  Future<void> reset() async {
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    _videoEnabled = true;
    _frontCamera = true;

    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> disposeRenderers() async {
    if (_disposed) {
      return;
    }

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    try {
      await _localRenderer.dispose();
    } catch (_) {}

    try {
      await _remoteRenderer.dispose();
    } catch (_) {}

    _initialized = false;
    _disposed = true;
  }

  @override
  void dispose() {
    if (!_disposed) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;

      _localRenderer.dispose();
      _remoteRenderer.dispose();

      _disposed = true;
      _initialized = false;
    }

    super.dispose();
  }
}
