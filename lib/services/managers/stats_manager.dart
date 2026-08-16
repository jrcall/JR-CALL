import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'network_manager.dart';

/// ===========================================================
/// JR CALL
/// File: stats_manager.dart
/// Location: lib/services/managers/stats_manager.dart
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
      timestamp: DateTime.now(),
    );
  }
}

class StatsManager extends ChangeNotifier {
  StatsManager._();

  static final StatsManager instance = StatsManager._();

  static const int _historyLimit = 50;

  Timer? _timer;

  bool _initialized = false;
  bool _sampleRunning = false;

  RTCPeerConnection? _connection;

  int _lastBytesSent = 0;
  int _lastBytesReceived = 0;

  DateTime? _lastStatsTime;

  CallStatsModel _currentStats = CallStatsModel.initial();

  final List<CallStatsModel> _history = [];

  Function(CallStatsModel)? onStatsChanged;

  Function(CallStatsModel)? onStatsUpdated;

  Function(String)? onWeakNetworkAlert;

  bool get isInitialized => _initialized;

  CallStatsModel get currentStats => _currentStats;

  List<CallStatsModel> get statsHistory => List.unmodifiable(_history);

  int get ping => _currentStats.ping;

  int get jitter => _currentStats.jitter;

  double get packetLoss => _currentStats.packetLoss;

  double get uploadBitrate => _currentStats.uploadBitrate;

  double get downloadBitrate => _currentStats.downloadBitrate;

  int get currentFps => _currentStats.fps;

  int get videoWidth => _currentStats.videoWidth;

  int get videoHeight => _currentStats.videoHeight;

  double get qualityScore => _currentStats.qualityScore;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    notifyListeners();
  }

  Future<Map<String, dynamic>> getLatestStats() async {
    final stats = _currentStats;

    return {
      'rtt': stats.ping,
      'jitter': stats.jitter,
      'packetLoss': stats.packetLoss,
      'uploadBitrate': stats.uploadBitrate,
      'downloadBitrate': stats.downloadBitrate,
      'currentVideoBitrate': stats.uploadBitrate,
      'currentAudioBitrate': 0.0,
      'fps': stats.fps,
      'videoWidth': stats.videoWidth,
      'videoHeight': stats.videoHeight,
      'qualityScore': stats.qualityScore,
      'timestamp': stats.timestamp.toIso8601String(),
    };
  }

  void startMonitoring(RTCPeerConnection? peerConnection) {
    stopMonitoring();

    if (peerConnection == null) {
      return;
    }

    _connection = peerConnection;

    _lastBytesSent = 0;
    _lastBytesReceived = 0;
    _lastStatsTime = null;

    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_collectSample());
    });

    unawaited(_collectSample());
  }

  Future<void> _collectSample() async {
    if (_sampleRunning) {
      return;
    }

    final connection = _connection;

    if (connection == null) {
      return;
    }

    _sampleRunning = true;

    try {
      final reports = await connection.getStats();

      _parse(reports);
    } catch (error) {
      debugPrint('StatsManager getStats failed: $error');
    } finally {
      _sampleRunning = false;
    }
  }

  void _parse(List<StatsReport> reports) {
    final now = DateTime.now();

    var ping = 0;
    var jitter = 0;

    var packetsLost = 0;
    var packetsReceived = 0;

    var bytesSent = 0;
    var bytesReceived = 0;

    var fps = 0;
    var width = 0;
    var height = 0;

    for (final report in reports) {
      final values = report.values;

      if (report.type == 'candidate-pair') {
        final selected = values['selected'] == true;

        final succeeded = values['state'] == 'succeeded';

        if (selected || succeeded) {
          final rawRtt = values['currentRoundTripTime'];

          if (rawRtt is num) {
            ping = (rawRtt.toDouble() * 1000).round();
          }
        }
      }

      if (report.type == 'inbound-rtp') {
        final rawBytes = values['bytesReceived'];

        if (rawBytes is num) {
          bytesReceived += rawBytes.toInt();
        }

        final rawLost = values['packetsLost'];

        if (rawLost is num) {
          packetsLost += rawLost.toInt();
        }

        final rawReceived = values['packetsReceived'];

        if (rawReceived is num) {
          packetsReceived += rawReceived.toInt();
        }

        final rawJitter = values['jitter'];

        if (rawJitter is num) {
          jitter = (rawJitter.toDouble() * 1000).round();
        }

        width = _readInt(values['frameWidth']) ?? width;

        height = _readInt(values['frameHeight']) ?? height;

        fps = _readInt(values['framesPerSecond']) ?? fps;
      }

      if (report.type == 'outbound-rtp') {
        final rawBytes = values['bytesSent'];

        if (rawBytes is num) {
          bytesSent += rawBytes.toInt();
        }

        width = _readInt(values['frameWidth']) ?? width;

        height = _readInt(values['frameHeight']) ?? height;

        fps = _readInt(values['framesPerSecond']) ?? fps;
      }
    }

    var packetLoss = 0.0;

    final packetTotal = packetsLost + packetsReceived;

    if (packetTotal > 0) {
      packetLoss = packetsLost / packetTotal * 100;
    }

    var uploadBitrate = 0.0;
    var downloadBitrate = 0.0;

    final previousTime = _lastStatsTime;

    if (previousTime != null) {
      final seconds = now.difference(previousTime).inMilliseconds / 1000.0;

      if (seconds > 0) {
        final sentDelta = bytesSent - _lastBytesSent;

        final receivedDelta = bytesReceived - _lastBytesReceived;

        if (sentDelta >= 0) {
          uploadBitrate = sentDelta * 8 / 1000 / seconds;
        }

        if (receivedDelta >= 0) {
          downloadBitrate = receivedDelta * 8 / 1000 / seconds;
        }
      }
    }

    _lastBytesSent = bytesSent;
    _lastBytesReceived = bytesReceived;

    _lastStatsTime = now;

    final network = NetworkManager.instance.currentNetwork;

    if (ping == 0 && network.ping > 0) {
      ping = network.ping;
    }

    if (packetLoss == 0 && network.packetLoss > 0) {
      packetLoss = network.packetLoss;
    }

    if (jitter == 0 && network.jitter > 0) {
      jitter = network.jitter;
    }

    final qualityScore = _qualityScore(
      ping: ping,
      jitter: jitter,
      packetLoss: packetLoss,
    );

    final next = CallStatsModel(
      ping: ping,
      jitter: jitter,
      packetLoss: packetLoss,
      uploadBitrate: uploadBitrate,
      downloadBitrate: downloadBitrate,
      fps: fps,
      videoWidth: width,
      videoHeight: height,
      qualityScore: qualityScore,
      timestamp: now,
    );

    if (_sameStats(_currentStats, next)) {
      return;
    }

    _currentStats = next;

    _history.add(next);

    if (_history.length > _historyLimit) {
      _history.removeAt(0);
    }

    if (packetLoss > 10 || ping > 300) {
      onWeakNetworkAlert?.call(
        'Weak network: '
        '${ping}ms / '
        '${packetLoss.toStringAsFixed(1)}% loss',
      );
    }

    onStatsUpdated?.call(next);
    onStatsChanged?.call(next);

    notifyListeners();
  }

  int? _readInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return null;
  }

  double _qualityScore({
    required int ping,
    required int jitter,
    required double packetLoss,
  }) {
    var score = 100.0;

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

    return score.clamp(0.0, 100.0).toDouble();
  }

  bool _sameStats(CallStatsModel a, CallStatsModel b) {
    return a.ping == b.ping &&
        a.jitter == b.jitter &&
        a.packetLoss == b.packetLoss &&
        a.uploadBitrate == b.uploadBitrate &&
        a.downloadBitrate == b.downloadBitrate &&
        a.fps == b.fps &&
        a.videoWidth == b.videoWidth &&
        a.videoHeight == b.videoHeight &&
        a.qualityScore == b.qualityScore;
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;

    _connection = null;
    _sampleRunning = false;
  }

  void reset() {
    stopMonitoring();

    _lastBytesSent = 0;
    _lastBytesReceived = 0;
    _lastStatsTime = null;

    _initialized = false;

    _currentStats = CallStatsModel.initial();

    _history.clear();

    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;

    _connection = null;

    onStatsChanged = null;
    onStatsUpdated = null;
    onWeakNetworkAlert = null;

    super.dispose();
  }
}
