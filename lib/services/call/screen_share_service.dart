import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: screen_share_service.dart
/// Description:
/// Screen Share Service
///
/// Features:
/// • Start Screen Sharing
/// • Stop Screen Sharing
/// • Switch Camera ↔ Screen
/// • Track Screen Share Status
///
/// Used by:
/// - video_call_screen.dart
/// - ai_call_engine.dart
/// - video_manager.dart
/// ===========================================================

class ScreenShareService extends ChangeNotifier {
  ScreenShareService._();

  static final ScreenShareService instance = ScreenShareService._();

  MediaStream? _screenStream;

  bool _isSharing = false;

  bool get isSharing => _isSharing;

  MediaStream? get stream => _screenStream;

  /// ==========================
  /// Start Screen Share
  /// ==========================
  Future<MediaStream?> start() async {
    if (_isSharing) return _screenStream;

    try {
      final mediaConstraints = <String, dynamic>{'audio': true, 'video': true};

      _screenStream = await navigator.mediaDevices.getDisplayMedia(
        mediaConstraints,
      );

      _isSharing = true;

      notifyListeners();

      return _screenStream;
    } catch (e) {
      debugPrint('Screen Share Error: $e');
      return null;
    }
  }

  /// ==========================
  /// Stop Screen Share
  /// ==========================
  Future<void> stop() async {
    if (_screenStream != null) {
      for (final track in _screenStream!.getTracks()) {
        track.stop();
      }

      await _screenStream!.dispose();

      _screenStream = null;
    }

    _isSharing = false;

    notifyListeners();
  }

  /// ==========================
  /// Toggle Screen Share
  /// ==========================
  Future<void> toggle() async {
    if (_isSharing) {
      await stop();
    } else {
      await start();
    }
  }

  /// ==========================
  /// Replace Video Sender Track
  /// ==========================
  Future<void> replaceVideoTrack(RTCRtpSender sender) async {
    if (_screenStream == null) return;

    final tracks = _screenStream!.getVideoTracks();

    if (tracks.isNotEmpty) {
      await sender.replaceTrack(tracks.first);
    }
  }

  /// ==========================
  /// Dispose
  /// ==========================
  Future<void> disposeService() async {
    await stop();
  }
}
