import 'package:flutter/foundation.dart';

import '../../models/network_model.dart';
import 'network_optimizer.dart';
import 'video_manager.dart';

// ===========================================================
// JR CALL
// File: ai_video_engine.dart
// Location: lib/services/call/ai_video_engine.dart
//
// FINAL PRODUCTION AI-ASSISTED VIDEO OPTIMIZATION COORDINATOR.
//
// IMPORTANT ARCHITECTURE:
//
// This file belongs to:
//
// lib/services/call/
//
// Therefore it uses:
//
// lib/services/call/video_manager.dart
//
// It MUST NOT be mixed with:
//
// lib/services/managers/video_manager.dart
//
// Architecture:
//
// NetworkManager
//      ↓
// NetworkOptimizer
//      ↓
// AIVideoEngine
//      ↓
// CALL-LAYER VideoManager
//
// Ownership:
//
// NetworkManager:
// - Network measurement.
//
// NetworkOptimizer:
// - Adaptive media policy.
//
// CALL-LAYER VideoManager:
// - Video adaptive settings.
// - Video presentation/enhancement policy application.
//
// AIVideoEngine:
// - Coordinates AI-assisted video decisions.
//
// WebRTC / sender layer:
// - Actual transport ownership.
//
// Rules:
//
// - No NetworkHelper polling.
// - No duplicate timers.
// - No direct PeerConnection lifecycle.
// - No signaling.
// - No ICE.
// - No recovery duplication.
// - No duplicate MediaStream acquisition.
// - No manager-layer VideoManager mixing.
// - No UI/design changes.
// ===========================================================

class AIVideoEngine extends ChangeNotifier {
  AIVideoEngine._();

  static final AIVideoEngine instance =
  AIVideoEngine._();

  // ===========================================================
  // DEPENDENCIES
  // ===========================================================

  final NetworkOptimizer _networkOptimizer =
      NetworkOptimizer.instance;

  final VideoManager _videoManager =
      VideoManager.instance;

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

  NetworkQuality _networkQuality =
      NetworkQuality.good;

  int _bitrate = 1500000;

  int _fps = 30;

  int _width = 1280;

  int _height = 720;

  Object? _lastError;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  bool get initialized =>
      _initialized;

  bool get isInitialized =>
      _initialized;

  bool get isInitializing =>
      _initializing;

  bool get aiEnabled =>
      _aiEnabled;

  bool get isOptimizing =>
      _optimizing;

  bool get isDisposed =>
      _disposed;

  NetworkQuality get networkQuality =>
      _networkQuality;

  int get bitrate =>
      _bitrate;

  int get fps =>
      _fps;

  int get width =>
      _width;

  int get height =>
      _height;

  Object? get lastError =>
      _lastError;

  Map<String, int> get resolution =>
      Map<String, int>.unmodifiable(
        <String, int>{
          'width': _width,
          'height': _height,
        },
      );

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() {
    _ensureUsable();

    if (_initialized) {
      return Future<void>.value();
    }

    final Future<void>? active =
        _initializationFuture;

    if (active != null) {
      return active;
    }

    final int generation =
        _generation;

    final Future<void> operation =
    _initializeInternal(
      generation,
    );

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _initializationFuture,
        tracked,
      )) {
        _initializationFuture = null;
      }
    });

    _initializationFuture =
        tracked;

    return tracked;
  }

  Future<void> _initializeInternal(
      int generation,
      ) async {
    if (!_isGenerationValid(
      generation,
    )) {
      return;
    }

    _initializing =
    true;

    _activeInitializationGeneration =
        generation;

    _lastError =
    null;

    _notifySafely();

    try {
      if (!_networkOptimizer.isInitialized) {
        await _networkOptimizer.initialize();
      }

      if (!_isGenerationValid(
        generation,
      )) {
        return;
      }

      if (!_videoManager.isInitialized) {
        await _videoManager.initialize();
      }

      if (!_isGenerationValid(
        generation,
      )) {
        return;
      }

      final _VideoPolicySnapshot? policy =
      await _captureVideoPolicy(
        generation,
      );

      if (!_isGenerationValid(
        generation,
      )) {
        return;
      }

      if (policy != null) {
        _applyPolicyState(
          policy,
        );
      }

      _initialized =
      true;

      _notifySafely();

      _debugPrint(
        'initialized.',
      );
    } catch (error, stackTrace) {
      if (_isGenerationValid(
        generation,
      )) {
        _initialized =
        false;

        _lastError =
            error;

        _reportError(
          'initialize',
          error,
          stackTrace,
        );
      }

      rethrow;
    } finally {
      if (_activeInitializationGeneration ==
          generation) {
        _activeInitializationGeneration =
        null;

        _initializing =
        false;

        _notifySafely();
      }
    }
  }

  Future<void> _ensureInitialized() async {
    _ensureUsable();

    if (_initialized) {
      return;
    }

    await initialize();
  }

  // ===========================================================
  // AI ENABLE / DISABLE
  // ===========================================================

  Future<void> enableAI() async {
    _ensureUsable();

    if (_aiEnabled) {
      return;
    }

    _aiEnabled =
    true;

    _lastError =
    null;

    _notifySafely();
  }

  Future<void> disableAI() async {
    _ensureUsable();

    if (!_aiEnabled) {
      return;
    }

    // Invalidate in-flight AI policy work before it can apply
    // additional video changes.

    _generation++;

    _aiEnabled =
    false;

    _optimizationPending =
    false;

    _notifySafely();
  }

  Future<void> setAIEnabled(
      bool enabled,
      ) async {
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

    final int generation =
        _generation;

    final _VideoPolicySnapshot? policy =
    await _captureVideoPolicy(
      generation,
    );

    if (!_isGenerationValid(
      generation,
    ) ||
        policy == null) {
      return;
    }

    _applyPolicyState(
      policy,
    );

    _notifySafely();
  }

  // ===========================================================
  // VIDEO OPTIMIZATION
  // ===========================================================

  Future<void> optimizeVideo() async {
    await _ensureInitialized();

    if (_disposed ||
        !_aiEnabled) {
      return;
    }

    final Future<void>? active =
        _optimizationFuture;

    if (active != null) {
      _optimizationPending =
      true;

      await active;

      return;
    }

    final int generation =
        _generation;

    final Future<void> operation =
    _optimizeVideoInternal(
      generation,
    );

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _optimizationFuture,
        tracked,
      )) {
        _optimizationFuture = null;
      }
    });

    _optimizationFuture =
        tracked;

    await tracked;
  }

  Future<void> _optimizeVideoInternal(
      int generation,
      ) async {
    if (!_isGenerationValid(
      generation,
    ) ||
        !_aiEnabled) {
      return;
    }

    _optimizing =
    true;

    _lastError =
    null;

    _notifySafely();

    try {
      do {
        _optimizationPending =
        false;

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled) {
          break;
        }

        final _VideoPolicySnapshot? policy =
        await _captureVideoPolicy(
          generation,
        );

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled ||
            policy == null) {
          break;
        }

        _applyPolicyState(
          policy,
        );

        // -----------------------------------------------------
        // NETWORK UNAVAILABLE
        //
        // Do not automatically turn the user's camera off.
        //
        // Temporary network loss/recovery must not overwrite
        // explicit user video state.
        // -----------------------------------------------------

        if (!policy.network.isConnected ||
            policy.network.quality ==
                NetworkQuality.offline) {
          continue;
        }

        // -----------------------------------------------------
        // VIDEO AVAILABILITY POLICY
        //
        // This remains recommendation state only.
        //
        // Do not silently enable video if the user explicitly
        // disabled their camera.
        // -----------------------------------------------------

        if (!policy.videoAllowed) {
          continue;
        }

        if (!_videoManager.videoEnabled) {
          continue;
        }

        // -----------------------------------------------------
        // APPLY CALL-LAYER ADAPTIVE SETTINGS
        // -----------------------------------------------------

        await _videoManager
            .applyAdaptiveSettings(
          width: policy.width,
          height: policy.height,
          fps: policy.fps,
          bitrate: policy.bitrate,
        );

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled) {
          break;
        }

        await _applyEnhancementPolicy(
          policy,
          generation,
        );
      } while (
      _optimizationPending &&
          _isGenerationValid(
            generation,
          ) &&
          _aiEnabled);
    } catch (error, stackTrace) {
      if (_isGenerationValid(
        generation,
      )) {
        _lastError =
            error;

        _reportError(
          'optimizeVideo',
          error,
          stackTrace,
        );
      }
    } finally {
      _optimizing =
      false;

      _notifySafely();
    }
  }

  // ===========================================================
  // CONSISTENT VIDEO POLICY SNAPSHOT
  //
  // NetworkOptimizer.recommendedProfile is asynchronous.
  //
  // Never treat Future<Map<...>> as a synchronous Map.
  // ===========================================================

  Future<_VideoPolicySnapshot?>
  _captureVideoPolicy(
      int generation,
      ) async {
    const int maxAttempts =
    3;

    for (int attempt = 0;
    attempt < maxAttempts;
    attempt++) {
      if (!_isGenerationValid(
        generation,
      )) {
        return null;
      }

      final NetworkModel network =
          _networkOptimizer.currentNetwork;

      final Map<String, dynamic> profile =
      await _networkOptimizer
          .recommendedProfile;

      if (!_isGenerationValid(
        generation,
      )) {
        return null;
      }

      final bool noiseReduction =
      await _networkOptimizer
          .enableNoiseReduction;

      if (!_isGenerationValid(
        generation,
      )) {
        return null;
      }

      final bool hdEnabled =
      await _networkOptimizer
          .enableHD;

      if (!_isGenerationValid(
        generation,
      )) {
        return null;
      }

      final bool superResolution =
      await _networkOptimizer
          .enableSuperResolution;

      if (!_isGenerationValid(
        generation,
      )) {
        return null;
      }

      if (!identical(
        network,
        _networkOptimizer.currentNetwork,
      )) {
        continue;
      }

      final int bitrate =
          _readNonNegativeInt(
            profile[
            'videoBitrate'],
          ) ??
              0;

      final int fps =
          _readNonNegativeInt(
            profile['fps'],
          ) ??
              0;

      final int width =
          _readPositiveInt(
            profile['width'],
          ) ??
              640;

      final int height =
          _readPositiveInt(
            profile['height'],
          ) ??
              360;

      final bool videoAllowed =
          profile['videoEnabled'] ==
              true;

      return _VideoPolicySnapshot(
        network:
        network,
        bitrate:
        bitrate,
        fps:
        fps,
        width:
        width,
        height:
        height,
        videoAllowed:
        videoAllowed,
        noiseReduction:
        noiseReduction,
        hdEnabled:
        hdEnabled,
        superResolution:
        superResolution,
      );
    }

    // Continuous network churn:
    // do not manufacture a mixed policy.

    return null;
  }

  // ===========================================================
  // POLICY STATE
  // ===========================================================

  void _applyPolicyState(
      _VideoPolicySnapshot policy,
      ) {
    _networkQuality =
        policy.network.quality;

    _bitrate =
        policy.bitrate;

    _fps =
        policy.fps;

    _width =
        policy.width;

    _height =
        policy.height;
  }

  // ===========================================================
  // ENHANCEMENT POLICY
  // ===========================================================

  Future<void> _applyEnhancementPolicy(
      _VideoPolicySnapshot policy,
      int generation,
      ) async {
    if (!_isGenerationValid(
      generation,
    ) ||
        !_aiEnabled) {
      return;
    }

    await _videoManager
        .enableNoiseReduction(
      policy.noiseReduction,
    );

    if (!_isGenerationValid(
      generation,
    ) ||
        !_aiEnabled) {
      return;
    }

    switch (policy.network.quality) {
      case NetworkQuality.excellent:
        await _videoManager
            .enableFaceEnhancement(
          true,
        );

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled) {
          return;
        }

        await _videoManager
            .enableBeautyMode(
          policy.superResolution,
        );

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled) {
          return;
        }

        await _videoManager
            .enableBackgroundBlur(
          false,
        );

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled) {
          return;
        }

        // Corrected condition:
        //
        // Never apply HD quality when optimizer says HD should
        // be disabled.

        if (policy.hdEnabled &&
            _videoManager.qualityProfile !=
                VideoQualityProfile.fullHd) {
          await _videoManager
              .applyHDQuality();
        }

        break;

      case NetworkQuality.good:
        await _videoManager
            .enableFaceEnhancement(
          true,
        );

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled) {
          return;
        }

        await _videoManager
            .enableBeautyMode(
          false,
        );

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled) {
          return;
        }

        await _videoManager
            .enableBackgroundBlur(
          false,
        );

        break;

      case NetworkQuality.fair:
      case NetworkQuality.poor:
        await _disableExpensiveEnhancements(
          generation,
        );

        break;

      case NetworkQuality.offline:
      // Offline processing state is left untouched.
      //
      // ConnectionManager/RecoveryManager own recovery.
        break;
    }
  }

  Future<void> _disableExpensiveEnhancements(
      int generation,
      ) async {
    if (!_isGenerationValid(
      generation,
    ) ||
        !_aiEnabled) {
      return;
    }

    await _videoManager
        .enableFaceEnhancement(
      false,
    );

    if (!_isGenerationValid(
      generation,
    ) ||
        !_aiEnabled) {
      return;
    }

    await _videoManager
        .enableBeautyMode(
      false,
    );

    if (!_isGenerationValid(
      generation,
    ) ||
        !_aiEnabled) {
      return;
    }

    await _videoManager
        .enableBackgroundBlur(
      false,
    );
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
    return Map<String, dynamic>.unmodifiable(
      <String, dynamic>{
        'initialized':
        _initialized,
        'initializing':
        _initializing,
        'aiEnabled':
        _aiEnabled,
        'optimizing':
        _optimizing,
        'networkQuality':
        _networkQuality.name,
        'bitrate':
        _bitrate,
        'fps':
        _fps,
        'width':
        _width,
        'height':
        _height,
        'videoEnabled':
        _videoManager.videoEnabled,
        'qualityProfile':
        _videoManager
            .qualityProfile
            .name,
        'lastError':
        _lastError?.toString(),
      },
    );
  }

  // ===========================================================
  // VALUE HELPERS
  // ===========================================================

  int? _readNonNegativeInt(
      Object? value,
      ) {
    int? result;

    if (value is int) {
      result =
          value;
    } else if (value is num &&
        value.isFinite) {
      result =
          value.toInt();
    } else if (value is String) {
      result =
          int.tryParse(
            value.trim(),
          );
    }

    if (result == null ||
        result < 0) {
      return null;
    }

    return result;
  }

  int? _readPositiveInt(
      Object? value,
      ) {
    final int? result =
    _readNonNegativeInt(
      value,
    );

    if (result == null ||
        result <= 0) {
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

    _optimizationPending =
    false;

    final Future<void>? initialization =
        _initializationFuture;

    final Future<void>? optimization =
        _optimizationFuture;

    if (initialization != null) {
      try {
        await initialization;
      } catch (error, stackTrace) {
        _reportError(
          'stale initialization during reset',
          error,
          stackTrace,
        );
      }
    }

    if (optimization != null) {
      try {
        await optimization;
      } catch (error, stackTrace) {
        _reportError(
          'stale optimization during reset',
          error,
          stackTrace,
        );
      }
    }

    if (_disposed) {
      return;
    }

    // Shared NetworkOptimizer and CALL-LAYER VideoManager are
    // intentionally NOT reset here.

    _initialized =
    false;

    _initializing =
    false;

    _activeInitializationGeneration =
    null;

    _optimizing =
    false;

    _optimizationPending =
    false;

    _aiEnabled =
    true;

    _networkQuality =
        NetworkQuality.good;

    _bitrate =
    1500000;

    _fps =
    30;

    _width =
    1280;

    _height =
    720;

    _lastError =
    null;

    _initializationFuture =
    null;

    _optimizationFuture =
    null;

    _notifySafely();

    _debugPrint(
      'reset.',
    );
  }

  // ===========================================================
  // INTERNAL HELPERS
  // ===========================================================

  bool _isGenerationValid(
      int generation,
      ) {
    return !_disposed &&
        generation ==
            _generation;
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError(
        'AIVideoEngine has already been disposed.',
      );
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _debugPrint(
      String message,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[AIVideoEngine] '
          '$message',
    );
  }

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
          '[AIVideoEngine/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[AIVideoEngine/$source]',
        stackTrace:
        stackTrace,
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

    _disposed =
    true;

    _initialized =
    false;

    _initializing =
    false;

    _activeInitializationGeneration =
    null;

    _optimizing =
    false;

    _optimizationPending =
    false;

    _initializationFuture =
    null;

    _optimizationFuture =
    null;

    _lastError =
    null;

    // CALL-LAYER VideoManager and NetworkOptimizer are shared
    // services and are intentionally not disposed here.

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

  final bool videoAllowed;

  final bool noiseReduction;

  final bool hdEnabled;

  final bool superResolution;

  const _VideoPolicySnapshot({
    required this.network,
    required this.bitrate,
    required this.fps,
    required this.width,
    required this.height,
    required this.videoAllowed,
    required this.noiseReduction,
    required this.hdEnabled,
    required this.superResolution,
  });
}

// ===============================================================
// END OF FILE
//
// FILE 25 CORRECTED FINAL GUARANTEES:
//
// ✓ Correct CALL-LAYER VideoManager restored.
// ✓ manager-layer VideoManager is NOT imported.
// ✓ Same-name architectural layers are not mixed.
// ✓ Existing AIVideoEngine public APIs preserved.
// ✓ Existing optimizeAudio compatibility alias preserved.
// ✓ Existing CALL-LAYER VideoManager APIs preserved.
// ✓ NetworkOptimizer remains policy owner.
// ✓ All NetworkOptimizer Future APIs are awaited.
// ✓ recommendedProfile Future<Map> handled correctly.
// ✓ Stable NetworkModel snapshot used for policy.
// ✓ No mixed async network policy manufactured.
// ✓ Initialization concurrency deduplicated.
// ✓ 10ms busy-wait initialization removed.
// ✓ Disable/reset/dispose invalidate stale operations.
// ✓ Optimization serialized/coalesced.
// ✓ AI does not silently enable a user-disabled camera.
// ✓ Temporary offline state does not silently disable camera.
// ✓ Adaptive video settings remain CALL-LAYER VideoManager-owned.
// ✓ Existing enhancement APIs preserved.
// ✓ HD policy condition corrected.
// ✓ Offline recovery remains RecoveryManager-owned.
// ✓ No NetworkHelper polling.
// ✓ No timer added.
// ✓ No direct PeerConnection ownership.
// ✓ No signaling/ICE ownership.
// ✓ No duplicate MediaStream acquisition.
// ✓ stateSnapshot keys preserved.
// ✓ resolution is unmodifiable.
// ✓ reset remains reusable.
// ✓ dispose remains terminal.
// ✓ No UI/design changes.
//
// STATUS:
// FILE 25 — CORRECTED FINAL.
//
// FILE 27 SOURCE:
// ALREADY RECEIVED.
// DO NOT RESEND.
// ===============================================================