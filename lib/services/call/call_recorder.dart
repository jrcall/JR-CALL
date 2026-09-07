// ===============================================================
// JR CALL
// File: call_recorder.dart
// Location: lib/services/call/call_recorder.dart
//
// MASTER PRODUCTION CALL RECORDER COORDINATOR
//
// RESPONSIBILITIES:
//
// - Recording-session state coordination.
// - Explicit user-consent gate.
// - Recording backend coordination.
// - Pause / resume coordination when backend supports it.
// - Monotonic recording-duration tracking.
// - Output-path state.
// - Serialized recorder operations.
// - Lifecycle-safe cancel / reset / disposal.
//
// OWNERSHIP:
//
// CallRecorder:
// - Recording orchestration and presentation state only.
//
// CallRecordingBackend:
// - Actual media recording implementation.
// - Native/WebRTC recorder lifecycle.
// - Platform-specific recorder requirements.
//
// WebRTCService / CallService:
// - Own active call MediaStream / MediaStreamTrack.
// - Own PeerConnection and call media transport.
//
// UI:
// - Must obtain and visibly communicate explicit recording consent
//   before calling setConsentGranted(true).
// - Must visibly show recording state while isRecording == true.
//
// IMPORTANT:
//
// - This file NEVER pretends a file is being recorded.
// - No backend = recording cannot start.
// - No consent = recording cannot start.
// - Call recording must remain optional.
// - Recording failure must never terminate the active call.
// - No covert recording.
// - No WebRTC ownership duplicated here.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

// ===============================================================
// RECORDING BACKEND CONTRACT
// ===============================================================

abstract interface class CallRecordingBackend {
  /// Whether this backend can genuinely pause/resume the
  /// underlying media recording.
  bool get supportsPause;

  /// Starts actual media recording.
  ///
  /// The backend is responsible for:
  /// - using the real call media it is explicitly given/bound to;
  /// - platform recorder APIs;
  /// - filesystem preparation;
  /// - platform permissions where required;
  /// - writing real media data to [savePath].
  Future<void> start({
    required String savePath,
  });

  /// Pauses actual recording.
  ///
  /// Called only when [supportsPause] is true.
  Future<void> pause();

  /// Resumes actual recording.
  ///
  /// Called only when [supportsPause] is true.
  Future<void> resume();

  /// Finalizes the real recording file.
  Future<void> stop();

  /// Cancels the recording and performs backend cleanup.
  Future<void> cancel();
}

// ===============================================================
// CALL RECORDER
// ===============================================================

class CallRecorder extends ChangeNotifier {
  CallRecorder._();

  static final CallRecorder instance = CallRecorder._();

  // =============================================================
  // BACKEND
  // =============================================================

  CallRecordingBackend? _backend;

  // =============================================================
  // STATE
  // =============================================================

  bool _isRecording = false;

  bool _isPaused = false;

  bool _consentGranted = false;

  bool _isDisposed = false;

  String? _filePath;

  String? _lastError;

  // =============================================================
  // DURATION
  // =============================================================

  final Stopwatch _stopwatch = Stopwatch();

  Timer? _ticker;

  int _lastEmittedSecond = 0;

  static const Duration _tickInterval = Duration(
    seconds: 1,
  );

  // =============================================================
  // SERIALIZED OPERATION QUEUE
  // =============================================================

  Future<void> _operationQueue = Future<void>.value();

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isRecording => _isRecording;

  bool get isPaused => _isPaused;

  bool get consentGranted => _consentGranted;

  bool get hasBackend => _backend != null;

  bool get supportsPause {
    return _backend?.supportsPause ?? false;
  }

  bool get isDisposed => _isDisposed;

  Duration get duration => _stopwatch.elapsed;

  String? get filePath => _filePath;

  String? get lastError => _lastError;

  // =============================================================
  // BACKEND BINDING
  // =============================================================

  /// Binds the actual recording implementation.
  ///
  /// This method must NOT be used to create a second call-media
  /// pipeline. The backend must integrate with the existing
  /// WebRTCService / CallService media ownership.
  void configureBackend(
      CallRecordingBackend backend,
      ) {
    _ensureUsable();

    if (_isRecording) {
      throw StateError(
        'Cannot replace the recording backend while recording.',
      );
    }

    _backend = backend;

    _lastError = null;

    _notifySafely();
  }

  void clearBackend() {
    _ensureUsable();

    if (_isRecording) {
      throw StateError(
        'Cannot clear the recording backend while recording.',
      );
    }

    if (_backend == null) {
      return;
    }

    _backend = null;

    _notifySafely();
  }

  // =============================================================
  // CONSENT
  // =============================================================

  /// UI must call this ONLY after explicit recording consent.
  ///
  /// Consent UI/wording belongs to the presentation layer.
  Future<void> setConsentGranted(
      bool granted,
      ) async {
    if (_isDisposed) {
      return;
    }

    if (!granted && _isRecording) {
      // Revoking consent immediately ends recording.
      await cancel();
    }

    if (_consentGranted == granted) {
      return;
    }

    _consentGranted = granted;

    _notifySafely();
  }

  // =============================================================
  // START RECORDING
  // =============================================================

  Future<void> start({
    String? savePath,
  }) async {
    if (_isDisposed) {
      return;
    }

    await _runSerialized<void>(
      'start',
          () async {
        if (_isRecording) {
          return;
        }

        _lastError = null;

        if (!_consentGranted) {
          _setError(
            'Recording was not started because explicit consent '
                'has not been confirmed.',
          );

          return;
        }

        final CallRecordingBackend? backend = _backend;

        if (backend == null) {
          _setError(
            'Recording backend is not configured.',
          );

          return;
        }

        final String resolvedPath = _resolveSavePath(
          savePath,
        );

        try {
          await backend.start(
            savePath: resolvedPath,
          );

          _filePath = resolvedPath;

          _isRecording = true;

          _isPaused = false;

          _stopwatch
            ..stop()
            ..reset()
            ..start();

          _lastEmittedSecond = 0;

          _startTicker();
        } catch (error, stackTrace) {
          _reportError(
            'start',
            error,
            stackTrace,
          );

          _setError(
            'Recording could not be started.',
          );

          _clearSessionState(
            clearPath: true,
            clearDuration: true,
          );
        }
      },
    );
  }

  // =============================================================
  // PAUSE RECORDING
  // =============================================================

  Future<void> pause() async {
    if (_isDisposed) {
      return;
    }

    await _runSerialized<void>(
      'pause',
          () async {
        if (!_isRecording || _isPaused) {
          return;
        }

        final CallRecordingBackend? backend = _backend;

        if (backend == null) {
          return;
        }

        if (!backend.supportsPause) {
          _setError(
            'The active recording backend does not support pause.',
          );

          return;
        }

        try {
          await backend.pause();

          _stopwatch.stop();

          _isPaused = true;
        } catch (error, stackTrace) {
          _reportError(
            'pause',
            error,
            stackTrace,
          );

          _setError(
            'Recording could not be paused.',
          );
        }
      },
    );
  }

  // =============================================================
  // RESUME RECORDING
  // =============================================================

  Future<void> resume() async {
    if (_isDisposed) {
      return;
    }

    await _runSerialized<void>(
      'resume',
          () async {
        if (!_isRecording || !_isPaused) {
          return;
        }

        final CallRecordingBackend? backend = _backend;

        if (backend == null) {
          return;
        }

        if (!backend.supportsPause) {
          _setError(
            'The active recording backend does not support resume.',
          );

          return;
        }

        try {
          await backend.resume();

          _stopwatch.start();

          _isPaused = false;
        } catch (error, stackTrace) {
          _reportError(
            'resume',
            error,
            stackTrace,
          );

          _setError(
            'Recording could not be resumed.',
          );
        }
      },
    );
  }

  // =============================================================
  // STOP RECORDING
  // =============================================================

  Future<String?> stop() async {
    if (_isDisposed) {
      return null;
    }

    return _runSerialized<String?>(
      'stop',
          () async {
        if (!_isRecording) {
          return null;
        }

        final CallRecordingBackend? backend = _backend;

        if (backend == null) {
          _clearSessionState(
            clearPath: true,
            clearDuration: false,
          );

          return null;
        }

        final String? completedPath = _filePath;

        _stopTicker();

        _stopwatch.stop();

        try {
          await backend.stop();

          _isRecording = false;

          _isPaused = false;

          // Consent is session-specific.
          _consentGranted = false;

          return completedPath;
        } catch (error, stackTrace) {
          _reportError(
            'stop',
            error,
            stackTrace,
          );

          _setError(
            'Recording could not be finalized.',
          );

          await _cancelBackendBestEffort(
            backend,
          );

          _isRecording = false;

          _isPaused = false;

          _filePath = null;

          _consentGranted = false;

          return null;
        }
      },
    );
  }

  // =============================================================
  // CANCEL RECORDING
  // =============================================================

  Future<void> cancel() async {
    if (_isDisposed) {
      return;
    }

    await _runSerialized<void>(
      'cancel',
          () async {
        final CallRecordingBackend? backend = _backend;

        _stopTicker();

        _stopwatch.stop();

        if (_isRecording && backend != null) {
          await _cancelBackendBestEffort(
            backend,
          );
        }

        _clearSessionState(
          clearPath: true,
          clearDuration: true,
        );

        _consentGranted = false;
      },
    );
  }

  // =============================================================
  // RESET
  // =============================================================

  Future<void> reset() async {
    await cancel();
  }

  // =============================================================
  // TIMER
  // =============================================================

  void _startTicker() {
    _ticker?.cancel();

    _ticker = Timer.periodic(
      _tickInterval,
          (_) {
        if (_isDisposed ||
            !_isRecording ||
            _isPaused) {
          return;
        }

        final int seconds = _stopwatch.elapsed.inSeconds;

        if (seconds == _lastEmittedSecond) {
          return;
        }

        _lastEmittedSecond = seconds;

        _notifySafely();
      },
    );
  }

  void _stopTicker() {
    _ticker?.cancel();

    _ticker = null;
  }

  // =============================================================
  // INTERNAL SESSION STATE
  // =============================================================

  void _clearSessionState({
    required bool clearPath,
    required bool clearDuration,
  }) {
    _stopTicker();

    _isRecording = false;

    _isPaused = false;

    if (clearPath) {
      _filePath = null;
    }

    if (clearDuration) {
      _stopwatch
        ..stop()
        ..reset();

      _lastEmittedSecond = 0;
    }
  }

  // =============================================================
  // SAVE PATH
  // =============================================================

  String _resolveSavePath(
      String? savePath,
      ) {
    final String normalizedPath = savePath?.trim() ?? '';

    if (normalizedPath.isNotEmpty) {
      return normalizedPath;
    }

    // Compatibility with the previous public behavior.
    //
    // Actual parent-directory creation and filesystem permission
    // belong to the concrete recording backend.
    return 'JR_CALL_'
        '${DateTime.now().millisecondsSinceEpoch}'
        '.mp4';
  }

  // =============================================================
  // BACKEND CLEANUP
  // =============================================================

  Future<void> _cancelBackendBestEffort(
      CallRecordingBackend backend,
      ) async {
    try {
      await backend.cancel();
    } catch (error, stackTrace) {
      _reportError(
        'backend cancel',
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // SERIALIZED OPERATION ENGINE
  // =============================================================

  Future<T> _runSerialized<T>(
      String operation,
      Future<T> Function() action,
      ) {
    final Completer<T> completer = Completer<T>();

    _operationQueue = _operationQueue.then<void>(
          (_) async {
        if (_isDisposed) {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'CallRecorder is disposed. '
                    'Operation "$operation" cannot run.',
              ),
            );
          }

          return;
        }

        try {
          final T result = await action();

          if (!completer.isCompleted) {
            completer.complete(
              result,
            );
          }
        } catch (error, stackTrace) {
          _reportError(
            operation,
            error,
            stackTrace,
          );

          if (!completer.isCompleted) {
            completer.completeError(
              error,
              stackTrace,
            );
          }
        } finally {
          _notifySafely();
        }
      },
    );

    return completer.future;
  }

  // =============================================================
  // ERROR STATE
  // =============================================================

  void clearError() {
    if (_isDisposed || _lastError == null) {
      return;
    }

    _lastError = null;

    _notifySafely();
  }

  void _setError(
      String message,
      ) {
    _lastError = message;
  }

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [CallRecorder/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [CallRecorder/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // =============================================================
  // LIFECYCLE
  // =============================================================

  void _ensureUsable() {
    if (_isDisposed) {
      throw StateError(
        'CallRecorder has already been disposed.',
      );
    }
  }

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }

    notifyListeners();
  }

  // =============================================================
  // DISPOSE
  // =============================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _stopTicker();

    _stopwatch.stop();

    final CallRecordingBackend? backend = _backend;

    if (_isRecording && backend != null) {
      unawaited(
        _cancelBackendBestEffort(
          backend,
        ),
      );
    }

    _isRecording = false;

    _isPaused = false;

    _consentGranted = false;

    _filePath = null;

    _backend = null;

    _isDisposed = true;

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 31 PRODUCTION CONTRACT:
//
// ✓ Existing CallRecorder.instance preserved.
// ✓ Existing isRecording preserved.
// ✓ Existing isPaused preserved.
// ✓ Existing duration preserved.
// ✓ Existing filePath preserved.
//
// ✓ Existing start({String? savePath}) preserved.
// ✓ Existing pause() preserved.
// ✓ Existing resume() preserved.
// ✓ Existing stop() -> Future<String?> preserved.
// ✓ Existing cancel() preserved.
// ✓ Existing reset() preserved.
//
// ✓ Fake recording state removed.
// ✓ No backend = no recording claim.
// ✓ Explicit consent required.
// ✓ Revoked consent ends active recording.
// ✓ Visible UI can use isRecording.
// ✓ Recording failure cannot terminate call flow.
//
// ✓ Stopwatch is authoritative duration source.
// ✓ Wall-clock changes cannot corrupt duration.
// ✓ Background timer throttling cannot corrupt duration.
// ✓ Timer is presentation-only.
// ✓ Pause time is excluded only when backend truly supports pause.
//
// ✓ Recorder operations serialized.
// ✓ Rapid start/stop/toggle-style races prevented.
// ✓ Duplicate recording sessions prevented.
// ✓ Final path returned only after backend stop succeeds.
// ✓ Failed finalization returns null.
// ✓ Backend cleanup is best effort.
//
// ✓ No MediaStream created.
// ✓ No call MediaStream disposed.
// ✓ No PeerConnection ownership.
// ✓ No signaling ownership.
// ✓ No ICE ownership.
// ✓ No recovery ownership.
// ✓ No network ownership.
// ✓ No UI/design ownership.
// ✓ No covert recording.
// ===============================================================