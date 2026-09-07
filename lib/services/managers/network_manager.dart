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
/// FINAL PRODUCTION NETWORK-STATE ORCHESTRATOR
///
/// OWNERSHIP:
///
/// NetworkManager:
/// - Network transport observation.
/// - Advisory quality measurement.
/// - Advisory latency measurement.
/// - Advisory packet-loss measurement.
/// - NetworkModel recommendation state.
/// - Connectivity-change observation.
/// - Periodic refresh.
/// - onNetworkChanged notification.
///
/// RecoveryManager:
/// - Network recovery orchestration.
///
/// NetworkOptimizer:
/// - Network optimization policy.
///
/// BitrateController:
/// - Actual WebRTC bitrate mutation.
///
/// IMPORTANT:
///
/// Connectivity transport availability is NOT proof of Internet
/// access.
///
/// Wi-Fi/mobile/VPN/etc. keeps the Call Engine eligible to attempt
/// real Firebase/TURN/WebRTC operations.
///
/// Service-specific failures remain authoritative at their own
/// network boundaries.
/// ===========================================================

class NetworkManager extends ChangeNotifier {
  NetworkManager._();

  static final NetworkManager instance =
  NetworkManager._();

  // ===========================================================
  // CONNECTIVITY
  // ===========================================================

  final Connectivity _connectivity =
  Connectivity();

  StreamSubscription<List<ConnectivityResult>>?
  _connectivitySubscription;

  Timer? _periodicTimer;

  Timer? _connectivityDebounceTimer;

  // ===========================================================
  // NETWORK STATE
  // ===========================================================

  NetworkModel _currentNetwork =
  NetworkModel.initial();

  bool _initialized = false;

  bool _disposed = false;

  // ===========================================================
  // LIFECYCLE GENERATION
  // ===========================================================

  int _lifecycleGeneration = 0;

  Future<void>? _activeInitialization;

  // ===========================================================
  // UPDATE SERIALIZATION
  // ===========================================================

  int? _activeUpdateGeneration;

  bool _pendingRefresh = false;

  // ===========================================================
  // CONFIGURATION
  // ===========================================================

  static const Duration _periodicRefreshInterval =
  Duration(seconds: 5);

  static const Duration _connectivityDebounceDuration =
  Duration(milliseconds: 300);

  // ===========================================================
  // PUBLIC COMPATIBILITY CALLBACK
  // ===========================================================

  Function(NetworkModel)? onNetworkChanged;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  NetworkModel get currentNetwork =>
      _currentNetwork;

  bool get isInitialized =>
      _initialized;

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() async {
    if (_disposed) {
      return;
    }

    if (_initialized &&
        _connectivitySubscription != null) {
      return;
    }

    final Future<void>? active =
        _activeInitialization;

    if (active != null) {
      await active;

      return;
    }

    final int generation =
    ++_lifecycleGeneration;

    _initialized = true;

    final Future<void> operation =
    _initializeInternal(
      generation,
    );

    _activeInitialization =
        operation;

    try {
      await operation;
    } finally {
      if (identical(
        _activeInitialization,
        operation,
      )) {
        _activeInitialization = null;
      }
    }
  }

  Future<void> _initializeInternal(
      int generation,
      ) async {
    try {
      await _updateNetworkStatus(
        generation,
      );

      if (!_isLifecycleCurrent(
        generation,
      )) {
        return;
      }

      _connectivitySubscription ??=
          _connectivity
              .onConnectivityChanged
              .listen(
                (
                List<ConnectivityResult> _,
                ) {
              if (!_isLifecycleCurrent(
                generation,
              )) {
                return;
              }

              _scheduleConnectivityRefresh(
                generation,
              );
            },
            onError: (
                Object error,
                StackTrace stackTrace,
                ) {
              if (!_isLifecycleCurrent(
                generation,
              )) {
                return;
              }

              _reportError(
                'connectivity stream',
                error,
                stackTrace,
              );
            },
          );

      _periodicTimer?.cancel();

      _periodicTimer = Timer.periodic(
        _periodicRefreshInterval,
            (_) {
          if (!_isLifecycleCurrent(
            generation,
          )) {
            return;
          }

          unawaited(
            refresh(),
          );
        },
      );

      _notifySafely(
        generation,
      );

      _debugPrint(
        'initialized.',
      );
    } catch (error, stackTrace) {
      if (_isLifecycleCurrent(
        generation,
      )) {
        _initialized = false;

        final StreamSubscription<
            List<ConnectivityResult>>?
        subscription =
            _connectivitySubscription;

        _connectivitySubscription =
        null;

        _periodicTimer?.cancel();

        _periodicTimer = null;

        _connectivityDebounceTimer?.cancel();

        _connectivityDebounceTimer =
        null;

        if (subscription != null) {
          await _cancelSubscriptionSafely(
            subscription,
            source:
            'initialize rollback',
          );
        }
      }

      _reportError(
        'initialize',
        error,
        stackTrace,
      );

      rethrow;
    }
  }

  // ===========================================================
  // CONNECTIVITY EVENT DEBOUNCE
  // ===========================================================

  void _scheduleConnectivityRefresh(
      int generation,
      ) {
    if (!_isLifecycleCurrent(
      generation,
    )) {
      return;
    }

    _connectivityDebounceTimer?.cancel();

    _connectivityDebounceTimer =
        Timer(
          _connectivityDebounceDuration,
              () {
            _connectivityDebounceTimer =
            null;

            if (!_isLifecycleCurrent(
              generation,
            )) {
              return;
            }

            unawaited(
              refresh(),
            );
          },
        );
  }

  // ===========================================================
  // REFRESH
  // ===========================================================

  Future<void> refresh() async {
    if (_disposed ||
        !_initialized) {
      return;
    }

    final int generation =
        _lifecycleGeneration;

    await _updateNetworkStatus(
      generation,
    );
  }

  // ===========================================================
  // NETWORK STATE UPDATE
  // ===========================================================

  Future<void> _updateNetworkStatus(
      int generation,
      ) async {
    if (!_isLifecycleCurrent(
      generation,
    )) {
      return;
    }

    if (_activeUpdateGeneration ==
        generation) {
      _pendingRefresh = true;

      return;
    }

    // A stale generation may still be unwinding asynchronously.
    // A current generation is allowed to proceed independently.
    _activeUpdateGeneration =
        generation;

    try {
      final bool hasTransport =
      await NetworkHelper
          .hasNetworkTransport();

      if (!_isLifecycleCurrent(
        generation,
      )) {
        return;
      }

      NetworkType type =
          NetworkType.unknown;

      try {
        type =
        await NetworkHelper
            .getNetworkType();
      } catch (error, stackTrace) {
        _reportError(
          'network type',
          error,
          stackTrace,
        );

        if (_currentNetwork.isConnected) {
          type =
              _currentNetwork.type;
        }
      }

      if (!_isLifecycleCurrent(
        generation,
      )) {
        return;
      }

      if (!hasTransport) {
        _commitOfflineNetwork(
          type,
          generation,
        );

        return;
      }

      // -------------------------------------------------------
      // ADVISORY MEASUREMENTS
      //
      // Failure here must not convert a real transport into
      // false OFFLINE.
      // -------------------------------------------------------

      NetworkQuality quality;

      int ping;

      double packetLoss;

      try {
        final List<Object> measurements =
        await Future.wait<Object>(
          <Future<Object>>[
            NetworkHelper
                .getNetworkQuality(),
            NetworkHelper
                .getLatency(),
            NetworkHelper
                .getPacketLoss(),
          ],
        );

        final Object qualityValue =
        measurements[0];

        final Object pingValue =
        measurements[1];

        final Object lossValue =
        measurements[2];

        if (qualityValue
        is! NetworkQuality ||
            pingValue is! int ||
            lossValue is! double) {
          throw StateError(
            'NetworkHelper returned '
                'unexpected measurement types.',
          );
        }

        quality =
            qualityValue;

        ping =
            pingValue;

        packetLoss =
            lossValue;
      } catch (error, stackTrace) {
        _reportError(
          'advisory measurement',
          error,
          stackTrace,
        );

        quality =
            NetworkQuality.poor;

        ping = 999;

        packetLoss = 0.0;
      }

      if (!_isLifecycleCurrent(
        generation,
      )) {
        return;
      }

      // -------------------------------------------------------
      // FALSE-OFFLINE PROTECTION
      //
      // A transport exists.
      //
      // External measurement/probe failure therefore means
      // "unknown/poor", not "device definitely offline".
      // -------------------------------------------------------

      if (quality ==
          NetworkQuality.offline) {
        quality =
            NetworkQuality.poor;
      }

      if (ping < 0) {
        ping = 999;
      }

      if (!packetLoss.isFinite ||
          packetLoss < 0) {
        packetLoss = 0.0;
      } else if (packetLoss > 100) {
        packetLoss = 100.0;
      }

      final int recommendedBitrate =
      NetworkHelper
          .recommendedBitrate(
        quality,
      );

      final int recommendedFps =
      NetworkHelper
          .recommendedFps(
        quality,
      );

      final Map<String, int> resolution =
      _resolveResolution(
        quality,
      );

      final NetworkModel next =
      _currentNetwork.copyWith(
        // Transport availability only.
        //
        // This does not claim Firebase/TURN/WebRTC reachability.
        isConnected: true,

        quality: quality,

        type: type,

        ping: ping,

        packetLoss:
        packetLoss,

        // These metrics are not actually measured by this manager.
        // Do not manufacture fake production values.
        downloadSpeed: 0.0,

        uploadSpeed: 0.0,

        jitter: 0,

        signalStrength: 0,

        recommendedBitrate:
        recommendedBitrate,

        recommendedFps:
        recommendedFps,

        videoWidth:
        resolution['width'] ??
            640,

        videoHeight:
        resolution['height'] ??
            360,

        updatedAt:
        DateTime.now().toUtc(),
      );

      _commitNetwork(
        next,
        generation,
      );

      // -------------------------------------------------------
      // IMPORTANT OWNERSHIP:
      //
      // Do NOT call NetworkHelper.adjustBitrate() here.
      //
      // NetworkManager publishes recommendations only.
      //
      // BitrateController is the actual WebRTC bitrate owner.
      // -------------------------------------------------------
    } catch (error, stackTrace) {
      if (_isLifecycleCurrent(
        generation,
      )) {
        _reportError(
          'refresh',
          error,
          stackTrace,
        );
      }

      // Preserve the previous known state on helper failure.
    } finally {
      if (_activeUpdateGeneration ==
          generation) {
        _activeUpdateGeneration =
        null;

        if (_pendingRefresh &&
            _isLifecycleCurrent(
              generation,
            )) {
          _pendingRefresh = false;

          scheduleMicrotask(
                () {
              if (!_isLifecycleCurrent(
                generation,
              )) {
                return;
              }

              unawaited(
                refresh(),
              );
            },
          );
        }
      }
    }
  }

  // ===========================================================
  // OFFLINE COMMIT
  // ===========================================================

  void _commitOfflineNetwork(
      NetworkType type,
      int generation,
      ) {
    if (!_isLifecycleCurrent(
      generation,
    )) {
      return;
    }

    final Map<String, int> resolution =
    _resolveResolution(
      NetworkQuality.offline,
    );

    final NetworkModel next =
    _currentNetwork.copyWith(
      isConnected: false,

      quality:
      NetworkQuality.offline,

      type: type,

      ping: 999,

      packetLoss: 100.0,

      downloadSpeed: 0.0,

      uploadSpeed: 0.0,

      jitter: 0,

      signalStrength: 0,

      recommendedBitrate: 0,

      recommendedFps: 0,

      videoWidth:
      resolution['width'] ??
          640,

      videoHeight:
      resolution['height'] ??
          360,

      updatedAt:
      DateTime.now().toUtc(),
    );

    _commitNetwork(
      next,
      generation,
    );
  }

  // ===========================================================
  // NETWORK COMMIT
  // ===========================================================

  void _commitNetwork(
      NetworkModel next,
      int generation,
      ) {
    if (!_isLifecycleCurrent(
      generation,
    )) {
      return;
    }

    final bool changed =
    !_sameNetwork(
      _currentNetwork,
      next,
    );

    _currentNetwork =
        next;

    if (!changed) {
      return;
    }

    try {
      onNetworkChanged?.call(
        next,
      );
    } catch (error, stackTrace) {
      _reportError(
        'onNetworkChanged callback',
        error,
        stackTrace,
      );
    }

    if (!_isLifecycleCurrent(
      generation,
    )) {
      return;
    }

    _notifySafely(
      generation,
    );
  }

  // ===========================================================
  // NETWORK COMPARISON
  // ===========================================================

  bool _sameNetwork(
      NetworkModel first,
      NetworkModel second,
      ) {
    return first.isConnected ==
        second.isConnected &&
        first.quality ==
            second.quality &&
        first.type ==
            second.type &&
        first.ping ==
            second.ping &&
        first.packetLoss ==
            second.packetLoss &&
        first.downloadSpeed ==
            second.downloadSpeed &&
        first.uploadSpeed ==
            second.uploadSpeed &&
        first.jitter ==
            second.jitter &&
        first.signalStrength ==
            second.signalStrength &&
        first.recommendedBitrate ==
            second.recommendedBitrate &&
        first.recommendedFps ==
            second.recommendedFps &&
        first.videoWidth ==
            second.videoWidth &&
        first.videoHeight ==
            second.videoHeight;
  }

  // ===========================================================
  // RESOLUTION RECOMMENDATION
  // ===========================================================

  Map<String, int> _resolveResolution(
      NetworkQuality quality,
      ) {
    switch (quality) {
      case NetworkQuality.excellent:
        return const <String, int>{
          'width': 1280,
          'height': 720,
        };

      case NetworkQuality.good:
        return const <String, int>{
          'width': 854,
          'height': 480,
        };

      case NetworkQuality.fair:
      case NetworkQuality.poor:
      case NetworkQuality.offline:
        return const <String, int>{
          'width': 640,
          'height': 360,
        };
    }
  }

  // ===========================================================
  // LIFECYCLE VALIDATION
  // ===========================================================

  bool _isLifecycleCurrent(
      int generation,
      ) {
    return !_disposed &&
        _initialized &&
        generation ==
            _lifecycleGeneration;
  }

  // ===========================================================
  // SAFE SUBSCRIPTION CANCELLATION
  // ===========================================================

  Future<void> _cancelSubscriptionSafely(
      StreamSubscription<
          List<ConnectivityResult>>
      subscription, {
        required String source,
      }) async {
    try {
      await subscription.cancel();
    } catch (error, stackTrace) {
      _reportError(
        source,
        error,
        stackTrace,
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

    _lifecycleGeneration++;

    _connectivityDebounceTimer?.cancel();

    _connectivityDebounceTimer =
    null;

    _periodicTimer?.cancel();

    _periodicTimer =
    null;

    final StreamSubscription<
        List<ConnectivityResult>>?
    subscription =
        _connectivitySubscription;

    _connectivitySubscription =
    null;

    _activeInitialization =
    null;

    _activeUpdateGeneration =
    null;

    _pendingRefresh =
    false;

    _initialized =
    false;

    _currentNetwork =
        NetworkModel.initial();

    if (subscription != null) {
      unawaited(
        _cancelSubscriptionSafely(
          subscription,
          source: 'reset subscription',
        ),
      );
    }

    notifyListeners();

    _debugPrint(
      'reset.',
    );
  }

  // ===========================================================
  // SAFE NOTIFICATION
  // ===========================================================

  void _notifySafely(
      int generation,
      ) {
    if (_isLifecycleCurrent(
      generation,
    )) {
      notifyListeners();
    }
  }

  // ===========================================================
  // LOGGING
  // ===========================================================

  void _debugPrint(
      String message,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[NetworkManager] '
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
          '[NetworkManager/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[NetworkManager/$source]',
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

    _disposed = true;

    _initialized = false;

    _lifecycleGeneration++;

    _connectivityDebounceTimer?.cancel();

    _connectivityDebounceTimer =
    null;

    _periodicTimer?.cancel();

    _periodicTimer =
    null;

    final StreamSubscription<
        List<ConnectivityResult>>?
    subscription =
        _connectivitySubscription;

    _connectivitySubscription =
    null;

    _activeInitialization =
    null;

    _activeUpdateGeneration =
    null;

    _pendingRefresh =
    false;

    onNetworkChanged =
    null;

    if (subscription != null) {
      unawaited(
        _cancelSubscriptionSafely(
          subscription,
          source: 'dispose subscription',
        ),
      );
    }

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 16 FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ connectivity_plus 6.1.5 List<ConnectivityResult> API preserved.
// ✓ Connectivity transport is not treated as Internet proof.
// ✓ Real transport remains pre-call attempt eligible.
// ✓ Probe failure degrades to POOR, not false OFFLINE.
// ✓ Actual absence of transport becomes OFFLINE.
// ✓ Stale async refresh cannot overwrite a new lifecycle.
// ✓ Reset/dispose invalidate old async work.
// ✓ Same-generation refreshes collapse safely.
// ✓ Old generation cannot clear a newer update lock.
// ✓ Connectivity event bursts are debounced.
// ✓ Existing 5-second monitoring cadence preserved.
// ✓ Initialization is concurrency-safe.
// ✓ Subscription cleanup is safe.
// ✓ Timestamp-only refresh does not emit false network change.
// ✓ Real ping/packet-loss values normalized.
// ✓ Fake download/upload speed removed.
// ✓ Fake signal strength removed.
// ✓ Derived fake jitter removed.
// ✓ Network recommendations remain in NetworkModel.
// ✓ NetworkManager no longer mutates WebRTC bitrate.
// ✓ BitrateController remains actual bitrate owner.
// ✓ RecoveryManager remains network recovery owner.
// ✓ No PeerConnection ownership.
// ✓ No ICE restart ownership.
// ✓ No Firebase/signaling ownership.
//
// STATUS:
// NETWORK MANAGER FINALIZED.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 17
// lib/services/managers/recovery_manager.dart
// ===============================================================