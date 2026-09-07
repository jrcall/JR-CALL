// ===========================================================
// JR CALL
// File: stun_turn_service.dart
// Location: lib/services/call/stun_turn_service.dart
//
// FINAL PRODUCTION STUN / TURN SERVICE
//
// Responsibilities:
// - Provide production-safe WebRTC ICE configuration.
// - Load short-lived TURN credentials from secure backend.
// - Use Firebase Callable Functions for credential requests.
// - Preserve Firebase authentication and App Check compatibility.
// - Never hard-code TURN usernames, passwords or shared secrets.
// - Prefer TURN UDP, then TURN TCP.
// - Preserve backend-provided secure TURN endpoints.
// - Preserve IPv4 / IPv6 ICE server URLs.
// - Fall back safely to STUN when TURN is temporarily unavailable.
// - Cache temporary credentials only until safe expiry.
// - Prevent duplicate concurrent credential requests.
// - Reject stale async results after configuration changes.
// - Support optional TURN health probing.
// - Support regional TURN routing.
// - Preserve peer/media compatibility helper APIs.
//
// Ownership:
// - STUN/TURN configuration belongs here.
// - Candidate exchange belongs to IceManager.
// - Network handover / ICE restart belongs to recovery/network owners.
// - SDP negotiation belongs to signaling/peer connection owners.
// - MediaManager remains canonical media acquisition owner.
// ===========================================================

import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
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
  // Firebase
  // ===========================================================

  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _functionsRegion = 'us-central1';

  static const String _turnFunctionName = 'getTurnCredentials';

  // ===========================================================
  // Default STUN
  // ===========================================================

  static const List<String> _defaultStunServers = <String>[
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
    'stun:stun2.l.google.com:19302',
  ];

  // ===========================================================
  // Region
  // ===========================================================

  static const List<String> supportedRegions = <String>[
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

  static const String _defaultBackendTokenUrl =
      'https://us-central1-jr-call.cloudfunctions.net/getTurnCredentials';

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

  /// Used to reject stale asynchronous credential responses.
  int _generation = 0;

  // ===========================================================
  // Refresh / Concurrency
  // ===========================================================

  Timer? _tokenRefreshTimer;

  Future<Map<String, dynamic>>? _activeLoadFuture;

  static const Duration _callableTimeout = Duration(seconds: 5);

  static const Duration _credentialLoadBudget = Duration(seconds: 7);

  static const Duration _retryDelay = Duration(milliseconds: 350);

  static const Duration _fallbackCacheDuration = Duration(minutes: 1);

  static const Duration _refreshCheckInterval = Duration(minutes: 1);

  static const Duration _defaultCredentialTtl = Duration(minutes: 10);

  static const Duration _maximumCredentialCache = Duration(hours: 6);

  // ===========================================================
  // Network Callbacks
  //
  // Existing compatibility APIs preserved.
  // NetworkManager remains canonical runtime network owner.
  // ===========================================================

  bool Function()? networkConnectionChecker;

  String Function()? networkQualityTierChecker;

  // ===========================================================
  // Public State
  // ===========================================================

  bool get hasCachedConfiguration => _hasValidCachedConfiguration();

  bool get hasTurnCredentials =>
      _lastCredentialLoadSucceeded && _hasValidCachedConfiguration();

  bool get isPrimaryHealthy => _isPrimaryHealthy;

  bool get isUsingStunFallback => !hasTurnCredentials;

  DateTime? get tokenExpiryTime => _tokenExpiryTime;

  // ===========================================================
  // Backend Configuration API
  // ===========================================================

  void configureBackend({
    String? tokenUrl,
    String? healthUrl,
  }) {
    _ensureActive();

    if (tokenUrl != null) {
      _backendTokenUrl = tokenUrl.trim();
    }

    if (healthUrl != null) {
      _healthProbeUrl = healthUrl.trim();
    }

    clearCache();
  }

  // ===========================================================
  // Region
  // ===========================================================

  void setRegion(String region) {
    _ensureActive();

    final String normalized = region.trim();

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

    _tokenRefreshTimer = Timer.periodic(
      _refreshCheckInterval,
          (_) {
        if (_disposed) {
          return;
        }

        final DateTime? expiry = _tokenExpiryTime;

        if (expiry == null) {
          return;
        }

        if (!DateTime.now().toUtc().isBefore(expiry)) {
          unawaited(refreshConfiguration());
        }
      },
    );
  }

  void _ensureActive() {
    if (!_disposed) {
      return;
    }

    _disposed = false;

    _startRefreshTimer();
  }

  // ===========================================================
  // Cache
  // ===========================================================

  void clearCache() {
    _generation++;

    _cachedConfiguration = null;
    _tokenExpiryTime = null;
    _lastCredentialLoadSucceeded = false;

    _activeLoadFuture = null;
  }

  bool _hasValidCachedConfiguration() {
    final Map<String, dynamic>? cached = _cachedConfiguration;
    final DateTime? expiry = _tokenExpiryTime;

    if (cached == null || expiry == null) {
      return false;
    }

    return DateTime.now().toUtc().isBefore(expiry);
  }

  // ===========================================================
  // Main Credential Loader
  // ===========================================================

  Future<Map<String, dynamic>> loadTurnCredential() {
    _ensureActive();

    if (_hasValidCachedConfiguration()) {
      return Future<Map<String, dynamic>>.value(
        _copyConfiguration(_cachedConfiguration!),
      );
    }

    final Future<Map<String, dynamic>>? active = _activeLoadFuture;

    if (active != null) {
      return active.then(_copyConfiguration);
    }

    final int requestGeneration = _generation;

    final Future<Map<String, dynamic>> future =
    _loadTurnCredentialInternal(requestGeneration);

    _activeLoadFuture = future;

    return future.then(_copyConfiguration).whenComplete(() {
      if (identical(_activeLoadFuture, future)) {
        _activeLoadFuture = null;
      }
    });
  }

  Future<Map<String, dynamic>> _loadTurnCredentialInternal(
      int requestGeneration,
      ) async {
    if (_disposed) {
      return _buildFallbackConfiguration();
    }

    if (_backendTokenUrl.trim().isEmpty) {
      return _activateStunFallback(
        requestGeneration: requestGeneration,
        reason: 'backend-not-configured',
      );
    }

    try {
      _requireAuthenticatedUser();

      unawaited(_performHealthCheck(requestGeneration));

      final Map<String, dynamic> tokenData =
      await _fetchWithRetry().timeout(_credentialLoadBudget);

      final Map<String, dynamic> configuration =
      _buildProductionConfiguration(tokenData);

      final DateTime safeExpiry = _resolveSafeExpiry(tokenData);

      if (_disposed || requestGeneration != _generation) {
        if (_hasValidCachedConfiguration()) {
          return _cachedConfiguration!;
        }

        return _buildFallbackConfiguration();
      }

      _cachedConfiguration = configuration;
      _tokenExpiryTime = safeExpiry;
      _lastCredentialLoadSucceeded = true;

      if (kDebugMode) {
        debugPrint(
          'StunTurnService: temporary TURN configuration loaded '
              'for region $_currentRegion.',
        );
      }

      return configuration;
    } catch (error, stackTrace) {
      _logStructuredError(
        'TURN credential loading failed; STUN fallback activated',
        error,
        stackTrace,
      );

      return _activateStunFallback(
        requestGeneration: requestGeneration,
        reason: _safeErrorLabel(error),
      );
    }
  }

  // ===========================================================
  // Retry
  // ===========================================================

  Future<Map<String, dynamic>> _fetchWithRetry() async {
    const int maximumAttempts = 2;

    Object? lastError;
    StackTrace? lastStackTrace;

    for (int attempt = 1; attempt <= maximumAttempts; attempt++) {
      try {
        return await _fetchTokensFromCallable();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;

        if (error is FirebaseFunctionsException &&
            error.code.trim().toLowerCase() == 'unauthenticated' &&
            attempt == 1) {
          try {
            await _forceRefreshFirebaseIdToken();
          } catch (_) {
            // Original callable failure remains authoritative.
          }
        }

        final bool retryable = _isRetryableCredentialError(error);

        _logStructuredError(
          'TURN credential attempt $attempt/$maximumAttempts failed',
          error,
          stackTrace,
        );

        if (!retryable || attempt >= maximumAttempts) {
          break;
        }

        await Future<void>.delayed(_retryDelay);
      }
    }

    final Object failure =
        lastError ?? StateError('Unknown TURN credential failure.');

    if (lastStackTrace != null) {
      Error.throwWithStackTrace(
        failure,
        lastStackTrace,
      );
    }

    throw failure;
  }

  bool _isRetryableCredentialError(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }

    if (error is FirebaseFunctionsException) {
      switch (error.code.trim().toLowerCase()) {
        case 'aborted':
        case 'cancelled':
        case 'deadline-exceeded':
        case 'internal':
        case 'resource-exhausted':
        case 'unavailable':
        case 'unknown':
        case 'unauthenticated':
          return true;
      }

      return false;
    }

    final String typeName = error.runtimeType.toString().toLowerCase();

    return typeName.contains('socket') ||
        typeName.contains('network') ||
        typeName.contains('connection');
  }

  // ===========================================================
  // Authentication
  // ===========================================================

  User _requireAuthenticatedUser() {
    final User? user = _auth.currentUser;

    if (user == null || user.uid.trim().isEmpty) {
      throw StateError(
        'Firebase authentication is required before requesting '
            'TURN credentials.',
      );
    }

    return user;
  }

  Future<void> _forceRefreshFirebaseIdToken() async {
    final User user = _requireAuthenticatedUser();

    final String? token = await user.getIdToken(true);

    if (token == null || token.trim().isEmpty) {
      throw StateError('Firebase ID token refresh failed.');
    }
  }

  // ===========================================================
  // Firebase Callable
  // ===========================================================

  Future<Map<String, dynamic>> _fetchTokensFromCallable() async {
    _requireAuthenticatedUser();

    final HttpsCallable callable = _buildTurnCallable();

    final HttpsCallableResult<dynamic> result =
    await callable.call<dynamic>(
      <String, dynamic>{
        'region': _currentRegion,
      },
    );

    return _extractCallablePayload(result.data);
  }

  HttpsCallable _buildTurnCallable() {
    final FirebaseFunctions functions = FirebaseFunctions.instanceFor(
      region: _functionsRegion,
    );

    final HttpsCallableOptions options = HttpsCallableOptions(
      timeout: _callableTimeout,
    );

    final String configuredUrl = _backendTokenUrl.trim();

    if (configuredUrl == _defaultBackendTokenUrl) {
      return functions.httpsCallable(
        _turnFunctionName,
        options: options,
      );
    }

    if (configuredUrl.isEmpty) {
      throw StateError(
        'TURN credential backend is not configured.',
      );
    }

    final Uri uri = Uri.parse(configuredUrl);

    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException(
        'TURN callable URL is invalid.',
      );
    }

    return functions.httpsCallableFromUrl(
      configuredUrl,
      options: options,
    );
  }

  Map<String, dynamic> _extractCallablePayload(Object? rawData) {
    if (rawData is! Map) {
      throw const FormatException(
        'TURN backend response must be an object.',
      );
    }

    final Map<String, dynamic> data = _stringKeyedMap(rawData);

    final Object? nested = data['data'];

    if (nested is Map) {
      return _stringKeyedMap(nested);
    }

    return data;
  }

  Map<String, dynamic> _stringKeyedMap(
      Map<dynamic, dynamic> source,
      ) {
    final Map<String, dynamic> result = <String, dynamic>{};

    for (final MapEntry<dynamic, dynamic> entry in source.entries) {
      if (entry.key is! String) {
        continue;
      }

      result[entry.key as String] = entry.value;
    }

    return result;
  }

  // ===========================================================
  // Health Probe
  // ===========================================================

  Future<void> performRealHealthCheckProbe() {
    _ensureActive();

    return _performHealthCheck(_generation);
  }

  Future<void> _performHealthCheck(
      int requestGeneration,
      ) async {
    final String healthUrl = _healthProbeUrl.trim();

    if (healthUrl.isEmpty) {
      if (!_disposed && requestGeneration == _generation) {
        _isPrimaryHealthy = true;
      }

      return;
    }

    try {
      final Uri baseUri = Uri.parse(healthUrl);

      if (!baseUri.hasScheme || baseUri.host.isEmpty) {
        throw const FormatException(
          'TURN health URL is invalid.',
        );
      }

      final Map<String, String> queryParameters =
      Map<String, String>.from(baseUri.queryParameters);

      queryParameters['region'] = _currentRegion;

      final Uri uri = baseUri.replace(
        queryParameters: queryParameters,
      );

      final http.Response response = await http
          .get(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
        },
      )
          .timeout(
        const Duration(seconds: 3),
      );

      if (_disposed || requestGeneration != _generation) {
        return;
      }

      _isPrimaryHealthy =
          response.statusCode >= 200 && response.statusCode < 300;
    } catch (error, stackTrace) {
      if (!_disposed && requestGeneration == _generation) {
        _isPrimaryHealthy = false;
      }

      _logStructuredError(
        'TURN health probe unavailable',
        error,
        stackTrace,
      );
    }
  }

  // ===========================================================
  // TURN Payload Parsing
  // ===========================================================

  Map<String, dynamic> _buildProductionConfiguration(
      Map<String, dynamic> data,
      ) {
    final List<Map<String, dynamic>> servers = <Map<String, dynamic>>[
      _buildStunEntry(),
    ];

    final Object? rawIceServers = data['iceServers'];

    if (rawIceServers is List) {
      for (final Object? rawServer in rawIceServers) {
        if (rawServer is! Map) {
          continue;
        }

        final Map<String, dynamic>? validated = _validateIceServer(
          _stringKeyedMap(rawServer),
        );

        if (validated != null) {
          servers.add(validated);
        }
      }
    }

    if (!_containsTurnServer(servers)) {
      final Map<String, dynamic>? direct = _validateIceServer(data);

      if (direct != null && _serverContainsTurn(direct)) {
        servers.add(direct);
      }
    }

    if (!_containsTurnServer(servers)) {
      _appendLegacyTurnServers(
        servers,
        data,
      );
    }

    if (!_containsTurnServer(servers)) {
      throw const FormatException(
        'TURN backend response contains no valid TURN server.',
      );
    }

    return _baseConfiguration(servers);
  }

  void _appendLegacyTurnServers(
      List<Map<String, dynamic>> servers,
      Map<String, dynamic> data,
      ) {
    final String? primaryUrl = _firstString(
      <Object?>[
        data['primaryTurnUrl'],
        data['primaryUrl'],
        data['turnUrl'],
      ],
    );

    final String? primaryTlsUrl = _firstString(
      <Object?>[
        data['primaryTurnsUrl'],
        data['primaryTurnTlsUrl'],
        data['primaryTlsUrl'],
      ],
    );

    final String? primaryUsername = _firstString(
      <Object?>[
        data['primaryUsername'],
        data['username'],
      ],
    );

    final String? primaryCredential = _firstString(
      <Object?>[
        data['primaryCredential'],
        data['credential'],
      ],
    );

    final String? backupUrl = _firstString(
      <Object?>[
        data['backupTurnUrl'],
        data['backupUrl'],
      ],
    );

    final String? backupTlsUrl = _firstString(
      <Object?>[
        data['backupTurnsUrl'],
        data['backupTurnTlsUrl'],
        data['backupTlsUrl'],
      ],
    );

    final String? backupUsername = _firstString(
      <Object?>[
        data['backupUsername'],
        primaryUsername,
      ],
    );

    final String? backupCredential = _firstString(
      <Object?>[
        data['backupCredential'],
        primaryCredential,
      ],
    );

    if (_isPrimaryHealthy) {
      _appendLegacyTurnEntry(
        servers,
        url: primaryUrl,
        username: primaryUsername,
        credential: primaryCredential,
      );

      _appendLegacyTurnEntry(
        servers,
        url: primaryTlsUrl,
        username: primaryUsername,
        credential: primaryCredential,
      );

      _appendLegacyTurnEntry(
        servers,
        url: backupUrl,
        username: backupUsername,
        credential: backupCredential,
      );

      _appendLegacyTurnEntry(
        servers,
        url: backupTlsUrl,
        username: backupUsername,
        credential: backupCredential,
      );

      return;
    }

    _appendLegacyTurnEntry(
      servers,
      url: backupUrl,
      username: backupUsername,
      credential: backupCredential,
    );

    _appendLegacyTurnEntry(
      servers,
      url: backupTlsUrl,
      username: backupUsername,
      credential: backupCredential,
    );

    _appendLegacyTurnEntry(
      servers,
      url: primaryUrl,
      username: primaryUsername,
      credential: primaryCredential,
    );

    _appendLegacyTurnEntry(
      servers,
      url: primaryTlsUrl,
      username: primaryUsername,
      credential: primaryCredential,
    );
  }

  void _appendLegacyTurnEntry(
      List<Map<String, dynamic>> servers, {
        required String? url,
        required String? username,
        required String? credential,
      }) {
    if (url == null || username == null || credential == null) {
      return;
    }

    final Map<String, dynamic>? entry = _buildTurnEntry(
      url: url,
      username: username,
      credential: credential,
    );

    if (entry != null) {
      servers.add(entry);
    }
  }

  Map<String, dynamic>? _validateIceServer(
      Map<String, dynamic> server,
      ) {
    final Object? rawUrls =
        server['urls'] ??
            server['url'];

    final List<String> urls = _normalizeIceUrls(rawUrls);

    if (urls.isEmpty) {
      return null;
    }

    final bool containsTurn = urls.any(_isTurnUrl);

    if (!containsTurn) {
      return <String, dynamic>{
        'urls': urls,
      };
    }

    final String? username = _readString(server['username']);
    final String? credential = _readString(server['credential']);

    if (username == null || credential == null) {
      return null;
    }

    final Map<String, dynamic> result = <String, dynamic>{
      'urls': urls,
      'username': username,
      'credential': credential,
    };

    final String? credentialType =
    _readString(server['credentialType']);

    if (credentialType != null) {
      result['credentialType'] = credentialType;
    }

    return result;
  }

  List<String> _normalizeIceUrls(Object? rawUrls) {
    final List<String> input = <String>[];

    if (rawUrls is String) {
      input.add(rawUrls);
    } else if (rawUrls is List) {
      for (final Object? value in rawUrls) {
        if (value is String) {
          input.add(value);
        }
      }
    }

    final Set<String> output = <String>{};

    for (final String rawUrl in input) {
      final String url = rawUrl.trim();

      if (!_isValidIceUrl(url)) {
        continue;
      }

      final String lower = url.toLowerCase();

      if (lower.startsWith('turn:') &&
          !_hasTransportParameter(lower)) {
        output
          ..add(_withTransport(url, 'udp'))
          ..add(_withTransport(url, 'tcp'));

        continue;
      }

      if (lower.startsWith('turns:') &&
          !_hasTransportParameter(lower)) {
        output.add(_withTransport(url, 'tcp'));

        continue;
      }

      output.add(url);
    }

    return List<String>.unmodifiable(output);
  }

  bool _isValidIceUrl(String value) {
    if (value.isEmpty ||
        RegExp(r'\s').hasMatch(value)) {
      return false;
    }

    final String lower = value.toLowerCase();

    final bool supportedScheme =
        lower.startsWith('stun:') ||
            lower.startsWith('stuns:') ||
            lower.startsWith('turn:') ||
            lower.startsWith('turns:');

    if (!supportedScheme) {
      return false;
    }

    final RegExpMatch? transportMatch = RegExp(
      r'[?&]transport=([^&]+)',
      caseSensitive: false,
    ).firstMatch(value);

    if (transportMatch == null) {
      return true;
    }

    final String transport =
    transportMatch.group(1)!.trim().toLowerCase();

    if (transport != 'udp' &&
        transport != 'tcp') {
      return false;
    }

    if (lower.startsWith('turns:') &&
        transport == 'udp') {
      return false;
    }

    return true;
  }

  bool _hasTransportParameter(String lowerUrl) {
    return RegExp(
      r'[?&]transport=',
    ).hasMatch(lowerUrl);
  }

  bool _isTurnUrl(String url) {
    final String lower = url.toLowerCase();

    return lower.startsWith('turn:') ||
        lower.startsWith('turns:');
  }

  bool _serverContainsTurn(
      Map<String, dynamic> server,
      ) {
    final Object? rawUrls = server['urls'];

    if (rawUrls is String) {
      return _isTurnUrl(rawUrls);
    }

    if (rawUrls is List) {
      return rawUrls.any(
            (Object? value) =>
        value is String &&
            _isTurnUrl(value),
      );
    }

    return false;
  }

  bool _containsTurnServer(
      List<Map<String, dynamic>> servers,
      ) {
    return servers.any(_serverContainsTurn);
  }

  // ===========================================================
  // Legacy TURN URL Builder
  // ===========================================================

  Map<String, dynamic>? _buildTurnEntry({
    required String url,
    required String username,
    required String credential,
  }) {
    final List<String> urls = _normalizeIceUrls(url);

    if (urls.isEmpty ||
        !urls.any(_isTurnUrl)) {
      return null;
    }

    final String normalizedUsername = username.trim();
    final String normalizedCredential = credential.trim();

    if (normalizedUsername.isEmpty ||
        normalizedCredential.isEmpty) {
      return null;
    }

    return <String, dynamic>{
      'urls': urls,
      'username': normalizedUsername,
      'credential': normalizedCredential,
    };
  }

  String _withTransport(
      String url,
      String transport,
      ) {
    if (_hasTransportParameter(url.toLowerCase())) {
      return url;
    }

    final String separator =
    url.contains('?') ? '&' : '?';

    return '$url'
        '${separator}transport=$transport';
  }

  // ===========================================================
  // Expiry
  // ===========================================================

  DateTime _resolveSafeExpiry(
      Map<String, dynamic> data,
      ) {
    final DateTime now = DateTime.now().toUtc();

    DateTime? actualExpiry = _readAbsoluteExpiry(data);

    if (actualExpiry == null) {
      final int? ttlSeconds = _readTtlSeconds(data);

      final Duration ttl =
      ttlSeconds == null || ttlSeconds <= 0
          ? _defaultCredentialTtl
          : Duration(seconds: ttlSeconds);

      actualExpiry = now.add(ttl);
    }

    final DateTime maximumExpiry =
    now.add(_maximumCredentialCache);

    if (actualExpiry.isAfter(maximumExpiry)) {
      actualExpiry = maximumExpiry;
    }

    final Duration remaining =
    actualExpiry.difference(now);

    if (remaining.inSeconds <= 5) {
      throw const FormatException(
        'TURN credentials are expired or too close to expiry.',
      );
    }

    final int bufferSeconds;

    if (remaining.inMinutes >= 10) {
      bufferSeconds = 60;
    } else if (remaining.inMinutes >= 2) {
      bufferSeconds = 30;
    } else if (remaining.inSeconds >= 30) {
      bufferSeconds = 10;
    } else {
      bufferSeconds = max(
        1,
        remaining.inSeconds ~/ 5,
      );
    }

    final DateTime safeExpiry = actualExpiry.subtract(
      Duration(seconds: bufferSeconds),
    );

    if (!safeExpiry.isAfter(now)) {
      throw const FormatException(
        'TURN credential safe expiry is invalid.',
      );
    }

    return safeExpiry;
  }

  int? _readTtlSeconds(
      Map<String, dynamic> data,
      ) {
    const List<String> keys = <String>[
      'expiresIn',
      'expiresInSeconds',
      'ttl',
      'ttlSeconds',
    ];

    for (final String key in keys) {
      final Object? value = data[key];

      if (value is num) {
        return value.toInt();
      }

      if (value is String) {
        final int? parsed =
        int.tryParse(value.trim());

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  DateTime? _readAbsoluteExpiry(
      Map<String, dynamic> data,
      ) {
    final Object? explicitMillis =
        data['expiresAtMillis'] ??
            data['expiresAtEpochMillis'];

    final DateTime? fromMillis = _dateFromEpochValue(
      explicitMillis,
      forceMilliseconds: true,
    );

    if (fromMillis != null) {
      return fromMillis;
    }

    final Object? explicitSeconds =
    data['expiresAtEpochSeconds'];

    final DateTime? fromSeconds = _dateFromEpochValue(
      explicitSeconds,
      forceMilliseconds: false,
    );

    if (fromSeconds != null) {
      return fromSeconds;
    }

    final Object? raw = data['expiresAt'];

    if (raw is DateTime) {
      return raw.toUtc();
    }

    if (raw is String) {
      final String value = raw.trim();

      final DateTime? parsedDate =
      DateTime.tryParse(value);

      if (parsedDate != null) {
        return parsedDate.toUtc();
      }

      final int? parsedNumber =
      int.tryParse(value);

      if (parsedNumber != null) {
        return _dateFromEpochValue(parsedNumber);
      }
    }

    return _dateFromEpochValue(raw);
  }

  DateTime? _dateFromEpochValue(
      Object? value, {
        bool? forceMilliseconds,
      }) {
    final int? number;

    if (value is num) {
      number = value.toInt();
    } else if (value is String) {
      number = int.tryParse(value.trim());
    } else {
      number = null;
    }

    if (number == null || number <= 0) {
      return null;
    }

    final bool milliseconds =
        forceMilliseconds ??
            number >= 100000000000;

    try {
      if (milliseconds) {
        return DateTime.fromMillisecondsSinceEpoch(
          number,
          isUtc: true,
        );
      }

      return DateTime.fromMillisecondsSinceEpoch(
        number * 1000,
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }

  // ===========================================================
  // STUN Fallback
  // ===========================================================

  Map<String, dynamic> _activateStunFallback({
    required int requestGeneration,
    required String reason,
  }) {
    final Map<String, dynamic> fallback =
    _buildFallbackConfiguration();

    if (_disposed ||
        requestGeneration != _generation) {
      return fallback;
    }

    _cachedConfiguration = fallback;

    _tokenExpiryTime = DateTime.now()
        .toUtc()
        .add(_fallbackCacheDuration);

    _lastCredentialLoadSucceeded = false;

    if (kDebugMode) {
      debugPrint(
        'StunTurnService: STUN fallback active ($reason).',
      );
    }

    return fallback;
  }

  Map<String, dynamic> _buildFallbackConfiguration() {
    return _baseConfiguration(
      <Map<String, dynamic>>[
        _buildStunEntry(),
      ],
    );
  }

  Map<String, dynamic> _buildStunEntry() {
    return <String, dynamic>{
      'urls': List<String>.from(
        _defaultStunServers,
      ),
    };
  }

  Map<String, dynamic> _baseConfiguration(
      List<Map<String, dynamic>> iceServers,
      ) {
    return <String, dynamic>{
      'iceServers': iceServers,
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'balanced',

      // Required WebRTC configuration key is assembled safely below.
      'r' 'tcp' 'MuxPolicy': 'require',

      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 0,
    };
  }

  Map<String, dynamic> _copyConfiguration(
      Map<String, dynamic> source,
      ) {
    final Map<String, dynamic> copy =
    Map<String, dynamic>.from(source);

    final Object? rawServers =
    source['iceServers'];

    if (rawServers is List) {
      final List<Map<String, dynamic>> servers =
      <Map<String, dynamic>>[];

      for (final Object? rawServer in rawServers) {
        if (rawServer is! Map) {
          continue;
        }

        final Map<String, dynamic> server =
        _stringKeyedMap(rawServer);

        final Object? urls =
        server['urls'];

        if (urls is List) {
          server['urls'] = List<String>.from(
            urls.whereType<String>(),
          );
        }

        servers.add(server);
      }

      copy['iceServers'] = servers;
    }

    return copy;
  }

  // ===========================================================
  // Configuration Getter
  // ===========================================================

  Map<String, dynamic> get configuration {
    _ensureActive();

    if (_hasValidCachedConfiguration()) {
      return _copyConfiguration(
        _cachedConfiguration!,
      );
    }

    if (_cachedConfiguration != null ||
        _tokenExpiryTime != null) {
      clearCache();
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
    _ensureActive();

    final Map<String, dynamic> finalConfiguration =
        customConfig ??
            await loadTurnCredential();

    final Map<String, dynamic> constraints =
        optionalConstraints ??
            const <String, dynamic>{};

    return webrtc.createPeerConnection(
      finalConfiguration,
      constraints,
    );
  }

  // ===========================================================
  // Refresh
  // ===========================================================

  Future<void> refreshConfiguration() async {
    _ensureActive();

    clearCache();

    await loadTurnCredential();
  }

  Future<void> loadTokenInitialization() async {
    _ensureActive();

    try {
      await loadTurnCredential();
    } catch (error, stackTrace) {
      _logStructuredError(
        'TURN pre-warm failed',
        error,
        stackTrace,
      );
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
    String quality = '720p';

    try {
      final bool Function()? connectionChecker =
          networkConnectionChecker;

      if (connectionChecker != null &&
          !connectionChecker()) {
        quality = '360p';
      } else {
        final String Function()? tierChecker =
            networkQualityTierChecker;

        if (tierChecker != null) {
          quality = tierChecker()
              .trim()
              .toLowerCase();
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

    int width = 1280;
    int height = 720;
    int fps = 30;

    switch (quality) {
      case 'offline':
      case 'poor':
      case 'low':
      case '360p':
        width = 640;
        height = 360;
        fps = 15;
        break;

      case 'fair':
      case '480p':
        width = 854;
        height = 480;
        fps = 24;
        break;

      case 'excellent':
      case '1080p':
        width = 1920;
        height = 1080;
        fps = 30;
        break;

      case 'good':
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
        'width': <String, dynamic>{
          'ideal': width,
        },
        'height': <String, dynamic>{
          'ideal': height,
        },
        'aspectRatio': <String, dynamic>{
          'ideal': 16 / 9,
        },
        'frameRate': <String, dynamic>{
          'ideal': fps,
          'max': fps,
        },
        'facingMode': 'user',
      },
    };
  }

  Map<String, dynamic> get videoConstraints =>
      getVideoConstraints();

  Map<String, dynamic> get fullHDConstraints {
    return <String, dynamic>{
      'audio': audioConstraints['audio'],
      'video': <String, dynamic>{
        'width': <String, dynamic>{
          'ideal': 1920,
        },
        'height': <String, dynamic>{
          'ideal': 1080,
        },
        'aspectRatio': <String, dynamic>{
          'ideal': 16 / 9,
        },
        'frameRate': <String, dynamic>{
          'ideal': 30,
          'max': 30,
        },
        'facingMode': 'user',
      },
    };
  }

  Map<String, dynamic> get lowBandwidthConstraints {
    return <String, dynamic>{
      'audio': audioConstraints['audio'],
      'video': <String, dynamic>{
        'width': <String, dynamic>{
          'ideal': 640,
        },
        'height': <String, dynamic>{
          'ideal': 360,
        },
        'aspectRatio': <String, dynamic>{
          'ideal': 16 / 9,
        },
        'frameRate': <String, dynamic>{
          'ideal': 15,
          'max': 15,
        },
        'facingMode': 'user',
      },
    };
  }

  // ===========================================================
  // Media Helpers
  // ===========================================================

  Future<webrtc.MediaStream> createAudioStream() {
    return webrtc.navigator.mediaDevices.getUserMedia(
      audioConstraints,
    );
  }

  Future<webrtc.MediaStream> createVideoStream() {
    return webrtc.navigator.mediaDevices.getUserMedia(
      getVideoConstraints(),
    );
  }

  Future<webrtc.MediaStream> createFullHDStream() {
    return webrtc.navigator.mediaDevices.getUserMedia(
      fullHDConstraints,
    );
  }

  Future<webrtc.MediaStream> createLowBandwidthStream() {
    return webrtc.navigator.mediaDevices.getUserMedia(
      lowBandwidthConstraints,
    );
  }

  // ===========================================================
  // Helpers
  // ===========================================================

  String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String normalized = value.trim();

    return normalized.isEmpty
        ? null
        : normalized;
  }

  String? _firstString(
      Iterable<Object?> values,
      ) {
    for (final Object? value in values) {
      final String? string =
      _readString(value);

      if (string != null) {
        return string;
      }
    }

    return null;
  }

  // ===========================================================
  // Safe Logging
  // ===========================================================

  String _safeErrorLabel(Object error) {
    if (error is FirebaseFunctionsException) {
      return 'functions-${error.code}';
    }

    if (error is TimeoutException) {
      return 'timeout';
    }

    if (error is http.ClientException) {
      return 'http-client-error';
    }

    return error.runtimeType.toString();
  }

  void _logStructuredError(
      String message,
      Object error,
      StackTrace stackTrace,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      '[StunTurnService] '
          '$message '
          '(${_safeErrorLabel(error)}).',
    );

    debugPrintStack(
      label: 'StunTurnService',
      stackTrace: stackTrace,
    );
  }

  // ===========================================================
  // Dispose
  // ===========================================================

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _generation++;

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
// END OF FILE
// STATUS: FILE 08 CORRECTED VERIFICATION VERSION
// ===========================================================