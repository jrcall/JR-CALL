// ===========================================================
// JR CALL
// File: video_manager.dart
// Location: lib/services/call/video_manager.dart
//
// Description:
// Central production video-state and camera orchestration manager.
//
// Responsibilities:
// - Camera initialization and lifecycle
// - Enable / disable local video
// - Front / back camera switching
// - Flash and zoom control
// - Resolution / FPS / bitrate state
// - Adaptive quality profiles
// - AI video feature state
// - Safe reset and duplicate-operation protection
//
// Ownership Rules:
// - CameraManager owns physical camera/device operations
// - VideoManager owns video feature state and orchestration
// - NetworkOptimizer decides recommended quality
// - BitrateController owns actual WebRTC sender bitrate changes
// - WebRTCService owns RTCPeerConnection/media transport
// - AIVideoEngine owns AI decision logic
//
// IMPORTANT:
// This file does not duplicate WebRTC, signaling, ICE,
// recovery, network monitoring, or peer-connection logic.
// ===========================================================

import 'package:flutter/foundation.dart';

import 'camera_manager.dart';

/// Video quality profile used by JR CALL video orchestration.
enum VideoQualityProfile { low, medium, hd, fullHd }

/// Immutable snapshot of the current video presentation state.
@immutable
class VideoStateSnapshot {
  const VideoStateSnapshot({
    required this.initialized,
    required this.videoEnabled,
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrate,
    required this.beautyMode,
    required this.faceEnhancement,
    required this.noiseReduction,
    required this.backgroundBlur,
    required this.qualityProfile,
  });

  final bool initialized;
  final bool videoEnabled;

  final int width;
  final int height;
  final int fps;
  final int bitrate;

  final bool beautyMode;
  final bool faceEnhancement;
  final bool noiseReduction;
  final bool backgroundBlur;

  final VideoQualityProfile qualityProfile;
}

/// Central video-state and camera orchestration manager.
class VideoManager extends ChangeNotifier {
  VideoManager._();

  static final VideoManager instance = VideoManager._();

  // ===========================================================
  // Dependencies
  // ===========================================================

  final CameraManager camera = CameraManager();

  // ===========================================================
  // Runtime Guards
  // ===========================================================

  bool _initialized = false;
  bool _disposed = false;

  bool _initializing = false;
  bool _changingVideoState = false;
  bool _changingCamera = false;
  bool _changingQuality = false;

  // ===========================================================
  // Video State
  // ===========================================================

  bool _videoEnabled = true;

  int _width = 1280;
  int _height = 720;
  int _fps = 30;

  /// Stored in bits per second.
  int _bitrate = 1500000;

  VideoQualityProfile _qualityProfile = VideoQualityProfile.hd;

  // ===========================================================
  // AI / Enhancement State
  // ===========================================================

  bool _beautyMode = false;
  bool _faceEnhancement = true;
  bool _noiseReduction = true;
  bool _backgroundBlur = false;

  // ===========================================================
  // Public State
  // ===========================================================

  bool get isInitialized => _initialized;

  bool get isDisposed => _disposed;

  bool get videoEnabled => _videoEnabled;

  bool get isFrontCamera => camera.isFrontCamera;

  bool get flashEnabled => camera.isFlashOn;

  double get zoomLevel => camera.zoomLevel;

  int get width => _width;

  int get height => _height;

  int get fps => _fps;

  int get bitrate => _bitrate;

  bool get beautyMode => _beautyMode;

  bool get faceEnhancement => _faceEnhancement;

  bool get noiseReduction => _noiseReduction;

  bool get backgroundBlur => _backgroundBlur;

  VideoQualityProfile get qualityProfile => _qualityProfile;

  Map<String, int> get resolution => <String, int>{
    'width': _width,
    'height': _height,
  };

  VideoStateSnapshot get snapshot => VideoStateSnapshot(
    initialized: _initialized,
    videoEnabled: _videoEnabled,
    width: _width,
    height: _height,
    fps: _fps,
    bitrate: _bitrate,
    beautyMode: _beautyMode,
    faceEnhancement: _faceEnhancement,
    noiseReduction: _noiseReduction,
    backgroundBlur: _backgroundBlur,
    qualityProfile: _qualityProfile,
  );

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize() async {
    _ensureUsable();

    if (_initialized || _initializing) {
      return;
    }

    _initializing = true;

    try {
      await camera.initialize();

      _videoEnabled = camera.isCameraEnabled;
      _width = camera.previewWidth;
      _height = camera.previewHeight;

      _qualityProfile = _resolveProfileFromResolution(_width, _height);

      _initialized = true;

      _notifySafely();

      debugPrint('JR CALL: VideoManager initialized.');
    } catch (error, stackTrace) {
      _reportError('initialize', error, stackTrace);

      rethrow;
    } finally {
      _initializing = false;
    }
  }

  Future<void> _ensureInitialized() async {
    _ensureUsable();

    if (!_initialized) {
      await initialize();
    }
  }

  // ===========================================================
  // Video Enable / Disable
  // ===========================================================

  Future<void> enableVideo() async {
    await _ensureInitialized();

    if (_changingVideoState || _videoEnabled) {
      return;
    }

    _changingVideoState = true;

    try {
      await camera.enableCamera();

      _videoEnabled = true;

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('enableVideo', error, stackTrace);

      rethrow;
    } finally {
      _changingVideoState = false;
    }
  }

  Future<void> disableVideo() async {
    await _ensureInitialized();

    if (_changingVideoState || !_videoEnabled) {
      return;
    }

    _changingVideoState = true;

    try {
      await camera.disableCamera();

      _videoEnabled = false;

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('disableVideo', error, stackTrace);

      rethrow;
    } finally {
      _changingVideoState = false;
    }
  }

  Future<void> setVideoEnabled(bool enabled) async {
    if (enabled) {
      await enableVideo();
    } else {
      await disableVideo();
    }
  }

  Future<void> toggleVideo() async {
    if (_videoEnabled) {
      await disableVideo();
    } else {
      await enableVideo();
    }
  }

  // ===========================================================
  // Camera Controls
  // ===========================================================

  Future<void> switchCamera() async {
    await _ensureInitialized();

    if (_changingCamera) {
      return;
    }

    _changingCamera = true;

    try {
      await camera.switchCamera();

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('switchCamera', error, stackTrace);

      rethrow;
    } finally {
      _changingCamera = false;
    }
  }

  Future<void> enableFlash() async {
    await _ensureInitialized();

    try {
      await camera.enableFlash();

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('enableFlash', error, stackTrace);

      rethrow;
    }
  }

  Future<void> disableFlash() async {
    await _ensureInitialized();

    try {
      await camera.disableFlash();

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('disableFlash', error, stackTrace);

      rethrow;
    }
  }

  Future<void> toggleFlash() async {
    await _ensureInitialized();

    try {
      await camera.toggleFlash();

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('toggleFlash', error, stackTrace);

      rethrow;
    }
  }

  Future<void> setZoom(double zoom) async {
    await _ensureInitialized();

    if (!zoom.isFinite) {
      throw ArgumentError.value(zoom, 'zoom', 'Zoom must be a finite number.');
    }

    try {
      await camera.setZoom(zoom);

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('setZoom', error, stackTrace);

      rethrow;
    }
  }

  // ===========================================================
  // Resolution
  // ===========================================================

  Future<void> setResolution({required int width, required int height}) async {
    await _ensureInitialized();

    if (width <= 0 || height <= 0) {
      throw ArgumentError('Video resolution must be greater than zero.');
    }

    if (_width == width && _height == height) {
      return;
    }

    try {
      await camera.setPreviewSize(width: width, height: height);

      _width = width;
      _height = height;

      _qualityProfile = _resolveProfileFromResolution(width, height);

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('setResolution', error, stackTrace);

      rethrow;
    }
  }

  // ===========================================================
  // FPS
  // ===========================================================

  Future<void> setFrameRate(int value) async {
    _ensureUsable();

    if (value < 1 || value > 120) {
      throw ArgumentError.value(
        value,
        'value',
        'FPS must be between 1 and 120.',
      );
    }

    if (_fps == value) {
      return;
    }

    _fps = value;

    _notifySafely();
  }

  // ===========================================================
  // Bitrate
  // ===========================================================

  Future<void> setBitrate(int value) async {
    _ensureUsable();

    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'Bitrate cannot be negative.');
    }

    if (_bitrate == value) {
      return;
    }

    _bitrate = value;

    // Actual RTCRtpSender bitrate application belongs to the
    // bitrate/WebRTC transport layer.
    _notifySafely();
  }

  // ===========================================================
  // Unified Video Profile
  // ===========================================================

  Future<void> applyProfile(VideoQualityProfile profile) async {
    await _ensureInitialized();

    if (_changingQuality) {
      return;
    }

    if (_qualityProfile == profile && _cameraMatchesProfile(profile)) {
      return;
    }

    _changingQuality = true;

    try {
      switch (profile) {
        case VideoQualityProfile.low:
          await camera.applyLowQuality();

          _width = 640;
          _height = 360;
          _fps = 15;
          _bitrate = 400000;
          break;

        case VideoQualityProfile.medium:
          await camera.applyMediumQuality();

          _width = 960;
          _height = 540;
          _fps = 24;
          _bitrate = 900000;
          break;

        case VideoQualityProfile.hd:
          await camera.applyHDQuality();

          _width = 1280;
          _height = 720;
          _fps = 30;
          _bitrate = 1500000;
          break;

        case VideoQualityProfile.fullHd:
          await camera.applyFullHDQuality();

          _width = 1920;
          _height = 1080;
          _fps = 60;
          _bitrate = 3000000;
          break;
      }

      _qualityProfile = profile;

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('applyProfile', error, stackTrace);

      rethrow;
    } finally {
      _changingQuality = false;
    }
  }

  Future<void> applyLowQuality() async {
    await applyProfile(VideoQualityProfile.low);
  }

  Future<void> applyMediumQuality() async {
    await applyProfile(VideoQualityProfile.medium);
  }

  Future<void> applyHDQuality() async {
    await applyProfile(VideoQualityProfile.hd);
  }

  Future<void> applyFullHDQuality() async {
    await applyProfile(VideoQualityProfile.fullHd);
  }

  // ===========================================================
  // AI Features
  // ===========================================================

  Future<void> enableBeautyMode(bool value) async {
    _ensureUsable();

    if (_beautyMode == value) {
      return;
    }

    _beautyMode = value;

    _notifySafely();
  }

  Future<void> enableFaceEnhancement(bool value) async {
    _ensureUsable();

    if (_faceEnhancement == value) {
      return;
    }

    _faceEnhancement = value;

    _notifySafely();
  }

  Future<void> enableNoiseReduction(bool value) async {
    _ensureUsable();

    if (_noiseReduction == value) {
      return;
    }

    _noiseReduction = value;

    _notifySafely();
  }

  Future<void> enableBackgroundBlur(bool value) async {
    _ensureUsable();

    if (_backgroundBlur == value) {
      return;
    }

    _backgroundBlur = value;

    _notifySafely();
  }

  // ===========================================================
  // Adaptive Network Settings
  // ===========================================================

  Future<void> applyAdaptiveSettings({
    required int width,
    required int height,
    required int fps,
    required int bitrate,
  }) async {
    await _ensureInitialized();

    if (width <= 0 || height <= 0 || fps <= 0 || fps > 120 || bitrate < 0) {
      throw ArgumentError('Invalid adaptive video settings.');
    }

    final resolutionChanged = _width != width || _height != height;

    final stateChanged =
        resolutionChanged || _fps != fps || _bitrate != bitrate;

    if (!stateChanged) {
      return;
    }

    try {
      if (resolutionChanged) {
        await camera.setPreviewSize(width: width, height: height);
      }

      _width = width;
      _height = height;
      _fps = fps;
      _bitrate = bitrate;

      _qualityProfile = _resolveProfileFromResolution(width, height);

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError('applyAdaptiveSettings', error, stackTrace);

      rethrow;
    }
  }

  // ===========================================================
  // Reset
  // ===========================================================

  Future<void> reset() async {
    if (_disposed) {
      return;
    }

    try {
      await camera.reset();
    } catch (error, stackTrace) {
      _reportError('reset camera', error, stackTrace);
    }

    _initialized = false;

    _initializing = false;
    _changingVideoState = false;
    _changingCamera = false;
    _changingQuality = false;

    _videoEnabled = true;

    _width = 1280;
    _height = 720;
    _fps = 30;
    _bitrate = 1500000;

    _qualityProfile = VideoQualityProfile.hd;

    _beautyMode = false;
    _faceEnhancement = true;
    _noiseReduction = true;
    _backgroundBlur = false;

    _notifySafely();
  }

  // ===========================================================
  // Internal Helpers
  // ===========================================================

  bool _cameraMatchesProfile(VideoQualityProfile profile) {
    switch (profile) {
      case VideoQualityProfile.low:
        return camera.previewWidth == 640 && camera.previewHeight == 360;

      case VideoQualityProfile.medium:
        return camera.previewWidth == 960 && camera.previewHeight == 540;

      case VideoQualityProfile.hd:
        return camera.previewWidth == 1280 && camera.previewHeight == 720;

      case VideoQualityProfile.fullHd:
        return camera.previewWidth == 1920 && camera.previewHeight == 1080;
    }
  }

  VideoQualityProfile _resolveProfileFromResolution(int width, int height) {
    final pixels = width * height;

    if (pixels >= 1920 * 1080) {
      return VideoQualityProfile.fullHd;
    }

    if (pixels >= 1280 * 720) {
      return VideoQualityProfile.hd;
    }

    if (pixels >= 854 * 480) {
      return VideoQualityProfile.medium;
    }

    return VideoQualityProfile.low;
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('VideoManager has already been disposed.');
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint('JR CALL [VideoManager/$source] error: $error');

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [VideoManager/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // Dispose
  // ===========================================================

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _initialized = false;
    _initializing = false;
    _changingVideoState = false;
    _changingCamera = false;
    _changingQuality = false;

    camera.dispose();

    super.dispose();
  }
}
