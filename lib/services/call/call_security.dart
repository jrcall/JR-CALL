import 'dart:convert';
import 'dart:math';

import '../../core/constants/call_status.dart';

/// ===========================================================
/// JR CALL
/// File: call_security.dart
/// Location: lib/services/call/call_security.dart
///
/// FINAL PRODUCTION CONTRACT:
/// - Secure session/token generation uses Random.secure().
/// - Existing public APIs are preserved.
/// - Base64 placeholder hashing is removed.
/// - SHA-256 is used for deterministic hashing.
/// - Hash verification avoids ordinary direct equality.
/// - Firebase UID participant boundaries are validated locally.
/// - FILE 01 CallStatus transition safety is exposed here.
/// - Same-state transitions are idempotent.
/// - No WebRTC/ICE/SDP ownership.
/// - No TURN credential ownership.
/// - No backend/rules security authority duplicated here.
/// - WebRTC media encryption remains owned by native encrypted transport.
/// ===========================================================

class CallSecurity {
  CallSecurity._();

  static final CallSecurity instance = CallSecurity._();

  final Random _random = Random.secure();

  static const int _sessionBytes = 32;
  static const int _tokenBytes = 32;
  static const int _keyBytes = 32;

  static const int _mask32 = 0xffffffff;

  // =============================================================
  // SECURE RANDOM MATERIAL
  // =============================================================

  /// Generates a cryptographically strong Call session identifier.
  ///
  /// The resulting Base64URL value contains no `/`, so it is also
  /// suitable for normal Firestore document/session identifiers.
  String generateSessionId() {
    return _encodeRandomBytes(_sessionBytes);
  }

  /// Generates cryptographically strong random token material.
  ///
  /// IMPORTANT:
  /// This client token is NOT an authorization credential.
  /// Firebase authentication / backend validation / Firestore rules
  /// remain the authoritative security boundary.
  String generateCallToken() {
    return _encodeRandomBytes(_tokenBytes);
  }

  /// Existing compatibility API preserved.
  ///
  /// Returns 256-bit random key material.
  ///
  /// IMPORTANT:
  /// Do NOT use this to replace WebRTC native encrypted media transport.
  /// Do NOT use this as a substitute for temporary server-issued
  /// TURN credentials.
  String generateEncryptionKey() {
    return _encodeRandomBytes(_keyBytes);
  }

  // =============================================================
  // SESSION VALIDATION
  // =============================================================

  /// Validates structural session-ID safety.
  ///
  /// This is format validation only and does NOT prove ownership.
  bool isValidSession(String sessionId) {
    final String value = sessionId.trim();

    if (value.length < 32 || value.length > 256) {
      return false;
    }

    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      return false;
    }

    return true;
  }

  // =============================================================
  // TOKEN VALIDATION
  // =============================================================

  /// Validates token encoding and minimum entropy-sized payload.
  ///
  /// This does NOT authorize a user or a call.
  bool isValidToken(String token) {
    final String value = token.trim();

    if (value.length < 32 || value.length > 512) {
      return false;
    }

    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      return false;
    }

    try {
      final List<int> decoded = base64Url.decode(
        _restoreBase64Padding(value),
      );

      return decoded.length >= 32 && decoded.length <= 256;
    } catch (_) {
      return false;
    }
  }

  // =============================================================
  // UID / PARTICIPANT SECURITY
  // =============================================================

  /// Local structural validation for Firebase UID usage.
  ///
  /// Firebase/backend remains authoritative for whether a UID exists.
  bool isValidUid(String uid) {
    final String value = uid.trim();

    if (value.isEmpty || value.length > 128) {
      return false;
    }

    if (value.contains('/')) {
      return false;
    }

    for (final int codeUnit in value.codeUnits) {
      if (codeUnit < 0x20 || codeUnit == 0x7f) {
        return false;
      }
    }

    return true;
  }

  /// Whether the authenticated Firebase UID belongs to this call.
  bool isParticipant({
    required String authenticatedUid,
    required String callerUid,
    required String receiverUid,
  }) {
    final String auth = authenticatedUid.trim();
    final String caller = callerUid.trim();
    final String receiver = receiverUid.trim();

    if (!isValidUid(auth) ||
        !isValidUid(caller) ||
        !isValidUid(receiver) ||
        caller == receiver) {
      return false;
    }

    return auth == caller || auth == receiver;
  }

  /// Validates the local outgoing-call identity boundary.
  bool isValidOutgoingCall({
    required String authenticatedUid,
    required String callerUid,
    required String receiverUid,
  }) {
    final String auth = authenticatedUid.trim();
    final String caller = callerUid.trim();
    final String receiver = receiverUid.trim();

    if (!isValidUid(auth) ||
        !isValidUid(caller) ||
        !isValidUid(receiver)) {
      return false;
    }

    if (auth != caller) {
      return false;
    }

    return caller != receiver;
  }

  /// Throws when the outgoing identity boundary is invalid.
  void requireValidOutgoingCall({
    required String authenticatedUid,
    required String callerUid,
    required String receiverUid,
  }) {
    if (!isValidOutgoingCall(
      authenticatedUid: authenticatedUid,
      callerUid: callerUid,
      receiverUid: receiverUid,
    )) {
      throw StateError(
        'Invalid JR CALL outgoing participant identity.',
      );
    }
  }

  // =============================================================
  // CALL STATUS SECURITY
  // =============================================================

  bool isTerminalStatus(CallStatus status) {
    return switch (status) {
      CallStatus.rejected ||
      CallStatus.ended ||
      CallStatus.missed ||
      CallStatus.busy ||
      CallStatus.cancelled ||
      CallStatus.failed =>
      true,
      _ => false,
    };
  }

  bool isValidStatusTransition(
      CallStatus from,
      CallStatus to,
      ) {
    if (from == to) {
      return true;
    }

    if (isTerminalStatus(from)) {
      return false;
    }

    return switch (from) {
      CallStatus.calling => switch (to) {
        CallStatus.ringing ||
        CallStatus.accepted ||
        CallStatus.rejected ||
        CallStatus.missed ||
        CallStatus.busy ||
        CallStatus.cancelled ||
        CallStatus.failed =>
        true,
        _ => false,
      },

      CallStatus.ringing => switch (to) {
        CallStatus.accepted ||
        CallStatus.rejected ||
        CallStatus.missed ||
        CallStatus.busy ||
        CallStatus.cancelled ||
        CallStatus.failed =>
        true,
        _ => false,
      },

      CallStatus.accepted => switch (to) {
        CallStatus.connecting ||
        CallStatus.connected ||
        CallStatus.ended ||
        CallStatus.cancelled ||
        CallStatus.failed =>
        true,
        _ => false,
      },

      CallStatus.connecting => switch (to) {
        CallStatus.connected ||
        CallStatus.reconnecting ||
        CallStatus.ended ||
        CallStatus.cancelled ||
        CallStatus.failed =>
        true,
        _ => false,
      },

      CallStatus.connected => switch (to) {
        CallStatus.reconnecting ||
        CallStatus.ended ||
        CallStatus.failed =>
        true,
        _ => false,
      },

      CallStatus.reconnecting => switch (to) {
        CallStatus.connected ||
        CallStatus.ended ||
        CallStatus.failed =>
        true,
        _ => false,
      },

      CallStatus.rejected ||
      CallStatus.ended ||
      CallStatus.missed ||
      CallStatus.busy ||
      CallStatus.cancelled ||
      CallStatus.failed =>
      false,
    };
  }

  // =============================================================
  // HASH
  // =============================================================

  String hash(String value) {
    final List<int> digest = _sha256(
      utf8.encode(value),
    );

    return base64Url
        .encode(digest)
        .replaceAll('=', '');
  }

  bool verifyHash({
    required String original,
    required String hashed,
  }) {
    final String expected = hash(original);

    return _constantTimeEquals(
      expected,
      hashed.trim(),
    );
  }

  // =============================================================
  // CLEAR
  // =============================================================

  void clear() {
    // Intentionally no retained secret state.
  }

  // =============================================================
  // RANDOM HELPERS
  // =============================================================

  String _encodeRandomBytes(int length) {
    final List<int> bytes = List<int>.generate(
      length,
          (_) => _random.nextInt(256),
      growable: false,
    );

    return base64Url
        .encode(bytes)
        .replaceAll('=', '');
  }

  String _restoreBase64Padding(String value) {
    final int remainder = value.length % 4;

    if (remainder == 0) {
      return value;
    }

    return value.padRight(
      value.length + (4 - remainder),
      '=',
    );
  }

  bool _constantTimeEquals(
      String first,
      String second,
      ) {
    int difference = first.length ^ second.length;

    final int maximumLength = max(
      first.length,
      second.length,
    );

    for (int index = 0; index < maximumLength; index++) {
      final int firstUnit =
      index < first.length ? first.codeUnitAt(index) : 0;

      final int secondUnit =
      index < second.length ? second.codeUnitAt(index) : 0;

      difference |= firstUnit ^ secondUnit;
    }

    return difference == 0;
  }

  // =============================================================
  // SHA-256
  // =============================================================

  List<int> _sha256(List<int> input) {
    final List<int> message = List<int>.of(
      input,
      growable: true,
    );

    final int bitLength = message.length * 8;

    message.add(0x80);

    while ((message.length % 64) != 56) {
      message.add(0);
    }

    for (int shift = 56; shift >= 0; shift -= 8) {
      message.add(
        (bitLength >> shift) & 0xff,
      );
    }

    int h0 = 0x6a09e667;
    int h1 = 0xbb67ae85;
    int h2 = 0x3c6ef372;
    int h3 = 0xa54ff53a;
    int h4 = 0x510e527f;
    int h5 = 0x9b05688c;
    int h6 = 0x1f83d9ab;
    int h7 = 0x5be0cd19;

    for (
    int chunkOffset = 0;
    chunkOffset < message.length;
    chunkOffset += 64
    ) {
      final List<int> words = List<int>.filled(
        64,
        0,
      );

      for (int index = 0; index < 16; index++) {
        final int offset =
            chunkOffset + (index * 4);

        words[index] =
        ((message[offset] << 24) |
        (message[offset + 1] << 16) |
        (message[offset + 2] << 8) |
        message[offset + 3]) &
        _mask32;
      }

      for (int index = 16; index < 64; index++) {
        final int s0 =
        _rotateRight(words[index - 15], 7) ^
        _rotateRight(words[index - 15], 18) ^
        (words[index - 15] >>> 3);

        final int s1 =
        _rotateRight(words[index - 2], 17) ^
        _rotateRight(words[index - 2], 19) ^
        (words[index - 2] >>> 10);

        words[index] =
        (words[index - 16] +
            s0 +
            words[index - 7] +
            s1) &
        _mask32;
      }

      int a = h0;
      int b = h1;
      int c = h2;
      int d = h3;
      int e = h4;
      int f = h5;
      int g = h6;
      int h = h7;

      for (int index = 0; index < 64; index++) {
        final int sigma1 =
        _rotateRight(e, 6) ^
        _rotateRight(e, 11) ^
        _rotateRight(e, 25);

        final int choose =
        (e & f) ^
        ((~e) & g);

        final int temp1 =
        (h +
            sigma1 +
            choose +
            _sha256Constants[index] +
            words[index]) &
        _mask32;

        final int sigma0 =
        _rotateRight(a, 2) ^
        _rotateRight(a, 13) ^
        _rotateRight(a, 22);

        final int majority =
        (a & b) ^
        (a & c) ^
        (b & c);

        final int temp2 =
        (sigma0 + majority) &
        _mask32;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & _mask32;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & _mask32;
      }

      h0 = (h0 + a) & _mask32;
      h1 = (h1 + b) & _mask32;
      h2 = (h2 + c) & _mask32;
      h3 = (h3 + d) & _mask32;
      h4 = (h4 + e) & _mask32;
      h5 = (h5 + f) & _mask32;
      h6 = (h6 + g) & _mask32;
      h7 = (h7 + h) & _mask32;
    }

    final List<int> digest = <int>[];

    for (final int value in <int>[
      h0,
      h1,
      h2,
      h3,
      h4,
      h5,
      h6,
      h7,
    ]) {
      digest
        ..add((value >>> 24) & 0xff)
        ..add((value >>> 16) & 0xff)
        ..add((value >>> 8) & 0xff)
        ..add(value & 0xff);
    }

    return List<int>.unmodifiable(digest);
  }

  int _rotateRight(
      int value,
      int amount,
      ) {
    final int normalized =
    value & _mask32;

    return ((normalized >>> amount) |
    (normalized << (32 - amount))) &
    _mask32;
  }

  static const List<int> _sha256Constants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
}