import '../../models/network_model.dart';
import 'network_optimizer.dart';

// ===========================================================
// JR CALL
// File: bitrate_controller.dart
// Location: lib/services/call/bitrate_controller.dart
//
// Description:
// Central adaptive audio/video bitrate policy controller.
//
// Architecture:
//
// NetworkManager
//      ↓
// NetworkOptimizer
//      ↓
// BitrateController
//      ↓
// AI / WebRTC media layer
//
// Ownership:
// - NetworkManager owns network measurement
// - NetworkOptimizer owns optimization policy
// - BitrateController exposes bitrate decisions
// - WebRTC/media layer owns actual RTCRtpSender mutation
//
// Rules:
// - No direct NetworkHelper access
// - No duplicate network polling
// - No duplicate timers
// - No signaling
// - No ICE handling
// - No recovery logic
// - No peer-connection lifecycle ownership
// ===========================================================

class BitrateController {
  BitrateController._();

  static final BitrateController instance = BitrateController._();

  // ===========================================================
  // Dependencies
  // ===========================================================

  final NetworkOptimizer _networkOptimizer = NetworkOptimizer.instance;

  // ===========================================================
  // Runtime State
  // ===========================================================

  bool _initialized = false;

  // ===========================================================
  // Public State
  // ===========================================================

  bool get isInitialized => _initialized;

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (!_networkOptimizer.isInitialized) {
      await _networkOptimizer.initialize();
    }

    _initialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  // ===========================================================
  // Current Network Quality
  // ===========================================================

  Future<NetworkQuality> get quality async {
    await _ensureInitialized();

    return _networkOptimizer.currentNetwork.quality;
  }

  // ===========================================================
  // Video Bitrate
  // ===========================================================

  /// Recommended video bitrate in bits per second.
  Future<int> get videoBitrate async {
    await _ensureInitialized();

    final bitrate = await _networkOptimizer.videoBitrate;

    return _sanitizeBitrate(bitrate);
  }

  // ===========================================================
  // Audio Bitrate
  // ===========================================================

  /// Recommended audio bitrate in bits per second.
  Future<int> get audioBitrate async {
    await _ensureInitialized();

    final bitrate = await _networkOptimizer.audioBitrate;

    return _sanitizeBitrate(bitrate);
  }

  // ===========================================================
  // Adaptive Bitrate
  // ===========================================================

  /// Compatibility method used by existing call-engine code.
  ///
  /// The actual adaptive recommendation is owned by
  /// NetworkOptimizer.
  Future<int> adaptiveBitrate() async {
    return videoBitrate;
  }

  // ===========================================================
  // Adaptive Audio Bitrate
  // ===========================================================

  Future<int> adaptiveAudioBitrate() async {
    return audioBitrate;
  }

  // ===========================================================
  // HD Availability
  // ===========================================================

  Future<bool> get allowHD async {
    await _ensureInitialized();

    return _networkOptimizer.enableHD;
  }

  // ===========================================================
  // Full-HD Availability
  // ===========================================================

  Future<bool> get allowFullHD async {
    await _ensureInitialized();

    final network = _networkOptimizer.currentNetwork;

    if (!network.isConnected) {
      return false;
    }

    return network.quality == NetworkQuality.excellent &&
        network.packetLoss < 2.0 &&
        network.ping < 150;
  }

  // ===========================================================
  // Adaptive Feature State
  // ===========================================================

  Future<bool> get adaptiveBitrateEnabled async {
    await _ensureInitialized();

    return _networkOptimizer.enableAdaptiveBitrate;
  }

  Future<bool> get dataSaverEnabled async {
    await _ensureInitialized();

    return _networkOptimizer.enableDataSaver;
  }

  // ===========================================================
  // Current Recommended Profile
  // ===========================================================

  Future<Map<String, dynamic>> get recommendedProfile async {
    await _ensureInitialized();

    return <String, dynamic>{
      'connected': _networkOptimizer.isConnected,
      'quality': _networkOptimizer.currentNetwork.quality.name,
      'videoBitrate': await videoBitrate,
      'audioBitrate': await audioBitrate,
      'allowHD': await allowHD,
      'allowFullHD': await allowFullHD,
      'adaptiveBitrate': await adaptiveBitrateEnabled,
      'dataSaver': await dataSaverEnabled,
    };
  }

  // ===========================================================
  // Validation
  // ===========================================================

  int _sanitizeBitrate(int bitrate) {
    if (bitrate <= 0) {
      return 0;
    }

    return bitrate;
  }

  // ===========================================================
  // Reset
  // ===========================================================

  void reset() {
    _initialized = false;

    // NetworkOptimizer and NetworkManager are shared
    // call-engine services and therefore are intentionally
    // NOT reset from BitrateController.
  }
}
