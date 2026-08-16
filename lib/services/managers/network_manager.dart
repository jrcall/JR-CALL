import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../models/network_model.dart';
import '../../utils/network_helper.dart';

/// ===========================================================
/// JR CALL
/// File: network_manager.dart
/// Location: lib/services/managers/network_manager.dart
///
/// Production network-state orchestrator.
/// ===========================================================

class NetworkManager extends ChangeNotifier {
  NetworkManager._();

  static final NetworkManager instance = NetworkManager._();

  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Timer? _periodicTimer;

  NetworkModel _currentNetwork = NetworkModel.initial();

  bool _initialized = false;
  bool _updating = false;
  bool _pendingRefresh = false;

  Function(NetworkModel)? onNetworkChanged;

  NetworkModel get currentNetwork => _currentNetwork;

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;

    try {
      await _updateNetworkStatus();

      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        (_) {
          unawaited(refresh());
        },
        onError: (Object error) {
          debugPrint(
            'NetworkManager connectivity stream '
            'failed: $error',
          );
        },
      );

      _periodicTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(refresh());
      });

      notifyListeners();
    } catch (error) {
      _initialized = false;

      debugPrint(
        'NetworkManager initialize failed: '
        '$error',
      );

      rethrow;
    }
  }

  Future<void> refresh() async {
    if (!_initialized) {
      return;
    }

    if (_updating) {
      _pendingRefresh = true;
      return;
    }

    await _updateNetworkStatus();
  }

  Future<void> _updateNetworkStatus() async {
    if (!_initialized || _updating) {
      return;
    }

    _updating = true;

    try {
      final hasInternet = await NetworkHelper.hasInternet();

      final quality = await NetworkHelper.getNetworkQuality();

      final type = await NetworkHelper.getNetworkType();

      final ping = await NetworkHelper.getLatency();

      final packetLoss = await NetworkHelper.getPacketLoss();

      final recommendedBitrate = NetworkHelper.recommendedBitrate(quality);

      final recommendedFps = NetworkHelper.recommendedFps(quality);

      final resolution = _resolveResolution(quality);

      final next = _currentNetwork.copyWith(
        isConnected: hasInternet,
        quality: quality,
        type: type,
        ping: ping,
        packetLoss: packetLoss,
        downloadSpeed: _resolveDownloadSpeed(quality, type),
        uploadSpeed: _resolveUploadSpeed(quality, type),
        jitter: _resolveJitter(ping, packetLoss),
        signalStrength: _resolveSignalStrength(quality),
        recommendedBitrate: recommendedBitrate,
        recommendedFps: recommendedFps,
        videoWidth: resolution['width'] ?? 640,
        videoHeight: resolution['height'] ?? 360,
        updatedAt: DateTime.now(),
      );

      final changed = !_sameNetwork(_currentNetwork, next);

      _currentNetwork = next;

      if (hasInternet) {
        try {
          await NetworkHelper.adjustBitrate(quality, ping, packetLoss);
        } catch (error) {
          debugPrint(
            'NetworkManager bitrate adjustment '
            'failed: $error',
          );
        }
      }

      if (changed) {
        onNetworkChanged?.call(next);
        notifyListeners();
      }
    } catch (error) {
      debugPrint('NetworkManager refresh failed: $error');
    } finally {
      _updating = false;

      if (_pendingRefresh && _initialized) {
        _pendingRefresh = false;

        scheduleMicrotask(() => unawaited(refresh()));
      }
    }
  }

  bool _sameNetwork(NetworkModel a, NetworkModel b) {
    return a.isConnected == b.isConnected &&
        a.quality == b.quality &&
        a.type == b.type &&
        a.ping == b.ping &&
        a.packetLoss == b.packetLoss &&
        a.downloadSpeed == b.downloadSpeed &&
        a.uploadSpeed == b.uploadSpeed &&
        a.jitter == b.jitter &&
        a.signalStrength == b.signalStrength &&
        a.recommendedBitrate == b.recommendedBitrate &&
        a.recommendedFps == b.recommendedFps &&
        a.videoWidth == b.videoWidth &&
        a.videoHeight == b.videoHeight;
  }

  double _resolveDownloadSpeed(NetworkQuality quality, NetworkType type) {
    switch (quality) {
      case NetworkQuality.excellent:
        return type == NetworkType.wifi ? 25.0 : 15.0;

      case NetworkQuality.good:
        return type == NetworkType.wifi ? 10.0 : 5.0;

      case NetworkQuality.fair:
        return type == NetworkType.wifi ? 4.0 : 2.0;

      case NetworkQuality.poor:
        return 1.0;

      case NetworkQuality.offline:
        return 0.0;
    }
  }

  double _resolveUploadSpeed(NetworkQuality quality, NetworkType type) {
    switch (quality) {
      case NetworkQuality.excellent:
        return type == NetworkType.wifi ? 10.0 : 6.0;

      case NetworkQuality.good:
        return type == NetworkType.wifi ? 5.0 : 2.5;

      case NetworkQuality.fair:
        return type == NetworkType.wifi ? 2.0 : 1.0;

      case NetworkQuality.poor:
        return 0.5;

      case NetworkQuality.offline:
        return 0.0;
    }
  }

  int _resolveJitter(int ping, double packetLoss) {
    if (ping <= 0) {
      return 0;
    }

    final value = (ping * 0.12) + (packetLoss * 5);

    return value.round().clamp(1, 300).toInt();
  }

  int _resolveSignalStrength(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return 100;
      case NetworkQuality.good:
        return 75;
      case NetworkQuality.fair:
        return 50;
      case NetworkQuality.poor:
        return 25;
      case NetworkQuality.offline:
        return 0;
    }
  }

  Map<String, int> _resolveResolution(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return {'width': 1280, 'height': 720};

      case NetworkQuality.good:
        return {'width': 854, 'height': 480};

      case NetworkQuality.fair:
      case NetworkQuality.poor:
      case NetworkQuality.offline:
        return {'width': 640, 'height': 360};
    }
  }

  void reset() {
    final subscription = _connectivitySubscription;

    _connectivitySubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    _periodicTimer?.cancel();
    _periodicTimer = null;

    _initialized = false;
    _updating = false;
    _pendingRefresh = false;

    _currentNetwork = NetworkModel.initial();

    notifyListeners();
  }

  @override
  void dispose() {
    final subscription = _connectivitySubscription;

    _connectivitySubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    _periodicTimer?.cancel();

    onNetworkChanged = null;

    super.dispose();
  }
}
