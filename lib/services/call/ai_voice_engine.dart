import 'package:flutter/foundation.dart';

import '../../models/network_model.dart';
import 'audio_manager.dart';
import 'network_optimizer.dart';

// ===========================================================
// JR CALL
// File: ai_voice_engine.dart
// Location: lib/services/call/ai_voice_engine.dart
//
// Production AI-assisted voice optimization coordinator.
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
// - NetworkManager owns network measurement
// - NetworkOptimizer owns optimization policy
// - AudioManager owns microphone/audio-processing state
// - AIVoiceEngine coordinates AI voice decisions only
//
// Rules:
// - No direct NetworkHelper access
// - No duplicate network polling
// - No duplicate timer
// - No direct WebRTC signaling
// - No ICE logic
// - No recovery logic
// - No duplicate MediaStream
// ===========================================================

class AIVoiceEngine extends ChangeNotifier {
  AIVoiceEngine._();

  static final AIVoiceEngine instance = AIVoiceEngine._();

  // ===========================================================
  // Dependencies
  // ===========================================================

  final AudioManager _audioManager = AudioManager.instance;

  final NetworkOptimizer _networkOptimizer = NetworkOptimizer.instance;

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

  int _bitrate = 64000;

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

  Object? get lastError => _lastError;

  bool get noiseSuppression => _audioManager.noiseSuppression;

  bool get echoCancellation => _audioManager.echoCancellation;

  bool get autoGainControl => _audioManager.autoGainControl;

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

      if (!_audioManager.isInitialized) {
        await _audioManager.initialize();
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

      debugPrint('JR CALL: AIVoiceEngine initialized.');
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
  // AI Enable / Disable
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

    if (_isGenerationValid(generation)) {
      _notifySafely();
    }
  }

  Future<void> _analyzeNetworkInternal(int generation) async {
    if (!_isGenerationValid(generation)) {
      return;
    }

    final network = _networkOptimizer.currentNetwork;

    final recommendedBitrate = await _networkOptimizer.audioBitrate;

    if (!_isGenerationValid(generation)) {
      return;
    }

    _networkQuality = network.quality;

    _bitrate = recommendedBitrate < 0 ? 0 : recommendedBitrate;
  }

  // ===========================================================
  // Audio Optimization
  // ===========================================================

  Future<void> optimizeAudio() async {
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

        final noiseReduction = await _networkOptimizer.enableNoiseReduction;

        if (!_isGenerationValid(generation)) {
          return;
        }

        final echoCancellation = await _networkOptimizer.enableEchoCancellation;

        if (!_isGenerationValid(generation)) {
          return;
        }

        final autoGainControl = await _networkOptimizer.enableAutoGainControl;

        if (!_isGenerationValid(generation)) {
          return;
        }

        await _audioManager.enableNoiseSuppression(noiseReduction);

        if (!_isGenerationValid(generation)) {
          return;
        }

        await _audioManager.enableEchoCancellation(echoCancellation);

        if (!_isGenerationValid(generation)) {
          return;
        }

        await _audioManager.enableAutoGainControl(autoGainControl);

        if (!_isGenerationValid(generation)) {
          return;
        }

        await _applyQualityPolicy(generation);
      } while (_optimizationPending &&
          _isGenerationValid(generation) &&
          _aiEnabled);
    } catch (error, stackTrace) {
      _lastError = error;

      _reportError('optimizeAudio', error, stackTrace);
    } finally {
      _optimizing = false;

      _notifySafely();
    }
  }

  // ===========================================================
  // Quality Policy
  // ===========================================================

  Future<void> _applyQualityPolicy(int generation) async {
    if (!_isGenerationValid(generation)) {
      return;
    }

    switch (_networkQuality) {
      case NetworkQuality.excellent:
      case NetworkQuality.good:
      case NetworkQuality.fair:
      case NetworkQuality.poor:
        await _ensureVoiceProcessingEnabled(generation);
        break;

      case NetworkQuality.offline:
        // Audio-processing preferences remain unchanged.
        // Network restoration/recovery belongs to
        // RecoveryManager / ConnectionManager.
        break;
    }
  }

  Future<void> _ensureVoiceProcessingEnabled(int generation) async {
    if (!_isGenerationValid(generation)) {
      return;
    }

    if (!_audioManager.noiseSuppression) {
      await _audioManager.enableNoiseSuppression(true);
    }

    if (!_isGenerationValid(generation)) {
      return;
    }

    if (!_audioManager.echoCancellation) {
      await _audioManager.enableEchoCancellation(true);
    }

    if (!_isGenerationValid(generation)) {
      return;
    }

    if (!_audioManager.autoGainControl) {
      await _audioManager.enableAutoGainControl(true);
    }
  }

  // ===========================================================
  // Current AI Voice Snapshot
  // ===========================================================

  Map<String, dynamic> get stateSnapshot {
    return <String, dynamic>{
      'initialized': _initialized,
      'initializing': _initializing,
      'aiEnabled': _aiEnabled,
      'optimizing': _optimizing,
      'networkQuality': _networkQuality.name,
      'bitrate': _bitrate,
      'noiseSuppression': _audioManager.noiseSuppression,
      'echoCancellation': _audioManager.echoCancellation,
      'autoGainControl': _audioManager.autoGainControl,
      'microphoneEnabled': _audioManager.microphoneEnabled,
      'muted': _audioManager.isMuted,
      'audioTransmitting': _audioManager.isAudioTransmitting,
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

    // AudioManager is shared across the call engine.
    // Do not reset AudioManager here.

    _initialized = false;
    _initializing = false;

    _optimizing = false;
    _optimizationPending = false;

    _aiEnabled = true;

    _networkQuality = NetworkQuality.good;

    _bitrate = 64000;

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
      throw StateError('AIVoiceEngine has already been disposed.');
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint(
      'JR CALL [AIVoiceEngine/$source] '
      'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [AIVoiceEngine/$source]',
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
