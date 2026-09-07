import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: stats_manager.dart
/// Location: lib/services/managers/stats_manager.dart
///
/// FINAL PRODUCTION WEBRTC STATS MANAGER
///
/// OWNERSHIP:
///
/// StatsManager:
/// - Read RTCPeerConnection.getStats().
/// - Derive call telemetry.
/// - Maintain bounded stats history.
/// - Emit weak-network alerts.
///
/// StatsManager does NOT:
/// - Mutate PeerConnection.
/// - Change bitrate.
/// - Own media.
/// - Own ICE.
/// - Own signaling.
/// - Own recovery.
/// - Own call lifecycle.
/// - Change UI/design.
/// ===========================================================

class CallStatsModel {
  final int ping;

  final int jitter;

  final double packetLoss;

  final double uploadBitrate;

  final double downloadBitrate;

  final int fps;

  final int videoWidth;

  final int videoHeight;

  final double qualityScore;

  final DateTime timestamp;

  const CallStatsModel({
    required this.ping,
    required this.jitter,
    required this.packetLoss,
    required this.uploadBitrate,
    required this.downloadBitrate,
    required this.fps,
    required this.videoWidth,
    required this.videoHeight,
    required this.qualityScore,
    required this.timestamp,
  });

  factory CallStatsModel.initial() {
    return CallStatsModel(
      ping: 0,
      jitter: 0,
      packetLoss: 0,
      uploadBitrate: 0,
      downloadBitrate: 0,
      fps: 0,
      videoWidth: 0,
      videoHeight: 0,
      qualityScore: 100,
      timestamp: DateTime.now().toUtc(),
    );
  }
}

class StatsManager extends ChangeNotifier {
  StatsManager._();

  static final StatsManager instance = StatsManager._();

  // ===========================================================
  // CONFIGURATION
  // ===========================================================

  static const int _historyLimit = 50;

  static const Duration _sampleInterval =
  Duration(seconds: 2);

  static const String _candidatePairType =
      'candidate-' 'pair';

  static const String _transportType =
      'transport';

  static const String _inboundRtpType =
      'inbound-' 'rtp';

  static const String _outboundRtpType =
      'outbound-' 'rtp';

  static const String _remoteInboundRtpType =
      'remote-inbound-' 'rtp';

  static const String _audioKind =
      'audio';

  static const String _videoKind =
      'video';

  // ===========================================================
  // MONITORING
  // ===========================================================

  Timer? _timer;

  RTCPeerConnection? _connection;

  bool _initialized = false;

  bool _disposed = false;

  int _generation = 0;

  int? _activeSampleGeneration;

  Stopwatch? _samplingClock;

  Duration? _lastSampleElapsed;

  // ===========================================================
  // BYTE BASELINES
  // ===========================================================

  int _lastBytesSent = 0;

  int _lastBytesReceived = 0;

  int _lastVideoBytesSent = 0;

  int _lastAudioBytesSent = 0;

  // ===========================================================
  // SPLIT BITRATE STATE
  // ===========================================================

  double _currentVideoBitrate = 0.0;

  double _currentAudioBitrate = 0.0;

  // ===========================================================
  // STATS STATE
  // ===========================================================

  CallStatsModel _currentStats =
  CallStatsModel.initial();

  final List<CallStatsModel> _history =
  <CallStatsModel>[];

  bool _weakNetworkActive = false;

  // ===========================================================
  // PUBLIC CALLBACKS
  // ===========================================================

  Function(CallStatsModel)? onStatsChanged;

  Function(CallStatsModel)? onStatsUpdated;

  Function(String)? onWeakNetworkAlert;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  bool get isInitialized =>
      _initialized;

  CallStatsModel get currentStats =>
      _currentStats;

  List<CallStatsModel> get statsHistory =>
      List<CallStatsModel>.unmodifiable(
        _history,
      );

  int get ping =>
      _currentStats.ping;

  int get jitter =>
      _currentStats.jitter;

  double get packetLoss =>
      _currentStats.packetLoss;

  double get uploadBitrate =>
      _currentStats.uploadBitrate;

  double get downloadBitrate =>
      _currentStats.downloadBitrate;

  int get currentFps =>
      _currentStats.fps;

  int get videoWidth =>
      _currentStats.videoWidth;

  int get videoHeight =>
      _currentStats.videoHeight;

  double get qualityScore =>
      _currentStats.qualityScore;

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() async {
    if (_disposed ||
        _initialized) {
      return;
    }

    _initialized = true;

    _notifySafely();
  }

  // ===========================================================
  // LATEST STATS
  // ===========================================================

  Future<Map<String, dynamic>>
  getLatestStats() {
    final CallStatsModel stats =
        _currentStats;

    return Future<Map<String, dynamic>>.value(
      <String, dynamic>{
        'rtt': stats.ping,
        'jitter': stats.jitter,
        'packetLoss':
        stats.packetLoss,
        'uploadBitrate':
        stats.uploadBitrate,
        'downloadBitrate':
        stats.downloadBitrate,
        'currentVideoBitrate':
        _currentVideoBitrate,
        'currentAudioBitrate':
        _currentAudioBitrate,
        'fps': stats.fps,
        'videoWidth':
        stats.videoWidth,
        'videoHeight':
        stats.videoHeight,
        'qualityScore':
        stats.qualityScore,
        'timestamp':
        stats.timestamp
            .toIso8601String(),
      },
    );
  }

  // ===========================================================
  // START MONITORING
  // ===========================================================

  void startMonitoring(
      RTCPeerConnection? peerConnection,
      ) {
    if (_disposed) {
      return;
    }

    stopMonitoring();

    if (peerConnection == null) {
      return;
    }

    final int generation =
    ++_generation;

    _connection =
        peerConnection;

    _resetSamplingBaselines();

    _samplingClock =
    Stopwatch()
      ..start();

    _timer =
        Timer.periodic(
          _sampleInterval,
              (_) {
            unawaited(
              _collectSample(
                generation,
                peerConnection,
              ),
            );
          },
        );

    unawaited(
      _collectSample(
        generation,
        peerConnection,
      ),
    );
  }

  // ===========================================================
  // SAMPLE COLLECTION
  // ===========================================================

  Future<void> _collectSample(
      int generation,
      RTCPeerConnection connection,
      ) async {
    if (!_isMonitoringSession(
      generation,
      connection,
    )) {
      return;
    }

    if (_activeSampleGeneration ==
        generation) {
      return;
    }

    _activeSampleGeneration =
        generation;

    try {
      final List<StatsReport> reports =
      await connection.getStats();

      if (!_isMonitoringSession(
        generation,
        connection,
      )) {
        return;
      }

      final Stopwatch? clock =
          _samplingClock;

      if (clock == null) {
        return;
      }

      final Duration elapsed =
          clock.elapsed;

      final _StatsSampleResult? result =
      _buildSample(
        reports: reports,
        elapsed: elapsed,
      );

      if (result == null) {
        return;
      }

      if (!_isMonitoringSession(
        generation,
        connection,
      )) {
        return;
      }

      _commitSample(
        result,
      );
    } catch (error, stackTrace) {
      if (_isMonitoringSession(
        generation,
        connection,
      )) {
        _reportError(
          'getStats',
          error,
          stackTrace,
        );
      }
    } finally {
      if (_activeSampleGeneration ==
          generation) {
        _activeSampleGeneration =
        null;
      }
    }
  }

  // ===========================================================
  // SAMPLE PARSING
  // ===========================================================

  _StatsSampleResult? _buildSample({
    required List<StatsReport> reports,
    required Duration elapsed,
  }) {
    if (reports.isEmpty) {
      return null;
    }

    final Set<String> selectedPairIds =
    <String>{};

    int remoteInboundRtt = 0;

    for (final StatsReport report
    in reports) {
      final Map<dynamic, dynamic> values =
          report.values;

      if (report.type ==
          _transportType) {
        final String? pairId =
        _readString(
          values[
          'selectedCandidatePairId'],
        );

        if (pairId != null &&
            pairId.isNotEmpty) {
          selectedPairIds.add(
            pairId,
          );
        }
      }

      if (report.type ==
          _remoteInboundRtpType) {
        final double? rawRtt =
        _readDouble(
          values[
          'roundTripTime'],
        );

        if (rawRtt != null &&
            rawRtt >= 0) {
          final int value =
          (rawRtt * 1000)
              .round();

          if (value >
              remoteInboundRtt) {
            remoteInboundRtt =
                value;
          }
        }
      }
    }

    int ping = 0;

    int jitter = 0;

    int packetsLost = 0;

    int packetsReceived = 0;

    int bytesSent = 0;

    int bytesReceived = 0;

    int videoBytesSent = 0;

    int audioBytesSent = 0;

    int fps = 0;

    int width = 0;

    int height = 0;

    int largestVideoArea = 0;

    bool meaningfulReportFound =
    false;

    for (final StatsReport report
    in reports) {
      final Map<dynamic, dynamic> values =
          report.values;

      final String type =
          report.type;

      if (type ==
          _candidatePairType) {
        final bool selected =
            selectedPairIds.contains(
              report.id,
            ) ||
                _readBool(
                  values['selected'],
                ) ||
                _readBool(
                  values['nominated'],
                );

        final String? state =
        _readString(
          values['state'],
        );

        if (selected &&
            state ==
                'succeeded') {
          final double? rawRtt =
          _readDouble(
            values[
            'currentRoundTripTime'],
          );

          if (rawRtt != null &&
              rawRtt >= 0) {
            final int value =
            (rawRtt * 1000)
                .round();

            if (value >
                ping) {
              ping =
                  value;
            }

            meaningfulReportFound =
            true;
          }
        }

        continue;
      }

      if (type ==
          _inboundRtpType) {
        meaningfulReportFound =
        true;

        final int receivedBytes =
        _nonNegativeInt(
          values['bytesReceived'],
        );

        bytesReceived +=
            receivedBytes;

        final int lost =
        _nonNegativeInt(
          values['packetsLost'],
        );

        final int receivedPackets =
        _nonNegativeInt(
          values['packetsReceived'],
        );

        packetsLost +=
            lost;

        packetsReceived +=
            receivedPackets;

        final double? rawJitter =
        _readDouble(
          values['jitter'],
        );

        if (rawJitter != null &&
            rawJitter >= 0) {
          final int jitterMs =
          (rawJitter * 1000)
              .round();

          if (jitterMs >
              jitter) {
            jitter =
                jitterMs;
          }
        }

        if (_isVideoReport(
          values,
        )) {
          final int candidateWidth =
          _nonNegativeInt(
            values['frameWidth'],
          );

          final int candidateHeight =
          _nonNegativeInt(
            values['frameHeight'],
          );

          final int candidateFps =
          _nonNegativeInt(
            values[
            'framesPerSecond'],
          );

          final int area =
              candidateWidth *
                  candidateHeight;

          if (area >
              largestVideoArea) {
            largestVideoArea =
                area;

            width =
                candidateWidth;

            height =
                candidateHeight;
          }

          if (candidateFps >
              fps) {
            fps =
                candidateFps;
          }
        }

        continue;
      }

      if (type ==
          _outboundRtpType) {
        meaningfulReportFound =
        true;

        final int sentBytes =
        _nonNegativeInt(
          values['bytesSent'],
        );

        bytesSent +=
            sentBytes;

        final String? mediaKind =
        _mediaKind(
          values,
        );

        if (mediaKind ==
            _videoKind) {
          videoBytesSent +=
              sentBytes;
        } else if (mediaKind ==
            _audioKind) {
          audioBytesSent +=
              sentBytes;
        }

        if (_isVideoReport(
          values,
        )) {
          final int candidateWidth =
          _nonNegativeInt(
            values['frameWidth'],
          );

          final int candidateHeight =
          _nonNegativeInt(
            values['frameHeight'],
          );

          final int candidateFps =
          _nonNegativeInt(
            values[
            'framesPerSecond'],
          );

          final int area =
              candidateWidth *
                  candidateHeight;

          if (area >
              largestVideoArea) {
            largestVideoArea =
                area;

            width =
                candidateWidth;

            height =
                candidateHeight;
          }

          if (candidateFps >
              fps) {
            fps =
                candidateFps;
          }
        }
      }
    }

    if (!meaningfulReportFound) {
      return null;
    }

    if (ping <= 0 &&
        remoteInboundRtt > 0) {
      ping =
          remoteInboundRtt;
    }

    double packetLoss = 0.0;

    final int packetTotal =
        packetsLost +
            packetsReceived;

    if (packetTotal > 0) {
      packetLoss =
          packetsLost /
              packetTotal *
              100.0;
    }

    if (!packetLoss.isFinite ||
        packetLoss < 0) {
      packetLoss = 0.0;
    } else if (packetLoss >
        100.0) {
      packetLoss = 100.0;
    }

    final Duration? previousElapsed =
        _lastSampleElapsed;

    double elapsedSeconds = 0.0;

    if (previousElapsed != null) {
      final int elapsedMicros =
          elapsed.inMicroseconds -
              previousElapsed
                  .inMicroseconds;

      if (elapsedMicros > 0) {
        elapsedSeconds =
            elapsedMicros /
                Duration
                    .microsecondsPerSecond;
      }
    }

    final double uploadBitrate =
    _bitrateKbps(
      currentBytes:
      bytesSent,
      previousBytes:
      _lastBytesSent,
      elapsedSeconds:
      elapsedSeconds,
    );

    final double downloadBitrate =
    _bitrateKbps(
      currentBytes:
      bytesReceived,
      previousBytes:
      _lastBytesReceived,
      elapsedSeconds:
      elapsedSeconds,
    );

    final double videoBitrate =
    _bitrateKbps(
      currentBytes:
      videoBytesSent,
      previousBytes:
      _lastVideoBytesSent,
      elapsedSeconds:
      elapsedSeconds,
    );

    final double audioBitrate =
    _bitrateKbps(
      currentBytes:
      audioBytesSent,
      previousBytes:
      _lastAudioBytesSent,
      elapsedSeconds:
      elapsedSeconds,
    );

    final double score =
    _qualityScore(
      ping: ping,
      jitter: jitter,
      packetLoss:
      packetLoss,
    );

    final CallStatsModel model =
    CallStatsModel(
      ping:
      ping,
      jitter:
      jitter,
      packetLoss:
      packetLoss,
      uploadBitrate:
      uploadBitrate,
      downloadBitrate:
      downloadBitrate,
      fps:
      fps,
      videoWidth:
      width,
      videoHeight:
      height,
      qualityScore:
      score,
      timestamp:
      DateTime.now().toUtc(),
    );

    return _StatsSampleResult(
      model:
      model,
      elapsed:
      elapsed,
      bytesSent:
      bytesSent,
      bytesReceived:
      bytesReceived,
      videoBytesSent:
      videoBytesSent,
      audioBytesSent:
      audioBytesSent,
      videoBitrate:
      videoBitrate,
      audioBitrate:
      audioBitrate,
    );
  }

  // ===========================================================
  // SAMPLE COMMIT
  // ===========================================================

  void _commitSample(
      _StatsSampleResult result,
      ) {
    _lastSampleElapsed =
        result.elapsed;

    _lastBytesSent =
        result.bytesSent;

    _lastBytesReceived =
        result.bytesReceived;

    _lastVideoBytesSent =
        result.videoBytesSent;

    _lastAudioBytesSent =
        result.audioBytesSent;

    _currentVideoBitrate =
        result.videoBitrate;

    _currentAudioBitrate =
        result.audioBitrate;

    final CallStatsModel next =
        result.model;

    _updateWeakNetworkState(
      next,
    );

    if (_sameStats(
      _currentStats,
      next,
    )) {
      return;
    }

    _currentStats =
        next;

    _history.add(
      next,
    );

    if (_history.length >
        _historyLimit) {
      _history.removeAt(
        0,
      );
    }

    _safeStatsCallback(
      onStatsUpdated,
      next,
      source:
      'onStatsUpdated',
    );

    _safeStatsCallback(
      onStatsChanged,
      next,
      source:
      'onStatsChanged',
    );

    _notifySafely();
  }

  // ===========================================================
  // WEAK NETWORK ALERT
  // ===========================================================

  void _updateWeakNetworkState(
      CallStatsModel stats,
      ) {
    final bool weak =
        stats.packetLoss > 10.0 ||
            stats.ping > 300 ||
            stats.jitter > 70;

    if (!weak) {
      _weakNetworkActive =
      false;

      return;
    }

    if (_weakNetworkActive) {
      return;
    }

    _weakNetworkActive =
    true;

    final Function(String)? callback =
        onWeakNetworkAlert;

    if (_disposed ||
        callback == null) {
      return;
    }

    final String message =
        'Weak network: '
        '${stats.ping}ms / '
        '${stats.packetLoss.toStringAsFixed(1)}% loss';

    try {
      callback(
        message,
      );
    } catch (error, stackTrace) {
      _reportError(
        'onWeakNetworkAlert',
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // RTP HELPERS
  // ===========================================================

  String? _mediaKind(
      Map<dynamic, dynamic> values,
      ) {
    final String? kind =
    _readString(
      values['kind'],
    );

    if (kind != null &&
        kind.isNotEmpty) {
      return kind.toLowerCase();
    }

    final String? mediaType =
    _readString(
      values['mediaType'],
    );

    return mediaType
        ?.toLowerCase();
  }

  bool _isVideoReport(
      Map<dynamic, dynamic> values,
      ) {
    if (_mediaKind(
      values,
    ) ==
        _videoKind) {
      return true;
    }

    return _nonNegativeInt(
      values['frameWidth'],
    ) >
        0 ||
        _nonNegativeInt(
          values['frameHeight'],
        ) >
            0 ||
        _nonNegativeInt(
          values[
          'framesPerSecond'],
        ) >
            0;
  }

  // ===========================================================
  // VALUE READERS
  // ===========================================================

  String? _readString(
      Object? value,
      ) {
    if (value is String) {
      final String normalized =
      value.trim();

      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    return null;
  }

  bool _readBool(
      Object? value,
      ) {
    if (value is bool) {
      return value;
    }

    if (value is String) {
      return value
          .trim()
          .toLowerCase() ==
          'true';
    }

    return false;
  }

  int _nonNegativeInt(
      Object? value,
      ) {
    final int? result =
    _readInt(
      value,
    );

    if (result == null ||
        result < 0) {
      return 0;
    }

    return result;
  }

  int? _readInt(
      Object? value,
      ) {
    if (value is int) {
      return value;
    }

    if (value is num &&
        value.isFinite) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(
        value.trim(),
      );
    }

    return null;
  }

  double? _readDouble(
      Object? value,
      ) {
    if (value is double) {
      if (value.isFinite) {
        return value;
      }

      return null;
    }

    if (value is num &&
        value.isFinite) {
      return value.toDouble();
    }

    if (value is String) {
      final double? parsed =
      double.tryParse(
        value.trim(),
      );

      if (parsed != null &&
          parsed.isFinite) {
        return parsed;
      }
    }

    return null;
  }

  // ===========================================================
  // BITRATE
  // ===========================================================

  double _bitrateKbps({
    required int currentBytes,
    required int previousBytes,
    required double elapsedSeconds,
  }) {
    if (elapsedSeconds <= 0) {
      return 0.0;
    }

    final int delta =
        currentBytes -
            previousBytes;

    if (delta < 0) {
      // RTP source/counter replacement.
      // This sample becomes the new baseline.
      return 0.0;
    }

    return delta *
        8.0 /
        1000.0 /
        elapsedSeconds;
  }

  // ===========================================================
  // QUALITY SCORE
  // ===========================================================

  double _qualityScore({
    required int ping,
    required int jitter,
    required double packetLoss,
  }) {
    double score =
    100.0;

    if (ping > 200) {
      score -= 40;
    } else if (ping > 100) {
      score -= 25;
    } else if (ping > 50) {
      score -= 10;
    }

    if (packetLoss > 10) {
      score -= 50;
    } else if (packetLoss > 3) {
      score -= 30;
    } else if (packetLoss > 1) {
      score -= 15;
    }

    if (jitter > 70) {
      score -= 20;
    } else if (jitter > 30) {
      score -= 10;
    }

    return score
        .clamp(
      0.0,
      100.0,
    )
        .toDouble();
  }

  // ===========================================================
  // STATS COMPARISON
  // ===========================================================

  bool _sameStats(
      CallStatsModel first,
      CallStatsModel second,
      ) {
    return first.ping ==
        second.ping &&
        first.jitter ==
            second.jitter &&
        first.packetLoss ==
            second.packetLoss &&
        first.uploadBitrate ==
            second.uploadBitrate &&
        first.downloadBitrate ==
            second.downloadBitrate &&
        first.fps ==
            second.fps &&
        first.videoWidth ==
            second.videoWidth &&
        first.videoHeight ==
            second.videoHeight &&
        first.qualityScore ==
            second.qualityScore;
  }

  // ===========================================================
  // CALLBACK SAFETY
  // ===========================================================

  void _safeStatsCallback(
      Function(CallStatsModel)? callback,
      CallStatsModel value, {
        required String source,
      }) {
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
        source,
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // SESSION VALIDATION
  // ===========================================================

  bool _isMonitoringSession(
      int generation,
      RTCPeerConnection connection,
      ) {
    return !_disposed &&
        generation ==
            _generation &&
        identical(
          _connection,
          connection,
        );
  }

  // ===========================================================
  // STOP MONITORING
  // ===========================================================

  void stopMonitoring() {
    if (_disposed) {
      return;
    }

    _generation++;

    _timer?.cancel();

    _timer =
    null;

    _connection =
    null;

    _activeSampleGeneration =
    null;

    _samplingClock?.stop();

    _samplingClock =
    null;

    _resetSamplingBaselines();

    _weakNetworkActive =
    false;
  }

  // ===========================================================
  // RESET BASELINES
  // ===========================================================

  void _resetSamplingBaselines() {
    _lastBytesSent =
    0;

    _lastBytesReceived =
    0;

    _lastVideoBytesSent =
    0;

    _lastAudioBytesSent =
    0;

    _lastSampleElapsed =
    null;

    _currentVideoBitrate =
    0.0;

    _currentAudioBitrate =
    0.0;
  }

  // ===========================================================
  // RESET
  // ===========================================================

  void reset() {
    if (_disposed) {
      return;
    }

    stopMonitoring();

    _initialized =
    false;

    _currentStats =
        CallStatsModel.initial();

    _history.clear();

    _weakNetworkActive =
    false;

    _notifySafely();
  }

  // ===========================================================
  // SAFE NOTIFY
  // ===========================================================

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ===========================================================
  // LOGGING
  // ===========================================================

  void _reportError(
      String source,
      Object error,
      StackTrace stackTrace,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[StatsManager/$source] '
          'error: $error',
    );

    debugPrintStack(
      label:
      'JR CALL '
          '[StatsManager/$source]',
      stackTrace:
      stackTrace,
    );
  }

  // ===========================================================
  // DISPOSE
  // ===========================================================

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed =
    true;

    _generation++;

    _timer?.cancel();

    _timer =
    null;

    _connection =
    null;

    _activeSampleGeneration =
    null;

    _samplingClock?.stop();

    _samplingClock =
    null;

    _resetSamplingBaselines();

    _weakNetworkActive =
    false;

    onStatsChanged =
    null;

    onStatsUpdated =
    null;

    onWeakNetworkAlert =
    null;

    super.dispose();
  }
}

/// ===========================================================
/// INTERNAL PARSED SAMPLE
/// ===========================================================

class _StatsSampleResult {
  final CallStatsModel model;

  final Duration elapsed;

  final int bytesSent;

  final int bytesReceived;

  final int videoBytesSent;

  final int audioBytesSent;

  final double videoBitrate;

  final double audioBitrate;

  const _StatsSampleResult({
    required this.model,
    required this.elapsed,
    required this.bytesSent,
    required this.bytesReceived,
    required this.videoBytesSent,
    required this.audioBytesSent,
    required this.videoBitrate,
    required this.audioBitrate,
  });
}

// ===============================================================
// END OF FILE
//
// FILE 20 FINAL GUARANTEES:
//
// ✓ Existing CallStatsModel public API preserved.
// ✓ Existing StatsManager public APIs preserved.
// ✓ RTCPeerConnection.getStats() remains sole WebRTC stats source.
// ✓ Old async stats cannot publish into a later call.
// ✓ Stop/reset/new monitoring invalidates stale samples.
// ✓ Sample concurrency is generation-safe.
// ✓ Existing 2-second monitoring cadence preserved.
// ✓ Immediate first sample preserved.
// ✓ Monotonic Stopwatch used for bitrate timing.
// ✓ Wall-clock changes cannot corrupt bitrate calculation.
// ✓ First sample establishes counters without fake bitrate.
// ✓ RTP source replacement handled safely.
// ✓ Total upload/download bitrate remains in kbps.
// ✓ Actual outbound audio bitrate tracked.
// ✓ Actual outbound video bitrate tracked.
// ✓ currentAudioBitrate is no longer hard-coded to zero.
// ✓ Selected/nominated candidate-pair RTT parsed.
// ✓ Remote-inbound RTT used only as WebRTC fallback.
// ✓ Inbound RTP packet-loss aggregation preserved.
// ✓ Inbound jitter uses worst valid observed value.
// ✓ Multiple RTP reports aggregated.
// ✓ Video geometry/FPS parsed defensively.
// ✓ Empty/no-useful report does not overwrite good stats.
// ✓ No NetworkManager values mixed into WebRTC call telemetry.
// ✓ No fabricated stats introduced.
// ✓ Weak-network alert is edge-triggered.
// ✓ Weak alert does not spam every two seconds.
// ✓ Callback failures cannot stop monitoring.
// ✓ History remains bounded to 50.
// ✓ History is exposed as an unmodifiable typed list.
// ✓ reset remains reusable.
// ✓ dispose remains terminal.
// ✓ No PeerConnection mutation.
// ✓ No bitrate mutation.
// ✓ No ICE/signaling/recovery ownership.
// ✓ No media/lifecycle/UI ownership.
// ✓ No UI/design changes.
//
// STATUS:
// FILE 20 CORRECTED VERIFICATION VERSION.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 21
// lib/services/call/bitrate_controller.dart
// ===============================================================