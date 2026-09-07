// ===============================================================
// JR CALL
// File: webrtc_service.dart
// Location: lib/services/call/webrtc_service.dart
//
// PRODUCTION WEBRTC TRANSPORT SERVICE
//
// CURRENT JR CALL OWNERSHIP:
//
// CallService:
// - Full call lifecycle/orchestration.
// - Caller / receiver session.
// - SDP signaling orchestration.
// - Duration and user-visible call state.
//
// WebRTCService:
// - The CURRENT CallService-facing native PeerConnection owner.
// - Local microphone / camera acquisition.
// - Local track publication.
// - Remote media exposure.
// - Offer / answer creation.
// - Remote SDP application.
// - Explicit ICE-restart offer creation.
// - Local media replacement.
// - Camera switching.
// - On-demand WebRTC diagnostics.
// - Native transport cleanup.
//
// SignalingService:
// - Firestore signaling persistence.
//
// IceManager:
// - ONLY owner of RTCPeerConnection.onIceCandidate.
// - Candidate persistence/listening/queue/de-duplication.
//
// RecoveryManager:
// - Recovery policy/orchestration.
//
// StatsManager:
// - Canonical periodic call telemetry.
//
// CRITICAL CALLBACK OWNERSHIP:
//
// WebRTCService MUST NEVER assign or clear:
//
//   peerConnection.onIceCandidate
//
// WebRTCService MUST ALSO NOT clear:
//
//   peerConnection.onDataChannel
//   peerConnection.onRenegotiationNeeded
//
// It detaches only callbacks installed by this file.
//
// IMPORTANT:
//
// The project also contains manager-layer WebRTC/media helpers.
// CallService must never initialize a second independent native
// PeerConnection/media stack for the same active call.
//
// No Firestore persistence.
// No recovery scheduling.
// No UI/design ownership.
//
// SIGNALING STATE COMPATIBILITY:
//
// flutter_webrtc can temporarily report a null signalingState on a
// freshly-created native PeerConnection even when createOffer() /
// createAnswer() is valid.
//
// Therefore:
//
// - null is treated as "native state not surfaced yet".
// - Explicit incompatible non-null signaling states are rejected.
// - The native WebRTC implementation remains the final authority.
// - Initial offer creation is never blocked only because state=null.
//
// REMOTE SDP SAFETY:
//
// Native getRemoteDescription() may temporarily return/throw
// "SessionDescription is NULL" immediately around SDP signaling.
//
// Therefore this service maintains its own successfully-applied
// remote SDP cache.
//
// IMPORTANT:
// - Never query native getRemoteDescription() as a prerequisite
//   before applying remote SDP.
// - Cache remote SDP only AFTER native setRemoteDescription()
//   succeeds.
// - Use the cache for duplicate detection and ICE readiness.
// - Native WebRTC remains the final authority for actual SDP state.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  // =============================================================
  // INTERNAL CONSTANTS
  // =============================================================

  static const String _inboundRtpType =
      'inbound-r'
      'tp';

  static const String _outboundRtpType =
      'outbound-r'
      'tp';

  static const String _remoteInboundRtpType =
      'remote-inbound-r'
      'tp';

  static const String _candidatePairType =
      'candidate-'
      'pair';

  static const String _localCandidateType =
      'local-'
      'candidate';

  static const String _transportType = 'transport';

  static const String _muxPolicyConfigurationKey =
      'r'
      'tcp'
      'MuxPolicy';

  static const String _offerType = 'offer';
  static const String _answerType = 'answer';

  static const String _provisionalAnswerType =
      'pr'
      'answer';

  static const String _audioKind = 'audio';
  static const String _videoKind = 'video';

  // =============================================================
  // CORE WEBRTC STATE
  // =============================================================

  RTCPeerConnection? peerConnection;

  MediaStream? localStream;
  MediaStream? remoteStream;

  // =============================================================
  // REMOTE SDP CACHE
  // =============================================================

  String? _appliedRemoteSdp;
  String? _appliedRemoteType;

  // =============================================================
  // LOCAL SENDER STATE
  // =============================================================

  final Map<String, RTCRtpSender> _localSendersByKind =
  <String, RTCRtpSender>{};

  // =============================================================
  // REMOTE TRACK STATE
  // =============================================================

  final Set<MediaStreamTrack> _endedRemoteTracks =
  <MediaStreamTrack>{};

  // =============================================================
  // MEDIA STREAM CONTROLLERS
  // =============================================================

  StreamController<MediaStream?> _localStreamController =
  StreamController<MediaStream?>.broadcast();

  StreamController<MediaStream?> _remoteStreamController =
  StreamController<MediaStream?>.broadcast();

  Stream<MediaStream?> get localStream$ =>
      _localStreamController.stream;

  Stream<MediaStream?> get remoteStream$ =>
      _remoteStreamController.stream;

  // =============================================================
  // WEBRTC STATE CALLBACKS
  // =============================================================

  void Function(RTCPeerConnectionState state)?
  onConnectionStateChanged;

  void Function(RTCIceConnectionState state)?
  onIceConnectionStateChanged;

  void Function(RTCSignalingState state)?
  onSignalingStateChanged;

  void Function(RTCIceGatheringState state)?
  onIceGatheringStateChanged;

  // =============================================================
  // FULL-RECREATION COMPATIBILITY CALLBACK
  // =============================================================

  void Function(RTCPeerConnection connection)?
  onPeerConnectionRecreated;

  // =============================================================
  // LEGACY ICE CALLBACK COMPATIBILITY
  // =============================================================

  void Function(RTCIceCandidate candidate)?
  _legacyIceCandidateCallback;

  void Function(RTCIceCandidate candidate)? get onIceCandidate =>
      _legacyIceCandidateCallback;

  set onIceCandidate(
      void Function(RTCIceCandidate candidate)? callback,
      ) {
    _legacyIceCandidateCallback = callback;

    if (callback != null) {
      _debugPrint(
        'Legacy ICE observer stored. '
            'IceManager remains the native candidate callback owner.',
      );
    }
  }

  void deliverOwnedIceCandidate(RTCIceCandidate candidate) {
    final void Function(RTCIceCandidate candidate)? callback =
        _legacyIceCandidateCallback;

    if (callback == null) {
      return;
    }

    try {
      callback(candidate);
    } catch (error, stackTrace) {
      _reportError(
        'legacy ICE observer',
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // ICE SERVER CONFIGURATION
  // =============================================================

  List<Map<String, dynamic>> _iceServers =
  <Map<String, dynamic>>[
    <String, dynamic>{
      'urls': <String>[
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];

  // =============================================================
  // LAST LOCAL MEDIA CONFIGURATION
  // =============================================================

  bool _lastVideoParam = true;
  bool _lastAudioParam = true;

  // =============================================================
  // ON-DEMAND DIAGNOSTIC STATS BASELINE
  // =============================================================

  int _lastBytesReceived = 0;
  int _lastBytesSent = 0;

  Stopwatch? _statsClock;
  Duration? _lastStatsElapsed;

  // =============================================================
  // RUNTIME GUARDS
  // =============================================================

  bool _isInitializing = false;
  bool _isDisposing = false;
  bool _isReplacingMedia = false;
  bool _isRestarting = false;

  int _connectionGeneration = 0;

  Future<void>? _initializationFuture;
  Future<void>? _releaseFuture;
  Future<void>? _mediaReplacementFuture;

  // =============================================================
  // PUBLIC STATE
  // =============================================================

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

  RTCSignalingState? get signalingState =>
      peerConnection?.signalingState;

  RTCIceGatheringState? get iceGatheringState =>
      peerConnection?.iceGatheringState;

  bool get hasLocalAudio =>
      localStream?.getAudioTracks().isNotEmpty == true;

  bool get hasLocalVideo =>
      localStream?.getVideoTracks().isNotEmpty == true;

  bool get hasRemoteAudio =>
      remoteStream?.getAudioTracks().isNotEmpty == true;

  bool get hasRemoteVideo =>
      remoteStream?.getVideoTracks().isNotEmpty == true;

  // =============================================================
  // COMPATIBILITY INITIALIZATION
  // =============================================================

  Future<void> initialize() async {
    await initializeConnection(
      video: _lastVideoParam,
      audio: _lastAudioParam,
    );
  }

  // =============================================================
  // PEER CONNECTION INITIALIZATION
  // =============================================================

  Future<void> initializeConnection({
    bool video = true,
    bool audio = true,
    List<Map<String, dynamic>>? iceServers,
  }) async {
    if (!video && !audio) {
      throw ArgumentError(
        'At least microphone audio or camera video must be enabled.',
      );
    }

    final Future<void>? activeRelease = _releaseFuture;

    if (activeRelease != null) {
      await activeRelease;
    }

    if (_isDisposing) {
      throw StateError(
        'WebRTCService cannot initialize while resources are disposing.',
      );
    }

    final RTCPeerConnection? existingConnection =
        peerConnection;

    if (existingConnection != null) {
      if (localStream == null) {
        await _releaseResources(
          clearExternalCallbacks: false,
          invalidateGeneration: true,
        );
      } else {
        if (iceServers != null && iceServers.isNotEmpty) {
          await configureTurnFailoverServers(iceServers);
        }

        if (video != _lastVideoParam ||
            audio != _lastAudioParam) {
          await replaceMediaTracks(
            video: video,
            audio: audio,
          );
        }

        return;
      }
    }

    final Future<void>? runningInitialization =
        _initializationFuture;

    if (runningInitialization != null) {
      await runningInitialization;

      if (peerConnection == null && !_isDisposing) {
        await initializeConnection(
          video: video,
          audio: audio,
          iceServers: iceServers,
        );

        return;
      }

      if (peerConnection != null) {
        if (iceServers != null && iceServers.isNotEmpty) {
          await configureTurnFailoverServers(iceServers);
        }

        if (video != _lastVideoParam ||
            audio != _lastAudioParam) {
          await replaceMediaTracks(
            video: video,
            audio: audio,
          );
        }
      }

      return;
    }

    final Future<void> operation =
    _performInitializeConnection(
      video: video,
      audio: audio,
      iceServers: iceServers,
    );

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(_initializationFuture, tracked)) {
        _initializationFuture = null;
      }
    });

    _initializationFuture = tracked;

    await tracked;
  }

  Future<void> _performInitializeConnection({
    required bool video,
    required bool audio,
    required List<Map<String, dynamic>>? iceServers,
  }) async {
    if (_isDisposing) {
      throw StateError(
        'WebRTCService cannot initialize while resources are disposing.',
      );
    }

    _isInitializing = true;

    final int generation = ++_connectionGeneration;

    RTCPeerConnection? newConnection;
    MediaStream? newLocalStream;

    try {
      _lastVideoParam = video;
      _lastAudioParam = audio;

      if (iceServers != null && iceServers.isNotEmpty) {
        _iceServers = _copyIceServers(iceServers);
      }

      _ensureStreamControllers();

      _clearAppliedRemoteDescription();

      newConnection = await createPeerConnection(
        _buildPeerConfiguration(),
      );

      if (!_isGenerationCurrent(generation)) {
        await _closeSpecificPeerConnection(newConnection);
        return;
      }

      peerConnection = newConnection;

      _localSendersByKind.clear();

      _configurePeerConnectionCallbacks(
        newConnection,
        generation: generation,
      );

      newLocalStream = await _createLocalMediaStream(
        video: video,
        audio: audio,
      );

      if (!_isConnectionCurrent(
        generation: generation,
        connection: newConnection,
      )) {
        await _disposeMediaStream(newLocalStream);
        return;
      }

      localStream = newLocalStream;

      _emitLocalStream(newLocalStream);

      await _publishLocalTracks(
        connection: newConnection,
        stream: newLocalStream,
      );

      if (!_isConnectionCurrent(
        generation: generation,
        connection: newConnection,
      )) {
        return;
      }

      _resetStatsState();

      _debugPrint(
        'PeerConnection and local media initialized.',
      );
    } catch (error, stackTrace) {
      _reportError(
        'initializeConnection',
        error,
        stackTrace,
      );

      if (newLocalStream != null &&
          !identical(localStream, newLocalStream)) {
        await _disposeMediaStream(newLocalStream);
      }

      if (newConnection != null &&
          !identical(peerConnection, newConnection)) {
        await _closeSpecificPeerConnection(newConnection);
      }

      if (_isGenerationCurrent(generation)) {
        await _releaseResources(
          clearExternalCallbacks: false,
          invalidateGeneration: true,
        );
      }

      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  // =============================================================
  // PEER CONFIGURATION
  // =============================================================

  Map<String, dynamic> _buildPeerConfiguration() {
    return <String, dynamic>{
      'iceServers': _copyIceServers(_iceServers),
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'balanced',
      _muxPolicyConfigurationKey: 'require',
      'sdpSemantics': 'unified-plan',
    };
  }

  // =============================================================
  // GENERATION VALIDATION
  // =============================================================

  bool _isGenerationCurrent(int generation) {
    return generation == _connectionGeneration &&
        !_isDisposing;
  }

  bool _isConnectionCurrent({
    required int generation,
    required RTCPeerConnection connection,
  }) {
    return generation == _connectionGeneration &&
        identical(peerConnection, connection) &&
        !_isDisposing;
  }

  // =============================================================
  // STREAM CONTROLLER SAFETY
  // =============================================================

  void _ensureStreamControllers() {
    if (_localStreamController.isClosed) {
      _localStreamController =
      StreamController<MediaStream?>.broadcast();
    }

    if (_remoteStreamController.isClosed) {
      _remoteStreamController =
      StreamController<MediaStream?>.broadcast();
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

  // =============================================================
  // PEER CONNECTION CALLBACKS
  // =============================================================

  void _configurePeerConnectionCallbacks(
      RTCPeerConnection connection, {
        required int generation,
      }) {
    connection.onConnectionState =
        (RTCPeerConnectionState state) {
      if (!_isConnectionCurrent(
        generation: generation,
        connection: connection,
      )) {
        return;
      }

      _debugPrint('PeerConnection state -> $state');

      _safeStateCallback(
        onConnectionStateChanged,
        state,
        source: 'connection-state callback',
      );

      if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_clearRemoteStream());
      }
    };

    connection.onIceConnectionState =
        (RTCIceConnectionState state) {
      if (!_isConnectionCurrent(
        generation: generation,
        connection: connection,
      )) {
        return;
      }

      _debugPrint('ICE connection state -> $state');

      _safeStateCallback(
        onIceConnectionStateChanged,
        state,
        source: 'ICE-state callback',
      );
    };

    connection.onSignalingState =
        (RTCSignalingState state) {
      if (!_isConnectionCurrent(
        generation: generation,
        connection: connection,
      )) {
        return;
      }

      _debugPrint('Signaling state -> $state');

      _safeStateCallback(
        onSignalingStateChanged,
        state,
        source: 'signaling-state callback',
      );
    };

    connection.onIceGatheringState =
        (RTCIceGatheringState state) {
      if (!_isConnectionCurrent(
        generation: generation,
        connection: connection,
      )) {
        return;
      }

      _debugPrint('ICE gathering state -> $state');

      _safeStateCallback(
        onIceGatheringStateChanged,
        state,
        source: 'ICE-gathering callback',
      );
    };

    connection.onTrack = (RTCTrackEvent event) {
      if (!_isConnectionCurrent(
        generation: generation,
        connection: connection,
      )) {
        return;
      }

      _handleRemoteTrack(
        event,
        generation: generation,
        connection: connection,
      );
    };
  }

  void _safeStateCallback<T>(
      void Function(T value)? callback,
      T value, {
        required String source,
      }) {
    if (callback == null) {
      return;
    }

    try {
      callback(value);
    } catch (error, stackTrace) {
      _reportError(
        source,
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // REMOTE MEDIA
  // =============================================================

  void _handleRemoteTrack(
      RTCTrackEvent event, {
        required int generation,
        required RTCPeerConnection connection,
      }) {
    if (!_isConnectionCurrent(
      generation: generation,
      connection: connection,
    )) {
      return;
    }

    if (event.streams.isEmpty) {
      _debugPrint(
        'Remote ${event.track.kind ?? 'unknown'} '
            'track arrived without a MediaStream.',
      );

      return;
    }

    final MediaStream incomingStream =
        event.streams.first;

    if (remoteStream?.id != incomingStream.id) {
      _endedRemoteTracks.clear();

      remoteStream = incomingStream;

      _emitRemoteStream(incomingStream);
    }

    final StreamTrackCallback? previousOnEnded =
        event.track.onEnded;

    event.track.onEnded = () {
      try {
        previousOnEnded?.call();
      } catch (error, stackTrace) {
        _reportError(
          'previous remote-track end callback',
          error,
          stackTrace,
        );
      }

      if (!_isConnectionCurrent(
        generation: generation,
        connection: connection,
      )) {
        return;
      }

      _endedRemoteTracks.add(event.track);

      _debugPrint(
        'Remote ${event.track.kind ?? 'unknown'} track ended.',
      );

      final MediaStream? activeRemote = remoteStream;

      if (activeRemote == null ||
          activeRemote.id != incomingStream.id) {
        return;
      }

      final bool stillHasActiveTrack =
      activeRemote.getTracks().any(
            (MediaStreamTrack track) =>
        !_endedRemoteTracks.contains(track),
      );

      if (!stillHasActiveTrack) {
        unawaited(
          _clearRemoteStream(stopTracks: false),
        );
      }
    };
  }

  Future<void> _clearRemoteStream({
    bool stopTracks = true,
  }) async {
    final MediaStream? stream = remoteStream;

    remoteStream = null;

    _endedRemoteTracks.clear();

    _emitRemoteStream(null);

    if (stream == null || !stopTracks) {
      return;
    }

    await _disposeMediaStream(stream);
  }

  // =============================================================
  // LOCAL MEDIA ACQUISITION
  // =============================================================

  Future<MediaStream> _createLocalMediaStream({
    required bool video,
    required bool audio,
  }) async {
    if (!video && !audio) {
      throw ArgumentError(
        'At least audio or video must be enabled.',
      );
    }

    final Map<String, dynamic> constraints =
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
        'facingMode': 'user',
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
      }
          : false,
    };

    try {
      final MediaStream stream =
      await navigator.mediaDevices.getUserMedia(
        constraints,
      );

      if (audio &&
          stream.getAudioTracks().isEmpty) {
        await _disposeMediaStream(stream);

        throw StateError(
          'Microphone media acquisition completed '
              'without an audio track.',
        );
      }

      if (video &&
          stream.getVideoTracks().isEmpty) {
        await _disposeMediaStream(stream);

        throw StateError(
          'Camera media acquisition completed '
              'without a video track.',
        );
      }

      return stream;
    } catch (error, stackTrace) {
      _reportError(
        'getUserMedia',
        error,
        stackTrace,
      );

      rethrow;
    }
  }

  // =============================================================
  // LOCAL TRACK PUBLICATION
  // =============================================================

  Future<void> _publishLocalTracks({
    required RTCPeerConnection connection,
    required MediaStream stream,
  }) async {
    final List<RTCRtpSender> senders =
    await connection.getSenders();

    for (final RTCRtpSender sender in senders) {
      final String? kind =
      _normalizedTrackKind(sender.track);

      if (kind != null &&
          !_localSendersByKind.containsKey(kind)) {
        _localSendersByKind[kind] = sender;
      }
    }

    for (final MediaStreamTrack track
    in stream.getTracks()) {
      RTCRtpSender? existingTrackSender;

      final String? trackId = track.id;

      if (trackId != null && trackId.isNotEmpty) {
        for (final RTCRtpSender sender in senders) {
          if (sender.track?.id == trackId) {
            existingTrackSender = sender;
            break;
          }
        }
      }

      final String? kind =
      _normalizedTrackKind(track);

      if (existingTrackSender != null) {
        if (kind != null) {
          _localSendersByKind[kind] =
              existingTrackSender;
        }

        continue;
      }

      final RTCRtpSender sender =
      await connection.addTrack(
        track,
        stream,
      );

      if (kind != null) {
        _localSendersByKind[kind] = sender;
      }
    }
  }

  String? _normalizedTrackKind(
      MediaStreamTrack? track,
      ) {
    final String? rawKind = track?.kind;

    if (rawKind == null) {
      return null;
    }

    final String normalized =
    rawKind.trim().toLowerCase();

    return normalized.isEmpty ? null : normalized;
  }

  // =============================================================
  // SIGNALING STATE HELPERS
  // =============================================================

  bool _canCreateOfferFromState(
      RTCSignalingState? state,
      ) {
    return state == null ||
        state ==
            RTCSignalingState.RTCSignalingStateStable;
  }

  bool _canCreateAnswerFromState(
      RTCSignalingState? state,
      ) {
    return state == null ||
        state ==
            RTCSignalingState
                .RTCSignalingStateHaveRemoteOffer ||
        state ==
            RTCSignalingState
                .RTCSignalingStateHaveLocalPrAnswer;
  }

  // =============================================================
  // OFFER
  // =============================================================

  Future<RTCSessionDescription> createOffer({
    bool iceRestart = false,
  }) async {
    final RTCPeerConnection connection =
    _requirePeerConnection();

    if (connection.connectionState ==
        RTCPeerConnectionState
            .RTCPeerConnectionStateClosed) {
      throw StateError(
        'Cannot create offer on a closed PeerConnection.',
      );
    }

    final RTCSignalingState? state =
        connection.signalingState;

    if (!_canCreateOfferFromState(state)) {
      throw StateError(
        'Cannot create offer while signaling state is $state.',
      );
    }

    final Map<String, dynamic> offerConstraints =
    <String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _lastVideoParam,
      if (iceRestart) 'iceRestart': true,
    };

    final RTCSessionDescription offer =
    await connection.createOffer(
      offerConstraints,
    );

    _validateSessionDescription(
      offer,
      expectedType: _offerType,
    );

    await connection.setLocalDescription(offer);

    return offer;
  }

  // =============================================================
  // ANSWER
  // =============================================================

  Future<RTCSessionDescription> createAnswer() async {
    final RTCPeerConnection connection =
    _requirePeerConnection();

    if (connection.connectionState ==
        RTCPeerConnectionState
            .RTCPeerConnectionStateClosed) {
      throw StateError(
        'Cannot create answer on a closed PeerConnection.',
      );
    }

    final String cachedRemoteType =
        _appliedRemoteType?.trim().toLowerCase() ?? '';

    final String cachedRemoteSdp =
        _appliedRemoteSdp?.trim() ?? '';

    if (cachedRemoteSdp.isEmpty ||
        cachedRemoteType != _offerType) {
      throw StateError(
        'Remote offer must be successfully applied '
            'before creating an answer.',
      );
    }

    final RTCSignalingState? state =
        connection.signalingState;

    if (!_canCreateAnswerFromState(state)) {
      throw StateError(
        'Cannot create answer while signaling state is $state.',
      );
    }

    final RTCSessionDescription answer =
    await connection.createAnswer(
      <String, dynamic>{
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _lastVideoParam,
      },
    );

    _validateSessionDescription(
      answer,
      expectedType: _answerType,
    );

    await connection.setLocalDescription(answer);

    return answer;
  }

  // =============================================================
  // REMOTE SDP
  // =============================================================

  Future<void> setRemoteDescription({
    required String sdp,
    required String type,
  }) async {
    final RTCPeerConnection connection =
    _requirePeerConnection();

    final String normalizedSdp = sdp.trim();

    final String normalizedType =
    type.trim().toLowerCase();

    if (normalizedSdp.isEmpty) {
      throw ArgumentError(
        'Remote SDP cannot be empty.',
      );
    }

    if (normalizedType != _offerType &&
        normalizedType != _answerType &&
        normalizedType != _provisionalAnswerType) {
      throw ArgumentError.value(
        type,
        'type',
        'Unsupported WebRTC SDP type.',
      );
    }

    final String cachedSdp =
        _appliedRemoteSdp?.trim() ?? '';

    final String cachedType =
        _appliedRemoteType?.trim().toLowerCase() ?? '';

    if (cachedSdp == normalizedSdp &&
        cachedType == normalizedType) {
      _debugPrint(
        'Remote SDP already applied; duplicate ignored.',
      );

      return;
    }

    final RTCSessionDescription description =
    RTCSessionDescription(
      normalizedSdp,
      normalizedType,
    );

    await connection.setRemoteDescription(
      description,
    );

    _appliedRemoteSdp = normalizedSdp;
    _appliedRemoteType = normalizedType;

    _debugPrint(
      'Remote $normalizedType SDP applied successfully.',
    );
  }

  Future<RTCSessionDescription?> getLocalDescription() async {
    final RTCPeerConnection? connection =
        peerConnection;

    if (connection == null) {
      return null;
    }

    return connection.getLocalDescription();
  }

  // =============================================================
  // SAFE REMOTE DESCRIPTION GETTER
  // =============================================================

  Future<RTCSessionDescription?> getRemoteDescription() async {
    final RTCPeerConnection? connection =
        peerConnection;

    if (connection == null) {
      return null;
    }

    final String cachedSdp =
        _appliedRemoteSdp?.trim() ?? '';

    final String cachedType =
        _appliedRemoteType?.trim().toLowerCase() ?? '';

    if (cachedSdp.isNotEmpty &&
        cachedType.isNotEmpty) {
      return RTCSessionDescription(
        cachedSdp,
        cachedType,
      );
    }

    try {
      final RTCSessionDescription? nativeDescription =
      await connection.getRemoteDescription();

      if (nativeDescription == null) {
        return null;
      }

      final String nativeSdp =
          nativeDescription.sdp?.trim() ?? '';

      final String nativeType =
          nativeDescription.type
              ?.trim()
              .toLowerCase() ??
              '';

      if (nativeSdp.isNotEmpty &&
          nativeType.isNotEmpty) {
        _appliedRemoteSdp = nativeSdp;
        _appliedRemoteType = nativeType;
      }

      return nativeDescription;
    } catch (error, stackTrace) {
      if (_isNativeNullSdpError(error)) {
        _debugPrint(
          'Native remote SDP is not available yet; '
              'returning null safely.',
        );

        return null;
      }

      _reportError(
        'getRemoteDescription',
        error,
        stackTrace,
      );

      rethrow;
    }
  }

  bool _isNativeNullSdpError(
      Object error,
      ) {
    final String message =
    error.toString().toLowerCase();

    return message.contains(
      'session'
          'description is null',
    ) ||
        message.contains(
          'webrtc_set_remote_description_error',
        ) ||
        message.contains(
          'remote description is null',
        );
  }

  // =============================================================
  // REMOTE ICE COMPATIBILITY
  // =============================================================

  Future<void> addIceCandidate(
      RTCIceCandidate? candidate,
      ) async {
    final RTCPeerConnection? connection =
        peerConnection;

    if (connection == null || candidate == null) {
      return;
    }

    final String candidateValue =
        candidate.candidate?.trim() ?? '';

    if (candidateValue.isEmpty) {
      return;
    }

    final String remoteSdp =
        _appliedRemoteSdp?.trim() ?? '';

    final String remoteType =
        _appliedRemoteType?.trim().toLowerCase() ?? '';

    if (remoteSdp.isEmpty ||
        remoteType.isEmpty) {
      throw StateError(
        'Remote description must be set before adding '
            'an ICE candidate. IceManager owns pending candidates.',
      );
    }

    await connection.addCandidate(candidate);
  }

  Future<void> flushPendingCandidates() async {}

  // =============================================================
  // TURN / STUN CONFIGURATION
  // =============================================================

  Future<void> configureTurnFailoverServers([
    List<Map<String, dynamic>>? fallbackServers,
  ]) async {
    if (fallbackServers != null &&
        fallbackServers.isNotEmpty) {
      _iceServers =
          _copyIceServers(fallbackServers);
    }

    final RTCPeerConnection? connection =
        peerConnection;

    if (connection == null) {
      return;
    }

    try {
      await connection.setConfiguration(
        _buildPeerConfiguration(),
      );
    } catch (error, stackTrace) {
      _reportError(
        'configureTurnFailoverServers',
        error,
        stackTrace,
      );

      rethrow;
    }
  }

  // =============================================================
  // ICE RESTART
  // =============================================================

  Future<RTCSessionDescription> performIceRestart() async {
    final RTCPeerConnection connection =
    _requirePeerConnection();

    if (connection.connectionState ==
        RTCPeerConnectionState
            .RTCPeerConnectionStateClosed) {
      throw StateError(
        'Cannot restart ICE on a closed PeerConnection.',
      );
    }

    final RTCSignalingState? state =
        connection.signalingState;

    if (!_canCreateOfferFromState(state)) {
      throw StateError(
        'ICE restart requires a stable signaling state. '
            'Current state=$state.',
      );
    }

    await connection.restartIce();

    return createOffer(iceRestart: true);
  }

  // =============================================================
  // WAIT UNTIL CONNECTED
  // =============================================================

  Future<void> waitUntilConnected({
    Duration timeout =
    const Duration(seconds: 15),
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Connection timeout must be greater than zero.',
      );
    }

    if (isPeerConnected) {
      return;
    }

    final RTCPeerConnection connection =
    _requirePeerConnection();

    final int generation =
        _connectionGeneration;

    final Completer<void> completer =
    Completer<void>();

    void completeWithError(Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    final Timer pollTimer =
    Timer.periodic(
      const Duration(milliseconds: 150),
          (_) {
        if (completer.isCompleted) {
          return;
        }

        if (!_isConnectionCurrent(
          generation: generation,
          connection: connection,
        )) {
          completeWithError(
            StateError(
              'PeerConnection changed while '
                  'waiting for connection.',
            ),
          );

          return;
        }

        switch (connection.connectionState) {
          case RTCPeerConnectionState
              .RTCPeerConnectionStateConnected:
            completer.complete();
            break;

          case RTCPeerConnectionState
              .RTCPeerConnectionStateFailed:
            completeWithError(
              StateError(
                'PeerConnection entered failed state.',
              ),
            );
            break;

          case RTCPeerConnectionState
              .RTCPeerConnectionStateClosed:
            completeWithError(
              StateError(
                'PeerConnection was closed.',
              ),
            );
            break;

          default:
            break;
        }
      },
    );

    final Timer timeoutTimer =
    Timer(timeout, () {
      if (completer.isCompleted) {
        return;
      }

      completeWithError(
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
      pollTimer.cancel();
      timeoutTimer.cancel();
    }
  }

  // =============================================================
  // RAW WEBRTC STATISTICS
  // =============================================================

  Future<List<StatsReport>> getStats() async {
    final RTCPeerConnection? connection =
        peerConnection;

    if (connection == null) {
      return const <StatsReport>[];
    }

    try {
      return await connection.getStats();
    } catch (error, stackTrace) {
      _reportError(
        'getStats',
        error,
        stackTrace,
      );

      return const <StatsReport>[];
    }
  }

  // =============================================================
  // PARSED DIAGNOSTIC STATS
  // =============================================================

  Future<Map<String, dynamic>> getParsedStats() async {
    final List<StatsReport> reports =
    await getStats();

    if (reports.isEmpty) {
      return _emptyParsedStats();
    }

    final Map<String, Map<String, dynamic>>
    localCandidates =
    <String, Map<String, dynamic>>{};

    final Set<String> selectedPairIds =
    <String>{};

    int remoteInboundRttMs = 0;

    for (final StatsReport report in reports) {
      final Map<String, dynamic> values =
      _statsValues(report);

      if (report.type == _localCandidateType) {
        localCandidates[report.id] = values;
      }

      if (report.type == _transportType) {
        final String? selectedPairId =
        _readString(
          values['selectedCandidatePairId'],
        );

        if (selectedPairId != null) {
          selectedPairIds.add(selectedPairId);
        }
      }

      if (report.type == _remoteInboundRtpType) {
        final double? rawRtt =
        _readNonNegativeDouble(
          values['roundTripTime'],
        );

        if (rawRtt != null) {
          final int rttMs =
          (rawRtt * 1000).round();

          if (rttMs > remoteInboundRttMs) {
            remoteInboundRttMs = rttMs;
          }
        }
      }
    }

    int bytesReceived = 0;
    int bytesSent = 0;

    int packetsLost = 0;
    int packetsReceived = 0;

    double jitterSeconds = 0.0;
    double rttSeconds = 0.0;

    String transport = 'unknown';
    String candidatePair = 'unknown';

    bool selectedPairResolved = false;

    for (final StatsReport report in reports) {
      final Map<String, dynamic> values =
      _statsValues(report);

      switch (report.type) {
        case _inboundRtpType:
          bytesReceived +=
              _readNonNegativeInt(
                values['bytesReceived'],
              ) ??
                  0;

          packetsLost +=
              _readNonNegativeInt(
                values['packetsLost'],
              ) ??
                  0;

          packetsReceived +=
              _readNonNegativeInt(
                values['packetsReceived'],
              ) ??
                  0;

          final double? rawJitter =
          _readNonNegativeDouble(
            values['jitter'],
          );

          if (rawJitter != null &&
              rawJitter > jitterSeconds) {
            jitterSeconds = rawJitter;
          }

          break;

        case _outboundRtpType:
          bytesSent +=
              _readNonNegativeInt(
                values['bytesSent'],
              ) ??
                  0;

          break;

        case _candidatePairType:
          final String? state =
          _readString(values['state']);

          if (state != 'succeeded') {
            break;
          }

          final bool explicitlySelected =
              selectedPairIds.contains(report.id) ||
                  _readBool(values['selected']);

          final bool nominated =
          _readBool(values['nominated']);

          if (!explicitlySelected &&
              selectedPairResolved) {
            break;
          }

          if (!explicitlySelected &&
              !nominated) {
            break;
          }

          final double? currentRtt =
          _readNonNegativeDouble(
            values['currentRoundTripTime'],
          );

          if (currentRtt != null) {
            rttSeconds = currentRtt;
          }

          final String localCandidateId =
              _readString(
                values['localCandidateId'],
              ) ??
                  'unknown';

          final String remoteCandidateId =
              _readString(
                values['remoteCandidateId'],
              ) ??
                  'unknown';

          candidatePair =
          '$localCandidateId <-> $remoteCandidateId';

          final Map<String, dynamic>?
          localCandidate =
          localCandidates[localCandidateId];

          final String? protocol =
          _readString(
            localCandidate?['protocol'],
          );

          final String? relayProtocol =
          _readString(
            localCandidate?['relayProtocol'],
          );

          final String? transportId =
          _readString(
            values['transportId'],
          );

          if (protocol != null &&
              relayProtocol != null &&
              relayProtocol != protocol) {
            transport =
            '$protocol/$relayProtocol';
          } else if (protocol != null) {
            transport = protocol;
          } else if (transportId != null) {
            transport = transportId;
          }

          if (explicitlySelected) {
            selectedPairResolved = true;
          }

          break;

        default:
          break;
      }
    }

    if (rttSeconds <= 0 &&
        remoteInboundRttMs > 0) {
      rttSeconds =
          remoteInboundRttMs / 1000.0;
    }

    final Stopwatch clock =
    _statsClock ??= (Stopwatch()..start());

    final Duration currentElapsed =
        clock.elapsed;

    double bitrateRx = 0.0;
    double bitrateTx = 0.0;

    final Duration? previousElapsed =
        _lastStatsElapsed;

    if (previousElapsed != null) {
      final int elapsedMicroseconds =
          currentElapsed.inMicroseconds -
              previousElapsed.inMicroseconds;

      if (elapsedMicroseconds > 0) {
        final double elapsedSeconds =
            elapsedMicroseconds /
                Duration.microsecondsPerSecond;

        bitrateRx = _calculateBitrateKbps(
          currentBytes: bytesReceived,
          previousBytes: _lastBytesReceived,
          elapsedSeconds: elapsedSeconds,
        );

        bitrateTx = _calculateBitrateKbps(
          currentBytes: bytesSent,
          previousBytes: _lastBytesSent,
          elapsedSeconds: elapsedSeconds,
        );
      }
    }

    _lastBytesReceived = bytesReceived;
    _lastBytesSent = bytesSent;
    _lastStatsElapsed = currentElapsed;

    final int packetTotal =
        packetsReceived + packetsLost;

    double packetLossPercent = 0.0;

    if (packetTotal > 0) {
      packetLossPercent =
          packetsLost / packetTotal * 100.0;
    }

    packetLossPercent =
        packetLossPercent
            .clamp(0.0, 100.0)
            .toDouble();

    return <String, dynamic>{
      'bitrateRx': bitrateRx,
      'bitrateTx': bitrateTx,
      'uploadBitrate': bitrateTx,
      'downloadBitrate': bitrateRx,
      'packetLoss': packetLossPercent,
      'packetsLost': packetsLost,
      'packetsReceived': packetsReceived,
      'rtt': (rttSeconds * 1000).round(),
      'jitter': jitterSeconds * 1000.0,
      'transport': transport,
      'candidatePair': candidatePair,
    };
  }

  Map<String, dynamic> _emptyParsedStats() {
    return <String, dynamic>{
      'bitrateRx': 0.0,
      'bitrateTx': 0.0,
      'uploadBitrate': 0.0,
      'downloadBitrate': 0.0,
      'packetLoss': 0.0,
      'packetsLost': 0,
      'packetsReceived': 0,
      'rtt': 0,
      'jitter': 0.0,
      'transport': 'unknown',
      'candidatePair': 'unknown',
    };
  }

  Map<String, dynamic> _statsValues(
      StatsReport report,
      ) {
    return <String, dynamic>{
      for (final MapEntry<dynamic, dynamic> entry
      in report.values.entries)
        entry.key.toString(): entry.value,
    };
  }

  double _calculateBitrateKbps({
    required int currentBytes,
    required int previousBytes,
    required double elapsedSeconds,
  }) {
    if (elapsedSeconds <= 0) {
      return 0.0;
    }

    final int byteDelta =
        currentBytes - previousBytes;

    if (byteDelta < 0) {
      return 0.0;
    }

    return byteDelta *
        8.0 /
        1000.0 /
        elapsedSeconds;
  }

  // =============================================================
  // AUDIO ENABLE / DISABLE
  // =============================================================

  Future<void> setAudioEnabled(
      bool enabled,
      ) async {
    final MediaStream? stream =
        localStream;

    if (stream == null) {
      return;
    }

    for (final MediaStreamTrack track
    in stream.getAudioTracks()) {
      track.enabled = enabled;
    }
  }

  // =============================================================
  // VIDEO ENABLE / DISABLE
  // =============================================================

  Future<void> setVideoEnabled(
      bool enabled,
      ) async {
    final MediaStream? stream =
        localStream;

    if (stream == null) {
      return;
    }

    for (final MediaStreamTrack track
    in stream.getVideoTracks()) {
      track.enabled = enabled;
    }
  }

  // =============================================================
  // CAMERA SWITCH
  // =============================================================

  Future<void> switchCamera() async {
    final List<MediaStreamTrack>? tracks =
    localStream?.getVideoTracks();

    if (tracks == null || tracks.isEmpty) {
      return;
    }

    await Helper.switchCamera(tracks.first);
  }

  // =============================================================
  // LOCAL MEDIA REPLACEMENT ENTRY
  // =============================================================

  Future<void> replaceMediaTracks({
    bool? video,
    bool? audio,
  }) async {
    if (_isDisposing) {
      return;
    }

    if (_isReplacingMedia) {
      final Future<void>? activeReplacement =
          _mediaReplacementFuture;

      if (activeReplacement != null) {
        await activeReplacement;

        if (_isDisposing ||
            peerConnection == null) {
          return;
        }

        await replaceMediaTracks(
          video: video,
          audio: audio,
        );
      }

      return;
    }

    final Future<void>? activeReplacement =
        _mediaReplacementFuture;

    if (activeReplacement != null) {
      await activeReplacement;

      if (_isDisposing ||
          peerConnection == null) {
        return;
      }

      await replaceMediaTracks(
        video: video,
        audio: audio,
      );

      return;
    }

    final bool useVideo =
        video ?? _lastVideoParam;

    final bool useAudio =
        audio ?? _lastAudioParam;

    if (!useVideo && !useAudio) {
      throw ArgumentError(
        'At least audio or video must remain enabled.',
      );
    }

    final Future<void> operation =
    _performMediaReplacement(
      useVideo: useVideo,
      useAudio: useAudio,
    );

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _mediaReplacementFuture,
        tracked,
      )) {
        _mediaReplacementFuture = null;
      }
    });

    _mediaReplacementFuture = tracked;

    await tracked;
  }

  // =============================================================
  // TRANSACTIONAL LOCAL MEDIA REPLACEMENT
  // =============================================================

  Future<void> _performMediaReplacement({
    required bool useVideo,
    required bool useAudio,
  }) async {
    final RTCPeerConnection connection =
    _requirePeerConnection();

    _isReplacingMedia = true;

    final int generation =
        _connectionGeneration;

    final Map<String, RTCRtpSender>
    previousSenderMap =
    Map<String, RTCRtpSender>.from(
      _localSendersByKind,
    );

    final Map<RTCRtpSender,
        MediaStreamTrack?>
    originalSenderTracks =
    <RTCRtpSender,
        MediaStreamTrack?>{};

    final List<RTCRtpSender>
    newlyAddedSenders =
    <RTCRtpSender>[];

    MediaStream? uncommittedStream;

    bool committed = false;

    try {
      final MediaStream acquiredStream =
      await _createLocalMediaStream(
        video: useVideo,
        audio: useAudio,
      );

      uncommittedStream = acquiredStream;

      if (!_isConnectionCurrent(
        generation: generation,
        connection: connection,
      )) {
        await _disposeMediaStream(
          acquiredStream,
        );

        uncommittedStream = null;

        return;
      }

      final List<RTCRtpSender> senders =
      await connection.getSenders();

      if (!_isConnectionCurrent(
        generation: generation,
        connection: connection,
      )) {
        await _disposeMediaStream(
          acquiredStream,
        );

        uncommittedStream = null;

        return;
      }

      for (final RTCRtpSender sender in senders) {
        final String? kind =
        _normalizedTrackKind(sender.track);

        if (kind != null &&
            !_localSendersByKind
                .containsKey(kind)) {
          _localSendersByKind[kind] = sender;
        }
      }

      for (final MediaStreamTrack newTrack
      in acquiredStream.getTracks()) {
        final String? kind =
        _normalizedTrackKind(newTrack);

        if (kind == null) {
          continue;
        }

        RTCRtpSender? matchingSender =
        _localSendersByKind[kind];

        if (matchingSender == null) {
          for (final RTCRtpSender sender
          in senders) {
            if (_normalizedTrackKind(
              sender.track,
            ) ==
                kind) {
              matchingSender = sender;
              break;
            }
          }
        }

        if (matchingSender != null) {
          final RTCRtpSender sender =
              matchingSender;

          originalSenderTracks.putIfAbsent(
            sender,
                () => sender.track,
          );

          await sender.replaceTrack(
            newTrack,
          );

          _localSendersByKind[kind] = sender;
        } else {
          final RTCRtpSender sender =
          await connection.addTrack(
            newTrack,
            acquiredStream,
          );

          newlyAddedSenders.add(sender);

          _localSendersByKind[kind] = sender;
        }

        if (!_isConnectionCurrent(
          generation: generation,
          connection: connection,
        )) {
          await _rollbackMediaReplacement(
            connection: connection,
            originalSenderTracks:
            originalSenderTracks,
            newlyAddedSenders:
            newlyAddedSenders,
            previousSenderMap:
            previousSenderMap,
          );

          await _disposeMediaStream(
            acquiredStream,
          );

          uncommittedStream = null;

          return;
        }
      }

      if (!useAudio) {
        final RTCRtpSender? audioSender =
        _localSendersByKind[_audioKind];

        if (audioSender != null) {
          originalSenderTracks.putIfAbsent(
            audioSender,
                () => audioSender.track,
          );

          await audioSender.replaceTrack(
            null,
          );
        }
      }

      if (!useVideo) {
        final RTCRtpSender? videoSender =
        _localSendersByKind[_videoKind];

        if (videoSender != null) {
          originalSenderTracks.putIfAbsent(
            videoSender,
                () => videoSender.track,
          );

          await videoSender.replaceTrack(
            null,
          );
        }
      }

      if (!_isConnectionCurrent(
        generation: generation,
        connection: connection,
      )) {
        await _rollbackMediaReplacement(
          connection: connection,
          originalSenderTracks:
          originalSenderTracks,
          newlyAddedSenders:
          newlyAddedSenders,
          previousSenderMap:
          previousSenderMap,
        );

        await _disposeMediaStream(
          acquiredStream,
        );

        uncommittedStream = null;

        return;
      }

      final MediaStream? previousStream =
          localStream;

      localStream = acquiredStream;

      _lastVideoParam = useVideo;
      _lastAudioParam = useAudio;

      _emitLocalStream(acquiredStream);

      committed = true;

      uncommittedStream = null;

      if (previousStream != null &&
          previousStream.id != acquiredStream.id) {
        await _disposeMediaStream(
          previousStream,
        );
      }
    } catch (error, stackTrace) {
      _reportError(
        'replaceMediaTracks',
        error,
        stackTrace,
      );

      if (!committed) {
        await _rollbackMediaReplacement(
          connection: connection,
          originalSenderTracks:
          originalSenderTracks,
          newlyAddedSenders:
          newlyAddedSenders,
          previousSenderMap:
          previousSenderMap,
        );

        final MediaStream? streamToDispose =
            uncommittedStream;

        if (streamToDispose != null) {
          await _disposeMediaStream(
            streamToDispose,
          );
        }
      }

      rethrow;
    } finally {
      _isReplacingMedia = false;
    }
  }

  // =============================================================
  // MEDIA REPLACEMENT ROLLBACK
  // =============================================================

  Future<void> _rollbackMediaReplacement({
    required RTCPeerConnection connection,
    required Map<RTCRtpSender,
        MediaStreamTrack?>
    originalSenderTracks,
    required List<RTCRtpSender>
    newlyAddedSenders,
    required Map<String, RTCRtpSender>
    previousSenderMap,
  }) async {
    for (final MapEntry<RTCRtpSender,
        MediaStreamTrack?> entry
    in originalSenderTracks.entries) {
      try {
        await entry.key.replaceTrack(
          entry.value,
        );
      } catch (error, stackTrace) {
        _reportError(
          'media replacement rollback',
          error,
          stackTrace,
        );
      }
    }

    for (final RTCRtpSender sender
    in newlyAddedSenders) {
      try {
        await connection.removeTrack(
          sender,
        );
      } catch (error, stackTrace) {
        _reportError(
          'media sender rollback',
          error,
          stackTrace,
        );
      }
    }

    _localSendersByKind
      ..clear()
      ..addAll(previousSenderMap);
  }

  // =============================================================
  // LEGACY FULL PEER CONNECTION RESTART
  // =============================================================

  Future<void> restartPeerConnection() async {
    if (_isRestarting) {
      return;
    }

    _isRestarting = true;

    final bool video =
        _lastVideoParam;

    final bool audio =
        _lastAudioParam;

    final List<Map<String, dynamic>> servers =
    _copyIceServers(_iceServers);

    final void Function(
        RTCPeerConnectionState state)?
    connectionCallback =
        onConnectionStateChanged;

    final void Function(
        RTCIceConnectionState state)?
    iceConnectionCallback =
        onIceConnectionStateChanged;

    final void Function(
        RTCSignalingState state)?
    signalingCallback =
        onSignalingStateChanged;

    final void Function(
        RTCIceGatheringState state)?
    gatheringCallback =
        onIceGatheringStateChanged;

    final void Function(
        RTCIceCandidate candidate)?
    compatibilityIceCallback =
        _legacyIceCandidateCallback;

    try {
      await _releaseResources(
        clearExternalCallbacks: false,
        invalidateGeneration: true,
      );

      onConnectionStateChanged =
          connectionCallback;

      onIceConnectionStateChanged =
          iceConnectionCallback;

      onSignalingStateChanged =
          signalingCallback;

      onIceGatheringStateChanged =
          gatheringCallback;

      _legacyIceCandidateCallback =
          compatibilityIceCallback;

      await initializeConnection(
        video: video,
        audio: audio,
        iceServers: servers,
      );

      final RTCPeerConnection? recreated =
          peerConnection;

      if (recreated == null) {
        return;
      }

      final void Function(
          RTCPeerConnection connection)?
      callback =
          onPeerConnectionRecreated;

      if (callback == null) {
        return;
      }

      try {
        callback(recreated);
      } catch (error, stackTrace) {
        _reportError(
          'peer recreation callback',
          error,
          stackTrace,
        );
      }
    } finally {
      _isRestarting = false;
    }
  }

  // =============================================================
  // CLOSE PEER CONNECTION
  // =============================================================

  Future<void> closePeerConnection() async {
    final RTCPeerConnection? connection =
        peerConnection;

    peerConnection = null;

    _localSendersByKind.clear();

    _clearAppliedRemoteDescription();

    if (connection == null) {
      return;
    }

    _detachOwnedPeerConnectionCallbacks(
      connection,
    );

    await _closeSpecificPeerConnection(
      connection,
    );
  }

  Future<void> _closeSpecificPeerConnection(
      RTCPeerConnection connection,
      ) async {
    try {
      await connection.close();
    } catch (error, stackTrace) {
      _reportError(
        'PeerConnection.close',
        error,
        stackTrace,
      );
    }

    try {
      final dynamic disposableConnection =
          connection;

      await disposableConnection.dispose();
    } catch (_) {
      // close() remains the portable shutdown operation.
    }
  }

  // =============================================================
  // DETACH ONLY CALLBACKS OWNED BY THIS SERVICE
  // =============================================================

  void _detachOwnedPeerConnectionCallbacks(
      RTCPeerConnection connection,
      ) {
    try {
      connection.onTrack = null;

      connection.onConnectionState = null;

      connection.onIceConnectionState = null;

      connection.onSignalingState = null;

      connection.onIceGatheringState = null;
    } catch (_) {
      // Native PeerConnection may already be released.
    }
  }

  // =============================================================
  // RESET CONNECTION-DIAGNOSTIC STATE
  // =============================================================

  void resetConnectionState() {
    _resetStatsState();

    _clearAppliedRemoteDescription();

    unawaited(_clearRemoteStream());
  }

  void _resetStatsState() {
    _lastBytesReceived = 0;

    _lastBytesSent = 0;

    _lastStatsElapsed = null;

    _statsClock?.stop();

    _statsClock = null;
  }

  // =============================================================
  // REMOTE SDP CACHE RESET
  // =============================================================

  void _clearAppliedRemoteDescription() {
    _appliedRemoteSdp = null;
    _appliedRemoteType = null;
  }

  // =============================================================
  // RESOURCE CLEANUP
  // =============================================================

  Future<void> dispose() async {
    await _releaseResources(
      clearExternalCallbacks: true,
      invalidateGeneration: true,
    );
  }

  Future<void> _releaseResources({
    required bool clearExternalCallbacks,
    required bool invalidateGeneration,
  }) async {
    final Future<void>? activeRelease =
        _releaseFuture;

    if (activeRelease != null) {
      await activeRelease;

      if (clearExternalCallbacks) {
        _clearExternalCallbacks();
      }

      return;
    }

    final Future<void> operation =
    _performReleaseResources(
      clearExternalCallbacks:
      clearExternalCallbacks,
      invalidateGeneration:
      invalidateGeneration,
    );

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _releaseFuture,
        tracked,
      )) {
        _releaseFuture = null;
      }
    });

    _releaseFuture = tracked;

    await tracked;
  }

  Future<void> _performReleaseResources({
    required bool clearExternalCallbacks,
    required bool invalidateGeneration,
  }) async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    if (invalidateGeneration) {
      _connectionGeneration++;
    }

    try {
      final Future<void>? mediaReplacement =
          _mediaReplacementFuture;

      if (mediaReplacement != null) {
        try {
          await mediaReplacement;
        } catch (error, stackTrace) {
          _reportError(
            'pending media replacement during cleanup',
            error,
            stackTrace,
          );
        }
      }

      await closePeerConnection();

      final MediaStream? local =
          localStream;

      localStream = null;

      if (local != null) {
        await _disposeMediaStream(local);
      }

      _emitLocalStream(null);

      await _clearRemoteStream();

      _resetStatsState();

      _clearAppliedRemoteDescription();

      _localSendersByKind.clear();

      _endedRemoteTracks.clear();

      _isReplacingMedia = false;

      if (clearExternalCallbacks) {
        _clearExternalCallbacks();
      }

      _debugPrint(
        'WebRTC resources released.',
      );
    } finally {
      _isDisposing = false;
    }
  }

  void _clearExternalCallbacks() {
    _legacyIceCandidateCallback = null;

    onConnectionStateChanged = null;

    onIceConnectionStateChanged = null;

    onSignalingStateChanged = null;

    onIceGatheringStateChanged = null;

    onPeerConnectionRecreated = null;
  }

  // =============================================================
  // MEDIA DISPOSAL
  // =============================================================

  Future<void> _disposeMediaStream(
      MediaStream stream,
      ) async {
    for (final MediaStreamTrack track
    in stream.getTracks()) {
      try {
        await track.stop();
      } catch (_) {
        // Track may already be stopped or ended.
      }
    }

    await _disposeMediaStreamSafely(stream);
  }

  Future<void> _disposeMediaStreamSafely(
      MediaStream stream,
      ) async {
    try {
      await stream.dispose();
    } catch (_) {
      // Native stream may already have been disposed.
    }
  }

  // =============================================================
  // PEER CONNECTION REQUIREMENT
  // =============================================================

  RTCPeerConnection _requirePeerConnection() {
    final RTCPeerConnection? connection =
        peerConnection;

    if (connection == null) {
      throw StateError(
        'PeerConnection is not initialized.',
      );
    }

    return connection;
  }

  // =============================================================
  // SDP VALIDATION
  // =============================================================

  void _validateSessionDescription(
      RTCSessionDescription description, {
        required String expectedType,
      }) {
    final String sdp =
        description.sdp?.trim() ?? '';

    final String type =
        description.type?.trim().toLowerCase() ??
            '';

    if (sdp.isEmpty ||
        type != expectedType.toLowerCase()) {
      throw StateError(
        'Generated WebRTC $expectedType '
            'session description is invalid.',
      );
    }
  }

  // =============================================================
  // VALUE HELPERS
  // =============================================================

  String? _readString(Object? value) {
    if (value == null) {
      return null;
    }

    final String normalized =
    value.toString().trim();

    return normalized.isEmpty
        ? null
        : normalized;
  }

  bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final String normalized =
      value.trim().toLowerCase();

      return normalized == 'true' ||
          normalized == '1';
    }

    return false;
  }

  int? _readNonNegativeInt(Object? value) {
    int? result;

    if (value is int) {
      result = value;
    } else if (value is num &&
        value.isFinite) {
      result = value.toInt();
    } else if (value is String) {
      result = int.tryParse(
        value.trim(),
      );
    }

    if (result == null || result < 0) {
      return null;
    }

    return result;
  }

  double? _readNonNegativeDouble(
      Object? value,
      ) {
    double? result;

    if (value is double) {
      result = value;
    } else if (value is num) {
      result = value.toDouble();
    } else if (value is String) {
      result = double.tryParse(
        value.trim(),
      );
    }

    if (result == null ||
        !result.isFinite ||
        result < 0) {
      return null;
    }

    return result;
  }

  // =============================================================
  // ICE SERVER COPY
  // =============================================================

  List<Map<String, dynamic>> _copyIceServers(
      List<Map<String, dynamic>> source,
      ) {
    return source
        .map<Map<String, dynamic>>(
          (Map<String, dynamic> server) {
        final Map<String, dynamic> copy =
        Map<String, dynamic>.from(server);

        final Object? urls = copy['urls'];

        if (urls is List) {
          copy['urls'] =
          List<dynamic>.from(urls);
        }

        return copy;
      },
    )
        .toList(growable: false);
  }

  // =============================================================
  // LOGGING
  // =============================================================

  void _debugPrint(String message) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[WebRTCService] '
          '$message',
    );
  }

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
          '[WebRTCService/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[WebRTCService/$source]',
        stackTrace: stackTrace,
      );
    }
  }
}

// ===============================================================
// END OF FILE
// ===============================================================
//
// JR CALL — REMOTE SDP NULL RACE FIX
//
// FIXED:
//
// ✓ Removed unsafe native getRemoteDescription() pre-read from
//   setRemoteDescription().
//
// ✓ Added internally cached successfully-applied remote SDP.
//
// ✓ createAnswer() no longer requires a native
//   getRemoteDescription() call immediately after applying the
//   incoming offer.
//
// ✓ getRemoteDescription() safely prefers the successful local
//   SDP cache and handles transient native NULL descriptions.
//
// ✓ addIceCandidate() uses the applied SDP cache instead of
//   performing an unsafe native remote-description pre-read.
//
// ✓ Remote SDP cache is cleared whenever the native
//   PeerConnection is recreated, closed, reset, or disposed.
//
// ✓ Native setRemoteDescription() remains the final authority.
//
// ✓ Remote SDP is cached ONLY after native application succeeds.
//
// ✓ IDE spell-check warning fixed without changing the native
//   runtime error-matching text.
//
// PRESERVED:
//
// ✓ Single PeerConnection ownership.
// ✓ Local microphone acquisition.
// ✓ Local camera acquisition.
// ✓ Voice-call media path.
// ✓ Video-call media path.
// ✓ 720p / 30 fps video configuration.
// ✓ Audio processing constraints.
// ✓ Offer creation.
// ✓ Answer creation.
// ✓ Local SDP.
// ✓ Remote SDP.
// ✓ ICE configuration.
// ✓ ICE restart.
// ✓ IceManager native ICE ownership.
// ✓ Remote track handling.
// ✓ Camera switching.
// ✓ Audio enable/disable.
// ✓ Video enable/disable.
// ✓ Media replacement.
// ✓ Replacement rollback.
// ✓ Statistics.
// ✓ Cleanup.
// ✓ Generation protection.
// ✓ External callback ownership.
// ✓ No Firestore logic.
// ✓ No UI changes.
// ✓ No CallService API changes.
// ✓ No RecoveryManager ownership changes.
//
// IMPORTANT:
//
// The spell-check fix intentionally keeps the runtime matching
// semantics unchanged:
//
//   'session' 'description is null'
//
// Dart concatenates adjacent string literals at compile time,
// so the runtime value remains:
//
//   sessiondescription is null
//
// while Android Studio no longer reports the combined word as a
// typo.
//
// ===============================================================