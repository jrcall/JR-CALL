import 'package:flutter/foundation.dart';

/// ===========================================================
/// JR CALL
/// File: speaker_manager.dart
/// Description:
/// Controls speaker output during voice/video calls.
/// Used by:
/// - audio_manager.dart
/// - ai_voice_engine.dart
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// ===========================================================

class SpeakerManager extends ChangeNotifier {
  bool _speakerEnabled = false;
  bool _earpieceEnabled = true;
  bool _bluetoothEnabled = false;

  double _outputVolume = 1.0;

  /// ==========================
  /// Getters
  /// ==========================

  bool get speakerEnabled => _speakerEnabled;

  bool get earpieceEnabled => _earpieceEnabled;

  bool get bluetoothEnabled => _bluetoothEnabled;

  double get outputVolume => _outputVolume;

  /// ==========================
  /// Speaker
  /// ==========================

  Future<void> enableSpeaker() async {
    _speakerEnabled = true;
    _earpieceEnabled = false;
    notifyListeners();
  }

  Future<void> disableSpeaker() async {
    _speakerEnabled = false;
    _earpieceEnabled = true;
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    if (_speakerEnabled) {
      await disableSpeaker();
    } else {
      await enableSpeaker();
    }
  }

  /// ==========================
  /// Bluetooth
  /// ==========================

  Future<void> connectBluetooth() async {
    _bluetoothEnabled = true;
    _speakerEnabled = false;
    _earpieceEnabled = false;

    notifyListeners();
  }

  Future<void> disconnectBluetooth() async {
    _bluetoothEnabled = false;
    _earpieceEnabled = true;

    notifyListeners();
  }

  /// ==========================
  /// Volume
  /// ==========================

  Future<void> setVolume(double volume) async {
    _outputVolume = volume.clamp(0.0, 1.0);

    notifyListeners();
  }

  Future<void> volumeUp() async {
    _outputVolume = (_outputVolume + 0.1).clamp(0.0, 1.0);

    notifyListeners();
  }

  Future<void> volumeDown() async {
    _outputVolume = (_outputVolume - 0.1).clamp(0.0, 1.0);

    notifyListeners();
  }

  /// ==========================
  /// Reset
  /// ==========================

  Future<void> reset() async {
    _speakerEnabled = false;
    _earpieceEnabled = true;
    _bluetoothEnabled = false;
    _outputVolume = 1.0;

    notifyListeners();
  }
}
