// ===========================================================
// JR CALL
// File: webrtc_service.dart
// Location: lib/services/call/webrtc_service.dart
//
// Description:
// Central WebRTC transport service for JR CALL.
//
// Responsibilities:
// - Create and manage RTCPeerConnection
// - Acquire microphone/camera media
// - Publish local audio/video tracks
// - Receive and expose remote media streams
// - Create SDP offers and answers
// - Apply remote SDP safely
// - Support ICE restart and recovery
// - Configure STUN/TURN servers
// - Replace microphone/camera tracks
// - Expose WebRTC statistics
// - Release native WebRTC resources safely
//
// Ownership:
// - CallService owns call lifecycle
// - IceManager owns ICE persistence, de-duplication and
//   pending remote-candidate handling
// - SignalingService owns Firestore signaling
// - RecoveryManager owns recovery orchestration
// - StunTurnService owns ICE-server credentials/configuration
// - WebRTCService owns transport and media only
// ===========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  // ===========================================================
  // WebRTC Core
  // ===========================================================

  RTCPeerConnection? peerConnection;

  MediaStream? localStream;
  MediaStream? remoteStream;

  // ===========================================================
  // Media Streams
  // ===========================================================

  StreamController<MediaStream?> _localStreamController =
      StreamController<MediaStream?>.broadcast();

  StreamController<MediaStream?> _remoteStreamController =
      StreamController<MediaStream?>.broadcast();

  Stream<MediaStream?> get localStream$ => _localStreamController.stream;

  Stream<MediaStream?> get remoteStream$ => _remoteStreamController.stream;

  // ===========================================================
  // External WebRTC Callbacks
  // ===========================================================

  void Function(RTCIceCandidate candidate)? _onIceCandidateCallback;

  void Function(RTCPeerConnectionState state)? onConnectionStateChanged;

  void Function(RTCIceConnectionState state)? onIceConnectionStateChanged;

  void Function(RTCSignalingState state)? onSignalingStateChanged;

  void Function(RTCIceGatheringState state)? onIceGatheringStateChanged;

  void Function(RTCIceCandidate candidate)? get onIceCandidate =>
      _onIceCandidateCallback;

  set onIceCandidate(void Function(RTCIceCandidate candidate)? callback) {
    _onIceCandidateCallback = callback;

    final connection = peerConnection;

    if (connection != null) {
      _bindIceCandidateCallback(connection);
    }
  }

  // ===========================================================
  // ICE Server Configuration
  // ===========================================================

  List<Map<String, dynamic>> _iceServers = <Map<String, dynamic>>[
    <String, dynamic>{
      'urls': <String>[
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];

  // ===========================================================
  // Media Configuration
  // ===========================================================

  bool _lastVideoParam = true;
  bool _lastAudioParam = true;

  // ===========================================================
  // Stats State
  // ===========================================================

  int _lastBytesReceived = 0;
  int _lastBytesSent = 0;

  DateTime? _lastStatsTime;

  // ===========================================================
  // Runtime Guards
  // ===========================================================

  bool _isInitializing = false;
  bool _isDisposing = false;
  bool _isReplacingMedia = false;
  bool _isRestarting = false;

  // ===========================================================
  // Public State
  // ===========================================================

  bool get isInitialized => peerConnection != null;

  bool get isInitializing => _isInitializing;

  bool get isDisposing => _isDisposing;

  bool get isPeerConnected =>
      peerConnection?.connectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  RTCPeerConnectionState? get connectionState =>
      peerConnection?.connectionState;

  RTCIceConnectionState? get iceConnectionState =>
      peerConnection?.iceConnectionState;

  RTCSignalingState? get signalingState => peerConnection?.signalingState;

  RTCIceGatheringState? get iceGatheringState =>
      peerConnection?.iceGatheringState;

  bool get hasLocalAudio => localStream?.getAudioTracks().isNotEmpty == true;

  bool get hasLocalVideo => localStream?.getVideoTracks().isNotEmpty == true;

  bool get hasRemoteAudio => remoteStream?.getAudioTracks().isNotEmpty == true;

  bool get hasRemoteVideo => remoteStream?.getVideoTracks().isNotEmpty == true;

  // ===========================================================
  // Compatibility Initialization
  // ===========================================================

  Future<void> initialize() async {
    if (peerConnection != null || _isInitializing) {
      return;
    }

    await initializeConnection(video: _lastVideoParam, audio: _lastAudioParam);
  }

  // ===========================================================
  // Peer Connection Initialization
  // ===========================================================

  Future<void> initializeConnection({
    bool video = true,
    bool audio = true,
    List<Map<String, dynamic>>? iceServers,
  }) async {
    if (peerConnection != null || _isInitializing) {
      return;
    }

    _isInitializing = true;

    try {
      _lastVideoParam = video;
      _lastAudioParam = audio;

      if (iceServers != null && iceServers.isNotEmpty) {
        _iceServers = _copyIceServers(iceServers);
      }

      _ensureStreamControllers();

      final configuration = <String, dynamic>{
        'iceServers': _copyIceServers(_iceServers),
        'iceTransportPolicy': 'all',
        'bundlePolicy': 'balanced',
        'rtcpMuxPolicy': 'require',
        'sdpSemantics': 'unified-plan',
      };

      final connection = await createPeerConnection(configuration);

      peerConnection = connection;

      _configurePeerConnectionCallbacks(connection);

      final stream = await _createLocalMediaStream(video: video, audio: audio);

      if (peerConnection != connection) {
        await _disposeMediaStream(stream);

        throw StateError('PeerConnection changed during media initialization.');
      }

      localStream = stream;

      _emitLocalStream(stream);

      await _publishLocalTracks(connection, stream);

      debugPrint('JR CALL [WebRTCService]: initialized successfully.');
    } catch (error, stackTrace) {
      _reportError('initializeConnection', error, stackTrace);

      await _releaseResources(clearExternalCallbacks: false);

      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  // ===========================================================
  // Stream Controller Safety
  // ===========================================================

  void _ensureStreamControllers() {
    if (_localStreamController.isClosed) {
      _localStreamController = StreamController<MediaStream?>.broadcast();
    }

    if (_remoteStreamController.isClosed) {
      _remoteStreamController = StreamController<MediaStream?>.broadcast();
    }
  }

  void _emitLocalStream(MediaStream? stream) {
    if (!_localStreamController.isClosed) {
      _localStreamController.add(stream);
    }
  }

  void _emitRemoteStream(MediaStream? stream) {
    if (!_remoteStreamController.isClosed) {
      _remoteStreamController.add(stream);
    }
  }

  // ===========================================================
  // Peer Connection Callbacks
  // ===========================================================

  void _configurePeerConnectionCallbacks(RTCPeerConnection connection) {
    _bindIceCandidateCallback(connection);

    connection.onConnectionState = (RTCPeerConnectionState state) {
      if (peerConnection != connection) {
        return;
      }

      debugPrint('JR CALL [WebRTCService]: connection -> $state');

      onConnectionStateChanged?.call(state);

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _clearRemoteStream();
      }
    };

    connection.onIceConnectionState = (RTCIceConnectionState state) {
      if (peerConnection != connection) {
        return;
      }

      debugPrint('JR CALL [WebRTCService]: ICE -> $state');

      onIceConnectionStateChanged?.call(state);
    };

    connection.onSignalingState = (RTCSignalingState state) {
      if (peerConnection != connection) {
        return;
      }

      debugPrint('JR CALL [WebRTCService]: signaling -> $state');

      onSignalingStateChanged?.call(state);
    };

    connection.onIceGatheringState = (RTCIceGatheringState state) {
      if (peerConnection != connection) {
        return;
      }

      debugPrint('JR CALL [WebRTCService]: gathering -> $state');

      onIceGatheringStateChanged?.call(state);
    };

    connection.onTrack = (RTCTrackEvent event) {
      if (peerConnection != connection) {
        return;
      }

      _handleRemoteTrack(event);
    };
  }

  void _bindIceCandidateCallback(RTCPeerConnection connection) {
    connection.onIceCandidate = (RTCIceCandidate candidate) {
      if (peerConnection != connection) {
        return;
      }

      final value = candidate.candidate?.trim();

      if (value == null || value.isEmpty) {
        return;
      }

      _onIceCandidateCallback?.call(candidate);
    };
  }

  // ===========================================================
  // Remote Media
  // ===========================================================

  void _handleRemoteTrack(RTCTrackEvent event) {
    if (event.streams.isEmpty) {
      return;
    }

    final incomingStream = event.streams.first;

    if (remoteStream?.id != incomingStream.id) {
      remoteStream = incomingStream;

      _emitRemoteStream(incomingStream);
    }

    event.track.onEnded = () {
      debugPrint(
        'JR CALL [WebRTCService]: '
        'remote ${event.track.kind} track ended.',
      );

      final activeRemote = remoteStream;

      if (activeRemote == null) {
        return;
      }

      final remainingTracks = activeRemote
          .getTracks()
          .where((track) => track.id != event.track.id)
          .toList(growable: false);

      if (remainingTracks.isEmpty) {
        _clearRemoteStream(stopTracks: false);
      }
    };
  }

  void _clearRemoteStream({bool stopTracks = true}) {
    final stream = remoteStream;

    if (stream == null) {
      return;
    }

    remoteStream = null;

    if (stopTracks) {
      for (final track in stream.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }

      unawaited(_disposeMediaStreamSafely(stream));
    }

    _emitRemoteStream(null);
  }

  // ===========================================================
  // Local Media
  // ===========================================================

  Future<MediaStream> _createLocalMediaStream({
    required bool video,
    required bool audio,
  }) async {
    if (!video && !audio) {
      throw ArgumentError('At least audio or video must be enabled.');
    }

    final constraints = <String, dynamic>{
      'audio': audio
          ? <String, dynamic>{
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            }
          : false,
      'video': video
          ? <String, dynamic>{
              'width': <String, dynamic>{'ideal': 1280},
              'height': <String, dynamic>{'ideal': 720},
              'frameRate': <String, dynamic>{'ideal': 30, 'max': 30},
              'facingMode': 'user',
            }
          : false,
    };

    try {
      return await navigator.mediaDevices.getUserMedia(constraints);
    } catch (error, stackTrace) {
      _reportError('getUserMedia', error, stackTrace);

      rethrow;
    }
  }

  Future<void> _publishLocalTracks(
    RTCPeerConnection connection,
    MediaStream stream,
  ) async {
    final senders = await connection.getSenders();

    for (final track in stream.getTracks()) {
      final alreadyPublished = senders.any(
        (sender) => sender.track?.id == track.id,
      );

      if (!alreadyPublished) {
        await connection.addTrack(track, stream);
      }
    }
  }

  // ===========================================================
  // Offer
  // ===========================================================

  Future<RTCSessionDescription> createOffer({bool iceRestart = false}) async {
    final connection = peerConnection;

    if (connection == null) {
      throw StateError('PeerConnection is not initialized.');
    }

    final state = connection.signalingState;

    if (state != RTCSignalingState.RTCSignalingStateStable && !iceRestart) {
      throw StateError('Cannot create offer while signaling state is $state.');
    }

    final constraints = <String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _lastVideoParam,
      if (iceRestart) 'iceRestart': true,
    };

    final offer = await connection.createOffer(constraints);

    _validateSessionDescription(offer, expectedType: 'offer');

    await connection.setLocalDescription(offer);

    return offer;
  }

  // ===========================================================
  // Answer
  // ===========================================================

  Future<RTCSessionDescription> createAnswer() async {
    final connection = peerConnection;

    if (connection == null) {
      throw StateError('PeerConnection is not initialized.');
    }

    final remoteDescription = await connection.getRemoteDescription();

    if (remoteDescription == null) {
      throw StateError(
        'Remote offer must be applied before creating an answer.',
      );
    }

    final state = connection.signalingState;

    if (state != RTCSignalingState.RTCSignalingStateHaveRemoteOffer &&
        state != RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer) {
      throw StateError('Cannot create answer while signaling state is $state.');
    }

    final answer = await connection.createAnswer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _lastVideoParam,
    });

    _validateSessionDescription(answer, expectedType: 'answer');

    await connection.setLocalDescription(answer);

    return answer;
  }

  // ===========================================================
  // Remote SDP
  // ===========================================================

  Future<void> setRemoteDescription({
    required String sdp,
    required String type,
  }) async {
    final connection = peerConnection;

    if (connection == null) {
      throw StateError('PeerConnection is not initialized.');
    }

    final normalizedSdp = sdp.trim();
    final normalizedType = type.trim().toLowerCase();

    if (normalizedSdp.isEmpty) {
      throw ArgumentError('Remote SDP cannot be empty.');
    }

    if (normalizedType != 'offer' &&
        normalizedType != 'answer' &&
        normalizedType != 'pranswer') {
      throw ArgumentError.value(type, 'type', 'Unsupported WebRTC SDP type.');
    }

    final existing = await connection.getRemoteDescription();

    if (existing?.sdp == normalizedSdp && existing?.type == normalizedType) {
      return;
    }

    await connection.setRemoteDescription(
      RTCSessionDescription(normalizedSdp, normalizedType),
    );
  }

  Future<RTCSessionDescription?> getLocalDescription() async {
    final connection = peerConnection;

    if (connection == null) {
      return null;
    }

    return connection.getLocalDescription();
  }

  Future<RTCSessionDescription?> getRemoteDescription() async {
    final connection = peerConnection;

    if (connection == null) {
      return null;
    }

    return connection.getRemoteDescription();
  }

  // ===========================================================
  // ICE Compatibility
  //
  // IMPORTANT:
  // IceManager remains the actual owner of remote-candidate
  // queueing and de-duplication.
  // ===========================================================

  Future<void> addIceCandidate(RTCIceCandidate? candidate) async {
    final connection = peerConnection;

    if (connection == null || candidate == null) {
      return;
    }

    final value = candidate.candidate?.trim();

    if (value == null || value.isEmpty) {
      return;
    }

    final remoteDescription = await connection.getRemoteDescription();

    if (remoteDescription == null) {
      throw StateError(
        'Remote description must be set before '
        'adding an ICE candidate. '
        'Use IceManager for pending candidates.',
      );
    }

    await connection.addCandidate(candidate);
  }

  /// Compatibility method.
  ///
  /// Pending ICE candidates are intentionally owned and flushed
  /// by IceManager. Therefore WebRTCService itself has no pending
  /// candidate collection to flush.
  Future<void> flushPendingCandidates() async {}

  // ===========================================================
  // STUN / TURN Configuration
  // ===========================================================

  Future<void> configureTurnFailoverServers([
    List<Map<String, dynamic>>? fallbackServers,
  ]) async {
    if (fallbackServers != null && fallbackServers.isNotEmpty) {
      _iceServers = _copyIceServers(fallbackServers);
    }

    final connection = peerConnection;

    if (connection == null) {
      return;
    }

    try {
      await connection.setConfiguration(<String, dynamic>{
        'iceServers': _copyIceServers(_iceServers),
        'iceTransportPolicy': 'all',
        'bundlePolicy': 'balanced',
        'rtcpMuxPolicy': 'require',
        'sdpSemantics': 'unified-plan',
      });
    } catch (error, stackTrace) {
      _reportError('configureTurnFailoverServers', error, stackTrace);

      rethrow;
    }
  }

  // ===========================================================
  // ICE Restart
  // ===========================================================

  Future<RTCSessionDescription> performIceRestart() async {
    final connection = peerConnection;

    if (connection == null) {
      throw StateError('PeerConnection is not initialized.');
    }

    if (connection.connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
      throw StateError('Cannot restart ICE on a closed PeerConnection.');
    }

    try {
      final dynamic dynamicConnection = connection;

      await dynamicConnection.restartIce();
    } catch (error) {
      debugPrint(
        'JR CALL [WebRTCService]: '
        'native restartIce unavailable; '
        'using SDP ICE restart. $error',
      );
    }

    return createOffer(iceRestart: true);
  }

  // ===========================================================
  // Wait Until Connected
  // ===========================================================

  Future<void> waitUntilConnected({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (isPeerConnected) {
      return;
    }

    final connection = peerConnection;

    if (connection == null) {
      throw StateError('PeerConnection is not initialized.');
    }

    final completer = Completer<void>();

    Timer? pollingTimer;
    Timer? timeoutTimer;

    pollingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (completer.isCompleted) {
        return;
      }

      if (peerConnection != connection) {
        completer.completeError(
          StateError('PeerConnection changed while waiting for connection.'),
        );
        return;
      }

      final state = connection.connectionState;

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        completer.complete();
        return;
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        completer.completeError(StateError('PeerConnection entered $state.'));
      }
    });

    timeoutTimer = Timer(timeout, () {
      if (completer.isCompleted) {
        return;
      }

      completer.completeError(
        TimeoutException(
          'PeerConnection did not connect within $timeout. '
          'Connection=${connection.connectionState}, '
          'ICE=${connection.iceConnectionState}, '
          'Signaling=${connection.signalingState}',
        ),
      );
    });

    try {
      await completer.future;
    } finally {
      pollingTimer.cancel();
      timeoutTimer.cancel();
    }
  }

  // ===========================================================
  // WebRTC Statistics
  // ===========================================================

  Future<List<StatsReport>> getStats() async {
    final connection = peerConnection;

    if (connection == null) {
      return const <StatsReport>[];
    }

    try {
      return await connection.getStats();
    } catch (error, stackTrace) {
      _reportError('getStats', error, stackTrace);

      return const <StatsReport>[];
    }
  }

  Future<Map<String, dynamic>> getParsedStats() async {
    final reports = await getStats();

    var bytesReceived = 0;
    var bytesSent = 0;

    var packetsLost = 0;
    var packetsReceived = 0;

    var jitterSeconds = 0.0;
    var rttSeconds = 0.0;

    var transport = 'unknown';
    var candidatePair = 'unknown';

    for (final report in reports) {
      final values = report.values;

      if (report.type == 'inbound-rtp') {
        final received = values['bytesReceived'];

        if (received is num) {
          bytesReceived += received.toInt();
        }

        final lost = values['packetsLost'];

        if (lost is num) {
          packetsLost += lost.toInt();
        }

        final receivedPackets = values['packetsReceived'];

        if (receivedPackets is num) {
          packetsReceived += receivedPackets.toInt();
        }

        final jitter = values['jitter'];

        if (jitter is num) {
          jitterSeconds = jitter.toDouble();
        }
      }

      if (report.type == 'outbound-rtp') {
        final sent = values['bytesSent'];

        if (sent is num) {
          bytesSent += sent.toInt();
        }
      }

      if (report.type == 'candidate-pair') {
        final selected = values['selected'] == true;

        final succeeded = values['state'] == 'succeeded';

        if (!selected && !succeeded) {
          continue;
        }

        final currentRtt = values['currentRoundTripTime'];

        if (currentRtt is num) {
          rttSeconds = currentRtt.toDouble();
        }

        final transportValue = values['transportId'];

        if (transportValue != null) {
          transport = transportValue.toString();
        }

        candidatePair =
            '${values['localCandidateId'] ?? 'unknown'}'
            ' <-> '
            '${values['remoteCandidateId'] ?? 'unknown'}';
      }
    }

    var bitrateRx = 0.0;
    var bitrateTx = 0.0;

    final now = DateTime.now();

    final previousTime = _lastStatsTime;

    if (previousTime != null) {
      final elapsedSeconds =
          now.difference(previousTime).inMilliseconds / 1000.0;

      if (elapsedSeconds > 0) {
        final receivedDelta = bytesReceived - _lastBytesReceived;

        final sentDelta = bytesSent - _lastBytesSent;

        if (receivedDelta >= 0) {
          bitrateRx = receivedDelta * 8 / 1000.0 / elapsedSeconds;
        }

        if (sentDelta >= 0) {
          bitrateTx = sentDelta * 8 / 1000.0 / elapsedSeconds;
        }
      }
    }

    _lastBytesReceived = bytesReceived;
    _lastBytesSent = bytesSent;
    _lastStatsTime = now;

    final packetTotal = packetsReceived + packetsLost;

    final packetLossPercent = packetTotal <= 0
        ? 0.0
        : packetsLost / packetTotal * 100.0;

    return <String, dynamic>{
      'bitrateRx': bitrateRx,
      'bitrateTx': bitrateTx,
      'uploadBitrate': bitrateTx,
      'downloadBitrate': bitrateRx,
      'packetLoss': packetLossPercent,
      'packetsLost': packetsLost,
      'rtt': (rttSeconds * 1000).round(),
      'jitter': jitterSeconds * 1000.0,
      'transport': transport,
      'candidatePair': candidatePair,
    };
  }

  // ===========================================================
  // Local Audio / Video Track State
  // ===========================================================

  Future<void> setAudioEnabled(bool enabled) async {
    final stream = localStream;

    if (stream == null) {
      return;
    }

    for (final track in stream.getAudioTracks()) {
      track.enabled = enabled;
    }
  }

  Future<void> setVideoEnabled(bool enabled) async {
    final stream = localStream;

    if (stream == null) {
      return;
    }

    for (final track in stream.getVideoTracks()) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final tracks = localStream?.getVideoTracks();

    if (tracks == null || tracks.isEmpty) {
      return;
    }

    await Helper.switchCamera(tracks.first);
  }

  // ===========================================================
  // Replace Local Media
  // ===========================================================

  Future<void> replaceMediaTracks({bool? video, bool? audio}) async {
    final connection = peerConnection;

    if (connection == null) {
      throw StateError('PeerConnection is not initialized.');
    }

    if (_isReplacingMedia) {
      return;
    }

    _isReplacingMedia = true;

    final useVideo = video ?? _lastVideoParam;

    final useAudio = audio ?? _lastAudioParam;

    MediaStream? newStream;

    try {
      newStream = await _createLocalMediaStream(
        video: useVideo,
        audio: useAudio,
      );

      if (peerConnection != connection) {
        throw StateError('PeerConnection changed while replacing media.');
      }

      final senders = await connection.getSenders();

      final newTracks = newStream.getTracks();

      for (final newTrack in newTracks) {
        RTCRtpSender? matchingSender;

        for (final sender in senders) {
          if (sender.track?.kind == newTrack.kind) {
            matchingSender = sender;
            break;
          }
        }

        if (matchingSender != null) {
          await matchingSender.replaceTrack(newTrack);
        } else {
          await connection.addTrack(newTrack, newStream);
        }
      }

      final oldStream = localStream;

      localStream = newStream;

      _lastVideoParam = useVideo;
      _lastAudioParam = useAudio;

      _emitLocalStream(newStream);

      if (oldStream != null && oldStream.id != newStream.id) {
        await _disposeMediaStream(oldStream);
      }

      newStream = null;
    } catch (error, stackTrace) {
      _reportError('replaceMediaTracks', error, stackTrace);

      if (newStream != null) {
        await _disposeMediaStream(newStream);
      }

      rethrow;
    } finally {
      _isReplacingMedia = false;
    }
  }

  // ===========================================================
  // Restart Peer Connection
  // ===========================================================

  Future<void> restartPeerConnection() async {
    if (_isRestarting) {
      return;
    }

    _isRestarting = true;

    final video = _lastVideoParam;
    final audio = _lastAudioParam;

    final servers = _copyIceServers(_iceServers);

    final iceCandidateCallback = _onIceCandidateCallback;

    final connectionCallback = onConnectionStateChanged;

    final iceConnectionCallback = onIceConnectionStateChanged;

    final signalingCallback = onSignalingStateChanged;

    final gatheringCallback = onIceGatheringStateChanged;

    try {
      await _releaseResources(clearExternalCallbacks: false);

      _onIceCandidateCallback = iceCandidateCallback;

      onConnectionStateChanged = connectionCallback;

      onIceConnectionStateChanged = iceConnectionCallback;

      onSignalingStateChanged = signalingCallback;

      onIceGatheringStateChanged = gatheringCallback;

      await initializeConnection(
        video: video,
        audio: audio,
        iceServers: servers,
      );
    } finally {
      _isRestarting = false;
    }
  }

  // ===========================================================
  // Close PeerConnection Only
  // ===========================================================

  Future<void> closePeerConnection() async {
    final connection = peerConnection;

    peerConnection = null;

    if (connection == null) {
      return;
    }

    _detachPeerConnectionCallbacks(connection);

    try {
      await connection.close();
    } catch (error, stackTrace) {
      _reportError('closePeerConnection', error, stackTrace);
    }

    try {
      final dynamic dynamicConnection = connection;

      await dynamicConnection.dispose();
    } catch (_) {}
  }

  void _detachPeerConnectionCallbacks(RTCPeerConnection connection) {
    try {
      connection.onIceCandidate = null;
      connection.onTrack = null;
      connection.onDataChannel = null;
      connection.onConnectionState = null;
      connection.onIceConnectionState = null;
      connection.onSignalingState = null;
      connection.onIceGatheringState = null;
    } catch (_) {}
  }

  // ===========================================================
  // Reset Runtime State
  // ===========================================================

  void resetConnectionState() {
    _lastBytesReceived = 0;
    _lastBytesSent = 0;
    _lastStatsTime = null;

    _clearRemoteStream();
  }

  // ===========================================================
  // Reusable Resource Cleanup
  // ===========================================================

  Future<void> dispose() async {
    await _releaseResources(clearExternalCallbacks: true);
  }

  Future<void> _releaseResources({required bool clearExternalCallbacks}) async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    try {
      await closePeerConnection();

      final local = localStream;

      localStream = null;

      if (local != null) {
        await _disposeMediaStream(local);
      }

      _emitLocalStream(null);

      _clearRemoteStream();

      _lastBytesReceived = 0;
      _lastBytesSent = 0;
      _lastStatsTime = null;

      _isReplacingMedia = false;

      if (clearExternalCallbacks) {
        _onIceCandidateCallback = null;

        onConnectionStateChanged = null;
        onIceConnectionStateChanged = null;
        onSignalingStateChanged = null;
        onIceGatheringStateChanged = null;
      }

      debugPrint('JR CALL [WebRTCService]: resources released.');
    } finally {
      _isDisposing = false;
    }
  }

  // ===========================================================
  // Media Disposal
  // ===========================================================

  Future<void> _disposeMediaStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        track.stop();
      } catch (_) {}
    }

    await _disposeMediaStreamSafely(stream);
  }

  Future<void> _disposeMediaStreamSafely(MediaStream stream) async {
    try {
      await stream.dispose();
    } catch (_) {}
  }

  // ===========================================================
  // Validation
  // ===========================================================

  void _validateSessionDescription(
    RTCSessionDescription description, {
    required String expectedType,
  }) {
    final sdp = description.sdp?.trim();
    final type = description.type?.trim().toLowerCase();

    if (sdp == null || sdp.isEmpty || type != expectedType) {
      throw StateError(
        'Generated WebRTC $expectedType '
        'session description is invalid.',
      );
    }
  }

  List<Map<String, dynamic>> _copyIceServers(
    List<Map<String, dynamic>> source,
  ) {
    return source
        .map<Map<String, dynamic>>(
          (server) => Map<String, dynamic>.from(server),
        )
        .toList(growable: false);
  }

  // ===========================================================
  // Error Logging
  // ===========================================================

  void _reportError(String source, Object error, [StackTrace? stackTrace]) {
    debugPrint('JR CALL [WebRTCService/$source] error: $error');

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [WebRTCService/$source]',
        stackTrace: stackTrace,
      );
    }
  }
}
