import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/call/audio_manager.dart';

/// ===========================================================
/// JR CALL
/// File: audio_provider.dart
/// Location: lib/providers/audio_provider.dart
///
/// Description:
/// Production audio-state bridge between AudioManager and UI.
///
/// Architecture ownership:
/// - AudioManager owns audio orchestration.
/// - MicrophoneManager owns microphone state.
/// - SpeakerManager owns speaker/earpiece state.
/// - BluetoothManager owns Bluetooth audio-device state.
/// - AudioProvider exposes those states to Presentation/UI.
///
/// Rules:
/// - No duplicate audio state.
/// - No duplicate timer.
/// - No duplicate stream.
/// - No direct WebRTC manipulation.
/// - No platform permission handling.
/// - No recording ownership.
/// - No duplicated microphone/speaker/Bluetooth logic.
/// ===========================================================

class AudioProvider extends ChangeNotifier {
  AudioProvider({AudioManager? audioManager})
    : _audioManager = audioManager ?? AudioManager.instance;

  final AudioManager _audioManager;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _listenersAttached = false;
  bool _operationInProgress = false;

  Future<void>? _initializationFuture;

  String? _lastStateSignature;

  /// ===========================================================
  /// Public State
  /// ===========================================================

  bool get isInitialized => _isInitialized;

  bool get isBusy => _operationInProgress;

  bool get isMuted => _audioManager.microphone.isMuted;

  bool get microphoneEnabled => _audioManager.microphone.isEnabled;

  double get inputVolume => _audioManager.microphone.inputVolume;

  bool get noiseSuppression => _audioManager.microphone.noiseSuppression;

  bool get echoCancellation => _audioManager.microphone.echoCancellation;

  bool get autoGainControl => _audioManager.microphone.autoGainControl;

  bool get speakerEnabled => _audioManager.speaker.speakerEnabled;

  bool get earpieceEnabled => _audioManager.speaker.earpieceEnabled;

  double get outputVolume => _audioManager.speaker.outputVolume;

  bool get bluetoothEnabled => _audioManager.speaker.bluetoothEnabled;

  bool get bluetoothAvailable => _audioManager.bluetooth.isAvailable;

  bool get bluetoothConnected => _audioManager.bluetooth.isConnected;

  bool get bluetoothScanning => _audioManager.bluetooth.isScanning;

  String? get bluetoothDeviceName => _audioManager.bluetooth.deviceName;

  String? get bluetoothDeviceAddress => _audioManager.bluetooth.deviceAddress;

  /// ===========================================================
  /// Initialization
  /// ===========================================================

  Future<void> initialize() {
    if (_isDisposed) {
      return Future<void>.error(
        StateError('AudioProvider has already been disposed.'),
      );
    }

    return _initializationFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    try {
      _attachListeners();

      if (!_audioManager.isInitialized) {
        await _audioManager.initialize();
      }

      if (_isDisposed) {
        return;
      }

      _isInitialized = true;
      _lastStateSignature = _buildStateSignature();

      _notifySafely(force: true);
    } catch (error, stackTrace) {
      _initializationFuture = null;

      _reportError('Initialization', error, stackTrace);

      rethrow;
    }
  }

  /// ===========================================================
  /// Microphone
  /// ===========================================================

  Future<void> enableMicrophone() async {
    await _runOperation(() async {
      await _audioManager.microphone.enable();
    });
  }

  Future<void> disableMicrophone() async {
    await _runOperation(() async {
      await _audioManager.microphone.disable();
    });
  }

  Future<void> setMicrophone(bool enabled) async {
    if (enabled) {
      await enableMicrophone();
    } else {
      await disableMicrophone();
    }
  }

  /// ===========================================================
  /// Mute
  /// ===========================================================

  Future<void> mute() async {
    await _runOperation(_audioManager.mute);
  }

  Future<void> unMute() async {
    await _runOperation(_audioManager.unMute);
  }

  Future<void> toggleMute() async {
    await _runOperation(_audioManager.toggleMute);
  }

  Future<void> setMute(bool value) async {
    if (value) {
      await mute();
    } else {
      await unMute();
    }
  }

  /// ===========================================================
  /// Speaker / Earpiece
  /// ===========================================================

  Future<void> enableSpeaker() async {
    await _runOperation(_audioManager.enableSpeaker);
  }

  Future<void> disableSpeaker() async {
    await _runOperation(_audioManager.disableSpeaker);
  }

  Future<void> toggleSpeaker() async {
    await _runOperation(_audioManager.toggleSpeaker);
  }

  Future<void> setSpeaker(bool enabled) async {
    if (enabled) {
      await enableSpeaker();
    } else {
      await disableSpeaker();
    }
  }

  /// ===========================================================
  /// Bluetooth
  /// ===========================================================

  Future<void> startBluetoothScan() async {
    await _runOperation(() async {
      await _audioManager.bluetooth.startScan();
    });
  }

  Future<void> stopBluetoothScan() async {
    await _runOperation(() async {
      await _audioManager.bluetooth.stopScan();
    });
  }

  Future<void> connectBluetooth({
    required String name,
    required String address,
  }) async {
    final normalizedName = name.trim();
    final normalizedAddress = address.trim();

    if (normalizedName.isEmpty || normalizedAddress.isEmpty) {
      throw ArgumentError('Bluetooth device name and address are required.');
    }

    await _runOperation(() async {
      await _audioManager.connectBluetooth(
        name: normalizedName,
        address: normalizedAddress,
      );
    });
  }

  Future<void> disconnectBluetooth() async {
    await _runOperation(_audioManager.disconnectBluetooth);
  }

  /// Legacy compatibility.
  ///
  /// Enabling Bluetooth requires an actual device identity,
  /// therefore callers should use connectBluetooth().
  Future<void> setBluetooth(bool enabled) async {
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

  /// ===========================================================
  /// Input / Output Volume
  /// ===========================================================

  Future<void> setInputVolume(double value) async {
    final normalized = value.clamp(0.0, 1.0).toDouble();

    await _runOperation(() async {
      await _audioManager.setInputVolume(normalized);
    });
  }

  Future<void> setOutputVolume(double value) async {
    final normalized = value.clamp(0.0, 1.0).toDouble();

    await _runOperation(() async {
      await _audioManager.setOutputVolume(normalized);
    });
  }

  /// ===========================================================
  /// Audio Processing
  /// ===========================================================

  Future<void> setNoiseSuppression(bool enabled) async {
    await _runOperation(() async {
      await _audioManager.enableNoiseSuppression(enabled);
    });
  }

  Future<void> setEchoCancellation(bool enabled) async {
    await _runOperation(() async {
      await _audioManager.enableEchoCancellation(enabled);
    });
  }

  Future<void> setAutoGainControl(bool enabled) async {
    await _runOperation(() async {
      await _audioManager.enableAutoGainControl(enabled);
    });
  }

  /// Compatibility aliases.
  Future<void> enableNoiseSuppression(bool enabled) =>
      setNoiseSuppression(enabled);

  Future<void> enableEchoCancellation(bool enabled) =>
      setEchoCancellation(enabled);

  Future<void> enableAutoGainControl(bool enabled) =>
      setAutoGainControl(enabled);

  /// ===========================================================
  /// Audio Device Refresh
  /// ===========================================================

  Future<void> refresh() async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    await _audioManager.bluetooth.refresh();

    _notifySafely();
  }

  /// ===========================================================
  /// Internal Listener Synchronization
  /// ===========================================================

  void _attachListeners() {
    if (_listenersAttached || _isDisposed) {
      return;
    }

    _audioManager.microphone.addListener(_handleManagerStateChanged);

    _audioManager.speaker.addListener(_handleManagerStateChanged);

    _audioManager.bluetooth.addListener(_handleManagerStateChanged);

    _listenersAttached = true;
  }

  void _detachListeners() {
    if (!_listenersAttached) {
      return;
    }

    _audioManager.microphone.removeListener(_handleManagerStateChanged);

    _audioManager.speaker.removeListener(_handleManagerStateChanged);

    _audioManager.bluetooth.removeListener(_handleManagerStateChanged);

    _listenersAttached = false;
  }

  void _handleManagerStateChanged() {
    if (_isDisposed) {
      return;
    }

    _notifySafely();
  }

  /// ===========================================================
  /// Serialized Operation Guard
  /// ===========================================================

  Future<void> _runOperation(Future<void> Function() operation) async {
    if (_isDisposed) {
      return;
    }

    await initialize();

    if (_isDisposed) {
      return;
    }

    if (_operationInProgress) {
      return;
    }

    _operationInProgress = true;

    try {
      await operation();
    } catch (error, stackTrace) {
      _reportError('Audio operation', error, stackTrace);

      rethrow;
    } finally {
      _operationInProgress = false;
      _notifySafely(force: true);
    }
  }

  /// ===========================================================
  /// Duplicate Notification Protection
  /// ===========================================================

  String _buildStateSignature() {
    return <Object?>[
      _isInitialized,
      _operationInProgress,
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

  void _notifySafely({bool force = false}) {
    if (_isDisposed) {
      return;
    }

    final signature = _buildStateSignature();

    if (!force && signature == _lastStateSignature) {
      return;
    }

    _lastStateSignature = signature;

    notifyListeners();
  }

  /// ===========================================================
  /// Reset
  /// ===========================================================

  Future<void> reset() async {
    if (_isDisposed) {
      return;
    }

    await _runOperation(() async {
      await _audioManager.reset();
    });

    _isInitialized = _audioManager.isInitialized;

    _notifySafely(force: true);
  }

  /// ===========================================================
  /// Error Reporting
  /// ===========================================================

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint('JR CALL [AudioProvider/$source] error: $error');

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [AudioProvider/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  /// ===========================================================
  /// Dispose
  /// ===========================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _detachListeners();

    _isDisposed = true;
    _isInitialized = false;
    _operationInProgress = false;
    _initializationFuture = null;
    _lastStateSignature = null;

    /// AudioManager is shared by the call engine,
    /// therefore Provider disposal MUST NOT reset/dispose it.

    super.dispose();
  }
}
