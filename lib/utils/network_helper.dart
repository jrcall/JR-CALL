import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/network_model.dart';

// ===========================================================
// JR CALL
// File: network_helper.dart
// Location: lib/utils/network_helper.dart
//
// Description:
// Production cross-platform network utility for JR CALL.
//
// Responsibilities:
// - Detect available network transport
// - Observe connectivity changes
// - Perform lightweight Internet reachability checks
// - Measure approximate HTTP round-trip latency
// - Provide advisory network-quality classification
// - Provide compatibility bitrate/FPS recommendations
// - Preserve existing NetworkHelper public APIs
//
// Architecture:
// - ConnectionManager owns live Call Engine connectivity state
// - RecoveryManager owns call reconnection/recovery
// - StatsManager/WebRTC owns real RTP packet-loss measurements
// - BitrateController owns real WebRTC bitrate adaptation
// - NetworkOptimizer owns call-specific network optimization
// - NetworkHelper remains a lightweight shared utility
//
// Important:
// - Connectivity type alone does NOT guarantee Internet access
// - HTTP latency is NOT ICMP ping
// - Helper packet-loss value is only an advisory reachability sample
// - Real call packet loss must come from WebRTC statistics
// - This file does NOT manipulate WebRTC
// - This file does NOT duplicate ConnectionManager
// - This file does NOT duplicate BitrateController
// - This file does NOT contain UI/design logic
// ===========================================================

class NetworkHelper {
  NetworkHelper._();

  // ===========================================================
  // Connectivity
  // ===========================================================

  static final Connectivity _connectivity = Connectivity();

  // ===========================================================
  // Probe Configuration
  // ===========================================================

  static const Duration _probeTimeout = Duration(seconds: 3);

  static const int _packetLossProbeCount = 5;

  /// Multiple geographically independent HTTPS endpoints are used
  /// so one blocked/unavailable provider does not automatically
  /// classify the device as offline.
  ///
  /// No user/account data is sent by NetworkHelper.
  static final List<Uri> _probeEndpoints = <Uri>[
    Uri.parse('https://www.gstatic.com/generate_204'),
    Uri.parse('https://www.msftconnecttest.com/connecttest.txt'),
    Uri.parse('https://www.apple.com/library/test/success.html'),
  ];

  // ===========================================================
  // Current Connectivity Results
  // ===========================================================

  /// Returns every active connectivity type reported by
  /// connectivity_plus.
  ///
  /// The returned collection is immutable.
  static Future<List<ConnectivityResult>> getConnectivityResults() async {
    try {
      final results = await _connectivity.checkConnectivity();

      if (results.isEmpty) {
        return const <ConnectivityResult>[ConnectivityResult.none];
      }

      return List<ConnectivityResult>.unmodifiable(results);
    } catch (error, stackTrace) {
      _debugError('getConnectivityResults', error, stackTrace);

      return const <ConnectivityResult>[ConnectivityResult.none];
    }
  }

  // ===========================================================
  // Current Network Type
  // ===========================================================

  static Future<NetworkType> getNetworkType() async {
    final results = await getConnectivityResults();

    if (_isOfflineResult(results)) {
      return NetworkType.unknown;
    }

    // Prefer the underlying physical/high-bandwidth transport
    // when several connectivity types are reported together.
    //
    // Example:
    // Wi-Fi + VPN should continue to classify as Wi-Fi rather
    // than arbitrarily depending on List ordering.

    if (results.contains(ConnectivityResult.ethernet)) {
      return NetworkType.ethernet;
    }

    if (results.contains(ConnectivityResult.wifi)) {
      return NetworkType.wifi;
    }

    if (results.contains(ConnectivityResult.mobile)) {
      return NetworkType.mobile;
    }

    if (results.contains(ConnectivityResult.vpn)) {
      return NetworkType.vpn;
    }

    if (results.contains(ConnectivityResult.bluetooth)) {
      return NetworkType.bluetooth;
    }

    return NetworkType.unknown;
  }

  // ===========================================================
  // Network Transport Availability
  // ===========================================================

  /// Returns whether the operating system currently reports at
  /// least one usable network transport.
  ///
  /// This is NOT the same as confirmed Internet reachability.
  static Future<bool> hasNetworkTransport() async {
    final results = await getConnectivityResults();

    return !_isOfflineResult(results);
  }

  // ===========================================================
  // Internet Availability
  // ===========================================================

  /// Checks whether Internet access appears usable.
  ///
  /// Native/desktop:
  /// - verifies network transport first
  /// - then performs lightweight HTTPS probes
  ///
  /// Web:
  /// Browser CORS/security policy may prevent generic external
  /// reachability probes even while the browser is online.
  /// Therefore connectivity_plus remains the safe browser-level
  /// fallback.
  ///
  /// Call Engine operations must still handle their own network
  /// timeouts/errors. This method must never be treated as an
  /// absolute guarantee that Firebase/WebRTC/TURN is reachable.
  static Future<bool> hasInternet() async {
    final hasTransport = await hasNetworkTransport();

    if (!hasTransport) {
      return false;
    }

    if (kIsWeb) {
      return true;
    }

    for (final endpoint in _probeEndpoints) {
      final result = await _probe(endpoint);

      if (result.success) {
        return true;
      }
    }

    return false;
  }

  // ===========================================================
  // Latency / Ping Compatibility
  // ===========================================================

  /// Returns approximate HTTP round-trip latency in milliseconds.
  ///
  /// Compatibility name:
  /// getPing()
  ///
  /// This is intentionally NOT represented as ICMP ping.
  ///
  /// Returns 999 when no probe succeeds.
  static Future<int> getPing() async {
    final hasTransport = await hasNetworkTransport();

    if (!hasTransport) {
      return 999;
    }

    // Browser security/CORS rules prevent a reliable generic
    // HTTP reachability benchmark to arbitrary domains.
    //
    // Preserve a conservative usable value when the browser
    // reports online rather than falsely classifying Web as
    // offline.
    if (kIsWeb) {
      return 100;
    }

    int? fastestLatency;

    for (final endpoint in _probeEndpoints) {
      final result = await _probe(endpoint);

      if (!result.success) {
        continue;
      }

      final latency = result.latencyMilliseconds;

      if (fastestLatency == null || latency < fastestLatency) {
        fastestLatency = latency;
      }
    }

    return fastestLatency ?? 999;
  }

  /// Backward-compatible alias.
  static Future<int> getLatency() {
    return getPing();
  }

  // ===========================================================
  // Network Quality
  // ===========================================================

  /// Returns advisory pre-call/general network quality.
  ///
  /// Actual active-call quality must be determined from WebRTC
  /// statistics by the Call Engine quality/statistics layer.
  static Future<NetworkQuality> getNetworkQuality() async {
    final connected = await hasInternet();

    if (!connected) {
      return NetworkQuality.offline;
    }

    final latency = await getLatency();

    if (latency <= 50) {
      return NetworkQuality.excellent;
    }

    if (latency <= 100) {
      return NetworkQuality.good;
    }

    if (latency <= 180) {
      return NetworkQuality.fair;
    }

    return NetworkQuality.poor;
  }

  // ===========================================================
  // Advisory Reachability Loss
  // ===========================================================

  /// Returns an advisory failed-request percentage.
  ///
  /// IMPORTANT:
  /// This is NOT RTP/WebRTC packet loss.
  ///
  /// Real voice/video packet loss must be read from WebRTC stats.
  ///
  /// Existing public API is preserved because finalized JR CALL
  /// files may already depend on getPacketLoss().
  static Future<double> getPacketLoss() async {
    final hasTransport = await hasNetworkTransport();

    if (!hasTransport) {
      return 100.0;
    }

    if (kIsWeb) {
      // Generic external probes are not reliable in browsers
      // because CORS can block the request independently of
      // Internet availability.
      return 0.0;
    }

    final probes = <Future<_NetworkProbeResult>>[];

    for (var index = 0; index < _packetLossProbeCount; index++) {
      final endpoint = _probeEndpoints[index % _probeEndpoints.length];

      probes.add(_probe(endpoint));
    }

    final results = await Future.wait(probes);

    var failures = 0;

    for (final result in results) {
      if (!result.success) {
        failures++;
      }
    }

    return (failures / results.length) * 100.0;
  }

  // ===========================================================
  // Bitrate Compatibility Hook
  // ===========================================================

  /// Backward-compatible hook only.
  ///
  /// NetworkHelper intentionally does NOT directly change the
  /// WebRTC sender bitrate.
  ///
  /// Real bitrate mutation belongs to the existing protected
  /// BitrateController / NetworkOptimizer layer.
  static Future<void> adjustBitrate(
    NetworkQuality quality,
    int latency,
    double packetLoss,
  ) async {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL [NetworkHelper]: '
      'bitrate recommendation requested -> '
      'quality=$quality, '
      'latency=${latency}ms, '
      'advisoryLoss=${packetLoss.toStringAsFixed(1)}%. '
      'Real WebRTC bitrate remains owned by BitrateController.',
    );
  }

  // ===========================================================
  // Recommended Video Bitrate
  // ===========================================================

  /// Compatibility recommendation only.
  ///
  /// Values are in bits per second.
  ///
  /// The actual call engine remains free to further adapt bitrate
  /// using WebRTC stats, TURN conditions, packet loss and recovery.
  static int recommendedBitrate(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return 3000000;

      case NetworkQuality.good:
        return 1800000;

      case NetworkQuality.fair:
        return 900000;

      case NetworkQuality.poor:
        return 400000;

      case NetworkQuality.offline:
        return 0;
    }
  }

  /// Backward-compatible alias.
  static int getBitrate(NetworkQuality quality) {
    return recommendedBitrate(quality);
  }

  // ===========================================================
  // Recommended FPS
  // ===========================================================

  /// Compatibility recommendation only.
  ///
  /// Actual camera/WebRTC frame rate remains controlled by the
  /// media/video layer.
  static int recommendedFps(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return 60;

      case NetworkQuality.good:
        return 30;

      case NetworkQuality.fair:
        return 24;

      case NetworkQuality.poor:
        return 15;

      case NetworkQuality.offline:
        return 0;
    }
  }

  /// Backward-compatible alias.
  static int getFps(NetworkQuality quality) {
    return recommendedFps(quality);
  }

  // ===========================================================
  // Connectivity Stream
  // ===========================================================

  /// Existing public stream API preserved exactly.
  static Stream<List<ConnectivityResult>> get onNetworkChanged =>
      _connectivity.onConnectivityChanged;

  // ===========================================================
  // Connectivity Helpers
  // ===========================================================

  static bool _isOfflineResult(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      return true;
    }

    if (results.length == 1 && results.first == ConnectivityResult.none) {
      return true;
    }

    for (final result in results) {
      if (result != ConnectivityResult.none) {
        return false;
      }
    }

    return true;
  }

  // ===========================================================
  // HTTP Reachability Probe
  // ===========================================================

  static Future<_NetworkProbeResult> _probe(Uri endpoint) async {
    final stopwatch = Stopwatch()..start();

    try {
      final response = await http
          .get(
            endpoint,
            headers: const <String, String>{'Cache-Control': 'no-cache'},
          )
          .timeout(_probeTimeout);

      stopwatch.stop();

      // Any valid HTTP response proves that the request crossed
      // the network and reached an HTTP server.
      //
      // A 4xx/5xx response may indicate endpoint policy/service
      // state, but it still proves network reachability.
      final validHttpResponse =
          response.statusCode >= 100 && response.statusCode <= 599;

      return _NetworkProbeResult(
        success: validHttpResponse,
        latencyMilliseconds: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException catch (error, stackTrace) {
      stopwatch.stop();

      _debugError('probe timeout: $endpoint', error, stackTrace);

      return _NetworkProbeResult(
        success: false,
        latencyMilliseconds: stopwatch.elapsedMilliseconds,
      );
    } catch (error, stackTrace) {
      stopwatch.stop();

      _debugError('probe failure: $endpoint', error, stackTrace);

      return _NetworkProbeResult(
        success: false,
        latencyMilliseconds: stopwatch.elapsedMilliseconds,
      );
    }
  }

  // ===========================================================
  // Platform
  // ===========================================================

  /// Returns the current Flutter target platform without importing
  /// dart:io, keeping this helper compatible with Flutter Web.
  static String get platform {
    if (kIsWeb) {
      return 'Web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';

      case TargetPlatform.iOS:
        return 'iOS';

      case TargetPlatform.windows:
        return 'Windows';

      case TargetPlatform.macOS:
        return 'macOS';

      case TargetPlatform.linux:
        return 'Linux';

      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  /// JR CALL production target support.
  static bool get isSupportedPlatform {
    if (kIsWeb) {
      return true;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;

      case TargetPlatform.fuchsia:
        return false;
    }
  }

  // ===========================================================
  // Debug Logging
  // ===========================================================

  static void _debugError(String source, Object error, StackTrace stackTrace) {
    if (!kDebugMode) {
      return;
    }

    debugPrint('JR CALL [NetworkHelper/$source] error: $error');

    debugPrintStack(
      label: 'JR CALL [NetworkHelper/$source]',
      stackTrace: stackTrace,
    );
  }
}

// ===========================================================
// Internal Network Probe Result
// ===========================================================

class _NetworkProbeResult {
  const _NetworkProbeResult({
    required this.success,
    required this.latencyMilliseconds,
  });

  final bool success;
  final int latencyMilliseconds;
}
