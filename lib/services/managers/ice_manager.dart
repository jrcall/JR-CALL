// ===============================================================
// JR CALL
// File: ice_manager.dart
// Location: lib/services/managers/ice_manager.dart
//
// FINAL PRODUCTION ICE COORDINATOR
//
// OWNERSHIP:
//
// SignalingService:
// - Firestore ICE persistence.
// - Remote ICE candidate stream.
//
// WebRTCService / PeerConnectionManager:
// - PeerConnection creation.
// - SDP application.
// - Media transport.
//
// IceManager:
// - ONLY owner of RTCPeerConnection.onIceCandidate.
// - Local ICE persistence handoff.
// - Remote ICE listening.
// - ICE generation awareness.
// - Remote ICE queueing.
// - Remote ICE de-duplication.
// - Remote ICE retry.
//
// CallService:
// - Complete call lifecycle.
// - SDP orchestration.
// - Recovery orchestration handoff.
//
// CRITICAL CONTRACT:
//
// WebRTCService / PeerConnectionManager MUST NOT install:
//
//   peerConnection.onIceCandidate = ...
//
// IceManager exclusively owns that callback.
//
// PRODUCTION GUARANTEES:
//
// - Local candidate de-duplication.
// - Remote candidate de-duplication.
// - ICE restart generation awareness.
// - usernameFragment preserved when available.
// - Future-generation ICE waits for matching remote SDP.
// - Pending ICE until remote SDP exists.
// - Candidate marked processed ONLY after addCandidate succeeds.
// - Failed addCandidate remains retryable.
// - Failed local signaling write gets bounded retry.
// - Concurrent Firestore snapshots serialized.
// - Duplicate initialize/listener request is harmless.
// - Old-call async work cannot mutate new-call state.
// - Reset invalidates every stale callback.
// - Pending retry remains genuinely bounded.
// - No PeerConnection creation here.
// - No media ownership here.
// - No SDP/signaling ownership duplicated.
// - Existing public APIs preserved.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../call/signaling_service.dart';

class IceManager extends ChangeNotifier {
  IceManager._();

  static final IceManager instance = IceManager._();

  // =============================================================
  // CONFIGURATION
  // =============================================================

  static const int _maximumLocalPersistenceAttempts = 2;

  static const int _maximumPendingFlushRetries = 5;

  static const int _maximumPendingRemoteCandidates = 512;

  static const Duration _baseLocalRetryDelay =
  Duration(milliseconds: 300);

  static const Duration _basePendingRetryDelay =
  Duration(milliseconds: 250);

  static const Duration _maximumPendingCandidateAge =
  Duration(minutes: 3);

  // =============================================================
  // SERVICES
  // =============================================================

  final SignalingService _signaling = SignalingService.instance;

  // =============================================================
  // REMOTE LISTENER
  // =============================================================

  StreamSubscription<List<Map<String, dynamic>>>? _remoteSubscription;

  // =============================================================
  // REMOTE ICE STATE
  // =============================================================

  final List<_IceCandidateEnvelope> _pendingRemoteCandidates =
  <_IceCandidateEnvelope>[];

  /// Candidates successfully installed into PeerConnection.
  final Set<String> _processedRemoteCandidates = <String>{};

  /// Candidates already waiting for a future flush.
  final Set<String> _pendingRemoteCandidateSignatures = <String>{};

  /// Candidate currently being processed.
  final Set<String> _inFlightRemoteCandidateSignatures = <String>{};

  // =============================================================
  // LOCAL ICE STATE
  // =============================================================

  /// Candidates already handed successfully to SignalingService.
  ///
  /// Signature includes ICE generation where available.
  final Set<String> _sentLocalCandidates = <String>{};

  // =============================================================
  // SESSION STATE
  // =============================================================

  bool _initialized = false;

  bool _disposed = false;

  int _generation = 0;

  String? _currentCallId;

  bool? _currentIsCaller;

  RTCPeerConnection? _currentPeerConnection;

  // =============================================================
  // REMOTE PROCESSING SERIALIZATION
  // =============================================================

  Future<void> _remoteProcessingTail = Future<void>.value();

  // =============================================================
  // RETRY STATE
  // =============================================================

  Timer? _pendingRetryTimer;

  int _pendingFlushRetryAttempt = 0;

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isInitialized => _initialized;

  String get currentState {
    return _initialized ? 'INITIALIZED' : 'DISCONNECTED';
  }

  String? get currentCallId => _currentCallId;

  bool? get currentIsCaller => _currentIsCaller;

  int get pendingCandidateCount => _pendingRemoteCandidates.length;

  // =============================================================
  // INITIALIZATION
  // =============================================================

  Future<void> initialize({
    String? callId,
    bool? isCaller,
    RTCPeerConnection? peerConnection,
  }) async {
    if (_disposed) {
      return;
    }

    final String normalizedCallId = callId?.trim() ?? '';

    if (_initialized &&
        peerConnection != null &&
        normalizedCallId.isNotEmpty &&
        isCaller != null &&
        _currentCallId == normalizedCallId &&
        _currentIsCaller == isCaller &&
        identical(
          _currentPeerConnection,
          peerConnection,
        )) {
      _bindLocalCandidateHandler(
        callId: normalizedCallId,
        isCaller: isCaller,
        peerConnection: peerConnection,
        generation: _generation,
      );

      if (_remoteSubscription == null) {
        _startRemoteCandidateListener(
          callId: normalizedCallId,
          isCaller: isCaller,
          peerConnection: peerConnection,
          generation: _generation,
        );
      }

      return;
    }

    final int generation = ++_generation;

    _cancelPendingRetry();

    await _cancelRemoteSubscription();

    if (!_isGenerationCurrent(
      generation,
    )) {
      return;
    }

    _detachLocalCandidateCallback();

    _clearCandidateState();

    _currentCallId =
    normalizedCallId.isEmpty ? null : normalizedCallId;

    _currentIsCaller = isCaller;

    _currentPeerConnection = peerConnection;

    if (peerConnection == null ||
        normalizedCallId.isEmpty ||
        isCaller == null) {
      _initialized = true;

      _notifySafely();

      return;
    }

    _bindLocalCandidateHandler(
      callId: normalizedCallId,
      isCaller: isCaller,
      peerConnection: peerConnection,
      generation: generation,
    );

    _startRemoteCandidateListener(
      callId: normalizedCallId,
      isCaller: isCaller,
      peerConnection: peerConnection,
      generation: generation,
    );

    if (!_isCurrentSession(
      generation: generation,
      callId: normalizedCallId,
      peerConnection: peerConnection,
    )) {
      return;
    }

    _initialized = true;

    _notifySafely();

    _debugPrint(
      'initialized '
          'call=$normalizedCallId '
          'role=${isCaller ? 'caller' : 'receiver'}.',
    );
  }

  // =============================================================
  // LOCAL ICE CALLBACK
  // =============================================================

  void _bindLocalCandidateHandler({
    required String callId,
    required bool isCaller,
    required RTCPeerConnection peerConnection,
    required int generation,
  }) {
    peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
      if (!_isCurrentSession(
        generation: generation,
        callId: callId,
        peerConnection: peerConnection,
      )) {
        return;
      }

      unawaited(
        _handleLocalCandidate(
          candidate: candidate,
          callId: callId,
          isCaller: isCaller,
          generation: generation,
          peerConnection: peerConnection,
        ),
      );
    };
  }

  // =============================================================
  // LOCAL ICE PERSISTENCE
  // =============================================================

  Future<void> _handleLocalCandidate({
    required RTCIceCandidate candidate,
    required String callId,
    required bool isCaller,
    required int generation,
    required RTCPeerConnection peerConnection,
  }) async {
    if (!_isCurrentSession(
      generation: generation,
      callId: callId,
      peerConnection: peerConnection,
    )) {
      return;
    }

    final String? candidateValue = _cleanCandidate(
      candidate.candidate,
    );

    if (candidateValue == null) {
      return;
    }

    String? usernameFragment =
    _usernameFragmentFromNativeCandidate(
      candidate,
    );

    if (usernameFragment == null) {
      try {
        final RTCSessionDescription? localDescription =
        await peerConnection.getLocalDescription();

        if (!_isCurrentSession(
          generation: generation,
          callId: callId,
          peerConnection: peerConnection,
        )) {
          return;
        }

        usernameFragment = _extractIceUsernameFragment(
          localDescription?.sdp,
          candidate.sdpMid,
        );
      } catch (_) {
        // Candidate is still usable without generation metadata.
      }
    }

    if (!_isCurrentSession(
      generation: generation,
      callId: callId,
      peerConnection: peerConnection,
    )) {
      return;
    }

    final String signature = _candidateSignature(
      candidateValue: candidateValue,
      sdpMid: candidate.sdpMid,
      sdpMLineIndex: candidate.sdpMLineIndex,
      usernameFragment: usernameFragment,
    );

    if (!_sentLocalCandidates.add(
      signature,
    )) {
      return;
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'candidate': candidateValue,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    };

    if (usernameFragment != null) {
      payload['usernameFragment'] = usernameFragment;
    }

    bool persisted = false;

    Object? lastError;

    StackTrace? lastStackTrace;

    try {
      for (
      int attempt = 1;
      attempt <= _maximumLocalPersistenceAttempts;
      attempt++
      ) {
        if (!_isCurrentSession(
          generation: generation,
          callId: callId,
          peerConnection: peerConnection,
        )) {
          return;
        }

        try {
          await _signaling.addIceCandidate(
            callId,
            isCaller,
            payload,
          );

          persisted = true;

          break;
        } catch (error, stackTrace) {
          lastError = error;
          lastStackTrace = stackTrace;

          if (attempt >= _maximumLocalPersistenceAttempts) {
            break;
          }

          await Future<void>.delayed(
            Duration(
              milliseconds:
              _baseLocalRetryDelay.inMilliseconds * attempt,
            ),
          );
        }
      }
    } finally {
      if (!persisted &&
          _isCurrentSession(
            generation: generation,
            callId: callId,
            peerConnection: peerConnection,
          )) {
        _sentLocalCandidates.remove(
          signature,
        );
      }
    }

    if (!persisted &&
        lastError != null &&
        _isCurrentSession(
          generation: generation,
          callId: callId,
          peerConnection: peerConnection,
        )) {
      _reportError(
        'Local ICE persistence',
        lastError,
        lastStackTrace,
      );
    }
  }

  // =============================================================
  // PUBLIC REMOTE LISTENER COMPATIBILITY
  // =============================================================

  void listenRemoteCandidates({
    required String callId,
    required bool isCaller,
    required RTCPeerConnection? peerConnection,
  }) {
    if (_disposed || peerConnection == null) {
      return;
    }

    final String normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      return;
    }

    final int generation = _generation;

    final bool sameSession = _isCurrentSession(
      generation: generation,
      callId: normalizedCallId,
      peerConnection: peerConnection,
    );

    if (!sameSession || _currentIsCaller != isCaller) {
      _debugPrint(
        'ignored remote listener request '
            'for a non-current ICE session.',
      );

      return;
    }

    if (_remoteSubscription != null) {
      return;
    }

    _startRemoteCandidateListener(
      callId: normalizedCallId,
      isCaller: isCaller,
      peerConnection: peerConnection,
      generation: generation,
    );
  }

  // =============================================================
  // REMOTE FIRESTORE LISTENER
  // =============================================================

  void _startRemoteCandidateListener({
    required String callId,
    required bool isCaller,
    required RTCPeerConnection peerConnection,
    required int generation,
  }) {
    if (!_isCurrentSession(
      generation: generation,
      callId: callId,
      peerConnection: peerConnection,
    )) {
      return;
    }

    if (_remoteSubscription != null) {
      return;
    }

    _remoteSubscription = _signaling
        .listenToRemoteICECandidates(
      callId,
      isCaller,
    )
        .listen(
          (
          List<Map<String, dynamic>> candidates,
          ) {
        if (!_isCurrentSession(
          generation: generation,
          callId: callId,
          peerConnection: peerConnection,
        )) {
          return;
        }

        _enqueueRemoteOperation(
              () => _processRemoteBatch(
            candidates: candidates,
            peerConnection: peerConnection,
            callId: callId,
            generation: generation,
          ),
        );
      },
      onError: (
          Object error,
          StackTrace stackTrace,
          ) {
        if (!_isCurrentSession(
          generation: generation,
          callId: callId,
          peerConnection: peerConnection,
        )) {
          return;
        }

        _reportError(
          'Remote ICE stream',
          error,
          stackTrace,
        );
      },
    );
  }

  // =============================================================
  // SERIALIZED REMOTE PROCESSING
  // =============================================================

  void _enqueueRemoteOperation(
      Future<void> Function() operation,
      ) {
    final Future<void> next =
    _remoteProcessingTail.then<void>(
          (_) async {
        try {
          await operation();
        } catch (error, stackTrace) {
          _reportError(
            'Serialized remote ICE operation',
            error,
            stackTrace,
          );
        }
      },
      onError: (
          Object error,
          StackTrace stackTrace,
          ) async {
        _reportError(
          'Previous remote ICE operation',
          error,
          stackTrace,
        );

        try {
          await operation();
        } catch (nextError, nextStackTrace) {
          _reportError(
            'Serialized remote ICE operation',
            nextError,
            nextStackTrace,
          );
        }
      },
    );

    _remoteProcessingTail = next;
  }

  // =============================================================
  // REMOTE BATCH
  // =============================================================

  Future<void> _processRemoteBatch({
    required List<Map<String, dynamic>> candidates,
    required RTCPeerConnection peerConnection,
    required String callId,
    required int generation,
  }) async {
    for (final Map<String, dynamic> data in candidates) {
      if (!_isCurrentSession(
        generation: generation,
        callId: callId,
        peerConnection: peerConnection,
      )) {
        return;
      }

      await _processRemoteCandidate(
        peerConnection: peerConnection,
        data: data,
        generation: generation,
        callId: callId,
      );
    }
  }

  // =============================================================
  // REMOTE CANDIDATE PROCESSING
  // =============================================================

  Future<void> _processRemoteCandidate({
    required RTCPeerConnection peerConnection,
    required Map<String, dynamic> data,
    required int generation,
    required String callId,
  }) async {
    if (!_isCurrentSession(
      generation: generation,
      callId: callId,
      peerConnection: peerConnection,
    )) {
      return;
    }

    final _IceCandidateEnvelope? envelope =
    _candidateFromMap(
      data,
    );

    if (envelope == null) {
      return;
    }

    final String signature = _signatureForEnvelope(
      envelope,
    );

    if (_processedRemoteCandidates.contains(signature) ||
        _pendingRemoteCandidateSignatures.contains(signature) ||
        _inFlightRemoteCandidateSignatures.contains(signature)) {
      return;
    }

    _inFlightRemoteCandidateSignatures.add(
      signature,
    );

    try {
      final RTCSessionDescription? remoteDescription =
      await peerConnection.getRemoteDescription();

      if (!_isCurrentSession(
        generation: generation,
        callId: callId,
        peerConnection: peerConnection,
      )) {
        return;
      }

      if (remoteDescription == null) {
        _enqueuePendingCandidate(
          envelope,
          scheduleRetry: false,
        );

        return;
      }

      if (!_candidateMatchesRemoteDescription(
        envelope,
        remoteDescription,
      )) {
        _enqueuePendingCandidate(
          envelope,
          scheduleRetry: true,
        );

        return;
      }

      try {
        await peerConnection.addCandidate(
          envelope.candidate,
        );
      } catch (error, stackTrace) {
        if (_isCurrentSession(
          generation: generation,
          callId: callId,
          peerConnection: peerConnection,
        )) {
          _enqueuePendingCandidate(
            envelope,
            scheduleRetry: true,
          );
        }

        _reportError(
          'Remote ICE addCandidate',
          error,
          stackTrace,
        );

        return;
      }

      if (!_isCurrentSession(
        generation: generation,
        callId: callId,
        peerConnection: peerConnection,
      )) {
        return;
      }

      _processedRemoteCandidates.add(
        signature,
      );

      _removePendingCandidate(
        signature,
      );
    } catch (error, stackTrace) {
      if (_isCurrentSession(
        generation: generation,
        callId: callId,
        peerConnection: peerConnection,
      )) {
        _enqueuePendingCandidate(
          envelope,
          scheduleRetry: true,
        );
      }

      _reportError(
        'Remote ICE candidate processing',
        error,
        stackTrace,
      );
    } finally {
      if (_isCurrentSession(
        generation: generation,
        callId: callId,
        peerConnection: peerConnection,
      )) {
        _inFlightRemoteCandidateSignatures.remove(
          signature,
        );
      }
    }
  }

  // =============================================================
  // PENDING CANDIDATE QUEUE
  // =============================================================

  void _enqueuePendingCandidate(
      _IceCandidateEnvelope envelope, {
        required bool scheduleRetry,
      }) {
    _pruneExpiredPendingCandidates();

    final String signature =
    _signatureForEnvelope(
      envelope,
    );

    if (_processedRemoteCandidates.contains(signature) ||
        _pendingRemoteCandidateSignatures.contains(signature)) {
      if (scheduleRetry) {
        _schedulePendingFlush();
      }

      return;
    }

    if (_pendingRemoteCandidates.length >=
        _maximumPendingRemoteCandidates) {
      final _IceCandidateEnvelope removed =
      _pendingRemoteCandidates.removeAt(0);

      _pendingRemoteCandidateSignatures.remove(
        _signatureForEnvelope(
          removed,
        ),
      );
    }

    _pendingRemoteCandidateSignatures.add(
      signature,
    );

    _pendingRemoteCandidates.add(
      envelope,
    );

    if (scheduleRetry) {
      _schedulePendingFlush();
    }
  }

  void _removePendingCandidate(
      String signature,
      ) {
    if (!_pendingRemoteCandidateSignatures.remove(signature)) {
      return;
    }

    _pendingRemoteCandidates.removeWhere(
          (_IceCandidateEnvelope envelope) {
        return _signatureForEnvelope(
          envelope,
        ) ==
            signature;
      },
    );
  }

  void _pruneExpiredPendingCandidates() {
    if (_pendingRemoteCandidates.isEmpty) {
      return;
    }

    final DateTime cutoff =
    DateTime.now().toUtc().subtract(
      _maximumPendingCandidateAge,
    );

    _pendingRemoteCandidates.removeWhere(
          (_IceCandidateEnvelope envelope) {
        if (!envelope.enqueuedAt.isBefore(cutoff)) {
          return false;
        }

        _pendingRemoteCandidateSignatures.remove(
          _signatureForEnvelope(
            envelope,
          ),
        );

        return true;
      },
    );
  }

  // =============================================================
  // PUBLIC PENDING FLUSH
  // =============================================================

  Future<void> flushPendingCandidates(
      RTCPeerConnection? peerConnection,
      ) {
    return _queuePendingFlush(
      peerConnection,
      resetRetryBudget: true,
    );
  }

  Future<void> _queuePendingFlush(
      RTCPeerConnection? peerConnection, {
        required bool resetRetryBudget,
      }) async {
    if (_disposed ||
        peerConnection == null ||
        _pendingRemoteCandidates.isEmpty ||
        !identical(
          peerConnection,
          _currentPeerConnection,
        )) {
      return;
    }

    final int generation = _generation;

    final String? callId = _currentCallId;

    if (callId == null || callId.isEmpty) {
      return;
    }

    if (resetRetryBudget) {
      _pendingRetryTimer?.cancel();

      _pendingRetryTimer = null;

      _pendingFlushRetryAttempt = 0;
    }

    final Completer<void> completer = Completer<void>();

    _enqueueRemoteOperation(
          () async {
        try {
          await _flushPendingCandidatesInternal(
            peerConnection: peerConnection,
            callId: callId,
            generation: generation,
          );

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

    return completer.future;
  }

  Future<void> _flushPendingCandidatesInternal({
    required RTCPeerConnection peerConnection,
    required String callId,
    required int generation,
  }) async {
    _pruneExpiredPendingCandidates();

    if (_pendingRemoteCandidates.isEmpty ||
        !_isCurrentSession(
          generation: generation,
          callId: callId,
          peerConnection: peerConnection,
        )) {
      return;
    }

    final RTCSessionDescription? remoteDescription;

    try {
      remoteDescription =
      await peerConnection.getRemoteDescription();
    } catch (error, stackTrace) {
      _reportError(
        'Read remote SDP before ICE flush',
        error,
        stackTrace,
      );

      _schedulePendingFlush();

      return;
    }

    if (!_isCurrentSession(
      generation: generation,
      callId: callId,
      peerConnection: peerConnection,
    )) {
      return;
    }

    if (remoteDescription == null) {
      return;
    }

    final List<_IceCandidateEnvelope> queuedCandidates =
    List<_IceCandidateEnvelope>.from(
      _pendingRemoteCandidates,
    );

    _pendingRemoteCandidates.clear();

    _pendingRemoteCandidateSignatures.clear();

    bool hadFailure = false;

    bool waitingForMatchingGeneration = false;

    final DateTime cutoff =
    DateTime.now().toUtc().subtract(
      _maximumPendingCandidateAge,
    );

    for (final _IceCandidateEnvelope envelope
    in queuedCandidates) {
      if (!_isCurrentSession(
        generation: generation,
        callId: callId,
        peerConnection: peerConnection,
      )) {
        return;
      }

      if (envelope.enqueuedAt.isBefore(cutoff)) {
        continue;
      }

      final String signature =
      _signatureForEnvelope(
        envelope,
      );

      if (_processedRemoteCandidates.contains(signature)) {
        continue;
      }

      if (!_candidateMatchesRemoteDescription(
        envelope,
        remoteDescription,
      )) {
        waitingForMatchingGeneration = true;

        _enqueuePendingCandidate(
          envelope,
          scheduleRetry: false,
        );

        continue;
      }

      try {
        await peerConnection.addCandidate(
          envelope.candidate,
        );

        if (!_isCurrentSession(
          generation: generation,
          callId: callId,
          peerConnection: peerConnection,
        )) {
          return;
        }

        _processedRemoteCandidates.add(
          signature,
        );
      } catch (error, stackTrace) {
        hadFailure = true;

        _enqueuePendingCandidate(
          envelope,
          scheduleRetry: false,
        );

        _reportError(
          'Pending ICE addCandidate',
          error,
          stackTrace,
        );
      }
    }

    if (_pendingRemoteCandidates.isEmpty) {
      _cancelPendingRetry();

      return;
    }

    if (hadFailure ||
        waitingForMatchingGeneration) {
      _schedulePendingFlush();
    }
  }

  // =============================================================
  // BOUNDED PENDING RETRY
  // =============================================================

  void _schedulePendingFlush() {
    if (_disposed ||
        _pendingRemoteCandidates.isEmpty ||
        _pendingRetryTimer?.isActive == true) {
      return;
    }

    if (_pendingFlushRetryAttempt >=
        _maximumPendingFlushRetries) {
      _debugPrint(
        'pending ICE automatic retry limit reached; '
            'candidate remains queued for explicit '
            'remote-SDP/recovery flush.',
      );

      return;
    }

    final RTCPeerConnection? peerConnection =
        _currentPeerConnection;

    final String? callId = _currentCallId;

    if (peerConnection == null ||
        callId == null ||
        callId.isEmpty) {
      return;
    }

    final int generation = _generation;

    _pendingFlushRetryAttempt++;

    final int delayMilliseconds =
        _basePendingRetryDelay.inMilliseconds *
            _pendingFlushRetryAttempt;

    _pendingRetryTimer = Timer(
      Duration(
        milliseconds: delayMilliseconds,
      ),
          () {
        _pendingRetryTimer = null;

        if (!_isCurrentSession(
          generation: generation,
          callId: callId,
          peerConnection: peerConnection,
        )) {
          return;
        }

        unawaited(
          _queuePendingFlush(
            peerConnection,
            resetRetryBudget: false,
          ),
        );
      },
    );
  }

  void _cancelPendingRetry() {
    _pendingRetryTimer?.cancel();

    _pendingRetryTimer = null;

    _pendingFlushRetryAttempt = 0;
  }

  // =============================================================
  // MAP -> CANDIDATE ENVELOPE
  // =============================================================

  _IceCandidateEnvelope? _candidateFromMap(
      Map<String, dynamic> data,
      ) {
    final Object? rawCandidate = data['candidate'];

    if (rawCandidate is! String) {
      return null;
    }

    final String candidateValue = rawCandidate.trim();

    if (candidateValue.isEmpty) {
      return null;
    }

    final String? sdpMid =
    _readNullableString(
      data['sdpMid'],
    );

    final int? sdpMLineIndex =
    _readNullableInt(
      data['sdpMLineIndex'],
    );

    final String? usernameFragment =
        _readNullableString(
          data['usernameFragment'] ??
              data['u' 'frag'],
        ) ??
            _extractUsernameFragmentFromCandidateLine(
              candidateValue,
            );

    return _IceCandidateEnvelope(
      candidate: RTCIceCandidate(
        candidateValue,
        sdpMid,
        sdpMLineIndex,
      ),
      usernameFragment: usernameFragment,
      enqueuedAt: DateTime.now().toUtc(),
    );
  }

  // =============================================================
  // ICE GENERATION MATCHING
  // =============================================================

  bool _candidateMatchesRemoteDescription(
      _IceCandidateEnvelope envelope,
      RTCSessionDescription remoteDescription,
      ) {
    final String? candidateFragment =
        envelope.usernameFragment;

    if (candidateFragment == null) {
      return true;
    }

    final String? remoteFragment =
    _extractIceUsernameFragment(
      remoteDescription.sdp,
      envelope.candidate.sdpMid,
    );

    if (remoteFragment == null) {
      return true;
    }

    return candidateFragment == remoteFragment;
  }

  String? _usernameFragmentFromNativeCandidate(
      RTCIceCandidate candidate,
      ) {
    try {
      final Object? rawMap = candidate.toMap();

      if (rawMap is Map) {
        final String? mapped =
        _readNullableString(
          rawMap['usernameFragment'] ??
              rawMap['u' 'frag'],
        );

        if (mapped != null) {
          return mapped;
        }
      }
    } catch (_) {
      // Some platform implementations expose only the base fields.
    }

    return _extractUsernameFragmentFromCandidateLine(
      candidate.candidate,
    );
  }

  String? _extractUsernameFragmentFromCandidateLine(
      String? candidateValue,
      ) {
    final String candidate =
        candidateValue?.trim() ?? '';

    if (candidate.isEmpty) {
      return null;
    }

    final List<String> parts = candidate.split(
      RegExp(r'\s+'),
    );

    for (
    int index = 0;
    index < parts.length - 1;
    index++
    ) {
      if (parts[index].trim().toLowerCase() !=
          'u' 'frag') {
        continue;
      }

      final String value = parts[index + 1].trim();

      if (value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  String? _extractIceUsernameFragment(
      String? sdp,
      String? targetMid,
      ) {
    final String rawSdp = sdp?.trim() ?? '';

    if (rawSdp.isEmpty) {
      return null;
    }

    final List<String> lines = rawSdp.split(
      RegExp(r'\r?\n'),
    );

    String? sessionFragment;

    String? currentMid;

    String? currentMediaFragment;

    bool insideMediaSection = false;

    final Map<String, String> fragmentByMid =
    <String, String>{};

    final Set<String> mediaFragments =
    <String>{};

    void commitMediaSection() {
      final String? fragment = currentMediaFragment;

      if (fragment == null ||
          fragment.isEmpty) {
        return;
      }

      mediaFragments.add(
        fragment,
      );

      final String? mid = currentMid;

      if (mid != null &&
          mid.isNotEmpty) {
        fragmentByMid[mid] = fragment;
      }
    }

    for (final String rawLine in lines) {
      final String line = rawLine.trim();

      if (line.isEmpty) {
        continue;
      }

      if (line.startsWith('m=')) {
        if (insideMediaSection) {
          commitMediaSection();
        }

        insideMediaSection = true;

        currentMid = null;

        currentMediaFragment = null;

        continue;
      }

      if (line.startsWith('a=mid:') &&
          insideMediaSection) {
        final String value = line
            .substring(
          'a=mid:'.length,
        )
            .trim();

        if (value.isNotEmpty) {
          currentMid = value;
        }

        continue;
      }

      if (!line.startsWith(
        'a=ice-u' 'frag:',
      )) {
        continue;
      }

      final String value = line
          .substring(
        ('a=ice-u' 'frag:').length,
      )
          .trim();

      if (value.isEmpty) {
        continue;
      }

      if (insideMediaSection) {
        currentMediaFragment ??= value;
      } else {
        sessionFragment ??= value;
      }
    }

    if (insideMediaSection) {
      commitMediaSection();
    }

    final String? normalizedMid =
    _readNullableString(
      targetMid,
    );

    if (normalizedMid != null) {
      final String? exact =
      fragmentByMid[normalizedMid];

      if (exact != null &&
          exact.isNotEmpty) {
        return exact;
      }
    }

    if (mediaFragments.length == 1) {
      return mediaFragments.first;
    }

    return sessionFragment;
  }

  // =============================================================
  // SESSION VALIDATION
  // =============================================================

  bool _isGenerationCurrent(
      int generation,
      ) {
    return !_disposed &&
        generation == _generation;
  }

  bool _isCurrentSession({
    required int generation,
    required String callId,
    required RTCPeerConnection peerConnection,
  }) {
    return !_disposed &&
        generation == _generation &&
        _currentCallId == callId &&
        identical(
          _currentPeerConnection,
          peerConnection,
        );
  }

  // =============================================================
  // CANDIDATE SIGNATURE
  // =============================================================

  String _signatureForEnvelope(
      _IceCandidateEnvelope envelope,
      ) {
    return _candidateSignature(
      candidateValue: envelope.candidate.candidate,
      sdpMid: envelope.candidate.sdpMid,
      sdpMLineIndex:
      envelope.candidate.sdpMLineIndex,
      usernameFragment:
      envelope.usernameFragment,
    );
  }

  String _candidateSignature({
    required String? candidateValue,
    required String? sdpMid,
    required int? sdpMLineIndex,
    required String? usernameFragment,
  }) {
    return '${candidateValue?.trim() ?? ''}|'
        '${sdpMid?.trim() ?? ''}|'
        '${sdpMLineIndex?.toString() ?? ''}|'
        '${usernameFragment?.trim() ?? ''}';
  }

  // =============================================================
  // DATA HELPERS
  // =============================================================

  String? _cleanCandidate(
      String? value,
      ) {
    final String normalized =
        value?.trim() ?? '';

    return normalized.isEmpty
        ? null
        : normalized;
  }

  String? _readNullableString(
      Object? value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      final String normalized = value.trim();

      return normalized.isEmpty
          ? null
          : normalized;
    }

    final String normalized =
    value.toString().trim();

    return normalized.isEmpty
        ? null
        : normalized;
  }

  int? _readNullableInt(
      Object? value,
      ) {
    if (value == null) {
      return null;
    }

    int? result;

    if (value is int) {
      result = value;
    } else if (value is num) {
      if (!value.isFinite) {
        return null;
      }

      result = value.toInt();
    } else if (value is String) {
      result = int.tryParse(
        value.trim(),
      );
    }

    if (result == null ||
        result < 0) {
      return null;
    }

    return result;
  }

  // =============================================================
  // REMOTE SUBSCRIPTION CLEANUP
  // =============================================================

  Future<void> _cancelRemoteSubscription() async {
    final StreamSubscription<List<Map<String, dynamic>>>?
    subscription =
        _remoteSubscription;

    _remoteSubscription = null;

    if (subscription == null) {
      return;
    }

    await _cancelSubscriptionSafely(
      subscription,
      source: 'Cancel remote ICE subscription',
    );
  }

  Future<void> _cancelSubscriptionSafely(
      StreamSubscription<List<Map<String, dynamic>>> subscription, {
        required String source,
      }) async {
    try {
      await subscription.cancel();
    } catch (error, stackTrace) {
      _reportError(
        source,
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // LOCAL CALLBACK CLEANUP
  // =============================================================

  void _detachLocalCandidateCallback() {
    final RTCPeerConnection? peerConnection =
        _currentPeerConnection;

    if (peerConnection == null) {
      return;
    }

    try {
      peerConnection.onIceCandidate = null;
    } catch (_) {
      // PeerConnection may already have been released.
    }
  }

  // =============================================================
  // CANDIDATE STATE RESET
  // =============================================================

  void _clearCandidateState() {
    _pendingRemoteCandidates.clear();

    _processedRemoteCandidates.clear();

    _pendingRemoteCandidateSignatures.clear();

    _inFlightRemoteCandidateSignatures.clear();

    _sentLocalCandidates.clear();

    _remoteProcessingTail = Future<void>.value();
  }

  // =============================================================
  // RESET
  // =============================================================

  void reset() {
    if (_disposed) {
      return;
    }

    _generation++;

    _cancelPendingRetry();

    final StreamSubscription<List<Map<String, dynamic>>>?
    subscription =
        _remoteSubscription;

    _remoteSubscription = null;

    if (subscription != null) {
      unawaited(
        _cancelSubscriptionSafely(
          subscription,
          source: 'Reset remote ICE subscription',
        ),
      );
    }

    _detachLocalCandidateCallback();

    _clearCandidateState();

    _currentCallId = null;

    _currentIsCaller = null;

    _currentPeerConnection = null;

    _initialized = false;

    _notifySafely();

    _debugPrint(
      'reset complete.',
    );
  }

  // =============================================================
  // SAFE NOTIFICATION
  // =============================================================

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // =============================================================
  // ERROR REPORTING
  // =============================================================

  void _debugPrint(
      String message,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL [IceManager]: '
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
          '[IceManager/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[IceManager/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // =============================================================
  // COMPLETE DISPOSAL
  // =============================================================

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _generation++;

    _cancelPendingRetry();

    final StreamSubscription<List<Map<String, dynamic>>>?
    subscription =
        _remoteSubscription;

    _remoteSubscription = null;

    if (subscription != null) {
      unawaited(
        _cancelSubscriptionSafely(
          subscription,
          source: 'Dispose remote ICE subscription',
        ),
      );
    }

    _detachLocalCandidateCallback();

    _clearCandidateState();

    _currentCallId = null;

    _currentIsCaller = null;

    _currentPeerConnection = null;

    _initialized = false;

    super.dispose();
  }
}

// ===============================================================
// PRIVATE ICE CANDIDATE ENVELOPE
//
// flutter_webrtc 1.5.2 RTCIceCandidate itself exposes only:
// - candidate
// - sdpMid
// - sdpMLineIndex
//
// usernameFragment therefore remains side metadata here.
// ===============================================================

class _IceCandidateEnvelope {
  const _IceCandidateEnvelope({
    required this.candidate,
    required this.usernameFragment,
    required this.enqueuedAt,
  });

  final RTCIceCandidate candidate;

  final String? usernameFragment;

  final DateTime enqueuedAt;
}

// ===============================================================
// END OF FILE
// STATUS: FILE 10 CORRECTED VERIFICATION VERSION
//
// NEXT PURE CALL ENGINE FILE:
// FILE 11
// lib/services/managers/peer_connection_manager.dart
// ===============================================================