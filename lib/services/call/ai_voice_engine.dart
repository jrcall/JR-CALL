import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/network_model.dart';
import 'audio_manager.dart';
import 'network_optimizer.dart';

// ===========================================================
// JR CALL
// File: ai_voice_engine.dart
// Location: lib/services/call/ai_voice_engine.dart
//
// FINAL PRODUCTION AI-ASSISTED VOICE OPTIMIZATION COORDINATOR.
//
// Architecture:
//
// NetworkManager
//      ↓
// NetworkOptimizer
//      ↓
// AIVoiceEngine
//      ↓
// AudioManager
//
// Ownership:
//
// NetworkManager:
// - Network measurement.
//
// NetworkOptimizer:
// - Voice/network optimization policy.
//
// AudioManager:
// - Microphone/audio-processing state.
//
// AIVoiceEngine:
// - Coordinates voice optimization decisions only.
//
// IMPORTANT:
//
// - No direct NetworkHelper access.
// - No duplicate network polling.
// - No duplicate timer.
// - No direct WebRTC signaling.
// - No ICE logic.
// - No recovery logic.
// - No duplicate MediaStream.
// - No PeerConnection lifecycle ownership.
// - No terminal call lifecycle ownership.
// - No UI/design changes.
// ===========================================================

class AIVoiceEngine extends ChangeNotifier {
  AIVoiceEngine._();

  static final AIVoiceEngine instance =
  AIVoiceEngine._();

  // ===========================================================
  // DEPENDENCIES
  // ===========================================================

  final AudioManager _audioManager =
      AudioManager.instance;

  final NetworkOptimizer _networkOptimizer =
      NetworkOptimizer.instance;

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

  int _bitrate = 64000;

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

  Object? get lastError =>
      _lastError;

  bool get noiseSuppression =>
      _audioManager.noiseSuppression;

  bool get echoCancellation =>
      _audioManager.echoCancellation;

  bool get autoGainControl =>
      _audioManager.autoGainControl;

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() {
    _ensureUsable();

    if (_initialized) {
      return Future<void>.value();
    }

    final Future<void>? existing =
        _initializationFuture;

    if (existing != null) {
      return existing;
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

      if (!_audioManager.isInitialized) {
        await _audioManager.initialize();
      }

      if (!_isGenerationValid(
        generation,
      )) {
        return;
      }

      final _VoicePolicySnapshot? policy =
      await _captureVoicePolicy(
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

    while (!_initialized &&
        !_disposed) {
      await initialize();

      if (_initialized ||
          _disposed) {
        break;
      }
    }
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

    // Invalidate any in-flight optimization before it can apply
    // additional processing changes.

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

    final _VoicePolicySnapshot? policy =
    await _captureVoicePolicy(
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
  // AUDIO OPTIMIZATION
  // ===========================================================

  Future<void> optimizeAudio() async {
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
    _optimizeAudioInternal(
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

  Future<void> _optimizeAudioInternal(
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

        final _VoicePolicySnapshot? policy =
        await _captureVoicePolicy(
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
        // OFFLINE POLICY
        //
        // NetworkOptimizer may recommend zero bitrate while the
        // network is unavailable.
        //
        // Existing AudioManager processing preferences remain
        // unchanged while offline. Recovery/transport restoration
        // belongs to ConnectionManager/RecoveryManager.
        // -----------------------------------------------------

        if (!policy.network.isConnected ||
            policy.network.quality ==
                NetworkQuality.offline) {
          continue;
        }

        await _audioManager
            .enableNoiseSuppression(
          policy.noiseReduction,
        );

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled) {
          break;
        }

        await _audioManager
            .enableEchoCancellation(
          policy.echoCancellation,
        );

        if (!_isGenerationValid(
          generation,
        ) ||
            !_aiEnabled) {
          break;
        }

        await _audioManager
            .enableAutoGainControl(
          policy.autoGainControl,
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
          'optimizeAudio',
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
  // CONSISTENT VOICE POLICY SNAPSHOT
  //
  // NetworkOptimizer APIs are asynchronous.
  //
  // Capture one NetworkModel identity before the reads and
  // accept the result only if that same snapshot is still
  // current afterward.
  //
  // This prevents quality/bitrate/audio-processing policy from
  // being assembled from several different network snapshots.
  // ===========================================================

  Future<_VoicePolicySnapshot?>
  _captureVoicePolicy(
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

      final int bitrate =
      await _networkOptimizer
          .audioBitrate;

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

      final bool echoCancellation =
      await _networkOptimizer
          .enableEchoCancellation;

      if (!_isGenerationValid(
        generation,
      )) {
        return null;
      }

      final bool autoGainControl =
      await _networkOptimizer
          .enableAutoGainControl;

      if (!_isGenerationValid(
        generation,
      )) {
        return null;
      }

      if (identical(
        network,
        _networkOptimizer.currentNetwork,
      )) {
        return _VoicePolicySnapshot(
          network:
          network,
          bitrate:
          _sanitizeBitrate(
            bitrate,
          ),
          noiseReduction:
          noiseReduction,
          echoCancellation:
          echoCancellation,
          autoGainControl:
          autoGainControl,
        );
      }
    }

    // Network changed continuously during all bounded attempts.
    // Do not manufacture a mixed policy. A later network/stats
    // update will request optimization again.

    return null;
  }

  // ===========================================================
  // POLICY STATE
  // ===========================================================

  void _applyPolicyState(
      _VoicePolicySnapshot policy,
      ) {
    _networkQuality =
        policy.network.quality;

    _bitrate =
        policy.bitrate;
  }

  int _sanitizeBitrate(
      int bitrate,
      ) {
    if (bitrate <= 0) {
      return 0;
    }

    return bitrate;
  }

  // ===========================================================
  // CURRENT AI VOICE SNAPSHOT
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
        'noiseSuppression':
        _audioManager
            .noiseSuppression,
        'echoCancellation':
        _audioManager
            .echoCancellation,
        'autoGainControl':
        _audioManager
            .autoGainControl,
        'microphoneEnabled':
        _audioManager
            .microphoneEnabled,
        'muted':
        _audioManager.isMuted,
        'audioTransmitting':
        _audioManager
            .isAudioTransmitting,
        'lastError':
        _lastError?.toString(),
      },
    );
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

    // AudioManager and NetworkOptimizer are shared Call Engine
    // services and are intentionally NOT reset here.

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
    64000;

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
        'AIVoiceEngine has already been disposed.',
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
          '[AIVoiceEngine] '
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
          '[AIVoiceEngine/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[AIVoiceEngine/$source]',
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

    // Shared AudioManager / NetworkOptimizer are intentionally
    // not disposed here.

    super.dispose();
  }
}

// ===========================================================
// INTERNAL VOICE POLICY SNAPSHOT
// ===========================================================

class _VoicePolicySnapshot {
  final NetworkModel network;

  final int bitrate;

  final bool noiseReduction;

  final bool echoCancellation;

  final bool autoGainControl;

  const _VoicePolicySnapshot({
    required this.network,
    required this.bitrate,
    required this.noiseReduction,
    required this.echoCancellation,
    required this.autoGainControl,
  });
}

// ===============================================================
// END OF FILE
//
// FILE 24 FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ Existing ChangeNotifier ownership preserved.
// ✓ NetworkOptimizer remains voice-policy owner.
// ✓ AudioManager remains audio-processing state owner.
// ✓ No direct network measurement/polling added.
// ✓ No timer added.
// ✓ No MediaStream duplicated.
// ✓ No signaling/ICE/recovery ownership.
// ✓ No PeerConnection lifecycle ownership.
// ✓ Initialization Future is concurrency-deduplicated.
// ✓ 10ms initialization busy-wait loop removed.
// ✓ Initialization is generation guarded.
// ✓ Reset/disable/dispose invalidate stale async work.
// ✓ Optimization is serialized/coalesced.
// ✓ Old optimization cannot continue after AI disable.
// ✓ NetworkOptimizer Future APIs are explicitly awaited.
// ✓ audioBitrate Future contract handled correctly.
// ✓ enableNoiseReduction Future contract handled correctly.
// ✓ enableEchoCancellation Future contract handled correctly.
// ✓ enableAutoGainControl Future contract handled correctly.
// ✓ Voice policy assembled only from a stable network snapshot.
// ✓ Mixed network snapshots are never manufactured.
// ✓ NetworkOptimizer decisions are not overridden afterward.
// ✓ No duplicate forced audio-processing policy.
// ✓ Offline network does not disable existing processing settings.
// ✓ Recovery remains RecoveryManager/ConnectionManager-owned.
// ✓ Audio bitrate remains bits per second.
// ✓ Negative/non-positive bitrate safely becomes zero.
// ✓ stateSnapshot existing keys preserved.
// ✓ stateSnapshot returned unmodifiable.
// ✓ Shared AudioManager is not reset/disposed.
// ✓ Shared NetworkOptimizer is not reset/disposed.
// ✓ reset remains reusable.
// ✓ dispose remains terminal.
// ✓ Debug logging is release-safe.
// ✓ No UI/design changes.
//
// STATUS:
// AI VOICE ENGINE FINALIZED.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 25
// lib/services/call/ai_video_engine.dart
// ===============================================================