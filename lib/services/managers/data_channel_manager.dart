import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: data_channel_manager.dart
/// Location: lib/services/managers/data_channel_manager.dart
///
/// FINAL PRODUCTION WEBRTC DATA CHANNEL MANAGER
///
/// OWNERSHIP:
///
/// DataChannelManager:
/// - High-level RTCDataChannel ownership.
/// - RTCPeerConnection.onDataChannel ownership.
/// - Channel state callbacks.
/// - Text-message callbacks.
/// - Ordered application send queue.
/// - Data-channel reset/close.
///
/// PeerConnectionManager:
/// - Owns PeerConnection lifecycle.
/// - Low-level createDataChannel() compatibility API only.
///
/// IMPORTANT:
///
/// Production orchestration must not create a second channel
/// through both PeerConnectionManager and DataChannelManager.
///
/// DataChannelManager does NOT:
/// - Create/dispose PeerConnection.
/// - Own ICE.
/// - Persist signaling.
/// - Own media.
/// - Own call lifecycle.
/// - Own recovery.
/// - Own Message Engine persistence.
/// ===========================================================

class DataChannelManager extends ChangeNotifier {
  DataChannelManager._();

  static final DataChannelManager instance =
  DataChannelManager._();

  // ===========================================================
  // CHANNEL STATE
  // ===========================================================

  RTCDataChannel? _dataChannel;

  bool _isOpen = false;

  bool _disposed = false;

  int _generation = 0;

  // ===========================================================
  // LOCAL CREATION
  // ===========================================================

  Future<RTCDataChannel?>? _activeCreationFuture;

  // ===========================================================
  // RECEIVER CALLBACK OWNERSHIP
  // ===========================================================

  RTCPeerConnection? _receiverPeerConnection;

  void Function(RTCDataChannel channel)? _receiverHandler;

  // ===========================================================
  // SEND SERIALIZATION
  // ===========================================================

  Future<void> _sendOperationTail =
  Future<void>.value();

  // ===========================================================
  // STREAMS
  // ===========================================================

  final StreamController<String> _messageController =
  StreamController<String>.broadcast();

  final StreamController<RTCDataChannelState> _stateController =
  StreamController<RTCDataChannelState>.broadcast();

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

  RTCDataChannel? get dataChannel =>
      _dataChannel;

  bool get isDataChannelOpen =>
      _isOpen;

  Stream<String> get messageStream =>
      _messageController.stream;

  Stream<RTCDataChannelState> get stateStream =>
      _stateController.stream;

  // ===========================================================
  // CREATE DATA CHANNEL
  // ===========================================================

  Future<RTCDataChannel?> createDataChannel(
      RTCPeerConnection peerConnection, {
        String label = 'jr_call_data',
      }) {
    if (_disposed) {
      return Future<RTCDataChannel?>.value(
        null,
      );
    }

    final RTCDataChannel? existing =
        _dataChannel;

    if (existing != null &&
        _isUsableChannel(existing)) {
      return Future<RTCDataChannel?>.value(
        existing,
      );
    }

    final Future<RTCDataChannel?>? active =
        _activeCreationFuture;

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
        _generation;

    final Future<RTCDataChannel?> operation =
    _createDataChannelInternal(
      peerConnection: peerConnection,
      label: normalizedLabel,
      generation: generation,
    );

    late final Future<RTCDataChannel?> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _activeCreationFuture,
        tracked,
      )) {
        _activeCreationFuture = null;
      }
    });

    _activeCreationFuture = tracked;

    return tracked;
  }

  Future<RTCDataChannel?> _createDataChannelInternal({
    required RTCPeerConnection peerConnection,
    required String label,
    required int generation,
  }) async {
    RTCDataChannel? createdChannel;

    try {
      final RTCDataChannelInit configuration =
      RTCDataChannelInit()
        ..ordered = true;

      createdChannel =
      await peerConnection.createDataChannel(
        label,
        configuration,
      );

      if (!_isGenerationCurrent(
        generation,
      )) {
        await _closeChannelSafely(
          createdChannel,
          source: 'stale created channel',
        );

        return null;
      }

      final RTCDataChannel? attached =
      await _attachChannel(
        createdChannel,
        generation: generation,
      );

      return attached;
    } catch (error, stackTrace) {
      if (createdChannel != null &&
          !identical(
            createdChannel,
            _dataChannel,
          )) {
        await _closeChannelSafely(
          createdChannel,
          source: 'failed created channel',
        );
      }

      if (_isGenerationCurrent(
        generation,
      )) {
        _reportError(
          'create',
          error,
          stackTrace,
        );
      }

      return null;
    }
  }

  // ===========================================================
  // RECEIVER DATA CHANNEL
  //
  // DataChannelManager is the sole high-level owner of
  // RTCPeerConnection.onDataChannel.
  // ===========================================================

  void setupReceiverDataChannel(
      RTCPeerConnection peerConnection,
      ) {
    if (_disposed) {
      return;
    }

    final void Function(RTCDataChannel channel)?
    currentHandler =
        _receiverHandler;

    if (identical(
      _receiverPeerConnection,
      peerConnection,
    ) &&
        currentHandler != null &&
        identical(
          peerConnection.onDataChannel,
          currentHandler,
        )) {
      return;
    }

    _detachReceiverHandler();

    final int generation =
        _generation;

    late final void Function(RTCDataChannel channel)
    handler;

    handler = (RTCDataChannel channel) {
      if (!_isReceiverHandlerCurrent(
        peerConnection: peerConnection,
        handler: handler,
        generation: generation,
      )) {
        unawaited(
          _closeChannelSafely(
            channel,
            source: 'stale receiver channel',
          ),
        );

        return;
      }

      unawaited(
        _attachChannel(
          channel,
          generation: generation,
        ),
      );
    };

    _receiverPeerConnection =
        peerConnection;

    _receiverHandler =
        handler;

    peerConnection.onDataChannel =
        handler;
  }

  // ===========================================================
  // ATTACH EXISTING CHANNEL
  // ===========================================================

  void attachExistingChannel(
      RTCDataChannel? channel,
      ) {
    if (_disposed ||
        channel == null) {
      return;
    }

    unawaited(
      _attachChannel(
        channel,
        generation: _generation,
      ),
    );
  }

  // ===========================================================
  // CHANNEL ATTACHMENT
  // ===========================================================

  Future<RTCDataChannel?> _attachChannel(
      RTCDataChannel channel, {
        required int generation,
      }) async {
    if (!_isGenerationCurrent(
      generation,
    )) {
      await _closeChannelSafely(
        channel,
        source: 'stale attach',
      );

      return null;
    }

    final RTCDataChannel? current =
        _dataChannel;

    if (identical(
      current,
      channel,
    )) {
      _installChannelCallbacks(
        channel,
        generation: generation,
      );

      _syncCurrentState(
        channel,
        generation: generation,
      );

      return channel;
    }

    if (current != null &&
        _isUsableChannel(current)) {
      // -------------------------------------------------------
      // Never allow a duplicate newly-delivered channel to
      // replace a still-live channel.
      //
      // This also protects accidental simultaneous channel
      // creation on both peers.
      // -------------------------------------------------------

      await _closeChannelSafely(
        channel,
        source: 'duplicate live channel',
      );

      return current;
    }

    if (current != null) {
      _detachChannelCallbacks(
        current,
      );

      await _closeChannelSafely(
        current,
        source: 'replaced inactive channel',
      );

      if (!_isGenerationCurrent(
        generation,
      )) {
        await _closeChannelSafely(
          channel,
          source: 'stale replacement channel',
        );

        return null;
      }
    }

    _dataChannel =
        channel;

    _isOpen = false;

    _installChannelCallbacks(
      channel,
      generation: generation,
    );

    _syncCurrentState(
      channel,
      generation: generation,
    );

    _notifySafely();

    return channel;
  }

  // ===========================================================
  // CHANNEL CALLBACKS
  // ===========================================================

  void _installChannelCallbacks(
      RTCDataChannel channel, {
        required int generation,
      }) {
    channel.onDataChannelState =
        (RTCDataChannelState state) {
      if (!_isCurrentChannel(
        channel: channel,
        generation: generation,
      )) {
        return;
      }

      final bool open =
          state ==
              RTCDataChannelState
                  .RTCDataChannelOpen;

      final bool changed =
          _isOpen != open;

      _isOpen = open;

      if (!_stateController.isClosed) {
        _stateController.add(
          state,
        );
      }

      if (changed) {
        _notifySafely();
      }

      _debugPrint(
        'state=$state',
      );
    };

    channel.onMessage =
        (RTCDataChannelMessage message) {
      if (!_isCurrentChannel(
        channel: channel,
        generation: generation,
      )) {
        return;
      }

      // Public API is Stream<String>.
      // Never read .text from a binary message.
      if (message.isBinary) {
        return;
      }

      final String text =
          message.text;

      if (text.isEmpty) {
        return;
      }

      if (!_messageController.isClosed) {
        _messageController.add(
          text,
        );
      }
    };
  }

  // ===========================================================
  // INITIAL STATE SYNCHRONIZATION
  //
  // An existing channel may already be OPEN before it is attached.
  // ===========================================================

  void _syncCurrentState(
      RTCDataChannel channel, {
        required int generation,
      }) {
    if (!_isCurrentChannel(
      channel: channel,
      generation: generation,
    )) {
      return;
    }

    final RTCDataChannelState? state =
        channel.state;

    if (state == null) {
      return;
    }

    _isOpen =
        state ==
            RTCDataChannelState
                .RTCDataChannelOpen;

    if (!_stateController.isClosed) {
      _stateController.add(
        state,
      );
    }

    _notifySafely();
  }

  // ===========================================================
  // SEND MESSAGE
  //
  // Existing behavior preserved:
  // - trim text
  // - reject empty messages
  //
  // Sends are serialized for deterministic application ordering.
  // ===========================================================

  Future<bool> sendMessage(
      String message,
      ) {
    final String normalized =
    message.trim();

    if (_disposed ||
        normalized.isEmpty) {
      return Future<bool>.value(
        false,
      );
    }

    final RTCDataChannel? channel =
        _dataChannel;

    final int generation =
        _generation;

    if (channel == null ||
        !_isOpen) {
      _debugPrint(
        'channel not open.',
      );

      return Future<bool>.value(
        false,
      );
    }

    final Completer<bool> completer =
    Completer<bool>();

    final Future<void> operation =
    _sendOperationTail.then<void>(
          (_) async {
        if (!_isCurrentChannel(
          channel: channel,
          generation: generation,
        ) ||
            !_isOpen) {
          if (!completer.isCompleted) {
            completer.complete(
              false,
            );
          }

          return;
        }

        final RTCDataChannelState? state =
            channel.state;

        if (state != null &&
            state !=
                RTCDataChannelState
                    .RTCDataChannelOpen) {
          if (!completer.isCompleted) {
            completer.complete(
              false,
            );
          }

          return;
        }

        try {
          await channel.send(
            RTCDataChannelMessage(
              normalized,
            ),
          );

          if (!completer.isCompleted) {
            completer.complete(
              true,
            );
          }
        } catch (error, stackTrace) {
          _reportError(
            'send',
            error,
            stackTrace,
          );

          if (!completer.isCompleted) {
            completer.complete(
              false,
            );
          }
        }
      },
    );

    _sendOperationTail =
        operation.then<void>(
              (_) {},
          onError: (
              Object _,
              StackTrace _,
              ) {},
        );

    return completer.future;
  }

  // ===========================================================
  // CHANNEL VALIDATION
  // ===========================================================

  bool _isUsableChannel(
      RTCDataChannel channel,
      ) {
    final RTCDataChannelState? state =
        channel.state;

    return state !=
        RTCDataChannelState
            .RTCDataChannelClosing &&
        state !=
            RTCDataChannelState
                .RTCDataChannelClosed;
  }

  bool _isGenerationCurrent(
      int generation,
      ) {
    return !_disposed &&
        generation ==
            _generation;
  }

  bool _isCurrentChannel({
    required RTCDataChannel channel,
    required int generation,
  }) {
    return !_disposed &&
        generation ==
            _generation &&
        identical(
          _dataChannel,
          channel,
        );
  }

  bool _isReceiverHandlerCurrent({
    required RTCPeerConnection peerConnection,
    required void Function(RTCDataChannel channel)
    handler,
    required int generation,
  }) {
    return !_disposed &&
        generation ==
            _generation &&
        identical(
          _receiverPeerConnection,
          peerConnection,
        ) &&
        identical(
          _receiverHandler,
          handler,
        ) &&
        identical(
          peerConnection.onDataChannel,
          handler,
        );
  }

  // ===========================================================
  // CALLBACK CLEANUP
  // ===========================================================

  void _detachChannelCallbacks(
      RTCDataChannel channel,
      ) {
    try {
      channel.onDataChannelState =
      null;
    } catch (_) {}

    try {
      channel.onMessage =
      null;
    } catch (_) {}
  }

  void _detachReceiverHandler() {
    final RTCPeerConnection? peerConnection =
        _receiverPeerConnection;

    final void Function(RTCDataChannel channel)?
    handler =
        _receiverHandler;

    _receiverPeerConnection =
    null;

    _receiverHandler =
    null;

    if (peerConnection == null ||
        handler == null) {
      return;
    }

    try {
      if (identical(
        peerConnection.onDataChannel,
        handler,
      )) {
        peerConnection.onDataChannel =
        null;
      }
    } catch (_) {
      // PeerConnection may already be closed/disposed.
    }
  }

  // ===========================================================
  // SAFE CHANNEL CLOSE
  // ===========================================================

  Future<void> _closeChannelSafely(
      RTCDataChannel channel, {
        required String source,
      }) async {
    _detachChannelCallbacks(
      channel,
    );

    try {
      await channel.close();
    } catch (error, stackTrace) {
      _reportError(
        source,
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // RESET
  // ===========================================================

  Future<void> reset() async {
    if (_disposed) {
      return;
    }

    _generation++;

    _activeCreationFuture =
    null;

    _detachReceiverHandler();

    final RTCDataChannel? channel =
        _dataChannel;

    _dataChannel =
    null;

    _isOpen =
    false;

    _sendOperationTail =
    Future<void>.value();

    if (channel != null) {
      await _closeChannelSafely(
        channel,
        source: 'reset close',
      );
    }

    _notifySafely();
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
          '[DataChannelManager] '
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
          '[DataChannelManager/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[DataChannelManager/$source]',
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

    _generation++;

    _activeCreationFuture =
    null;

    _detachReceiverHandler();

    final RTCDataChannel? channel =
        _dataChannel;

    _dataChannel =
    null;

    _isOpen =
    false;

    _sendOperationTail =
    Future<void>.value();

    if (channel != null) {
      unawaited(
        _closeChannelSafely(
          channel,
          source: 'dispose close',
        ),
      );
    }

    unawaited(
      _messageController.close(),
    );

    unawaited(
      _stateController.close(),
    );

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 15 FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ DataChannelManager owns RTCPeerConnection.onDataChannel.
// ✓ PeerConnectionManager ownership remains separate.
// ✓ Concurrent channel creation deduplicated.
// ✓ Stale creation cannot attach after reset/new generation.
// ✓ Stale native channel is safely closed.
// ✓ Receiver callback installation is idempotent.
// ✓ Receiver callback is detached only when still manager-owned.
// ✓ Old-session receiver callbacks cannot attach channels.
// ✓ Live channel cannot be replaced by accidental duplicate channel.
// ✓ Closing/closed channel can be safely replaced.
// ✓ Existing callback ownership is detached before channel close.
// ✓ Already-open attached channel state is detected.
// ✓ Stale state callbacks rejected.
// ✓ Stale message callbacks rejected.
// ✓ Binary message never accesses text payload.
// ✓ Existing Stream<String> public contract preserved.
// ✓ Outgoing non-empty trimmed-text behavior preserved.
// ✓ Application sends serialized deterministically.
// ✓ Every queued send revalidates current generation/channel/open state.
// ✓ Reset invalidates pending creation/send/callback work.
// ✓ Reset awaits current channel close.
// ✓ Dispose closes channel/controllers without post-dispose notification.
// ✓ No PeerConnection lifecycle ownership.
// ✓ No ICE/signaling ownership.
// ✓ No media ownership.
// ✓ No recovery/lifecycle ownership.
// ✓ No Message Engine persistence ownership.
//
// STATUS:
// DATA CHANNEL MANAGER FINALIZED.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 16
// lib/services/managers/network_manager.dart
// ===============================================================