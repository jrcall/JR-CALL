import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../call/signaling_service.dart';

/// ===========================================================
/// JR CALL
/// File: ice_manager.dart
/// Location: lib/services/managers/ice_manager.dart
///
/// Firestore/WebRTC ICE synchronization coordinator.
/// ===========================================================

class IceManager extends ChangeNotifier {
  IceManager._();

  static final IceManager instance = IceManager._();

  final SignalingService _signaling = SignalingService.instance;

  StreamSubscription<List<Map<String, dynamic>>>? _remoteSubscription;

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  final Set<String> _processedRemoteCandidates = {};

  final Set<String> _sentLocalCandidates = {};

  bool _initialized = false;

  bool get isInitialized => _initialized;

  String get currentState => _initialized ? 'INITIALIZED' : 'DISCONNECTED';

  Future<void> initialize({
    String? callId,
    bool? isCaller,
    RTCPeerConnection? peerConnection,
  }) async {
    await _cancelRemoteSubscription();

    _pendingRemoteCandidates.clear();
    _processedRemoteCandidates.clear();
    _sentLocalCandidates.clear();

    if (peerConnection == null) {
      _initialized = true;
      notifyListeners();
      return;
    }

    if (callId == null || isCaller == null) {
      _initialized = true;
      notifyListeners();
      return;
    }

    final normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      throw ArgumentError('callId cannot be empty.');
    }

    peerConnection.onIceCandidate = (RTCIceCandidate candidate) async {
      final rawCandidate = candidate.candidate?.trim();

      if (rawCandidate == null || rawCandidate.isEmpty) {
        return;
      }

      final signature = _signature(candidate);

      if (!_sentLocalCandidates.add(signature)) {
        return;
      }

      try {
        await _signaling.addIceCandidate(normalizedCallId, isCaller, {
          'candidate': rawCandidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      } catch (error) {
        _sentLocalCandidates.remove(signature);

        debugPrint(
          'IceManager local ICE send failed: '
          '$error',
        );
      }
    };

    listenRemoteCandidates(
      callId: normalizedCallId,
      isCaller: isCaller,
      peerConnection: peerConnection,
    );

    _initialized = true;
    notifyListeners();
  }

  void listenRemoteCandidates({
    required String callId,
    required bool isCaller,
    required RTCPeerConnection? peerConnection,
  }) {
    if (peerConnection == null) {
      return;
    }

    unawaited(_cancelRemoteSubscription());

    _remoteSubscription = _signaling
        .listenToRemoteICECandidates(callId, isCaller)
        .listen(
          (remoteCandidates) async {
            for (final candidateData in remoteCandidates) {
              await _processRemoteCandidate(peerConnection, candidateData);
            }
          },
          onError: (Object error) {
            debugPrint(
              'IceManager remote ICE stream failed: '
              '$error',
            );
          },
        );
  }

  Future<void> _processRemoteCandidate(
    RTCPeerConnection peerConnection,
    Map<String, dynamic> data,
  ) async {
    final rawCandidate = data['candidate'];

    if (rawCandidate is! String || rawCandidate.trim().isEmpty) {
      return;
    }

    final lineIndex = data['sdpMLineIndex'];

    final candidate = RTCIceCandidate(
      rawCandidate.trim(),
      data['sdpMid'] as String?,
      lineIndex is num ? lineIndex.toInt() : null,
    );

    final signature = _signature(candidate);

    if (!_processedRemoteCandidates.add(signature)) {
      return;
    }

    try {
      final remoteDescription = await peerConnection.getRemoteDescription();

      if (remoteDescription == null) {
        _pendingRemoteCandidates.add(candidate);

        return;
      }

      await peerConnection.addCandidate(candidate);
    } catch (error) {
      debugPrint(
        'IceManager remote candidate failed: '
        '$error',
      );
    }
  }

  Future<void> flushPendingCandidates(RTCPeerConnection? peerConnection) async {
    if (peerConnection == null || _pendingRemoteCandidates.isEmpty) {
      return;
    }

    final remoteDescription = await peerConnection.getRemoteDescription();

    if (remoteDescription == null) {
      return;
    }

    final candidates = List<RTCIceCandidate>.from(_pendingRemoteCandidates);

    _pendingRemoteCandidates.clear();

    for (final candidate in candidates) {
      try {
        await peerConnection.addCandidate(candidate);
      } catch (error) {
        debugPrint(
          'IceManager pending candidate failed: '
          '$error',
        );
      }
    }
  }

  String _signature(RTCIceCandidate candidate) {
    return '${candidate.candidate}|'
        '${candidate.sdpMid}|'
        '${candidate.sdpMLineIndex}';
  }

  Future<void> _cancelRemoteSubscription() async {
    final subscription = _remoteSubscription;

    _remoteSubscription = null;

    if (subscription != null) {
      await subscription.cancel();
    }
  }

  void reset() {
    final subscription = _remoteSubscription;

    _remoteSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    _pendingRemoteCandidates.clear();
    _processedRemoteCandidates.clear();
    _sentLocalCandidates.clear();

    _initialized = false;

    notifyListeners();
  }

  @override
  void dispose() {
    final subscription = _remoteSubscription;

    _remoteSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    _pendingRemoteCandidates.clear();
    _processedRemoteCandidates.clear();
    _sentLocalCandidates.clear();

    super.dispose();
  }
}
