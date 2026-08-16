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
/// Description:
/// Production-grade connection orchestration layer.
///
/// Responsibilities:
/// - Consume NetworkManager as the single network-state source
/// - Coordinate network loss/restoration with RecoveryManager
/// - Expose deterministic connection state to CallService/UI
/// - Expose NetworkOptimizer recommendations
/// - Prevent duplicate network polling, timers, and listeners
/// - Keep connection lifecycle separate from network measurement
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
/// Optimization:
///
/// NetworkManager
///      ↓
/// NetworkOptimizer
///      ↓
/// ConnectionManager
///
/// Important:
/// - Does NOT call NetworkHelper directly.
/// - Does NOT create a network polling timer.
/// - Does NOT reset NetworkManager.
/// - Does NOT perform ICE restart itself.
/// - Does NOT duplicate recovery logic.
/// ===========================================================

enum ConnectionStateModel { connected, reconnecting, disconnected }

class ConnectionManager {
  ConnectionManager._();

  static final ConnectionManager instance = ConnectionManager._();

  // ===========================================================
  // Dependencies
  // ===========================================================

  final NetworkManager _networkManager = NetworkManager.instance;

  final NetworkOptimizer _networkOptimizer = NetworkOptimizer.instance;

  final RecoveryManager _recoveryManager = RecoveryManager.instance;

  // ===========================================================
  // Connection Stream
  // ===========================================================

  final StreamController<ConnectionStateModel> _connectionController =
      StreamController<ConnectionStateModel>.broadcast(sync: true);

  Stream<ConnectionStateModel> get connectionStream =>
      _connectionController.stream;

  // ===========================================================
  // Runtime State
  // ===========================================================

  ConnectionStateModel _connectionState = ConnectionStateModel.disconnected;

  NetworkQuality _quality = NetworkQuality.offline;

  bool _connected = false;
  bool _monitoring = false;

  bool _networkListenerAttached = false;
  bool _recoveryListenerAttached = false;

  bool _syncRunning = false;
  bool _syncPending = false;

  bool _disposed = false;

  // ===========================================================
  // Public State
  // ===========================================================

  ConnectionStateModel get currentConnectionState => _connectionState;

  bool get isConnected => _connected;

  NetworkQuality get quality => _quality;

  bool get isMonitoring => _monitoring;

  bool get isReconnecting =>
      _connectionState == ConnectionStateModel.reconnecting;

  bool get isDisconnected =>
      _connectionState == ConnectionStateModel.disconnected;

  NetworkModel get currentNetwork => _networkManager.currentNetwork;

  // ===========================================================
  // External Callbacks
  // ===========================================================

  ValueChanged<ConnectionStateModel>? onConnectionChanged;

  ValueChanged<NetworkQuality>? onQualityChanged;

  VoidCallback? onReconnect;

  VoidCallback? onDisconnect;

  ValueChanged<Object>? onError;

  // ===========================================================
  // Start Monitoring
  // ===========================================================

  Future<void> startMonitoring() async {
    if (_disposed) {
      throw StateError('ConnectionManager has already been disposed.');
    }

    if (_monitoring) {
      await _synchronizeState();
      return;
    }

    try {
      if (!_networkManager.isInitialized) {
        await _networkManager.initialize();
      }

      if (!_networkOptimizer.isInitialized) {
        await _networkOptimizer.initialize();
      }

      _attachListeners();

      _monitoring = true;

      await _synchronizeState();

      debugPrint('ConnectionManager: monitoring started.');
    } catch (error, stackTrace) {
      _monitoring = false;

      _reportError(error, stackTrace, source: 'startMonitoring');

      rethrow;
    }
  }

  // ===========================================================
  // Listener Ownership
  // ===========================================================

  void _attachListeners() {
    if (!_networkListenerAttached) {
      _networkManager.addListener(_handleNetworkManagerChanged);

      _networkListenerAttached = true;
    }

    if (!_recoveryListenerAttached) {
      _recoveryManager.addListener(_handleRecoveryManagerChanged);

      _recoveryListenerAttached = true;
    }
  }

  void _detachListeners() {
    if (_networkListenerAttached) {
      _networkManager.removeListener(_handleNetworkManagerChanged);

      _networkListenerAttached = false;
    }

    if (_recoveryListenerAttached) {
      _recoveryManager.removeListener(_handleRecoveryManagerChanged);

      _recoveryListenerAttached = false;
    }
  }

  void _handleNetworkManagerChanged() {
    if (!_monitoring || _disposed) {
      return;
    }

    unawaited(_synchronizeState());
  }

  void _handleRecoveryManagerChanged() {
    if (!_monitoring || _disposed) {
      return;
    }

    unawaited(_synchronizeState());
  }

  // ===========================================================
  // Explicit Refresh
  // ===========================================================

  Future<void> refresh() async {
    if (_disposed) {
      return;
    }

    if (!_monitoring) {
      await startMonitoring();
      return;
    }

    try {
      await _networkManager.refresh();
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, source: 'refresh');
    }

    await _synchronizeState();
  }

  // ===========================================================
  // State Synchronization
  // ===========================================================

  Future<void> _synchronizeState() async {
    if (_disposed || !_monitoring) {
      return;
    }

    if (_syncRunning) {
      _syncPending = true;
      return;
    }

    _syncRunning = true;

    try {
      do {
        _syncPending = false;

        final network = _networkManager.currentNetwork;

        final previousState = _connectionState;

        final previousConnected = _connected;

        final previousQuality = _quality;

        final networkAvailable =
            network.isConnected && network.quality != NetworkQuality.offline;

        _connected = networkAvailable;
        _quality = network.quality;

        final nextState = _resolveConnectionState(
          networkAvailable: networkAvailable,
        );

        // =====================================================
        // Network Loss
        // =====================================================

        if (previousConnected && !networkAvailable) {
          try {
            _recoveryManager.handleRecoveryRequired();
          } catch (error, stackTrace) {
            _reportError(
              error,
              stackTrace,
              source: 'network-loss recovery request',
            );
          }

          _safeCallback(onDisconnect);
        }

        // =====================================================
        // Network Restoration
        // =====================================================

        if (!previousConnected && networkAvailable) {
          try {
            _recoveryManager.handleNetworkRestored();
          } catch (error, stackTrace) {
            _reportError(
              error,
              stackTrace,
              source: 'network-restored recovery request',
            );
          }
        }

        // =====================================================
        // Quality Change
        // =====================================================

        if (previousQuality != _quality) {
          _safeValueCallback(onQualityChanged, _quality);
        }

        // =====================================================
        // Connection State Change
        // =====================================================

        if (previousState != nextState) {
          _connectionState = nextState;

          if (!_connectionController.isClosed) {
            _connectionController.add(nextState);
          }

          _safeValueCallback(onConnectionChanged, nextState);

          if ((previousState == ConnectionStateModel.disconnected ||
                  previousState == ConnectionStateModel.reconnecting) &&
              nextState == ConnectionStateModel.connected) {
            _safeCallback(onReconnect);
          }
        }
      } while (_syncPending && !_disposed && _monitoring);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, source: 'state synchronization');
    } finally {
      _syncRunning = false;
    }
  }

  ConnectionStateModel _resolveConnectionState({
    required bool networkAvailable,
  }) {
    if (!networkAvailable) {
      return ConnectionStateModel.disconnected;
    }

    if (_recoveryManager.isRecovering || _recoveryManager.recoveryRequested) {
      return ConnectionStateModel.reconnecting;
    }

    return ConnectionStateModel.connected;
  }

  // ===========================================================
  // Network Read APIs
  // ===========================================================

  Future<NetworkQuality> currentQuality() async {
    return _networkManager.currentNetwork.quality;
  }

  Future<NetworkType> currentNetworkType() async {
    return _networkManager.currentNetwork.type;
  }

  Future<int> recommendedBitrate() async {
    return _networkOptimizer.videoBitrate;
  }

  Future<int> currentAudioBitrate() async {
    return _networkOptimizer.audioBitrate;
  }

  Future<int> recommendedFps() async {
    return _networkOptimizer.fps;
  }

  Future<Map<String, int>> currentResolution() async {
    return _networkOptimizer.resolutionProfile;
  }

  Future<int> currentOptimizationLevel() async {
    return _networkOptimizer.optimizationLevel;
  }

  Future<bool> shouldUseAdaptiveBitrate() async {
    return _networkOptimizer.enableAdaptiveBitrate;
  }

  Future<bool> shouldUseAdaptiveResolution() async {
    return _networkOptimizer.enableAdaptiveResolution;
  }

  Future<bool> shouldUseAdaptiveFps() async {
    return _networkOptimizer.enableAdaptiveFps;
  }

  Future<bool> shouldUseDataSaver() async {
    return _networkOptimizer.enableDataSaver;
  }

  Future<Map<String, dynamic>> recommendedMediaProfile() async {
    return _networkOptimizer.recommendedProfile;
  }

  // ===========================================================
  // Stop Monitoring
  // ===========================================================

  void stopMonitoring() {
    if (!_monitoring) {
      return;
    }

    _monitoring = false;

    _detachListeners();

    _syncRunning = false;
    _syncPending = false;

    debugPrint('ConnectionManager: monitoring stopped.');
  }

  // ===========================================================
  // Reset
  // ===========================================================

  void reset() {
    if (_disposed) {
      return;
    }

    stopMonitoring();

    _connected = false;

    _quality = NetworkQuality.offline;

    _connectionState = ConnectionStateModel.disconnected;

    _syncRunning = false;
    _syncPending = false;

    onConnectionChanged = null;
    onQualityChanged = null;
    onReconnect = null;
    onDisconnect = null;
    onError = null;

    /// IMPORTANT:
    /// NetworkManager and RecoveryManager are NOT reset here.
    ///
    /// They own their own lifecycle and must only be reset by
    /// their respective lifecycle owner / CallService.

    debugPrint('ConnectionManager: reset complete.');
  }

  // ===========================================================
  // Safe Callback Helpers
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
      'ConnectionManager [$source] error: '
      '$error',
    );

    debugPrintStack(
      label: 'ConnectionManager [$source]',
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
  // Dispose
  // ===========================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    stopMonitoring();

    _connected = false;
    _quality = NetworkQuality.offline;

    _connectionState = ConnectionStateModel.disconnected;

    onConnectionChanged = null;
    onQualityChanged = null;
    onReconnect = null;
    onDisconnect = null;
    onError = null;

    _disposed = true;

    if (!_connectionController.isClosed) {
      await _connectionController.close();
    }

    debugPrint('ConnectionManager: disposed.');
  }
}
