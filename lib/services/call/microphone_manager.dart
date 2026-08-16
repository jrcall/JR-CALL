import 'package:flutter/foundation.dart';

/// ===========================================================
/// JR CALL
/// File: microphone_manager.dart
/// Description:
/// Controls microphone state during voice/video calls.
/// Used by:
/// - ai_voice_engine.dart
/// - audio_manager.dart
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// ===========================================================

class MicrophoneManager extends ChangeNotifier {
  bool _isEnabled = true;
  bool _isMuted = false;
  double _inputVolume = 1.0;

  bool _noiseSuppression = true;
  bool _echoCancellation = true;
  bool _autoGainControl = true;

  /// Getters

  bool get isEnabled => _isEnabled;

  bool get isMuted => _isMuted;

  double get inputVolume => _inputVolume;

  bool get noiseSuppression => _noiseSuppression;

  bool get echoCancellation => _echoCancellation;

  bool get autoGainControl => _autoGainControl;

  /// Enable Microphone
  Future<void> enable() async {
    _isEnabled = true;
    _isMuted = false;
    notifyListeners();
  }

  /// Disable Microphone
  Future<void> disable() async {
    _isEnabled = false;
    notifyListeners();
  }

  /// Toggle Mute
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  /// Set Mute
  Future<void> setMute(bool value) async {
    _isMuted = value;
    notifyListeners();
  }

  /// Set Input Volume
  Future<void> setInputVolume(double volume) async {
    _inputVolume = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// AI Noise Suppression
  Future<void> setNoiseSuppression(bool enabled) async {
    _noiseSuppression = enabled;
    notifyListeners();
  }

  /// Echo Cancellation
  Future<void> setEchoCancellation(bool enabled) async {
    _echoCancellation = enabled;
    notifyListeners();
  }

  /// Automatic Gain Control
  Future<void> setAutoGainControl(bool enabled) async {
    _autoGainControl = enabled;
    notifyListeners();
  }

  /// Reset
  Future<void> reset() async {
    _isEnabled = true;
    _isMuted = false;
    _inputVolume = 1.0;

    _noiseSuppression = true;
    _echoCancellation = true;
    _autoGainControl = true;

    notifyListeners();
  }
}
