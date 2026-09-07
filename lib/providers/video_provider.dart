import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/call/video_manager.dart';

/// ===========================================================
/// JR CALL
/// File: video_provider.dart
/// Location: lib/providers/video_provider.dart
///
/// MASTER PRODUCTION VIDEO PROVIDER
///
/// RESPONSIBILITIES:
///
/// - Bridge VideoManager state to Presentation/UI.
/// - Expose video enabled state.
/// - Expose video quality presentation state.
/// - Expose AI/enhancement presentation state.
/// - Coordinate UI video actions through VideoManager.
/// - Serialize normal UI video operations.
/// - Prevent silently dropped UI operations.
/// - Prevent duplicate presentation notifications.
///
/// OWNERSHIP:
///
/// VideoManager:
/// - Video orchestration.
/// - Camera coordination.
/// - Quality-profile state.
/// - Adaptive video settings.
///
/// CameraManager:
/// - Physical camera/device state.
///
/// AI Video Engine:
/// - AI video decisions/optimization.
///
/// WebRTCService:
/// - MediaStream / MediaStreamTrack.
/// - PeerConnection.
/// - Actual media transport.
///
/// BitrateController:
/// - Actual WebRTC sender bitrate application.
///
/// VideoProvider:
/// - Presentation bridge only.
///
/// IMPORTANT:
///
/// - No duplicate camera implementation.
/// - No duplicate WebRTC logic.
/// - No duplicate AI engine.
/// - No timer ownership.
/// - No stream ownership.
/// - No permission ownership.
/// - No independent video source of truth.
/// ===========================================================

class VideoProvider extends ChangeNotifier {
  VideoProvider({
    VideoManager? videoManager,
  }) : _videoManager = videoManager ?? VideoManager.instance;

  // ===========================================================
  // DEPENDENCY
  // ===========================================================

  final VideoManager _videoManager;

  // ===========================================================
  // LIFECYCLE
  // ===========================================================

  bool _isInitialized = false;

  bool _isDisposed = false;

  bool _listenerAttached = false;

  Future<void>? _initializationFuture;

  // ===========================================================
  // OPERATION STATE
  // ===========================================================

  Future<void> _operationQueue = Future<void>.value();

  int _activeOperations = 0;

  // ===========================================================
  // DUPLICATE NOTIFICATION PROTECTION
  // ===========================================================

  String? _lastStateSignature;

  // ===========================================================
  // INITIALIZATION STATE
  // ===========================================================

  bool get isInitialized => _isInitialized;

  bool get isDisposed => _isDisposed;

  bool get isBusy => _activeOperations > 0;

  // ===========================================================
  // VIDEO STATE
  // ===========================================================

  bool get videoEnabled => _videoManager.videoEnabled;

  bool get cameraEnabled => _videoManager.videoEnabled;

  // ===========================================================
  // VIDEO QUALITY STATE
  // ===========================================================

  int get width => _videoManager.width;

  int get height => _videoManager.height;

  int get fps => _videoManager.fps;

  int get bitrate => _videoManager.bitrate;

  String get resolution =>
      '${_videoManager.width}x${_videoManager.height}';

  Map<String, int> get resolutionProfile => <String, int>{
    'width': _videoManager.width,
    'height': _videoManager.height,
  };

  // ===========================================================
  // AI / ENHANCEMENT STATE
  // ===========================================================

  bool get beautyMode => _videoManager.beautyMode;

  bool get faceEnhancement => _videoManager.faceEnhancement;

  bool get noiseReduction => _videoManager.noiseReduction;

  bool get backgroundBlur => _videoManager.backgroundBlur;

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() {
    if (_isDisposed) {
      return Future<void>.error(
        StateError(
          'VideoProvider has already been disposed.',
        ),
      );
    }

    if (_isInitialized &&
        _videoManager.isInitialized) {
      return Future<void>.value();
    }

    final Future<void>? existing =
        _initializationFuture;

    if (existing != null) {
      return existing;
    }

    final Future<void> future =
    _initializeInternal();

    _initializationFuture = future;

    return future;
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

      _isInitialized =
          _videoManager.isInitialized;

      _lastStateSignature =
          _buildStateSignature();

      _notifySafely(
        force: true,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Initialization',
        error,
        stackTrace,
      );

      rethrow;
    } finally {
      _initializationFuture = null;
    }
  }

  // ===========================================================
  // VIDEO ENABLE / DISABLE
  // ===========================================================

  Future<void> enableVideo() {
    return _runOperation(
      _videoManager.enableVideo,
    );
  }

  Future<void> disableVideo() {
    return _runOperation(
      _videoManager.disableVideo,
    );
  }

  Future<void> toggleVideo() {
    return _runOperation(
      _videoManager.toggleVideo,
    );
  }

  Future<void> setVideoEnabled(
      bool enabled,
      ) {
    return _runOperation(
          () => _videoManager.setVideoEnabled(
        enabled,
      ),
    );
  }

  /// Compatibility alias used by call UI.
  Future<void> setCameraEnabled(
      bool enabled,
      ) {
    return setVideoEnabled(
      enabled,
    );
  }

  // ===========================================================
  // CAMERA CONTROLS
  // ===========================================================

  Future<void> switchCamera() {
    return _runOperation(
      _videoManager.switchCamera,
    );
  }

  Future<void> toggleFlash() {
    return _runOperation(
      _videoManager.toggleFlash,
    );
  }

  Future<void> setZoom(
      double zoom,
      ) {
    if (!zoom.isFinite) {
      return Future<void>.error(
        ArgumentError.value(
          zoom,
          'zoom',
          'Zoom value must be finite.',
        ),
      );
    }

    return _runOperation(
          () => _videoManager.setZoom(
        zoom,
      ),
    );
  }

  // ===========================================================
  // RESOLUTION
  // ===========================================================

  Future<void> setResolution({
    required int width,
    required int height,
  }) {
    if (width <= 0 ||
        height <= 0) {
      return Future<void>.error(
        ArgumentError(
          'Video resolution must be greater than zero.',
        ),
      );
    }

    return _runOperation(
          () => _videoManager.setResolution(
        width: width,
        height: height,
      ),
    );
  }

  // ===========================================================
  // FRAME RATE
  // ===========================================================

  Future<void> setFrameRate(
      int value,
      ) {
    if (value < 1 ||
        value > 120) {
      return Future<void>.error(
        ArgumentError.value(
          value,
          'value',
          'Frame rate must be between 1 and 120.',
        ),
      );
    }

    return _runOperation(
          () => _videoManager.setFrameRate(
        value,
      ),
    );
  }

  // ===========================================================
  // BITRATE
  // ===========================================================

  Future<void> setBitrate(
      int value,
      ) {
    if (value < 0) {
      return Future<void>.error(
        ArgumentError.value(
          value,
          'value',
          'Bitrate cannot be negative.',
        ),
      );
    }

    return _runOperation(
          () => _videoManager.setBitrate(
        value,
      ),
    );
  }

  // ===========================================================
  // AI VIDEO FEATURES
  // ===========================================================

  Future<void> setBeautyMode(
      bool enabled,
      ) {
    return _runOperation(
          () => _videoManager.enableBeautyMode(
        enabled,
      ),
    );
  }

  Future<void> setFaceEnhancement(
      bool enabled,
      ) {
    return _runOperation(
          () => _videoManager.enableFaceEnhancement(
        enabled,
      ),
    );
  }

  Future<void> setNoiseReduction(
      bool enabled,
      ) {
    return _runOperation(
          () => _videoManager.enableNoiseReduction(
        enabled,
      ),
    );
  }

  Future<void> setBackgroundBlur(
      bool enabled,
      ) {
    return _runOperation(
          () => _videoManager.enableBackgroundBlur(
        enabled,
      ),
    );
  }

  // ===========================================================
  // COMPATIBILITY ALIASES
  // ===========================================================

  Future<void> enableBeautyMode(
      bool enabled,
      ) {
    return setBeautyMode(
      enabled,
    );
  }

  Future<void> enableFaceEnhancement(
      bool enabled,
      ) {
    return setFaceEnhancement(
      enabled,
    );
  }

  Future<void> enableNoiseReduction(
      bool enabled,
      ) {
    return setNoiseReduction(
      enabled,
    );
  }

  Future<void> enableBackgroundBlur(
      bool enabled,
      ) {
    return setBackgroundBlur(
      enabled,
    );
  }

  // ===========================================================
  // STANDARD QUALITY PROFILES
  // ===========================================================

  Future<void> applyLowQuality() {
    return _runOperation(
      _videoManager.applyLowQuality,
    );
  }

  Future<void> applyMediumQuality() {
    return _runOperation(
      _videoManager.applyMediumQuality,
    );
  }

  Future<void> applyHDQuality() {
    return _runOperation(
      _videoManager.applyHDQuality,
    );
  }

  Future<void> applyFullHDQuality() {
    return _runOperation(
      _videoManager.applyFullHDQuality,
    );
  }

  // ===========================================================
  // DYNAMIC PROFILE APPLICATION
  //
  // VideoManager already owns the unified adaptive-profile API.
  // Provider must not rebuild the same orchestration manually.
  // ===========================================================

  Future<void> applyStreamingProfile({
    required int width,
    required int height,
    required int fps,
    required int bitrate,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        fps < 1 ||
        fps > 120 ||
        bitrate < 0) {
      return Future<void>.error(
        ArgumentError(
          'Invalid video streaming profile.',
        ),
      );
    }

    return _runOperation(
          () => _videoManager.applyAdaptiveSettings(
        width: width,
        height: height,
        fps: fps,
        bitrate: bitrate,
      ),
    );
  }

  // ===========================================================
  // REFRESH
  // ===========================================================

  Future<void> refresh() async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    _isInitialized =
        _videoManager.isInitialized;

    _notifySafely(
      force: true,
    );
  }

  // ===========================================================
  // VIDEO MANAGER SYNCHRONIZATION
  // ===========================================================

  void _attachManagerListener() {
    if (_listenerAttached ||
        _isDisposed) {
      return;
    }

    _videoManager.addListener(
      _handleVideoManagerChanged,
    );

    _listenerAttached = true;
  }

  void _detachManagerListener() {
    if (!_listenerAttached) {
      return;
    }

    _videoManager.removeListener(
      _handleVideoManagerChanged,
    );

    _listenerAttached = false;
  }

  void _handleVideoManagerChanged() {
    if (_isDisposed) {
      return;
    }

    _isInitialized =
        _videoManager.isInitialized;

    _notifySafely();
  }

  // ===========================================================
  // SERIALIZED OPERATION ENGINE
  //
  // UI operations are queued, not silently discarded.
  // ===========================================================

  Future<void> _runOperation(
      Future<void> Function() operation,
      ) async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    final Completer<void> completer =
    Completer<void>();

    _beginBusyOperation();

    _operationQueue =
        _operationQueue.then<void>(
              (_) async {
            if (_isDisposed) {
              if (!completer.isCompleted) {
                completer.complete();
              }

              _endBusyOperation();

              return;
            }

            try {
              await operation();

              if (!completer.isCompleted) {
                completer.complete();
              }
            } catch (error, stackTrace) {
              _reportError(
                'Video operation',
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
              _endBusyOperation();
            }
          },
        );

    await completer.future;
  }

  // ===========================================================
  // BUSY STATE
  // ===========================================================

  void _beginBusyOperation() {
    if (_isDisposed) {
      return;
    }

    _activeOperations++;

    _notifySafely(
      force: true,
    );
  }

  void _endBusyOperation() {
    if (_activeOperations > 0) {
      _activeOperations--;
    }

    _notifySafely(
      force: true,
    );
  }

  // ===========================================================
  // DUPLICATE NOTIFICATION PROTECTION
  // ===========================================================

  String _buildStateSignature() {
    return <Object?>[
      _isInitialized,
      isBusy,
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

  void _notifySafely({
    bool force = false,
  }) {
    if (_isDisposed) {
      return;
    }

    final String signature =
    _buildStateSignature();

    if (!force &&
        signature ==
            _lastStateSignature) {
      return;
    }

    _lastStateSignature =
        signature;

    notifyListeners();
  }

  // ===========================================================
  // RESET
  //
  // VideoManager owns reset semantics.
  //
  // After reset VideoManager intentionally reports
  // isInitialized == false. The next provider operation
  // therefore performs a real initialization again.
  // ===========================================================

  Future<void> reset() async {
    if (_isDisposed) {
      return;
    }

    await _runOperation(
      _videoManager.reset,
    );

    if (_isDisposed) {
      return;
    }

    _isInitialized =
        _videoManager.isInitialized;

    _notifySafely(
      force: true,
    );
  }

  // ===========================================================
  // ERROR REPORTING
  // ===========================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [VideoProvider/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL [VideoProvider/$source]',
        stackTrace:
        stackTrace,
      );
    }
  }

  // ===========================================================
  // DISPOSAL
  //
  // VideoManager is shared by the call engine.
  // Provider disposal MUST NOT reset/dispose VideoManager.
  // ===========================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _detachManagerListener();

    _isDisposed = true;

    _isInitialized = false;

    _activeOperations = 0;

    _initializationFuture = null;

    _lastStateSignature = null;

    super.dispose();
  }
}