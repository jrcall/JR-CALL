import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/network_model.dart';
import '../managers/network_manager.dart';
import '../managers/recovery_manager.dart';
import 'network_optimizer.dart';

/// ===========================================================
/// JR CALL
/// File: connection_manager.dart
/// Location: lib/services/call/connection_manager.dart
///
/// FINAL PRODUCTION CONNECTION ORCHESTRATION LAYER.
///
/// Responsibilities:
/// - Consume NetworkManager as the single network-state source.
/// - Coordinate network loss/restoration with RecoveryManager.
/// - Expose deterministic connection state to CallService/UI.
/// - Expose NetworkOptimizer recommendations.
/// - Prevent duplicate listeners/start operations.
/// - Keep network measurement separate from orchestration.
///
/// Architecture:
///
/// NetworkManager
///      ↓
/// ConnectionManager
///      ↓
/// RecoveryManager
///      ↓
/// CallService / Providers / UI
///
/// IMPORTANT:
///
/// - NetworkModel.isConnected is the canonical transport
///   availability flag.
/// - NetworkQuality is advisory only.
/// - Does NOT call NetworkHelper directly.
/// - Does NOT create another network polling timer.
/// - Does NOT reset NetworkManager.
/// - Does NOT reset RecoveryManager.
/// - Does NOT perform ICE restart.
/// - Does NOT mutate WebRTC bitrate.
/// - Does NOT own signaling/media/call lifecycle.
/// ===========================================================

enum ConnectionStateModel {
  connected,
  reconnecting,
  disconnected,
}

class ConnectionManager {
  ConnectionManager._();

  static final ConnectionManager instance =
  ConnectionManager._();

  // ===========================================================
  // DEPENDENCIES
  // ===========================================================

  final NetworkManager _networkManager =
      NetworkManager.instance;

  final NetworkOptimizer _networkOptimizer =
      NetworkOptimizer.instance;

  final RecoveryManager _recoveryManager =
      RecoveryManager.instance;

  // ===========================================================
  // CONNECTION STREAM
  // ===========================================================

  final StreamController<ConnectionStateModel>
  _connectionController =
  StreamController<ConnectionStateModel>.broadcast(
    sync: true,
  );

  Stream<ConnectionStateModel> get connectionStream =>
      _connectionController.stream;

  // ===========================================================
  // RUNTIME STATE
  // ===========================================================

  ConnectionStateModel _connectionState =
      ConnectionStateModel.disconnected;

  NetworkQuality _quality =
      NetworkQuality.offline;

  bool _connected = false;

  bool _monitoring = false;

  bool _networkListenerAttached = false;

  bool _recoveryListenerAttached = false;

  bool _syncRunning = false;

  bool _syncPending = false;

  bool _hasSynchronizedState = false;

  bool _disposed = false;

  // ===========================================================
  // LIFECYCLE GENERATION
  // ===========================================================

  int _generation = 0;

  int? _syncGeneration;

  Future<void>? _activeStart;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  ConnectionStateModel get currentConnectionState =>
      _connectionState;

  bool get isConnected =>
      _connected;

  NetworkQuality get quality =>
      _quality;

  bool get isMonitoring =>
      _monitoring;

  bool get isReconnecting =>
      _connectionState ==
          ConnectionStateModel.reconnecting;

  bool get isDisconnected =>
      _connectionState ==
          ConnectionStateModel.disconnected;

  NetworkModel get currentNetwork =>
      _networkManager.currentNetwork;

  // ===========================================================
  // EXTERNAL CALLBACKS
  // ===========================================================

  ValueChanged<ConnectionStateModel>?
  onConnectionChanged;

  ValueChanged<NetworkQuality>?
  onQualityChanged;

  VoidCallback? onReconnect;

  VoidCallback? onDisconnect;

  ValueChanged<Object>? onError;

  // ===========================================================
  // START MONITORING
  // ===========================================================

  Future<void> startMonitoring() async {
    if (_disposed) {
      throw StateError(
        'ConnectionManager has already been disposed.',
      );
    }

    if (_monitoring) {
      await _synchronizeState(
        expectedGeneration: _generation,
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
    ++_generation;

    final Future<void> operation =
    _startMonitoringInternal(
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

    _activeStart = tracked;

    await tracked;
  }

  Future<void> _startMonitoringInternal(
      int generation,
      ) async {
    try {
      if (!_networkManager.isInitialized) {
        await _networkManager.initialize();
      }

      if (!_isGenerationCurrent(
        generation,
      )) {
        return;
      }

      if (!_networkOptimizer.isInitialized) {
        await _networkOptimizer.initialize();
      }

      if (!_isGenerationCurrent(
        generation,
      )) {
        return;
      }

      _attachListeners();

      if (!_isGenerationCurrent(
        generation,
      )) {
        _detachListeners();

        return;
      }

      _monitoring = true;

      _syncPending = false;

      _hasSynchronizedState = false;

      await _synchronizeState(
        expectedGeneration: generation,
      );

      if (!_isMonitoringGeneration(
        generation,
      )) {
        return;
      }

      _debugPrint(
        'monitoring started '
            '(connected=$_connected, '
            'quality=$_quality).',
      );
    } catch (error, stackTrace) {
      if (!_isGenerationCurrent(
        generation,
      )) {
        return;
      }

      _monitoring = false;

      _syncPending = false;

      _hasSynchronizedState = false;

      _detachListeners();

      _reportError(
        error,
        stackTrace,
        source: 'startMonitoring',
      );

      rethrow;
    }
  }

  // ===========================================================
  // LISTENER OWNERSHIP
  // ===========================================================

  void _attachListeners() {
    if (!_networkListenerAttached) {
      _networkManager.addListener(
        _handleNetworkManagerChanged,
      );

      _networkListenerAttached = true;
    }

    if (!_recoveryListenerAttached) {
      _recoveryManager.addListener(
        _handleRecoveryManagerChanged,
      );

      _recoveryListenerAttached = true;
    }
  }

  void _detachListeners() {
    if (_networkListenerAttached) {
      _networkManager.removeListener(
        _handleNetworkManagerChanged,
      );

      _networkListenerAttached = false;
    }

    if (_recoveryListenerAttached) {
      _recoveryManager.removeListener(
        _handleRecoveryManagerChanged,
      );

      _recoveryListenerAttached = false;
    }
  }

  void _handleNetworkManagerChanged() {
    if (_disposed ||
        !_monitoring) {
      return;
    }

    unawaited(
      _synchronizeState(
        expectedGeneration: _generation,
      ),
    );
  }

  void _handleRecoveryManagerChanged() {
    if (_disposed ||
        !_monitoring) {
      return;
    }

    unawaited(
      _synchronizeState(
        expectedGeneration: _generation,
      ),
    );
  }

  // ===========================================================
  // EXPLICIT REFRESH
  // ===========================================================

  Future<void> refresh() async {
    if (_disposed) {
      return;
    }

    if (!_monitoring) {
      await startMonitoring();

      return;
    }

    final int generation =
        _generation;

    try {
      await _networkManager.refresh();
    } catch (error, stackTrace) {
      if (_isMonitoringGeneration(
        generation,
      )) {
        _reportError(
          error,
          stackTrace,
          source: 'refresh',
        );
      }
    }

    if (!_isMonitoringGeneration(
      generation,
    )) {
      return;
    }

    await _synchronizeState(
      expectedGeneration: generation,
    );
  }

  // ===========================================================
  // STATE SYNCHRONIZATION
  // ===========================================================

  Future<void> _synchronizeState({
    required int expectedGeneration,
  }) {
    if (!_isMonitoringGeneration(
      expectedGeneration,
    )) {
      return Future<void>.value();
    }

    if (_syncRunning) {
      if (_syncGeneration ==
          expectedGeneration) {
        _syncPending = true;
      } else {
        scheduleMicrotask(() {
          if (_isMonitoringGeneration(
            expectedGeneration,
          )) {
            unawaited(
              _synchronizeState(
                expectedGeneration:
                expectedGeneration,
              ),
            );
          }
        });
      }

      return Future<void>.value();
    }

    _syncRunning = true;

    _syncGeneration =
        expectedGeneration;

    try {
      do {
        _syncPending = false;

        if (!_isMonitoringGeneration(
          expectedGeneration,
        )) {
          break;
        }

        final NetworkModel network =
            _networkManager.currentNetwork;

        final ConnectionStateModel
        previousState =
            _connectionState;

        final bool previousConnected =
            _connected;

        final NetworkQuality
        previousQuality =
            _quality;

        final bool hadPreviousSnapshot =
            _hasSynchronizedState;

        // =====================================================
        // NETWORK AVAILABILITY
        // =====================================================

        final bool networkAvailable =
            network.isConnected;

        _connected =
            networkAvailable;

        _quality =
            network.quality;

        // =====================================================
        // NETWORK LOSS
        // =====================================================

        final bool networkLost =
            hadPreviousSnapshot &&
                previousConnected &&
                !networkAvailable;

        if (networkLost) {
          try {
            _recoveryManager
                .handleRecoveryRequired();
          } catch (error, stackTrace) {
            _reportError(
              error,
              stackTrace,
              source:
              'network-loss recovery request',
            );
          }

          if (!_isMonitoringGeneration(
            expectedGeneration,
          )) {
            break;
          }
        }

        // =====================================================
        // NETWORK RESTORATION
        // =====================================================

        final bool networkRestored =
            hadPreviousSnapshot &&
                !previousConnected &&
                networkAvailable;

        if (networkRestored) {
          try {
            _recoveryManager
                .handleNetworkRestored();
          } catch (error, stackTrace) {
            _reportError(
              error,
              stackTrace,
              source:
              'network-restored recovery request',
            );
          }

          if (!_isMonitoringGeneration(
            expectedGeneration,
          )) {
            break;
          }
        }

        // =====================================================
        // FINAL STATE AFTER RECOVERY SIDE EFFECTS
        // =====================================================

        final ConnectionStateModel nextState =
        _resolveConnectionState(
          networkAvailable:
          networkAvailable,
        );

        // =====================================================
        // QUALITY CHANGE
        // =====================================================

        if (previousQuality !=
            _quality) {
          _safeValueCallback(
            onQualityChanged,
            _quality,
          );

          if (!_isMonitoringGeneration(
            expectedGeneration,
          )) {
            break;
          }
        }

        // =====================================================
        // CONNECTION STATE CHANGE
        // =====================================================

        final bool stateChanged =
            previousState !=
                nextState;

        if (stateChanged) {
          _connectionState =
              nextState;

          if (!_connectionController
              .isClosed) {
            _connectionController.add(
              nextState,
            );
          }

          _safeValueCallback(
            onConnectionChanged,
            nextState,
          );

          if (!_isMonitoringGeneration(
            expectedGeneration,
          )) {
            break;
          }
        }

        _hasSynchronizedState =
        true;

        // =====================================================
        // DISCONNECT CALLBACK
        // =====================================================

        if (networkLost) {
          _safeCallback(
            onDisconnect,
          );

          if (!_isMonitoringGeneration(
            expectedGeneration,
          )) {
            break;
          }
        }

        // =====================================================
        // RECONNECT CALLBACK
        // =====================================================

        final bool genuinelyReconnected =
            hadPreviousSnapshot &&
                stateChanged &&
                (previousState ==
                    ConnectionStateModel
                        .disconnected ||
                    previousState ==
                        ConnectionStateModel
                            .reconnecting) &&
                nextState ==
                    ConnectionStateModel
                        .connected;

        if (genuinelyReconnected) {
          _safeCallback(
            onReconnect,
          );

          if (!_isMonitoringGeneration(
            expectedGeneration,
          )) {
            break;
          }
        }
      } while (
      _syncPending &&
          _isMonitoringGeneration(
            expectedGeneration,
          ));
    } catch (error, stackTrace) {
      if (_isMonitoringGeneration(
        expectedGeneration,
      )) {
        _reportError(
          error,
          stackTrace,
          source:
          'state synchronization',
        );
      }
    } finally {
      if (_syncGeneration ==
          expectedGeneration) {
        _syncRunning = false;

        _syncGeneration = null;
      }
    }

    return Future<void>.value();
  }

  // ===========================================================
  // STATE RESOLVER
  // ===========================================================

  ConnectionStateModel _resolveConnectionState({
    required bool networkAvailable,
  }) {
    if (!networkAvailable) {
      return ConnectionStateModel
          .disconnected;
    }

    if (_recoveryManager.isRecovering ||
        _recoveryManager
            .recoveryRequested) {
      return ConnectionStateModel
          .reconnecting;
    }

    return ConnectionStateModel.connected;
  }

  // ===========================================================
  // NETWORK READ APIs
  // ===========================================================

  Future<NetworkQuality> currentQuality() {
    return Future<NetworkQuality>.value(
      _networkManager
          .currentNetwork
          .quality,
    );
  }

  Future<NetworkType> currentNetworkType() {
    return Future<NetworkType>.value(
      _networkManager
          .currentNetwork
          .type,
    );
  }

  Future<int> recommendedBitrate() {
    return Future<int>.value(
      _networkOptimizer.videoBitrate,
    );
  }

  Future<int> currentAudioBitrate() {
    return Future<int>.value(
      _networkOptimizer.audioBitrate,
    );
  }

  Future<int> recommendedFps() {
    return Future<int>.value(
      _networkOptimizer.fps,
    );
  }

  Future<Map<String, int>>
  currentResolution() async {
    final Map<String, int> resolution =
    await _networkOptimizer
        .resolutionProfile;

    return Map<String, int>.unmodifiable(
      resolution,
    );
  }

  Future<int> currentOptimizationLevel() {
    return Future<int>.value(
      _networkOptimizer
          .optimizationLevel,
    );
  }

  Future<bool> shouldUseAdaptiveBitrate() {
    return Future<bool>.value(
      _networkOptimizer
          .enableAdaptiveBitrate,
    );
  }

  Future<bool>
  shouldUseAdaptiveResolution() {
    return Future<bool>.value(
      _networkOptimizer
          .enableAdaptiveResolution,
    );
  }

  Future<bool> shouldUseAdaptiveFps() {
    return Future<bool>.value(
      _networkOptimizer
          .enableAdaptiveFps,
    );
  }

  Future<bool> shouldUseDataSaver() {
    return Future<bool>.value(
      _networkOptimizer
          .enableDataSaver,
    );
  }

  Future<Map<String, dynamic>>
  recommendedMediaProfile() async {
    final Map<String, dynamic> profile =
    await _networkOptimizer
        .recommendedProfile;

    return Map<String, dynamic>.unmodifiable(
      profile,
    );
  }

  // ===========================================================
  // STOP MONITORING
  // ===========================================================

  void stopMonitoring() {
    if (_disposed) {
      return;
    }

    final bool hadActivity =
        _monitoring ||
            _activeStart != null ||
            _networkListenerAttached ||
            _recoveryListenerAttached;

    _generation++;

    _monitoring = false;

    _activeStart = null;

    _syncPending = false;

    _hasSynchronizedState = false;

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

    stopMonitoring();

    _connected = false;

    _quality =
        NetworkQuality.offline;

    _connectionState =
        ConnectionStateModel.disconnected;

    _syncPending = false;

    _hasSynchronizedState = false;

    onConnectionChanged = null;

    onQualityChanged = null;

    onReconnect = null;

    onDisconnect = null;

    onError = null;

    _debugPrint(
      'reset complete.',
    );
  }

  // ===========================================================
  // LIFECYCLE VALIDATION
  // ===========================================================

  bool _isGenerationCurrent(
      int generation,
      ) {
    return !_disposed &&
        generation ==
            _generation;
  }

  bool _isMonitoringGeneration(
      int generation,
      ) {
    return !_disposed &&
        _monitoring &&
        generation ==
            _generation;
  }

  // ===========================================================
  // SAFE CALLBACK HELPERS
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
      callback(
        value,
      );
    } catch (error, stackTrace) {
      _reportError(
        error,
        stackTrace,
        source: 'value callback',
      );
    }
  }

  // ===========================================================
  // LOGGING / ERROR REPORTING
  // ===========================================================

  void _debugPrint(
      String message,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[ConnectionManager] '
          '$message',
    );
  }

  void _reportError(
      Object error,
      StackTrace stackTrace, {
        required String source,
      }) {
    if (kDebugMode) {
      debugPrint(
        'JR CALL '
            '[ConnectionManager/$source] '
            'error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL '
            '[ConnectionManager/$source]',
        stackTrace:
        stackTrace,
      );
    }

    final ValueChanged<Object>? callback =
        onError;

    if (_disposed ||
        callback == null) {
      return;
    }

    try {
      callback(
        error,
      );
    } catch (_) {}
  }

  // ===========================================================
  // DISPOSE
  // ===========================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _generation++;

    _monitoring = false;

    _activeStart = null;

    _syncPending = false;

    _hasSynchronizedState = false;

    _detachListeners();

    _connected = false;

    _quality =
        NetworkQuality.offline;

    _connectionState =
        ConnectionStateModel.disconnected;

    onConnectionChanged = null;

    onQualityChanged = null;

    onReconnect = null;

    onDisconnect = null;

    onError = null;

    _disposed = true;

    if (!_connectionController.isClosed) {
      await _connectionController.close();
    }

    _debugPrint(
      'disposed.',
    );
  }
}

// ===========================================================
// END OF FILE
//
// FILE 18 CORRECTED FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ NetworkOptimizer async resolutionProfile handled correctly.
// ✓ NetworkOptimizer async recommendedProfile handled correctly.
// ✓ No Future<Map> passed into Map.unmodifiable.
// ✓ Previous orchestration logic preserved.
// ✓ NetworkManager remains sole network-state source.
// ✓ NetworkQuality remains advisory only.
// ✓ RecoveryManager remains recovery owner.
// ✓ NetworkOptimizer remains recommendation owner.
// ✓ No duplicate network polling/timer added.
// ✓ startMonitoring concurrency deduplicated.
// ✓ Reset/stop/dispose invalidate stale lifecycle work.
// ✓ Listener ownership remains idempotent.
// ✓ State synchronization remains generation guarded.
// ✓ Initial start never falsely fires onReconnect.
// ✓ Real reconnect semantics preserved.
// ✓ No PeerConnection ownership.
// ✓ No ICE restart ownership.
// ✓ No signaling/media ownership.
// ✓ No UI/design changes.
//
// STATUS:
// CONNECTION MANAGER — CORRECTED FINAL.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 19
// lib/services/call/network_optimizer.dart
// ===========================================================