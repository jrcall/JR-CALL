// ===========================================================
// JR CALL
// File: stun_turn_service.dart
// Location: lib/services/call/stun_turn_service.dart
//
// Description:
// Production STUN/TURN configuration and credential service.
//
// Responsibilities:
// - Provide compile-safe WebRTC ICE configuration
// - Load short-lived TURN credentials from secure backend
// - Authenticate TURN backend requests with Firebase ID token
// - Never block Call Engine when TURN backend is temporarily down
// - Fall back safely to STUN-only connectivity
// - Cache TURN credentials until safe expiry
// - Prevent duplicate concurrent credential requests
// - Support optional TURN health endpoint
// - Support regional TURN routing
// - Create RTCPeerConnection for existing manager architecture
// - Provide audio/video media constraints
//
// Architecture:
// FirebaseAuth
//      ↓
// StunTurnService
//      ↓
// Secure Cloud Function
//      ↓
// TURN Infrastructure
//
// Important:
// TURN credentials must NEVER be hard-coded in the application.
// ===========================================================

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:http/http.dart' as http;

class StunTurnService {
  // ===========================================================
  // Singleton
  // ===========================================================

  StunTurnService._() {
    _startRefreshTimer();
  }

  static final StunTurnService instance = StunTurnService._();

  // ===========================================================
  // Firebase Authentication
  // ===========================================================

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ===========================================================
  // Default STUN
  // ===========================================================

  static const List<String> _defaultStunServers = [
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
    'stun:stun2.l.google.com:19302',
  ];

  // ===========================================================
  // Region
  // ===========================================================

  static const List<String> supportedRegions = [
    'Asia',
    'Europe',
    'America',
    'Middle East',
  ];

  String _currentRegion = 'Asia';

  String get currentRegion => _currentRegion;

  // ===========================================================
  // Backend Configuration
  // ===========================================================

  /// Firebase Project ID:
  /// jr-call
  ///
  /// Cloud Function:
  /// getTurnCredentials
  ///
  /// Authentication:
  /// Authorization: Bearer `Firebase ID Token`
  static const String _defaultBackendTokenUrl =
      'https://us-central1-jr-call.cloudfunctions.net/getTurnCredentials';

  /// Optional TURN health endpoint.
  ///
  /// Kept empty until an actual health endpoint is deployed.
  static const String _defaultHealthProbeUrl = '';

  String _backendTokenUrl = _defaultBackendTokenUrl;

  String _healthProbeUrl = _defaultHealthProbeUrl;

  String get backendTokenUrl => _backendTokenUrl;

  String get healthProbeUrl => _healthProbeUrl;

  // ===========================================================
  // Runtime State
  // ===========================================================

  Map<String, dynamic>? _cachedConfiguration;

  DateTime? _tokenExpiryTime;

  bool _isPrimaryHealthy = true;

  bool _lastCredentialLoadSucceeded = false;

  bool _disposed = false;

  // ===========================================================
  // Refresh / Concurrency
  // ===========================================================

  Timer? _tokenRefreshTimer;

  Future<Map<String, dynamic>>? _activeLoadFuture;

  static const Duration _requestTimeout = Duration(seconds: 6);

  static const Duration _fallbackCacheDuration = Duration(minutes: 10);

  static const Duration _refreshCheckInterval = Duration(minutes: 5);

  // ===========================================================
  // Network Callbacks
  // ===========================================================

  bool Function()? networkConnectionChecker;

  String Function()? networkQualityTierChecker;

  // ===========================================================
  // Public State
  // ===========================================================

  bool get hasCachedConfiguration => _cachedConfiguration != null;

  bool get hasTurnCredentials => _lastCredentialLoadSucceeded;

  bool get isPrimaryHealthy => _isPrimaryHealthy;

  bool get isUsingStunFallback => !_lastCredentialLoadSucceeded;

  DateTime? get tokenExpiryTime => _tokenExpiryTime;

  // ===========================================================
  // Backend Configuration API
  // ===========================================================

  void configureBackend({String? tokenUrl, String? healthUrl}) {
    final normalizedTokenUrl = tokenUrl?.trim();

    final normalizedHealthUrl = healthUrl?.trim();

    if (normalizedTokenUrl != null) {
      _backendTokenUrl = normalizedTokenUrl;
    }

    if (normalizedHealthUrl != null) {
      _healthProbeUrl = normalizedHealthUrl;
    }

    clearCache();
  }

  // ===========================================================
  // Region
  // ===========================================================

  void setRegion(String region) {
    final normalized = region.trim();

    if (!supportedRegions.contains(normalized)) {
      return;
    }

    if (_currentRegion == normalized) {
      return;
    }

    _currentRegion = normalized;

    clearCache();

    unawaited(loadTokenInitialization());
  }

  // ===========================================================
  // Refresh Timer
  // ===========================================================

  void _startRefreshTimer() {
    _tokenRefreshTimer?.cancel();

    _tokenRefreshTimer = Timer.periodic(_refreshCheckInterval, (_) {
      if (_disposed) {
        return;
      }

      final expiry = _tokenExpiryTime;

      if (expiry == null) {
        return;
      }

      final refreshAt = expiry.subtract(const Duration(minutes: 5));

      if (DateTime.now().isAfter(refreshAt)) {
        unawaited(refreshConfiguration());
      }
    });
  }

  // ===========================================================
  // Cache
  // ===========================================================

  void clearCache() {
    _cachedConfiguration = null;
    _tokenExpiryTime = null;

    _lastCredentialLoadSucceeded = false;
  }

  // ===========================================================
  // Main Credential Loader
  // ===========================================================

  Future<Map<String, dynamic>> loadTurnCredential() {
    final cached = _cachedConfiguration;

    final expiry = _tokenExpiryTime;

    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return Future<Map<String, dynamic>>.value(cached);
    }

    final active = _activeLoadFuture;

    if (active != null) {
      return active;
    }

    final future = _loadTurnCredentialInternal();

    _activeLoadFuture = future;

    return future.whenComplete(() {
      if (identical(_activeLoadFuture, future)) {
        _activeLoadFuture = null;
      }
    });
  }

  Future<Map<String, dynamic>> _loadTurnCredentialInternal() async {
    if (_disposed) {
      return _buildFallbackConfiguration();
    }

    final tokenUrl = _backendTokenUrl.trim();

    if (tokenUrl.isEmpty) {
      return _activateStunFallback(
        reason: 'TURN credential backend is not configured.',
      );
    }

    try {
      await performRealHealthCheckProbe();

      final tokenData = await _fetchWithRetry();

      final configuration = _buildProductionConfiguration(tokenData);

      _cachedConfiguration = configuration;

      _tokenExpiryTime = _resolveSafeExpiry(tokenData['expiresIn']);

      _lastCredentialLoadSucceeded = true;

      debugPrint(
        'StunTurnService: TURN credentials loaded '
        'for region $_currentRegion.',
      );

      return configuration;
    } catch (error, stackTrace) {
      _logStructuredError(
        'TURN credential loading failed; '
        'STUN fallback activated',
        error,
        stackTrace,
      );

      return _activateStunFallback(reason: error.toString());
    }
  }

  // ===========================================================
  // Retry
  // ===========================================================

  Future<Map<String, dynamic>> _fetchWithRetry() async {
    const maxAttempts = 3;

    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _fetchTokensFromRealBackendAPI();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;

        final retryable = _isRetryableNetworkError(error);

        _logStructuredError(
          'TURN token attempt '
          '$attempt/$maxAttempts failed',
          error,
          stackTrace,
        );

        if (!retryable || attempt >= maxAttempts) {
          break;
        }

        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    final failure = lastError ?? StateError('Unknown TURN credential error.');

    if (lastStackTrace != null) {
      Error.throwWithStackTrace(failure, lastStackTrace);
    }

    throw failure;
  }

  bool _isRetryableNetworkError(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }

    final typeName = error.runtimeType.toString().toLowerCase();

    return typeName.contains('socket') ||
        typeName.contains('network') ||
        typeName.contains('connection');
  }

  // ===========================================================
  // Firebase ID Token
  // ===========================================================

  Future<String> _getFirebaseIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'Firebase authentication is required '
        'before requesting TURN credentials.',
      );
    }

    final token = await user.getIdToken(forceRefresh);

    if (token == null || token.trim().isEmpty) {
      throw StateError('Firebase ID token is unavailable.');
    }

    return token.trim();
  }

  // ===========================================================
  // Backend Request
  // ===========================================================

  Future<Map<String, dynamic>> _fetchTokensFromRealBackendAPI() async {
    final normalizedUrl = _backendTokenUrl.trim();

    if (normalizedUrl.isEmpty) {
      throw StateError('TURN backend URL is empty.');
    }

    final apiUrl = Uri.parse(
      normalizedUrl,
    ).replace(queryParameters: <String, String>{'region': _currentRegion});

    var idToken = await _getFirebaseIdToken();

    var response = await _performAuthenticatedRequest(
      apiUrl: apiUrl,
      idToken: idToken,
    );

    // The cached Firebase token may theoretically expire between
    // acquisition and backend verification.
    //
    // One forced refresh is allowed for HTTP 401 only.
    if (response.statusCode == 401) {
      idToken = await _getFirebaseIdToken(forceRefresh: true);

      response = await _performAuthenticatedRequest(
        apiUrl: apiUrl,
        idToken: idToken,
      );
    }

    if (response.statusCode != 200) {
      throw _TurnBackendException(
        statusCode: response.statusCode,
        message: _safeResponseMessage(response.body),
      );
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw FormatException(
        'TURN backend returned invalid JSON: '
        '$error',
      );
    }

    if (decoded is! Map) {
      throw const FormatException(
        'TURN backend response must be a JSON object.',
      );
    }

    final data = Map<String, dynamic>.from(decoded);

    // Supports both nested:
    //
    // {
    //   "data": {
    //      ...
    //   }
    // }
    //
    // and direct JSON responses.
    final nestedData = data['data'];

    if (nestedData is Map) {
      return Map<String, dynamic>.from(nestedData);
    }

    return data;
  }

  Future<http.Response> _performAuthenticatedRequest({
    required Uri apiUrl,
    required String idToken,
  }) {
    return http
        .get(
          apiUrl,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
        )
        .timeout(_requestTimeout);
  }

  String _safeResponseMessage(String body) {
    final normalized = body.trim();

    if (normalized.isEmpty) {
      return 'Empty response body.';
    }

    const maxLength = 300;

    if (normalized.length <= maxLength) {
      return normalized;
    }

    return '${normalized.substring(0, maxLength)}...';
  }

  // ===========================================================
  // Health Probe
  // ===========================================================

  Future<void> performRealHealthCheckProbe() async {
    final healthUrl = _healthProbeUrl.trim();

    if (healthUrl.isEmpty) {
      _isPrimaryHealthy = true;
      return;
    }

    try {
      final uri = Uri.parse(
        healthUrl,
      ).replace(queryParameters: <String, String>{'region': _currentRegion});

      final response = await http
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 3));

      _isPrimaryHealthy =
          response.statusCode >= 200 && response.statusCode < 300;
    } catch (error, stackTrace) {
      _isPrimaryHealthy = false;

      _logStructuredError('TURN health probe unavailable', error, stackTrace);
    }
  }

  // ===========================================================
  // TURN Payload Parsing
  // ===========================================================

  Map<String, dynamic> _buildProductionConfiguration(
    Map<String, dynamic> data,
  ) {
    final servers = <Map<String, dynamic>>[_buildStunEntry()];

    final rawIceServers = data['iceServers'];

    if (rawIceServers is List) {
      for (final rawServer in rawIceServers) {
        if (rawServer is! Map) {
          continue;
        }

        final server = Map<String, dynamic>.from(rawServer);

        final validated = _validateIceServer(server);

        if (validated != null) {
          servers.add(validated);
        }
      }
    }

    if (servers.length == 1) {
      _appendLegacyTurnServers(servers, data);
    }

    if (!_containsTurnServer(servers)) {
      throw const FormatException(
        'TURN backend response contains no '
        'valid TURN server.',
      );
    }

    return _baseConfiguration(servers);
  }

  void _appendLegacyTurnServers(
    List<Map<String, dynamic>> servers,
    Map<String, dynamic> data,
  ) {
    final primaryUrl = _readString(data['primaryTurnUrl']);

    final primaryUsername = _readString(data['primaryUsername']);

    final primaryCredential = _readString(data['primaryCredential']);

    final backupUrl = _readString(data['backupTurnUrl']);

    final backupUsername = _readString(data['backupUsername']);

    final backupCredential = _readString(data['backupCredential']);

    if (_isPrimaryHealthy &&
        primaryUrl != null &&
        primaryUsername != null &&
        primaryCredential != null) {
      servers.add(
        _buildTurnEntry(
          url: primaryUrl,
          username: primaryUsername,
          credential: primaryCredential,
        ),
      );
    }

    if (backupUrl != null &&
        backupUsername != null &&
        backupCredential != null) {
      servers.add(
        _buildTurnEntry(
          url: backupUrl,
          username: backupUsername,
          credential: backupCredential,
        ),
      );
    }
  }

  Map<String, dynamic>? _validateIceServer(Map<String, dynamic> server) {
    final rawUrls = server['urls'];

    final urls = <String>[];

    if (rawUrls is String) {
      final normalized = rawUrls.trim();

      if (normalized.isNotEmpty) {
        urls.add(normalized);
      }
    } else if (rawUrls is List) {
      for (final entry in rawUrls) {
        if (entry is String && entry.trim().isNotEmpty) {
          urls.add(entry.trim());
        }
      }
    }

    if (urls.isEmpty) {
      return null;
    }

    final containsTurn = urls.any((url) {
      final lower = url.toLowerCase();

      return lower.startsWith('turn:') || lower.startsWith('turns:');
    });

    if (!containsTurn) {
      return <String, dynamic>{'urls': urls};
    }

    final username = _readString(server['username']);

    final credential = _readString(server['credential']);

    if (username == null || credential == null) {
      return null;
    }

    return <String, dynamic>{
      'urls': urls,
      'username': username,
      'credential': credential,
    };
  }

  bool _containsTurnServer(List<Map<String, dynamic>> servers) {
    for (final server in servers) {
      final rawUrls = server['urls'];

      final urls = rawUrls is List ? rawUrls : <dynamic>[rawUrls];

      for (final rawUrl in urls) {
        if (rawUrl is! String) {
          continue;
        }

        final lower = rawUrl.toLowerCase();

        if (lower.startsWith('turn:') || lower.startsWith('turns:')) {
          return true;
        }
      }
    }

    return false;
  }

  String? _readString(dynamic value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  // ===========================================================
  // TURN URL
  // ===========================================================

  Map<String, dynamic> _buildTurnEntry({
    required String url,
    required String username,
    required String credential,
  }) {
    final normalizedUrl = url.trim();

    return <String, dynamic>{
      'urls': <String>[
        _withTransport(normalizedUrl, 'udp'),
        _withTransport(normalizedUrl, 'tcp'),
      ],
      'username': username,
      'credential': credential,
    };
  }

  String _withTransport(String url, String transport) {
    if (url.contains('transport=')) {
      return url;
    }

    final separator = url.contains('?') ? '&' : '?';

    return '$url'
        '${separator}transport=$transport';
  }

  // ===========================================================
  // Expiry
  // ===========================================================

  DateTime _resolveSafeExpiry(dynamic rawExpiresIn) {
    int? seconds;

    if (rawExpiresIn is num) {
      seconds = rawExpiresIn.toInt();
    } else if (rawExpiresIn is String) {
      seconds = int.tryParse(rawExpiresIn);
    }

    if (seconds == null || seconds <= 0) {
      return DateTime.now().add(const Duration(minutes: 10));
    }

    final refreshBuffer = seconds > 120
        ? 60
        : seconds > 30
        ? 15
        : 0;

    final safeSeconds = seconds - refreshBuffer;

    return DateTime.now().add(Duration(seconds: safeSeconds));
  }

  // ===========================================================
  // STUN Fallback
  // ===========================================================

  Map<String, dynamic> _activateStunFallback({required String reason}) {
    final fallback = _buildFallbackConfiguration();

    _cachedConfiguration = fallback;

    _tokenExpiryTime = DateTime.now().add(_fallbackCacheDuration);

    _lastCredentialLoadSucceeded = false;

    debugPrint(
      'StunTurnService: '
      'STUN fallback active. '
      'Reason: $reason',
    );

    return fallback;
  }

  Map<String, dynamic> _buildFallbackConfiguration() {
    return _baseConfiguration(<Map<String, dynamic>>[_buildStunEntry()]);
  }

  Map<String, dynamic> _buildStunEntry() {
    return <String, dynamic>{'urls': List<String>.from(_defaultStunServers)};
  }

  Map<String, dynamic> _baseConfiguration(
    List<Map<String, dynamic>> iceServers,
  ) {
    return <String, dynamic>{
      'iceServers': iceServers,
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'balanced',
      'rtcpMuxPolicy': 'require',
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 10,
    };
  }

  // ===========================================================
  // Configuration Getter
  // ===========================================================

  Map<String, dynamic> get configuration {
    final cached = _cachedConfiguration;

    if (cached != null) {
      return cached;
    }

    unawaited(loadTokenInitialization());

    return _buildFallbackConfiguration();
  }

  // ===========================================================
  // Peer Connection
  // ===========================================================

  Future<webrtc.RTCPeerConnection> createPeerConnection({
    Map<String, dynamic>? customConfig,
    Map<String, dynamic>? optionalConstraints,
  }) async {
    final finalConfiguration = customConfig ?? await loadTurnCredential();

    final constraints =
        optionalConstraints ??
        <String, dynamic>{
          'mandatory': <String, dynamic>{},
          'optional': <Map<String, dynamic>>[
            <String, dynamic>{'DtlsSrtpKeyAgreement': true},
          ],
        };

    return webrtc.createPeerConnection(finalConfiguration, constraints);
  }

  // ===========================================================
  // Refresh
  // ===========================================================

  Future<void> refreshConfiguration() async {
    if (_disposed) {
      return;
    }

    clearCache();

    await loadTurnCredential();
  }

  Future<void> loadTokenInitialization() async {
    if (_disposed) {
      return;
    }

    try {
      await loadTurnCredential();
    } catch (error, stackTrace) {
      _logStructuredError('TURN pre-warm failed', error, stackTrace);
    }
  }

  // ===========================================================
  // Audio Constraints
  // ===========================================================

  Map<String, dynamic> get audioConstraints {
    return <String, dynamic>{
      'audio': <String, dynamic>{
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'googEchoCancellation': true,
        'googAutoGainControl': true,
        'googNoiseSuppression': true,
        'googHighpassFilter': true,
        if (!kIsWeb) 'googTypingNoiseDetection': true,
        'channelCount': 1,
        'sampleRate': 48000,
      },
      'video': false,
    };
  }

  // ===========================================================
  // Adaptive Video Constraints
  // ===========================================================

  Map<String, dynamic> getVideoConstraints() {
    var quality = '720p';

    try {
      final connectionChecker = networkConnectionChecker;

      if (connectionChecker != null && !connectionChecker()) {
        quality = '360p';
      } else {
        final tierChecker = networkQualityTierChecker;

        if (tierChecker != null) {
          quality = tierChecker().trim().toLowerCase();
        }
      }
    } catch (error, stackTrace) {
      _logStructuredError(
        'Adaptive video quality lookup failed',
        error,
        stackTrace,
      );

      quality = '720p';
    }

    var width = 1280;
    var height = 720;
    var fps = 30;

    switch (quality) {
      case '360p':
        width = 640;
        height = 360;
        fps = 15;
        break;

      case '480p':
        width = 854;
        height = 480;
        fps = 24;
        break;

      case '1080p':
        width = 1920;
        height = 1080;
        fps = 30;
        break;

      case '720p':
      default:
        width = 1280;
        height = 720;
        fps = 30;
        break;
    }

    return <String, dynamic>{
      'audio': <String, dynamic>{
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': <String, dynamic>{
        'width': <String, dynamic>{'ideal': width},
        'height': <String, dynamic>{'ideal': height},
        'aspectRatio': <String, dynamic>{'ideal': 16 / 9},
        'frameRate': <String, dynamic>{'ideal': fps, 'max': fps},
        'facingMode': 'user',
      },
    };
  }

  Map<String, dynamic> get videoConstraints => getVideoConstraints();

  Map<String, dynamic> get fullHDConstraints {
    return <String, dynamic>{
      'audio': audioConstraints['audio'],
      'video': <String, dynamic>{
        'width': <String, dynamic>{'ideal': 1920},
        'height': <String, dynamic>{'ideal': 1080},
        'aspectRatio': <String, dynamic>{'ideal': 16 / 9},
        'frameRate': <String, dynamic>{'ideal': 30, 'max': 30},
        'facingMode': 'user',
      },
    };
  }

  Map<String, dynamic> get lowBandwidthConstraints {
    return <String, dynamic>{
      'audio': audioConstraints['audio'],
      'video': <String, dynamic>{
        'width': <String, dynamic>{'ideal': 640},
        'height': <String, dynamic>{'ideal': 360},
        'aspectRatio': <String, dynamic>{'ideal': 16 / 9},
        'frameRate': <String, dynamic>{'ideal': 15, 'max': 15},
        'facingMode': 'user',
      },
    };
  }

  // ===========================================================
  // Media Helpers
  // ===========================================================

  Future<webrtc.MediaStream> createAudioStream() {
    return webrtc.navigator.mediaDevices.getUserMedia(audioConstraints);
  }

  Future<webrtc.MediaStream> createVideoStream() {
    return webrtc.navigator.mediaDevices.getUserMedia(getVideoConstraints());
  }

  Future<webrtc.MediaStream> createFullHDStream() {
    return webrtc.navigator.mediaDevices.getUserMedia(fullHDConstraints);
  }

  Future<webrtc.MediaStream> createLowBandwidthStream() {
    return webrtc.navigator.mediaDevices.getUserMedia(lowBandwidthConstraints);
  }

  // ===========================================================
  // Logging
  // ===========================================================

  void _logStructuredError(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      '[StunTurnService] '
      '$message: $error',
    );

    debugPrintStack(label: 'StunTurnService', stackTrace: stackTrace);
  }

  // ===========================================================
  // Dispose
  // ===========================================================

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;

    _activeLoadFuture = null;

    _cachedConfiguration = null;
    _tokenExpiryTime = null;

    _lastCredentialLoadSucceeded = false;

    networkConnectionChecker = null;
    networkQualityTierChecker = null;
  }
}

// ===========================================================
// Private TURN Backend Exception
// ===========================================================

class _TurnBackendException implements Exception {
  final int statusCode;
  final String message;

  const _TurnBackendException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() {
    return 'TURN backend HTTP '
        '$statusCode: $message';
  }
}
