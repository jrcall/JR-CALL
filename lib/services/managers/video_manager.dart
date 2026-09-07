import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: video_manager.dart
/// Location: lib/services/managers/video_manager.dart
///
/// FINAL PRODUCTION ACTIVE-CALL VIDEO MANAGER
///
/// OWNERSHIP:
///
/// VideoManager:
/// - Local RTCVideoRenderer lifecycle.
/// - Remote RTCVideoRenderer lifecycle.
/// - Local/remote renderer stream binding.
/// - Compatibility video-track enabled state.
/// - Compatibility camera-facing state.
///
/// MediaManager:
/// - Owns MediaStream acquisition/lifecycle/disposal.
///
/// CameraManager:
/// - High-level camera control.
///
/// PeerConnectionManager:
/// - Owns PeerConnection lifecycle.
///
/// IMPORTANT:
///
/// VideoManager does NOT:
/// - Acquire MediaStream.
/// - Stop/dispose MediaStream tracks.
/// - Create PeerConnection.
/// - Persist SDP/ICE.
/// - Own call lifecycle.
/// - Own recovery.
/// - Own bitrate adaptation.
/// - Own recording.
/// - Own screen sharing.
/// ===========================================================

class VideoManager extends ChangeNotifier {
  VideoManager._();

  static final VideoManager instance =
  VideoManager._();

  // ===========================================================
  // RENDERERS
  // ===========================================================

  RTCVideoRenderer _localRenderer =
  RTCVideoRenderer();

  RTCVideoRenderer _remoteRenderer =
  RTCVideoRenderer();

  // ===========================================================
  // STREAM REFERENCES
  //
  // These are references only.
  // VideoManager never owns/stops/disposes these streams.
  // ===========================================================

  MediaStream? _localStream;

  MediaStream? _remoteStream;

  // ===========================================================
  // STATE
  // ===========================================================

  bool _initialized = false;

  bool _videoEnabled = true;

  bool _frontCamera = true;

  bool _disposed = false;

  int _rendererGeneration = 0;

  // ===========================================================
  // RENDERER LIFECYCLE SERIALIZATION
  // ===========================================================

  Future<void> _rendererLifecycleTail =
  Future<void>.value();

  Future<void>? _activeRendererInitialization;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  bool get isInitialized =>
      _initialized;

  bool get isVideoEnabled =>
      _videoEnabled;

  bool get isFrontCamera =>
      _frontCamera;

  RTCVideoRenderer get localRenderer =>
      _localRenderer;

  RTCVideoRenderer get remoteRenderer =>
      _remoteRenderer;

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() async {
    await initializeRenderers();
  }

  Future<void> initializeRenderers() {
    if (_disposed) {
      return Future<void>.value();
    }

    if (_initialized) {
      return Future<void>.value();
    }

    final Future<void>? active =
        _activeRendererInitialization;

    if (active != null) {
      return active;
    }

    final int generation =
        _rendererGeneration;

    final RTCVideoRenderer localRenderer =
        _localRenderer;

    final RTCVideoRenderer remoteRenderer =
        _remoteRenderer;

    final Future<void> operation =
    _queueRendererLifecycle(
          () => _initializeRendererPair(
        generation: generation,
        localRenderer: localRenderer,
        remoteRenderer: remoteRenderer,
      ),
    );

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _activeRendererInitialization,
        tracked,
      )) {
        _activeRendererInitialization =
        null;
      }
    });

    _activeRendererInitialization =
        tracked;

    return tracked;
  }

  Future<void> _initializeRendererPair({
    required int generation,
    required RTCVideoRenderer localRenderer,
    required RTCVideoRenderer remoteRenderer,
  }) async {
    if (!_isRendererPairCurrent(
      generation: generation,
      localRenderer: localRenderer,
      remoteRenderer: remoteRenderer,
    )) {
      return;
    }

    try {
      await localRenderer.initialize();

      if (!_isRendererPairCurrent(
        generation: generation,
        localRenderer: localRenderer,
        remoteRenderer: remoteRenderer,
      )) {
        return;
      }

      await remoteRenderer.initialize();

      if (!_isRendererPairCurrent(
        generation: generation,
        localRenderer: localRenderer,
        remoteRenderer: remoteRenderer,
      )) {
        return;
      }

      localRenderer.srcObject =
          _localStream;

      remoteRenderer.srcObject =
          _remoteStream;

      _initialized = true;

      _notifySafely();
    } catch (error, stackTrace) {
      if (_isRendererPairCurrent(
        generation: generation,
        localRenderer: localRenderer,
        remoteRenderer: remoteRenderer,
      )) {
        _initialized = false;

        _rendererGeneration++;

        _localRenderer =
            RTCVideoRenderer();

        _remoteRenderer =
            RTCVideoRenderer();

        _reportError(
          'renderer initialization',
          error,
          stackTrace,
        );

        _notifySafely();
      }

      await _disposeRendererPair(
        localRenderer,
        remoteRenderer,
      );

      if (!_disposed) {
        rethrow;
      }
    }
  }

  // ===========================================================
  // LOCAL STREAM
  // ===========================================================

  void setLocalStream(
      MediaStream? stream,
      ) {
    if (_disposed) {
      return;
    }

    _localStream = stream;

    if (_initialized) {
      _localRenderer.srcObject =
          stream;
    }

    _notifySafely();
  }

  // ===========================================================
  // REMOTE STREAM
  // ===========================================================

  void setRemoteStream(
      MediaStream? stream,
      ) {
    if (_disposed) {
      return;
    }

    _remoteStream = stream;

    if (_initialized) {
      _remoteRenderer.srcObject =
          stream;
    }

    _notifySafely();
  }

  // ===========================================================
  // VIDEO ENABLE STATE
  // ===========================================================

  Future<void> enableVideo(
      MediaStream? stream,
      ) async {
    await setVideoEnabled(
      stream,
      true,
    );
  }

  Future<void> disableVideo(
      MediaStream? stream,
      ) async {
    await setVideoEnabled(
      stream,
      false,
    );
  }

  Future<void> setVideoEnabled(
      MediaStream? stream,
      bool enabled,
      ) async {
    if (_disposed) {
      return;
    }

    if (stream != null) {
      for (final MediaStreamTrack track
      in stream.getVideoTracks()) {
        track.enabled = enabled;
      }
    }

    if (_videoEnabled ==
        enabled) {
      return;
    }

    _videoEnabled = enabled;

    _notifySafely();
  }

  Future<void> toggleVideo(
      MediaStream? stream,
      ) async {
    await setVideoEnabled(
      stream,
      !_videoEnabled,
    );
  }

  // ===========================================================
  // CAMERA SWITCH COMPATIBILITY
  //
  // CameraManager remains the high-level owner.
  //
  // Helper.switchCamera() returns the resulting front-camera state.
  // Do not blindly invert local state.
  // ===========================================================

  Future<void> switchCamera(
      MediaStream? stream,
      ) async {
    if (_disposed ||
        stream == null) {
      return;
    }

    final List<MediaStreamTrack> tracks =
    stream.getVideoTracks();

    if (tracks.isEmpty) {
      return;
    }

    try {
      final bool frontCamera =
      await Helper.switchCamera(
        tracks.first,
      );

      if (_disposed) {
        return;
      }

      if (_frontCamera ==
          frontCamera) {
        return;
      }

      _frontCamera =
          frontCamera;

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError(
        'camera switch',
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // RESET
  //
  // Reset renderer bindings/state only.
  //
  // Media streams/tracks remain MediaManager-owned.
  // ===========================================================

  Future<void> reset() async {
    if (_disposed) {
      return;
    }

    _localStream = null;

    _remoteStream = null;

    if (_initialized) {
      _localRenderer.srcObject =
      null;

      _remoteRenderer.srcObject =
      null;
    }

    _videoEnabled = true;

    _frontCamera = true;

    _notifySafely();
  }

  // ===========================================================
  // RENDERER-ONLY DISPOSAL
  //
  // IMPORTANT:
  //
  // This is NOT ChangeNotifier.dispose().
  //
  // Renderer-only disposal must permit later reinitialization.
  // ===========================================================

  Future<void> disposeRenderers() {
    if (_disposed) {
      return Future<void>.value();
    }

    final RTCVideoRenderer oldLocalRenderer =
        _localRenderer;

    final RTCVideoRenderer oldRemoteRenderer =
        _remoteRenderer;

    _rendererGeneration++;

    _activeRendererInitialization =
    null;

    _initialized = false;

    _localStream = null;

    _remoteStream = null;

    try {
      oldLocalRenderer.srcObject =
      null;
    } catch (error, stackTrace) {
      _reportError(
        'local renderer detach',
        error,
        stackTrace,
      );
    }

    try {
      oldRemoteRenderer.srcObject =
      null;
    } catch (error, stackTrace) {
      _reportError(
        'remote renderer detach',
        error,
        stackTrace,
      );
    }

    // Fresh pair allows safe reinitialization after this operation.
    _localRenderer =
        RTCVideoRenderer();

    _remoteRenderer =
        RTCVideoRenderer();

    _notifySafely();

    return _queueRendererLifecycle(
          () => _disposeRendererPair(
        oldLocalRenderer,
        oldRemoteRenderer,
      ),
    );
  }

  // ===========================================================
  // SERIALIZED RENDERER LIFECYCLE
  // ===========================================================

  Future<void> _queueRendererLifecycle(
      Future<void> Function() operation,
      ) {
    final Completer<void> completer =
    Completer<void>();

    final Future<void> next =
    _rendererLifecycleTail.then<void>(
          (_) async {
        try {
          await operation();

          if (!completer.isCompleted) {
            completer.complete();
          }
        } catch (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(
              error,
              stackTrace,
            );
          }
        }
      },
    );

    _rendererLifecycleTail =
        next.then<void>(
              (_) {},
          onError: (
              Object _,
              StackTrace _,
              ) {},
        );

    return completer.future;
  }

  // ===========================================================
  // RENDERER VALIDATION
  // ===========================================================

  bool _isRendererPairCurrent({
    required int generation,
    required RTCVideoRenderer localRenderer,
    required RTCVideoRenderer remoteRenderer,
  }) {
    return !_disposed &&
        generation ==
            _rendererGeneration &&
        identical(
          _localRenderer,
          localRenderer,
        ) &&
        identical(
          _remoteRenderer,
          remoteRenderer,
        );
  }

  // ===========================================================
  // RENDERER CLEANUP
  // ===========================================================

  Future<void> _disposeRendererPair(
      RTCVideoRenderer localRenderer,
      RTCVideoRenderer remoteRenderer,
      ) async {
    try {
      localRenderer.srcObject =
      null;
    } catch (error, stackTrace) {
      _reportError(
        'local renderer stream cleanup',
        error,
        stackTrace,
      );
    }

    try {
      remoteRenderer.srcObject =
      null;
    } catch (error, stackTrace) {
      _reportError(
        'remote renderer stream cleanup',
        error,
        stackTrace,
      );
    }

    try {
      await localRenderer.dispose();
    } catch (error, stackTrace) {
      _reportError(
        'local renderer dispose',
        error,
        stackTrace,
      );
    }

    try {
      await remoteRenderer.dispose();
    } catch (error, stackTrace) {
      _reportError(
        'remote renderer dispose',
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // SAFE NOTIFICATION
  // ===========================================================

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ===========================================================
  // LOGGING
  // ===========================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[VideoManager/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[VideoManager/$source]',
        stackTrace:
        stackTrace,
      );
    }
  }

  // ===========================================================
  // COMPLETE MANAGER DISPOSAL
  // ===========================================================

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _rendererGeneration++;

    _activeRendererInitialization =
    null;

    _initialized = false;

    _localStream = null;

    _remoteStream = null;

    final RTCVideoRenderer localRenderer =
        _localRenderer;

    final RTCVideoRenderer remoteRenderer =
        _remoteRenderer;

    try {
      localRenderer.srcObject =
      null;
    } catch (error, stackTrace) {
      _reportError(
        'dispose local detach',
        error,
        stackTrace,
      );
    }

    try {
      remoteRenderer.srcObject =
      null;
    } catch (error, stackTrace) {
      _reportError(
        'dispose remote detach',
        error,
        stackTrace,
      );
    }

    final Future<void> cleanup =
    _rendererLifecycleTail.then<void>(
          (_) async {
        await _disposeRendererPair(
          localRenderer,
          remoteRenderer,
        );
      },
    );

    _rendererLifecycleTail =
        cleanup.then<void>(
              (_) {},
          onError: (
              Object _,
              StackTrace _,
              ) {},
        );

    unawaited(
      cleanup,
    );

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 14 FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ Accidental Undo/copy-state uncertainty removed by full rebuild.
// ✓ Renderer initialization serialized.
// ✓ Duplicate concurrent initialization deduplicated.
// ✓ Stale renderer initialization cannot publish.
// ✓ Partial renderer initialization is safely cleaned up.
// ✓ Failed pair is replaced with fresh renderers for retry.
// ✓ disposeRenderers() is renderer-only, not terminal manager dispose.
// ✓ Renderer disposal can be followed by safe reinitialization.
// ✓ ChangeNotifier.dispose() remains terminal.
// ✓ Local/remote stream binding preserved.
// ✓ Streams are never stopped/disposed here.
// ✓ MediaManager remains MediaStream lifecycle owner.
// ✓ Video enabled state applies to every supplied video track.
// ✓ Camera switch uses returned front-camera state.
// ✓ Blind camera-state inversion removed.
// ✓ CameraManager high-level ownership preserved.
// ✓ Renderer initialize()/dispose() are properly awaited.
// ✓ Synchronous manager dispose performs async best-effort cleanup.
// ✓ No post-dispose notifyListeners().
// ✓ No PeerConnection ownership.
// ✓ No signaling ownership.
// ✓ No recovery ownership.
// ✓ No bitrate ownership.
// ✓ No recording/screen-share ownership.
//
// STATUS:
// VIDEO MANAGER FINALIZED.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 15
// lib/services/managers/data_channel_manager.dart
// ===============================================================