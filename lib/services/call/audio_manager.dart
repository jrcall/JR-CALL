// ===========================================================
// JR CALL
// File: audio_manager.dart
// Location: lib/services/call/audio_manager.dart
//
// Description:
// Central production audio-state and routing orchestrator.
//
// Responsibilities:
// - Microphone enable / disable
// - Mute / unmute
// - Real WebRTC local audio-track synchronization
// - Speaker / earpiece routing
// - Bluetooth audio-state coordination
// - Input / output volume preference state
// - Noise suppression preference
// - Echo cancellation preference
// - Automatic gain-control preference
// - Microphone permission verification
// - Serialized audio operations to prevent race conditions
// - Lifecycle-safe reset / disposal
//
// Ownership:
// - MicrophoneManager owns microphone preference state
// - SpeakerManager owns output-route preference state
// - BluetoothManager owns Bluetooth device state
// - AudioManager coordinates those managers with WebRTC media
//
// Important:
// AudioManager does NOT create a second MediaStream.
// The active stream must come from WebRTCService / CallService.
// ===========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../utils/permissions.dart';
import 'bluetooth_manager.dart';
import 'microphone_manager.dart';
import 'speaker_manager.dart';

enum AudioOutputRoute { earpiece, speaker, bluetooth }

class AudioManager extends ChangeNotifier {
  AudioManager._() {
    microphone.addListener(_handleChildStateChanged);
    speaker.addListener(_handleChildStateChanged);
    bluetooth.addListener(_handleChildStateChanged);
  }

  static final AudioManager instance = AudioManager._();

  // ===========================================================
  // Child Managers
  // ===========================================================

  final MicrophoneManager microphone = MicrophoneManager();
  final SpeakerManager speaker = SpeakerManager();
  final BluetoothManager bluetooth = BluetoothManager();

  // ===========================================================
  // Runtime State
  // ===========================================================

  MediaStream? _localStream;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _suppressChildNotifications = false;

  AudioOutputRoute _outputRoute = AudioOutputRoute.earpiece;

  // Serializes every audio mutation so two UI actions cannot
  // change the same audio state at the same time.
  Future<void> _operationQueue = Future<void>.value();

  // ===========================================================
  // Public State
  // ===========================================================

  bool get isInitialized => _isInitialized;

  bool get isDisposed => _isDisposed;

  MediaStream? get localStream => _localStream;

  bool get hasLocalStream => _localStream != null;

  bool get microphoneEnabled => microphone.isEnabled;

  bool get isMuted => microphone.isMuted;

  bool get speakerEnabled => speaker.speakerEnabled;

  bool get bluetoothConnected => bluetooth.isConnected;

  bool get bluetoothAvailable => bluetooth.isAvailable;

  double get inputVolume => microphone.inputVolume;

  double get outputVolume => speaker.outputVolume;

  bool get noiseSuppression => microphone.noiseSuppression;

  bool get echoCancellation => microphone.echoCancellation;

  bool get autoGainControl => microphone.autoGainControl;

  AudioOutputRoute get outputRoute => _outputRoute;

  bool get isAudioTransmitting => microphone.isEnabled && !microphone.isMuted;

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize({MediaStream? localStream}) async {
    if (_isDisposed) {
      throw StateError('AudioManager has already been disposed.');
    }

    await _runSerialized<void>('initialize', () async {
      if (localStream != null) {
        _localStream = localStream;
      }

      if (!_isInitialized) {
        await microphone.reset();
        await speaker.reset();
        await bluetooth.reset();

        _outputRoute = AudioOutputRoute.earpiece;
        _isInitialized = true;
      }

      await _syncMicrophoneTracks();
    });
  }

  // ===========================================================
  // WebRTC Stream Binding
  // ===========================================================

  /// Attach the active WebRTC local MediaStream.
  ///
  /// CallService/WebRTCService should call this after
  /// local media has been created.
  Future<void> attachLocalStream(MediaStream? stream) async {
    await _runSerialized<void>('attachLocalStream', () async {
      _localStream = stream;

      if (stream != null) {
        _isInitialized = true;
        await _syncMicrophoneTracks();
      }
    });
  }

  /// Detaches only the reference.
  ///
  /// AudioManager intentionally does NOT stop or dispose
  /// WebRTCService's MediaStream because WebRTCService owns it.
  Future<void> detachLocalStream() async {
    await _runSerialized<void>('detachLocalStream', () async {
      _localStream = null;
    });
  }

  // ===========================================================
  // Permission
  // ===========================================================

  Future<bool> ensureMicrophonePermission({bool requestIfNeeded = true}) async {
    if (_isDisposed) {
      return false;
    }

    try {
      final alreadyGranted = await AppPermissions.hasMicrophonePermission();

      if (alreadyGranted) {
        return true;
      }

      if (!requestIfNeeded) {
        return false;
      }

      return await AppPermissions.requestMicrophone();
    } catch (error, stackTrace) {
      _reportError('Microphone permission', error, stackTrace);

      return false;
    }
  }

  // ===========================================================
  // Microphone
  // ===========================================================

  Future<void> enableMicrophone() async {
    await _runSerialized<void>('enableMicrophone', () async {
      await microphone.enable();
      await _syncMicrophoneTracks();
    });
  }

  Future<void> disableMicrophone() async {
    await _runSerialized<void>('disableMicrophone', () async {
      await microphone.disable();
      await _syncMicrophoneTracks();
    });
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (enabled) {
      await enableMicrophone();
    } else {
      await disableMicrophone();
    }
  }

  // ===========================================================
  // Mute
  // ===========================================================

  Future<void> mute() async {
    await setMute(true);
  }

  Future<void> unMute() async {
    await setMute(false);
  }

  Future<void> unmute() async {
    await unMute();
  }

  Future<void> setMute(bool muted) async {
    await _runSerialized<void>('setMute', () async {
      await microphone.setMute(muted);
      await _syncMicrophoneTracks();
    });
  }

  Future<void> toggleMute() async {
    await _runSerialized<void>('toggleMute', () async {
      await microphone.toggleMute();
      await _syncMicrophoneTracks();
    });
  }

  /// Applies AudioManager microphone state to the real
  /// WebRTC audio track.
  Future<void> _syncMicrophoneTracks() async {
    final stream = _localStream;

    if (stream == null) {
      return;
    }

    final shouldTransmit = microphone.isEnabled && !microphone.isMuted;

    try {
      final tracks = stream.getAudioTracks();

      for (final track in tracks) {
        if (track.enabled != shouldTransmit) {
          track.enabled = shouldTransmit;
        }
      }
    } catch (error, stackTrace) {
      _reportError('Microphone track synchronization', error, stackTrace);

      rethrow;
    }
  }

  // ===========================================================
  // Speaker / Earpiece
  // ===========================================================

  Future<void> enableSpeaker() async {
    await setSpeakerEnabled(true);
  }

  Future<void> disableSpeaker() async {
    await setSpeakerEnabled(false);
  }

  Future<void> setSpeakerEnabled(bool enabled) async {
    await _runSerialized<void>('setSpeakerEnabled', () async {
      await _setNativeSpeakerphone(enabled);

      if (enabled) {
        if (speaker.bluetoothEnabled) {
          await speaker.disconnectBluetooth();
        }

        await speaker.enableSpeaker();

        _outputRoute = AudioOutputRoute.speaker;
      } else {
        await speaker.disableSpeaker();

        _outputRoute = AudioOutputRoute.earpiece;
      }
    });
  }

  Future<void> toggleSpeaker() async {
    await setSpeakerEnabled(!speaker.speakerEnabled);
  }

  Future<void> useEarpiece() async {
    await setSpeakerEnabled(false);
  }

  Future<void> _setNativeSpeakerphone(bool enabled) async {
    try {
      await Helper.setSpeakerphoneOn(enabled);
    } catch (error, stackTrace) {
      // Some platforms do not expose mobile-style
      // speaker/earpiece switching.
      //
      // Do not crash a call because routing is unsupported.
      _reportError('Native speaker routing', error, stackTrace);
    }
  }

  // ===========================================================
  // Bluetooth
  // ===========================================================

  Future<void> connectBluetooth({
    required String name,
    required String address,
  }) async {
    final normalizedName = name.trim();
    final normalizedAddress = address.trim();

    if (normalizedName.isEmpty || normalizedAddress.isEmpty) {
      throw ArgumentError('Bluetooth device name and address cannot be empty.');
    }

    await _runSerialized<void>('connectBluetooth', () async {
      // Speakerphone should not remain forced ON
      // while Bluetooth is selected.
      await _setNativeSpeakerphone(false);

      await bluetooth.connect(name: normalizedName, address: normalizedAddress);

      await speaker.connectBluetooth();

      _outputRoute = AudioOutputRoute.bluetooth;
    });
  }

  Future<void> disconnectBluetooth() async {
    await _runSerialized<void>('disconnectBluetooth', () async {
      await bluetooth.disconnect();
      await speaker.disconnectBluetooth();

      await _setNativeSpeakerphone(false);

      _outputRoute = AudioOutputRoute.earpiece;
    });
  }

  Future<void> startBluetoothScan() async {
    await _runSerialized<void>('startBluetoothScan', () async {
      await bluetooth.startScan();
    });
  }

  Future<void> stopBluetoothScan() async {
    await _runSerialized<void>('stopBluetoothScan', () async {
      await bluetooth.stopScan();
    });
  }

  Future<void> refreshBluetooth() async {
    await _runSerialized<void>('refreshBluetooth', () async {
      await bluetooth.refresh();
    });
  }

  // ===========================================================
  // Volume Preferences
  // ===========================================================

  Future<void> setInputVolume(double value) async {
    await _runSerialized<void>('setInputVolume', () async {
      await microphone.setInputVolume(value.clamp(0.0, 1.0).toDouble());
    });
  }

  Future<void> setOutputVolume(double value) async {
    await _runSerialized<void>('setOutputVolume', () async {
      await speaker.setVolume(value.clamp(0.0, 1.0).toDouble());
    });
  }

  Future<void> volumeUp() async {
    await _runSerialized<void>('volumeUp', () async {
      await speaker.volumeUp();
    });
  }

  Future<void> volumeDown() async {
    await _runSerialized<void>('volumeDown', () async {
      await speaker.volumeDown();
    });
  }

  // ===========================================================
  // Audio Processing Preferences
  // ===========================================================

  Future<void> enableNoiseSuppression(bool enabled) async {
    await _runSerialized<void>('enableNoiseSuppression', () async {
      await microphone.setNoiseSuppression(enabled);
    });
  }

  Future<void> enableEchoCancellation(bool enabled) async {
    await _runSerialized<void>('enableEchoCancellation', () async {
      await microphone.setEchoCancellation(enabled);
    });
  }

  Future<void> enableAutoGainControl(bool enabled) async {
    await _runSerialized<void>('enableAutoGainControl', () async {
      await microphone.setAutoGainControl(enabled);
    });
  }

  // ===========================================================
  // State Snapshot
  // ===========================================================

  Map<String, dynamic> get stateSnapshot {
    return <String, dynamic>{
      'initialized': _isInitialized,
      'microphoneEnabled': microphone.isEnabled,
      'muted': microphone.isMuted,
      'audioTransmitting': isAudioTransmitting,
      'speakerEnabled': speaker.speakerEnabled,
      'bluetoothAvailable': bluetooth.isAvailable,
      'bluetoothConnected': bluetooth.isConnected,
      'bluetoothDeviceName': bluetooth.deviceName,
      'bluetoothDeviceAddress': bluetooth.deviceAddress,
      'outputRoute': _outputRoute.name,
      'inputVolume': microphone.inputVolume,
      'outputVolume': speaker.outputVolume,
      'noiseSuppression': microphone.noiseSuppression,
      'echoCancellation': microphone.echoCancellation,
      'autoGainControl': microphone.autoGainControl,
      'hasLocalStream': _localStream != null,
    };
  }

  // ===========================================================
  // Reset
  // ===========================================================

  Future<void> reset({bool detachStream = false}) async {
    if (_isDisposed) {
      return;
    }

    await _runSerialized<void>('reset', () async {
      try {
        await _setNativeSpeakerphone(false);
      } catch (_) {
        // Best-effort routing cleanup.
      }

      await microphone.reset();
      await speaker.reset();
      await bluetooth.reset();

      _outputRoute = AudioOutputRoute.earpiece;

      if (detachStream) {
        _localStream = null;
      } else {
        await _syncMicrophoneTracks();
      }

      _isInitialized = false;
    });
  }

  // ===========================================================
  // Serialized Operation Engine
  // ===========================================================

  Future<T> _runSerialized<T>(String operation, Future<T> Function() action) {
    final completer = Completer<T>();

    _operationQueue = _operationQueue.then((_) async {
      if (_isDisposed) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError(
              'AudioManager is disposed. '
              'Operation "$operation" cannot run.',
            ),
          );
        }

        return;
      }

      _suppressChildNotifications = true;

      try {
        final result = await action();

        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        _reportError(operation, error, stackTrace);

        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _suppressChildNotifications = false;
        _notifySafely();
      }
    });

    return completer.future;
  }

  // ===========================================================
  // Child Manager Synchronization
  // ===========================================================

  void _handleChildStateChanged() {
    if (_suppressChildNotifications || _isDisposed) {
      return;
    }

    _notifySafely();
  }

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }

    notifyListeners();
  }

  // ===========================================================
  // Error Logging
  // ===========================================================

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint('JR CALL [AudioManager/$source] error: $error');

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [AudioManager/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // Disposal
  // ===========================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    microphone.removeListener(_handleChildStateChanged);
    speaker.removeListener(_handleChildStateChanged);
    bluetooth.removeListener(_handleChildStateChanged);

    _localStream = null;

    microphone.dispose();
    speaker.dispose();
    bluetooth.dispose();

    super.dispose();
  }
}
