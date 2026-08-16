import 'package:flutter/foundation.dart';

import '../services/call/video_manager.dart';

/// ===========================================================
/// JR CALL
/// File: video_provider.dart
/// Location: lib/providers/video_provider.dart
///
/// Description:
/// Production video-state bridge between VideoManager and UI.
///
/// Architecture ownership:
/// - VideoManager owns video orchestration.
/// - CameraManager owns camera/device operations.
/// - AI Video Engine owns AI decision/optimization logic.
/// - WebRTCService owns WebRTC tracks/peer connection.
/// - VideoProvider exposes synchronized video state to UI.
///
/// Rules:
/// - No duplicate camera implementation.
/// - No duplicate WebRTC logic.
/// - No duplicate AI optimization engine.
/// - No duplicate timer.
/// - No duplicate stream.
/// - No direct platform permission handling.
/// - No independent source-of-truth video state.
/// ===========================================================

class VideoProvider extends ChangeNotifier {
  VideoProvider({VideoManager? videoManager})
    : _videoManager = videoManager ?? VideoManager.instance;

  final VideoManager _videoManager;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _listenerAttached = false;
  bool _operationInProgress = false;

  Future<void>? _initializationFuture;

  String? _lastStateSignature;

  /// ===========================================================
  /// Initialization State
  /// ===========================================================

  bool get isInitialized => _isInitialized;

  bool get isBusy => _operationInProgress;

  /// ===========================================================
  /// Video State
  /// ===========================================================

  bool get videoEnabled => _videoManager.videoEnabled;

  bool get cameraEnabled => _videoManager.videoEnabled;

  /// ===========================================================
  /// Video Quality State
  /// ===========================================================

  int get width => _videoManager.width;

  int get height => _videoManager.height;

  int get fps => _videoManager.fps;

  int get bitrate => _videoManager.bitrate;

  String get resolution => '${_videoManager.width}x${_videoManager.height}';

  Map<String, int> get resolutionProfile => <String, int>{
    'width': _videoManager.width,
    'height': _videoManager.height,
  };

  /// ===========================================================
  /// AI / Enhancement State
  /// ===========================================================

  bool get beautyMode => _videoManager.beautyMode;

  bool get faceEnhancement => _videoManager.faceEnhancement;

  bool get noiseReduction => _videoManager.noiseReduction;

  bool get backgroundBlur => _videoManager.backgroundBlur;

  /// ===========================================================
  /// Initialization
  /// ===========================================================

  Future<void> initialize() {
    if (_isDisposed) {
      return Future<void>.error(
        StateError('VideoProvider has already been disposed.'),
      );
    }

    return _initializationFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    try {
      _attachManagerListener();

      if (!_videoManager.isInitialized) {
        await _videoManager.initialize();
      }

      if (_isDisposed) {
        return;
      }

      _isInitialized = true;
      _lastStateSignature = _buildStateSignature();

      _notifySafely(force: true);
    } catch (error, stackTrace) {
      _initializationFuture = null;

      _reportError('Initialization', error, stackTrace);

      rethrow;
    }
  }

  /// ===========================================================
  /// Video Enable / Disable
  /// ===========================================================

  Future<void> enableVideo() async {
    await _runOperation(_videoManager.enableVideo);
  }

  Future<void> disableVideo() async {
    await _runOperation(_videoManager.disableVideo);
  }

  Future<void> toggleVideo() async {
    await _runOperation(_videoManager.toggleVideo);
  }

  Future<void> setVideoEnabled(bool enabled) async {
    if (enabled == videoEnabled) {
      return;
    }

    if (enabled) {
      await enableVideo();
    } else {
      await disableVideo();
    }
  }

  /// Compatibility alias used by call UI.
  Future<void> setCameraEnabled(bool enabled) {
    return setVideoEnabled(enabled);
  }

  /// ===========================================================
  /// Camera Controls
  /// ===========================================================

  Future<void> switchCamera() async {
    await _runOperation(_videoManager.switchCamera);
  }

  Future<void> toggleFlash() async {
    await _runOperation(_videoManager.toggleFlash);
  }

  Future<void> setZoom(double zoom) async {
    if (!zoom.isFinite) {
      throw ArgumentError.value(zoom, 'zoom', 'Zoom value must be finite.');
    }

    await _runOperation(() async {
      await _videoManager.setZoom(zoom);
    });
  }

  /// ===========================================================
  /// Resolution
  /// ===========================================================

  Future<void> setResolution({required int width, required int height}) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Video resolution must be greater than zero.');
    }

    if (this.width == width && this.height == height) {
      return;
    }

    await _runOperation(() async {
      await _videoManager.setResolution(width: width, height: height);
    });
  }

  /// ===========================================================
  /// Frame Rate
  /// ===========================================================

  Future<void> setFrameRate(int value) async {
    if (value <= 0) {
      throw ArgumentError.value(
        value,
        'value',
        'Frame rate must be greater than zero.',
      );
    }

    if (fps == value) {
      return;
    }

    await _runOperation(() async {
      await _videoManager.setFrameRate(value);
    });
  }

  /// ===========================================================
  /// Bitrate
  /// ===========================================================

  Future<void> setBitrate(int value) async {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'Bitrate cannot be negative.');
    }

    if (bitrate == value) {
      return;
    }

    await _runOperation(() async {
      await _videoManager.setBitrate(value);
    });
  }

  /// ===========================================================
  /// AI Video Features
  /// ===========================================================

  Future<void> setBeautyMode(bool enabled) async {
    if (beautyMode == enabled) {
      return;
    }

    await _runOperation(() async {
      await _videoManager.enableBeautyMode(enabled);
    });
  }

  Future<void> setFaceEnhancement(bool enabled) async {
    if (faceEnhancement == enabled) {
      return;
    }

    await _runOperation(() async {
      await _videoManager.enableFaceEnhancement(enabled);
    });
  }

  Future<void> setNoiseReduction(bool enabled) async {
    if (noiseReduction == enabled) {
      return;
    }

    await _runOperation(() async {
      await _videoManager.enableNoiseReduction(enabled);
    });
  }

  Future<void> setBackgroundBlur(bool enabled) async {
    if (backgroundBlur == enabled) {
      return;
    }

    await _runOperation(() async {
      await _videoManager.enableBackgroundBlur(enabled);
    });
  }

  /// Compatibility aliases.

  Future<void> enableBeautyMode(bool enabled) => setBeautyMode(enabled);

  Future<void> enableFaceEnhancement(bool enabled) =>
      setFaceEnhancement(enabled);

  Future<void> enableNoiseReduction(bool enabled) => setNoiseReduction(enabled);

  Future<void> enableBackgroundBlur(bool enabled) => setBackgroundBlur(enabled);

  /// ===========================================================
  /// Standard Quality Profiles
  /// ===========================================================

  Future<void> applyLowQuality() async {
    await _runOperation(_videoManager.applyLowQuality);
  }

  Future<void> applyMediumQuality() async {
    await _runOperation(_videoManager.applyMediumQuality);
  }

  Future<void> applyHDQuality() async {
    await _runOperation(_videoManager.applyHDQuality);
  }

  Future<void> applyFullHDQuality() async {
    await _runOperation(_videoManager.applyFullHDQuality);
  }

  /// ===========================================================
  /// Dynamic Profile Application
  /// ===========================================================

  Future<void> applyStreamingProfile({
    required int width,
    required int height,
    required int fps,
    required int bitrate,
  }) async {
    if (width <= 0 || height <= 0 || fps <= 0 || bitrate < 0) {
      throw ArgumentError('Invalid video streaming profile.');
    }

    await _runOperation(() async {
      if (_videoManager.width != width || _videoManager.height != height) {
        await _videoManager.setResolution(width: width, height: height);
      }

      if (_videoManager.fps != fps) {
        await _videoManager.setFrameRate(fps);
      }

      if (_videoManager.bitrate != bitrate) {
        await _videoManager.setBitrate(bitrate);
      }
    });
  }

  /// ===========================================================
  /// Refresh
  /// ===========================================================

  Future<void> refresh() async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    _notifySafely(force: true);
  }

  /// ===========================================================
  /// VideoManager Synchronization
  /// ===========================================================

  void _attachManagerListener() {
    if (_listenerAttached || _isDisposed) {
      return;
    }

    _videoManager.addListener(_handleVideoManagerChanged);

    _listenerAttached = true;
  }

  void _detachManagerListener() {
    if (!_listenerAttached) {
      return;
    }

    _videoManager.removeListener(_handleVideoManagerChanged);

    _listenerAttached = false;
  }

  void _handleVideoManagerChanged() {
    if (_isDisposed) {
      return;
    }

    _notifySafely();
  }

  /// ===========================================================
  /// Serialized Operation Guard
  /// ===========================================================

  Future<void> _runOperation(Future<void> Function() operation) async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    if (_operationInProgress) {
      return;
    }

    _operationInProgress = true;
    _notifySafely(force: true);

    try {
      await operation();
    } catch (error, stackTrace) {
      _reportError('Video operation', error, stackTrace);

      rethrow;
    } finally {
      _operationInProgress = false;
      _notifySafely(force: true);
    }
  }

  /// ===========================================================
  /// Duplicate Notification Protection
  /// ===========================================================

  String _buildStateSignature() {
    return <Object?>[
      _isInitialized,
      _operationInProgress,
      videoEnabled,
      width,
      height,
      fps,
      bitrate,
      beautyMode,
      faceEnhancement,
      noiseReduction,
      backgroundBlur,
    ].join('|');
  }

  void _notifySafely({bool force = false}) {
    if (_isDisposed) {
      return;
    }

    final signature = _buildStateSignature();

    if (!force && signature == _lastStateSignature) {
      return;
    }

    _lastStateSignature = signature;

    notifyListeners();
  }

  /// ===========================================================
  /// Reset
  /// ===========================================================

  Future<void> reset() async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    _operationInProgress = true;

    try {
      await _videoManager.reset();

      _isInitialized = _videoManager.isInitialized;
    } catch (error, stackTrace) {
      _reportError('Reset', error, stackTrace);

      rethrow;
    } finally {
      _operationInProgress = false;
      _notifySafely(force: true);
    }
  }

  /// ===========================================================
  /// Error Reporting
  /// ===========================================================

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint('JR CALL [VideoProvider/$source] error: $error');

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [VideoProvider/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  /// ===========================================================
  /// Disposal
  /// ===========================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _detachManagerListener();

    _isDisposed = true;
    _isInitialized = false;
    _operationInProgress = false;
    _initializationFuture = null;
    _lastStateSignature = null;

    /// VideoManager is a shared singleton used by the
    /// complete call engine. Provider disposal therefore
    /// MUST NOT reset or dispose VideoManager.

    super.dispose();
  }
}
