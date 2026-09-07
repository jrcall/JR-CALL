import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/network_model.dart';
import '../services/managers/network_manager.dart';

/// ===========================================================
/// JR CALL
/// File: network_provider.dart
/// Location: lib/providers/network_provider.dart
///
/// Production network state bridge between NetworkManager
/// and the Presentation/UI layer.
///
/// Ownership:
/// - NetworkManager owns network detection and monitoring.
/// - NetworkHelper owns network measurement utilities.
/// - NetworkOptimizer owns optimization decisions.
/// - ConnectionManager owns connection orchestration.
/// - NetworkProvider exposes NetworkManager state to UI.
///
/// Rules:
/// - No duplicate network polling.
/// - No duplicate timer.
/// - No duplicate connectivity listener.
/// - No network measurement logic inside this provider.
/// - No connection or recovery ownership.
/// - NetworkManager remains the shared network owner.
/// ===========================================================

class NetworkProvider extends ChangeNotifier {
  NetworkProvider({
    NetworkManager? networkManager,
  }) : _networkManager = networkManager ?? NetworkManager.instance;

  // ===========================================================
  // Dependency
  // ===========================================================

  final NetworkManager _networkManager;

  // ===========================================================
  // Presentation State
  // ===========================================================

  NetworkModel _network = NetworkModel.initial();

  bool _isMonitoring = false;
  bool _isDisposed = false;
  bool _listenerAttached = false;

  // ===========================================================
  // Initialization State
  // ===========================================================

  Future<void>? _initializationFuture;

  int _initializationSerial = 0;
  int _lifecycleGeneration = 0;

  // ===========================================================
  // Public State
  // ===========================================================

  NetworkModel get network => _network;

  bool get isMonitoring => _isMonitoring;

  bool get isDisposed => _isDisposed;

  bool get isConnected => _network.isConnected;

  NetworkQuality get quality => _network.quality;

  NetworkType get networkType => _network.type;

  int get ping => _network.ping;

  int get jitter => _network.jitter;

  double get packetLoss => _network.packetLoss;

  double get downloadSpeed => _network.downloadSpeed;

  double get uploadSpeed => _network.uploadSpeed;

  int get signalStrength => _network.signalStrength;

  int get bitrate => _network.recommendedBitrate;

  int get fps => _network.recommendedFps;

  int get videoWidth => _network.videoWidth;

  int get videoHeight => _network.videoHeight;

  DateTime get updatedAt => _network.updatedAt;

  bool get isOffline =>
      !_network.isConnected ||
          _network.quality == NetworkQuality.offline;

  bool get isPoor =>
      _network.quality == NetworkQuality.poor;

  bool get isStable =>
      _network.isConnected &&
          (_network.quality == NetworkQuality.excellent ||
              _network.quality == NetworkQuality.good);

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize() {
    if (_isDisposed) {
      return Future<void>.error(
        StateError(
          'NetworkProvider has already been disposed.',
        ),
      );
    }

    if (_isMonitoring && _listenerAttached) {
      _synchronizeFromManager();
      return Future<void>.value();
    }

    final Future<void>? existing = _initializationFuture;

    if (existing != null) {
      return existing;
    }

    final int lifecycleToken = _lifecycleGeneration;
    final int initializationToken = ++_initializationSerial;

    final Future<void> future = _initializeInternal(
      lifecycleToken: lifecycleToken,
      initializationToken: initializationToken,
    );

    _initializationFuture = future;

    return future;
  }

  Future<void> _initializeInternal({
    required int lifecycleToken,
    required int initializationToken,
  }) async {
    try {
      if (!_networkManager.isInitialized) {
        await _networkManager.initialize();
      }

      if (!_isLifecycleCurrent(lifecycleToken)) {
        return;
      }

      _attachManagerListener();

      if (!_isLifecycleCurrent(lifecycleToken)) {
        _detachManagerListener();
        return;
      }

      final NetworkModel nextNetwork = _networkManager.currentNetwork;

      final bool networkChanged = !_isSameNetworkState(
        _network,
        nextNetwork,
      );

      final bool monitoringChanged = !_isMonitoring;

      _network = nextNetwork;
      _isMonitoring = true;

      if (networkChanged || monitoringChanged) {
        _notifySafely();
      }
    } catch (error, stackTrace) {
      if (_isLifecycleCurrent(lifecycleToken)) {
        _detachManagerListener();

        _isMonitoring = false;

        _reportError(
          'Initialization',
          error,
          stackTrace,
        );
      }

      rethrow;
    } finally {
      if (initializationToken == _initializationSerial) {
        _initializationFuture = null;
      }
    }
  }

  // ===========================================================
  // Monitoring
  // ===========================================================

  /// Compatibility API.
  ///
  /// The interval is validated only.
  /// NetworkManager remains responsible for its own monitoring
  /// frequency and this provider never creates a timer.
  void startMonitoring({
    Duration interval = const Duration(seconds: 2),
  }) {
    if (_isDisposed || _isMonitoring) {
      return;
    }

    if (interval <= Duration.zero) {
      throw ArgumentError.value(
        interval,
        'interval',
        'Monitoring interval must be greater than zero.',
      );
    }

    unawaited(
      _startMonitoringSafely(),
    );
  }

  Future<void> _startMonitoringSafely() async {
    try {
      await initialize();
    } catch (_) {
      // initialize() already reports the error.
    }
  }

  /// Stops only this provider's observation of NetworkManager.
  ///
  /// NetworkManager itself remains active because other call
  /// engine components may still depend on it.
  void stopMonitoring() {
    if (_isDisposed) {
      return;
    }

    final bool stateChanged =
        _isMonitoring || _listenerAttached;

    _invalidatePendingInitialization();

    _detachManagerListener();

    _isMonitoring = false;

    if (stateChanged) {
      _notifySafely();
    }
  }

  // ===========================================================
  // Manager Listener
  // ===========================================================

  void _attachManagerListener() {
    if (_listenerAttached || _isDisposed) {
      return;
    }

    _networkManager.addListener(
      _handleNetworkManagerUpdate,
    );

    _listenerAttached = true;
  }

  void _detachManagerListener() {
    if (!_listenerAttached) {
      return;
    }

    _networkManager.removeListener(
      _handleNetworkManagerUpdate,
    );

    _listenerAttached = false;
  }

  // ===========================================================
  // NetworkManager Synchronization
  // ===========================================================

  void _handleNetworkManagerUpdate() {
    if (_isDisposed || !_isMonitoring) {
      return;
    }

    _synchronizeFromManager();
  }

  void _synchronizeFromManager() {
    if (_isDisposed) {
      return;
    }

    final NetworkModel nextNetwork =
        _networkManager.currentNetwork;

    final bool changed = !_isSameNetworkState(
      _network,
      nextNetwork,
    );

    // Always keep the latest manager snapshot internally.
    // This also keeps updatedAt current without forcing a rebuild
    // when every visible network metric is unchanged.
    _network = nextNetwork;

    if (changed) {
      _notifySafely();
    }
  }

  // ===========================================================
  // Refresh
  // ===========================================================

  Future<void> refresh() async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed || !_isMonitoring) {
      return;
    }

    _synchronizeFromManager();
  }

  // ===========================================================
  // Duplicate State Protection
  // ===========================================================

  bool _isSameNetworkState(
      NetworkModel current,
      NetworkModel next,
      ) {
    return current.isConnected == next.isConnected &&
        current.quality == next.quality &&
        current.type == next.type &&
        current.ping == next.ping &&
        current.jitter == next.jitter &&
        current.packetLoss == next.packetLoss &&
        current.downloadSpeed == next.downloadSpeed &&
        current.uploadSpeed == next.uploadSpeed &&
        current.signalStrength == next.signalStrength &&
        current.recommendedBitrate == next.recommendedBitrate &&
        current.recommendedFps == next.recommendedFps &&
        current.videoWidth == next.videoWidth &&
        current.videoHeight == next.videoHeight;
  }

  // ===========================================================
  // Initialization Protection
  // ===========================================================

  bool _isLifecycleCurrent(
      int token,
      ) {
    return !_isDisposed &&
        token == _lifecycleGeneration;
  }

  void _invalidatePendingInitialization() {
    _lifecycleGeneration++;

    _initializationSerial++;

    _initializationFuture = null;
  }

  // ===========================================================
  // Reset
  // ===========================================================

  /// Resets presentation state only.
  ///
  /// NetworkManager is shared by the call engine and is therefore
  /// intentionally not reset or disposed here.
  void reset() {
    if (_isDisposed) {
      return;
    }

    final NetworkModel initialNetwork =
    NetworkModel.initial();

    final bool stateChanged =
        _isMonitoring ||
            _listenerAttached ||
            !_isSameNetworkState(
              _network,
              initialNetwork,
            );

    _invalidatePendingInitialization();

    _detachManagerListener();

    _network = initialNetwork;
    _isMonitoring = false;

    if (stateChanged) {
      _notifySafely();
    }
  }

  // ===========================================================
  // Error Reporting
  // ===========================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [NetworkProvider/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [NetworkProvider/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // Safe Notification
  // ===========================================================

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }

    notifyListeners();
  }

  // ===========================================================
  // Dispose
  // ===========================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _invalidatePendingInitialization();

    _detachManagerListener();

    _isMonitoring = false;
    _isDisposed = true;

    // NetworkManager is shared.
    // Never stop, reset, or dispose it from this provider.

    super.dispose();
  }
}