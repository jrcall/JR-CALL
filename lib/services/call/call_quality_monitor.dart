import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/network_model.dart';
import '../managers/media_manager.dart';
import '../managers/network_manager.dart';
import '../managers/peer_connection_manager.dart';
import '../managers/recovery_manager.dart';
import '../managers/stats_manager.dart';
import 'call_timer.dart';
import 'connection_manager.dart';
import 'network_optimizer.dart';

/// ===========================================================
/// JR CALL
/// File: call_quality_monitor.dart
/// Location: lib/services/call/call_quality_monitor.dart
///
/// FINAL PRODUCTION REAL-TIME CALL QUALITY COORDINATOR.
///
/// Ownership:
/// - NetworkManager owns network measurement.
/// - StatsManager owns WebRTC statistics collection.
/// - ConnectionManager owns connection orchestration.
/// - RecoveryManager owns recovery scheduling.
/// - NetworkOptimizer owns optimization recommendations.
/// - CallQualityMonitor combines those states only.
/// - Optional AI receives emitted metrics through the
///   CallQualityMetricsConsumer contract.
///
/// Important:
/// - No direct AICallEngine import.
/// - No circular AI dependency.
/// - No duplicate network polling.
/// - No duplicate periodic timer.
/// - No duplicate WebRTC getStats polling.
/// - No direct ICE manipulation.
/// - No direct recovery execution.
/// - No direct signaling mutation.
/// - No bitrate mutation.
/// - No UI/design changes.
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
      quality == NetworkQuality.excellent ||
          quality == NetworkQuality.good;

  bool get isPoorConnection =>
      quality == NetworkQuality.poor ||
          quality == NetworkQuality.offline;

  static bool _mapEquals(
      Map<String, int> first,
      Map<String, int> second,
      ) {
    if (first.length != second.length) {
      return false;
    }

    for (final MapEntry<String, int> entry in first.entries) {
      if (second[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  static int _mapHash(
      Map<String, int> map,
      ) {
    final List<MapEntry<String, int>> entries =
    map.entries.toList()
      ..sort(
            (
            MapEntry<String, int> first,
            MapEntry<String, int> second,
            ) =>
            first.key.compareTo(second.key),
      );

    return Object.hashAll(
      entries.map(
            (MapEntry<String, int> entry) => Object.hash(
          entry.key,
          entry.value,
        ),
      ),
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
        _mapEquals(
          other.recommendedResolution,
          recommendedResolution,
        ) &&
        _mapEquals(
          other.currentResolution,
          currentResolution,
        ) &&
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
    return Object.hashAll(
      <Object?>[
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
      ],
    );
  }
}

/// ===========================================================
/// OPTIONAL METRICS CONSUMER CONTRACT
///
/// This interface intentionally lives in the metrics-owning
/// layer so CallQualityMonitor never imports AICallEngine.
///
/// AICallEngine implements this interface.
/// ===========================================================

abstract interface class CallQualityMetricsConsumer {
  void processMetrics(CallQualityMetrics metrics);
}

class CallQualityMonitor {
  CallQualityMonitor._();

  static final CallQualityMonitor instance =
  CallQualityMonitor._();

  // ===========================================================
  // CORE DEPENDENCIES
  // ===========================================================

  final NetworkManager _networkManager =
      NetworkManager.instance;

  final ConnectionManager _connectionManager =
      ConnectionManager.instance;

  final RecoveryManager _recoveryManager =
      RecoveryManager.instance;

  final NetworkOptimizer _networkOptimizer =
      NetworkOptimizer.instance;

  StatsManager? _statsManager;

  MediaManager? _mediaManager;

  PeerConnectionManager? _peerConnectionManager;

  CallTimer? _callTimer;

  CallQualityMetricsConsumer? _aiMetricsConsumer;

  StatsManager get _resolvedStatsManager =>
      _statsManager ?? StatsManager.instance;

  MediaManager get _resolvedMediaManager =>
      _mediaManager ?? MediaManager.instance;

  PeerConnectionManager get _resolvedPeerConnectionManager =>
      _peerConnectionManager ??
          PeerConnectionManager.instance;

  // ===========================================================
  // METRICS STREAM
  // ===========================================================

  final StreamController<CallQualityMetrics>
  _metricsController =
  StreamController<CallQualityMetrics>.broadcast(
    sync: true,
  );

  Stream<CallQualityMetrics> get metricsStream =>
      _metricsController.stream;

  // ===========================================================
  // LISTENER STATE
  // ===========================================================

  StreamSubscription<ConnectionStateModel>?
  _connectionSubscription;

  bool _networkListenerAttached = false;

  bool _statsListenerAttached = false;

  bool _mediaListenerAttached = false;

  bool _peerListenerAttached = false;

  bool _recoveryListenerAttached = false;

  // ===========================================================
  // RUNTIME STATE
  // ===========================================================

  bool _initialized = false;

  bool _monitoring = false;

  bool _updating = false;

  bool _pendingUpdate = false;

  bool _pendingForce = false;

  bool _updateScheduled = false;

  bool _disposed = false;

  int _lifecycleGeneration = 0;

  int _initializationGeneration = 0;

  int? _activeUpdateGeneration;

  Future<void>? _activeInitialization;

  Future<void>? _activeStart;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  bool get isInitialized => _initialized;

  bool get isMonitoring => _monitoring;

  NetworkQuality _lastQuality =
      NetworkQuality.offline;

  NetworkQuality get currentQuality =>
      _lastQuality;

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
  // PUBLIC CALLBACKS
  // ===========================================================

  ValueChanged<CallQualityMetrics>?
  onMetricsUpdated;

  ValueChanged<int>? onStabilityChanged;

  ValueChanged<NetworkType>?
  onNetworkTypeChanged;

  ValueChanged<int>?
  onBitrateRecommendationChanged;

  ValueChanged<int>? onQualityScoreChanged;

  ValueChanged<NetworkQuality>?
  onQualityChanged;

  ValueChanged<ConnectionStateModel>?
  onConnectionChanged;

  ValueChanged<CallRecommendation>?
  onRecommendationChanged;

  VoidCallback? onRecoveryRequired;

  VoidCallback? onRecoveryCompleted;

  ValueChanged<double>? onPacketLossHigh;

  ValueChanged<int>? onBitrateChanged;

  ValueChanged<int>?
  onFpsRecommendationChanged;

  ValueChanged<Map<String, int>>?
  onResolutionRecommendationChanged;

  ValueChanged<Object>? onError;

  // ===========================================================
  // DEPENDENCY INJECTION
  // ===========================================================

  void setDependencies({
    StatsManager? statsManager,
    MediaManager? mediaManager,
    PeerConnectionManager? peerConnectionManager,
    CallTimer? callTimer,
    CallQualityMetricsConsumer? aiCallEngine,
  }) {
    if (_disposed) {
      return;
    }

    final bool wasMonitoring =
        _monitoring;

    if (wasMonitoring) {
      _detachListeners();
    }

    _lifecycleGeneration++;

    _statsManager = statsManager;

    _mediaManager = mediaManager;

    _peerConnectionManager =
        peerConnectionManager;

    _callTimer = callTimer;

    _aiMetricsConsumer =
        aiCallEngine;

    if (wasMonitoring) {
      final int generation =
          _lifecycleGeneration;

      _attachListeners(generation);

      _requestMetricsUpdate(
        force: true,
      );
    }
  }

  /// Dedicated AI registration avoids resetting any injected
  /// StatsManager/MediaManager/PeerConnectionManager dependency.
  void setAiMetricsConsumer(
      CallQualityMetricsConsumer consumer,
      ) {
    if (_disposed) {
      return;
    }

    _aiMetricsConsumer =
        consumer;
  }

  void clearAiMetricsConsumer(
      CallQualityMetricsConsumer consumer,
      ) {
    if (_disposed) {
      return;
    }

    if (identical(
      _aiMetricsConsumer,
      consumer,
    )) {
      _aiMetricsConsumer =
      null;
    }
  }

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() async {
    if (_disposed) {
      throw StateError(
        'CallQualityMonitor has been disposed.',
      );
    }

    if (_initialized) {
      return;
    }

    final Future<void>? active =
        _activeInitialization;

    if (active != null) {
      await active;

      return;
    }

    final int generation =
    ++_initializationGeneration;

    final Future<void> operation =
    _initializeInternal(
      generation,
    );

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _activeInitialization,
        tracked,
      )) {
        _activeInitialization = null;
      }
    });

    _activeInitialization =
        tracked;

    await tracked;
  }

  Future<void> _initializeInternal(
      int generation,
      ) async {
    try {
      if (!_networkManager.isInitialized) {
        await _networkManager.initialize();
      }

      if (!_isInitializationCurrent(
        generation,
      )) {
        return;
      }

      if (!_networkOptimizer.isInitialized) {
        await _networkOptimizer.initialize();
      }

      if (!_isInitializationCurrent(
        generation,
      )) {
        return;
      }

      final StatsManager statsManager =
          _resolvedStatsManager;

      if (!statsManager.isInitialized) {
        await statsManager.initialize();
      }

      if (!_isInitializationCurrent(
        generation,
      )) {
        return;
      }

      if (!_connectionManager.isMonitoring) {
        await _connectionManager
            .startMonitoring();
      }

      if (!_isInitializationCurrent(
        generation,
      )) {
        return;
      }

      _initialized = true;

      await _analyzeAndEmitMetrics(
        expectedGeneration:
        _lifecycleGeneration,
        force: true,
        allowWhenNotMonitoring: true,
      );

      _debugPrint(
        'initialized.',
      );
    } catch (error, stackTrace) {
      if (_isInitializationCurrent(
        generation,
      )) {
        _reportError(
          error,
          stackTrace,
          source: 'initialize',
        );
      }

      rethrow;
    }
  }

  // ===========================================================
  // START
  // ===========================================================

  Future<void> start({
    Duration interval =
    const Duration(seconds: 2),
  }) async {
    if (_disposed) {
      throw StateError(
        'CallQualityMonitor has been disposed.',
      );
    }

    if (_monitoring) {
      await _analyzeAndEmitMetrics(
        expectedGeneration:
        _lifecycleGeneration,
        force: true,
      );

      return;
    }

    final Future<void>? active =
        _activeStart;

    if (active != null) {
      await active;

      return;
    }

    final int generation =
    ++_lifecycleGeneration;

    final Future<void> operation =
    _startInternal(
      generation,
    );

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _activeStart,
        tracked,
      )) {
        _activeStart = null;
      }
    });

    _activeStart =
        tracked;

    await tracked;
  }

  Future<void> _startInternal(
      int generation,
      ) async {
    if (!_initialized) {
      await initialize();
    }

    if (!_isLifecycleCurrent(
      generation,
    )) {
      return;
    }

    _monitoring =
    true;

    _attachListeners(
      generation,
    );

    if (!_isMonitoringGeneration(
      generation,
    )) {
      _detachListeners();

      return;
    }

    await _analyzeAndEmitMetrics(
      expectedGeneration:
      generation,
      force: true,
    );

    if (!_isMonitoringGeneration(
      generation,
    )) {
      return;
    }

    _debugPrint(
      'monitoring started.',
    );
  }

  // ===========================================================
  // LISTENER WIRING
  // ===========================================================

  void _attachListeners(
      int generation,
      ) {
    if (!_networkListenerAttached) {
      _networkManager.addListener(
        _handleDependencyChanged,
      );

      _networkListenerAttached =
      true;
    }

    if (!_statsListenerAttached) {
      _resolvedStatsManager.addListener(
        _handleDependencyChanged,
      );

      _statsListenerAttached =
      true;
    }

    if (!_mediaListenerAttached) {
      _resolvedMediaManager.addListener(
        _handleDependencyChanged,
      );

      _mediaListenerAttached =
      true;
    }

    if (!_peerListenerAttached) {
      _resolvedPeerConnectionManager
          .addListener(
        _handleDependencyChanged,
      );

      _peerListenerAttached =
      true;
    }

    if (!_recoveryListenerAttached) {
      _recoveryManager.addListener(
        _handleRecoveryChanged,
      );

      _recoveryListenerAttached =
      true;
    }

    _connectionSubscription ??=
        _connectionManager
            .connectionStream
            .listen(
              (
              ConnectionStateModel state,
              ) {
            if (!_isMonitoringGeneration(
              generation,
            )) {
              return;
            }

            _handleConnectionChanged(
              state,
            );
          },
          onError: (
              Object error,
              StackTrace stackTrace,
              ) {
            if (!_isMonitoringGeneration(
              generation,
            )) {
              return;
            }

            _reportError(
              error,
              stackTrace,
              source: 'connection stream',
            );
          },
        );
  }

  void _detachListeners() {
    if (_networkListenerAttached) {
      _networkManager.removeListener(
        _handleDependencyChanged,
      );

      _networkListenerAttached =
      false;
    }

    if (_statsListenerAttached) {
      _resolvedStatsManager.removeListener(
        _handleDependencyChanged,
      );

      _statsListenerAttached =
      false;
    }

    if (_mediaListenerAttached) {
      _resolvedMediaManager.removeListener(
        _handleDependencyChanged,
      );

      _mediaListenerAttached =
      false;
    }

    if (_peerListenerAttached) {
      _resolvedPeerConnectionManager
          .removeListener(
        _handleDependencyChanged,
      );

      _peerListenerAttached =
      false;
    }

    if (_recoveryListenerAttached) {
      _recoveryManager.removeListener(
        _handleRecoveryChanged,
      );

      _recoveryListenerAttached =
      false;
    }

    final StreamSubscription<ConnectionStateModel>?
    subscription =
        _connectionSubscription;

    _connectionSubscription =
    null;

    if (subscription != null) {
      unawaited(
        _cancelConnectionSubscription(
          subscription,
        ),
      );
    }
  }

  Future<void> _cancelConnectionSubscription(
      StreamSubscription<ConnectionStateModel>
      subscription,
      ) async {
    try {
      await subscription.cancel();
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        source:
        'connection subscription cancel',
      );
    }
  }

  // ===========================================================
  // DEPENDENCY EVENTS
  // ===========================================================

  void _handleDependencyChanged() {
    if (_disposed ||
        !_monitoring) {
      return;
    }

    _requestMetricsUpdate();
  }

  void _handleRecoveryChanged() {
    if (_disposed ||
        !_monitoring) {
      return;
    }

    final bool recovering =
        _recoveryManager.isRecovering ||
            _recoveryManager.recoveryRequested;

    if (recovering &&
        !_recoveryWasActive) {
      _recoveryWasActive =
      true;

      _safeCallback(
        onRecoveryRequired,
      );
    } else if (!recovering &&
        _recoveryWasActive) {
      final bool recoveredTransport =
      _peerTransportConnected();

      _recoveryWasActive =
      false;

      if (recoveredTransport) {
        _safeCallback(
          onRecoveryCompleted,
        );
      }
    }

    _requestMetricsUpdate();
  }

  void _handleConnectionChanged(
      ConnectionStateModel state,
      ) {
    _safeValueCallback(
      onConnectionChanged,
      state,
    );

    _requestMetricsUpdate();
  }

  // ===========================================================
  // METRICS UPDATE COALESCING
  // ===========================================================

  void _requestMetricsUpdate({
    bool force = false,
  }) {
    if (_disposed ||
        !_monitoring) {
      return;
    }

    _pendingUpdate =
    true;

    if (force) {
      _pendingForce =
      true;
    }

    if (_updating ||
        _updateScheduled) {
      return;
    }

    _updateScheduled =
    true;

    final int generation =
        _lifecycleGeneration;

    scheduleMicrotask(() {
      _updateScheduled =
      false;

      if (!_isMonitoringGeneration(
        generation,
      )) {
        return;
      }

      final bool forceUpdate =
          _pendingForce;

      _pendingForce =
      false;

      _pendingUpdate =
      false;

      unawaited(
        _analyzeAndEmitMetrics(
          expectedGeneration:
          generation,
          force:
          forceUpdate,
        ),
      );
    });
  }

  // ===========================================================
  // METRICS ANALYSIS
  // ===========================================================

  Future<void> _analyzeAndEmitMetrics({
    required int expectedGeneration,
    bool force = false,
    bool allowWhenNotMonitoring = false,
  }) async {
    if (!_isAnalysisAllowed(
      expectedGeneration,
      allowWhenNotMonitoring:
      allowWhenNotMonitoring,
    )) {
      return;
    }

    if (_updating) {
      _pendingUpdate =
      true;

      if (force) {
        _pendingForce =
        true;
      }

      return;
    }

    _updating =
    true;

    _activeUpdateGeneration =
        expectedGeneration;

    try {
      bool currentForce =
          force;

      do {
        _pendingUpdate =
        false;

        if (_pendingForce) {
          currentForce =
          true;

          _pendingForce =
          false;
        }

        if (!_isAnalysisAllowed(
          expectedGeneration,
          allowWhenNotMonitoring:
          allowWhenNotMonitoring,
        )) {
          break;
        }

        final CallQualityMetrics? metrics =
        await _buildMetrics(
          expectedGeneration:
          expectedGeneration,
          allowWhenNotMonitoring:
          allowWhenNotMonitoring,
        );

        if (metrics == null) {
          break;
        }

        if (!_isAnalysisAllowed(
          expectedGeneration,
          allowWhenNotMonitoring:
          allowWhenNotMonitoring,
        )) {
          break;
        }

        final bool shouldEmit =
            currentForce ||
                _lastEmittedMetrics !=
                    metrics;

        if (shouldEmit) {
          _lastEmittedMetrics =
              metrics;

          if (!_metricsController.isClosed) {
            _metricsController.add(
              metrics,
            );
          }

          _safeValueCallback(
            onMetricsUpdated,
            metrics,
          );

          if (!_isAnalysisAllowed(
            expectedGeneration,
            allowWhenNotMonitoring:
            allowWhenNotMonitoring,
          )) {
            break;
          }

          _feedAi(
            metrics,
          );
        }

        _emitChangedCallbacks(
          metrics,
          expectedGeneration:
          expectedGeneration,
          allowWhenNotMonitoring:
          allowWhenNotMonitoring,
        );

        currentForce =
        false;
      } while (
      _pendingUpdate &&
          _isAnalysisAllowed(
            expectedGeneration,
            allowWhenNotMonitoring:
            allowWhenNotMonitoring,
          ));
    } catch (error, stackTrace) {
      if (_isAnalysisAllowed(
        expectedGeneration,
        allowWhenNotMonitoring:
        allowWhenNotMonitoring,
      )) {
        _reportError(
          error,
          stackTrace,
          source: 'analysis',
        );
      }
    } finally {
      if (_activeUpdateGeneration ==
          expectedGeneration) {
        _activeUpdateGeneration =
        null;

        _updating =
        false;
      }

      if (_pendingUpdate &&
          _monitoring &&
          !_disposed) {
        _requestMetricsUpdate(
          force:
          _pendingForce,
        );
      }
    }
  }

  Future<CallQualityMetrics?> _buildMetrics({
    required int expectedGeneration,
    required bool allowWhenNotMonitoring,
  }) async {
    final _OptimizerSnapshot optimizerSnapshot =
    await _captureOptimizerSnapshot();

    if (!_isAnalysisAllowed(
      expectedGeneration,
      allowWhenNotMonitoring:
      allowWhenNotMonitoring,
    )) {
      return null;
    }

    final NetworkModel network =
        optimizerSnapshot.network;

    final Map<String, dynamic>
    optimizerProfile =
        optimizerSnapshot.profile;

    final StatsManager statsManager =
        _resolvedStatsManager;

    final MediaManager mediaManager =
        _resolvedMediaManager;

    final PeerConnectionManager
    peerConnectionManager =
        _resolvedPeerConnectionManager;

    Map<String, dynamic> statsData =
    <String, dynamic>{};

    try {
      statsData =
      await statsManager.getLatestStats();
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        source: 'stats',
      );
    }

    if (!_isAnalysisAllowed(
      expectedGeneration,
      allowWhenNotMonitoring:
      allowWhenNotMonitoring,
    )) {
      return null;
    }

    final bool internetAvailable =
        network.isConnected;

    final int networkPing =
    _normalizedLatency(
      network.ping,
    );

    final int measuredRtt =
        _readNonNegativeInt(
          statsData['rtt'],
        ) ??
            0;

    final int effectiveRtt =
    measuredRtt > 0
        ? measuredRtt
        : networkPing;

    final double measuredJitter =
        _readNonNegativeDouble(
          statsData['jitter'],
        ) ??
            network.jitter.toDouble();

    final double measuredPacketLoss =
    _normalizePacketLoss(
      _readNonNegativeDouble(
        statsData['packetLoss'],
      ) ??
          network.packetLoss,
    );

    final double uploadBitrate =
        _readNonNegativeDouble(
          statsData['uploadBitrate'],
        ) ??
            0.0;

    final double downloadBitrate =
        _readNonNegativeDouble(
          statsData['downloadBitrate'],
        ) ??
            0.0;

    final double currentVideoBitrate =
        _readNonNegativeDouble(
          statsData[
          'currentVideoBitrate'],
        ) ??
            0.0;

    final double currentAudioBitrate =
        _readNonNegativeDouble(
          statsData[
          'currentAudioBitrate'],
        ) ??
            0.0;

    final int recommendedBitrate =
        _readNonNegativeInt(
          optimizerProfile[
          'videoBitrate'],
        ) ??
            0;

    final int recommendedFps =
        _readNonNegativeInt(
          optimizerProfile['fps'],
        ) ??
            0;

    final int recommendedWidth =
        _readPositiveInt(
          optimizerProfile['width'],
        ) ??
            640;

    final int recommendedHeight =
        _readPositiveInt(
          optimizerProfile['height'],
        ) ??
            360;

    final Map<String, int>
    recommendedResolution =
    <String, int>{
      'width': recommendedWidth,
      'height': recommendedHeight,
    };

    Map<String, int> currentResolution =
    const <String, int>{
      'width': 0,
      'height': 0,
    };

    try {
      currentResolution =
      await mediaManager
          .currentResolutionProfile;
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        source:
        'current media resolution',
      );
    }

    if (!_isAnalysisAllowed(
      expectedGeneration,
      allowWhenNotMonitoring:
      allowWhenNotMonitoring,
    )) {
      return null;
    }

    final RTCPeerConnection?
    peerConnection =
        peerConnectionManager
            .peerConnection;

    final String peerConnectionState =
    _enumName(
      peerConnection?.connectionState,
    );

    final String iceConnectionState =
    _enumName(
      peerConnection?.iceConnectionState,
    );

    final String signalingState =
    _enumName(
      peerConnection?.signalingState,
    );

    final int signalStrength =
    network.signalStrength
        .clamp(
      0,
      100,
    )
        .toInt();

    final int stabilityScore =
    _calculateStabilityScore(
      internetAvailable:
      internetAvailable,
      quality:
      network.quality,
      advisoryPing:
      networkPing,
      measuredRtt:
      measuredRtt,
      jitter:
      measuredJitter,
      packetLoss:
      measuredPacketLoss,
    );

    final CallRecommendation recommendation =
    _evaluateRecommendation(
      quality:
      network.quality,
      internetAvailable:
      internetAvailable,
      packetLoss:
      measuredPacketLoss,
      rtt:
      effectiveRtt,
      jitter:
      measuredJitter,
      stability:
      stabilityScore,
      signalStrength:
      signalStrength,
    );

    int callDuration = 0;

    final CallTimer? callTimer =
        _callTimer;

    if (callTimer != null) {
      try {
        final int elapsed =
            callTimer.elapsedSeconds;

        if (elapsed > 0) {
          callDuration =
              elapsed;
        }
      } catch (_) {}
    }

    return CallQualityMetrics(
      quality:
      network.quality,
      networkType:
      network.type,
      isInternetAvailable:
      internetAvailable,
      ping:
      networkPing,
      rtt:
      effectiveRtt,
      jitter:
      measuredJitter,
      packetLoss:
      measuredPacketLoss,
      uploadBitrate:
      uploadBitrate.round(),
      downloadBitrate:
      downloadBitrate.round(),
      currentVideoBitrate:
      currentVideoBitrate.round(),
      currentAudioBitrate:
      currentAudioBitrate.round(),
      recommendedBitrate:
      recommendedBitrate,
      recommendedFps:
      recommendedFps,
      recommendedResolution:
      Map<String, int>.unmodifiable(
        recommendedResolution,
      ),
      currentResolution:
      Map<String, int>.unmodifiable(
        currentResolution,
      ),
      signalStrength:
      signalStrength,
      callDurationSeconds:
      callDuration,
      peerConnectionState:
      peerConnectionState,
      iceConnectionState:
      iceConnectionState,
      signalingState:
      signalingState,
      transportType:
      'unknown',
      stabilityScore:
      stabilityScore,
      recommendation:
      recommendation,
      reconnectCount:
      _recoveryManager
          .reconnectAttempts,
      isRecovering:
      _recoveryManager.isRecovering ||
          _recoveryManager
              .recoveryRequested,
    );
  }

  // ===========================================================
  // OPTIMIZER SNAPSHOT
  // ===========================================================

  Future<_OptimizerSnapshot>
  _captureOptimizerSnapshot() async {
    const int maxAttempts = 3;

    for (int attempt = 0;
    attempt < maxAttempts;
    attempt++) {
      final NetworkModel network =
          _networkManager.currentNetwork;

      final Map<String, dynamic> profile =
      await _networkOptimizer
          .recommendedProfile;

      if (identical(
        network,
        _networkManager.currentNetwork,
      )) {
        return _OptimizerSnapshot(
          network: network,
          profile: profile,
        );
      }
    }

    final NetworkModel network =
        _networkManager.currentNetwork;

    final Map<String, dynamic> profile =
    await _networkOptimizer
        .recommendedProfile;

    return _OptimizerSnapshot(
      network: network,
      profile: profile,
    );
  }

  // ===========================================================
  // STABILITY
  // ===========================================================

  int _calculateStabilityScore({
    required bool internetAvailable,
    required NetworkQuality quality,
    required int advisoryPing,
    required int measuredRtt,
    required double jitter,
    required double packetLoss,
  }) {
    if (!internetAvailable) {
      return 0;
    }

    double score = 100.0;

    final int effectiveLatency =
    measuredRtt > 0
        ? measuredRtt
        : advisoryPing;

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

    if (quality ==
        NetworkQuality.poor) {
      score -= 12;
    } else if (quality ==
        NetworkQuality.fair) {
      score -= 5;
    }

    return score
        .clamp(
      0.0,
      100.0,
    )
        .round();
  }

  // ===========================================================
  // RECOMMENDATION ENGINE
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
    if (!internetAvailable) {
      return CallRecommendation
          .enableDataSaver;
    }

    final bool weakMeasuredSignal =
        signalStrength > 0 &&
            signalStrength < 15;

    if (packetLoss > 10 ||
        stability < 30 ||
        weakMeasuredSignal) {
      return CallRecommendation
          .enableDataSaver;
    }

    if (packetLoss > 5 ||
        quality ==
            NetworkQuality.poor ||
        stability < 50 ||
        rtt > 350) {
      return CallRecommendation
          .reduceResolution;
    }

    if (quality ==
        NetworkQuality.fair ||
        rtt > 200 ||
        jitter > 30) {
      return CallRecommendation
          .enableAdaptiveBitrate;
    }

    if (quality ==
        NetworkQuality.good &&
        (rtt > 120 ||
            jitter > 15)) {
      return CallRecommendation
          .enableAdaptiveFps;
    }

    final bool signalAllowsEnhancement =
        signalStrength <= 0 ||
            signalStrength >= 80;

    if (quality ==
        NetworkQuality.excellent &&
        stability >= 90 &&
        signalAllowsEnhancement) {
      return CallRecommendation
          .enableSuperResolution;
    }

    return CallRecommendation.none;
  }

  // ===========================================================
  // OPTIONAL AI FEED
  // ===========================================================

  void _feedAi(
      CallQualityMetrics metrics,
      ) {
    final CallQualityMetricsConsumer? consumer =
        _aiMetricsConsumer;

    if (consumer == null) {
      return;
    }

    try {
      consumer.processMetrics(
        metrics,
      );
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        source: 'AI metrics feed',
      );
    }
  }

  // ===========================================================
  // CHANGED-ONLY CALLBACKS
  // ===========================================================

  void _emitChangedCallbacks(
      CallQualityMetrics metrics, {
        required int expectedGeneration,
        required bool allowWhenNotMonitoring,
      }) {
    if (!_isAnalysisAllowed(
      expectedGeneration,
      allowWhenNotMonitoring:
      allowWhenNotMonitoring,
    )) {
      return;
    }

    if (_lastQuality !=
        metrics.quality) {
      _lastQuality =
          metrics.quality;

      _safeValueCallback(
        onQualityChanged,
        metrics.quality,
      );
    }

    if (!_isAnalysisAllowed(
      expectedGeneration,
      allowWhenNotMonitoring:
      allowWhenNotMonitoring,
    )) {
      return;
    }

    if (_lastNetworkType !=
        metrics.networkType) {
      _lastNetworkType =
          metrics.networkType;

      _safeValueCallback(
        onNetworkTypeChanged,
        metrics.networkType,
      );
    }

    if (_lastStabilityScore !=
        metrics.stabilityScore) {
      _lastStabilityScore =
          metrics.stabilityScore;

      _safeValueCallback(
        onStabilityChanged,
        metrics.stabilityScore,
      );

      _safeValueCallback(
        onQualityScoreChanged,
        metrics.stabilityScore,
      );
    }

    if (_lastRecommendedBitrate !=
        metrics.recommendedBitrate) {
      _lastRecommendedBitrate =
          metrics.recommendedBitrate;

      _safeValueCallback(
        onBitrateRecommendationChanged,
        metrics.recommendedBitrate,
      );
    }

    if (_lastCurrentVideoBitrate !=
        metrics.currentVideoBitrate) {
      _lastCurrentVideoBitrate =
          metrics.currentVideoBitrate;

      _safeValueCallback(
        onBitrateChanged,
        metrics.currentVideoBitrate,
      );
    }

    if (_lastRecommendedFps !=
        metrics.recommendedFps) {
      _lastRecommendedFps =
          metrics.recommendedFps;

      _safeValueCallback(
        onFpsRecommendationChanged,
        metrics.recommendedFps,
      );
    }

    if (!_sameResolution(
      _lastRecommendedResolution,
      metrics.recommendedResolution,
    )) {
      _lastRecommendedResolution =
      Map<String, int>.from(
        metrics.recommendedResolution,
      );

      _safeValueCallback(
        onResolutionRecommendationChanged,
        Map<String, int>.unmodifiable(
          metrics.recommendedResolution,
        ),
      );
    }

    if (_lastRecommendation !=
        metrics.recommendation) {
      _lastRecommendation =
          metrics.recommendation;

      _safeValueCallback(
        onRecommendationChanged,
        metrics.recommendation,
      );
    }

    final bool highPacketLoss =
        metrics.packetLoss > 5.0;

    if (highPacketLoss &&
        !_packetLossAlertActive) {
      _packetLossAlertActive =
      true;

      _safeValueCallback(
        onPacketLossHigh,
        metrics.packetLoss,
      );
    } else if (!highPacketLoss) {
      _packetLossAlertActive =
      false;
    }
  }

  bool _sameResolution(
      Map<String, int>? first,
      Map<String, int> second,
      ) {
    if (first == null) {
      return false;
    }

    return first['width'] ==
        second['width'] &&
        first['height'] ==
            second['height'];
  }

  // ===========================================================
  // PEER TRANSPORT STATE
  // ===========================================================

  bool _peerTransportConnected() {
    final PeerConnectionManager manager =
        _resolvedPeerConnectionManager;

    final RTCPeerConnectionState?
    connectionState =
        manager.connectionState;

    final RTCIceConnectionState?
    iceState =
        manager.iceConnectionState;

    return connectionState ==
        RTCPeerConnectionState
            .RTCPeerConnectionStateConnected ||
        iceState ==
            RTCIceConnectionState
                .RTCIceConnectionStateConnected ||
        iceState ==
            RTCIceConnectionState
                .RTCIceConnectionStateCompleted;
  }

  // ===========================================================
  // PUBLIC READ APIS
  // ===========================================================

  Future<int> getPing() async {
    return _networkManager
        .currentNetwork
        .ping;
  }

  Future<int> getRecommendedBitrate() async {
    final NetworkModel network =
        _networkManager.currentNetwork;

    if (network.recommendedBitrate > 0) {
      return network.recommendedBitrate;
    }

    return await _networkOptimizer
        .videoBitrate;
  }

  Future<int> getRecommendedFps() async {
    final NetworkModel network =
        _networkManager.currentNetwork;

    if (network.recommendedFps > 0) {
      return network.recommendedFps;
    }

    return await _networkOptimizer.fps;
  }

  bool get isHdAvailable =>
      _lastQuality ==
          NetworkQuality.excellent ||
          _lastQuality ==
              NetworkQuality.good;

  bool get isPoorConnection =>
      _lastQuality ==
          NetworkQuality.poor ||
          _lastQuality ==
              NetworkQuality.offline;

  Future<NetworkQuality> refresh() async {
    if (_disposed) {
      return _lastQuality;
    }

    if (!_networkManager.isInitialized) {
      await _networkManager.initialize();
    } else {
      await _networkManager.refresh();
    }

    if (_disposed) {
      return _lastQuality;
    }

    _lastQuality =
        _networkManager
            .currentNetwork
            .quality;

    await _analyzeAndEmitMetrics(
      expectedGeneration:
      _lifecycleGeneration,
      force: true,
      allowWhenNotMonitoring: true,
    );

    return _lastQuality;
  }

  // ===========================================================
  // VALUE HELPERS
  // ===========================================================

  int? _readNonNegativeInt(
      Object? value,
      ) {
    int? result;

    if (value is int) {
      result = value;
    } else if (value is num &&
        value.isFinite) {
      result = value.toInt();
    } else if (value is String) {
      result = int.tryParse(
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
    _readNonNegativeInt(value);

    if (result == null ||
        result <= 0) {
      return null;
    }

    return result;
  }

  double? _readNonNegativeDouble(
      Object? value,
      ) {
    double? result;

    if (value is double) {
      result = value;
    } else if (value is num) {
      result = value.toDouble();
    } else if (value is String) {
      result = double.tryParse(
        value.trim(),
      );
    }

    if (result == null ||
        !result.isFinite ||
        result < 0) {
      return null;
    }

    return result;
  }

  double _normalizePacketLoss(
      double value,
      ) {
    if (!value.isFinite ||
        value < 0) {
      return 0.0;
    }

    if (value > 100) {
      return 100.0;
    }

    return value;
  }

  int _normalizedLatency(
      int value,
      ) {
    if (value < 0) {
      return 0;
    }

    return value;
  }

  String _enumName(
      Object? value,
      ) {
    if (value == null) {
      return 'unknown';
    }

    final String raw =
    value.toString();

    final int separator =
    raw.lastIndexOf('.');

    if (separator >= 0 &&
        separator <
            raw.length - 1) {
      return raw.substring(
        separator + 1,
      );
    }

    return raw;
  }

  // ===========================================================
  // GENERATION VALIDATION
  // ===========================================================

  bool _isInitializationCurrent(
      int generation,
      ) {
    return !_disposed &&
        generation ==
            _initializationGeneration;
  }

  bool _isLifecycleCurrent(
      int generation,
      ) {
    return !_disposed &&
        generation ==
            _lifecycleGeneration;
  }

  bool _isMonitoringGeneration(
      int generation,
      ) {
    return !_disposed &&
        _monitoring &&
        generation ==
            _lifecycleGeneration;
  }

  bool _isAnalysisAllowed(
      int generation, {
        required bool allowWhenNotMonitoring,
      }) {
    if (_disposed ||
        generation !=
            _lifecycleGeneration) {
      return false;
    }

    if (allowWhenNotMonitoring) {
      return true;
    }

    return _monitoring;
  }

  // ===========================================================
  // SAFE CALLBACKS
  // ===========================================================

  void _safeCallback(
      VoidCallback? callback,
      ) {
    if (_disposed ||
        callback == null) {
      return;
    }

    try {
      callback();
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        source: 'callback',
      );
    }
  }

  void _safeValueCallback<T>(
      ValueChanged<T>? callback,
      T value,
      ) {
    if (_disposed ||
        callback == null) {
      return;
    }

    try {
      callback(value);
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        source: 'value callback',
      );
    }
  }

  // ===========================================================
  // ERROR REPORTING
  // ===========================================================

  void _reportError(
      Object error,
      StackTrace stackTrace, {
        required String source,
      }) {
    if (kDebugMode) {
      debugPrint(
        'JR CALL '
            '[CallQualityMonitor/$source] '
            'error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL '
            '[CallQualityMonitor/$source]',
        stackTrace: stackTrace,
      );
    }

    final ValueChanged<Object>? callback =
        onError;

    if (_disposed ||
        callback == null) {
      return;
    }

    try {
      callback(error);
    } catch (_) {}
  }

  // ===========================================================
  // STOP
  // ===========================================================

  void stop() {
    if (_disposed) {
      return;
    }

    final bool hadActivity =
        _monitoring ||
            _activeStart != null ||
            _updateScheduled ||
            _updating;

    _lifecycleGeneration++;

    _monitoring =
    false;

    _activeStart =
    null;

    _updateScheduled =
    false;

    _pendingUpdate =
    false;

    _pendingForce =
    false;

    _recoveryWasActive =
    false;

    _detachListeners();

    if (hadActivity) {
      _debugPrint(
        'monitoring stopped.',
      );
    }
  }

  // ===========================================================
  // RESET
  // ===========================================================

  void reset() {
    if (_disposed) {
      return;
    }

    stop();

    _initializationGeneration++;

    _activeInitialization =
    null;

    _initialized =
    false;

    _aiMetricsConsumer =
    null;

    _lastQuality =
        NetworkQuality.offline;

    _lastNetworkType =
    null;

    _lastEmittedMetrics =
    null;

    _lastRecommendation =
    null;

    _lastRecommendedBitrate =
    null;

    _lastRecommendedFps =
    null;

    _lastCurrentVideoBitrate =
    null;

    _lastStabilityScore =
    null;

    _lastRecommendedResolution =
    null;

    _packetLossAlertActive =
    false;

    _recoveryWasActive =
    false;

    onMetricsUpdated =
    null;

    onStabilityChanged =
    null;

    onNetworkTypeChanged =
    null;

    onBitrateRecommendationChanged =
    null;

    onQualityScoreChanged =
    null;

    onQualityChanged =
    null;

    onConnectionChanged =
    null;

    onRecommendationChanged =
    null;

    onRecoveryRequired =
    null;

    onRecoveryCompleted =
    null;

    onPacketLossHigh =
    null;

    onBitrateChanged =
    null;

    onFpsRecommendationChanged =
    null;

    onResolutionRecommendationChanged =
    null;

    onError =
    null;
  }

  // ===========================================================
  // DISPOSE
  // ===========================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    stop();

    _initializationGeneration++;

    _activeInitialization =
    null;

    _statsManager =
    null;

    _mediaManager =
    null;

    _peerConnectionManager =
    null;

    _callTimer =
    null;

    _aiMetricsConsumer =
    null;

    onMetricsUpdated =
    null;

    onStabilityChanged =
    null;

    onNetworkTypeChanged =
    null;

    onBitrateRecommendationChanged =
    null;

    onQualityScoreChanged =
    null;

    onQualityChanged =
    null;

    onConnectionChanged =
    null;

    onRecommendationChanged =
    null;

    onRecoveryRequired =
    null;

    onRecoveryCompleted =
    null;

    onPacketLossHigh =
    null;

    onBitrateChanged =
    null;

    onFpsRecommendationChanged =
    null;

    onResolutionRecommendationChanged =
    null;

    onError =
    null;

    _disposed =
    true;

    if (!_metricsController.isClosed) {
      await _metricsController.close();
    }

    _debugPrint(
      'disposed.',
    );
  }

  // ===========================================================
  // DEBUG LOGGING
  // ===========================================================

  void _debugPrint(
      String message,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[CallQualityMonitor] '
          '$message',
    );
  }
}

class _OptimizerSnapshot {
  final NetworkModel network;

  final Map<String, dynamic> profile;

  const _OptimizerSnapshot({
    required this.network,
    required this.profile,
  });
}

// ===============================================================
// END OF FILE
//
// FILE 22 INTEGRATION FIX:
//
// ✓ Direct ai_call_engine.dart import removed.
// ✓ AICallEngine symbols removed from this file.
// ✓ Circular FILE22 ↔ FILE23 type dependency removed.
// ✓ Typed CallQualityMetricsConsumer contract added.
// ✓ Existing aiCallEngine named dependency slot preserved.
// ✓ Dedicated AI registration added.
// ✓ Other dependency injection remains untouched.
// ✓ AI remains optional/downstream.
// ✓ Existing quality logic preserved.
// ✓ No UI/design changes.
//
// STATUS:
// FILE 22 — REPLACE, THEN FILE 23 BELOW.
// ===============================================================