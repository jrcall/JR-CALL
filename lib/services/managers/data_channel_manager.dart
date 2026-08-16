import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// ===========================================================
/// JR CALL
/// File: data_channel_manager.dart
/// Location: lib/services/managers/data_channel_manager.dart
///
/// Manages WebRTC peer-to-peer data channel.
/// ===========================================================

class DataChannelManager extends ChangeNotifier {
  DataChannelManager._();

  static final DataChannelManager instance = DataChannelManager._();

  RTCDataChannel? _dataChannel;

  final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  final StreamController<RTCDataChannelState> _stateController =
      StreamController<RTCDataChannelState>.broadcast();

  bool _isOpen = false;

  RTCDataChannel? get dataChannel => _dataChannel;

  bool get isDataChannelOpen => _isOpen;

  Stream<String> get messageStream => _messageController.stream;

  Stream<RTCDataChannelState> get stateStream => _stateController.stream;

  Future<RTCDataChannel?> createDataChannel(
    RTCPeerConnection peerConnection, {
    String label = 'jr_call_data',
  }) async {
    if (_dataChannel != null) {
      return _dataChannel;
    }

    try {
      final configuration = RTCDataChannelInit()..ordered = true;

      final channel = await peerConnection.createDataChannel(
        label,
        configuration,
      );

      _attachChannel(channel);

      return channel;
    } catch (error) {
      debugPrint(
        'DataChannelManager create failed: '
        '$error',
      );

      return null;
    }
  }

  void setupReceiverDataChannel(RTCPeerConnection peerConnection) {
    peerConnection.onDataChannel = (RTCDataChannel channel) {
      _attachChannel(channel);
    };
  }

  void attachExistingChannel(RTCDataChannel? channel) {
    if (channel == null) {
      return;
    }

    _attachChannel(channel);
  }

  void _attachChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    channel.onDataChannelState = (RTCDataChannelState state) {
      _isOpen = state == RTCDataChannelState.RTCDataChannelOpen;

      if (!_stateController.isClosed) {
        _stateController.add(state);
      }

      notifyListeners();

      debugPrint('DataChannelManager state=$state');
    };

    channel.onMessage = (RTCDataChannelMessage message) {
      if (message.text.isEmpty) {
        return;
      }

      if (!_messageController.isClosed) {
        _messageController.add(message.text);
      }
    };
  }

  Future<bool> sendMessage(String message) async {
    final normalized = message.trim();

    if (normalized.isEmpty) {
      return false;
    }

    final channel = _dataChannel;

    if (channel == null || !_isOpen) {
      debugPrint('DataChannelManager: channel not open.');

      return false;
    }

    try {
      await channel.send(RTCDataChannelMessage(normalized));

      return true;
    } catch (error) {
      debugPrint(
        'DataChannelManager send failed: '
        '$error',
      );

      return false;
    }
  }

  Future<void> reset() async {
    final channel = _dataChannel;

    _dataChannel = null;
    _isOpen = false;

    if (channel != null) {
      try {
        await channel.close();
      } catch (error) {
        debugPrint(
          'DataChannelManager close failed: '
          '$error',
        );
      }
    }

    notifyListeners();
  }

  @override
  void dispose() {
    final channel = _dataChannel;

    _dataChannel = null;
    _isOpen = false;

    if (channel != null) {
      unawaited(channel.close());
    }

    unawaited(_messageController.close());
    unawaited(_stateController.close());

    super.dispose();
  }
}
