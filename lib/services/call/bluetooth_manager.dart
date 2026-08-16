import 'package:flutter/foundation.dart';

/// ===========================================================
/// JR CALL
/// File: bluetooth_manager.dart
/// Description:
/// Bluetooth Audio Device Manager
///
/// Used by:
/// - speaker_manager.dart
/// - audio_manager.dart
/// - ai_voice_engine.dart
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// ===========================================================

class BluetoothManager extends ChangeNotifier {
  bool _isAvailable = false;
  bool _isConnected = false;
  bool _isScanning = false;

  String? _deviceName;
  String? _deviceAddress;

  /// ==========================
  /// Getters
  /// ==========================

  bool get isAvailable => _isAvailable;

  bool get isConnected => _isConnected;

  bool get isScanning => _isScanning;

  String? get deviceName => _deviceName;

  String? get deviceAddress => _deviceAddress;

  /// ==========================
  /// Start Scan
  /// ==========================

  Future<void> startScan() async {
    _isScanning = true;
    notifyListeners();

    // Future:
    // flutter_blue_plus scan

    await Future.delayed(const Duration(seconds: 2));

    _isAvailable = true;

    _isScanning = false;

    notifyListeners();
  }

  /// ==========================
  /// Stop Scan
  /// ==========================

  Future<void> stopScan() async {
    _isScanning = false;
    notifyListeners();
  }

  /// ==========================
  /// Connect Device
  /// ==========================

  Future<void> connect({required String name, required String address}) async {
    _deviceName = name;
    _deviceAddress = address;

    _isConnected = true;
    _isAvailable = true;

    notifyListeners();
  }

  /// ==========================
  /// Disconnect Device
  /// ==========================

  Future<void> disconnect() async {
    _deviceName = null;
    _deviceAddress = null;

    _isConnected = false;

    notifyListeners();
  }

  /// ==========================
  /// Toggle Connection
  /// ==========================

  Future<void> toggleConnection({
    required String name,
    required String address,
  }) async {
    if (_isConnected) {
      await disconnect();
    } else {
      await connect(name: name, address: address);
    }
  }

  /// ==========================
  /// Refresh Status
  /// ==========================

  Future<void> refresh() async {
    notifyListeners();
  }

  /// ==========================
  /// Reset
  /// ==========================

  Future<void> reset() async {
    _isAvailable = false;
    _isConnected = false;
    _isScanning = false;

    _deviceName = null;
    _deviceAddress = null;

    notifyListeners();
  }
}
