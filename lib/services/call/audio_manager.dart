// ===============================================================
// JR CALL
// File: audio_manager.dart
// Location: lib/services/call/audio_manager.dart
//
// MASTER PRODUCTION AUDIO MANAGER
//
// RESPONSIBILITIES:
//
// - Microphone enable / disable.
// - Mute / unmute.
// - Real WebRTC local audio-track synchronization.
// - Speaker / earpiece routing coordination.
// - Bluetooth audio-state coordination.
// - Input / output volume preference coordination.
// - Noise-suppression preference coordination.
// - Echo-cancellation preference coordination.
// - Automatic-gain-control preference coordination.
// - Microphone permission verification.
// - Serialized audio mutation.
// - Lifecycle-safe reset / disposal.
//
// OWNERSHIP:
//
// MicrophoneManager:
// - Microphone preference state.
//
// SpeakerManager:
// - Speaker / output-route preference state.
//
// BluetoothManager:
// - Bluetooth device state.
//
// AudioManager:
// - Coordinates those managers with the ACTIVE WebRTC MediaStream.
//
// WebRTCService / CallService:
// - Own MediaStream creation and destruction.
//
// IMPORTANT:
//
// - AudioManager NEVER creates a second MediaStream.
// - AudioManager NEVER disposes the attached WebRTC MediaStream.
// - AudioManager NEVER owns PeerConnection.
// - AudioManager NEVER owns signaling.
// - AudioManager NEVER owns ICE.
// - AudioManager NEVER owns call lifecycle.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../utils/permissions.dart';
import 'bluetooth_manager.dart';
import 'microphone_manager.dart';
import 'speaker_manager.dart';

// ===============================================================
// AUDIO OUTPUT ROUTE
// ===============================================================

enum AudioOutputRoute {
  earpiece,
  speaker,
  bluetooth,
}

// ===============================================================
// AUDIO MANAGER
// ===============================================================

class AudioManager extends ChangeNotifier {
  AudioManager._() {
    microphone.addListener(
      _handleChildStateChanged,
    );

    speaker.addListener(
      _handleChildStateChanged,
    );

    bluetooth.addListener(
      _handleChildStateChanged,
    );
  }

  static final AudioManager instance = AudioManager._();

  // =============================================================
  // CHILD MANAGERS
  // =============================================================

  final MicrophoneManager microphone = MicrophoneManager();

  final SpeakerManager speaker = SpeakerManager();

  final BluetoothManager bluetooth = BluetoothManager();

  // =============================================================
  // RUNTIME STATE
  // =============================================================

  MediaStream? _localStream;

  bool _isInitialized = false;

  bool _isDisposed = false;

  bool _suppressChildNotifications = false;

  AudioOutputRoute _outputRoute = AudioOutputRoute.earpiece;

  // -------------------------------------------------------------
  // Every mutation is serialized through this queue.
  //
  // This prevents rapid UI actions from racing:
  // - mute/unmute
  // - speaker toggles
  // - Bluetooth route changes
  // - stream attach/detach
  // -------------------------------------------------------------

  Future<void> _operationQueue = Future<void>.value();

  // =============================================================
  // PUBLIC STATE
  // =============================================================

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

  bool get isAudioTransmitting {
    return microphone.isEnabled && !microphone.isMuted;
  }

  // =============================================================
  // INITIALIZATION
  // =============================================================

  Future<void> initialize({
    MediaStream? localStream,
  }) async {
    if (_isDisposed) {
      throw StateError(
        'AudioManager has already been disposed.',
      );
    }

    await _runSerialized<void>(
      'initialize',
          () async {
        if (localStream != null) {
          _localStream = localStream;
        }

        if (_isInitialized) {
          await _syncMicrophoneTracks();
          return;
        }

        // Start every new AudioManager runtime from the
        // neutral mobile output route.
        await _setNativeSpeakerphone(
          false,
        );

        await microphone.reset();

        await speaker.reset();

        await bluetooth.reset();

        _outputRoute = AudioOutputRoute.earpiece;

        // Apply the resulting microphone state to the real
        // WebRTC stream before declaring initialization complete.
        await _syncMicrophoneTracks();

        _isInitialized = true;
      },
    );
  }

  // =============================================================
  // WEBRTC STREAM BINDING
  // =============================================================

  /// Attaches the ACTIVE local WebRTC MediaStream.
  ///
  /// Ownership remains with WebRTCService / CallService.
  Future<void> attachLocalStream(
      MediaStream? stream,
      ) async {
    await _runSerialized<void>(
      'attachLocalStream',
          () async {
        final MediaStream? previousStream = _localStream;

        final bool previousInitialized = _isInitialized;

        _localStream = stream;

        if (stream == null) {
          return;
        }

        try {
          await _syncMicrophoneTracks();

          _isInitialized = true;
        } catch (_) {
          // Keep AudioManager internally coherent if WebRTC track
          // synchronization rejects the newly supplied stream.
          _localStream = previousStream;

          _isInitialized = previousInitialized;

          rethrow;
        }
      },
    );
  }

  /// Detaches only AudioManager's reference.
  ///
  /// The MediaStream itself is NOT stopped or disposed here.
  Future<void> detachLocalStream() async {
    await _runSerialized<void>(
      'detachLocalStream',
          () async {
        _localStream = null;
      },
    );
  }

  // =============================================================
  // MICROPHONE PERMISSION
  // =============================================================

  Future<bool> ensureMicrophonePermission({
    bool requestIfNeeded = true,
  }) async {
    if (_isDisposed) {
      return false;
    }

    try {
      final bool alreadyGranted =
      await AppPermissions.hasMicrophonePermission();

      if (alreadyGranted) {
        return true;
      }

      if (!requestIfNeeded) {
        return false;
      }

      return AppPermissions.requestMicrophone();
    } catch (error, stackTrace) {
      _reportError(
        'Microphone permission',
        error,
        stackTrace,
      );

      return false;
    }
  }

  // =============================================================
  // MICROPHONE
  // =============================================================

  Future<void> enableMicrophone() async {
    await _runSerialized<void>(
      'enableMicrophone',
          () async {
        await microphone.enable();

        await _syncMicrophoneTracks();
      },
    );
  }

  Future<void> disableMicrophone() async {
    await _runSerialized<void>(
      'disableMicrophone',
          () async {
        await microphone.disable();

        await _syncMicrophoneTracks();
      },
    );
  }

  Future<void> setMicrophoneEnabled(
      bool enabled,
      ) async {
    if (enabled) {
      await enableMicrophone();
    } else {
      await disableMicrophone();
    }
  }

  // =============================================================
  // MUTE
  // =============================================================

  Future<void> mute() async {
    await setMute(
      true,
    );
  }

  /// Existing compatibility API.
  Future<void> unMute() async {
    await setMute(
      false,
    );
  }

  Future<void> unmute() async {
    await unMute();
  }

  Future<void> setMute(
      bool muted,
      ) async {
    await _runSerialized<void>(
      'setMute',
          () async {
        await microphone.setMute(
          muted,
        );

        await _syncMicrophoneTracks();
      },
    );
  }

  Future<void> toggleMute() async {
    await _runSerialized<void>(
      'toggleMute',
          () async {
        // The state is read INSIDE the serialized operation.
        // Therefore rapid double taps cannot calculate from stale state.
        await microphone.toggleMute();

        await _syncMicrophoneTracks();
      },
    );
  }

  // =============================================================
  // WEBRTC MICROPHONE TRACK SYNCHRONIZATION
  // =============================================================

  Future<void> _syncMicrophoneTracks() async {
    final MediaStream? stream = _localStream;

    if (stream == null) {
      return;
    }

    final bool shouldTransmit =
        microphone.isEnabled && !microphone.isMuted;

    try {
      final List<MediaStreamTrack> tracks = stream.getAudioTracks();

      for (final MediaStreamTrack track in tracks) {
        if (track.enabled == shouldTransmit) {
          continue;
        }

        track.enabled = shouldTransmit;
      }
    } catch (error, stackTrace) {
      _reportError(
        'Microphone track synchronization',
        error,
        stackTrace,
      );

      rethrow;
    }
  }

  // =============================================================
  // SPEAKER / EARPIECE
  // =============================================================

  Future<void> enableSpeaker() async {
    await setSpeakerEnabled(
      true,
    );
  }

  Future<void> disableSpeaker() async {
    await setSpeakerEnabled(
      false,
    );
  }

  Future<void> setSpeakerEnabled(
      bool enabled,
      ) async {
    await _runSerialized<void>(
      'setSpeakerEnabled',
          () async {
        await _applySpeakerEnabled(
          enabled,
        );
      },
    );
  }

  Future<void> toggleSpeaker() async {
    await _runSerialized<void>(
      'toggleSpeaker',
          () async {
        // CRITICAL:
        // Resolve the next value INSIDE the operation queue.
        //
        // Reading speakerEnabled before entering the queue would allow
        // two rapid taps to calculate the same stale target state.
        final bool nextEnabled = !speaker.speakerEnabled;

        await _applySpeakerEnabled(
          nextEnabled,
        );
      },
    );
  }

  Future<void> useEarpiece() async {
    await setSpeakerEnabled(
      false,
    );
  }

  Future<void> _applySpeakerEnabled(
      bool enabled,
      ) async {
    if (enabled) {
      // Bluetooth output preference must no longer be active
      // when explicit loudspeaker output is selected.
      if (speaker.bluetoothEnabled) {
        await speaker.disconnectBluetooth();
      }

      await _setNativeSpeakerphone(
        true,
      );

      await speaker.enableSpeaker();

      _outputRoute = AudioOutputRoute.speaker;

      return;
    }

    await _setNativeSpeakerphone(
      false,
    );

    await speaker.disableSpeaker();

    _outputRoute = AudioOutputRoute.earpiece;
  }

  Future<void> _setNativeSpeakerphone(
      bool enabled,
      ) async {
    try {
      await Helper.setSpeakerphoneOn(
        enabled,
      );
    } catch (error, stackTrace) {
      // Desktop/web or unsupported platforms may not expose
      // mobile-style speaker/earpiece switching.
      //
      // Unsupported routing must not terminate an active call.
      _reportError(
        'Native speaker routing',
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // BLUETOOTH
  // =============================================================

  Future<void> connectBluetooth({
    required String name,
    required String address,
  }) async {
    final String normalizedName = name.trim();

    final String normalizedAddress = address.trim();

    if (normalizedName.isEmpty || normalizedAddress.isEmpty) {
      throw ArgumentError(
        'Bluetooth device name and address cannot be empty.',
      );
    }

    await _runSerialized<void>(
      'connectBluetooth',
          () async {
        // Never leave loudspeaker force-enabled while Bluetooth
        // is being selected as the preferred route.
        await _setNativeSpeakerphone(
          false,
        );

        await bluetooth.connect(
          name: normalizedName,
          address: normalizedAddress,
        );

        try {
          await speaker.connectBluetooth();
        } catch (_) {
          // Roll back the child Bluetooth selection if SpeakerManager
          // cannot complete the route preference transition.
          try {
            await bluetooth.disconnect();
          } catch (rollbackError, rollbackStackTrace) {
            _reportError(
              'Bluetooth connection rollback',
              rollbackError,
              rollbackStackTrace,
            );
          }

          rethrow;
        }

        _outputRoute = AudioOutputRoute.bluetooth;
      },
    );
  }

  Future<void> disconnectBluetooth() async {
    await _runSerialized<void>(
      'disconnectBluetooth',
          () async {
        await bluetooth.disconnect();

        await speaker.disconnectBluetooth();

        await _setNativeSpeakerphone(
          false,
        );

        _outputRoute = AudioOutputRoute.earpiece;
      },
    );
  }

  Future<void> startBluetoothScan() async {
    await _runSerialized<void>(
      'startBluetoothScan',
          () async {
        await bluetooth.startScan();
      },
    );
  }

  Future<void> stopBluetoothScan() async {
    await _runSerialized<void>(
      'stopBluetoothScan',
          () async {
        await bluetooth.stopScan();
      },
    );
  }

  Future<void> refreshBluetooth() async {
    await _runSerialized<void>(
      'refreshBluetooth',
          () async {
        await bluetooth.refresh();
      },
    );
  }

  // =============================================================
  // VOLUME PREFERENCES
  // =============================================================

  Future<void> setInputVolume(
      double value,
      ) async {
    final double normalizedValue = value.clamp(
      0.0,
      1.0,
    ).toDouble();

    await _runSerialized<void>(
      'setInputVolume',
          () async {
        await microphone.setInputVolume(
          normalizedValue,
        );
      },
    );
  }

  Future<void> setOutputVolume(
      double value,
      ) async {
    final double normalizedValue = value.clamp(
      0.0,
      1.0,
    ).toDouble();

    await _runSerialized<void>(
      'setOutputVolume',
          () async {
        await speaker.setVolume(
          normalizedValue,
        );
      },
    );
  }

  Future<void> volumeUp() async {
    await _runSerialized<void>(
      'volumeUp',
          () async {
        await speaker.volumeUp();
      },
    );
  }

  Future<void> volumeDown() async {
    await _runSerialized<void>(
      'volumeDown',
          () async {
        await speaker.volumeDown();
      },
    );
  }

  // =============================================================
  // AUDIO PROCESSING PREFERENCES
  // =============================================================

  Future<void> enableNoiseSuppression(
      bool enabled,
      ) async {
    await _runSerialized<void>(
      'enableNoiseSuppression',
          () async {
        await microphone.setNoiseSuppression(
          enabled,
        );
      },
    );
  }

  Future<void> enableEchoCancellation(
      bool enabled,
      ) async {
    await _runSerialized<void>(
      'enableEchoCancellation',
          () async {
        await microphone.setEchoCancellation(
          enabled,
        );
      },
    );
  }

  Future<void> enableAutoGainControl(
      bool enabled,
      ) async {
    await _runSerialized<void>(
      'enableAutoGainControl',
          () async {
        await microphone.setAutoGainControl(
          enabled,
        );
      },
    );
  }

  // =============================================================
  // STATE SNAPSHOT
  // =============================================================

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

  // =============================================================
  // RESET
  // =============================================================

  Future<void> reset({
    bool detachStream = false,
  }) async {
    if (_isDisposed) {
      return;
    }

    await _runSerialized<void>(
      'reset',
          () async {
        await _setNativeSpeakerphone(
          false,
        );

        await microphone.reset();

        await speaker.reset();

        await bluetooth.reset();

        _outputRoute = AudioOutputRoute.earpiece;

        if (detachStream) {
          // Only remove AudioManager's reference.
          //
          // WebRTCService still owns disposal of the MediaStream.
          _localStream = null;
        } else {
          // Preserve existing compatibility:
          // if the stream remains attached, synchronize it with
          // the newly reset microphone preference state.
          await _syncMicrophoneTracks();
        }

        _isInitialized = false;
      },
    );
  }

  // =============================================================
  // SERIALIZED OPERATION ENGINE
  // =============================================================

  Future<T> _runSerialized<T>(
      String operation,
      Future<T> Function() action,
      ) {
    final Completer<T> completer = Completer<T>();

    _operationQueue = _operationQueue.then(
          (_) async {
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
          _suppressChildNotifications = false;

          _notifySafely();
        }
      },
    );

    return completer.future;
  }

  // =============================================================
  // CHILD MANAGER SYNCHRONIZATION
  // =============================================================

  void _handleChildStateChanged() {
    if (_suppressChildNotifications || _isDisposed) {
      return;
    }

    // Keep AudioManager route metadata coherent if a child
    // manager changes state independently.
    if (_outputRoute == AudioOutputRoute.bluetooth &&
        !bluetooth.isConnected &&
        !speaker.bluetoothEnabled) {
      _outputRoute = speaker.speakerEnabled
          ? AudioOutputRoute.speaker
          : AudioOutputRoute.earpiece;
    } else if (_outputRoute == AudioOutputRoute.speaker &&
        !speaker.speakerEnabled) {
      _outputRoute = AudioOutputRoute.earpiece;
    }

    _notifySafely();
  }

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }

    notifyListeners();
  }

  // =============================================================
  // ERROR LOGGING
  // =============================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [AudioManager/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [AudioManager/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // =============================================================
  // DISPOSAL
  // =============================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    microphone.removeListener(
      _handleChildStateChanged,
    );

    speaker.removeListener(
      _handleChildStateChanged,
    );

    bluetooth.removeListener(
      _handleChildStateChanged,
    );

    // MediaStream ownership remains outside AudioManager.
    _localStream = null;

    microphone.dispose();

    speaker.dispose();

    bluetooth.dispose();

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 23 PRODUCTION CONTRACT:
//
// ✓ No second MediaStream created.
// ✓ Attached MediaStream never disposed here.
// ✓ Real audio-track mute synchronization preserved.
// ✓ Microphone state remains MicrophoneManager-owned.
// ✓ Speaker preference remains SpeakerManager-owned.
// ✓ Bluetooth device state remains BluetoothManager-owned.
// ✓ Microphone permission API preserved.
// ✓ Existing public AudioManager APIs preserved.
// ✓ unMute() compatibility preserved.
// ✓ unmute() compatibility preserved.
//
// ✓ All audio mutations serialized.
// ✓ Speaker double-tap stale-state race removed.
// ✓ Mute serialization preserved.
// ✓ Stream attach synchronization made transactional.
// ✓ Initialization completion occurs after track synchronization.
// ✓ Bluetooth route partial-failure rollback added.
// ✓ Child-route metadata reconciliation added.
// ✓ Native speaker routing remains best effort.
// ✓ No unsupported platform routing failure terminates a call.
//
// ✓ No CallService ownership duplicated.
// ✓ No WebRTCService ownership duplicated.
// ✓ No PeerConnection ownership added.
// ✓ No signaling ownership added.
// ✓ No ICE ownership added.
// ✓ No RecoveryManager ownership added.
// ===============================================================