import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../call/stun_turn_service.dart';
import 'recovery_manager.dart';

/// ===========================================================
/// JR CALL
/// File: peer_connection_manager.dart
/// Location: lib/services/managers/peer_connection_manager.dart
///
/// FINAL PRODUCTION LOW-LEVEL PEER CONNECTION MANAGER
///
/// OWNERSHIP:
///
/// PeerConnectionManager:
/// - PeerConnection creation/lifecycle.
/// - Local/remote description application.
/// - Local track attachment.
/// - PeerConnection state callbacks.
/// - Native ICE restart request.
/// - Low-level compatibility DataChannel creation.
///
/// IceManager:
/// - ONLY owner of RTCPeerConnection.onIceCandidate.
/// - Local/remote ICE candidate coordination.
///
/// SignalingService:
/// - SDP/ICE persistence.
///
/// MediaManager:
/// - Media acquisition/lifecycle.
///
/// DataChannelManager:
/// - High-level DataChannel ownership.
///
/// RecoveryManager:
/// - Recovery policy/orchestration.
///
/// IMPORTANT:
///
/// The existing initializeConnection(onIceCandidate: ...) parameter
/// is preserved for source compatibility, but this class NEVER
/// installs peerConnection.onIceCandidate.
///
/// IceManager exclusively owns that callback.
/// ===========================================================

class PeerConnectionManager extends ChangeNotifier {
  PeerConnectionManager._();

  static final PeerConnectionManager instance =
  PeerConnectionManager._();

  // ===========================================================
  // SDP TYPE CONSTANTS
  // ===========================================================

  static const String _offerType = 'offer';
  static const String _answerType = 'answer';

  // Runtime value is exactly the WebRTC provisional-answer type.
  // Split only to avoid IDE spelling inspection noise.
  static const String _provisionalAnswerType = 'pr' 'answer';

  static const String _rollbackType = 'rollback';

  // ===========================================================
  // CONNECTION STATE
  // ===========================================================

  RTCPeerConnection? _peerConnection;

  RTCDataChannel? _dataChannel;

  bool _initialized = false;

  bool _disposed = false;

  int _connectionGeneration = 0;

  Future<void>? _activeConnectionInitialization;

  Future<RTCDataChannel?>? _activeDataChannelCreation;

  // ===========================================================
  // NEGOTIATION STATE
  // ===========================================================

  bool? _isCallerRole;

  bool _makingOffer = false;

  bool _ignoreOffer = false;

  bool _renegotiationNeeded = false;

  /// Serializes local/remote SDP mutation operations.
  Future<void> _sdpMutationTail =
  Future<void>.value();

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  RTCPeerConnection? get peerConnection =>
      _peerConnection;

  RTCDataChannel? get dataChannel =>
      _dataChannel;

  bool get isInitialized =>
      _initialized;

  bool get hasPeerConnection =>
      _peerConnection != null;

  RTCPeerConnectionState? get connectionState =>
      _peerConnection?.connectionState;

  RTCIceConnectionState? get iceConnectionState =>
      _peerConnection?.iceConnectionState;

  RTCIceGatheringState? get iceGatheringState =>
      _peerConnection?.iceGatheringState;

  RTCSignalingState? get signalingState =>
      _peerConnection?.signalingState;

  bool get makingOffer =>
      _makingOffer;

  bool get ignoreOffer =>
      _ignoreOffer;

  bool get renegotiationNeeded =>
      _renegotiationNeeded;

  bool? get isCallerRole =>
      _isCallerRole;

  // ===========================================================
  // BASIC INITIALIZATION
  // ===========================================================

  Future<void> initialize() async {
    if (_disposed || _initialized) {
      return;
    }

    _initialized = true;

    _notifySafely();
  }

  // ===========================================================
  // NEGOTIATION ROLE
  //
  // FILE 09 deterministic glare contract:
  //
  // Caller:
  // - preferred / impolite side.
  //
  // Receiver:
  // - polite side.
  // ===========================================================

  void configureNegotiationRole({
    required bool isCaller,
  }) {
    if (_disposed) {
      return;
    }

    _isCallerRole = isCaller;

    _ignoreOffer = false;

    _notifySafely();
  }

  // ===========================================================
  // CONNECTION INITIALIZATION
  // ===========================================================

  Future<void> initializeConnection({
    required Function(RTCIceCandidate candidate)
    onIceCandidate,
    required Function(MediaStream stream)
    onAddStream,
    required Function(dynamic state)
    onIceConnectionStateChange,
  }) {
    if (_disposed) {
      return Future<void>.value();
    }

    if (_peerConnection != null) {
      if (!_initialized) {
        _initialized = true;

        _notifySafely();
      }

      return Future<void>.value();
    }

    final Future<void>? active =
        _activeConnectionInitialization;

    if (active != null) {
      return active;
    }

    final int generation =
    ++_connectionGeneration;

    final Future<void> future =
    _initializeConnectionInternal(
      generation: generation,
      onAddStream: onAddStream,
      onIceConnectionStateChange:
      onIceConnectionStateChange,
    );

    _activeConnectionInitialization =
        future;

    return future.whenComplete(() {
      if (identical(
        _activeConnectionInitialization,
        future,
      )) {
        _activeConnectionInitialization =
        null;
      }
    });
  }

  Future<void> _initializeConnectionInternal({
    required int generation,
    required Function(MediaStream stream)
    onAddStream,
    required Function(dynamic state)
    onIceConnectionStateChange,
  }) async {
    RTCPeerConnection? createdConnection;

    try {
      createdConnection =
      await StunTurnService.instance
          .createPeerConnection();

      if (!_isGenerationCurrent(
        generation,
      )) {
        await _closeNativeConnection(
          createdConnection,
        );

        return;
      }

      if (_peerConnection != null) {
        await _closeNativeConnection(
          createdConnection,
        );

        return;
      }

      _peerConnection =
          createdConnection;

      _installOwnedCallbacks(
        connection: createdConnection,
        generation: generation,
        onAddStream: onAddStream,
        onIceConnectionStateChange:
        onIceConnectionStateChange,
      );

      _initialized = true;

      _notifySafely();
    } catch (error, stackTrace) {
      if (_isGenerationCurrent(
        generation,
      )) {
        if (identical(
          _peerConnection,
          createdConnection,
        )) {
          _peerConnection = null;
        }

        _initialized = false;

        _notifySafely();
      }

      if (createdConnection != null) {
        await _closeNativeConnection(
          createdConnection,
        );
      }

      _reportError(
        'initialization',
        error,
        stackTrace,
      );

      rethrow;
    }
  }

  // ===========================================================
  // OWNED CALLBACKS
  //
  // DO NOT install onIceCandidate here.
  // IceManager exclusively owns it.
  // ===========================================================

  void _installOwnedCallbacks({
    required RTCPeerConnection connection,
    required int generation,
    required Function(MediaStream stream)
    onAddStream,
    required Function(dynamic state)
    onIceConnectionStateChange,
  }) {
    connection.onTrack =
        (RTCTrackEvent event) {
      if (!_isCurrentConnection(
        connection,
        generation,
      )) {
        return;
      }

      if (event.streams.isEmpty) {
        return;
      }

      try {
        onAddStream(
          event.streams.first,
        );
      } catch (error, stackTrace) {
        _reportError(
          'remote track callback',
          error,
          stackTrace,
        );
      }
    };

    connection.onIceConnectionState =
        (RTCIceConnectionState state) {
      if (!_isCurrentConnection(
        connection,
        generation,
      )) {
        return;
      }

      try {
        onIceConnectionStateChange(
          state,
        );
      } catch (error, stackTrace) {
        _reportError(
          'ICE state callback',
          error,
          stackTrace,
        );
      }

      try {
        RecoveryManager.instance
            .handleIceConnectionChange(
          state,
          connection,
          restartIce,
        );
      } catch (error, stackTrace) {
        _reportError(
          'RecoveryManager ICE handoff',
          error,
          stackTrace,
        );
      }

      _notifySafely();
    };

    connection.onConnectionState =
        (RTCPeerConnectionState state) {
      if (!_isCurrentConnection(
        connection,
        generation,
      )) {
        return;
      }

      _debugPrint(
        'connection=$state',
      );

      _notifySafely();
    };

    connection.onSignalingState =
        (RTCSignalingState state) {
      if (!_isCurrentConnection(
        connection,
        generation,
      )) {
        return;
      }

      if (state ==
          RTCSignalingState
              .RTCSignalingStateStable) {
        _ignoreOffer = false;
      }

      _debugPrint(
        'signaling=$state',
      );

      _notifySafely();
    };

    connection.onIceGatheringState =
        (RTCIceGatheringState state) {
      if (!_isCurrentConnection(
        connection,
        generation,
      )) {
        return;
      }

      _debugPrint(
        'gathering=$state',
      );

      _notifySafely();
    };

    connection.onRenegotiationNeeded =
        () {
      if (!_isCurrentConnection(
        connection,
        generation,
      )) {
        return;
      }

      // CallService/WebRTCService performs the actual signaling.
      _renegotiationNeeded = true;

      _debugPrint(
        'renegotiation needed.',
      );

      _notifySafely();
    };
  }

  // ===========================================================
  // DATA CHANNEL
  // ===========================================================

  Future<RTCDataChannel?> createDataChannel({
    String label = 'jr_call_data',
  }) {
    if (_disposed) {
      return Future<RTCDataChannel?>.value(
        null,
      );
    }

    final RTCPeerConnection? connection =
        _peerConnection;

    if (connection == null) {
      return Future<RTCDataChannel?>.value(
        null,
      );
    }

    final RTCDataChannel? existing =
        _dataChannel;

    if (existing != null) {
      return Future<RTCDataChannel?>.value(
        existing,
      );
    }

    final Future<RTCDataChannel?>? active =
        _activeDataChannelCreation;

    if (active != null) {
      return active;
    }

    final String normalizedLabel =
    label.trim();

    if (normalizedLabel.isEmpty) {
      return Future<RTCDataChannel?>.value(
        null,
      );
    }

    final int generation =
        _connectionGeneration;

    final Future<RTCDataChannel?> future =
    _createDataChannelInternal(
      connection: connection,
      generation: generation,
      label: normalizedLabel,
    );

    _activeDataChannelCreation =
        future;

    return future.whenComplete(() {
      if (identical(
        _activeDataChannelCreation,
        future,
      )) {
        _activeDataChannelCreation =
        null;
      }
    });
  }

  Future<RTCDataChannel?>
  _createDataChannelInternal({
    required RTCPeerConnection connection,
    required int generation,
    required String label,
  }) async {
    try {
      final RTCDataChannelInit configuration =
      RTCDataChannelInit()
        ..ordered = true;

      final RTCDataChannel channel =
      await connection.createDataChannel(
        label,
        configuration,
      );

      if (!_isCurrentConnection(
        connection,
        generation,
      )) {
        try {
          await channel.close();
        } catch (_) {}

        return null;
      }

      final RTCDataChannel? existing =
          _dataChannel;

      if (existing != null) {
        try {
          await channel.close();
        } catch (_) {}

        return existing;
      }

      _dataChannel = channel;

      _notifySafely();

      return channel;
    } catch (error, stackTrace) {
      _reportError(
        'data channel creation',
        error,
        stackTrace,
      );

      return null;
    }
  }

  // ===========================================================
  // CREATE OFFER
  // ===========================================================

  Future<RTCSessionDescription?> createOffer({
    bool iceRestart = false,
  }) {
    final RTCPeerConnection? connection =
        _peerConnection;

    if (_disposed ||
        connection == null) {
      return Future<
          RTCSessionDescription?>.value(
        null,
      );
    }

    final int generation =
        _connectionGeneration;

    return _runSerializedSdp<
        RTCSessionDescription?>(
          () async {
        if (!_isCurrentConnection(
          connection,
          generation,
        )) {
          return null;
        }

        if (!iceRestart &&
            connection.signalingState ==
                RTCSignalingState
                    .RTCSignalingStateHaveLocalOffer) {
          final RTCSessionDescription?
          existing =
          await connection
              .getLocalDescription();

          if (existing != null &&
              existing.type
                  ?.trim()
                  .toLowerCase() ==
                  _offerType) {
            return existing;
          }
        }

        _makingOffer = true;

        _notifySafely();

        try {
          final RTCSessionDescription offer =
          await connection.createOffer(
            <String, dynamic>{
              'offerToReceiveAudio':
              true,
              'offerToReceiveVideo':
              true,
              'iceRestart':
              iceRestart,
            },
          );

          if (!_isCurrentConnection(
            connection,
            generation,
          )) {
            return null;
          }

          await connection
              .setLocalDescription(
            offer,
          );

          if (!_isCurrentConnection(
            connection,
            generation,
          )) {
            return null;
          }

          _renegotiationNeeded = false;

          return offer;
        } catch (error, stackTrace) {
          _reportError(
            'offer',
            error,
            stackTrace,
          );

          return null;
        } finally {
          if (_isCurrentConnection(
            connection,
            generation,
          )) {
            _makingOffer = false;

            _notifySafely();
          }
        }
      },
    );
  }

  // ===========================================================
  // CREATE ANSWER
  // ===========================================================

  Future<RTCSessionDescription?>
  createAnswer() {
    final RTCPeerConnection? connection =
        _peerConnection;

    if (_disposed ||
        connection == null) {
      return Future<
          RTCSessionDescription?>.value(
        null,
      );
    }

    final int generation =
        _connectionGeneration;

    return _runSerializedSdp<
        RTCSessionDescription?>(
          () async {
        if (!_isCurrentConnection(
          connection,
          generation,
        )) {
          return null;
        }

        try {
          final RTCSessionDescription answer =
          await connection.createAnswer(
            <String, dynamic>{
              'offerToReceiveAudio':
              true,
              'offerToReceiveVideo':
              true,
            },
          );

          if (!_isCurrentConnection(
            connection,
            generation,
          )) {
            return null;
          }

          await connection
              .setLocalDescription(
            answer,
          );

          if (!_isCurrentConnection(
            connection,
            generation,
          )) {
            return null;
          }

          _renegotiationNeeded = false;

          return answer;
        } catch (error, stackTrace) {
          _reportError(
            'answer',
            error,
            stackTrace,
          );

          return null;
        }
      },
    );
  }

  // ===========================================================
  // REMOTE DESCRIPTION
  // ===========================================================

  Future<void> setRemoteDescription(
      String type,
      String sdp,
      ) {
    final RTCPeerConnection? connection =
        _peerConnection;

    final String normalizedType =
    type.trim().toLowerCase();

    final String normalizedSdp =
    sdp.trim();

    if (_disposed ||
        connection == null ||
        normalizedSdp.isEmpty) {
      return Future<void>.value();
    }

    if (normalizedType != _offerType &&
        normalizedType != _answerType &&
        normalizedType !=
            _provisionalAnswerType) {
      return Future<void>.error(
        ArgumentError.value(
          type,
          'type',
          'Unsupported WebRTC '
              'session description type.',
        ),
      );
    }

    if (normalizedSdp.length > 600000) {
      return Future<void>.error(
        ArgumentError(
          'WebRTC session description '
              'is too large.',
        ),
      );
    }

    final int generation =
        _connectionGeneration;

    return _runSerializedSdp<void>(
          () async {
        if (!_isCurrentConnection(
          connection,
          generation,
        )) {
          return;
        }

        final RTCSessionDescription?
        currentRemote =
        await connection
            .getRemoteDescription();

        if (!_isCurrentConnection(
          connection,
          generation,
        )) {
          return;
        }

        if (currentRemote != null &&
            currentRemote.type
                ?.trim()
                .toLowerCase() ==
                normalizedType &&
            currentRemote.sdp?.trim() ==
                normalizedSdp) {
          return;
        }

        final RTCSignalingState? state =
            connection.signalingState;

        if (state ==
            RTCSignalingState
                .RTCSignalingStateClosed) {
          throw StateError(
            'PeerConnection is closed.',
          );
        }

        final bool offerCollision =
            normalizedType == _offerType &&
                state != null &&
                state !=
                    RTCSignalingState
                        .RTCSignalingStateStable;

        if (offerCollision) {
          final bool? callerRole =
              _isCallerRole;

          if (callerRole == true) {
            _ignoreOffer = true;

            _debugPrint(
              'colliding remote offer '
                  'ignored by caller side.',
            );

            _notifySafely();

            return;
          }

          if (callerRole == null) {
            throw StateError(
              'Negotiation role must be '
                  'configured before resolving '
                  'an SDP offer collision.',
            );
          }

          if (state ==
              RTCSignalingState
                  .RTCSignalingStateHaveLocalOffer ||
              state ==
                  RTCSignalingState
                      .RTCSignalingStateHaveLocalPrAnswer) {
            await connection
                .setLocalDescription(
              RTCSessionDescription(
                '',
                _rollbackType,
              ),
            );

            if (!_isCurrentConnection(
              connection,
              generation,
            )) {
              return;
            }
          } else {
            throw StateError(
              'Cannot resolve remote offer '
                  'collision from signaling '
                  'state $state.',
            );
          }
        }

        _ignoreOffer = false;

        await connection
            .setRemoteDescription(
          RTCSessionDescription(
            normalizedSdp,
            normalizedType,
          ),
        );

        if (!_isCurrentConnection(
          connection,
          generation,
        )) {
          return;
        }

        if (normalizedType ==
            _answerType) {
          _renegotiationNeeded = false;
        }

        _notifySafely();
      },
    );
  }

  // ===========================================================
  // ICE CANDIDATE COMPATIBILITY
  // ===========================================================

  Future<void> addCandidate(
      RTCIceCandidate candidate,
      ) async {
    final RTCPeerConnection? connection =
        _peerConnection;

    if (_disposed ||
        connection == null) {
      return;
    }

    final String raw =
        candidate.candidate?.trim() ?? '';

    if (raw.isEmpty) {
      return;
    }

    final int generation =
        _connectionGeneration;

    if (!_isCurrentConnection(
      connection,
      generation,
    )) {
      return;
    }

    await connection.addCandidate(
      candidate,
    );
  }

  // ===========================================================
  // LOCAL TRACK ATTACHMENT
  //
  // MediaStreamTrack.id is nullable in flutter_webrtc.
  // Never force nullable id into non-nullable String.
  // ===========================================================

  Future<void> addLocalStream(
      MediaStream stream,
      ) async {
    final RTCPeerConnection? connection =
        _peerConnection;

    if (_disposed ||
        connection == null) {
      return;
    }

    final int generation =
        _connectionGeneration;

    final List<RTCRtpSender> senders =
    await connection.getSenders();

    if (!_isCurrentConnection(
      connection,
      generation,
    )) {
      return;
    }

    final Set<String> existingTrackIds =
    senders
        .map(
          (RTCRtpSender sender) =>
          sender.track?.id?.trim(),
    )
        .whereType<String>()
        .where(
          (String id) => id.isNotEmpty,
    )
        .toSet();

    for (final MediaStreamTrack track
    in stream.getTracks()) {
      if (!_isCurrentConnection(
        connection,
        generation,
      )) {
        return;
      }

      final String? trackId =
      track.id?.trim();

      final bool alreadyAttached =
      senders.any(
            (RTCRtpSender sender) {
          final MediaStreamTrack? senderTrack =
              sender.track;

          if (identical(
            senderTrack,
            track,
          )) {
            return true;
          }

          final String? senderTrackId =
          senderTrack?.id?.trim();

          return trackId != null &&
              trackId.isNotEmpty &&
              senderTrackId != null &&
              senderTrackId.isNotEmpty &&
              senderTrackId == trackId;
        },
      );

      if (alreadyAttached ||
          (trackId != null &&
              trackId.isNotEmpty &&
              existingTrackIds.contains(
                trackId,
              ))) {
        continue;
      }

      await connection.addTrack(
        track,
        stream,
      );

      if (!_isCurrentConnection(
        connection,
        generation,
      )) {
        return;
      }

      if (trackId != null &&
          trackId.isNotEmpty) {
        existingTrackIds.add(
          trackId,
        );
      }
    }
  }

  // ===========================================================
  // ICE RESTART
  // ===========================================================

  Future<void> restartIce() {
    final RTCPeerConnection? connection =
        _peerConnection;

    if (_disposed ||
        connection == null) {
      return Future<void>.value();
    }

    final int generation =
        _connectionGeneration;

    return _runSerializedSdp<void>(
          () async {
        if (!_isCurrentConnection(
          connection,
          generation,
        )) {
          return;
        }

        await connection.restartIce();

        if (!_isCurrentConnection(
          connection,
          generation,
        )) {
          return;
        }

        _renegotiationNeeded = true;

        _notifySafely();
      },
    );
  }

  // ===========================================================
  // SERIALIZED SDP OPERATIONS
  // ===========================================================

  Future<T> _runSerializedSdp<T>(
      Future<T> Function() operation,
      ) {
    final Completer<T> completer =
    Completer<T>();

    final Future<void> next =
    _sdpMutationTail.then<void>(
          (_) async {
        try {
          final T result =
          await operation();

          if (!completer.isCompleted) {
            completer.complete(
              result,
            );
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

    _sdpMutationTail = next;

    return completer.future;
  }

  // ===========================================================
  // SESSION VALIDATION
  // ===========================================================

  bool _isGenerationCurrent(
      int generation,
      ) {
    return !_disposed &&
        generation ==
            _connectionGeneration;
  }

  bool _isCurrentConnection(
      RTCPeerConnection connection,
      int generation,
      ) {
    return !_disposed &&
        generation ==
            _connectionGeneration &&
        identical(
          _peerConnection,
          connection,
        );
  }

  // ===========================================================
  // CONNECTION DISPOSAL
  // ===========================================================

  Future<void> disposeConnection() async {
    if (_disposed) {
      return;
    }

    _connectionGeneration++;

    _activeConnectionInitialization =
    null;

    _activeDataChannelCreation =
    null;

    final RTCDataChannel? channel =
        _dataChannel;

    final RTCPeerConnection? connection =
        _peerConnection;

    _dataChannel = null;

    _peerConnection = null;

    _initialized = false;

    _makingOffer = false;

    _ignoreOffer = false;

    _renegotiationNeeded = false;

    _isCallerRole = null;

    _sdpMutationTail =
    Future<void>.value();

    if (connection != null) {
      _detachOwnedCallbacks(
        connection,
      );
    }

    if (channel != null) {
      try {
        await channel.close();
      } catch (error, stackTrace) {
        _reportError(
          'data channel close',
          error,
          stackTrace,
        );
      }
    }

    if (connection != null) {
      await _closeNativeConnection(
        connection,
      );
    }

    _notifySafely();
  }

  void _detachOwnedCallbacks(
      RTCPeerConnection connection,
      ) {
    // IceManager owns onIceCandidate.
    // Never clear it here.

    try {
      connection.onTrack = null;
    } catch (_) {}

    try {
      connection.onIceConnectionState =
      null;
    } catch (_) {}

    try {
      connection.onConnectionState =
      null;
    } catch (_) {}

    try {
      connection.onSignalingState =
      null;
    } catch (_) {}

    try {
      connection.onIceGatheringState =
      null;
    } catch (_) {}

    try {
      connection.onRenegotiationNeeded =
      null;
    } catch (_) {}
  }

  Future<void> _closeNativeConnection(
      RTCPeerConnection connection,
      ) async {
    _detachOwnedCallbacks(
      connection,
    );

    try {
      await connection.close();
    } catch (error, stackTrace) {
      _reportError(
        'PeerConnection close',
        error,
        stackTrace,
      );
    }

    try {
      await connection.dispose();
    } catch (error, stackTrace) {
      _reportError(
        'PeerConnection dispose',
        error,
        stackTrace,
      );
    }
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

  void _debugPrint(
      String message,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[PeerConnectionManager] '
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
          '[PeerConnectionManager/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[PeerConnectionManager/$source]',
        stackTrace:
        stackTrace,
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

    _connectionGeneration++;

    _activeConnectionInitialization =
    null;

    _activeDataChannelCreation =
    null;

    final RTCDataChannel? channel =
        _dataChannel;

    final RTCPeerConnection? connection =
        _peerConnection;

    _dataChannel = null;

    _peerConnection = null;

    _initialized = false;

    _makingOffer = false;

    _ignoreOffer = false;

    _renegotiationNeeded = false;

    _isCallerRole = null;

    _sdpMutationTail =
    Future<void>.value();

    if (connection != null) {
      _detachOwnedCallbacks(
        connection,
      );
    }

    if (channel != null) {
      unawaited(
        channel.close().catchError(
              (Object error) {
            _debugPrint(
              'data channel disposal error: '
                  '$error',
            );
          },
        ),
      );
    }

    if (connection != null) {
      unawaited(
        _closeNativeConnection(
          connection,
        ),
      );
    }

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 11 CORRECTED FINAL GUARANTEES:
//
// ✓ MediaStreamTrack.id nullable contract handled correctly.
// ✓ No String? -> String assignment error.
// ✓ Null/empty track IDs handled safely.
// ✓ Duplicate tracks still prevented.
// ✓ Object-identity dedupe preserved for nullable IDs.
// ✓ Valid provisional-answer SDP type preserved.
// ✓ IDE spelling inspection avoided without runtime change.
// ✓ IceManager remains sole onIceCandidate owner.
// ✓ Existing public API preserved.
// ✓ PeerConnection generation guards preserved.
// ✓ SDP serialization preserved.
// ✓ Caller-wins glare policy preserved.
// ✓ Polite receiver rollback preserved.
// ✓ Native restartIce() preserved.
// ✓ No hidden unsignaled restart offer.
// ✓ Media tracks are not stopped here.
// ✓ Signaling ownership is not duplicated.
//
// STATUS:
// PEER CONNECTION MANAGER — CORRECTED FINAL.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 12
// lib/services/managers/media_manager.dart
// ===============================================================