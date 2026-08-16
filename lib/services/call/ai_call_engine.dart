import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'ai_video_engine.dart';
import 'ai_voice_engine.dart';
import 'bitrate_controller.dart';
import 'call_quality_monitor.dart';
import 'network_optimizer.dart';

// ===========================================================
// JR CALL
// File: ai_call_engine.dart
// Location: lib/services/call/ai_call_engine.dart
//
// Description:
// Central AI call-optimization coordinator.
//
// Architecture:
//
// CallQualityMonitor
//        ↓
// AICallEngine
//        ↓
// ┌───────────────┬───────────────┐
// │ AIVoiceEngine │ AIVideoEngine │
// └───────────────┴───────────────┘
//        ↓
// NetworkOptimizer / Audio-Video Managers
//
// Ownership:
// - CallQualityMonitor owns quality metrics
// - NetworkOptimizer owns optimization policy
// - AIVoiceEngine owns voice optimization decisions
// - AIVideoEngine owns video optimization decisions
// - BitrateController owns bitrate-controller compatibility
// - AICallEngine coordinates them only
//
// Rules:
// - No direct network polling
// - No direct WebRTC lifecycle ownership
// - No signaling
// - No ICE
// - No recovery duplication
// - No duplicate timer
// - No duplicate quality monitor
// ===========================================================

class AICallEngine {
  AICallEngine._();

  static final AICallEngine instance = AICallEngine._();

  // ===========================================================
  // Dependencies
  // ===========================================================

  final AIVoiceEngine voiceEngine = AIVoiceEngine.instance;

  final AIVideoEngine videoEngine = AIVideoEngine.instance;

  final NetworkOptimizer optimizer = NetworkOptimizer.instance;

  final BitrateController bitrateController = BitrateController.instance;

  final CallQualityMonitor qualityMonitor = CallQualityMonitor.instance;

  // ===========================================================
  // Runtime State
  // ===========================================================

  bool _running = false;
  bool _starting = false;
  bool _stopping = false;
  bool _optimizing = false;
  bool _disposed = false;

  bool _optimizationPending = false;

  int _generation = 0;

  Future<void>? _startFuture;
  Future<void>? _stopFuture;

  CallQualityMetrics? _latestMetrics;

  Object? _lastError;

  // ===========================================================
  // Public State
  // ===========================================================

  bool get isRunning => _running;

  bool get isStarting => _starting;

  bool get isStopping => _stopping;

  bool get isOptimizing => _optimizing;

  bool get isDisposed => _disposed;

  CallQualityMetrics? get latestMetrics => _latestMetrics;

  Object? get lastError => _lastError;

  // ===========================================================
  // Start AI Engine
  // ===========================================================

  Future<void> start() {
    _ensureUsable();

    if (_running) {
      return Future<void>.value();
    }

    final existing = _startFuture;

    if (existing != null) {
      return existing;
    }

    final generation = _generation;

    final future = _startInternal(generation);

    _startFuture = future;

    return future.whenComplete(() {
      if (identical(_startFuture, future)) {
        _startFuture = null;
      }
    });
  }

  Future<void> _startInternal(int generation) async {
    if (!_isGenerationValid(generation)) {
      return;
    }

    _starting = true;
    _lastError = null;

    try {
      if (!optimizer.isInitialized) {
        await optimizer.initialize();
      }

      if (!_isGenerationValid(generation)) {
        return;
      }

      await voiceEngine.initialize();

      if (!_isGenerationValid(generation)) {
        return;
      }

      await videoEngine.initialize();

      if (!_isGenerationValid(generation)) {
        return;
      }

      // Must become active before CallQualityMonitor starts,
      // because its first forced metrics emission can feed
      // processMetrics() immediately.
      _running = true;

      await qualityMonitor.start();

      if (!_isGenerationValid(generation)) {
        _running = false;
        return;
      }

      debugPrint('JR CALL: AICallEngine started.');
    } catch (error, stackTrace) {
      _running = false;
      _lastError = error;

      _reportError('start', error, stackTrace);

      rethrow;
    } finally {
      _starting = false;
    }
  }

  // ===========================================================
  // Stop AI Engine
  // ===========================================================

  Future<void> stop() {
    if (_disposed) {
      return Future<void>.value();
    }

    final existing = _stopFuture;

    if (existing != null) {
      return existing;
    }

    final future = _stopInternal();

    _stopFuture = future;

    return future.whenComplete(() {
      if (identical(_stopFuture, future)) {
        _stopFuture = null;
      }
    });
  }

  Future<void> _stopInternal() async {
    if (_stopping) {
      return;
    }

    _stopping = true;

    // Invalidate pending start/optimization operations.
    _generation++;

    try {
      _running = false;
      _optimizationPending = false;

      qualityMonitor.stop();

      debugPrint('JR CALL: AICallEngine stopped.');
    } catch (error, stackTrace) {
      _lastError = error;

      _reportError('stop', error, stackTrace);
    } finally {
      _stopping = false;
    }
  }

  // ===========================================================
  // Metrics Feed
  // ===========================================================

  /// Called synchronously by CallQualityMonitor.
  ///
  /// Expensive asynchronous optimization is serialized below.
  void processMetrics(CallQualityMetrics metrics) {
    if (_disposed || !_running) {
      return;
    }

    _latestMetrics = metrics;

    if (_optimizing) {
      _optimizationPending = true;
      return;
    }

    unawaited(_processMetricsInternal());
  }

  Future<void> _processMetricsInternal() async {
    if (_disposed || !_running || _optimizing) {
      return;
    }

    _optimizing = true;

    final generation = _generation;

    try {
      do {
        _optimizationPending = false;

        if (!_isGenerationValid(generation) || !_running) {
          break;
        }

        final metrics = _latestMetrics;

        if (metrics == null) {
          break;
        }

        await _applyMetricPolicy(metrics, generation);
      } while (_optimizationPending &&
          _isGenerationValid(generation) &&
          _running);
    } catch (error, stackTrace) {
      _lastError = error;

      _reportError('metrics optimization', error, stackTrace);
    } finally {
      _optimizing = false;

      if (_optimizationPending && _running && !_disposed) {
        _optimizationPending = false;

        unawaited(_processMetricsInternal());
      }
    }
  }

  Future<void> _applyMetricPolicy(
    CallQualityMetrics metrics,
    int generation,
  ) async {
    if (!_isGenerationValid(generation) || !_running) {
      return;
    }

    // Voice processing remains useful for every active call.
    await voiceEngine.optimizeAudio();

    if (!_isGenerationValid(generation) || !_running) {
      return;
    }

    switch (metrics.recommendation) {
      case CallRecommendation.increaseBitrate:
      case CallRecommendation.decreaseBitrate:
      case CallRecommendation.increaseFps:
      case CallRecommendation.decreaseFps:
      case CallRecommendation.reduceResolution:
      case CallRecommendation.increaseResolution:
      case CallRecommendation.disableHd:
      case CallRecommendation.enableHd:
      case CallRecommendation.enableAdaptiveBitrate:
      case CallRecommendation.enableAdaptiveFps:
      case CallRecommendation.enableAdaptiveResolution:
      case CallRecommendation.enableDataSaver:
      case CallRecommendation.enableSuperResolution:
        await videoEngine.optimizeVideo();
        break;

      case CallRecommendation.enableNoiseReduction:
        await voiceEngine.optimizeAudio();
        break;

      case CallRecommendation.none:
        if (metrics.isPoorConnection) {
          await videoEngine.optimizeVideo();
        }
        break;
    }
  }

  // ===========================================================
  // Explicit In-Call Optimization
  // ===========================================================

  Future<void> optimizeCall({
    RTCRtpSender? audioSender,
    RTCRtpSender? videoSender,
  }) async {
    _ensureUsable();

    if (!_running) {
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
      await voiceEngine.optimizeAudio();

      if (!_isGenerationValid(generation) || !_running) {
        return;
      }

      if (videoSender != null || _latestMetrics?.isPoorConnection == true) {
        await videoEngine.optimizeVideo();
      }

      if (!_isGenerationValid(generation) || !_running) {
        return;
      }

      // RTCRtpSender mutation intentionally remains outside
      // AICallEngine. BitrateController/WebRTC media layer
      // owns actual RTP sender parameter mutation.
      //
      // These reads preserve compatibility with integrations
      // that pass sender references through this API.
      if (audioSender != null) {
        await optimizer.audioBitrate;
      }

      if (videoSender != null) {
        await optimizer.videoBitrate;
      }
    } catch (error, stackTrace) {
      _lastError = error;

      _reportError('optimizeCall', error, stackTrace);
    } finally {
      _optimizing = false;

      if (_optimizationPending && _running && !_disposed) {
        _optimizationPending = false;

        unawaited(_processMetricsInternal());
      }
    }
  }

  // ===========================================================
  // Status Snapshot
  // ===========================================================

  Future<Map<String, dynamic>> status() async {
    _ensureUsable();

    final quality = await qualityMonitor.refresh();

    final metrics = _latestMetrics;

    return <String, dynamic>{
      'running': _running,
      'starting': _starting,
      'stopping': _stopping,
      'optimizing': _optimizing,
      'quality': quality.name,
      'voice': <String, dynamic>{
        'aiEnabled': voiceEngine.aiEnabled,
        'initialized': voiceEngine.isInitialized,
        'bitrate': voiceEngine.bitrate,
        'networkQuality': voiceEngine.networkQuality.name,
        'noiseSuppression': voiceEngine.noiseSuppression,
        'echoCancellation': voiceEngine.echoCancellation,
        'autoGainControl': voiceEngine.autoGainControl,
      },
      'video': <String, dynamic>{
        'aiEnabled': videoEngine.aiEnabled,
        'initialized': videoEngine.isInitialized,
        'bitrate': videoEngine.bitrate,
        'fps': videoEngine.fps,
        'width': videoEngine.width,
        'height': videoEngine.height,
        'networkQuality': videoEngine.networkQuality.name,
      },
      'network': <String, dynamic>{
        'connected': optimizer.isConnected,
        'quality': optimizer.currentNetwork.quality.name,
        'recommendedProfile': await optimizer.recommendedProfile,
      },
      'metrics': metrics == null
          ? null
          : <String, dynamic>{
              'stabilityScore': metrics.stabilityScore,
              'packetLoss': metrics.packetLoss,
              'jitter': metrics.jitter,
              'rtt': metrics.rtt,
              'recommendedBitrate': metrics.recommendedBitrate,
              'recommendedFps': metrics.recommendedFps,
              'recommendation': metrics.recommendation.name,
              'recovering': metrics.isRecovering,
            },
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

    _running = false;
    _starting = false;
    _stopping = false;

    _optimizationPending = false;

    qualityMonitor.stop();

    try {
      await voiceEngine.reset();
    } catch (error, stackTrace) {
      _reportError('voice reset', error, stackTrace);
    }

    try {
      await videoEngine.reset();
    } catch (error, stackTrace) {
      _reportError('video reset', error, stackTrace);
    }

    bitrateController.reset();

    _latestMetrics = null;
    _lastError = null;

    _optimizing = false;

    debugPrint('JR CALL: AICallEngine reset.');
  }

  // ===========================================================
  // Helpers
  // ===========================================================

  bool _isGenerationValid(int generation) {
    return !_disposed && generation == _generation;
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('AICallEngine has already been disposed.');
    }
  }

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint(
      'JR CALL [AICallEngine/$source] '
      'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [AICallEngine/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // Dispose
  // ===========================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    await stop();

    _generation++;
    _disposed = true;

    _running = false;
    _starting = false;
    _stopping = false;
    _optimizing = false;

    _optimizationPending = false;

    _startFuture = null;
    _stopFuture = null;

    _latestMetrics = null;
    _lastError = null;

    debugPrint('JR CALL: AICallEngine disposed.');
  }
}
