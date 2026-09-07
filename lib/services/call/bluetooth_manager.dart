// ===============================================================
// JR CALL
// File: bluetooth_manager.dart
// Location: lib/services/call/bluetooth_manager.dart
//
// MASTER PRODUCTION BLUETOOTH MANAGER
//
// RESPONSIBILITIES:
//
// - Bluetooth audio-device availability state.
// - Bluetooth connection preference/state.
// - Active Bluetooth device presentation metadata.
// - Bounded Bluetooth discovery-state coordination.
// - Connect / disconnect / toggle serialization.
// - Stale scan completion protection.
// - Lifecycle-safe reset / disposal.
//
// OWNERSHIP:
//
// BluetoothManager:
// - Bluetooth device coordination state.
//
// SpeakerManager:
// - Logical output-route preference.
//
// AudioManager:
// - Coordinates BluetoothManager + SpeakerManager.
// - Owns native speaker/earpiece routing.
//
// WebRTC / platform audio layer:
// - Owns actual native audio transport/routing.
//
// IMPORTANT:
//
// - No fake Bluetooth device discovery.
// - No fake physical connection claim.
// - No MediaStream ownership.
// - No RTCPeerConnection ownership.
// - No signaling ownership.
// - No ICE ownership.
// - No call-lifecycle ownership.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

class BluetoothManager extends ChangeNotifier {
  BluetoothManager();

  // =============================================================
  // DISCOVERY POLICY
  // =============================================================

  /// Preserves the existing bounded scan-duration behavior.
  ///
  /// IMPORTANT:
  /// This manager does NOT fabricate a discovered device when the
  /// window expires. Physical/native discovery belongs to the
  /// platform audio implementation.
  static const Duration _scanWindow = Duration(
    seconds: 2,
  );

  // =============================================================
  // STATE
  // =============================================================

  bool _isAvailable = false;

  bool _isConnected = false;

  bool _isScanning = false;

  bool _isDisposed = false;

  String? _deviceName;

  String? _deviceAddress;

  // =============================================================
  // SCAN LIFECYCLE
  // =============================================================

  Timer? _scanTimer;

  Completer<void>? _scanCompleter;

  int _scanGeneration = 0;

  // =============================================================
  // SERIALIZED CONNECTION OPERATIONS
  // =============================================================

  Future<void> _operationQueue = Future<void>.value();

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isAvailable => _isAvailable;

  bool get isConnected => _isConnected;

  bool get isScanning => _isScanning;

  bool get isDisposed => _isDisposed;

  String? get deviceName => _deviceName;

  String? get deviceAddress => _deviceAddress;

  // =============================================================
  // START SCAN
  // =============================================================

  Future<void> startScan() async {
    _ensureUsable();

    if (_isScanning) {
      final Completer<void>? activeCompleter = _scanCompleter;

      if (activeCompleter != null) {
        await activeCompleter.future;
      }

      return;
    }

    final int generation = ++_scanGeneration;

    final Completer<void> completer = Completer<void>();

    _scanCompleter = completer;

    _isScanning = true;

    _notifySafely();

    _scanTimer?.cancel();

    _scanTimer = Timer(
      _scanWindow,
          () {
        if (_isDisposed ||
            generation != _scanGeneration) {
          if (!completer.isCompleted) {
            completer.complete();
          }

          return;
        }

        _scanTimer = null;

        if (identical(
          _scanCompleter,
          completer,
        )) {
          _scanCompleter = null;
        }

        final bool changed = _isScanning;

        _isScanning = false;

        // CRITICAL:
        //
        // Do NOT set _isAvailable = true here.
        //
        // A timeout is not proof that a Bluetooth device exists.
        // The previous implementation fabricated availability after
        // two seconds, which could produce incorrect call-route UI.

        if (changed) {
          _notifySafely();
        }

        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await completer.future;
  }

  // =============================================================
  // STOP SCAN
  // =============================================================

  Future<void> stopScan() async {
    _ensureUsable();

    _stopScanInternal(
      notify: true,
    );
  }

  void _stopScanInternal({
    required bool notify,
  }) {
    _scanGeneration++;

    final bool changed =
        _isScanning ||
            _scanTimer != null ||
            _scanCompleter != null;

    _scanTimer?.cancel();

    _scanTimer = null;

    final Completer<void>? completer =
        _scanCompleter;

    _scanCompleter = null;

    _isScanning = false;

    if (completer != null &&
        !completer.isCompleted) {
      completer.complete();
    }

    if (notify && changed) {
      _notifySafely();
    }
  }

  // =============================================================
  // CONNECT DEVICE
  // =============================================================

  Future<void> connect({
    required String name,
    required String address,
  }) async {
    _ensureUsable();

    final String normalizedName =
    _requireDeviceValue(
      name,
      'name',
    );

    final String normalizedAddress =
    _requireDeviceValue(
      address,
      'address',
    );

    // A connection choice finishes any active discovery window.
    _stopScanInternal(
      notify: false,
    );

    await _runSerialized(
      'connect',
          () {
        final bool changed =
            !_isConnected ||
                !_isAvailable ||
                _deviceName != normalizedName ||
                _deviceAddress != normalizedAddress;

        _deviceName = normalizedName;

        _deviceAddress = normalizedAddress;

        _isConnected = true;

        // A device explicitly selected for connection is now a
        // known available Bluetooth endpoint in this manager state.
        _isAvailable = true;

        return changed;
      },
    );
  }

  // =============================================================
  // DISCONNECT DEVICE
  // =============================================================

  Future<void> disconnect() async {
    _ensureUsable();

    await _runSerialized(
      'disconnect',
      _disconnectState,
    );
  }

  bool _disconnectState() {
    final bool changed =
        _isConnected ||
            _deviceName != null ||
            _deviceAddress != null;

    _deviceName = null;

    _deviceAddress = null;

    _isConnected = false;

    // Existing compatibility preserved:
    //
    // Disconnecting the active device does NOT automatically prove
    // that Bluetooth hardware is unavailable, therefore availability
    // is not forcibly cleared here.

    return changed;
  }

  // =============================================================
  // TOGGLE CONNECTION
  // =============================================================

  Future<void> toggleConnection({
    required String name,
    required String address,
  }) async {
    _ensureUsable();

    final String normalizedName =
    _requireDeviceValue(
      name,
      'name',
    );

    final String normalizedAddress =
    _requireDeviceValue(
      address,
      'address',
    );

    _stopScanInternal(
      notify: false,
    );

    await _runSerialized(
      'toggleConnection',
          () {
        // CRITICAL:
        // Connection state is inspected INSIDE the serialized queue.
        // Rapid taps therefore cannot act on stale state.
        if (_isConnected) {
          return _disconnectState();
        }

        final bool changed =
            !_isAvailable ||
                _deviceName != normalizedName ||
                _deviceAddress != normalizedAddress;

        _deviceName = normalizedName;

        _deviceAddress = normalizedAddress;

        _isConnected = true;

        _isAvailable = true;

        return changed || _isConnected;
      },
    );
  }

  // =============================================================
  // REFRESH STATUS
  // =============================================================

  Future<void> refresh() async {
    _ensureUsable();

    await _runSerialized(
      'refresh',
          () {
        // Existing public API intentionally preserved.
        //
        // This is a presentation/state refresh hook. It does not
        // invent native Bluetooth availability or connection.
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

    _stopScanInternal(
      notify: false,
    );

    await _runSerialized(
      'reset',
          () {
        final bool changed =
            _isAvailable ||
                _isConnected ||
                _isScanning ||
                _deviceName != null ||
                _deviceAddress != null;

        _isAvailable = false;

        _isConnected = false;

        _isScanning = false;

        _deviceName = null;

        _deviceAddress = null;

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
                    'BluetoothManager is disposed. '
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
  // VALIDATION
  // =============================================================

  String _requireDeviceValue(
      String value,
      String parameterName,
      ) {
    final String normalized =
    value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        parameterName,
        'Bluetooth device $parameterName cannot be empty.',
      );
    }

    return normalized;
  }

  // =============================================================
  // INTERNAL HELPERS
  // =============================================================

  void _ensureUsable() {
    if (_isDisposed) {
      throw StateError(
        'BluetoothManager has already been disposed.',
      );
    }
  }

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
      'JR CALL [BluetoothManager/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL [BluetoothManager/$source]',
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

    _stopScanInternal(
      notify: false,
    );

    _isDisposed = true;

    _isConnected = false;

    _deviceName = null;

    _deviceAddress = null;

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 28 VERIFIED CONTRACT:
//
// ✓ Public BluetoothManager() preserved.
// ✓ ChangeNotifier contract preserved.
//
// ✓ isAvailable preserved.
// ✓ isConnected preserved.
// ✓ isScanning preserved.
// ✓ deviceName preserved.
// ✓ deviceAddress preserved.
//
// ✓ startScan() preserved.
// ✓ stopScan() preserved.
// ✓ connect(name/address) preserved.
// ✓ disconnect() preserved.
// ✓ toggleConnection() preserved.
// ✓ refresh() preserved.
// ✓ reset() preserved.
//
// ✓ Fake "device available after 2 seconds" removed.
// ✓ Scan window remains bounded.
// ✓ stopScan can immediately cancel an active scan.
// ✓ Stale scan callback cannot overwrite newer state.
// ✓ Connect terminates active scanning safely.
// ✓ Device name/address validation added.
// ✓ Connection mutations serialized.
// ✓ Toggle stale-state race removed.
// ✓ Duplicate notifications reduced.
// ✓ Reset cancels scan safely.
// ✓ Dispose cancels scan safely.
// ✓ Pending scan Future is completed on cancellation.
//
// ✓ Bluetooth logical state remains BluetoothManager-owned.
// ✓ Speaker logical route remains SpeakerManager-owned.
// ✓ Native speaker routing remains AudioManager-owned.
// ✓ No MediaStream ownership added.
// ✓ No PeerConnection ownership added.
// ✓ No signaling ownership added.
// ✓ No ICE ownership added.
// ✓ No call-lifecycle ownership added.
// ===============================================================