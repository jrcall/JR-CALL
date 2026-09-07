// ===============================================================
// JR CALL
// File: screen_share_service.dart
// Location: lib/services/call/screen_share_service.dart
//
// MASTER PRODUCTION SCREEN SHARE SERVICE
//
// RESPONSIBILITIES:
//
// - Start display capture.
// - Stop display capture.
// - Track screen-sharing state.
// - Replace a supplied WebRTC video sender with screen video.
// - Detect native/user-ended screen sharing.
// - Serialize start / stop / toggle operations.
// - Own and dispose ONLY the display-capture MediaStream.
//
// OWNERSHIP:
//
// ScreenShareService:
// - Owns the display-capture MediaStream created by getDisplayMedia().
//
// WebRTCService / CallService:
// - Own normal camera MediaStream / MediaStreamTrack.
// - Own PeerConnection and sender lifecycle.
// - Restore the camera track after screen sharing ends.
//
// AudioManager / MicrophoneManager:
// - Own normal call microphone/audio path.
//
// IMPORTANT:
//
// - Screen capture does NOT request another audio track.
// - No duplicate call microphone/audio.
// - No normal camera MediaStream ownership here.
// - No signaling ownership here.
// - No ICE ownership here.
// - No recovery ownership here.
// - No call-lifecycle ownership here.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ScreenShareService extends ChangeNotifier {
  ScreenShareService._();

  static final ScreenShareService instance =
  ScreenShareService._();

  // =============================================================
  // STATE
  // =============================================================

  MediaStream? _screenStream;

  bool _isSharing = false;

  bool _isDisposed = false;

  int _captureGeneration = 0;

  // =============================================================
  // SERIALIZED OPERATION QUEUE
  // =============================================================

  Future<void> _operationQueue =
  Future<void>.value();

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isSharing => _isSharing;

  MediaStream? get stream => _screenStream;

  bool get isDisposed => _isDisposed;

  // =============================================================
  // START SCREEN SHARE
  // =============================================================

  Future<MediaStream?> start() {
    return _runSerialized<MediaStream?>(
      'start',
      _startInternal,
    );
  }

  Future<MediaStream?> _startInternal() async {
    if (_isSharing &&
        _screenStream != null) {
      return _screenStream;
    }

    // Clean any inconsistent leftover stream before requesting
    // a new display-capture session.
    final MediaStream? previousStream =
        _screenStream;

    if (previousStream != null) {
      _screenStream = null;

      _isSharing = false;

      await _releaseOwnedStream(
        previousStream,
      );
    }

    final int generation =
    ++_captureGeneration;

    try {
      // IMPORTANT:
      // Normal call audio remains owned by the existing microphone /
      // WebRTC audio path. Screen sharing must not create a second
      // audio source.
      final Map<String, dynamic>
      mediaConstraints =
      <String, dynamic>{
        'audio': false,
        'video': true,
      };

      final MediaStream capturedStream =
      await navigator.mediaDevices
          .getDisplayMedia(
        mediaConstraints,
      );

      // The service may have been disposed while the platform
      // permission / capture picker was open.
      if (_isDisposed ||
          generation !=
              _captureGeneration) {
        await _releaseOwnedStream(
          capturedStream,
        );

        return null;
      }

      final List<MediaStreamTrack>
      videoTracks =
      capturedStream
          .getVideoTracks();

      if (videoTracks.isEmpty) {
        await _releaseOwnedStream(
          capturedStream,
        );

        return null;
      }

      final MediaStreamTrack screenTrack =
          videoTracks.first;

      _screenStream =
          capturedStream;

      _isSharing = true;

      // Native/user action can end display capture outside the app.
      //
      // Keep service state synchronized with that event.
      screenTrack.onEnded = () {
        unawaited(
          _handleScreenTrackEnded(
            capturedStream,
            generation,
          ),
        );
      };

      return capturedStream;
    } catch (error, stackTrace) {
      _reportError(
        'start',
        error,
        stackTrace,
      );

      if (generation ==
          _captureGeneration) {
        _screenStream = null;

        _isSharing = false;
      }

      // Existing compatibility preserved:
      // user cancellation / unsupported capture returns null.
      return null;
    }
  }

  // =============================================================
  // NATIVE SCREEN TRACK ENDED
  // =============================================================

  Future<void> _handleScreenTrackEnded(
      MediaStream capturedStream,
      int generation,
      ) async {
    if (_isDisposed ||
        generation !=
            _captureGeneration ||
        !identical(
          _screenStream,
          capturedStream,
        )) {
      return;
    }

    await _runSerialized<void>(
      'screenTrackEnded',
          () async {
        if (_isDisposed ||
            generation !=
                _captureGeneration ||
            !identical(
              _screenStream,
              capturedStream,
            )) {
          return;
        }

        await _stopInternal();
      },
    );
  }

  // =============================================================
  // STOP SCREEN SHARE
  // =============================================================

  Future<void> stop() {
    if (_isDisposed) {
      return Future<void>.value();
    }

    return _runSerialized<void>(
      'stop',
      _stopInternal,
    );
  }

  Future<void> _stopInternal() async {
    final MediaStream? activeStream =
        _screenStream;

    final bool wasSharing =
        _isSharing;

    _captureGeneration++;

    _screenStream = null;

    _isSharing = false;

    if (activeStream != null) {
      await _releaseOwnedStream(
        activeStream,
      );
    }

    if (!wasSharing &&
        activeStream == null) {
      return;
    }
  }

  // =============================================================
  // TOGGLE SCREEN SHARE
  // =============================================================

  Future<void> toggle() {
    return _runSerialized<void>(
      'toggle',
          () async {
        if (_isSharing &&
            _screenStream != null) {
          await _stopInternal();

          return;
        }

        await _startInternal();
      },
    );
  }

  // =============================================================
  // REPLACE VIDEO SENDER TRACK
  // =============================================================

  Future<void> replaceVideoTrack(
      RTCRtpSender sender,
      ) {
    return _runSerialized<void>(
      'replaceVideoTrack',
          () async {
        final MediaStream? activeStream =
            _screenStream;

        if (!_isSharing ||
            activeStream == null) {
          return;
        }

        final List<MediaStreamTrack>
        tracks =
        activeStream
            .getVideoTracks();

        if (tracks.isEmpty) {
          return;
        }

        // Existing compatibility API preserved.
        //
        // ScreenShareService does not own the sender or PeerConnection.
        // It only applies its currently owned screen track to the
        // sender supplied by WebRTCService / CallService.
        await sender.replaceTrack(
          tracks.first,
        );
      },
    );
  }

  // =============================================================
  // OWNED STREAM CLEANUP
  // =============================================================

  Future<void> _releaseOwnedStream(
      MediaStream stream,
      ) async {
    final List<MediaStreamTrack> tracks;

    try {
      tracks = stream.getTracks();
    } catch (error, stackTrace) {
      _reportError(
        'read screen tracks',
        error,
        stackTrace,
      );

      try {
        await stream.dispose();
      } catch (disposeError,
      disposeStackTrace) {
        _reportError(
          'dispose screen stream',
          disposeError,
          disposeStackTrace,
        );
      }

      return;
    }

    for (final MediaStreamTrack track
    in tracks) {
      try {
        // Prevent stop() from recursively triggering our own
        // screen-ended callback.
        track.onEnded = null;
      } catch (error, stackTrace) {
        _reportError(
          'detach screen-track callback',
          error,
          stackTrace,
        );
      }

      try {
        await track.stop();
      } catch (error, stackTrace) {
        _reportError(
          'stop screen track',
          error,
          stackTrace,
        );
      }
    }

    try {
      await stream.dispose();
    } catch (error, stackTrace) {
      _reportError(
        'dispose screen stream',
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // SERIALIZED OPERATION ENGINE
  // =============================================================

  Future<T> _runSerialized<T>(
      String operation,
      Future<T> Function() action,
      ) {
    final Completer<T> completer =
    Completer<T>();

    _operationQueue =
        _operationQueue.then<void>(
              (_) async {
            if (_isDisposed) {
              if (!completer.isCompleted) {
                completer.completeError(
                  StateError(
                    'ScreenShareService is disposed. '
                        'Operation "$operation" cannot run.',
                  ),
                );
              }

              return;
            }

            try {
              final T result =
              await action();

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
              _notifySafely();
            }
          },
        );

    return completer.future;
  }

  // =============================================================
  // NOTIFICATION
  // =============================================================

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
      'JR CALL '
          '[ScreenShareService/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[ScreenShareService/$source]',
        stackTrace:
        stackTrace,
      );
    }
  }

  // =============================================================
  // SERVICE CLEANUP
  // =============================================================

  /// Existing public compatibility API.
  ///
  /// This stops the current sharing session but does NOT permanently
  /// dispose the singleton, so it can be reused by a later call.
  Future<void> disposeService() async {
    if (_isDisposed) {
      return;
    }

    await stop();
  }

  // =============================================================
  // CHANGE NOTIFIER DISPOSE
  // =============================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _captureGeneration++;

    final MediaStream? activeStream =
        _screenStream;

    _screenStream = null;

    _isSharing = false;

    _isDisposed = true;

    if (activeStream != null) {
      unawaited(
        _releaseOwnedStream(
          activeStream,
        ),
      );
    }

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 29 VERIFIED CONTRACT:
//
// ✓ ScreenShareService.instance preserved.
// ✓ isSharing preserved.
// ✓ stream preserved.
// ✓ start() preserved.
// ✓ stop() preserved.
// ✓ toggle() preserved.
// ✓ replaceVideoTrack() preserved.
// ✓ disposeService() preserved.
//
// ✓ Display-capture stream remains service-owned.
// ✓ Duplicate display streams prevented.
// ✓ Start/stop/toggle operations serialized.
// ✓ Rapid toggle race removed.
// ✓ Stale async capture completion rejected.
// ✓ Native/user screen-share termination detected.
// ✓ Screen-ended callback cannot leak into a later session.
// ✓ Track callbacks detached before explicit stop.
// ✓ All owned tracks stopped.
// ✓ Owned MediaStream disposed.
// ✓ Cleanup is best-effort and call-safe.
//
// ✓ Screen sharing requests video only.
// ✓ Existing microphone/call audio is not duplicated.
// ✓ Provided RTCRtpSender can receive active screen track.
// ✓ Camera restoration remains WebRTCService/CallService-owned.
//
// ✓ No normal camera MediaStream ownership added.
// ✓ No PeerConnection ownership added.
// ✓ No signaling ownership added.
// ✓ No ICE ownership added.
// ✓ No recovery ownership added.
// ✓ No call-lifecycle ownership added.
// ===============================================================