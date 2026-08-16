import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../call/stun_turn_service.dart';
import 'recovery_manager.dart';

/// ===========================================================
/// JR CALL
/// File: peer_connection_manager.dart
/// Location: lib/services/managers/peer_connection_manager.dart
///
/// Low-level PeerConnection manager.
/// ===========================================================

class PeerConnectionManager extends ChangeNotifier {
  PeerConnectionManager._();

  static final PeerConnectionManager instance = PeerConnectionManager._();

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  bool _initialized = false;

  RTCPeerConnection? get peerConnection => _peerConnection;

  RTCDataChannel? get dataChannel => _dataChannel;

  bool get isInitialized => _initialized;

  RTCPeerConnectionState? get connectionState =>
      _peerConnection?.connectionState;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> initializeConnection({
    required Function(RTCIceCandidate candidate) onIceCandidate,
    required Function(MediaStream stream) onAddStream,
    required Function(dynamic state) onIceConnectionStateChange,
  }) async {
    if (_peerConnection != null) {
      return;
    }

    try {
      final connection = await StunTurnService.instance.createPeerConnection();

      _peerConnection = connection;

      connection.onIceCandidate = (RTCIceCandidate candidate) {
        final raw = candidate.candidate;

        if (raw == null || raw.isEmpty) {
          return;
        }

        onIceCandidate(candidate);
      };

      connection.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          onAddStream(event.streams.first);
        }
      };

      connection.onIceConnectionState = (RTCIceConnectionState state) {
        onIceConnectionStateChange(state);

        RecoveryManager.instance.handleIceConnectionChange(
          state,
          connection,
          restartIce,
        );
      };

      connection.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('PeerConnectionManager state=$state');
      };

      connection.onSignalingState = (RTCSignalingState state) {
        debugPrint(
          'PeerConnectionManager '
          'signaling=$state',
        );
      };

      connection.onIceGatheringState = (RTCIceGatheringState state) {
        debugPrint(
          'PeerConnectionManager '
          'gathering=$state',
        );
      };

      _initialized = true;

      notifyListeners();
    } catch (error) {
      _peerConnection = null;
      _initialized = false;

      debugPrint(
        'PeerConnectionManager initialization '
        'failed: $error',
      );

      rethrow;
    }
  }

  Future<RTCDataChannel?> createDataChannel({
    String label = 'jr_call_data',
  }) async {
    final connection = _peerConnection;

    if (connection == null) {
      return null;
    }

    if (_dataChannel != null) {
      return _dataChannel;
    }

    try {
      final configuration = RTCDataChannelInit()..ordered = true;

      _dataChannel = await connection.createDataChannel(label, configuration);

      return _dataChannel;
    } catch (error) {
      debugPrint(
        'PeerConnectionManager data channel '
        'failed: $error',
      );

      return null;
    }
  }

  Future<RTCSessionDescription?> createOffer({bool iceRestart = false}) async {
    final connection = _peerConnection;

    if (connection == null) {
      return null;
    }

    try {
      final offer = await connection.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
        'iceRestart': iceRestart,
      });

      await connection.setLocalDescription(offer);

      return offer;
    } catch (error) {
      debugPrint(
        'PeerConnectionManager offer failed: '
        '$error',
      );

      return null;
    }
  }

  Future<RTCSessionDescription?> createAnswer() async {
    final connection = _peerConnection;

    if (connection == null) {
      return null;
    }

    try {
      final answer = await connection.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });

      await connection.setLocalDescription(answer);

      return answer;
    } catch (error) {
      debugPrint(
        'PeerConnectionManager answer failed: '
        '$error',
      );

      return null;
    }
  }

  Future<void> setRemoteDescription(String type, String sdp) async {
    final connection = _peerConnection;

    if (connection == null || sdp.trim().isEmpty) {
      return;
    }

    await connection.setRemoteDescription(
      RTCSessionDescription(sdp.trim(), type.trim().toLowerCase()),
    );
  }

  Future<void> addCandidate(RTCIceCandidate candidate) async {
    final connection = _peerConnection;

    if (connection == null) {
      return;
    }

    final raw = candidate.candidate;

    if (raw == null || raw.isEmpty) {
      return;
    }

    await connection.addCandidate(candidate);
  }

  Future<void> addLocalStream(MediaStream stream) async {
    final connection = _peerConnection;

    if (connection == null) {
      return;
    }

    final senders = await connection.getSenders();

    for (final track in stream.getTracks()) {
      final exists = senders.any((sender) => sender.track?.id == track.id);

      if (!exists) {
        await connection.addTrack(track, stream);
      }
    }
  }

  Future<void> restartIce() async {
    final connection = _peerConnection;

    if (connection == null) {
      return;
    }

    final offer = await connection.createOffer({
      'iceRestart': true,
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await connection.setLocalDescription(offer);
  }

  Future<void> disposeConnection() async {
    final channel = _dataChannel;
    final connection = _peerConnection;

    _dataChannel = null;
    _peerConnection = null;

    if (channel != null) {
      try {
        await channel.close();
      } catch (_) {}
    }

    if (connection != null) {
      connection.onIceCandidate = null;
      connection.onTrack = null;
      connection.onIceConnectionState = null;
      connection.onConnectionState = null;
      connection.onSignalingState = null;
      connection.onIceGatheringState = null;
      connection.onDataChannel = null;

      try {
        await connection.close();
      } catch (_) {}

      try {
        final dynamic dynamicConnection = connection;

        await dynamicConnection.dispose();
      } catch (_) {}
    }

    _initialized = false;

    notifyListeners();
  }

  @override
  void dispose() {
    final connection = _peerConnection;

    final channel = _dataChannel;

    _peerConnection = null;
    _dataChannel = null;

    if (channel != null) {
      channel.close();
    }

    if (connection != null) {
      connection.onIceCandidate = null;
      connection.onTrack = null;
      connection.onIceConnectionState = null;
      connection.onConnectionState = null;
      connection.onSignalingState = null;
      connection.onIceGatheringState = null;
      connection.close();
    }

    super.dispose();
  }
}
