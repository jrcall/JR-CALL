import '../../models/network_model.dart';
import 'network_optimizer.dart';

// ===========================================================
// JR CALL
// File: bitrate_controller.dart
// Location: lib/services/call/bitrate_controller.dart
//
// FINAL PRODUCTION BITRATE POLICY CONTROLLER.
//
// Architecture:
//
// NetworkManager
//      ↓
// NetworkOptimizer
//      ↓
// BitrateController
//      ↓
// WebRTC / Media Layer
//
// Ownership:
//
// NetworkManager:
// - Network measurement.
//
// NetworkOptimizer:
// - Optimization policy.
//
// BitrateController:
// - Exposes and validates bitrate decisions.
//
// WebRTC / Media Layer:
// - Actual RTCRtpSender mutation.
//
// IMPORTANT:
//
// - No direct NetworkHelper access.
// - No duplicate network polling.
// - No timers/listeners.
// - No signaling.
// - No ICE handling.
// - No recovery logic.
// - No PeerConnection lifecycle ownership.
// - No media acquisition.
// - No UI/design changes.
// ===========================================================

class BitrateController {
  BitrateController._();

  static final BitrateController instance =
  BitrateController._();

  // ===========================================================
  // DEPENDENCY
  // ===========================================================

  final NetworkOptimizer _networkOptimizer =
      NetworkOptimizer.instance;

  // ===========================================================
  // INITIALIZATION STATE
  // ===========================================================

  bool _initialized = false;

  int _generation = 0;

  Future<void>? _activeInitialization;

  // ===========================================================
  // PUBLIC STATE
  // ===========================================================

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
    if (!_networkOptimizer.isInitialized) {
      await _networkOptimizer.initialize();
    }

    if (generation !=
        _generation) {
      return;
    }

    _initialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    await initialize();
  }

  // ===========================================================
  // CURRENT NETWORK QUALITY
  // ===========================================================

  Future<NetworkQuality> get quality async {
    await _ensureInitialized();

    return _networkOptimizer
        .currentNetwork
        .quality;
  }

  // ===========================================================
  // VIDEO BITRATE
  //
  // Bits per second.
  // ===========================================================

  Future<int> get videoBitrate async {
    await _ensureInitialized();

    final int bitrate =
    await _networkOptimizer
        .videoBitrate;

    return _sanitizeBitrate(
      bitrate,
    );
  }

  // ===========================================================
  // AUDIO BITRATE
  //
  // Bits per second.
  // ===========================================================

  Future<int> get audioBitrate async {
    await _ensureInitialized();

    final int bitrate =
    await _networkOptimizer
        .audioBitrate;

    return _sanitizeBitrate(
      bitrate,
    );
  }

  // ===========================================================
  // ADAPTIVE VIDEO BITRATE
  // ===========================================================

  Future<int> adaptiveBitrate() async {
    return videoBitrate;
  }

  // ===========================================================
  // ADAPTIVE AUDIO BITRATE
  // ===========================================================

  Future<int> adaptiveAudioBitrate() async {
    return audioBitrate;
  }

  // ===========================================================
  // HD AVAILABILITY
  //
  // NetworkOptimizer remains policy owner.
  // ===========================================================

  Future<bool> get allowHD async {
    await _ensureInitialized();

    final bool enabled =
    await _networkOptimizer
        .enableHD;

    return enabled;
  }

  // ===========================================================
  // FULL-HD AVAILABILITY
  //
  // Compatibility policy preserved from the existing file.
  // ===========================================================

  Future<bool> get allowFullHD async {
    await _ensureInitialized();

    final NetworkModel network =
        _networkOptimizer.currentNetwork;

    return _allowFullHDFor(
      network,
    );
  }

  bool _allowFullHDFor(
      NetworkModel network,
      ) {
    if (!network.isConnected) {
      return false;
    }

    final double packetLoss =
        network.packetLoss;

    final int ping =
        network.ping;

    if (!packetLoss.isFinite ||
        packetLoss < 0 ||
        packetLoss >= 2.0) {
      return false;
    }

    if (ping < 0 ||
        ping >= 150) {
      return false;
    }

    return network.quality ==
        NetworkQuality.excellent;
  }

  // ===========================================================
  // ADAPTIVE FEATURE STATE
  // ===========================================================

  Future<bool> get adaptiveBitrateEnabled async {
    await _ensureInitialized();

    final bool enabled =
    await _networkOptimizer
        .enableAdaptiveBitrate;

    return enabled;
  }

  Future<bool> get dataSaverEnabled async {
    await _ensureInitialized();

    final bool enabled =
    await _networkOptimizer
        .enableDataSaver;

    return enabled;
  }

  // ===========================================================
  // CURRENT RECOMMENDED PROFILE
  //
  // IMPORTANT:
  //
  // NetworkOptimizer.recommendedProfile is asynchronous:
  //
  // Future<Map<String, dynamic>>
  //
  // It must always be awaited before using it as a Map.
  //
  // A short retry protects the composed profile from a network
  // snapshot changing between asynchronous policy reads.
  // ===========================================================

  Future<Map<String, dynamic>>
  get recommendedProfile async {
    await _ensureInitialized();

    const int maxSnapshotAttempts = 3;

    for (int attempt = 0;
    attempt < maxSnapshotAttempts;
    attempt++) {
      final NetworkModel snapshot =
          _networkOptimizer.currentNetwork;

      final Map<String, dynamic>
      optimizerProfile =
      await _networkOptimizer
          .recommendedProfile;

      final bool hdEnabled =
      await _networkOptimizer
          .enableHD;

      if (!identical(
        snapshot,
        _networkOptimizer.currentNetwork,
      )) {
        continue;
      }

      return Map<String, dynamic>.unmodifiable(
        <String, dynamic>{
          'connected':
          optimizerProfile['connected'] ??
              snapshot.isConnected,
          'quality':
          optimizerProfile['quality'] ??
              snapshot.quality.name,
          'videoBitrate':
          _sanitizeDynamicBitrate(
            optimizerProfile[
            'videoBitrate'],
          ),
          'audioBitrate':
          _sanitizeDynamicBitrate(
            optimizerProfile[
            'audioBitrate'],
          ),
          'allowHD':
          hdEnabled,
          'allowFullHD':
          _allowFullHDFor(
            snapshot,
          ),
          'adaptiveBitrate':
          optimizerProfile[
          'adaptiveBitrate'] ==
              true,
          'dataSaver':
          optimizerProfile[
          'dataSaver'] ==
              true,
        },
      );
    }

    // ---------------------------------------------------------
    // Extremely rare case:
    //
    // Network state changed during every retry.
    //
    // Return the freshest policy snapshot rather than failing
    // the Call Engine.
    // ---------------------------------------------------------

    final Map<String, dynamic> optimizerProfile =
    await _networkOptimizer
        .recommendedProfile;

    final NetworkModel latestNetwork =
        _networkOptimizer.currentNetwork;

    final bool hdEnabled =
    await _networkOptimizer
        .enableHD;

    return Map<String, dynamic>.unmodifiable(
      <String, dynamic>{
        'connected':
        optimizerProfile['connected'] ??
            latestNetwork.isConnected,
        'quality':
        optimizerProfile['quality'] ??
            latestNetwork.quality.name,
        'videoBitrate':
        _sanitizeDynamicBitrate(
          optimizerProfile[
          'videoBitrate'],
        ),
        'audioBitrate':
        _sanitizeDynamicBitrate(
          optimizerProfile[
          'audioBitrate'],
        ),
        'allowHD':
        hdEnabled,
        'allowFullHD':
        _allowFullHDFor(
          latestNetwork,
        ),
        'adaptiveBitrate':
        optimizerProfile[
        'adaptiveBitrate'] ==
            true,
        'dataSaver':
        optimizerProfile[
        'dataSaver'] ==
            true,
      },
    );
  }

  // ===========================================================
  // VALIDATION
  // ===========================================================

  int _sanitizeBitrate(
      int bitrate,
      ) {
    if (bitrate <= 0) {
      return 0;
    }

    return bitrate;
  }

  int _sanitizeDynamicBitrate(
      Object? value,
      ) {
    if (value is int) {
      return _sanitizeBitrate(
        value,
      );
    }

    if (value is num &&
        value.isFinite) {
      return _sanitizeBitrate(
        value.toInt(),
      );
    }

    return 0;
  }

  // ===========================================================
  // RESET
  // ===========================================================

  void reset() {
    _generation++;

    _activeInitialization =
    null;

    _initialized = false;

    // NetworkOptimizer and NetworkManager are shared Call Engine
    // services and are intentionally NOT reset here.
  }
}

// ===========================================================
// END OF FILE
//
// FILE 21 FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ Existing bits-per-second bitrate semantics preserved.
// ✓ NetworkOptimizer remains optimization-policy owner.
// ✓ BitrateController remains recommendation/exposure layer.
// ✓ Actual RTCRtpSender mutation remains WebRTC/media-owned.
// ✓ Initialization concurrency deduplicated.
// ✓ Reset invalidates stale initialization.
// ✓ Old initialization cannot reactivate controller after reset.
// ✓ NetworkOptimizer Future APIs are explicitly awaited.
// ✓ videoBitrate Future contract handled correctly.
// ✓ audioBitrate Future contract handled correctly.
// ✓ enableHD Future contract handled correctly.
// ✓ enableAdaptiveBitrate Future contract handled correctly.
// ✓ enableDataSaver Future contract handled correctly.
// ✓ recommendedProfile Future<Map> contract handled correctly.
// ✓ No Future<Map> passed directly where Map is required.
// ✓ Non-positive bitrate safely becomes zero.
// ✓ Invalid dynamic bitrate safely becomes zero.
// ✓ Full-HD policy uses one NetworkModel snapshot.
// ✓ Invalid packet-loss/latency cannot enable Full-HD.
// ✓ Recommended profile is returned unmodifiable.
// ✓ Network snapshot churn is handled safely.
// ✓ No NetworkHelper access.
// ✓ No duplicate polling/timers/listeners.
// ✓ No PeerConnection lifecycle ownership.
// ✓ No ICE/signaling/recovery ownership.
// ✓ No media acquisition ownership.
// ✓ Shared NetworkOptimizer/NetworkManager are not reset.
// ✓ No UI/design changes.
//
// STATUS:
// BITRATE CONTROLLER FINALIZED.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 22
// lib/services/call/call_quality_monitor.dart
// ===========================================================