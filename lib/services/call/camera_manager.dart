// ===============================================================
// JR CALL
// File: camera_manager.dart
// Location: lib/services/call/camera_manager.dart
//
// MASTER PRODUCTION CAMERA MANAGER
//
// RESPONSIBILITIES:
//
// - Camera enabled / disabled state.
// - Front / back camera state.
// - Flash state.
// - Zoom preference state.
// - Preview resolution state.
// - Camera quality presets.
// - Serialized camera-state mutations.
// - Safe reset / disposal.
//
// OWNERSHIP:
//
// CameraManager:
// - Camera/device control state and orchestration intent.
//
// VideoManager:
// - Higher-level video feature orchestration.
//
// WebRTCService:
// - Owns MediaStream / MediaStreamTrack.
// - Owns real WebRTC transport.
//
// IMPORTANT:
//
// - CameraManager does NOT create MediaStream.
// - CameraManager does NOT dispose WebRTC media.
// - CameraManager does NOT own PeerConnection.
// - CameraManager does NOT own signaling.
// - CameraManager does NOT own ICE.
// - CameraManager does NOT own recovery.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

class CameraManager extends ChangeNotifier {
  CameraManager();

  // =============================================================
  // DEFAULTS
  // =============================================================

  static const double _minimumZoom = 1.0;
  static const double _maximumZoom = 10.0;

  static const int _defaultPreviewWidth = 1280;
  static const int _defaultPreviewHeight = 720;

  // =============================================================
  // RUNTIME STATE
  // =============================================================

  bool _isInitialized = false;

  bool _isDisposed = false;

  bool _isCameraEnabled = true;

  bool _isFrontCamera = true;

  bool _isFlashOn = false;

  double _zoomLevel = _minimumZoom;

  int _previewWidth = _defaultPreviewWidth;

  int _previewHeight = _defaultPreviewHeight;

  // =============================================================
  // SERIALIZED OPERATION QUEUE
  // =============================================================

  Future<void> _operationQueue = Future<void>.value();

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isInitialized => _isInitialized;

  bool get isDisposed => _isDisposed;

  bool get isCameraEnabled => _isCameraEnabled;

  bool get isFrontCamera => _isFrontCamera;

  bool get isFlashOn => _isFlashOn;

  double get zoomLevel => _zoomLevel;

  int get previewWidth => _previewWidth;

  int get previewHeight => _previewHeight;

  // =============================================================
  // INITIALIZATION
  // =============================================================

  Future<void> initialize() async {
    _ensureUsable();

    await _runSerialized(
      'initialize',
          () async {
        if (_isInitialized) {
          return false;
        }

        _isInitialized = true;

        return true;
      },
    );
  }

  // =============================================================
  // CAMERA ENABLE / DISABLE
  // =============================================================

  Future<void> enableCamera() async {
    await _runSerialized(
      'enableCamera',
          () async {
        if (_isCameraEnabled) {
          return false;
        }

        _isCameraEnabled = true;

        return true;
      },
    );
  }

  Future<void> disableCamera() async {
    await _runSerialized(
      'disableCamera',
          () async {
        if (!_isCameraEnabled) {
          return false;
        }

        _isCameraEnabled = false;

        return true;
      },
    );
  }

  Future<void> toggleCamera() async {
    await _runSerialized(
      'toggleCamera',
          () async {
        // State is read inside the serialized operation.
        // Rapid taps therefore cannot calculate from stale state.
        _isCameraEnabled = !_isCameraEnabled;

        return true;
      },
    );
  }

  // =============================================================
  // FRONT / BACK CAMERA
  // =============================================================

  Future<void> switchCamera() async {
    await _runSerialized(
      'switchCamera',
          () async {
        _isFrontCamera = !_isFrontCamera;

        return true;
      },
    );
  }

  // =============================================================
  // FLASH
  // =============================================================

  Future<void> enableFlash() async {
    await _runSerialized(
      'enableFlash',
          () async {
        if (_isFlashOn) {
          return false;
        }

        _isFlashOn = true;

        return true;
      },
    );
  }

  Future<void> disableFlash() async {
    await _runSerialized(
      'disableFlash',
          () async {
        if (!_isFlashOn) {
          return false;
        }

        _isFlashOn = false;

        return true;
      },
    );
  }

  Future<void> toggleFlash() async {
    await _runSerialized(
      'toggleFlash',
          () async {
        _isFlashOn = !_isFlashOn;

        return true;
      },
    );
  }

  // =============================================================
  // ZOOM
  // =============================================================

  Future<void> setZoom(
      double value,
      ) async {
    if (!value.isFinite) {
      throw ArgumentError.value(
        value,
        'value',
        'Zoom must be a finite number.',
      );
    }

    final double normalizedValue = value
        .clamp(
      _minimumZoom,
      _maximumZoom,
    )
        .toDouble();

    await _runSerialized(
      'setZoom',
          () async {
        if (_zoomLevel == normalizedValue) {
          return false;
        }

        _zoomLevel = normalizedValue;

        return true;
      },
    );
  }

  // =============================================================
  // PREVIEW SIZE
  // =============================================================

  Future<void> setPreviewSize({
    required int width,
    required int height,
  }) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'Camera preview width and height must be greater than zero.',
      );
    }

    await _runSerialized(
      'setPreviewSize',
          () async {
        if (_previewWidth == width &&
            _previewHeight == height) {
          return false;
        }

        _previewWidth = width;

        _previewHeight = height;

        return true;
      },
    );
  }

  // =============================================================
  // QUALITY PRESETS
  // =============================================================

  Future<void> applyLowQuality() async {
    await _applyPreviewPreset(
      operation: 'applyLowQuality',
      width: 640,
      height: 360,
    );
  }

  Future<void> applyMediumQuality() async {
    await _applyPreviewPreset(
      operation: 'applyMediumQuality',
      width: 960,
      height: 540,
    );
  }

  Future<void> applyHDQuality() async {
    await _applyPreviewPreset(
      operation: 'applyHDQuality',
      width: 1280,
      height: 720,
    );
  }

  Future<void> applyFullHDQuality() async {
    await _applyPreviewPreset(
      operation: 'applyFullHDQuality',
      width: 1920,
      height: 1080,
    );
  }

  Future<void> _applyPreviewPreset({
    required String operation,
    required int width,
    required int height,
  }) async {
    await _runSerialized(
      operation,
          () async {
        if (_previewWidth == width &&
            _previewHeight == height) {
          return false;
        }

        _previewWidth = width;

        _previewHeight = height;

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
          () async {
        final bool changed =
            _isInitialized ||
                !_isCameraEnabled ||
                !_isFrontCamera ||
                _isFlashOn ||
                _zoomLevel != _minimumZoom ||
                _previewWidth != _defaultPreviewWidth ||
                _previewHeight != _defaultPreviewHeight;

        _isInitialized = false;

        _isCameraEnabled = true;

        _isFrontCamera = true;

        _isFlashOn = false;

        _zoomLevel = _minimumZoom;

        _previewWidth = _defaultPreviewWidth;

        _previewHeight = _defaultPreviewHeight;

        return changed;
      },
    );
  }

  // =============================================================
  // SERIALIZED OPERATION ENGINE
  // =============================================================

  Future<void> _runSerialized(
      String operation,
      Future<bool> Function() action,
      ) {
    final Completer<void> completer = Completer<void>();

    _operationQueue = _operationQueue.then<void>(
          (_) async {
        if (_isDisposed) {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'CameraManager is disposed. '
                    'Operation "$operation" cannot run.',
              ),
            );
          }

          return;
        }

        try {
          final bool changed = await action();

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

  void _ensureUsable() {
    if (_isDisposed) {
      throw StateError(
        'CameraManager has already been disposed.',
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
      'JR CALL [CameraManager/$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [CameraManager/$source]',
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

    _isInitialized = false;

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 25 VERIFIED CONTRACT:
//
// ✓ Public CameraManager() constructor preserved.
// ✓ Existing public getters preserved.
// ✓ Existing public async APIs preserved.
//
// ✓ Default state preserved:
//   camera enabled
//   front camera
//   flash off
//   zoom 1.0
//   preview 1280x720
//
// ✓ Camera mutations serialized.
// ✓ Camera toggle stale-state race removed.
// ✓ Camera switching race removed.
// ✓ Flash toggle stale-state race removed.
// ✓ Zoom finite-value validation added.
// ✓ Zoom 1.0–10.0 compatibility preserved.
// ✓ Preview-size validation added.
// ✓ Quality presets preserved.
// ✓ Duplicate state notifications reduced.
// ✓ Use-after-dispose rejected safely.
// ✓ Reset remains lifecycle-safe.
//
// ✓ No MediaStream created.
// ✓ No MediaStreamTrack ownership added.
// ✓ No PeerConnection ownership added.
// ✓ No signaling ownership added.
// ✓ No ICE ownership added.
// ✓ No recovery ownership added.
// ===============================================================