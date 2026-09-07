import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: media_manager.dart
/// Location: lib/services/managers/media_manager.dart
///
/// FINAL PRODUCTION LOCAL MEDIA MANAGER
///
/// OWNERSHIP:
///
/// MediaManager:
/// - Local user-media acquisition.
/// - Current owned local MediaStream.
/// - Audio/video track enabled state.
/// - Local media cleanup.
///
/// PeerConnectionManager:
/// - Attaches acquired tracks to PeerConnection.
///
/// CameraManager:
/// - High-level camera control.
///
/// SpeakerManager:
/// - High-level audio-route control.
///
/// ScreenShareService:
/// - Screen capture.
///
/// CallService:
/// - Complete call lifecycle.
///
/// IMPORTANT:
///
/// This class does NOT:
/// - Create PeerConnections.
/// - Persist SDP/ICE.
/// - Own call status.
/// - Own recovery policy.
/// - Own bitrate adaptation.
/// - Own recording.
/// - Own screen sharing.
///
/// Existing switchCamera() / setSpeakerphone() APIs are retained
/// only for source compatibility.
/// ===========================================================

class MediaManager extends ChangeNotifier {
  MediaManager._();

  static final MediaManager instance = MediaManager._();

  // ===========================================================
  // MEDIA STATE
  // ===========================================================

  MediaStream? _localStream;

  bool _initialized = false;

  bool _audioEnabled = true;

  bool _videoEnabled = true;

  bool _disposed = false;

  int _mediaGeneration = 0;

  // ===========================================================
  // ACQUISITION CONCURRENCY
  // ===========================================================

  Future<MediaStream?>? _activeInitializationFuture;

  bool? _activeInitializationAudio;

  bool? _activeInitializationVideo;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  MediaStream? get localStream => _localStream;

  bool get isInitialized => _initialized;

  bool get isAudioEnabled => _audioEnabled;

  bool get isVideoEnabled => _videoEnabled;

  bool get hasAudioTrack =>
      _localStream?.getAudioTracks().isNotEmpty ?? false;

  bool get hasVideoTrack =>
      _localStream?.getVideoTracks().isNotEmpty ?? false;

  // ===========================================================
  // CURRENT RESOLUTION
  // ===========================================================

  Future<Map<String, int>> get currentResolutionProfile {
    final MediaStream? stream = _localStream;

    if (stream == null) {
      return Future<Map<String, int>>.value(
        const <String, int>{
          'width': 0,
          'height': 0,
        },
      );
    }

    for (final MediaStreamTrack track in stream.getVideoTracks()) {
      try {
        final Map<String, dynamic> settings = track.getSettings();

        final int? width = _positiveInt(
          settings['width'],
        );

        final int? height = _positiveInt(
          settings['height'],
        );

        if (width != null && height != null) {
          return Future<Map<String, int>>.value(
            <String, int>{
              'width': width,
              'height': height,
            },
          );
        }
      } catch (error, stackTrace) {
        _reportError(
          'resolution settings',
          error,
          stackTrace,
        );
      }
    }

    return Future<Map<String, int>>.value(
      const <String, int>{
        'width': 0,
        'height': 0,
      },
    );
  }

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() async {
    await initializeMedia(
      video: true,
      audio: true,
    );
  }

  Future<MediaStream?> initializeMedia({
    bool video = true,
    bool audio = true,
  }) {
    if (_disposed) {
      return Future<MediaStream?>.value(
        null,
      );
    }

    final Future<MediaStream?>? active =
        _activeInitializationFuture;

    if (active != null) {
      final bool sameRequest =
          _activeInitializationAudio == audio &&
              _activeInitializationVideo == video;

      if (sameRequest) {
        return active;
      }

      _mediaGeneration++;

      final MediaStream? current = _localStream;

      if (_streamSatisfiesRequest(
        current,
        audio: audio,
        video: video,
      )) {
        _applyTrackPreferences(
          current!,
          audio: audio,
          video: video,
        );

        _initialized = true;

        _audioEnabled = audio;

        _videoEnabled = video;

        _notifySafely();

        return Future<MediaStream?>.value(
          current,
        );
      }

      return active.then(
            (_) => initializeMedia(
          video: video,
          audio: audio,
        ),
      );
    }

    final MediaStream? current = _localStream;

    if (_streamSatisfiesRequest(
      current,
      audio: audio,
      video: video,
    )) {
      _applyTrackPreferences(
        current!,
        audio: audio,
        video: video,
      );

      _initialized = true;

      _audioEnabled = audio;

      _videoEnabled = video;

      _notifySafely();

      return Future<MediaStream?>.value(
        current,
      );
    }

    if (!audio && !video) {
      _audioEnabled = false;

      _videoEnabled = false;

      _notifySafely();

      return Future<MediaStream?>.value(
        current,
      );
    }

    final int generation = ++_mediaGeneration;

    final Future<MediaStream?> operation =
    _initializeMediaInternal(
      generation: generation,
      video: video,
      audio: audio,
    );

    late final Future<MediaStream?> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _activeInitializationFuture,
        tracked,
      )) {
        _activeInitializationFuture = null;

        _activeInitializationAudio = null;

        _activeInitializationVideo = null;
      }
    });

    _activeInitializationFuture = tracked;

    _activeInitializationAudio = audio;

    _activeInitializationVideo = video;

    return tracked;
  }

  Future<MediaStream?> _initializeMediaInternal({
    required int generation,
    required bool video,
    required bool audio,
  }) async {
    final MediaStream? previousStream = _localStream;

    MediaStream? acquiredStream;

    try {
      acquiredStream = await navigator.mediaDevices.getUserMedia(
        <String, dynamic>{
          'audio': audio
              ? <String, dynamic>{
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          }
              : false,
          'video': video
              ? <String, dynamic>{
            'width': <String, dynamic>{
              'ideal': 1280,
            },
            'height': <String, dynamic>{
              'ideal': 720,
            },
            'frameRate': <String, dynamic>{
              'ideal': 30,
              'max': 30,
            },
            'aspectRatio': <String, dynamic>{
              'ideal': 16 / 9,
            },
            'facingMode': 'user',
          }
              : false,
        },
      );

      if (!_isGenerationCurrent(
        generation,
      )) {
        await _stopAndDisposeStream(
          acquiredStream,
        );

        return _localStream;
      }

      if (!_streamSatisfiesRequest(
        acquiredStream,
        audio: audio,
        video: video,
      )) {
        await _stopAndDisposeStream(
          acquiredStream,
        );

        throw StateError(
          'Requested local media tracks '
              'were not acquired.',
        );
      }

      _applyTrackPreferences(
        acquiredStream,
        audio: audio,
        video: video,
      );

      _localStream = acquiredStream;

      _initialized = true;

      _audioEnabled = audio;

      _videoEnabled = video;

      _notifySafely();

      if (previousStream != null &&
          !identical(
            previousStream,
            acquiredStream,
          )) {
        await _stopAndDisposeStream(
          previousStream,
        );
      }

      return acquiredStream;
    } catch (error, stackTrace) {
      if (acquiredStream != null &&
          !identical(
            acquiredStream,
            _localStream,
          )) {
        await _stopAndDisposeStream(
          acquiredStream,
        );
      }

      if (_isGenerationCurrent(
        generation,
      )) {
        _initialized = _localStream != null;

        _reportError(
          'initialization',
          error,
          stackTrace,
        );

        _notifySafely();
      }

      return _localStream;
    }
  }

  // ===========================================================
  // STREAM ATTACHMENT
  // ===========================================================

  void attachStream(
      MediaStream? stream,
      ) {
    if (_disposed) {
      return;
    }

    _mediaGeneration++;

    final MediaStream? previousStream = _localStream;

    if (identical(
      previousStream,
      stream,
    )) {
      _syncStateFromStream(
        stream,
      );

      _notifySafely();

      return;
    }

    _localStream = stream;

    _syncStateFromStream(
      stream,
    );

    _notifySafely();

    if (previousStream != null) {
      unawaited(
        _stopAndDisposeStream(
          previousStream,
        ),
      );
    }
  }

  // ===========================================================
  // AUDIO TRACK STATE
  // ===========================================================

  Future<void> setAudioEnabled(
      bool enabled,
      ) async {
    if (_disposed) {
      return;
    }

    final MediaStream? stream = _localStream;

    if (stream != null) {
      for (final MediaStreamTrack track
      in stream.getAudioTracks()) {
        track.enabled = enabled;
      }
    }

    _audioEnabled = enabled;

    _notifySafely();
  }

  Future<void> toggleAudio() async {
    await setAudioEnabled(
      !_audioEnabled,
    );
  }

  // ===========================================================
  // VIDEO TRACK STATE
  // ===========================================================

  Future<void> setVideoEnabled(
      bool enabled,
      ) async {
    if (_disposed) {
      return;
    }

    final MediaStream? stream = _localStream;

    if (stream != null) {
      for (final MediaStreamTrack track
      in stream.getVideoTracks()) {
        track.enabled = enabled;
      }
    }

    _videoEnabled = enabled;

    _notifySafely();
  }

  Future<void> toggleVideo() async {
    await setVideoEnabled(
      !_videoEnabled,
    );
  }

  // ===========================================================
  // CAMERA COMPATIBILITY
  // ===========================================================

  Future<void> switchCamera() async {
    if (_disposed) {
      return;
    }

    final List<MediaStreamTrack>? tracks =
    _localStream?.getVideoTracks();

    if (tracks == null || tracks.isEmpty) {
      return;
    }

    try {
      await Helper.switchCamera(
        tracks.first,
      );
    } catch (error, stackTrace) {
      _reportError(
        'camera switch',
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // SPEAKER COMPATIBILITY
  // ===========================================================

  Future<void> setSpeakerphone(
      bool enable,
      ) async {
    if (_disposed) {
      return;
    }

    try {
      await Helper.setSpeakerphoneOn(
        enable,
      );
    } catch (error, stackTrace) {
      _reportError(
        'speaker routing',
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // DEVICES
  // ===========================================================

  Future<List<MediaDeviceInfo>> getAudioInputDevices() async {
    if (_disposed) {
      return const <MediaDeviceInfo>[];
    }

    try {
      final List<MediaDeviceInfo> devices =
      await navigator.mediaDevices.enumerateDevices();

      return List<MediaDeviceInfo>.unmodifiable(
        devices.where(
              (MediaDeviceInfo device) =>
          device.kind?.trim().toLowerCase() ==
              'audio' 'input',
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'audio device enumeration',
        error,
        stackTrace,
      );

      return const <MediaDeviceInfo>[];
    }
  }

  Future<List<MediaDeviceInfo>> getVideoInputDevices() async {
    if (_disposed) {
      return const <MediaDeviceInfo>[];
    }

    try {
      final List<MediaDeviceInfo> devices =
      await navigator.mediaDevices.enumerateDevices();

      return List<MediaDeviceInfo>.unmodifiable(
        devices.where(
              (MediaDeviceInfo device) =>
          device.kind?.trim().toLowerCase() ==
              'video' 'input',
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'video device enumeration',
        error,
        stackTrace,
      );

      return const <MediaDeviceInfo>[];
    }
  }

  Future<void> refreshAudioDevices() async {
    if (_disposed) {
      return;
    }

    try {
      await navigator.mediaDevices.enumerateDevices();

      _notifySafely();
    } catch (error, stackTrace) {
      _reportError(
        'device refresh',
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // MEDIA DISPOSAL
  // ===========================================================

  Future<void> disposeMedia() async {
    if (_disposed) {
      return;
    }

    _mediaGeneration++;

    final MediaStream? stream = _localStream;

    _localStream = null;

    _initialized = false;

    _audioEnabled = true;

    _videoEnabled = true;

    _notifySafely();

    if (stream != null) {
      await _stopAndDisposeStream(
        stream,
      );
    }
  }

  Future<void> _stopAndDisposeStream(
      MediaStream stream,
      ) async {
    final List<MediaStreamTrack> tracks =
    List<MediaStreamTrack>.from(
      stream.getTracks(),
    );

    for (final MediaStreamTrack track in tracks) {
      try {
        await track.stop();
      } catch (error, stackTrace) {
        _reportError(
          'track stop',
          error,
          stackTrace,
        );
      }
    }

    try {
      await stream.dispose();
    } catch (error, stackTrace) {
      _reportError(
        'stream dispose',
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // INTERNAL STREAM STATE
  // ===========================================================

  bool _streamSatisfiesRequest(
      MediaStream? stream, {
        required bool audio,
        required bool video,
      }) {
    if (stream == null) {
      return false;
    }

    if (audio && stream.getAudioTracks().isEmpty) {
      return false;
    }

    if (video && stream.getVideoTracks().isEmpty) {
      return false;
    }

    return true;
  }

  void _applyTrackPreferences(
      MediaStream stream, {
        required bool audio,
        required bool video,
      }) {
    for (final MediaStreamTrack track
    in stream.getAudioTracks()) {
      track.enabled = audio;
    }

    for (final MediaStreamTrack track
    in stream.getVideoTracks()) {
      track.enabled = video;
    }
  }

  void _syncStateFromStream(
      MediaStream? stream,
      ) {
    if (stream == null) {
      _initialized = false;

      return;
    }

    _initialized = true;

    final List<MediaStreamTrack> audioTracks =
    stream.getAudioTracks();

    final List<MediaStreamTrack> videoTracks =
    stream.getVideoTracks();

    if (audioTracks.isNotEmpty) {
      _audioEnabled = audioTracks.any(
            (MediaStreamTrack track) => track.enabled,
      );
    }

    if (videoTracks.isNotEmpty) {
      _videoEnabled = videoTracks.any(
            (MediaStreamTrack track) => track.enabled,
      );
    } else {
      _videoEnabled = false;
    }
  }

  bool _isGenerationCurrent(
      int generation,
      ) {
    return !_disposed &&
        generation == _mediaGeneration;
  }

  int? _positiveInt(
      Object? value,
      ) {
    int? result;

    if (value is int) {
      result = value;
    } else if (value is num && value.isFinite) {
      result = value.round();
    } else if (value is String) {
      result = int.tryParse(
        value.trim(),
      );
    }

    if (result == null || result <= 0) {
      return null;
    }

    return result;
  }

  // ===========================================================
  // NOTIFICATION
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
          '[MediaManager/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[MediaManager/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // COMPLETE DISPOSAL
  // ===========================================================

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _mediaGeneration++;

    _activeInitializationFuture = null;

    _activeInitializationAudio = null;

    _activeInitializationVideo = null;

    final MediaStream? stream = _localStream;

    _localStream = null;

    _initialized = false;

    if (stream != null) {
      unawaited(
        _stopAndDisposeStream(
          stream,
        ),
      );
    }

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 12 FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ Concurrent identical acquisition deduplicated.
// ✓ Different acquisition requests do not race.
// ✓ Stale getUserMedia result cannot overwrite newer media.
// ✓ Stale acquired stream is safely stopped/disposed.
// ✓ Existing valid media preserved when replacement fails.
// ✓ Requested track kinds verified before stream commit.
// ✓ Local stream ownership is explicit.
// ✓ Replaced owned streams are cleaned up.
// ✓ Audio/video track enable state preserved.
// ✓ Actual current resolution used when available.
// ✓ No invented 1280x720 "current" state when no video exists.
// ✓ MediaStreamTrack.stop() awaited in async cleanup.
// ✓ MediaStream.dispose() awaited in async cleanup.
// ✓ Device enumeration remains input-only.
// ✓ Platform device ordering preserved.
// ✓ Camera compatibility API preserved.
// ✓ Speaker compatibility API preserved.
// ✓ CameraManager/SpeakerManager high-level ownership preserved.
// ✓ No PeerConnection ownership.
// ✓ No signaling ownership.
// ✓ No recovery ownership.
// ✓ No bitrate ownership.
// ✓ No recording/screen-share ownership.
//
// STATUS:
// FILE 12 CORRECTED VERIFICATION VERSION.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 13
// lib/services/managers/audio_manager.dart
// ===============================================================