import '../../models/network_model.dart';
import '../managers/network_manager.dart';

/// ===========================================================
/// JR CALL
/// File: network_optimizer.dart
/// Location: lib/services/call/network_optimizer.dart
///
/// Description:
/// Production-grade call network optimization policy engine.
///
/// Responsibilities:
/// - Consume NetworkManager as the single network-state source
/// - Provide adaptive audio/video bitrate recommendations
/// - Provide adaptive FPS and resolution profiles
/// - Provide call-quality optimization level
/// - Expose feature flags for AI/media optimization
/// - Keep all network optimization decisions deterministic
///
/// Architecture:
/// NetworkManager
///      ↓
/// NetworkOptimizer
///      ↓
/// ConnectionManager / CallQualityMonitor / BitrateController
///      ↓
/// WebRTC / CallService
///
/// Important:
/// - Does NOT perform independent network measurements.
/// - Does NOT duplicate NetworkHelper polling.
/// - Does NOT own timers, listeners, recovery, or signaling.
/// ===========================================================

class NetworkOptimizer {
  NetworkOptimizer._();

  static final NetworkOptimizer instance = NetworkOptimizer._();

  final NetworkManager _networkManager = NetworkManager.instance;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (!_networkManager.isInitialized) {
      await _networkManager.initialize();
    }

    _initialized = true;
  }

  // ===========================================================
  // Current Network State
  // ===========================================================

  NetworkModel get currentNetwork => _networkManager.currentNetwork;

  Future<NetworkQuality> get quality async => currentNetwork.quality;

  bool get isConnected => currentNetwork.isConnected;

  // ===========================================================
  // Video Bitrate
  // ===========================================================

  Future<int> get videoBitrate async {
    if (!isConnected) {
      return 0;
    }

    final recommended = currentNetwork.recommendedBitrate;

    if (recommended > 0) {
      return recommended;
    }

    switch (currentNetwork.quality) {
      case NetworkQuality.excellent:
        return 2500000;

      case NetworkQuality.good:
        return 1500000;

      case NetworkQuality.fair:
        return 800000;

      case NetworkQuality.poor:
        return 350000;

      case NetworkQuality.offline:
        return 0;
    }
  }

  // ===========================================================
  // Audio Bitrate
  // ===========================================================

  Future<int> get audioBitrate async {
    if (!isConnected) {
      return 0;
    }

    switch (currentNetwork.quality) {
      case NetworkQuality.excellent:
        return 128000;

      case NetworkQuality.good:
        return 96000;

      case NetworkQuality.fair:
        return 64000;

      case NetworkQuality.poor:
        return 32000;

      case NetworkQuality.offline:
        return 0;
    }
  }

  // ===========================================================
  // FPS
  // ===========================================================

  Future<int> get fps async {
    if (!isConnected) {
      return 0;
    }

    final recommended = currentNetwork.recommendedFps;

    if (recommended > 0) {
      return recommended;
    }

    switch (currentNetwork.quality) {
      case NetworkQuality.excellent:
        return 30;

      case NetworkQuality.good:
        return 24;

      case NetworkQuality.fair:
        return 20;

      case NetworkQuality.poor:
        return 15;

      case NetworkQuality.offline:
        return 0;
    }
  }

  // ===========================================================
  // Resolution
  // ===========================================================

  Future<Map<String, int>> get resolutionProfile async {
    if (!isConnected) {
      return const {'width': 640, 'height': 360};
    }

    final width = currentNetwork.videoWidth;

    final height = currentNetwork.videoHeight;

    if (width > 0 && height > 0) {
      return {'width': width, 'height': height};
    }

    switch (currentNetwork.quality) {
      case NetworkQuality.excellent:
        return const {'width': 1280, 'height': 720};

      case NetworkQuality.good:
        return const {'width': 854, 'height': 480};

      case NetworkQuality.fair:
      case NetworkQuality.poor:
      case NetworkQuality.offline:
        return const {'width': 640, 'height': 360};
    }
  }

  Future<String> get resolution async {
    final profile = await resolutionProfile;

    return '${profile['width']}x'
        '${profile['height']}';
  }

  // ===========================================================
  // Optimization Level
  //
  // 0 = No optimization required
  // 1 = Light
  // 2 = Moderate
  // 3 = Aggressive
  // ===========================================================

  Future<int> get optimizationLevel async {
    if (!isConnected) {
      return 3;
    }

    final network = currentNetwork;

    /// Real metrics are allowed to raise optimization level
    /// even when the generic quality classification has not
    /// changed yet.
    if (network.packetLoss >= 10.0 || network.ping >= 300) {
      return 3;
    }

    if (network.packetLoss >= 5.0 ||
        network.ping >= 200 ||
        network.jitter >= 80) {
      return 2;
    }

    switch (network.quality) {
      case NetworkQuality.excellent:
        return 0;

      case NetworkQuality.good:
        return 1;

      case NetworkQuality.fair:
        return 2;

      case NetworkQuality.poor:
      case NetworkQuality.offline:
        return 3;
    }
  }

  // ===========================================================
  // Adaptive Media Flags
  // ===========================================================

  Future<bool> get enableAdaptiveBitrate async {
    if (!isConnected) {
      return true;
    }

    return currentNetwork.quality != NetworkQuality.excellent;
  }

  Future<bool> get enableAdaptiveResolution async {
    if (!isConnected) {
      return true;
    }

    switch (currentNetwork.quality) {
      case NetworkQuality.excellent:
        return false;

      case NetworkQuality.good:
      case NetworkQuality.fair:
      case NetworkQuality.poor:
      case NetworkQuality.offline:
        return true;
    }
  }

  Future<bool> get enableAdaptiveFps async {
    if (!isConnected) {
      return true;
    }

    return currentNetwork.quality != NetworkQuality.excellent;
  }

  // ===========================================================
  // Media Availability
  // ===========================================================

  Future<bool> get enableVideo async {
    if (!isConnected) {
      return false;
    }

    return currentNetwork.quality != NetworkQuality.offline;
  }

  Future<bool> get enableAudio async {
    if (!isConnected) {
      return false;
    }

    return currentNetwork.quality != NetworkQuality.offline;
  }

  Future<bool> get disableVideo async {
    return !(await enableVideo);
  }

  // ===========================================================
  // Data Saver
  // ===========================================================

  Future<bool> get enableDataSaver async {
    if (!isConnected) {
      return true;
    }

    final network = currentNetwork;

    return network.quality == NetworkQuality.poor ||
        network.quality == NetworkQuality.offline ||
        network.packetLoss >= 5.0 ||
        network.ping >= 250;
  }

  // ===========================================================
  // Audio Enhancement Flags
  // ===========================================================

  Future<bool> get enableNoiseReduction async {
    /// Noise suppression is useful on every voice call.
    /// More advanced AI processing can still scale separately.
    return isConnected;
  }

  Future<bool> get enableEchoCancellation async {
    return true;
  }

  Future<bool> get enableAutoGainControl async {
    return true;
  }

  // ===========================================================
  // Video Enhancement Flags
  // ===========================================================

  Future<bool> get enableHD async {
    if (!isConnected) {
      return false;
    }

    final network = currentNetwork;

    if (network.packetLoss >= 5.0 || network.ping >= 250) {
      return false;
    }

    return network.quality == NetworkQuality.excellent ||
        network.quality == NetworkQuality.good;
  }

  Future<bool> get enableSuperResolution async {
    if (!isConnected) {
      return false;
    }

    final network = currentNetwork;

    return network.quality == NetworkQuality.excellent &&
        network.packetLoss < 2.0 &&
        network.ping < 150;
  }

  // ===========================================================
  // Suggested Media Profile
  // ===========================================================

  Future<Map<String, dynamic>> get recommendedProfile async {
    final resolutionData = await resolutionProfile;

    return <String, dynamic>{
      'connected': isConnected,
      'quality': currentNetwork.quality.name,
      'videoBitrate': await videoBitrate,
      'audioBitrate': await audioBitrate,
      'fps': await fps,
      'width': resolutionData['width'],
      'height': resolutionData['height'],
      'optimizationLevel': await optimizationLevel,
      'adaptiveBitrate': await enableAdaptiveBitrate,
      'adaptiveResolution': await enableAdaptiveResolution,
      'adaptiveFps': await enableAdaptiveFps,
      'dataSaver': await enableDataSaver,
      'videoEnabled': await enableVideo,
      'audioEnabled': await enableAudio,
    };
  }

  // ===========================================================
  // Reset
  // ===========================================================

  void reset() {
    _initialized = false;
  }
}
