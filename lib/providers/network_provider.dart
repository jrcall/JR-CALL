import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/network_model.dart';
import '../services/managers/network_manager.dart';

/// ===========================================================
/// JR CALL
/// File: network_provider.dart
/// Location: lib/providers/network_provider.dart
///
/// Description:
/// Production network-state adapter between NetworkManager
/// and the Presentation/UI layer.
///
/// Architecture ownership:
/// - NetworkManager owns network detection and monitoring.
/// - NetworkHelper owns network measurement utilities.
/// - NetworkOptimizer owns optimization decisions.
/// - ConnectionManager owns connection orchestration.
/// - NetworkProvider only exposes NetworkManager state to UI.
///
/// Rules:
/// - No duplicate network polling.
/// - No duplicate timer.
/// - No duplicate connectivity listener.
/// - No network calculations inside Provider.
/// - One NetworkManager source of truth.
/// ===========================================================

class NetworkProvider extends ChangeNotifier {
  NetworkProvider({NetworkManager? networkManager})
    : _networkManager = networkManager ?? NetworkManager.instance;

  final NetworkManager _networkManager;

  NetworkModel _network = NetworkModel.initial();

  bool _isMonitoring = false;
  bool _isDisposed = false;
  bool _listenerAttached = false;

  Future<void>? _initializationFuture;

  // ===========================================================
  // Public State
  // ===========================================================

  NetworkModel get network => _network;

  bool get isMonitoring => _isMonitoring;

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
      !_network.isConnected || _network.quality == NetworkQuality.offline;

  bool get isPoor => _network.quality == NetworkQuality.poor;

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
        StateError('NetworkProvider has already been disposed.'),
      );
    }

    return _initializationFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    try {
      if (!_networkManager.isInitialized) {
        await _networkManager.initialize();
      }

      if (_isDisposed) {
        return;
      }

      _attachManagerListener();

      _network = _networkManager.currentNetwork;
      _isMonitoring = true;

      _notifySafely();
    } catch (error, stackTrace) {
      debugPrint('JR CALL [NetworkProvider] initialization error: $error');

      debugPrintStack(
        label: 'JR CALL [NetworkProvider]',
        stackTrace: stackTrace,
      );

      _initializationFuture = null;
      rethrow;
    }
  }

  // ===========================================================
  // Monitoring
  // ===========================================================

  /// Compatibility method for existing UI/provider code.
  ///
  /// NetworkProvider does NOT create its own timer.
  /// NetworkManager remains the single monitoring owner.
  void startMonitoring({Duration interval = const Duration(seconds: 2)}) {
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

    unawaited(initialize());
  }

  /// Stops only this provider's subscription to NetworkManager.
  ///
  /// It intentionally does NOT stop NetworkManager because
  /// CallService / ConnectionManager may still depend on it.
  void stopMonitoring() {
    if (_isDisposed) {
      return;
    }

    _detachManagerListener();

    _isMonitoring = false;

    _notifySafely();
  }

  void _attachManagerListener() {
    if (_listenerAttached || _isDisposed) {
      return;
    }

    _networkManager.addListener(_handleNetworkManagerUpdate);

    _listenerAttached = true;
  }

  void _detachManagerListener() {
    if (!_listenerAttached) {
      return;
    }

    _networkManager.removeListener(_handleNetworkManagerUpdate);

    _listenerAttached = false;
  }

  // ===========================================================
  // NetworkManager Synchronization
  // ===========================================================

  void _handleNetworkManagerUpdate() {
    if (_isDisposed || !_isMonitoring) {
      return;
    }

    final nextNetwork = _networkManager.currentNetwork;

    if (_isSameNetworkState(_network, nextNetwork)) {
      return;
    }

    _network = nextNetwork;

    _notifySafely();
  }

  /// Forces Provider state to match NetworkManager immediately.
  Future<void> refresh() async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    final nextNetwork = _networkManager.currentNetwork;

    if (_isSameNetworkState(_network, nextNetwork)) {
      return;
    }

    _network = nextNetwork;

    _notifySafely();
  }

  // ===========================================================
  // Duplicate-State Protection
  // ===========================================================

  bool _isSameNetworkState(NetworkModel current, NetworkModel next) {
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
  // Reset
  // ===========================================================

  /// Resets only Provider presentation state.
  ///
  /// NetworkManager is intentionally NOT reset here because
  /// it is shared by ConnectionManager and the active call engine.
  void reset() {
    if (_isDisposed) {
      return;
    }

    _detachManagerListener();

    _network = NetworkModel.initial();
    _isMonitoring = false;
    _initializationFuture = null;

    _notifySafely();
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

    _detachManagerListener();

    _isMonitoring = false;
    _isDisposed = true;
    _initializationFuture = null;

    super.dispose();
  }
}
