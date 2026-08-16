import 'dart:async';

/// ===========================================================
/// JR CALL
/// File: call_timer.dart
/// Description:
/// Manages call duration.
/// Used by:
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// - call_timer_widget.dart
/// - call_history_model.dart
/// ===========================================================

class CallTimer {
  CallTimer._();

  static final CallTimer instance = CallTimer._();

  Timer? _timer;

  Duration _duration = Duration.zero;

  bool _isRunning = false;

  final StreamController<Duration> _controller =
      StreamController<Duration>.broadcast();

  /// Stream
  Stream<Duration> get stream => _controller.stream;

  /// Current Duration
  Duration get duration => _duration;

  /// Running Status
  bool get isRunning => _isRunning;

  /// Total Seconds
  int get totalSeconds => _duration.inSeconds;

  /// Elapsed Seconds (Required by CallQualityMonitor)
  int get elapsedSeconds => _duration.inSeconds;

  /// Start Timer
  void start() {
    if (_isRunning) return;

    _isRunning = true;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _duration += const Duration(seconds: 1);

      if (!_controller.isClosed) {
        _controller.add(_duration);
      }
    });
  }

  /// Pause Timer
  void pause() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  /// Resume Timer
  void resume() {
    if (_isRunning) return;
    start();
  }

  /// Stop Timer
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  /// Reset Timer
  void reset() {
    stop();

    _duration = Duration.zero;

    if (!_controller.isClosed) {
      _controller.add(_duration);
    }
  }

  /// Restart Timer
  void restart() {
    reset();
    start();
  }

  /// Formatted Time (HH:MM:SS)
  String get formattedTime {
    final hours = _duration.inHours;

    final minutes = (_duration.inMinutes % 60).toString().padLeft(2, '0');

    final seconds = (_duration.inSeconds % 60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  /// Dispose
  void dispose() {
    stop();
    _controller.close();
  }
}
