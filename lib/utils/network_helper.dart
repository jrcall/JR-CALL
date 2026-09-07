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
// Production cross-platform network utility.
//
// Responsibilities:
// - Detect available network transport.
// - Observe connectivity changes.
// - Perform lightweight Internet reachability checks.
// - Measure approximate HTTP round-trip latency.
// - Provide advisory network-quality classification.
// - Provide compatibility bitrate/FPS recommendations.
//
// Ownership:
// - ConnectionManager owns live call connectivity state.
// - RecoveryManager owns call recovery.
// - StatsManager/WebRTC owns real RTP statistics.
// - BitrateController owns real sender bitrate mutation.
// - NetworkOptimizer owns call-specific optimization.
// - NetworkHelper remains a lightweight shared utility.
//
// Important:
// - Connectivity type is not proof of Internet access.
// - HTTP latency is not ICMP ping.
// - HTTP request failures are not RTP packet loss.
// - No WebRTC manipulation.
// - No recovery ownership.
// - No polling/timer ownership.
// - No UI/design ownership.
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

  static const Duration _probeTimeout = Duration(
    seconds: 3,
  );

  static const int _packetLossProbeCount = 5;

  static const int _offlineLatency = 999;

  static const int _webFallbackLatency = 100;

  /// Each target has an expected response.
  ///
  /// This prevents a captive portal or intercepted request that
  /// simply returns an unrelated HTTP 200 page from being treated
  /// as confirmed Internet reachability.
  static final List<_NetworkProbeTarget> _probeTargets =
  <_NetworkProbeTarget>[
    _NetworkProbeTarget(
      uri: Uri.parse(
        'https://www.gstatic.com/generate_204',
      ),
      expectedStatusCode: 204,
    ),
    _NetworkProbeTarget(
      uri: Uri.parse(
        'https://www.apple.com/library/test/success.html',
      ),
      expectedStatusCode: 200,
      requiredBodyText: 'Success',
    ),
  ];

  // ===========================================================
  // Current Connectivity Results
  // ===========================================================

  /// Returns every connectivity type currently reported by
  /// connectivity_plus.
  ///
  /// Transport availability must not be interpreted as guaranteed
  /// Internet reachability.
  static Future<List<ConnectivityResult>>
  getConnectivityResults() async {
    try {
      final List<ConnectivityResult> results =
      await _connectivity.checkConnectivity();

      if (results.isEmpty) {
        return const <ConnectivityResult>[
          ConnectivityResult.none,
        ];
      }

      return List<ConnectivityResult>.unmodifiable(
        results,
      );
    } catch (error, stackTrace) {
      _debugError(
        'getConnectivityResults',
        error,
        stackTrace,
      );

      return const <ConnectivityResult>[
        ConnectivityResult.none,
      ];
    }
  }

  // ===========================================================
  // Current Network Type
  // ===========================================================

  static Future<NetworkType> getNetworkType() async {
    final List<ConnectivityResult> results =
    await getConnectivityResults();

    if (_isOfflineResult(results)) {
      return NetworkType.unknown;
    }

    // Prefer the underlying physical/high-bandwidth transport
    // when more than one type is reported.
    //
    // For example, Wi-Fi + VPN remains classified as Wi-Fi for
    // the existing NetworkModel contract.
    if (results.contains(
      ConnectivityResult.ethernet,
    )) {
      return NetworkType.ethernet;
    }

    if (results.contains(
      ConnectivityResult.wifi,
    )) {
      return NetworkType.wifi;
    }

    if (results.contains(
      ConnectivityResult.mobile,
    )) {
      return NetworkType.mobile;
    }

    if (results.contains(
      ConnectivityResult.vpn,
    )) {
      return NetworkType.vpn;
    }

    if (results.contains(
      ConnectivityResult.bluetooth,
    )) {
      return NetworkType.bluetooth;
    }

    // connectivity_plus can report "other".
    // The current JR CALL NetworkType contract has no separate
    // value for it, so preserve NetworkType.unknown.
    return NetworkType.unknown;
  }

  // ===========================================================
  // Network Transport Availability
  // ===========================================================

  static Future<bool> hasNetworkTransport() async {
    final List<ConnectivityResult> results =
    await getConnectivityResults();

    return !_isOfflineResult(
      results,
    );
  }

  // ===========================================================
  // Internet Availability
  // ===========================================================

  /// Returns whether general Internet reachability appears usable.
  ///
  /// This remains advisory. Firebase, WebRTC and TURN requests must
  /// still handle their own errors and timeouts.
  static Future<bool> hasInternet() async {
    final _ReachabilityMeasurement measurement =
    await _measureReachability();

    return measurement.reachable;
  }

  // ===========================================================
  // Latency / Ping Compatibility
  // ===========================================================

  /// Approximate HTTP round-trip latency in milliseconds.
  ///
  /// This is not an ICMP ping.
  ///
  /// Returns 999 when reachability cannot be confirmed.
  static Future<int> getPing() async {
    final _ReachabilityMeasurement measurement =
    await _measureReachability();

    return measurement.latencyMilliseconds;
  }

  static Future<int> getLatency() {
    return getPing();
  }

  // ===========================================================
  // Network Quality
  // ===========================================================

  /// Advisory general/pre-call quality only.
  ///
  /// Active-call quality remains WebRTC statistics owned.
  static Future<NetworkQuality> getNetworkQuality() async {
    final _ReachabilityMeasurement measurement =
    await _measureReachability();

    if (!measurement.reachable) {
      return NetworkQuality.offline;
    }

    final int latency =
        measurement.latencyMilliseconds;

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

  /// Returns failed HTTPS probe percentage.
  ///
  /// This value is NOT RTP/WebRTC packet loss.
  /// Real call packet loss must come from WebRTC statistics.
  static Future<double> getPacketLoss() async {
    final bool hasTransport =
    await hasNetworkTransport();

    if (!hasTransport) {
      return 100.0;
    }

    if (kIsWeb) {
      // Cross-origin probe failure in a browser may be caused by
      // browser security policy rather than network packet loss.
      return 0.0;
    }

    if (_probeTargets.isEmpty) {
      return 100.0;
    }

    final List<Future<_NetworkProbeResult>> probes =
    <Future<_NetworkProbeResult>>[];

    for (
    int index = 0;
    index < _packetLossProbeCount;
    index++
    ) {
      final _NetworkProbeTarget target =
      _probeTargets[
      index % _probeTargets.length
      ];

      probes.add(
        _probe(target),
      );
    }

    final List<_NetworkProbeResult> results =
    await Future.wait(
      probes,
    );

    if (results.isEmpty) {
      return 100.0;
    }

    int failures = 0;

    for (final _NetworkProbeResult result
    in results) {
      if (!result.success) {
        failures++;
      }
    }

    final double percentage =
        (failures / results.length) * 100.0;

    return percentage.clamp(
      0.0,
      100.0,
    );
  }

  // ===========================================================
  // Bitrate Compatibility Hook
  // ===========================================================

  /// Compatibility hook only.
  ///
  /// NetworkHelper never mutates an RTP sender.
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
  /// Values are bits per second.
  static int recommendedBitrate(
      NetworkQuality quality,
      ) {
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

  static int getBitrate(
      NetworkQuality quality,
      ) {
    return recommendedBitrate(
      quality,
    );
  }

  // ===========================================================
  // Recommended FPS
  // ===========================================================

  /// Compatibility recommendation only.
  ///
  /// Camera/WebRTC layers remain authoritative for actual frame
  /// rate application.
  static int recommendedFps(
      NetworkQuality quality,
      ) {
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

  static int getFps(
      NetworkQuality quality,
      ) {
    return recommendedFps(
      quality,
    );
  }

  // ===========================================================
  // Connectivity Stream
  // ===========================================================

  /// Existing public stream API preserved.
  ///
  /// The helper exposes the plugin stream directly and does not
  /// create another listener, timer or polling engine.
  static Stream<List<ConnectivityResult>>
  get onNetworkChanged =>
      _connectivity.onConnectivityChanged;

  // ===========================================================
  // Connectivity Helpers
  // ===========================================================

  static bool _isOfflineResult(
      List<ConnectivityResult> results,
      ) {
    if (results.isEmpty) {
      return true;
    }

    for (final ConnectivityResult result
    in results) {
      if (result != ConnectivityResult.none) {
        return false;
      }
    }

    return true;
  }

  // ===========================================================
  // Reachability Measurement
  // ===========================================================

  static Future<_ReachabilityMeasurement>
  _measureReachability() async {
    final bool hasTransport =
    await hasNetworkTransport();

    if (!hasTransport) {
      return const _ReachabilityMeasurement(
        reachable: false,
        latencyMilliseconds: _offlineLatency,
      );
    }

    // Generic external HTTPS probing is not a dependable browser
    // test because cross-origin restrictions can block a request
    // even when the browser has working Internet access.
    if (kIsWeb) {
      return const _ReachabilityMeasurement(
        reachable: true,
        latencyMilliseconds: _webFallbackLatency,
      );
    }

    if (_probeTargets.isEmpty) {
      return const _ReachabilityMeasurement(
        reachable: false,
        latencyMilliseconds: _offlineLatency,
      );
    }

    final List<_NetworkProbeResult> results =
    await Future.wait(
      _probeTargets.map(
        _probe,
      ),
    );

    int? fastestLatency;

    for (final _NetworkProbeResult result
    in results) {
      if (!result.success) {
        continue;
      }

      if (fastestLatency == null ||
          result.latencyMilliseconds <
              fastestLatency) {
        fastestLatency =
            result.latencyMilliseconds;
      }
    }

    if (fastestLatency == null) {
      return const _ReachabilityMeasurement(
        reachable: false,
        latencyMilliseconds: _offlineLatency,
      );
    }

    return _ReachabilityMeasurement(
      reachable: true,
      latencyMilliseconds:
      fastestLatency.clamp(
        0,
        _offlineLatency,
      ),
    );
  }

  // ===========================================================
  // HTTPS Reachability Probe
  // ===========================================================

  static Future<_NetworkProbeResult> _probe(
      _NetworkProbeTarget target,
      ) async {
    final Stopwatch stopwatch =
    Stopwatch()..start();

    try {
      final http.Response response =
      await http
          .get(
        target.uri,
        headers: const <String, String>{
          'Cache-Control': 'no-cache',
        },
      )
          .timeout(
        _probeTimeout,
      );

      stopwatch.stop();

      final bool success =
      _isExpectedProbeResponse(
        target,
        response,
      );

      return _NetworkProbeResult(
        success: success,
        latencyMilliseconds:
        stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException
    catch (error, stackTrace) {
      stopwatch.stop();

      _debugError(
        'probe timeout: ${target.uri}',
        error,
        stackTrace,
      );

      return _NetworkProbeResult(
        success: false,
        latencyMilliseconds:
        stopwatch.elapsedMilliseconds,
      );
    } catch (error, stackTrace) {
      stopwatch.stop();

      _debugError(
        'probe failure: ${target.uri}',
        error,
        stackTrace,
      );

      return _NetworkProbeResult(
        success: false,
        latencyMilliseconds:
        stopwatch.elapsedMilliseconds,
      );
    }
  }

  static bool _isExpectedProbeResponse(
      _NetworkProbeTarget target,
      http.Response response,
      ) {
    if (response.statusCode !=
        target.expectedStatusCode) {
      return false;
    }

    final String? requiredBodyText =
        target.requiredBodyText;

    if (requiredBodyText == null) {
      return true;
    }

    return response.body.contains(
      requiredBodyText,
    );
  }

  // ===========================================================
  // Platform
  // ===========================================================

  /// Current Flutter target platform without dart:io.
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

  static void _debugError(
      String source,
      Object error,
      StackTrace stackTrace,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL [NetworkHelper/$source] error: $error',
    );

    debugPrintStack(
      label:
      'JR CALL [NetworkHelper/$source]',
      stackTrace:
      stackTrace,
    );
  }
}

// ===========================================================
// Internal Probe Target
// ===========================================================

@immutable
class _NetworkProbeTarget {
  const _NetworkProbeTarget({
    required this.uri,
    required this.expectedStatusCode,
    this.requiredBodyText,
  });

  final Uri uri;

  final int expectedStatusCode;

  final String? requiredBodyText;
}

// ===========================================================
// Internal Probe Result
// ===========================================================

@immutable
class _NetworkProbeResult {
  const _NetworkProbeResult({
    required this.success,
    required this.latencyMilliseconds,
  });

  final bool success;

  final int latencyMilliseconds;
}

// ===========================================================
// Internal Reachability Measurement
// ===========================================================

@immutable
class _ReachabilityMeasurement {
  const _ReachabilityMeasurement({
    required this.reachable,
    required this.latencyMilliseconds,
  });

  final bool reachable;

  final int latencyMilliseconds;
}