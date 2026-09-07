// ===============================================================
// JR CALL
// File: microphone_manager.dart
// Location: lib/services/call/microphone_manager.dart
//
// MASTER PRODUCTION MICROPHONE MANAGER
//
// RESPONSIBILITIES:
//
// - Microphone enabled / disabled preference state.
// - Mute / unmute preference state.
// - Input-volume preference state.
// - Noise-suppression preference state.
// - Echo-cancellation preference state.
// - Automatic-gain-control preference state.
// - Serialized state mutations.
// - Lifecycle-safe reset / disposal.
//
// OWNERSHIP:
//
// MicrophoneManager:
// - Microphone preference state only.
//
// AudioManager:
// - Synchronizes this state with the ACTIVE WebRTC audio track.
//
// AppPermissions:
// - Owns microphone permission checks/requests.
//
// WebRTCService / CallService:
// - Own MediaStream / MediaStreamTrack transport.
//
// IMPORTANT:
//
// - No MediaStream ownership here.
// - No MediaStreamTrack mutation here.
// - No microphone permission ownership here.
// - No signaling ownership here.
// - No ICE ownership here.
// - No call-lifecycle ownership here.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

class MicrophoneManager extends ChangeNotifier {
  MicrophoneManager();

  // =============================================================
  // DEFAULTS
  // =============================================================

  static const double _minimumInputVolume = 0.0;
  static const double _maximumInputVolume = 1.0;

  // =============================================================
  // STATE
  // =============================================================

  bool _isEnabled = true;

  bool _isMuted = false;

  double _inputVolume = 1.0;

  bool _noiseSuppression = true;

  bool _echoCancellation = true;

  bool _autoGainControl = true;

  bool _isDisposed = false;

  // =============================================================
  // SERIALIZED OPERATION QUEUE
  // =============================================================

  Future<void> _operationQueue = Future<void>.value();

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isEnabled => _isEnabled;

  bool get isMuted => _isMuted;

  double get inputVolume => _inputVolume;

  bool get noiseSuppression => _noiseSuppression;

  bool get echoCancellation => _echoCancellation;

  bool get autoGainControl => _autoGainControl;

  bool get isDisposed => _isDisposed;

  // =============================================================
  // ENABLE MICROPHONE
  // =============================================================

  Future<void> enable() async {
    await _runSerialized(
      'enable',
          () {
        final bool changed =
            !_isEnabled ||
                _isMuted;

        _isEnabled = true;

        // Existing JR CALL compatibility:
        // enabling the microphone also clears mute.
        _isMuted = false;

        return changed;
      },
    );
  }

  // =============================================================
  // DISABLE MICROPHONE
  // =============================================================

  Future<void> disable() async {
    await _runSerialized(
      'disable',
          () {
        if (!_isEnabled) {
          return false;
        }

        _isEnabled = false;

        // Existing behavior preserved:
        // disabling does NOT rewrite mute preference.
        return true;
      },
    );
  }

  // =============================================================
  // TOGGLE MUTE
  // =============================================================

  Future<void> toggleMute() async {
    await _runSerialized(
      'toggleMute',
          () {
        // Read and mutate state INSIDE the serialized operation.
        // Rapid taps therefore cannot toggle from stale state.
        _isMuted = !_isMuted;

        return true;
      },
    );
  }

  // =============================================================
  // SET MUTE
  // =============================================================

  Future<void> setMute(
      bool value,
      ) async {
    await _runSerialized(
      'setMute',
          () {
        if (_isMuted == value) {
          return false;
        }

        _isMuted = value;

        return true;
      },
    );
  }

  // =============================================================
  // INPUT VOLUME
  // =============================================================

  Future<void> setInputVolume(
      double volume,
      ) async {
    if (!volume.isFinite) {
      throw ArgumentError.value(
        volume,
        'volume',
        'Input volume must be a finite number.',
      );
    }

    final double normalizedVolume =
    volume
        .clamp(
      _minimumInputVolume,
      _maximumInputVolume,
    )
        .toDouble();

    await _runSerialized(
      'setInputVolume',
          () {
        if (_inputVolume == normalizedVolume) {
          return false;
        }

        _inputVolume = normalizedVolume;

        return true;
      },
    );
  }

  // =============================================================
  // NOISE SUPPRESSION
  // =============================================================

  Future<void> setNoiseSuppression(
      bool enabled,
      ) async {
    await _runSerialized(
      'setNoiseSuppression',
          () {
        if (_noiseSuppression == enabled) {
          return false;
        }

        _noiseSuppression = enabled;

        return true;
      },
    );
  }

  // =============================================================
  // ECHO CANCELLATION
  // =============================================================

  Future<void> setEchoCancellation(
      bool enabled,
      ) async {
    await _runSerialized(
      'setEchoCancellation',
          () {
        if (_echoCancellation == enabled) {
          return false;
        }

        _echoCancellation = enabled;

        return true;
      },
    );
  }

  // =============================================================
  // AUTOMATIC GAIN CONTROL
  // =============================================================

  Future<void> setAutoGainControl(
      bool enabled,
      ) async {
    await _runSerialized(
      'setAutoGainControl',
          () {
        if (_autoGainControl == enabled) {
          return false;
        }

        _autoGainControl = enabled;

        return true;
      },
    );
  }

  // =============================================================
  // RESET
  // =============================================================

  Future<void> reset() async {
    if (_isDisposed) {
      return;
    }

    await _runSerialized(
      'reset',
          () {
        final bool changed =
            !_isEnabled ||
                _isMuted ||
                _inputVolume != 1.0 ||
                !_noiseSuppression ||
                !_echoCancellation ||
                !_autoGainControl;

        _isEnabled = true;

        _isMuted = false;

        _inputVolume = 1.0;

        _noiseSuppression = true;

        _echoCancellation = true;

        _autoGainControl = true;

        return changed;
      },
    );
  }

  // =============================================================
  // SERIALIZED OPERATION ENGINE
  // =============================================================

  Future<void> _runSerialized(
      String operation,
      bool Function() action,
      ) {
    final Completer<void> completer =
    Completer<void>();

    _operationQueue =
        _operationQueue.then<void>(
              (_) {
            if (_isDisposed) {
              if (!completer.isCompleted) {
                completer.completeError(
                  StateError(
                    'MicrophoneManager is disposed. '
                        'Operation "$operation" cannot run.',
                  ),
                );
              }

              return;
            }

            try {
              final bool changed = action();

              if (changed) {
                _notifySafely();
              }

              if (!completer.isCompleted) {
                completer.complete();
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
            }
          },
        );

    return completer.future;
  }

  // =============================================================
  // INTERNAL HELPERS
  // =============================================================

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }

    notifyListeners();
  }

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [MicrophoneManager/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL [MicrophoneManager/$source]',
        stackTrace:
        stackTrace,
      );
    }
  }

  // =============================================================
  // DISPOSE
  // =============================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 26 VERIFIED CONTRACT:
//
// ✓ Public MicrophoneManager() preserved.
// ✓ ChangeNotifier contract preserved.
//
// ✓ isEnabled preserved.
// ✓ isMuted preserved.
// ✓ inputVolume preserved.
// ✓ noiseSuppression preserved.
// ✓ echoCancellation preserved.
// ✓ autoGainControl preserved.
//
// ✓ enable() preserved.
// ✓ disable() preserved.
// ✓ toggleMute() preserved.
// ✓ setMute() preserved.
// ✓ setInputVolume() preserved.
// ✓ setNoiseSuppression() preserved.
// ✓ setEchoCancellation() preserved.
// ✓ setAutoGainControl() preserved.
// ✓ reset() preserved.
//
// ✓ Existing enable() behavior preserved:
//   enabling also clears mute.
//
// ✓ Existing disable() behavior preserved:
//   disabling does not rewrite mute state.
//
// ✓ Input volume remains clamped 0.0–1.0.
// ✓ Non-finite input volume rejected.
// ✓ Rapid mute-toggle race removed.
// ✓ All state mutations serialized.
// ✓ Duplicate notifications reduced.
// ✓ Default reset state preserved.
// ✓ Use-after-dispose protected.
//
// ✓ No MediaStream ownership added.
// ✓ No MediaStreamTrack mutation added.
// ✓ No permission ownership added.
// ✓ No WebRTC ownership added.
// ✓ No signaling ownership added.
// ✓ No ICE ownership added.
// ✓ No call-lifecycle ownership added.
// ===============================================================