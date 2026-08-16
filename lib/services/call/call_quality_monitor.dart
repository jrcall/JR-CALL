import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/network_model.dart';
import '../managers/media_manager.dart';
import '../managers/network_manager.dart';
import '../managers/peer_connection_manager.dart';
import '../managers/recovery_manager.dart';
import '../managers/stats_manager.dart';
import 'ai_call_engine.dart';
import 'call_timer.dart';
import 'connection_manager.dart';
import 'network_optimizer.dart';

/// ===========================================================
/// JR CALL
/// File: call_quality_monitor.dart
/// Location: lib/services/call/call_quality_monitor.dart
///
/// Description:
/// Production real-time call-quality analysis coordinator.
///
/// Ownership:
/// - NetworkManager owns network measurement.
/// - StatsManager owns WebRTC statistics collection.
/// - ConnectionManager owns connection orchestration.
/// - RecoveryManager owns recovery scheduling.
/// - NetworkOptimizer owns optimization recommendations.
/// - CallQualityMonitor ONLY combines those states, calculates
///   quality/stability, emits metrics and feeds the AI layer.
///
/// Important:
/// - No duplicate network polling.
/// - No duplicate periodic timer.
/// - No duplicate WebRTC getStats polling.
/// - No direct ICE manipulation.
/// - No direct recovery execution.
/// - No direct signaling mutation.
/// ===========================================================

enum CallRecommendation {
  increaseBitrate,
  decreaseBitrate,
  increaseFps,
  decreaseFps,
  reduceResolution,
  increaseResolution,
  enableNoiseReduction,
  disableHd,
  enableHd,
  enableAdaptiveBitrate,
  enableAdaptiveFps,
  enableAdaptiveResolution,
  enableDataSaver,
  enableSuperResolution,
  none,
}

@immutable
class CallQualityMetrics {
  final NetworkQuality quality;
  final NetworkType networkType;

  final bool isInternetAvailable;

  final int ping;
  final int rtt;

  final double jitter;
  final double packetLoss;

  final int uploadBitrate;
  final int downloadBitrate;

  final int currentVideoBitrate;
  final int currentAudioBitrate;

  final int recommendedBitrate;
  final int recommendedFps;

  final Map<String, int> recommendedResolution;
  final Map<String, int> currentResolution;

  final int signalStrength;
  final int callDurationSeconds;

  final String peerConnectionState;
  final String iceConnectionState;
  final String signalingState;
  final String transportType;

  final int stabilityScore;

  final CallRecommendation recommendation;

  final int reconnectCount;
  final bool isRecovering;

  const CallQualityMetrics({
    required this.quality,
    required this.networkType,
    required this.isInternetAvailable,
    required this.ping,
    required this.rtt,
    required this.jitter,
    required this.packetLoss,
    required this.uploadBitrate,
    required this.downloadBitrate,
    required this.currentVideoBitrate,
    required this.currentAudioBitrate,
    required this.recommendedBitrate,
    required this.recommendedFps,
    required this.recommendedResolution,
    required this.currentResolution,
    required this.signalStrength,
    required this.callDurationSeconds,
    required this.peerConnectionState,
    required this.iceConnectionState,
    required this.signalingState,
    required this.transportType,
    required this.stabilityScore,
    required this.recommendation,
    required this.reconnectCount,
    required this.isRecovering,
  });

  bool get isHdAvailable =>
      quality == NetworkQuality.excellent || quality == NetworkQuality.good;

  bool get isPoorConnection =>
      quality == NetworkQuality.poor || quality == NetworkQuality.offline;

  static bool _mapEquals(Map<String, int> first, Map<String, int> second) {
    if (first.length != second.length) {
      return false;
    }

    for (final entry in first.entries) {
      if (second[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  static int _mapHash(Map<String, int> map) {
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is CallQualityMetrics &&
        other.quality == quality &&
        other.networkType == networkType &&
        other.isInternetAvailable == isInternetAvailable &&
        other.ping == ping &&
        other.rtt == rtt &&
        other.jitter == jitter &&
        other.packetLoss == packetLoss &&
        other.uploadBitrate == uploadBitrate &&
        other.downloadBitrate == downloadBitrate &&
        other.currentVideoBitrate == currentVideoBitrate &&
        other.currentAudioBitrate == currentAudioBitrate &&
        other.recommendedBitrate == recommendedBitrate &&
        other.recommendedFps == recommendedFps &&
        _mapEquals(other.recommendedResolution, recommendedResolution) &&
        _mapEquals(other.currentResolution, currentResolution) &&
        other.signalStrength == signalStrength &&
        other.callDurationSeconds == callDurationSeconds &&
        other.peerConnectionState == peerConnectionState &&
        other.iceConnectionState == iceConnectionState &&
        other.signalingState == signalingState &&
        other.transportType == transportType &&
        other.stabilityScore == stabilityScore &&
        other.recommendation == recommendation &&
        other.reconnectCount == reconnectCount &&
        other.isRecovering == isRecovering;
  }

  @override
  int get hashCode {
    return Object.hashAll(<Object?>[
      quality,
      networkType,
      isInternetAvailable,
      ping,
      rtt,
      jitter,
      packetLoss,
      uploadBitrate,
      downloadBitrate,
      currentVideoBitrate,
      currentAudioBitrate,
      recommendedBitrate,
      recommendedFps,
      _mapHash(recommendedResolution),
      _mapHash(currentResolution),
      signalStrength,
      callDurationSeconds,
      peerConnectionState,
      iceConnectionState,
      signalingState,
      transportType,
      stabilityScore,
      recommendation,
      reconnectCount,
      isRecovering,
    ]);
  }
}

class CallQualityMonitor {
  CallQualityMonitor._();

  static final CallQualityMonitor instance = CallQualityMonitor._();

  // ===========================================================
  // Core Dependencies
  // ===========================================================

  final NetworkManager _networkManager = NetworkManager.instance;

  final ConnectionManager _connectionManager = ConnectionManager.instance;

  final RecoveryManager _recoveryManager = RecoveryManager.instance;

  final NetworkOptimizer _networkOptimizer = NetworkOptimizer.instance;

  StatsManager? _statsManager;
  MediaManager? _mediaManager;
  PeerConnectionManager? _peerConnectionManager;
  CallTimer? _callTimer;
  AICallEngine? _aiCallEngine;

  StatsManager get _resolvedStatsManager =>
      _statsManager ?? StatsManager.instance;

  MediaManager get _resolvedMediaManager =>
      _mediaManager ?? MediaManager.instance;

  PeerConnectionManager get _resolvedPeerConnectionManager =>
      _peerConnectionManager ?? PeerConnectionManager.instance;

  // ===========================================================
  // Metrics Stream
  // ===========================================================

  final StreamController<CallQualityMetrics> _metricsController =
      StreamController<CallQualityMetrics>.broadcast(sync: true);

  Stream<CallQualityMetrics> get metricsStream => _metricsController.stream;

  // ===========================================================
  // Listener State
  // ===========================================================

  StreamSubscription<ConnectionStateModel>? _connectionSubscription;

  bool _networkListenerAttached = false;
  bool _statsListenerAttached = false;
  bool _mediaListenerAttached = false;
  bool _peerListenerAttached = false;
  bool _recoveryListenerAttached = false;

  // ===========================================================
  // Runtime State
  // ===========================================================

  bool _initialized = false;
  bool _monitoring = false;
  bool _updating = false;
  bool _pendingUpdate = false;
  bool _disposed = false;

  bool get isInitialized => _initialized;

  bool get isMonitoring => _monitoring;

  NetworkQuality _lastQuality = NetworkQuality.offline;

  NetworkQuality get currentQuality => _lastQuality;

  CallQualityMetrics? _lastEmittedMetrics;

  NetworkType? _lastNetworkType;

  CallRecommendation? _lastRecommendation;

  int? _lastRecommendedBitrate;
  int? _lastRecommendedFps;

  int? _lastCurrentVideoBitrate;

  int? _lastStabilityScore;

  Map<String, int>? _lastRecommendedResolution;

  bool _packetLossAlertActive = false;
  bool _recoveryWasActive = false;

  // ===========================================================
  // Public Callbacks
  // ===========================================================

  ValueChanged<CallQualityMetrics>? onMetricsUpdated;

  ValueChanged<int>? onStabilityChanged;

  ValueChanged<NetworkType>? onNetworkTypeChanged;

  ValueChanged<int>? onBitrateRecommendationChanged;

  ValueChanged<int>? onQualityScoreChanged;

  ValueChanged<NetworkQuality>? onQualityChanged;

  ValueChanged<ConnectionStateModel>? onConnectionChanged;

  ValueChanged<CallRecommendation>? onRecommendationChanged;

  VoidCallback? onRecoveryRequired;

  VoidCallback? onRecoveryCompleted;

  ValueChanged<double>? onPacketLossHigh;

  ValueChanged<int>? onBitrateChanged;

  ValueChanged<int>? onFpsRecommendationChanged;

  ValueChanged<Map<String, int>>? onResolutionRecommendationChanged;

  ValueChanged<Object>? onError;

  // ===========================================================
  // Dependency Injection
  // ===========================================================

  void setDependencies({
    StatsManager? statsManager,
    MediaManager? mediaManager,
    PeerConnectionManager? peerConnectionManager,
    CallTimer? callTimer,
    AICallEngine? aiCallEngine,
  }) {
    if (_disposed) {
      return;
    }

    final wasMonitoring = _monitoring;

    if (wasMonitoring) {
      _detachListeners();
    }

    _statsManager = statsManager;
    _mediaManager = mediaManager;
    _peerConnectionManager = peerConnectionManager;
    _callTimer = callTimer;
    _aiCallEngine = aiCallEngine;

    if (wasMonitoring) {
      _attachListeners();

      _requestMetricsUpdate();
    }
  }

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('CallQualityMonitor has been disposed.');
    }

    if (_initialized) {
      return;
    }

    try {
      if (!_networkManager.isInitialized) {
        await _networkManager.initialize();
      }

      if (!_networkOptimizer.isInitialized) {
        await _networkOptimizer.initialize();
      }

      if (!_resolvedStatsManager.isInitialized) {
        await _resolvedStatsManager.initialize();
      }

      if (!_connectionManager.isMonitoring) {
        await _connectionManager.startMonitoring();
      }

      _initialized = true;

      await _analyzeAndEmitMetrics(force: true);

      debugPrint('CallQualityMonitor: initialized.');
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, source: 'initialize');

      rethrow;
    }
  }

  // ===========================================================
  // Start
  // ===========================================================

  Future<void> start({Duration interval = const Duration(seconds: 2)}) async {
    /// interval remains in the public signature only for
    /// backwards compatibility.
    ///
    /// CallQualityMonitor intentionally does NOT create
    /// its own periodic timer. StatsManager and NetworkManager
    /// already own their sampling schedules.

    if (_disposed) {
      throw StateError('CallQualityMonitor has been disposed.');
    }

    if (!_initialized) {
      await initialize();
    }

    if (_monitoring) {
      await _analyzeAndEmitMetrics(force: true);

      return;
    }

    _monitoring = true;

    _attachListeners();

    await _analyzeAndEmitMetrics(force: true);

    debugPrint('CallQualityMonitor: monitoring started.');
  }

  // ===========================================================
  // Listener Wiring
  // ===========================================================

  void _attachListeners() {
    if (!_networkListenerAttached) {
      _networkManager.addListener(_handleDependencyChanged);

      _networkListenerAttached = true;
    }

    if (!_statsListenerAttached) {
      _resolvedStatsManager.addListener(_handleDependencyChanged);

      _statsListenerAttached = true;
    }

    if (!_mediaListenerAttached) {
      _resolvedMediaManager.addListener(_handleDependencyChanged);

      _mediaListenerAttached = true;
    }

    if (!_peerListenerAttached) {
      _resolvedPeerConnectionManager.addListener(_handleDependencyChanged);

      _peerListenerAttached = true;
    }

    if (!_recoveryListenerAttached) {
      _recoveryManager.addListener(_handleRecoveryChanged);

      _recoveryListenerAttached = true;
    }

    _connectionSubscription ??= _connectionManager.connectionStream.listen(
      _handleConnectionChanged,
      onError: (Object error) {
        _reportError(error, StackTrace.current, source: 'connection stream');
      },
    );
  }

  void _detachListeners() {
    if (_networkListenerAttached) {
      _networkManager.removeListener(_handleDependencyChanged);

      _networkListenerAttached = false;
    }

    if (_statsListenerAttached) {
      _resolvedStatsManager.removeListener(_handleDependencyChanged);

      _statsListenerAttached = false;
    }

    if (_mediaListenerAttached) {
      _resolvedMediaManager.removeListener(_handleDependencyChanged);

      _mediaListenerAttached = false;
    }

    if (_peerListenerAttached) {
      _resolvedPeerConnectionManager.removeListener(_handleDependencyChanged);

      _peerListenerAttached = false;
    }

    if (_recoveryListenerAttached) {
      _recoveryManager.removeListener(_handleRecoveryChanged);

      _recoveryListenerAttached = false;
    }

    final subscription = _connectionSubscription;

    _connectionSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  void _handleDependencyChanged() {
    _requestMetricsUpdate();
  }

  void _handleRecoveryChanged() {
    final recovering =
        _recoveryManager.isRecovering || _recoveryManager.recoveryRequested;

    if (recovering && !_recoveryWasActive) {
      _recoveryWasActive = true;

      _safeCallback(onRecoveryRequired);
    } else if (!recovering &&
        _recoveryWasActive &&
        _connectionManager.isConnected) {
      _recoveryWasActive = false;

      _safeCallback(onRecoveryCompleted);
    }

    _requestMetricsUpdate();
  }

  void _handleConnectionChanged(ConnectionStateModel state) {
    _safeValueCallback(onConnectionChanged, state);

    /// IMPORTANT:
    /// Recovery is NOT started here.
    ///
    /// ConnectionManager and RecoveryManager already own
    /// recovery orchestration.

    _requestMetricsUpdate();
  }

  void _requestMetricsUpdate() {
    if (_disposed || !_monitoring) {
      return;
    }

    scheduleMicrotask(() {
      if (!_disposed && _monitoring) {
        unawaited(_analyzeAndEmitMetrics());
      }
    });
  }

  // ===========================================================
  // Metrics Analysis
  // ===========================================================

  Future<void> _analyzeAndEmitMetrics({bool force = false}) async {
    if (_disposed) {
      return;
    }

    if (_updating) {
      _pendingUpdate = true;
      return;
    }

    _updating = true;

    try {
      do {
        _pendingUpdate = false;

        final network = _networkManager.currentNetwork;

        final quality = network.quality;

        final networkType = network.type;

        final internetAvailable =
            network.isConnected && quality != NetworkQuality.offline;

        final ping = network.ping;

        Map<String, dynamic> statsData = <String, dynamic>{};

        try {
          statsData = await _resolvedStatsManager.getLatestStats();
        } catch (error, stackTrace) {
          _reportError(error, stackTrace, source: 'stats');
        }

        final rtt = _readInt(statsData['rtt']) ?? ping;

        final jitter =
            _readDouble(statsData['jitter']) ?? network.jitter.toDouble();

        final packetLoss =
            _readDouble(statsData['packetLoss']) ?? network.packetLoss;

        final uploadBitrateDouble =
            _readDouble(statsData['uploadBitrate']) ?? 0.0;

        final downloadBitrateDouble =
            _readDouble(statsData['downloadBitrate']) ?? 0.0;

        final currentVideoBitrateDouble =
            _readDouble(statsData['currentVideoBitrate']) ??
            uploadBitrateDouble;

        final optimizerAudioBitrate = await _networkOptimizer.audioBitrate;

        final currentAudioBitrateDouble =
            _readDouble(statsData['currentAudioBitrate']) ?? 0.0;

        final currentAudioBitrate = currentAudioBitrateDouble > 0
            ? currentAudioBitrateDouble.round()
            : optimizerAudioBitrate;

        final recommendedBitrate = network.recommendedBitrate > 0
            ? network.recommendedBitrate
            : await _networkOptimizer.videoBitrate;

        final recommendedFps = network.recommendedFps > 0
            ? network.recommendedFps
            : await _networkOptimizer.fps;

        final recommendedResolution = <String, int>{
          'width': network.videoWidth > 0 ? network.videoWidth : 640,
          'height': network.videoHeight > 0 ? network.videoHeight : 360,
        };

        Map<String, int> currentResolution;

        try {
          currentResolution =
              await _resolvedMediaManager.currentResolutionProfile;
        } catch (_) {
          currentResolution = Map<String, int>.from(recommendedResolution);
        }

        final peerConnection = _resolvedPeerConnectionManager.peerConnection;

        final peerConnectionState = _enumName(peerConnection?.connectionState);

        final iceConnectionState = _enumName(
          peerConnection?.iceConnectionState,
        );

        final signalingState = _enumName(peerConnection?.signalingState);

        final stabilityScore = _calculateStabilityScore(
          internetAvailable: internetAvailable,
          quality: quality,
          ping: ping,
          rtt: rtt,
          jitter: jitter,
          packetLoss: packetLoss,
        );

        final signalStrength = network.signalStrength.clamp(0, 100).toInt();

        final recommendation = _evaluateRecommendation(
          quality: quality,
          internetAvailable: internetAvailable,
          packetLoss: packetLoss,
          rtt: rtt,
          jitter: jitter,
          stability: stabilityScore,
          signalStrength: signalStrength,
        );

        var callDuration = 0;

        final callTimer = _callTimer;

        if (callTimer != null) {
          try {
            callDuration = callTimer.elapsedSeconds;
          } catch (_) {}
        }

        final metrics = CallQualityMetrics(
          quality: quality,
          networkType: networkType,
          isInternetAvailable: internetAvailable,
          ping: ping,
          rtt: rtt,
          jitter: jitter,
          packetLoss: packetLoss,
          uploadBitrate: uploadBitrateDouble.round(),
          downloadBitrate: downloadBitrateDouble.round(),
          currentVideoBitrate: currentVideoBitrateDouble.round(),
          currentAudioBitrate: currentAudioBitrate,
          recommendedBitrate: recommendedBitrate,
          recommendedFps: recommendedFps,
          recommendedResolution: Map<String, int>.unmodifiable(
            recommendedResolution,
          ),
          currentResolution: Map<String, int>.unmodifiable(currentResolution),
          signalStrength: signalStrength,
          callDurationSeconds: callDuration,
          peerConnectionState: peerConnectionState,
          iceConnectionState: iceConnectionState,
          signalingState: signalingState,
          transportType: 'unknown',
          stabilityScore: stabilityScore,
          recommendation: recommendation,
          reconnectCount: _recoveryManager.reconnectAttempts,
          isRecovering:
              _recoveryManager.isRecovering ||
              _recoveryManager.recoveryRequested,
        );

        _feedAi(metrics);

        if (force || _lastEmittedMetrics != metrics) {
          _lastEmittedMetrics = metrics;

          if (!_metricsController.isClosed) {
            _metricsController.add(metrics);
          }

          _safeValueCallback(onMetricsUpdated, metrics);
        }

        _emitChangedCallbacks(metrics);

        force = false;
      } while (_pendingUpdate && !_disposed);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, source: 'analysis');
    } finally {
      _updating = false;
    }
  }

  // ===========================================================
  // Stability
  // ===========================================================

  int _calculateStabilityScore({
    required bool internetAvailable,
    required NetworkQuality quality,
    required int ping,
    required int rtt,
    required double jitter,
    required double packetLoss,
  }) {
    if (!internetAvailable || quality == NetworkQuality.offline) {
      return 0;
    }

    var score = 100.0;

    final effectiveLatency = ping > rtt ? ping : rtt;

    if (effectiveLatency > 400) {
      score -= 35;
    } else if (effectiveLatency > 300) {
      score -= 28;
    } else if (effectiveLatency > 200) {
      score -= 20;
    } else if (effectiveLatency > 120) {
      score -= 12;
    } else if (effectiveLatency > 70) {
      score -= 6;
    }

    if (packetLoss > 15) {
      score -= 45;
    } else if (packetLoss > 10) {
      score -= 35;
    } else if (packetLoss > 5) {
      score -= 25;
    } else if (packetLoss > 2) {
      score -= 12;
    } else if (packetLoss > 1) {
      score -= 5;
    }

    if (jitter > 100) {
      score -= 25;
    } else if (jitter > 70) {
      score -= 18;
    } else if (jitter > 40) {
      score -= 12;
    } else if (jitter > 20) {
      score -= 5;
    }

    if (quality == NetworkQuality.poor) {
      score -= 12;
    } else if (quality == NetworkQuality.fair) {
      score -= 5;
    }

    return score.clamp(0.0, 100.0).round();
  }

  // ===========================================================
  // Recommendation Engine
  // ===========================================================

  CallRecommendation _evaluateRecommendation({
    required NetworkQuality quality,
    required bool internetAvailable,
    required double packetLoss,
    required int rtt,
    required double jitter,
    required int stability,
    required int signalStrength,
  }) {
    if (!internetAvailable || quality == NetworkQuality.offline) {
      return CallRecommendation.enableDataSaver;
    }

    if (packetLoss > 10 || stability < 30 || signalStrength < 15) {
      return CallRecommendation.enableDataSaver;
    }

    if (packetLoss > 5 ||
        quality == NetworkQuality.poor ||
        stability < 50 ||
        rtt > 350) {
      return CallRecommendation.reduceResolution;
    }

    if (quality == NetworkQuality.fair || rtt > 200 || jitter > 30) {
      return CallRecommendation.enableAdaptiveBitrate;
    }

    if (quality == NetworkQuality.good && (rtt > 120 || jitter > 15)) {
      return CallRecommendation.enableAdaptiveFps;
    }

    if (quality == NetworkQuality.excellent &&
        stability >= 90 &&
        signalStrength >= 80) {
      return CallRecommendation.enableSuperResolution;
    }

    return CallRecommendation.none;
  }

  // ===========================================================
  // AI Feed
  // ===========================================================

  void _feedAi(CallQualityMetrics metrics) {
    try {
      final engine = _aiCallEngine ?? AICallEngine.instance;

      engine.processMetrics(metrics);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, source: 'AI metrics feed');
    }
  }

  // ===========================================================
  // Changed-Only Callbacks
  // ===========================================================

  void _emitChangedCallbacks(CallQualityMetrics metrics) {
    if (_lastQuality != metrics.quality) {
      _lastQuality = metrics.quality;

      _safeValueCallback(onQualityChanged, metrics.quality);
    }

    if (_lastNetworkType != metrics.networkType) {
      _lastNetworkType = metrics.networkType;

      _safeValueCallback(onNetworkTypeChanged, metrics.networkType);
    }

    if (_lastStabilityScore != metrics.stabilityScore) {
      _lastStabilityScore = metrics.stabilityScore;

      _safeValueCallback(onStabilityChanged, metrics.stabilityScore);

      _safeValueCallback(onQualityScoreChanged, metrics.stabilityScore);
    }

    if (_lastRecommendedBitrate != metrics.recommendedBitrate) {
      _lastRecommendedBitrate = metrics.recommendedBitrate;

      _safeValueCallback(
        onBitrateRecommendationChanged,
        metrics.recommendedBitrate,
      );
    }

    if (_lastCurrentVideoBitrate != metrics.currentVideoBitrate) {
      _lastCurrentVideoBitrate = metrics.currentVideoBitrate;

      _safeValueCallback(onBitrateChanged, metrics.currentVideoBitrate);
    }

    if (_lastRecommendedFps != metrics.recommendedFps) {
      _lastRecommendedFps = metrics.recommendedFps;

      _safeValueCallback(onFpsRecommendationChanged, metrics.recommendedFps);
    }

    if (!_sameResolution(
      _lastRecommendedResolution,
      metrics.recommendedResolution,
    )) {
      _lastRecommendedResolution = Map<String, int>.from(
        metrics.recommendedResolution,
      );

      _safeValueCallback(
        onResolutionRecommendationChanged,
        Map<String, int>.unmodifiable(metrics.recommendedResolution),
      );
    }

    if (_lastRecommendation != metrics.recommendation) {
      _lastRecommendation = metrics.recommendation;

      _safeValueCallback(onRecommendationChanged, metrics.recommendation);
    }

    final highPacketLoss = metrics.packetLoss > 5.0;

    if (highPacketLoss && !_packetLossAlertActive) {
      _packetLossAlertActive = true;

      _safeValueCallback(onPacketLossHigh, metrics.packetLoss);
    } else if (!highPacketLoss) {
      _packetLossAlertActive = false;
    }
  }

  bool _sameResolution(Map<String, int>? first, Map<String, int> second) {
    if (first == null) {
      return false;
    }

    return first['width'] == second['width'] &&
        first['height'] == second['height'];
  }

  // ===========================================================
  // Public Read APIs
  // ===========================================================

  Future<int> getPing() async {
    return _networkManager.currentNetwork.ping;
  }

  Future<int> getRecommendedBitrate() async {
    final network = _networkManager.currentNetwork;

    if (network.recommendedBitrate > 0) {
      return network.recommendedBitrate;
    }

    return _networkOptimizer.videoBitrate;
  }

  Future<int> getRecommendedFps() async {
    final network = _networkManager.currentNetwork;

    if (network.recommendedFps > 0) {
      return network.recommendedFps;
    }

    return _networkOptimizer.fps;
  }

  bool get isHdAvailable =>
      _lastQuality == NetworkQuality.excellent ||
      _lastQuality == NetworkQuality.good;

  bool get isPoorConnection =>
      _lastQuality == NetworkQuality.poor ||
      _lastQuality == NetworkQuality.offline;

  Future<NetworkQuality> refresh() async {
    if (!_networkManager.isInitialized) {
      await _networkManager.initialize();
    } else {
      await _networkManager.refresh();
    }

    _lastQuality = _networkManager.currentNetwork.quality;

    await _analyzeAndEmitMetrics(force: true);

    return _lastQuality;
  }

  // ===========================================================
  // Helpers
  // ===========================================================

  int? _readInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return null;
  }

  double? _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return null;
  }

  String _enumName(Object? value) {
    if (value == null) {
      return 'unknown';
    }

    final raw = value.toString();

    final separator = raw.lastIndexOf('.');

    if (separator >= 0 && separator < raw.length - 1) {
      return raw.substring(separator + 1);
    }

    return raw;
  }

  // ===========================================================
  // Safe Callbacks
  // ===========================================================

  void _safeCallback(VoidCallback? callback) {
    if (_disposed || callback == null) {
      return;
    }

    try {
      callback();
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, source: 'callback');
    }
  }

  void _safeValueCallback<T>(ValueChanged<T>? callback, T value) {
    if (_disposed || callback == null) {
      return;
    }

    try {
      callback(value);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, source: 'value callback');
    }
  }

  void _reportError(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {
    debugPrint(
      'CallQualityMonitor [$source] '
      'error: $error',
    );

    debugPrintStack(
      label: 'CallQualityMonitor [$source]',
      stackTrace: stackTrace,
    );

    final callback = onError;

    if (_disposed || callback == null) {
      return;
    }

    try {
      callback(error);
    } catch (_) {}
  }

  // ===========================================================
  // Stop
  // ===========================================================

  void stop() {
    if (!_monitoring) {
      return;
    }

    _monitoring = false;

    _detachListeners();

    _pendingUpdate = false;

    debugPrint('CallQualityMonitor: monitoring stopped.');
  }

  // ===========================================================
  // Reset
  // ===========================================================

  void reset() {
    if (_disposed) {
      return;
    }

    stop();

    _initialized = false;
    _updating = false;
    _pendingUpdate = false;

    _lastQuality = NetworkQuality.offline;

    _lastNetworkType = null;
    _lastEmittedMetrics = null;
    _lastRecommendation = null;
    _lastRecommendedBitrate = null;
    _lastRecommendedFps = null;
    _lastCurrentVideoBitrate = null;
    _lastStabilityScore = null;
    _lastRecommendedResolution = null;

    _packetLossAlertActive = false;
    _recoveryWasActive = false;

    onMetricsUpdated = null;
    onStabilityChanged = null;
    onNetworkTypeChanged = null;
    onBitrateRecommendationChanged = null;
    onQualityScoreChanged = null;
    onQualityChanged = null;
    onConnectionChanged = null;
    onRecommendationChanged = null;
    onRecoveryRequired = null;
    onRecoveryCompleted = null;
    onPacketLossHigh = null;
    onBitrateChanged = null;
    onFpsRecommendationChanged = null;
    onResolutionRecommendationChanged = null;
    onError = null;
  }

  // ===========================================================
  // Dispose
  // ===========================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    stop();

    _statsManager = null;
    _mediaManager = null;
    _peerConnectionManager = null;
    _callTimer = null;
    _aiCallEngine = null;

    onMetricsUpdated = null;
    onStabilityChanged = null;
    onNetworkTypeChanged = null;
    onBitrateRecommendationChanged = null;
    onQualityScoreChanged = null;
    onQualityChanged = null;
    onConnectionChanged = null;
    onRecommendationChanged = null;
    onRecoveryRequired = null;
    onRecoveryCompleted = null;
    onPacketLossHigh = null;
    onBitrateChanged = null;
    onFpsRecommendationChanged = null;
    onResolutionRecommendationChanged = null;
    onError = null;

    _disposed = true;

    if (!_metricsController.isClosed) {
      await _metricsController.close();
    }

    debugPrint('CallQualityMonitor: disposed.');
  }
}
