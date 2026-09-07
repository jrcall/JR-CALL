import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/call/audio_manager.dart';

/// ===========================================================
/// JR CALL
/// File: audio_provider.dart
/// Location: lib/providers/audio_provider.dart
///
/// MASTER PRODUCTION AUDIO PROVIDER
///
/// RESPONSIBILITIES:
///
/// - Bridge AudioManager state to Presentation/UI.
/// - Expose microphone presentation state.
/// - Expose speaker/earpiece presentation state.
/// - Expose Bluetooth presentation state.
/// - Expose audio-processing preference state.
/// - Coordinate UI audio actions through AudioManager.
/// - Serialize normal audio UI operations.
/// - Keep Bluetooth scan cancellation responsive.
/// - Prevent duplicate presentation notifications.
///
/// OWNERSHIP:
///
/// AudioManager:
/// - Audio orchestration.
/// - Real WebRTC audio-track synchronization.
/// - Native speaker/earpiece routing coordination.
/// - Bluetooth route coordination.
///
/// MicrophoneManager:
/// - Microphone preference state.
///
/// SpeakerManager:
/// - Logical output-route preference state.
///
/// BluetoothManager:
/// - Bluetooth device/discovery state.
///
/// AudioProvider:
/// - Presentation bridge only.
///
/// IMPORTANT:
///
/// - No WebRTC manipulation here.
/// - No MediaStream ownership here.
/// - No MediaStreamTrack mutation here.
/// - No permission ownership here.
/// - No recording ownership here.
/// - No native routing ownership here.
/// - No duplicated microphone/speaker/Bluetooth state.
/// ===========================================================

class AudioProvider extends ChangeNotifier {
  AudioProvider({
    AudioManager? audioManager,
  }) : _audioManager = audioManager ?? AudioManager.instance;

  // ===========================================================
  // DEPENDENCY
  // ===========================================================

  final AudioManager _audioManager;

  // ===========================================================
  // LIFECYCLE
  // ===========================================================

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _listenerAttached = false;

  Future<void>? _initializationFuture;

  // ===========================================================
  // OPERATION STATE
  // ===========================================================

  Future<void> _operationQueue = Future<void>.value();

  int _activeOperations = 0;

  // ===========================================================
  // DUPLICATE NOTIFICATION PROTECTION
  // ===========================================================

  String? _lastStateSignature;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  bool get isInitialized => _isInitialized;

  bool get isDisposed => _isDisposed;

  bool get isBusy => _activeOperations > 0;

  bool get isMuted => _audioManager.microphone.isMuted;

  bool get microphoneEnabled => _audioManager.microphone.isEnabled;

  double get inputVolume => _audioManager.microphone.inputVolume;

  bool get noiseSuppression =>
      _audioManager.microphone.noiseSuppression;

  bool get echoCancellation =>
      _audioManager.microphone.echoCancellation;

  bool get autoGainControl =>
      _audioManager.microphone.autoGainControl;

  bool get speakerEnabled => _audioManager.speaker.speakerEnabled;

  bool get earpieceEnabled => _audioManager.speaker.earpieceEnabled;

  double get outputVolume => _audioManager.speaker.outputVolume;

  bool get bluetoothEnabled =>
      _audioManager.speaker.bluetoothEnabled;

  bool get bluetoothAvailable =>
      _audioManager.bluetooth.isAvailable;

  bool get bluetoothConnected =>
      _audioManager.bluetooth.isConnected;

  bool get bluetoothScanning =>
      _audioManager.bluetooth.isScanning;

  String? get bluetoothDeviceName =>
      _audioManager.bluetooth.deviceName;

  String? get bluetoothDeviceAddress =>
      _audioManager.bluetooth.deviceAddress;

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() {
    if (_isDisposed) {
      return Future<void>.error(
        StateError(
          'AudioProvider has already been disposed.',
        ),
      );
    }

    if (_isInitialized &&
        _audioManager.isInitialized) {
      return Future<void>.value();
    }

    final Future<void>? existing = _initializationFuture;

    if (existing != null) {
      return existing;
    }

    final Future<void> future = _initializeInternal();

    _initializationFuture = future;

    return future;
  }

  Future<void> _initializeInternal() async {
    try {
      _attachListener();

      if (!_audioManager.isInitialized) {
        await _audioManager.initialize();
      }

      if (_isDisposed) {
        return;
      }

      _isInitialized = _audioManager.isInitialized;

      _lastStateSignature = _buildStateSignature();

      _notifySafely(
        force: true,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Initialization',
        error,
        stackTrace,
      );

      rethrow;
    } finally {
      _initializationFuture = null;
    }
  }

  // ===========================================================
  // MICROPHONE
  //
  // CRITICAL:
  //
  // Always route microphone enable/disable through AudioManager.
  // AudioManager synchronizes state with the real WebRTC track.
  // ===========================================================

  Future<void> enableMicrophone() {
    return _runOperation(
      _audioManager.enableMicrophone,
    );
  }

  Future<void> disableMicrophone() {
    return _runOperation(
      _audioManager.disableMicrophone,
    );
  }

  Future<void> setMicrophone(
      bool enabled,
      ) {
    return _runOperation(
          () => _audioManager.setMicrophoneEnabled(
        enabled,
      ),
    );
  }

  // ===========================================================
  // MUTE
  // ===========================================================

  Future<void> mute() {
    return _runOperation(
      _audioManager.mute,
    );
  }

  Future<void> unMute() {
    return _runOperation(
      _audioManager.unMute,
    );
  }

  Future<void> toggleMute() {
    return _runOperation(
      _audioManager.toggleMute,
    );
  }

  Future<void> setMute(
      bool value,
      ) {
    return _runOperation(
          () => _audioManager.setMute(
        value,
      ),
    );
  }

  // ===========================================================
  // SPEAKER / EARPIECE
  // ===========================================================

  Future<void> enableSpeaker() {
    return _runOperation(
      _audioManager.enableSpeaker,
    );
  }

  Future<void> disableSpeaker() {
    return _runOperation(
      _audioManager.disableSpeaker,
    );
  }

  Future<void> toggleSpeaker() {
    return _runOperation(
      _audioManager.toggleSpeaker,
    );
  }

  Future<void> setSpeaker(
      bool enabled,
      ) {
    return _runOperation(
          () => _audioManager.setSpeakerEnabled(
        enabled,
      ),
    );
  }

  // ===========================================================
  // BLUETOOTH SCAN
  //
  // IMPORTANT:
  //
  // BluetoothManager owns discovery state.
  //
  // Scan start/stop intentionally bypass the provider's normal
  // serialized queue so stopScan() can cancel an active scan
  // immediately instead of waiting for the scan window to finish.
  // ===========================================================

  Future<void> startBluetoothScan() async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    await _runConcurrentOperation(
      'Bluetooth scan start',
      _audioManager.bluetooth.startScan,
    );
  }

  Future<void> stopBluetoothScan() async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    await _runConcurrentOperation(
      'Bluetooth scan stop',
      _audioManager.bluetooth.stopScan,
    );
  }

  // ===========================================================
  // BLUETOOTH CONNECTION / ROUTING
  // ===========================================================

  Future<void> connectBluetooth({
    required String name,
    required String address,
  }) {
    final String normalizedName = name.trim();
    final String normalizedAddress = address.trim();

    if (normalizedName.isEmpty ||
        normalizedAddress.isEmpty) {
      return Future<void>.error(
        ArgumentError(
          'Bluetooth device name and address are required.',
        ),
      );
    }

    return _runOperation(
          () => _audioManager.connectBluetooth(
        name: normalizedName,
        address: normalizedAddress,
      ),
    );
  }

  Future<void> disconnectBluetooth() {
    return _runOperation(
      _audioManager.disconnectBluetooth,
    );
  }

  /// Existing compatibility API.
  ///
  /// Enabling Bluetooth requires a real selected device.
  Future<void> setBluetooth(
      bool enabled,
      ) async {
    if (!enabled) {
      await disconnectBluetooth();
      return;
    }

    if (bluetoothConnected) {
      return;
    }

    throw StateError(
      'Bluetooth cannot be enabled without selecting a device. '
          'Use connectBluetooth(name: ..., address: ...).',
    );
  }

  // ===========================================================
  // INPUT / OUTPUT VOLUME
  // ===========================================================

  Future<void> setInputVolume(
      double value,
      ) {
    if (!value.isFinite) {
      return Future<void>.error(
        ArgumentError.value(
          value,
          'value',
          'Input volume must be a finite number.',
        ),
      );
    }

    return _runOperation(
          () => _audioManager.setInputVolume(
        value.clamp(0.0, 1.0).toDouble(),
      ),
    );
  }

  Future<void> setOutputVolume(
      double value,
      ) {
    if (!value.isFinite) {
      return Future<void>.error(
        ArgumentError.value(
          value,
          'value',
          'Output volume must be a finite number.',
        ),
      );
    }

    return _runOperation(
          () => _audioManager.setOutputVolume(
        value.clamp(0.0, 1.0).toDouble(),
      ),
    );
  }

  // ===========================================================
  // AUDIO PROCESSING
  // ===========================================================

  Future<void> setNoiseSuppression(
      bool enabled,
      ) {
    return _runOperation(
          () => _audioManager.enableNoiseSuppression(
        enabled,
      ),
    );
  }

  Future<void> setEchoCancellation(
      bool enabled,
      ) {
    return _runOperation(
          () => _audioManager.enableEchoCancellation(
        enabled,
      ),
    );
  }

  Future<void> setAutoGainControl(
      bool enabled,
      ) {
    return _runOperation(
          () => _audioManager.enableAutoGainControl(
        enabled,
      ),
    );
  }

  Future<void> enableNoiseSuppression(
      bool enabled,
      ) {
    return setNoiseSuppression(
      enabled,
    );
  }

  Future<void> enableEchoCancellation(
      bool enabled,
      ) {
    return setEchoCancellation(
      enabled,
    );
  }

  Future<void> enableAutoGainControl(
      bool enabled,
      ) {
    return setAutoGainControl(
      enabled,
    );
  }

  // ===========================================================
  // AUDIO DEVICE REFRESH
  // ===========================================================

  Future<void> refresh() {
    return _runOperation(
      _audioManager.refreshBluetooth,
    );
  }

  // ===========================================================
  // CENTRAL AUDIO MANAGER LISTENER
  //
  // AudioManager already aggregates microphone/speaker/Bluetooth
  // child notifications. Listen once here to avoid duplicates.
  // ===========================================================

  void _attachListener() {
    if (_listenerAttached || _isDisposed) {
      return;
    }

    _audioManager.addListener(
      _handleAudioManagerStateChanged,
    );

    _listenerAttached = true;
  }

  void _detachListener() {
    if (!_listenerAttached) {
      return;
    }

    _audioManager.removeListener(
      _handleAudioManagerStateChanged,
    );

    _listenerAttached = false;
  }

  void _handleAudioManagerStateChanged() {
    if (_isDisposed) {
      return;
    }

    _isInitialized = _audioManager.isInitialized;

    _notifySafely();
  }

  // ===========================================================
  // SERIALIZED NORMAL OPERATION ENGINE
  //
  // Provider operations are queued rather than dropped.
  //
  // This is important for fast sequential UI interactions.
  // ===========================================================

  Future<void> _runOperation(
      Future<void> Function() operation,
      ) async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    final Completer<void> completer = Completer<void>();

    _beginBusyOperation();

    _operationQueue = _operationQueue.then<void>(
          (_) async {
        if (_isDisposed) {
          if (!completer.isCompleted) {
            completer.complete();
          }

          _endBusyOperation();

          return;
        }

        try {
          await operation();

          if (!completer.isCompleted) {
            completer.complete();
          }
        } catch (error, stackTrace) {
          _reportError(
            'Audio operation',
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
          _endBusyOperation();
        }
      },
    );

    await completer.future;
  }

  // ===========================================================
  // CONCURRENT SPECIAL OPERATION
  //
  // Used for Bluetooth scan start/stop so stop can interrupt scan.
  // ===========================================================

  Future<void> _runConcurrentOperation(
      String source,
      Future<void> Function() operation,
      ) async {
    if (_isDisposed) {
      return;
    }

    _beginBusyOperation();

    try {
      await operation();
    } catch (error, stackTrace) {
      _reportError(
        source,
        error,
        stackTrace,
      );

      rethrow;
    } finally {
      _endBusyOperation();
    }
  }

  // ===========================================================
  // BUSY STATE
  // ===========================================================

  void _beginBusyOperation() {
    if (_isDisposed) {
      return;
    }

    _activeOperations++;

    _notifySafely(
      force: true,
    );
  }

  void _endBusyOperation() {
    if (_activeOperations > 0) {
      _activeOperations--;
    }

    _notifySafely(
      force: true,
    );
  }

  // ===========================================================
  // DUPLICATE NOTIFICATION PROTECTION
  // ===========================================================

  String _buildStateSignature() {
    return <Object?>[
      _isInitialized,
      isBusy,
      microphoneEnabled,
      isMuted,
      inputVolume,
      noiseSuppression,
      echoCancellation,
      autoGainControl,
      speakerEnabled,
      earpieceEnabled,
      outputVolume,
      bluetoothEnabled,
      bluetoothAvailable,
      bluetoothConnected,
      bluetoothScanning,
      bluetoothDeviceName,
      bluetoothDeviceAddress,
    ].join('|');
  }

  void _notifySafely({
    bool force = false,
  }) {
    if (_isDisposed) {
      return;
    }

    final String signature = _buildStateSignature();

    if (!force &&
        signature == _lastStateSignature) {
      return;
    }

    _lastStateSignature = signature;

    notifyListeners();
  }

  // ===========================================================
  // RESET
  //
  // AudioManager owns reset semantics.
  //
  // Provider does NOT dispose AudioManager.
  // ===========================================================

  Future<void> reset() async {
    if (_isDisposed) {
      return;
    }

    await _runOperation(
      _audioManager.reset,
    );

    if (_isDisposed) {
      return;
    }

    _isInitialized = _audioManager.isInitialized;

    _notifySafely(
      force: true,
    );
  }

  // ===========================================================
  // ERROR REPORTING
  // ===========================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [AudioProvider/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [AudioProvider/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // DISPOSE
  //
  // AudioManager is shared by the call engine.
  // Provider disposal MUST NOT reset/dispose it.
  // ===========================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _detachListener();

    _isDisposed = true;

    _isInitialized = false;

    _activeOperations = 0;

    _initializationFuture = null;

    _lastStateSignature = null;

    super.dispose();
  }
}