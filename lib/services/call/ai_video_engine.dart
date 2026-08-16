import 'package:flutter/foundation.dart';

import '../../models/network_model.dart';
import 'network_optimizer.dart';
import 'video_manager.dart';

// ===========================================================
// JR CALL
// File: ai_video_engine.dart
// Location: lib/services/call/ai_video_engine.dart
//
// Description:
// Production AI-assisted video optimization coordinator.
//
// Architecture:
//
// NetworkManager
//      ↓
// NetworkOptimizer
//      ↓
// AIVideoEngine
//      ↓
// VideoManager
//
// Ownership:
// - NetworkManager owns network measurement
// - NetworkOptimizer owns optimization policy
// - VideoManager owns camera/video presentation state
// - WebRTC/Bitrate layer owns sender-level bitrate mutation
// - AIVideoEngine coordinates adaptive video decisions only
//
// Rules:
// - No NetworkHelper polling
// - No duplicate timers
// - No direct WebRTC lifecycle
// - No signaling
// - No ICE
// - No recovery duplication
// ===========================================================

class AIVideoEngine extends ChangeNotifier {
  AIVideoEngine._();

  static final AIVideoEngine instance = AIVideoEngine._();

  // ===========================================================
  // Dependencies
  // ===========================================================

  final NetworkOptimizer _networkOptimizer = NetworkOptimizer.instance;

  final VideoManager _videoManager = VideoManager.instance;

  // ===========================================================
  // Runtime State
  // ===========================================================

  bool _initialized = false;
  bool _initializing = false;

  bool _aiEnabled = true;

  bool _optimizing = false;
  bool _optimizationPending = false;

  bool _disposed = false;

  int _generation = 0;

  NetworkQuality _networkQuality = NetworkQuality.good;

  int _bitrate = 1500000;
  int _fps = 30;

  int _width = 1280;
  int _height = 720;

  Object? _lastError;

  // ===========================================================
  // Public State
  // ===========================================================

  bool get initialized => _initialized;

  bool get isInitialized => _initialized;

  bool get isInitializing => _initializing;

  bool get aiEnabled => _aiEnabled;

  bool get isOptimizing => _optimizing;

  bool get isDisposed => _disposed;

  NetworkQuality get networkQuality => _networkQuality;

  int get bitrate => _bitrate;

  int get fps => _fps;

  int get width => _width;

  int get height => _height;

  Object? get lastError => _lastError;

  Map<String, int> get resolution => <String, int>{
    'width': _width,
    'height': _height,
  };

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize() async {
    _ensureUsable();

    if (_initialized) {
      return;
    }

    if (_initializing) {
      while (_initializing && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      return;
    }

    _initializing = true;
    _lastError = null;

    final generation = _generation;

    try {
      if (!_networkOptimizer.isInitialized) {
        await _networkOptimizer.initialize();
      }

      if (!_isGenerationValid(generation)) {
        return;
      }

      if (!_videoManager.isInitialized) {
        await _videoManager.initialize();
      }

      if (!_isGenerationValid(generation)) {
        return;
      }

      _initialized = true;

      await _analyzeNetworkInternal(generation);

      if (!_isGenerationValid(generation)) {
        return;
      }

      _notifySafely();

      debugPrint('JR CALL: AIVideoEngine initialized.');
    } catch (error, stackTrace) {
      _initialized = false;
      _lastError = error;

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
  // AI State
  // ===========================================================

  Future<void> enableAI() async {
    _ensureUsable();

    if (_aiEnabled) {
      return;
    }

    _aiEnabled = true;

    _notifySafely();
  }

  Future<void> disableAI() async {
    _ensureUsable();

    if (!_aiEnabled) {
      return;
    }

    _aiEnabled = false;
    _optimizationPending = false;

    _notifySafely();
  }

  Future<void> setAIEnabled(bool enabled) async {
    if (enabled) {
      await enableAI();
    } else {
      await disableAI();
    }
  }

  // ===========================================================
  // Network Analysis
  // ===========================================================

  Future<void> analyzeNetwork() async {
    await _ensureInitialized();

    final generation = _generation;

    await _analyzeNetworkInternal(generation);
  }

  Future<void> _analyzeNetworkInternal(int generation) async {
    if (!_isGenerationValid(generation)) {
      return;
    }

    final network = _networkOptimizer.currentNetwork;

    final recommendedBitrate = await _networkOptimizer.videoBitrate;

    if (!_isGenerationValid(generation)) {
      return;
    }

    final recommendedFps = await _networkOptimizer.fps;

    if (!_isGenerationValid(generation)) {
      return;
    }

    final recommendedResolution = await _networkOptimizer.resolutionProfile;

    if (!_isGenerationValid(generation)) {
      return;
    }

    final resolvedWidth = recommendedResolution['width'] ?? network.videoWidth;

    final resolvedHeight =
        recommendedResolution['height'] ?? network.videoHeight;

    _networkQuality = network.quality;

    _bitrate = recommendedBitrate < 0 ? 0 : recommendedBitrate;

    _fps = recommendedFps <= 0 ? 15 : recommendedFps;

    _width = resolvedWidth > 0 ? resolvedWidth : 640;

    _height = resolvedHeight > 0 ? resolvedHeight : 360;

    _notifySafely();
  }

  // ===========================================================
  // Video Optimization
  // ===========================================================

  Future<void> optimizeVideo() async {
    await _ensureInitialized();

    if (!_aiEnabled || _disposed) {
      return;
    }

    if (_optimizing) {
      _optimizationPending = true;
      return;
    }

    _optimizing = true;
    _lastError = null;

    final generation = _generation;

    try {
      do {
        _optimizationPending = false;

        await _analyzeNetworkInternal(generation);

        if (!_isGenerationValid(generation) || !_aiEnabled) {
          return;
        }

        final videoEnabled = await _networkOptimizer.enableVideo;

        if (!_isGenerationValid(generation)) {
          return;
        }

        if (!videoEnabled) {
          if (_videoManager.videoEnabled) {
            await _videoManager.disableVideo();
          }

          continue;
        }

        if (!_videoManager.videoEnabled) {
          await _videoManager.enableVideo();
        }

        if (!_isGenerationValid(generation)) {
          return;
        }

        await _videoManager.applyAdaptiveSettings(
          width: _width,
          height: _height,
          fps: _fps,
          bitrate: _bitrate,
        );

        if (!_isGenerationValid(generation)) {
          return;
        }

        await _applyEnhancementPolicy(generation);
      } while (_optimizationPending &&
          _isGenerationValid(generation) &&
          _aiEnabled);
    } catch (error, stackTrace) {
      _lastError = error;

      _reportError('optimizeVideo', error, stackTrace);
    } finally {
      _optimizing = false;

      _notifySafely();
    }
  }

  // ===========================================================
  // Enhancement Policy
  // ===========================================================

  Future<void> _applyEnhancementPolicy(int generation) async {
    if (!_isGenerationValid(generation)) {
      return;
    }

    final noiseReduction = await _networkOptimizer.enableNoiseReduction;

    if (!_isGenerationValid(generation)) {
      return;
    }

    final hdEnabled = await _networkOptimizer.enableHD;

    if (!_isGenerationValid(generation)) {
      return;
    }

    final superResolution = await _networkOptimizer.enableSuperResolution;

    if (!_isGenerationValid(generation)) {
      return;
    }

    await _videoManager.enableNoiseReduction(noiseReduction);

    if (!_isGenerationValid(generation)) {
      return;
    }

    switch (_networkQuality) {
      case NetworkQuality.excellent:
        await _videoManager.enableFaceEnhancement(true);

        await _videoManager.enableBeautyMode(superResolution);

        await _videoManager.enableBackgroundBlur(false);

        if (!hdEnabled &&
            _videoManager.qualityProfile == VideoQualityProfile.fullHd) {
          await _videoManager.applyHDQuality();
        }

        break;

      case NetworkQuality.good:
        await _videoManager.enableFaceEnhancement(true);

        await _videoManager.enableBeautyMode(false);

        await _videoManager.enableBackgroundBlur(false);

        break;

      case NetworkQuality.fair:
        await _disableExpensiveEnhancements();
        break;

      case NetworkQuality.poor:
      case NetworkQuality.offline:
        await _disableExpensiveEnhancements();
        break;
    }
  }

  Future<void> _disableExpensiveEnhancements() async {
    await _videoManager.enableFaceEnhancement(false);

    await _videoManager.enableBeautyMode(false);

    await _videoManager.enableBackgroundBlur(false);
  }

  // ===========================================================
  // Backward Compatibility
  // ===========================================================

  /// Older integrations may still call optimizeAudio().
  ///
  /// Keep this alias until every dependent file has migrated.
  Future<void> optimizeAudio() async {
    await optimizeVideo();
  }

  // ===========================================================
  // State Snapshot
  // ===========================================================

  Map<String, dynamic> get stateSnapshot {
    return <String, dynamic>{
      'initialized': _initialized,
      'initializing': _initializing,
      'aiEnabled': _aiEnabled,
      'optimizing': _optimizing,
      'networkQuality': _networkQuality.name,
      'bitrate': _bitrate,
      'fps': _fps,
      'width': _width,
      'height': _height,
      'videoEnabled': _videoManager.videoEnabled,
      'qualityProfile': _videoManager.qualityProfile.name,
      'lastError': _lastError?.toString(),
    };
  }

  // ===========================================================
  // Reset
  // ===========================================================

  Future<void> reset() async {
    if (_disposed) {
      return;
    }

    _generation++;

    _initialized = false;
    _initializing = false;

    _optimizing = false;
    _optimizationPending = false;

    _aiEnabled = true;

    _networkQuality = NetworkQuality.good;

    _bitrate = 1500000;
    _fps = 30;

    _width = 1280;
    _height = 720;

    _lastError = null;

    _notifySafely();
  }

  // ===========================================================
  // Internal Helpers
  // ===========================================================

  bool _isGenerationValid(int generation) {
    return !_disposed && generation == _generation;
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('AIVideoEngine has already been disposed.');
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint(
      'JR CALL [AIVideoEngine/$source] '
      'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [AIVideoEngine/$source]',
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

    _generation++;

    _disposed = true;

    _initialized = false;
    _initializing = false;

    _optimizing = false;
    _optimizationPending = false;

    _lastError = null;

    super.dispose();
  }
}
