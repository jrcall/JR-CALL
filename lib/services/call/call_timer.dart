import 'dart:async';

/// ===========================================================
/// JR CALL
/// File: call_timer.dart
/// Location: lib/services/call/call_timer.dart
///
/// FINAL PRODUCTION CALL DURATION TIMER.
///
/// Used by:
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// - call_timer_widget.dart
/// - call_history_model.dart
///
/// IMPORTANT:
///
/// - Stopwatch is the authoritative elapsed-time source.
/// - Timer.periodic only emits presentation updates.
/// - Background/event-loop delay cannot corrupt call duration.
/// - Device wall-clock changes cannot affect elapsed duration.
/// - pause/stop preserve elapsed duration.
/// - reset clears elapsed duration.
/// - dispose is terminal for this singleton stream.
/// ===========================================================

class CallTimer {
  CallTimer._();

  static final CallTimer instance =
  CallTimer._();

  // ===========================================================
  // CONFIGURATION
  // ===========================================================

  static const Duration _tickInterval =
  Duration(seconds: 1);

  // ===========================================================
  // TIME SOURCE
  // ===========================================================

  final Stopwatch _stopwatch =
  Stopwatch();

  Timer? _timer;

  int _lastEmittedSeconds = 0;

  bool _disposed = false;

  // ===========================================================
  // STREAM
  // ===========================================================

  final StreamController<Duration>
  _controller =
  StreamController<Duration>.broadcast();

  Stream<Duration> get stream =>
      _controller.stream;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  Duration get duration =>
      Duration(
        seconds:
        _stopwatch.elapsed.inSeconds,
      );

  bool get isRunning =>
      _stopwatch.isRunning;

  int get totalSeconds =>
      _stopwatch.elapsed.inSeconds;

  int get elapsedSeconds =>
      _stopwatch.elapsed.inSeconds;

  // ===========================================================
  // START
  // ===========================================================

  void start() {
    _ensureUsable();

    if (_stopwatch.isRunning) {
      return;
    }

    _stopwatch.start();

    _lastEmittedSeconds =
        _stopwatch.elapsed.inSeconds;

    _startTicker();
  }

  // ===========================================================
  // TICKER
  //
  // The ticker never owns elapsed-time calculation.
  //
  // It only publishes the current Stopwatch value.
  // ===========================================================

  void _startTicker() {
    _timer?.cancel();

    _timer =
        Timer.periodic(
          _tickInterval,
              (_) {
            _emitCurrentDuration();
          },
        );
  }

  void _emitCurrentDuration({
    bool force = false,
  }) {
    if (_disposed ||
        _controller.isClosed) {
      return;
    }

    final int seconds =
        _stopwatch.elapsed.inSeconds;

    if (!force &&
        seconds ==
            _lastEmittedSeconds) {
      return;
    }

    _lastEmittedSeconds =
        seconds;

    _controller.add(
      Duration(
        seconds: seconds,
      ),
    );
  }

  // ===========================================================
  // PAUSE
  // ===========================================================

  void pause() {
    if (_disposed) {
      return;
    }

    _timer?.cancel();

    _timer =
    null;

    _stopwatch.stop();
  }

  // ===========================================================
  // RESUME
  // ===========================================================

  void resume() {
    _ensureUsable();

    if (_stopwatch.isRunning) {
      return;
    }

    start();
  }

  // ===========================================================
  // STOP
  //
  // Stop preserves elapsed duration.
  // ===========================================================

  void stop() {
    if (_disposed) {
      return;
    }

    _timer?.cancel();

    _timer =
    null;

    _stopwatch.stop();
  }

  // ===========================================================
  // RESET
  // ===========================================================

  void reset() {
    if (_disposed) {
      return;
    }

    _timer?.cancel();

    _timer =
    null;

    _stopwatch
      ..stop()
      ..reset();

    _lastEmittedSeconds =
    0;

    _emitCurrentDuration(
      force: true,
    );
  }

  // ===========================================================
  // RESTART
  // ===========================================================

  void restart() {
    _ensureUsable();

    reset();

    start();
  }

  // ===========================================================
  // FORMATTED TIME
  // ===========================================================

  String get formattedTime {
    final Duration current =
        duration;

    final int hours =
        current.inHours;

    final String minutes =
    (current.inMinutes % 60)
        .toString()
        .padLeft(
      2,
      '0',
    );

    final String seconds =
    (current.inSeconds % 60)
        .toString()
        .padLeft(
      2,
      '0',
    );

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '$minutes:'
          '$seconds';
    }

    return '$minutes:$seconds';
  }

  // ===========================================================
  // INTERNAL VALIDATION
  // ===========================================================

  void _ensureUsable() {
    if (_disposed) {
      throw StateError(
        'CallTimer has already been disposed.',
      );
    }
  }

  // ===========================================================
  // DISPOSE
  //
  // IMPORTANT:
  //
  // This singleton's dispose is terminal because the broadcast
  // StreamController is closed.
  //
  // Normal per-call cleanup must use reset()/stop(), not dispose().
  // ===========================================================

  void dispose() {
    if (_disposed) {
      return;
    }

    _timer?.cancel();

    _timer =
    null;

    _stopwatch.stop();

    _disposed =
    true;

    if (!_controller.isClosed) {
      unawaited(
        _controller.close(),
      );
    }
  }
}

// ===============================================================
// END OF FILE
//
// FILE 26 FINAL GUARANTEES:
//
// ✓ Existing public API preserved.
// ✓ Existing singleton preserved.
// ✓ Existing broadcast stream preserved.
// ✓ Stopwatch is authoritative elapsed-time source.
// ✓ Timer.periodic no longer increments duration manually.
// ✓ Background timer throttling cannot corrupt duration.
// ✓ Event-loop stalls cannot cause lost call seconds.
// ✓ Wall-clock changes cannot affect elapsed call duration.
// ✓ pause preserves elapsed duration.
// ✓ stop preserves elapsed duration.
// ✓ resume continues from preserved duration.
// ✓ reset returns duration to zero.
// ✓ restart resets then starts.
// ✓ duration/totalSeconds/elapsedSeconds stay consistent.
// ✓ formattedTime stays consistent with real elapsed duration.
// ✓ Duplicate same-second stream emissions suppressed.
// ✓ Reset emits zero safely.
// ✓ No extra timer beyond existing 1-second presentation tick.
// ✓ dispose remains terminal.
// ✓ Per-call reuse must use reset/stop, not dispose.
// ✓ No network ownership.
// ✓ No WebRTC ownership.
// ✓ No signaling/ICE/recovery ownership.
// ✓ No media ownership.
// ✓ No UI/design changes.
//
// STATUS:
// CALL TIMER FINALIZED.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 27
// lib/services/call/webrtc_service.dart
// ===============================================================