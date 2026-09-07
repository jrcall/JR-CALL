// ===============================================================
// JR CALL
// File: video_manager.dart
// Location: lib/services/call/video_manager.dart
//
// MASTER PRODUCTION VIDEO MANAGER
//
// RESPONSIBILITIES:
//
// - Camera initialization orchestration.
// - Enable / disable local video preference.
// - Front / back camera switching.
// - Flash coordination.
// - Zoom coordination.
// - Resolution / FPS / bitrate state.
// - Adaptive video-quality profile coordination.
// - AI video-feature preference state.
// - Serialized video operations.
// - Camera child-state synchronization.
// - Lifecycle-safe reset / disposal.
//
// OWNERSHIP:
//
// CameraManager:
// - Physical camera/device operation state.
//
// VideoManager:
// - Video feature state and orchestration.
//
// NetworkOptimizer:
// - Recommended network quality policy.
//
// BitrateController:
// - Actual RTCRtpSender bitrate application.
//
// WebRTCService:
// - RTCPeerConnection.
// - MediaStream / MediaStreamTrack transport.
//
// AIVideoEngine:
// - AI decision logic.
//
// IMPORTANT:
//
// - No PeerConnection ownership here.
// - No MediaStream creation here.
// - No signaling ownership here.
// - No ICE ownership here.
// - No recovery ownership here.
// - No network-monitoring ownership here.
// - Stored bitrate is policy state only.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'camera_manager.dart';

// ===============================================================
// VIDEO QUALITY PROFILE
// ===============================================================

enum VideoQualityProfile {
  low,
  medium,
  hd,
  fullHd,
}

// ===============================================================
// IMMUTABLE VIDEO STATE
// ===============================================================

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

  /// Bits per second.
  final int bitrate;

  final bool beautyMode;
  final bool faceEnhancement;
  final bool noiseReduction;
  final bool backgroundBlur;

  final VideoQualityProfile qualityProfile;
}

// ===============================================================
// VIDEO MANAGER
// ===============================================================

class VideoManager extends ChangeNotifier {
  VideoManager._() {
    camera.addListener(
      _handleCameraStateChanged,
    );
  }

  static final VideoManager instance = VideoManager._();

  // =============================================================
  // DEPENDENCIES
  // =============================================================

  final CameraManager camera = CameraManager();

  // =============================================================
  // RUNTIME STATE
  // =============================================================

  bool _initialized = false;

  bool _disposed = false;

  bool _suppressCameraNotifications = false;

  // =============================================================
  // VIDEO STATE
  // =============================================================

  bool _videoEnabled = true;

  int _width = 1280;

  int _height = 720;

  int _fps = 30;

  /// Stored in bits per second.
  ///
  /// Actual RTCRtpSender bitrate application belongs to
  /// BitrateController / WebRTC transport ownership.
  int _bitrate = 1500000;

  VideoQualityProfile _qualityProfile = VideoQualityProfile.hd;

  // =============================================================
  // AI / ENHANCEMENT PREFERENCE STATE
  // =============================================================

  bool _beautyMode = false;

  bool _faceEnhancement = true;

  bool _noiseReduction = true;

  bool _backgroundBlur = false;

  // =============================================================
  // SERIALIZED OPERATION ENGINE
  // =============================================================

  Future<void> _operationQueue = Future<void>.value();

  // =============================================================
  // PUBLIC STATE
  // =============================================================

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

  Map<String, int> get resolution {
    return <String, int>{
      'width': _width,
      'height': _height,
    };
  }

  VideoStateSnapshot get snapshot {
    return VideoStateSnapshot(
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
  }

  // =============================================================
  // INITIALIZATION
  // =============================================================

  Future<void> initialize() async {
    _ensureUsable();

    await _runSerialized<void>(
      'initialize',
          () async {
        if (_initialized) {
          _synchronizeCameraOwnedState();

          return;
        }

        await camera.initialize();

        _synchronizeCameraOwnedState();

        _initialized = true;

        debugPrint(
          'JR CALL: VideoManager initialized.',
        );
      },
    );
  }

  Future<void> _ensureInitialized() async {
    _ensureUsable();

    if (_initialized) {
      return;
    }

    await initialize();
  }

  // =============================================================
  // VIDEO ENABLE / DISABLE
  // =============================================================

  Future<void> enableVideo() async {
    await _setVideoEnabled(
      true,
      operation: 'enableVideo',
    );
  }

  Future<void> disableVideo() async {
    await _setVideoEnabled(
      false,
      operation: 'disableVideo',
    );
  }

  Future<void> setVideoEnabled(
      bool enabled,
      ) async {
    await _setVideoEnabled(
      enabled,
      operation: 'setVideoEnabled',
    );
  }

  Future<void> toggleVideo() async {
    await _ensureInitialized();

    await _runSerialized<void>(
      'toggleVideo',
          () async {
        final bool nextEnabled = !_videoEnabled;

        await _applyVideoEnabled(
          nextEnabled,
        );
      },
    );
  }

  Future<void> _setVideoEnabled(
      bool enabled, {
        required String operation,
      }) async {
    await _ensureInitialized();

    await _runSerialized<void>(
      operation,
          () async {
        if (_videoEnabled == enabled &&
            camera.isCameraEnabled == enabled) {
          return;
        }

        await _applyVideoEnabled(
          enabled,
        );
      },
    );
  }

  Future<void> _applyVideoEnabled(
      bool enabled,
      ) async {
    if (enabled) {
      await camera.enableCamera();
    } else {
      await camera.disableCamera();
    }

    _videoEnabled = camera.isCameraEnabled;
  }

  // =============================================================
  // CAMERA SWITCHING
  // =============================================================

  Future<void> switchCamera() async {
    await _ensureInitialized();

    await _runSerialized<void>(
      'switchCamera',
          () async {
        await camera.switchCamera();
      },
    );
  }

  // =============================================================
  // FLASH
  // =============================================================

  Future<void> enableFlash() async {
    await _ensureInitialized();

    await _runSerialized<void>(
      'enableFlash',
          () async {
        if (camera.isFlashOn) {
          return;
        }

        await camera.enableFlash();
      },
    );
  }

  Future<void> disableFlash() async {
    await _ensureInitialized();

    await _runSerialized<void>(
      'disableFlash',
          () async {
        if (!camera.isFlashOn) {
          return;
        }

        await camera.disableFlash();
      },
    );
  }

  Future<void> toggleFlash() async {
    await _ensureInitialized();

    await _runSerialized<void>(
      'toggleFlash',
          () async {
        // CameraManager owns physical flash state.
        //
        // Read current state INSIDE the serialized queue so
        // rapid taps cannot calculate from stale state.
        await camera.toggleFlash();
      },
    );
  }

  // =============================================================
  // ZOOM
  // =============================================================

  Future<void> setZoom(
      double zoom,
      ) async {
    await _ensureInitialized();

    if (!zoom.isFinite) {
      throw ArgumentError.value(
        zoom,
        'zoom',
        'Zoom must be a finite number.',
      );
    }

    await _runSerialized<void>(
      'setZoom',
          () async {
        await camera.setZoom(
          zoom,
        );
      },
    );
  }

  // =============================================================
  // RESOLUTION
  // =============================================================

  Future<void> setResolution({
    required int width,
    required int height,
  }) async {
    await _ensureInitialized();

    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'Video resolution must be greater than zero.',
      );
    }

    await _runSerialized<void>(
      'setResolution',
          () async {
        if (_width == width &&
            _height == height &&
            camera.previewWidth == width &&
            camera.previewHeight == height) {
          return;
        }

        await camera.setPreviewSize(
          width: width,
          height: height,
        );

        _width = camera.previewWidth;

        _height = camera.previewHeight;

        _qualityProfile = _resolveProfileFromResolution(
          _width,
          _height,
        );
      },
    );
  }

  // =============================================================
  // FPS
  // =============================================================

  Future<void> setFrameRate(
      int value,
      ) async {
    _ensureUsable();

    if (value < 1 || value > 120) {
      throw ArgumentError.value(
        value,
        'value',
        'FPS must be between 1 and 120.',
      );
    }

    await _runSerialized<void>(
      'setFrameRate',
          () async {
        if (_fps == value) {
          return;
        }

        _fps = value;
      },
    );
  }

  // =============================================================
  // BITRATE POLICY STATE
  // =============================================================

  Future<void> setBitrate(
      int value,
      ) async {
    _ensureUsable();

    if (value < 0) {
      throw ArgumentError.value(
        value,
        'value',
        'Bitrate cannot be negative.',
      );
    }

    await _runSerialized<void>(
      'setBitrate',
          () async {
        if (_bitrate == value) {
          return;
        }

        _bitrate = value;

        // No RTCRtpSender mutation here.
      },
    );
  }

  // =============================================================
  // UNIFIED VIDEO PROFILE
  // =============================================================

  Future<void> applyProfile(
      VideoQualityProfile profile,
      ) async {
    await _ensureInitialized();

    await _runSerialized<void>(
      'applyProfile',
          () async {
        if (_qualityProfile == profile &&
            _cameraMatchesProfile(profile)) {
          return;
        }

        switch (profile) {
          case VideoQualityProfile.low:
            await camera.applyLowQuality();

            _fps = 15;

            _bitrate = 400000;
            break;

          case VideoQualityProfile.medium:
            await camera.applyMediumQuality();

            _fps = 24;

            _bitrate = 900000;
            break;

          case VideoQualityProfile.hd:
            await camera.applyHDQuality();

            _fps = 30;

            _bitrate = 1500000;
            break;

          case VideoQualityProfile.fullHd:
            await camera.applyFullHDQuality();

            _fps = 60;

            _bitrate = 3000000;
            break;
        }

        // CameraManager is authoritative for the actual preview size.
        _width = camera.previewWidth;

        _height = camera.previewHeight;

        _qualityProfile = _resolveProfileFromResolution(
          _width,
          _height,
        );

        // With the current verified CameraManager contract,
        // this should exactly match the requested profile.
        if (_qualityProfile != profile) {
          throw StateError(
            'CameraManager did not apply the requested '
                'video quality profile.',
          );
        }
      },
    );
  }

  Future<void> applyLowQuality() async {
    await applyProfile(
      VideoQualityProfile.low,
    );
  }

  Future<void> applyMediumQuality() async {
    await applyProfile(
      VideoQualityProfile.medium,
    );
  }

  Future<void> applyHDQuality() async {
    await applyProfile(
      VideoQualityProfile.hd,
    );
  }

  Future<void> applyFullHDQuality() async {
    await applyProfile(
      VideoQualityProfile.fullHd,
    );
  }

  // =============================================================
  // AI / VIDEO ENHANCEMENT PREFERENCE STATE
  // =============================================================

  Future<void> enableBeautyMode(
      bool value,
      ) async {
    _ensureUsable();

    await _runSerialized<void>(
      'enableBeautyMode',
          () async {
        if (_beautyMode == value) {
          return;
        }

        _beautyMode = value;
      },
    );
  }

  Future<void> enableFaceEnhancement(
      bool value,
      ) async {
    _ensureUsable();

    await _runSerialized<void>(
      'enableFaceEnhancement',
          () async {
        if (_faceEnhancement == value) {
          return;
        }

        _faceEnhancement = value;
      },
    );
  }

  Future<void> enableNoiseReduction(
      bool value,
      ) async {
    _ensureUsable();

    await _runSerialized<void>(
      'enableNoiseReduction',
          () async {
        if (_noiseReduction == value) {
          return;
        }

        _noiseReduction = value;
      },
    );
  }

  Future<void> enableBackgroundBlur(
      bool value,
      ) async {
    _ensureUsable();

    await _runSerialized<void>(
      'enableBackgroundBlur',
          () async {
        if (_backgroundBlur == value) {
          return;
        }

        _backgroundBlur = value;
      },
    );
  }

  // =============================================================
  // ADAPTIVE NETWORK SETTINGS
  // =============================================================

  Future<void> applyAdaptiveSettings({
    required int width,
    required int height,
    required int fps,
    required int bitrate,
  }) async {
    await _ensureInitialized();

    if (width <= 0 ||
        height <= 0 ||
        fps <= 0 ||
        fps > 120 ||
        bitrate < 0) {
      throw ArgumentError(
        'Invalid adaptive video settings.',
      );
    }

    await _runSerialized<void>(
      'applyAdaptiveSettings',
          () async {
        final bool resolutionChanged =
            _width != width ||
                _height != height ||
                camera.previewWidth != width ||
                camera.previewHeight != height;

        final bool stateChanged =
            resolutionChanged ||
                _fps != fps ||
                _bitrate != bitrate;

        if (!stateChanged) {
          return;
        }

        if (resolutionChanged) {
          await camera.setPreviewSize(
            width: width,
            height: height,
          );
        }

        _width = camera.previewWidth;

        _height = camera.previewHeight;

        _fps = fps;

        _bitrate = bitrate;

        _qualityProfile = _resolveProfileFromResolution(
          _width,
          _height,
        );

        // NetworkOptimizer decides recommendations.
        // BitrateController/WebRTC transport applies sender bitrate.
      },
    );
  }

  // =============================================================
  // RESET
  // =============================================================

  Future<void> reset() async {
    if (_disposed) {
      return;
    }

    await _runSerialized<void>(
      'reset',
          () async {
        try {
          await camera.reset();
        } catch (error, stackTrace) {
          _reportError(
            'reset camera',
            error,
            stackTrace,
          );

          rethrow;
        }

        _initialized = false;

        _videoEnabled = camera.isCameraEnabled;

        _width = camera.previewWidth;

        _height = camera.previewHeight;

        _fps = 30;

        _bitrate = 1500000;

        _qualityProfile = _resolveProfileFromResolution(
          _width,
          _height,
        );

        _beautyMode = false;

        _faceEnhancement = true;

        _noiseReduction = true;

        _backgroundBlur = false;
      },
    );
  }

  // =============================================================
  // CAMERA CHILD-STATE SYNCHRONIZATION
  // =============================================================

  void _handleCameraStateChanged() {
    if (_disposed || _suppressCameraNotifications) {
      return;
    }

    final bool previousVideoEnabled = _videoEnabled;

    final int previousWidth = _width;

    final int previousHeight = _height;

    final VideoQualityProfile previousProfile = _qualityProfile;

    _synchronizeCameraOwnedState();

    if (previousVideoEnabled == _videoEnabled &&
        previousWidth == _width &&
        previousHeight == _height &&
        previousProfile == _qualityProfile) {
      // Camera may still have changed front/back camera,
      // flash or zoom. Those getters are CameraManager-owned,
      // therefore listeners still need this notification.
      _notifySafely();

      return;
    }

    _notifySafely();
  }

  void _synchronizeCameraOwnedState() {
    _videoEnabled = camera.isCameraEnabled;

    _width = camera.previewWidth;

    _height = camera.previewHeight;

    _qualityProfile = _resolveProfileFromResolution(
      _width,
      _height,
    );
  }

  // =============================================================
  // PROFILE HELPERS
  // =============================================================

  bool _cameraMatchesProfile(
      VideoQualityProfile profile,
      ) {
    switch (profile) {
      case VideoQualityProfile.low:
        return camera.previewWidth == 640 &&
            camera.previewHeight == 360;

      case VideoQualityProfile.medium:
        return camera.previewWidth == 960 &&
            camera.previewHeight == 540;

      case VideoQualityProfile.hd:
        return camera.previewWidth == 1280 &&
            camera.previewHeight == 720;

      case VideoQualityProfile.fullHd:
        return camera.previewWidth == 1920 &&
            camera.previewHeight == 1080;
    }
  }

  VideoQualityProfile _resolveProfileFromResolution(
      int width,
      int height,
      ) {
    final int pixels = width * height;

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

  // =============================================================
  // SERIALIZED OPERATION ENGINE
  // =============================================================

  Future<T> _runSerialized<T>(
      String operation,
      Future<T> Function() action,
      ) {
    final Completer<T> completer = Completer<T>();

    _operationQueue = _operationQueue.then<void>(
          (_) async {
        if (_disposed) {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'VideoManager is disposed. '
                    'Operation "$operation" cannot run.',
              ),
            );
          }

          return;
        }

        _suppressCameraNotifications = true;

        try {
          final T result = await action();

          if (!completer.isCompleted) {
            completer.complete(
              result,
            );
          }
        } catch (error, stackTrace) {
          _reportError(
            operation,
            error,
            stackTrace,
          );

          if (!completer.isCompleted) {
            completer.completeError(
              error,
              stackTrace,
            );
          }
        } finally {
          _suppressCameraNotifications = false;

          _notifySafely();
        }
      },
    );

    return completer.future;
  }

  // =============================================================
  // LIFECYCLE HELPERS
  // =============================================================

  void _ensureUsable() {
    if (_disposed) {
      throw StateError(
        'VideoManager has already been disposed.',
      );
    }
  }

  void _notifySafely() {
    if (_disposed) {
      return;
    }

    notifyListeners();
  }

  // =============================================================
  // ERROR LOGGING
  // =============================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [VideoManager/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [VideoManager/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // =============================================================
  // DISPOSE
  // =============================================================

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    camera.removeListener(
      _handleCameraStateChanged,
    );

    _initialized = false;

    camera.dispose();

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 24 VERIFIED CONTRACT:
//
// ✓ Exact current CameraManager API used.
// ✓ No invented CameraManager method.
// ✓ CameraManager remains physical-camera owner.
// ✓ VideoManager remains orchestration/state owner.
//
// ✓ Initialization race no longer drops waiting operations.
// ✓ Video enable/disable operations serialized.
// ✓ Toggle video stale-state race removed.
// ✓ Camera switching serialized.
// ✓ Flash operations serialized.
// ✓ Zoom operations serialized.
// ✓ Resolution changes serialized.
// ✓ FPS changes serialized.
// ✓ Bitrate policy changes serialized.
// ✓ Quality-profile changes serialized.
// ✓ Adaptive settings serialized.
// ✓ Reset serialized.
//
// ✓ Camera-owned width/height read back after physical operation.
// ✓ Camera child-state listener keeps VideoManager synchronized.
// ✓ Front/back, flash and zoom remain CameraManager getters.
// ✓ Actual RTCRtpSender bitrate is NOT applied here.
// ✓ AI switches remain preference state only.
//
// ✓ No MediaStream created.
// ✓ No WebRTCService ownership duplicated.
// ✓ No PeerConnection ownership added.
// ✓ No signaling ownership added.
// ✓ No ICE ownership added.
// ✓ No recovery ownership added.
// ✓ No NetworkManager ownership added.
// ===============================================================