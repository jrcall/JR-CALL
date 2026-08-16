import 'dart:async';

import 'package:flutter/foundation.dart';

/// ===========================================================
/// JR CALL
/// File: call_recorder.dart
/// Description:
/// Call Recorder Service
///
/// NOTE:
/// This is a service structure only.
/// Actual recording implementation will be added later
/// using flutter_webrtc / native platform APIs.
///
/// Used by:
/// - ai_call_engine.dart
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// ===========================================================

class CallRecorder extends ChangeNotifier {
  CallRecorder._();

  static final CallRecorder instance = CallRecorder._();

  bool _isRecording = false;

  bool _isPaused = false;

  String? _filePath;

  DateTime? _startTime;

  Timer? _timer;

  Duration _duration = Duration.zero;

  /// ==========================
  /// Getters
  /// ==========================

  bool get isRecording => _isRecording;

  bool get isPaused => _isPaused;

  Duration get duration => _duration;

  String? get filePath => _filePath;

  /// ==========================
  /// Start Recording
  /// ==========================

  Future<void> start({String? savePath}) async {
    if (_isRecording) return;

    _isRecording = true;
    _isPaused = false;

    _filePath =
        savePath ?? "JR_CALL_${DateTime.now().millisecondsSinceEpoch}.mp4";

    _startTime = DateTime.now();

    _duration = Duration.zero;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) {
        _duration = DateTime.now().difference(_startTime!);
        notifyListeners();
      }
    });

    notifyListeners();
  }

  /// ==========================
  /// Pause Recording
  /// ==========================

  Future<void> pause() async {
    if (!_isRecording) return;

    _isPaused = true;

    notifyListeners();
  }

  /// ==========================
  /// Resume Recording
  /// ==========================

  Future<void> resume() async {
    if (!_isRecording) return;

    _isPaused = false;

    notifyListeners();
  }

  /// ==========================
  /// Stop Recording
  /// ==========================

  Future<String?> stop() async {
    if (!_isRecording) return null;

    _timer?.cancel();

    _isRecording = false;
    _isPaused = false;

    final result = _filePath;

    notifyListeners();

    return result;
  }

  /// ==========================
  /// Cancel Recording
  /// ==========================

  Future<void> cancel() async {
    _timer?.cancel();

    _isRecording = false;
    _isPaused = false;

    _filePath = null;

    _duration = Duration.zero;

    notifyListeners();
  }

  /// ==========================
  /// Reset
  /// ==========================

  Future<void> reset() async {
    await cancel();
  }

  /// ==========================
  /// Dispose
  /// ==========================

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
