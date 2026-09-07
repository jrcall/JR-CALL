// ===============================================================
// JR CALL
// File: speaker_manager.dart
// Location: lib/services/call/speaker_manager.dart
//
// MASTER PRODUCTION SPEAKER MANAGER
//
// RESPONSIBILITIES:
//
// - Speaker logical output preference.
// - Earpiece logical output preference.
// - Bluetooth logical output preference.
// - Output-volume preference state.
// - Exclusive output-route state.
// - Serialized state mutations.
// - Lifecycle-safe reset / disposal.
//
// OWNERSHIP:
//
// SpeakerManager:
// - Logical audio-output route preference.
// - Output-volume preference.
//
// AudioManager:
// - Native speaker/earpiece application.
// - Coordinates SpeakerManager with BluetoothManager.
//
// BluetoothManager:
// - Bluetooth device discovery / connection state.
//
// WebRTCService / CallService:
// - Own WebRTC audio transport.
//
// IMPORTANT:
//
// - No Helper.setSpeakerphoneOn() ownership here.
// - No Bluetooth device discovery here.
// - No MediaStream ownership here.
// - No WebRTC ownership here.
// - No signaling ownership here.
// - No ICE ownership here.
// - No call-lifecycle ownership here.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

class SpeakerManager extends ChangeNotifier {
  SpeakerManager();

  // =============================================================
  // DEFAULTS
  // =============================================================

  static const double _minimumVolume = 0.0;
  static const double _maximumVolume = 1.0;
  static const double _volumeStep = 0.1;

  // =============================================================
  // ROUTE STATE
  // =============================================================

  bool _speakerEnabled = false;

  bool _earpieceEnabled = true;

  bool _bluetoothEnabled = false;

  double _outputVolume = 1.0;

  bool _isDisposed = false;

  // =============================================================
  // SERIALIZED OPERATION QUEUE
  // =============================================================

  Future<void> _operationQueue = Future<void>.value();

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get speakerEnabled => _speakerEnabled;

  bool get earpieceEnabled => _earpieceEnabled;

  bool get bluetoothEnabled => _bluetoothEnabled;

  double get outputVolume => _outputVolume;

  bool get isDisposed => _isDisposed;

  // =============================================================
  // SPEAKER
  // =============================================================

  Future<void> enableSpeaker() async {
    await _runSerialized(
      'enableSpeaker',
          () {
        final bool changed =
            !_speakerEnabled ||
                _earpieceEnabled ||
                _bluetoothEnabled;

        // Speaker becomes the exclusive logical output route.
        _speakerEnabled = true;
        _earpieceEnabled = false;
        _bluetoothEnabled = false;

        return changed;
      },
    );
  }

  Future<void> disableSpeaker() async {
    await _runSerialized(
      'disableSpeaker',
          () {
        final bool changed =
            _speakerEnabled ||
                !_earpieceEnabled ||
                _bluetoothEnabled;

        // Existing JR CALL behavior:
        // disabling loudspeaker returns logical output to earpiece.
        _speakerEnabled = false;
        _earpieceEnabled = true;
        _bluetoothEnabled = false;

        return changed;
      },
    );
  }

  Future<void> toggleSpeaker() async {
    await _runSerialized(
      'toggleSpeaker',
          () {
        // Read current state INSIDE the serialized operation.
        // Rapid taps therefore cannot calculate from stale state.
        if (_speakerEnabled) {
          _speakerEnabled = false;
          _earpieceEnabled = true;
          _bluetoothEnabled = false;
        } else {
          _speakerEnabled = true;
          _earpieceEnabled = false;
          _bluetoothEnabled = false;
        }

        return true;
      },
    );
  }

  // =============================================================
  // BLUETOOTH LOGICAL ROUTE
  // =============================================================

  Future<void> connectBluetooth() async {
    await _runSerialized(
      'connectBluetooth',
          () {
        final bool changed =
            !_bluetoothEnabled ||
                _speakerEnabled ||
                _earpieceEnabled;

        // Bluetooth becomes the exclusive logical output route.
        _bluetoothEnabled = true;
        _speakerEnabled = false;
        _earpieceEnabled = false;

        return changed;
      },
    );
  }

  Future<void> disconnectBluetooth() async {
    await _runSerialized(
      'disconnectBluetooth',
          () {
        final bool changed =
            _bluetoothEnabled ||
                _speakerEnabled ||
                !_earpieceEnabled;

        // Existing JR CALL route contract:
        // leaving Bluetooth returns output to earpiece.
        _bluetoothEnabled = false;
        _speakerEnabled = false;
        _earpieceEnabled = true;

        return changed;
      },
    );
  }

  // =============================================================
  // OUTPUT VOLUME
  // =============================================================

  Future<void> setVolume(
      double volume,
      ) async {
    if (!volume.isFinite) {
      throw ArgumentError.value(
        volume,
        'volume',
        'Output volume must be a finite number.',
      );
    }

    final double normalizedVolume = volume
        .clamp(
      _minimumVolume,
      _maximumVolume,
    )
        .toDouble();

    await _runSerialized(
      'setVolume',
          () {
        if (_outputVolume == normalizedVolume) {
          return false;
        }

        _outputVolume = normalizedVolume;

        return true;
      },
    );
  }

  Future<void> volumeUp() async {
    await _runSerialized(
      'volumeUp',
          () {
        final double nextVolume = (_outputVolume + _volumeStep)
            .clamp(
          _minimumVolume,
          _maximumVolume,
        )
            .toDouble();

        if (_outputVolume == nextVolume) {
          return false;
        }

        _outputVolume = nextVolume;

        return true;
      },
    );
  }

  Future<void> volumeDown() async {
    await _runSerialized(
      'volumeDown',
          () {
        final double nextVolume = (_outputVolume - _volumeStep)
            .clamp(
          _minimumVolume,
          _maximumVolume,
        )
            .toDouble();

        if (_outputVolume == nextVolume) {
          return false;
        }

        _outputVolume = nextVolume;

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
            _speakerEnabled ||
                !_earpieceEnabled ||
                _bluetoothEnabled ||
                _outputVolume != 1.0;

        _speakerEnabled = false;
        _earpieceEnabled = true;
        _bluetoothEnabled = false;
        _outputVolume = 1.0;

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
    final Completer<void> completer = Completer<void>();

    _operationQueue = _operationQueue.then<void>(
          (_) {
        if (_isDisposed) {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'SpeakerManager is disposed. '
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
      'JR CALL [SpeakerManager/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [SpeakerManager/$source]',
        stackTrace: stackTrace,
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
// FILE 27 VERIFIED CONTRACT:
//
// ✓ Public SpeakerManager() preserved.
// ✓ ChangeNotifier contract preserved.
//
// ✓ speakerEnabled preserved.
// ✓ earpieceEnabled preserved.
// ✓ bluetoothEnabled preserved.
// ✓ outputVolume preserved.
//
// ✓ enableSpeaker() preserved.
// ✓ disableSpeaker() preserved.
// ✓ toggleSpeaker() preserved.
// ✓ connectBluetooth() preserved.
// ✓ disconnectBluetooth() preserved.
// ✓ setVolume() preserved.
// ✓ volumeUp() preserved.
// ✓ volumeDown() preserved.
// ✓ reset() preserved.
//
// ✓ Speaker route is exclusive.
// ✓ Earpiece route is exclusive.
// ✓ Bluetooth logical route is exclusive.
// ✓ Disabling speaker returns to earpiece.
// ✓ Disconnecting Bluetooth returns to earpiece.
// ✓ Rapid speaker-toggle race removed.
// ✓ Rapid volume-up/down races removed.
// ✓ Output volume remains clamped 0.0–1.0.
// ✓ Non-finite volume rejected.
// ✓ Duplicate notifications reduced.
// ✓ Default reset state preserved.
// ✓ Use-after-dispose protected.
//
// ✓ Native speaker routing remains AudioManager-owned.
// ✓ Bluetooth device connection remains BluetoothManager-owned.
// ✓ No MediaStream ownership added.
// ✓ No WebRTC ownership added.
// ✓ No signaling ownership added.
// ✓ No ICE ownership added.
// ✓ No call-lifecycle ownership added.
// ===============================================================