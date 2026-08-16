import 'package:flutter/foundation.dart';

/// ===========================================================
/// JR CALL
/// File: camera_manager.dart
/// Description:
/// Controls camera during voice/video calls.
///
/// Used by:
/// - video_manager.dart
/// - ai_video_engine.dart
/// - video_call_screen.dart
/// - screen_share_service.dart
/// ===========================================================

class CameraManager extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isCameraEnabled = true;
  bool _isFrontCamera = true;
  bool _isFlashOn = false;

  double _zoomLevel = 1.0;

  int _previewWidth = 1280;
  int _previewHeight = 720;

  /// ==========================
  /// Getters
  /// ==========================

  bool get isInitialized => _isInitialized;

  bool get isCameraEnabled => _isCameraEnabled;

  bool get isFrontCamera => _isFrontCamera;

  bool get isFlashOn => _isFlashOn;

  double get zoomLevel => _zoomLevel;

  int get previewWidth => _previewWidth;

  int get previewHeight => _previewHeight;

  /// ==========================
  /// Initialize Camera
  /// ==========================

  Future<void> initialize() async {
    _isInitialized = true;
    notifyListeners();
  }

  /// ==========================
  /// Camera On
  /// ==========================

  Future<void> enableCamera() async {
    _isCameraEnabled = true;
    notifyListeners();
  }

  /// ==========================
  /// Camera Off
  /// ==========================

  Future<void> disableCamera() async {
    _isCameraEnabled = false;
    notifyListeners();
  }

  /// ==========================
  /// Toggle Camera
  /// ==========================

  Future<void> toggleCamera() async {
    _isCameraEnabled = !_isCameraEnabled;
    notifyListeners();
  }

  /// ==========================
  /// Switch Front / Back
  /// ==========================

  Future<void> switchCamera() async {
    _isFrontCamera = !_isFrontCamera;
    notifyListeners();
  }

  /// ==========================
  /// Flash
  /// ==========================

  Future<void> enableFlash() async {
    _isFlashOn = true;
    notifyListeners();
  }

  Future<void> disableFlash() async {
    _isFlashOn = false;
    notifyListeners();
  }

  Future<void> toggleFlash() async {
    _isFlashOn = !_isFlashOn;
    notifyListeners();
  }

  /// ==========================
  /// Zoom
  /// ==========================

  Future<void> setZoom(double value) async {
    _zoomLevel = value.clamp(1.0, 10.0);
    notifyListeners();
  }

  /// ==========================
  /// Preview Size
  /// ==========================

  Future<void> setPreviewSize({required int width, required int height}) async {
    _previewWidth = width;
    _previewHeight = height;

    notifyListeners();
  }

  /// ==========================
  /// AI Recommended Quality
  /// ==========================

  Future<void> applyLowQuality() async {
    _previewWidth = 640;
    _previewHeight = 360;

    notifyListeners();
  }

  Future<void> applyMediumQuality() async {
    _previewWidth = 960;
    _previewHeight = 540;

    notifyListeners();
  }

  Future<void> applyHDQuality() async {
    _previewWidth = 1280;
    _previewHeight = 720;

    notifyListeners();
  }

  Future<void> applyFullHDQuality() async {
    _previewWidth = 1920;
    _previewHeight = 1080;

    notifyListeners();
  }

  /// ==========================
  /// Reset
  /// ==========================

  Future<void> reset() async {
    _isInitialized = false;
    _isCameraEnabled = true;
    _isFrontCamera = true;
    _isFlashOn = false;

    _zoomLevel = 1.0;

    _previewWidth = 1280;
    _previewHeight = 720;

    notifyListeners();
  }
}
