import '../../models/network_model.dart';
import '../managers/network_manager.dart';

/// ===========================================================
/// JR CALL
/// File: network_optimizer.dart
/// Location: lib/services/call/network_optimizer.dart
///
/// FINAL PRODUCTION NETWORK OPTIMIZATION POLICY ENGINE.
///
/// Responsibilities:
/// - Consume NetworkManager as the single network-state source.
/// - Provide adaptive audio/video bitrate recommendations.
/// - Provide adaptive FPS and resolution profiles.
/// - Provide call-quality optimization level.
/// - Expose feature flags for media optimization.
/// - Keep optimization decisions deterministic.
///
/// Architecture:
///
/// NetworkManager
///      ↓
/// NetworkOptimizer
///      ↓
/// ConnectionManager / CallQualityMonitor / BitrateController
///      ↓
/// WebRTC / CallService
///
/// IMPORTANT:
///
/// - Does NOT perform independent network measurements.
/// - Does NOT duplicate NetworkHelper polling.
/// - Does NOT own timers/listeners.
/// - Does NOT mutate WebRTC bitrate.
/// - Does NOT own recovery.
/// - Does NOT own signaling.
/// - Does NOT own media.
/// - Does NOT change UI/design.
/// ===========================================================

class NetworkOptimizer {
  NetworkOptimizer._();

  static final NetworkOptimizer instance =
  NetworkOptimizer._();

  // ===========================================================
  // DEPENDENCY
  // ===========================================================

  final NetworkManager _networkManager =
      NetworkManager.instance;

  // ===========================================================
  // INITIALIZATION STATE
  // ===========================================================

  bool _initialized = false;

  int _generation = 0;

  Future<void>? _activeInitialization;

  bool get isInitialized =>
      _initialized;

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final Future<void>? active =
        _activeInitialization;

    if (active != null) {
      await active;

      return;
    }

    final int generation =
    ++_generation;

    final Future<void> operation =
    _initializeInternal(
      generation,
    );

    late final Future<void> tracked;

    tracked = operation.whenComplete(() {
      if (identical(
        _activeInitialization,
        tracked,
      )) {
        _activeInitialization = null;
      }
    });

    _activeInitialization =
        tracked;

    await tracked;
  }

  Future<void> _initializeInternal(
      int generation,
      ) async {
    if (!_networkManager.isInitialized) {
      await _networkManager.initialize();
    }

    if (generation !=
        _generation) {
      return;
    }

    _initialized = true;
  }

  // ===========================================================
  // CURRENT NETWORK STATE
  // ===========================================================

  NetworkModel get currentNetwork =>
      _networkManager.currentNetwork;

  Future<NetworkQuality> get quality =>
      Future<NetworkQuality>.value(
        currentNetwork.quality,
      );

  bool get isConnected =>
      currentNetwork.isConnected;

  // ===========================================================
  // VIDEO BITRATE
  // ===========================================================

  Future<int> get videoBitrate {
    final NetworkModel network =
        currentNetwork;

    return Future<int>.value(
      _videoBitrateFor(
        network,
      ),
    );
  }

  int _videoBitrateFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return 0;
    }

    final int recommended =
        network.recommendedBitrate;

    if (recommended > 0) {
      return recommended;
    }

    switch (network.quality) {
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
  // AUDIO BITRATE
  // ===========================================================

  Future<int> get audioBitrate {
    final NetworkModel network =
        currentNetwork;

    return Future<int>.value(
      _audioBitrateFor(
        network,
      ),
    );
  }

  int _audioBitrateFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return 0;
    }

    switch (network.quality) {
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

  Future<int> get fps {
    final NetworkModel network =
        currentNetwork;

    return Future<int>.value(
      _fpsFor(
        network,
      ),
    );
  }

  int _fpsFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return 0;
    }

    final int recommended =
        network.recommendedFps;

    if (recommended > 0) {
      return recommended;
    }

    switch (network.quality) {
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
  // RESOLUTION
  //
  // IMPORTANT:
  //
  // Public API intentionally remains:
  //
  // Future<Map<String, int>>
  //
  // FILE 18 depends on this exact async contract.
  // ===========================================================

  Future<Map<String, int>>
  get resolutionProfile {
    final NetworkModel network =
        currentNetwork;

    return Future<Map<String, int>>.value(
      _resolutionFor(
        network,
      ),
    );
  }

  Map<String, int> _resolutionFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return const <String, int>{
        'width': 640,
        'height': 360,
      };
    }

    final int width =
        network.videoWidth;

    final int height =
        network.videoHeight;

    if (width > 0 &&
        height > 0) {
      return <String, int>{
        'width': width,
        'height': height,
      };
    }

    switch (network.quality) {
      case NetworkQuality.excellent:
        return const <String, int>{
          'width': 1280,
          'height': 720,
        };

      case NetworkQuality.good:
        return const <String, int>{
          'width': 854,
          'height': 480,
        };

      case NetworkQuality.fair:
      case NetworkQuality.poor:
      case NetworkQuality.offline:
        return const <String, int>{
          'width': 640,
          'height': 360,
        };
    }
  }

  Future<String> get resolution {
    final NetworkModel network =
        currentNetwork;

    final Map<String, int> profile =
    _resolutionFor(
      network,
    );

    return Future<String>.value(
      '${profile['width']}x'
          '${profile['height']}',
    );
  }

  // ===========================================================
  // OPTIMIZATION LEVEL
  //
  // 0 = No optimization required
  // 1 = Light
  // 2 = Moderate
  // 3 = Aggressive
  // ===========================================================

  Future<int> get optimizationLevel {
    final NetworkModel network =
        currentNetwork;

    return Future<int>.value(
      _optimizationLevelFor(
        network,
      ),
    );
  }

  int _optimizationLevelFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return 3;
    }

    final double packetLoss =
    _normalizedPacketLoss(
      network.packetLoss,
    );

    final int ping =
    _normalizedPing(
      network.ping,
    );

    final int jitter =
    _normalizedJitter(
      network.jitter,
    );

    if (packetLoss >= 10.0 ||
        ping >= 300) {
      return 3;
    }

    if (packetLoss >= 5.0 ||
        ping >= 200 ||
        jitter >= 80) {
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
  // ADAPTIVE MEDIA FLAGS
  // ===========================================================

  Future<bool> get enableAdaptiveBitrate {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      _adaptiveBitrateFor(
        network,
      ),
    );
  }

  bool _adaptiveBitrateFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return true;
    }

    return network.quality !=
        NetworkQuality.excellent ||
        _optimizationLevelFor(
          network,
        ) >
            0;
  }

  Future<bool> get enableAdaptiveResolution {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      _adaptiveResolutionFor(
        network,
      ),
    );
  }

  bool _adaptiveResolutionFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return true;
    }

    if (_optimizationLevelFor(
      network,
    ) >=
        2) {
      return true;
    }

    return network.quality !=
        NetworkQuality.excellent;
  }

  Future<bool> get enableAdaptiveFps {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      _adaptiveFpsFor(
        network,
      ),
    );
  }

  bool _adaptiveFpsFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return true;
    }

    return network.quality !=
        NetworkQuality.excellent ||
        _optimizationLevelFor(
          network,
        ) >
            0;
  }

  // ===========================================================
  // MEDIA AVAILABILITY
  // ===========================================================

  Future<bool> get enableVideo {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      _videoEnabledFor(
        network,
      ),
    );
  }

  bool _videoEnabledFor(
      NetworkModel network,
      ) {
    return network.isConnected &&
        network.quality !=
            NetworkQuality.offline;
  }

  Future<bool> get enableAudio {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      _audioEnabledFor(
        network,
      ),
    );
  }

  bool _audioEnabledFor(
      NetworkModel network,
      ) {
    return network.isConnected &&
        network.quality !=
            NetworkQuality.offline;
  }

  Future<bool> get disableVideo {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      !_videoEnabledFor(
        network,
      ),
    );
  }

  // ===========================================================
  // DATA SAVER
  // ===========================================================

  Future<bool> get enableDataSaver {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      _dataSaverFor(
        network,
      ),
    );
  }

  bool _dataSaverFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return true;
    }

    final double packetLoss =
    _normalizedPacketLoss(
      network.packetLoss,
    );

    final int ping =
    _normalizedPing(
      network.ping,
    );

    return network.quality ==
        NetworkQuality.poor ||
        network.quality ==
            NetworkQuality.offline ||
        packetLoss >= 5.0 ||
        ping >= 250;
  }

  // ===========================================================
  // AUDIO ENHANCEMENT FLAGS
  // ===========================================================

  Future<bool> get enableNoiseReduction {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      network.isConnected,
    );
  }

  Future<bool> get enableEchoCancellation =>
      Future<bool>.value(
        true,
      );

  Future<bool> get enableAutoGainControl =>
      Future<bool>.value(
        true,
      );

  // ===========================================================
  // VIDEO ENHANCEMENT FLAGS
  // ===========================================================

  Future<bool> get enableHD {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      _hdEnabledFor(
        network,
      ),
    );
  }

  bool _hdEnabledFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return false;
    }

    final double packetLoss =
    _normalizedPacketLoss(
      network.packetLoss,
    );

    final int ping =
    _normalizedPing(
      network.ping,
    );

    if (packetLoss >= 5.0 ||
        ping >= 250) {
      return false;
    }

    return network.quality ==
        NetworkQuality.excellent ||
        network.quality ==
            NetworkQuality.good;
  }

  Future<bool> get enableSuperResolution {
    final NetworkModel network =
        currentNetwork;

    return Future<bool>.value(
      _superResolutionEnabledFor(
        network,
      ),
    );
  }

  bool _superResolutionEnabledFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return false;
    }

    final double packetLoss =
    _normalizedPacketLoss(
      network.packetLoss,
    );

    final int ping =
    _normalizedPing(
      network.ping,
    );

    return network.quality ==
        NetworkQuality.excellent &&
        packetLoss < 2.0 &&
        ping < 150;
  }

  // ===========================================================
  // SUGGESTED MEDIA PROFILE
  //
  // IMPORTANT:
  //
  // Capture ONE NetworkModel snapshot and derive every field
  // from that same snapshot.
  //
  // This prevents a network update between multiple awaits from
  // producing an internally mixed profile.
  //
  // Public API intentionally remains Future<Map<String, dynamic>>.
  // ===========================================================

  Future<Map<String, dynamic>>
  get recommendedProfile {
    final NetworkModel network =
        currentNetwork;

    final Map<String, int> resolutionData =
    _resolutionFor(
      network,
    );

    final Map<String, dynamic> profile =
    <String, dynamic>{
      'connected':
      network.isConnected,
      'quality':
      network.quality.name,
      'videoBitrate':
      _videoBitrateFor(
        network,
      ),
      'audioBitrate':
      _audioBitrateFor(
        network,
      ),
      'fps':
      _fpsFor(
        network,
      ),
      'width':
      resolutionData['width'],
      'height':
      resolutionData['height'],
      'optimizationLevel':
      _optimizationLevelFor(
        network,
      ),
      'adaptiveBitrate':
      _adaptiveBitrateFor(
        network,
      ),
      'adaptiveResolution':
      _adaptiveResolutionFor(
        network,
      ),
      'adaptiveFps':
      _adaptiveFpsFor(
        network,
      ),
      'dataSaver':
      _dataSaverFor(
        network,
      ),
      'videoEnabled':
      _videoEnabledFor(
        network,
      ),
      'audioEnabled':
      _audioEnabledFor(
        network,
      ),
    };

    return Future<
        Map<String, dynamic>>.value(
      profile,
    );
  }

  // ===========================================================
  // METRIC NORMALIZATION
  // ===========================================================

  double _normalizedPacketLoss(
      double value,
      ) {
    if (!value.isFinite ||
        value < 0) {
      return 0.0;
    }

    if (value > 100) {
      return 100.0;
    }

    return value;
  }

  int _normalizedPing(
      int value,
      ) {
    if (value < 0) {
      return 999;
    }

    return value;
  }

  int _normalizedJitter(
      int value,
      ) {
    if (value < 0) {
      return 0;
    }

    return value;
  }

  // ===========================================================
  // RESET
  // ===========================================================

  void reset() {
    _generation++;

    _activeInitialization =
    null;

    _initialized = false;

    // NetworkManager is intentionally NOT reset here.
  }
}

// ===============================================================
// END OF FILE
//
// FILE 19 FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ All existing Future-valued getters remain Future-valued.
// ✓ resolutionProfile remains Future<Map<String, int>>.
// ✓ recommendedProfile remains Future<Map<String, dynamic>>.
// ✓ FILE 18 async API contract preserved.
// ✓ No Future<Map> / Map type mismatch introduced.
// ✓ Initialization concurrency deduplicated.
// ✓ Reset invalidates stale initialization.
// ✓ NetworkManager remains sole network-state source.
// ✓ No independent network measurements added.
// ✓ No timers/listeners/polling added.
// ✓ No WebRTC bitrate mutation added.
// ✓ BitrateController remains actual bitrate owner.
// ✓ One NetworkModel snapshot used per recommendation.
// ✓ recommendedProfile is internally deterministic.
// ✓ Mixed-state async profile generation removed.
// ✓ Real ping/packet-loss/jitter influence optimization flags.
// ✓ No fake network metrics introduced.
// ✓ Adaptive bitrate/resolution/FPS recommendations preserved.
// ✓ Audio/video availability recommendations preserved.
// ✓ HD/super-resolution policy preserved.
// ✓ NetworkManager lifecycle is not reset here.
// ✓ No recovery/signaling/media ownership.
// ✓ No UI/design changes.
//
// STATUS:
// NETWORK OPTIMIZER FINALIZED.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 20
// lib/services/managers/stats_manager.dart
// ===============================================================