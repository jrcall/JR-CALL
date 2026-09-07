import 'package:flutter/foundation.dart';

import '../../models/network_model.dart';
import '../managers/video_manager.dart';
import 'network_optimizer.dart';

// ===========================================================
// JR CALL
// File: ai_video_engine.dart
// Location: lib/services/call/ai_video_engine.dart
//
// FINAL PRODUCTION AI-ASSISTED VIDEO POLICY COORDINATOR.
//
// Architecture:
//
// NetworkManager
//      â†“
// NetworkOptimizer
//      â†“
// AIVideoEngine
//      â†“
// VideoManager / WebRTC Media Adaptation Layer
//
// Ownership:
//
// NetworkManager:
// - Network measurement.
//
// NetworkOptimizer:
// - Adaptive video policy.
//
// VideoManager:
// - Renderer and video-track presentation state.
//
// WebRTC / Media Adaptation Layer:
// - Actual sender bitrate/FPS/resolution mutation.
//
// AIVideoEngine:
// - Coordinates and exposes video recommendations only.
//
// IMPORTANT:
//
// - No NetworkHelper polling.
// - No duplicate timer.
// - No direct WebRTC lifecycle.
// - No signaling.
// - No ICE.
// - No recovery duplication.
// - No MediaStream acquisition.
// - Does not override user camera/video enable state.
// - No UI/design changes.
// ===========================================================

class AIVideoEngine extends ChangeNotifier {
  AIVideoEngine._();

  static final AIVideoEngine instance = AIVideoEngine._();

  // ===========================================================
  // DEPENDENCIES
  // ===========================================================

  final NetworkOptimizer _networkOptimizer = NetworkOptimizer.instance;

  final VideoManager _videoManager = VideoManager.instance;

  // ===========================================================
  // RUNTIME STATE
  // ===========================================================

  bool _initialized = false;

  bool _initializing = false;

  bool _aiEnabled = true;

  bool _optimizing = false;

  bool _optimizationPending = false;

  bool _disposed = false;

  int _generation = 0;

  int? _activeInitializationGeneration;

  Future<void>? _initializationFuture;

  Future<void>? _optimizationFuture;

  NetworkQuality _networkQuality = NetworkQuality.good;

  int _bitrate = 1500000;

  int _fps = 30;

  int _width = 1280;

  int _height = 720;

  Object? _lastError;

  // ===========================================================
  // PUBLIC STATE
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

  Map<String, int> get resolution => Map<String, int>.unmodifiable(
    <String, int>{'width': _width, 'height': _height},
  );

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() {
    _ensureUsable();

    if (_initialized) {
      return Future<void>.value();
    }

    final Future<void>? existing = _initializationFuture;

    if (existing != null) {
      return existing;
    }

    final int generation = _generation;

    final Future<void> operation = _initializeInternal(generation);

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(_initializationFuture, tracked)) {
        _initializationFuture = null;
      }
    });

    _initializationFuture = tracked;

    return tracked;
  }

  Future<void> _initializeInternal(int generation) async {
    if (!_isGenerationValid(generation)) {
      return;
    }

    _initializing = true;

    _activeInitializationGeneration = generation;

    _lastError = null;

    _notifySafely();

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

      final _VideoPolicySnapshot? policy = await _captureVideoPolicy(
        generation,
      );

      if (!_isGenerationValid(generation)) {
        return;
      }

      if (policy != null) {
        _applyPolicyState(policy);
      }

      _initialized = true;

      _notifySafely();

      _debugPrint('initialized.');
    } catch (error, stackTrace) {
      if (_isGenerationValid(generation)) {
        _initialized = false;

        _lastError = error;

        _reportError('initialize', error, stackTrace);
      }

      rethrow;
    } finally {
      if (_activeInitializationGeneration == generation) {
        _activeInitializationGeneration = null;

        _initializing = false;

        _notifySafely();
      }
    }
  }

  Future<void> _ensureInitialized() async {
    _ensureUsable();

    while (!_initialized && !_disposed) {
      await initialize();

      if (_initialized || _disposed) {
        break;
      }
    }
  }

  // ===========================================================
  // AI STATE
  // ===========================================================

  Future<void> enableAI() async {
    _ensureUsable();

    if (_aiEnabled) {
      return;
    }

    _aiEnabled = true;

    _lastError = null;

    _notifySafely();
  }

  Future<void> disableAI() async {
    _ensureUsable();

    if (!_aiEnabled) {
      return;
    }

    // Invalidate in-flight AI optimization before further
    // recommendations can be committed.

    _generation++;

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
  // NETWORK ANALYSIS
  // ===========================================================

  Future<void> analyzeNetwork() async {
    await _ensureInitialized();

    if (_disposed) {
      return;
    }

    final int generation = _generation;

    final _VideoPolicySnapshot? policy = await _captureVideoPolicy(generation);

    if (!_isGenerationValid(generation) || policy == null) {
      return;
    }

    _applyPolicyState(policy);

    _notifySafely();
  }

  // ===========================================================
  // VIDEO OPTIMIZATION
  //
  // IMPORTANT:
  //
  // This engine computes policy only.
  //
  // It intentionally does NOT:
  // - enable the user's video,
  // - disable the user's video,
  // - mutate RTCRtpSender,
  // - acquire a new MediaStream,
  // - change renderer ownership.
  //
  // Actual media adaptation belongs to the WebRTC/media layer.
  // ===========================================================

  Future<void> optimizeVideo() async {
    await _ensureInitialized();

    if (_disposed || !_aiEnabled) {
      return;
    }

    final Future<void>? active = _optimizationFuture;

    if (active != null) {
      _optimizationPending = true;

      await active;

      return;
    }

    final int generation = _generation;

    final Future<void> operation = _optimizeVideoInternal(generation);

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(_optimizationFuture, tracked)) {
        _optimizationFuture = null;
      }
    });

    _optimizationFuture = tracked;

    await tracked;
  }

  Future<void> _optimizeVideoInternal(int generation) async {
    if (!_isGenerationValid(generation) || !_aiEnabled) {
      return;
    }

    _optimizing = true;

    _lastError = null;

    _notifySafely();

    try {
      do {
        _optimizationPending = false;

        if (!_isGenerationValid(generation) || !_aiEnabled) {
          break;
        }

        final _VideoPolicySnapshot? policy = await _captureVideoPolicy(
          generation,
        );

        if (!_isGenerationValid(generation) || !_aiEnabled || policy == null) {
          break;
        }

        _applyPolicyState(policy);

        // No direct VideoManager mutation here.
        //
        // User video state remains user/media-layer controlled.
        // Temporary network loss must not silently turn the
        // user's camera off or back on.
      } while (_optimizationPending &&
          _isGenerationValid(generation) &&
          _aiEnabled);
    } catch (error, stackTrace) {
      if (_isGenerationValid(generation)) {
        _lastError = error;

        _reportError('optimizeVideo', error, stackTrace);
      }
    } finally {
      _optimizing = false;

      _notifySafely();
    }
  }

  // ===========================================================
  // CONSISTENT VIDEO POLICY SNAPSHOT
  //
  // NetworkOptimizer.recommendedProfile is:
  //
  // Future<Map<String, dynamic>>
  //
  // It must always be awaited before being treated as a Map.
  // ===========================================================

  Future<_VideoPolicySnapshot?> _captureVideoPolicy(int generation) async {
    const int maxAttempts = 3;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (!_isGenerationValid(generation)) {
        return null;
      }

      final NetworkModel network = _networkOptimizer.currentNetwork;

      final Map<String, dynamic> profile =
          await _networkOptimizer.recommendedProfile;

      if (!_isGenerationValid(generation)) {
        return null;
      }

      if (!identical(network, _networkOptimizer.currentNetwork)) {
        continue;
      }

      final int bitrate = _readNonNegativeInt(profile['videoBitrate']) ?? 0;

      final int fps = _readNonNegativeInt(profile['fps']) ?? 0;

      final int width = _readPositiveInt(profile['width']) ?? 640;

      final int height = _readPositiveInt(profile['height']) ?? 360;

      return _VideoPolicySnapshot(
        network: network,
        bitrate: bitrate,
        fps: fps,
        width: width,
        height: height,
      );
    }

    // Network changed throughout all bounded attempts.
    // Do not manufacture a mixed policy. A later dependency
    // update will request optimization again.

    return null;
  }

  // ===========================================================
  // POLICY STATE
  // ===========================================================

  void _applyPolicyState(_VideoPolicySnapshot policy) {
    _networkQuality = policy.network.quality;

    _bitrate = policy.bitrate;

    _fps = policy.fps;

    _width = policy.width;

    _height = policy.height;
  }

  // ===========================================================
  // BACKWARD COMPATIBILITY
  // ===========================================================

  Future<void> optimizeAudio() async {
    await optimizeVideo();
  }

  // ===========================================================
  // STATE SNAPSHOT
  // ===========================================================

  Map<String, dynamic> get stateSnapshot {
    return Map<String, dynamic>.unmodifiable(<String, dynamic>{
      'initialized': _initialized,
      'initializing': _initializing,
      'aiEnabled': _aiEnabled,
      'optimizing': _optimizing,
      'networkQuality': _networkQuality.name,
      'bitrate': _bitrate,
      'fps': _fps,
      'width': _width,
      'height': _height,
      'videoEnabled': _videoManager.isVideoEnabled,
      'qualityProfile': _recommendedQualityProfile(),
      'lastError': _lastError?.toString(),
    });
  }

  String _recommendedQualityProfile() {
    if (_width >= 1920 && _height >= 1080) {
      return 'fullHd';
    }

    if (_width >= 1280 && _height >= 720) {
      return 'hd';
    }

    if (_width >= 854 && _height >= 480) {
      return 'standard';
    }

    return 'low';
  }

  // ===========================================================
  // VALUE HELPERS
  // ===========================================================

  int? _readNonNegativeInt(Object? value) {
    int? result;

    if (value is int) {
      result = value;
    } else if (value is num && value.isFinite) {
      result = value.toInt();
    } else if (value is String) {
      result = int.tryParse(value.trim());
    }

    if (result == null || result < 0) {
      return null;
    }

    return result;
  }

  int? _readPositiveInt(Object? value) {
    final int? result = _readNonNegativeInt(value);

    if (result == null || result <= 0) {
      return null;
    }

    return result;
  }

  // ===========================================================
  // RESET
  // ===========================================================

  Future<void> reset() async {
    if (_disposed) {
      return;
    }

    _generation++;

    _optimizationPending = false;

    final Future<void>? initialization = _initializationFuture;

    final Future<void>? optimization = _optimizationFuture;

    if (initialization != null) {
      try {
        await initialization;
      } catch (error, stackTrace) {
        _reportError('stale initialization during reset', error, stackTrace);
      }
    }

    if (optimization != null) {
      try {
        await optimization;
      } catch (error, stackTrace) {
        _reportError('stale optimization during reset', error, stackTrace);
      }
    }

    if (_disposed) {
      return;
    }

    // NetworkOptimizer and VideoManager are shared Call Engine
    // services and are intentionally NOT reset here.

    _initialized = false;

    _initializing = false;

    _activeInitializationGeneration = null;

    _optimizing = false;

    _optimizationPending = false;

    _aiEnabled = true;

    _networkQuality = NetworkQuality.good;

    _bitrate = 1500000;

    _fps = 30;

    _width = 1280;

    _height = 720;

    _lastError = null;

    _initializationFuture = null;

    _optimizationFuture = null;

    _notifySafely();

    _debugPrint('reset.');
  }

  // ===========================================================
  // INTERNAL HELPERS
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

  void _debugPrint(String message) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
      '[AIVideoEngine] '
      '$message',
    );
  }

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
      '[AIVideoEngine/$source] '
      'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
            'JR CALL '
            '[AIVideoEngine/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // DISPOSE
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

    _activeInitializationGeneration = null;

    _optimizing = false;

    _optimizationPending = false;

    _initializationFuture = null;

    _optimizationFuture = null;

    _lastError = null;

    // Shared VideoManager / NetworkOptimizer are intentionally
    // not disposed here.

    super.dispose();
  }
}

// ===========================================================
// INTERNAL VIDEO POLICY SNAPSHOT
// ===========================================================

class _VideoPolicySnapshot {
  final NetworkModel network;

  final int bitrate;

  final int fps;

  final int width;

  final int height;

  const _VideoPolicySnapshot({
    required this.network,
    required this.bitrate,
    required this.fps,
    required this.width,
    required this.height,
  });
}

// ===============================================================
// END OF FILE
//
// FILE 25 FINAL GUARANTEES:
//
// âœ“ Existing AIVideoEngine public APIs preserved.
// âœ“ Existing optimizeAudio compatibility alias preserved.
// âœ“ Finalized FILE 14 VideoManager import/API aligned.
// âœ“ No nonexistent VideoManager methods called.
// âœ“ VideoManager.isVideoEnabled used correctly.
// âœ“ NetworkOptimizer remains adaptive policy owner.
// âœ“ VideoManager remains renderer/video-track state owner.
// âœ“ Sender bitrate/FPS/resolution mutation remains downstream-owned.
// âœ“ AI never overrides explicit user camera/video state.
// âœ“ Temporary offline state cannot silently disable user video.
// âœ“ No direct network polling/timer added.
// âœ“ No MediaStream acquisition.
// âœ“ No signaling/ICE/recovery ownership.
// âœ“ No PeerConnection lifecycle ownership.
// âœ“ Initialization Future concurrency-deduplicated.
// âœ“ 10ms busy-wait initialization loop removed.
// âœ“ Initialization generation-guarded.
// âœ“ Disable/reset/dispose invalidate stale async work.
// âœ“ Optimization serialized/coalesced.
// âœ“ NetworkOptimizer recommendedProfile is explicitly awaited.
// âœ“ No Future<Map> used as a synchronous Map.
// âœ“ One stable NetworkModel snapshot used per policy.
// âœ“ Mixed network policy snapshots are rejected.
// âœ“ Bitrate remains bits per second.
// âœ“ Offline FPS may remain 0; fake 15 FPS is not invented.
// âœ“ Resolution dimensions validated with safe fallback.
// âœ“ resolution is unmodifiable.
// âœ“ stateSnapshot existing keys preserved.
// âœ“ stateSnapshot is unmodifiable.
// âœ“ Shared NetworkOptimizer is not reset/disposed.
// âœ“ Shared VideoManager is not reset/disposed.
// âœ“ reset remains reusable.
// âœ“ dispose remains terminal.
// âœ“ Debug logging is release-safe.
// âœ“ No UI/design changes.
//
// STATUS:
// AI VIDEO ENGINE FINALIZED.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 26
// lib/services/call/call_timer.dart
// ===============================================================
