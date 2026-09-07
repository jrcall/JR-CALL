// ===============================================================
// JR CALL
// File: user_discovery_service.dart
// Location: lib/services/user_discovery_service.dart
//
// PRODUCTION GLOBAL USER DISCOVERY
//
// PRIMARY SEARCH INDEX:
// - users/{uid}.searchFragments
//
// SEARCH:
// - Full Name contains
// - Username contains
// - JR CALL ID contains
// - Email contains only when explicitly discoverable
// - Phone contains only when explicitly discoverable
// - Single-character / single-digit indexed discovery
//
// PHONE:
// - Unified searchFragments primary path
// - phoneSearchKeys legacy compatibility
// - phoneNormalized / phoneNumber / phone legacy compatibility
// - E.164 support
// - international 00-prefix support
// - formatted-number normalization
// - current-user country assisted local-number resolution
//
// IDENTITY:
// - Firebase UID stays canonical internal identity.
// - Firebase UID is NEVER a public search keyword.
// - Username / JR CALL ID remain public discovery identities.
//
// PRIVACY:
// - isDiscoverable=false is always respected.
// - Missing email/phone discovery consent defaults to PRIVATE.
// - Blocked/deleted profiles are rejected.
// - No full users collection download.
//
// PAGINATION:
// - Stable Firestore document-order cursor.
// - Existing DiscoveryPage API preserved.
//
// CALL:
// - This service resolves Firebase UID only.
// - Call Engine / WebRTC / Signaling remain untouched.
// ===============================================================

import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';

// ===============================================================
// SEARCH TYPE
// ===============================================================

enum DiscoverySearchType {
  automatic,
  jrCallId,
  username,
  name,
  email,
  phone,
}

// ===============================================================
// DISCOVERY USER
// ===============================================================

class DiscoveryUser {
  const DiscoveryUser({
    required this.uid,
    required this.fullName,
    required this.username,
    required this.jrCallUserId,
    required this.profilePhotoUrl,
    required this.coverPhotoUrl,
    required this.country,
    required this.countryCode,
    required this.bio,
    required this.email,
    required this.phoneNumber,
    required this.online,
    required this.verified,
    required this.isDiscoverable,
    required this.isDiscoverableByEmail,
    required this.isDiscoverableByPhone,
  });

  final String uid;

  final String fullName;

  final String? username;

  final String? jrCallUserId;

  final String? profilePhotoUrl;

  final String? coverPhotoUrl;

  final String? country;

  final String? countryCode;

  final String? bio;

  final String? email;

  final String? phoneNumber;

  final bool online;

  final bool verified;

  final bool isDiscoverable;

  final bool isDiscoverableByEmail;

  final bool isDiscoverableByPhone;

  // =============================================================
  // STATE
  // =============================================================

  bool get hasUsername {
    return _cleanString(username) != null;
  }

  bool get hasJrCallUserId {
    return _cleanString(jrCallUserId) != null;
  }

  bool get hasProfilePhoto {
    return _cleanString(profilePhotoUrl) != null;
  }

  bool get hasCoverPhoto {
    return _cleanString(coverPhotoUrl) != null;
  }

  bool get hasBio {
    return _cleanString(bio) != null;
  }

  // =============================================================
  // NORMALIZED DISCOVERY VALUES
  // =============================================================

  String get normalizedName {
    return _normalizeSearchTextValue(
      fullName,
    );
  }

  String? get normalizedUsername {
    final String? value = _cleanString(
      username,
    );

    if (value == null) {
      return null;
    }

    return _normalizePublicIdentityValue(
      value,
    );
  }

  String? get normalizedJrCallUserId {
    final String? value = _cleanString(
      jrCallUserId,
    );

    if (value == null) {
      return null;
    }

    return _normalizePublicIdentityValue(
      value,
    );
  }

  String? get normalizedEmail {
    final String? value = _cleanString(
      email,
    );

    if (value == null) {
      return null;
    }

    return value.toLowerCase();
  }

  String? get normalizedPhone {
    final String? value = _cleanString(
      phoneNumber,
    );

    if (value == null) {
      return null;
    }

    final String normalized = _normalizePhoneValue(
      value,
    );

    return normalized.isEmpty
        ? null
        : normalized;
  }

  String? get phoneDigits {
    final String? value = normalizedPhone;

    if (value == null) {
      return null;
    }

    final String digits = value.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    return digits.isEmpty
        ? null
        : digits;
  }

  // =============================================================
  // DISPLAY
  // =============================================================

  String get displayName {
    final String name = fullName.trim();

    if (name.isNotEmpty) {
      return name;
    }

    final String? usernameValue = _cleanString(
      username,
    );

    if (usernameValue != null) {
      return usernameValue;
    }

    final String? jrId = _cleanString(
      jrCallUserId,
    );

    return jrId ?? 'JR CALL User';
  }

  String? get usernameLabel {
    final String? value = _cleanString(
      username,
    );

    if (value == null) {
      return null;
    }

    return value.startsWith('@')
        ? value
        : '@$value';
  }

  String? get publicIdentityLabel {
    return _cleanString(
      jrCallUserId,
    ) ??
        usernameLabel;
  }

  // =============================================================
  // FIRESTORE
  // =============================================================

  factory DiscoveryUser.fromDocument(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    return DiscoveryUser.fromMap(
      document.data() ??
          const <String, dynamic>{},
      documentId: document.id,
    );
  }

  factory DiscoveryUser.fromMap(
      Map<String, dynamic> data, {
        String? documentId,
      }) {
    final String fallbackUid =
        documentId?.trim() ?? '';

    final String uid =
        _firstNonEmptyString(
          <Object?>[
            data['uid'],
            data['userId'],
            fallbackUid,
          ],
        ) ??
            fallbackUid;

    final String fullName =
        _firstNonEmptyString(
          <Object?>[
            data['fullName'],
            data['name'],
            data['displayName'],
          ],
        ) ??
            '';

    final String? username =
    _firstNonEmptyString(
      <Object?>[
        data['username'],
        data['shortName'],
      ],
    );

    final String? jrCallUserId =
    _firstNonEmptyString(
      <Object?>[
        data['jrCallUserId'],
        data['userAddress'],
        data['jrCallId'],
      ],
    );

    final String? profilePhotoUrl =
    _firstNonEmptyString(
      <Object?>[
        data['profilePhotoUrl'],
        data['photoUrl'],
        data['photoURL'],
      ],
    );

    final String? coverPhotoUrl =
    _firstNonEmptyString(
      <Object?>[
        data['coverPhotoUrl'],
        data['coverPhoto'],
        data['backgroundPhotoUrl'],
      ],
    );

    final String? country =
    _firstNonEmptyString(
      <Object?>[
        data['country'],
      ],
    );

    final String? countryCode =
    _firstNonEmptyString(
      <Object?>[
        data['countryCode'],
      ],
    );

    final String? bio =
    _firstNonEmptyString(
      <Object?>[
        data['bio'],
      ],
    );

    // -----------------------------------------------------------
    // GLOBAL DISCOVERY
    //
    // Existing profiles without this global flag remain compatible.
    // Explicit false is always respected.
    // -----------------------------------------------------------

    final bool isDiscoverable =
        _readBool(
          data['isDiscoverable'],
        ) ??
            true;

    // -----------------------------------------------------------
    // EMAIL / PHONE PRIVACY
    //
    // Missing consent is PRIVATE.
    //
    // This matches UserModel + FirestoreService contract.
    // -----------------------------------------------------------

    final bool isDiscoverableByEmail =
        _readBool(
          data['isDiscoverableByEmail'],
        ) ??
            false;

    final bool isDiscoverableByPhone =
        _readBool(
          data['isDiscoverableByPhone'],
        ) ??
            false;

    final String? rawEmail =
    _firstNonEmptyString(
      <Object?>[
        data['email'],
        data['emailNormalized'],
      ],
    );

    final String? rawPhone =
    _firstNonEmptyString(
      <Object?>[
        data['phoneNumber'],
        data['phone'],
        data['phoneNormalized'],
      ],
    );

    final bool emailVerified =
        _readBool(
          data['emailVerified'],
        ) ??
            false;

    final bool phoneVerified =
        _readBool(
          data['phoneVerified'],
        ) ??
            false;

    final bool legacyVerified =
        _readBool(
          data['verified'],
        ) ??
            false;

    return DiscoveryUser(
      uid: uid,
      fullName: fullName,
      username: username,
      jrCallUserId: jrCallUserId,
      profilePhotoUrl: profilePhotoUrl,
      coverPhotoUrl: coverPhotoUrl,
      country: country,
      countryCode: countryCode,
      bio: bio,

      // Private fields are never exposed through DiscoveryUser
      // unless the profile explicitly permits discovery by them.
      email: isDiscoverableByEmail
          ? rawEmail
          : null,

      phoneNumber: isDiscoverableByPhone
          ? rawPhone
          : null,

      online:
      _readBool(
        data['online'],
      ) ??
          false,

      verified:
      emailVerified ||
          phoneVerified ||
          legacyVerified,

      isDiscoverable: isDiscoverable,

      isDiscoverableByEmail:
      isDiscoverableByEmail,

      isDiscoverableByPhone:
      isDiscoverableByPhone,
    );
  }

  // =============================================================
  // DEBUG
  // =============================================================

  @override
  String toString() {
    return 'DiscoveryUser('
        'uid: $uid, '
        'displayName: $displayName, '
        'username: $username, '
        'jrCallUserId: $jrCallUserId'
        ')';
  }

  static String? _cleanString(
      String? value,
      ) {
    final String normalized =
        value?.trim() ?? '';

    return normalized.isEmpty
        ? null
        : normalized;
  }
}

// ===============================================================
// PAGE
// ===============================================================

class DiscoveryPage {
  const DiscoveryPage({
    required this.users,
    required this.hasMore,
    this.nextCursor,
  });

  final List<DiscoveryUser> users;

  final bool hasMore;

  final DocumentSnapshot<Map<String, dynamic>>? nextCursor;

  static const DiscoveryPage empty = DiscoveryPage(
    users: <DiscoveryUser>[],
    hasMore: false,
  );
}

// ===============================================================
// SERVICE
// ===============================================================

class UserDiscoveryService {
  UserDiscoveryService._();

  static final UserDiscoveryService instance =
  UserDiscoveryService._();

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  final CountryService _countryService =
  CountryService();

  // =============================================================
  // COLLECTIONS
  // =============================================================

  static const String usersCollection =
      'users';

  static const String usernamesCollection =
      'usernames';

  static const String jrCallIdsCollection =
      'user_addresses';

  static const String userAddressesCollection =
      jrCallIdsCollection;

  // Legacy / future compatibility.
  static const String canonicalJrCallIdsCollection =
      'jr_call_ids';

  // =============================================================
  // LIMITS
  // =============================================================

  static const int defaultPageSize = 20;

  static const int maximumPageSize = 50;

  static const int _maximumArrayContainsAnyValues = 30;

  CollectionReference<Map<String, dynamic>> get _users {
    return _firestore.collection(
      usersCollection,
    );
  }

  // =============================================================
  // MAIN SEARCH
  //
  // IMPORTANT:
  //
  // Every public search type now supports contains-style matching.
  //
  // Exact helper APIs remain available separately below for
  // compatibility and fast exact identity resolution.
  // =============================================================

  Future<DiscoveryPage> search(
      String value, {
        DiscoverySearchType type =
            DiscoverySearchType.automatic,
        int limit = defaultPageSize,
        DocumentSnapshot<Map<String, dynamic>>? cursor,
        bool excludeCurrentUser = true,
      }) async {
    final String query = value.trim();

    if (query.isEmpty) {
      return DiscoveryPage.empty;
    }

    final int safeLimit = _safeLimit(
      limit,
    );

    return _searchIndexed(
      query,
      type: type,
      limit: safeLimit,
      cursor: cursor,
      excludeCurrentUser: excludeCurrentUser,
    );
  }

  // =============================================================
  // GLOBAL INDEXED SEARCH
  //
  // Firestore only retrieves documents whose searchFragments
  // contain the requested normalized fragment.
  //
  // No full users collection download occurs.
  // =============================================================

  Future<DiscoveryPage> _searchIndexed(
      String value, {
        required DiscoverySearchType type,
        required int limit,
        required DocumentSnapshot<Map<String, dynamic>>? cursor,
        required bool excludeCurrentUser,
      }) async {
    final _DiscoveryQueryPlan plan =
    await _buildQueryPlan(
      value,
      type: type,
    );

    if (plan.indexFragments.isEmpty) {
      return _legacyFallbackPage(
        value,
        type: type,
        limit: limit,
        cursor: cursor,
        excludeCurrentUser: excludeCurrentUser,
      );
    }

    Query<Map<String, dynamic>> query =
    _users.where(
      'isDiscoverable',
      isEqualTo: true,
    );

    if (plan.indexFragments.length == 1) {
      query = query.where(
        'searchFragments',
        arrayContains:
        plan.indexFragments.first,
      );
    } else {
      query = query.where(
        'searchFragments',
        arrayContainsAny:
        plan.indexFragments
            .take(
          _maximumArrayContainsAnyValues,
        )
            .toList(
          growable: false,
        ),
      );
    }

    // Stable document ordering is required for reliable pagination.
    query = query.orderBy(
      FieldPath.documentId,
    );

    if (cursor != null) {
      query = query.startAfterDocument(
        cursor,
      );
    }

    // One extra document allows hasMore detection.
    final int fetchLimit = limit + 1;

    final QuerySnapshot<Map<String, dynamic>> snapshot =
    await query
        .limit(
      fetchLimit,
    )
        .get();

    if (snapshot.docs.isEmpty) {
      // ---------------------------------------------------------
      // Transitional legacy fallback:
      //
      // Existing profiles that have not yet been re-saved may not
      // have searchFragments.
      // ---------------------------------------------------------

      if (cursor == null) {
        return _legacyFallbackPage(
          value,
          type: type,
          limit: limit,
          cursor: null,
          excludeCurrentUser: excludeCurrentUser,
        );
      }

      return DiscoveryPage.empty;
    }

    final List<_DiscoveryHit> acceptedHits =
    <_DiscoveryHit>[];

    final Set<String> acceptedUids =
    <String>{};

    for (final QueryDocumentSnapshot<Map<String, dynamic>>
    document in snapshot.docs) {
      final DiscoveryUser? user =
      _acceptedDiscoveryUser(
        document,
        excludeCurrentUser: excludeCurrentUser,
      );

      if (user == null) {
        continue;
      }

      final String uid = user.uid.trim();

      if (uid.isEmpty ||
          !acceptedUids.add(uid)) {
        continue;
      }

      if (!_matchesPlan(
        user,
        plan,
      )) {
        continue;
      }

      acceptedHits.add(
        _DiscoveryHit(
          user: user,
          document: document,
          rank: _searchRank(
            user,
            plan,
          ),
        ),
      );
    }

    // -----------------------------------------------------------
    // PAGINATION CURSOR
    //
    // Never skip an accepted result that belongs to next page.
    // -----------------------------------------------------------

    final bool hasExtraAccepted =
        acceptedHits.length > limit;

    final bool serverMayHaveMore =
        snapshot.docs.length > limit;

    final bool hasMore =
        hasExtraAccepted ||
            serverMayHaveMore;

    final List<_DiscoveryHit> pageHits =
    acceptedHits
        .take(
      limit,
    )
        .toList(
      growable: false,
    );

    DocumentSnapshot<Map<String, dynamic>>? nextCursor;

    if (hasMore) {
      if (hasExtraAccepted &&
          pageHits.isNotEmpty) {
        // Start the next page after the last accepted user that
        // actually belongs to this page.
        nextCursor =
            pageHits.last.document;
      } else {
        // All accepted users from the current server batch were
        // returned. Advance after the whole scanned batch.
        nextCursor =
            snapshot.docs.last;
      }
    }

    // -----------------------------------------------------------
    // PAGE-LOCAL RANKING
    //
    // Exact match > prefix > contains.
    //
    // Pagination itself remains stable by Firestore document ID.
    // -----------------------------------------------------------

    final List<_DiscoveryHit> ranked =
    List<_DiscoveryHit>.of(
      pageHits,
    );

    ranked.sort(
          (
          _DiscoveryHit first,
          _DiscoveryHit second,
          ) {
        final int rankComparison =
        first.rank.compareTo(
          second.rank,
        );

        if (rankComparison != 0) {
          return rankComparison;
        }

        final int nameComparison =
        first.user.normalizedName.compareTo(
          second.user.normalizedName,
        );

        if (nameComparison != 0) {
          return nameComparison;
        }

        return first.user.uid.compareTo(
          second.user.uid,
        );
      },
    );

    return DiscoveryPage(
      users: List<DiscoveryUser>.unmodifiable(
        ranked.map(
              (
              _DiscoveryHit hit,
              ) =>
          hit.user,
        ),
      ),
      hasMore: hasMore,
      nextCursor: nextCursor,
    );
  }

  // =============================================================
  // QUERY PLAN
  // =============================================================

  Future<_DiscoveryQueryPlan> _buildQueryPlan(
      String value, {
        required DiscoverySearchType type,
      }) async {
    final String raw = value.trim();

    final String text =
    normalizeName(
      raw,
    );

    final String identity =
    _normalizePublicIdentityQuery(
      raw,
    );

    final String email =
    normalizeEmail(
      raw,
    );

    final List<String> phoneFragments =
    await _buildPhoneContainsCandidates(
      raw,
    );

    final LinkedHashSet<String> fragments =
    LinkedHashSet<String>();

    void addFragment(
        String? value,
        ) {
      final String candidate =
          value?.trim() ?? '';

      if (candidate.isEmpty) {
        return;
      }

      final String bounded =
      _boundSearchFragment(
        candidate,
      );

      if (bounded.isNotEmpty) {
        fragments.add(
          bounded,
        );
      }
    }

    switch (type) {
      case DiscoverySearchType.name:
        addFragment(
          text,
        );
        break;

      case DiscoverySearchType.username:
        addFragment(
          identity,
        );
        break;

      case DiscoverySearchType.jrCallId:
        addFragment(
          identity,
        );
        break;

      case DiscoverySearchType.email:
        addFragment(
          email,
        );
        break;

      case DiscoverySearchType.phone:
        for (final String candidate
        in phoneFragments) {
          addFragment(
            candidate,
          );
        }
        break;

      case DiscoverySearchType.automatic:
      // -------------------------------------------------------
      // General text supports:
      // Name / Username / JR CALL ID / Email.
      // -------------------------------------------------------

        addFragment(
          text,
        );

        if (identity != text) {
          addFragment(
            identity,
          );
        }

        if (email != text) {
          addFragment(
            email,
          );
        }

        // Numeric/phone-compatible alternatives.
        for (final String candidate
        in phoneFragments) {
          addFragment(
            candidate,
          );
        }
        break;
    }

    return _DiscoveryQueryPlan(
      type: type,
      raw: raw,
      text: text,
      identity: identity,
      email: email,
      phoneFragments:
      List<String>.unmodifiable(
        phoneFragments,
      ),
      indexFragments:
      List<String>.unmodifiable(
        fragments
            .take(
          _maximumArrayContainsAnyValues,
        )
            .toList(
          growable: false,
        ),
      ),
    );
  }

  String _boundSearchFragment(
      String value,
      ) {
    final List<int> runes =
    value.runes
        .take(
      UserModel.searchFragmentMaxRunes,
    )
        .toList(
      growable: false,
    );

    if (runes.isEmpty) {
      return '';
    }

    return String.fromCharCodes(
      runes,
    );
  }

  // =============================================================
  // QUERY MATCHING
  // =============================================================

  bool _matchesPlan(
      DiscoveryUser user,
      _DiscoveryQueryPlan plan,
      ) {
    if (!user.isDiscoverable) {
      return false;
    }

    switch (plan.type) {
      case DiscoverySearchType.name:
        return plan.text.isNotEmpty &&
            user.normalizedName.contains(
              plan.text,
            );

      case DiscoverySearchType.username:
        return _containsNullable(
          user.normalizedUsername,
          plan.identity,
        );

      case DiscoverySearchType.jrCallId:
        return _containsNullable(
          user.normalizedJrCallUserId,
          plan.identity,
        );

      case DiscoverySearchType.email:
        return user.isDiscoverableByEmail &&
            _containsNullable(
              user.normalizedEmail,
              plan.email,
            );

      case DiscoverySearchType.phone:
        return user.isDiscoverableByPhone &&
            _phoneContainsAny(
              user,
              plan.phoneFragments,
            );

      case DiscoverySearchType.automatic:
        if (plan.text.isNotEmpty &&
            user.normalizedName.contains(
              plan.text,
            )) {
          return true;
        }

        if (_containsNullable(
          user.normalizedUsername,
          plan.identity,
        )) {
          return true;
        }

        if (_containsNullable(
          user.normalizedJrCallUserId,
          plan.identity,
        )) {
          return true;
        }

        if (user.isDiscoverableByEmail &&
            _containsNullable(
              user.normalizedEmail,
              plan.email,
            )) {
          return true;
        }

        if (user.isDiscoverableByPhone &&
            _phoneContainsAny(
              user,
              plan.phoneFragments,
            )) {
          return true;
        }

        return false;
    }
  }

  bool _containsNullable(
      String? source,
      String query,
      ) {
    return source != null &&
        query.isNotEmpty &&
        source.contains(
          query,
        );
  }

  bool _phoneContainsAny(
      DiscoveryUser user,
      Iterable<String> candidates,
      ) {
    final String? normalizedPhone =
        user.normalizedPhone;

    final String? phoneDigits =
        user.phoneDigits;

    if (normalizedPhone == null &&
        phoneDigits == null) {
      return false;
    }

    for (final String rawCandidate
    in candidates) {
      final String candidate =
      rawCandidate.trim();

      if (candidate.isEmpty) {
        continue;
      }

      if (normalizedPhone != null &&
          normalizedPhone.contains(
            candidate,
          )) {
        return true;
      }

      final String candidateDigits =
      candidate.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      if (candidateDigits.isNotEmpty &&
          phoneDigits != null &&
          phoneDigits.contains(
            candidateDigits,
          )) {
        return true;
      }
    }

    return false;
  }

  // =============================================================
  // SEARCH RANK
  //
  // Lower number = stronger result.
  // =============================================================

  int _searchRank(
      DiscoveryUser user,
      _DiscoveryQueryPlan plan,
      ) {
    final String? username =
        user.normalizedUsername;

    final String? jrCallId =
        user.normalizedJrCallUserId;

    final String? email =
        user.normalizedEmail;

    // -----------------------------------------------------------
    // EXACT
    // -----------------------------------------------------------

    if (plan.identity.isNotEmpty &&
        jrCallId == plan.identity) {
      return 0;
    }

    if (plan.identity.isNotEmpty &&
        username == plan.identity) {
      return 1;
    }

    if (plan.text.isNotEmpty &&
        user.normalizedName ==
            plan.text) {
      return 2;
    }

    if (user.isDiscoverableByEmail &&
        plan.email.isNotEmpty &&
        email == plan.email) {
      return 3;
    }

    if (user.isDiscoverableByPhone &&
        _phoneMatchesExactPlan(
          user,
          plan.phoneFragments,
        )) {
      return 4;
    }

    // -----------------------------------------------------------
    // PREFIX
    // -----------------------------------------------------------

    if (plan.text.isNotEmpty &&
        user.normalizedName.startsWith(
          plan.text,
        )) {
      return 10;
    }

    if (username != null &&
        plan.identity.isNotEmpty &&
        username.startsWith(
          plan.identity,
        )) {
      return 11;
    }

    if (jrCallId != null &&
        plan.identity.isNotEmpty &&
        jrCallId.startsWith(
          plan.identity,
        )) {
      return 12;
    }

    if (user.isDiscoverableByEmail &&
        email != null &&
        plan.email.isNotEmpty &&
        email.startsWith(
          plan.email,
        )) {
      return 13;
    }

    // -----------------------------------------------------------
    // CONTAINS
    // -----------------------------------------------------------

    return 20;
  }

  bool _phoneMatchesExactPlan(
      DiscoveryUser user,
      Iterable<String> candidates,
      ) {
    final String? normalizedPhone =
        user.normalizedPhone;

    final String? phoneDigits =
        user.phoneDigits;

    if (normalizedPhone == null &&
        phoneDigits == null) {
      return false;
    }

    for (final String candidate
    in candidates) {
      final String normalizedCandidate =
      normalizePhone(
        candidate,
      );

      final String candidateDigits =
      candidate.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      if (normalizedPhone != null &&
          normalizedCandidate.isNotEmpty &&
          normalizedPhone ==
              normalizedCandidate) {
        return true;
      }

      if (phoneDigits != null &&
          candidateDigits.isNotEmpty &&
          phoneDigits ==
              candidateDigits) {
        return true;
      }
    }

    return false;
  }

  // =============================================================
  // LEGACY FALLBACK
  //
  // Arbitrary substring search cannot be reconstructed from old
  // documents that never stored searchFragments without scanning
  // the whole users collection.
  //
  // Therefore:
  // - exact public identities are preserved;
  // - exact email/phone compatibility is preserved;
  // - old name prefix search is preserved;
  // - profile/auth updates progressively self-heal searchFragments.
  // =============================================================

  Future<DiscoveryPage> _legacyFallbackPage(
      String value, {
        required DiscoverySearchType type,
        required int limit,
        required DocumentSnapshot<Map<String, dynamic>>? cursor,
        required bool excludeCurrentUser,
      }) async {
    if (cursor != null) {
      return DiscoveryPage.empty;
    }

    switch (type) {
      case DiscoverySearchType.jrCallId:
        return _singleResultPage(
          await searchByJrCallId(
            value,
            excludeCurrentUser:
            excludeCurrentUser,
          ),
        );

      case DiscoverySearchType.username:
        return _singleResultPage(
          await searchByUsername(
            value,
            excludeCurrentUser:
            excludeCurrentUser,
          ),
        );

      case DiscoverySearchType.email:
        return _singleResultPage(
          await searchByEmail(
            value,
            excludeCurrentUser:
            excludeCurrentUser,
            skipIndexedSearch: true,
          ),
        );

      case DiscoverySearchType.phone:
        return _singleResultPage(
          await searchByPhone(
            value,
            excludeCurrentUser:
            excludeCurrentUser,
            skipIndexedSearch: true,
          ),
        );

      case DiscoverySearchType.name:
        return _searchLegacyNamePrefix(
          value,
          limit: limit,
          excludeCurrentUser:
          excludeCurrentUser,
        );

      case DiscoverySearchType.automatic:
        final DiscoveryUser? exactUser =
        await _legacyAutomaticExact(
          value,
          excludeCurrentUser:
          excludeCurrentUser,
        );

        if (exactUser != null) {
          return _singleResultPage(
            exactUser,
          );
        }

        return _searchLegacyNamePrefix(
          value,
          limit: limit,
          excludeCurrentUser:
          excludeCurrentUser,
        );
    }
  }

  Future<DiscoveryUser?> _legacyAutomaticExact(
      String value, {
        required bool excludeCurrentUser,
      }) async {
    final String trimmed = value.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    if (_looksLikeEmail(
      trimmed,
    )) {
      final DiscoveryUser? emailUser =
      await searchByEmail(
        trimmed,
        excludeCurrentUser:
        excludeCurrentUser,
        skipIndexedSearch: true,
      );

      if (emailUser != null) {
        return emailUser;
      }
    }

    if (_looksLikePhone(
      trimmed,
    )) {
      final DiscoveryUser? phoneUser =
      await searchByPhone(
        trimmed,
        excludeCurrentUser:
        excludeCurrentUser,
        skipIndexedSearch: true,
      );

      if (phoneUser != null) {
        return phoneUser;
      }
    }

    final DiscoveryUser? usernameUser =
    await searchByUsername(
      trimmed,
      excludeCurrentUser:
      excludeCurrentUser,
    );

    if (usernameUser != null) {
      return usernameUser;
    }

    return searchByJrCallId(
      trimmed,
      excludeCurrentUser:
      excludeCurrentUser,
    );
  }

  // =============================================================
  // JR CALL ID — EXACT COMPATIBILITY API
  // =============================================================

  Future<DiscoveryUser?> searchByJrCallId(
      String value, {
        bool excludeCurrentUser = true,
      }) async {
    final String normalized =
    normalizeJrCallId(
      value,
    );

    if (!isValidJrCallId(
      normalized,
    )) {
      return null;
    }

    // -----------------------------------------------------------
    // CURRENT RESERVATION
    // -----------------------------------------------------------

    final String? legacyUid =
    await _resolveReservationUid(
      collection: jrCallIdsCollection,
      normalizedValue: normalized,
    );

    if (legacyUid != null) {
      final DiscoveryUser? user =
      await getUserByUid(
        legacyUid,
        excludeCurrentUser:
        excludeCurrentUser,
      );

      if (user != null &&
          normalizeJrCallId(
            user.jrCallUserId ?? '',
          ) ==
              normalized) {
        return user;
      }
    }

    // -----------------------------------------------------------
    // OPTIONAL CANONICAL/FUTURE RESERVATION
    // -----------------------------------------------------------

    final String? canonicalUid =
    await _resolveReservationUid(
      collection:
      canonicalJrCallIdsCollection,
      normalizedValue: normalized,
    );

    if (canonicalUid != null) {
      final DiscoveryUser? user =
      await getUserByUid(
        canonicalUid,
        excludeCurrentUser:
        excludeCurrentUser,
      );

      if (user != null &&
          normalizeJrCallId(
            user.jrCallUserId ?? '',
          ) ==
              normalized) {
        return user;
      }
    }

    // -----------------------------------------------------------
    // LEGACY USER FIELDS
    // -----------------------------------------------------------

    const List<String> fields =
    <String>[
      'jrCallUserIdLowercase',
      'jrCallUserIdLower',
      'normalizedUserAddress',
      'userAddressLowercase',
      'userAddressLower',
      'jrCallUserId',
      'userAddress',
      'jrCallId',
    ];

    for (final String field
    in fields) {
      final DiscoveryUser? user =
      await _findExactUserByField(
        field: field,
        value: normalized,
        excludeCurrentUser:
        excludeCurrentUser,
        compare: (
            DiscoveryUser candidate,
            ) {
          return normalizeJrCallId(
            candidate.jrCallUserId ?? '',
          ) ==
              normalized;
        },
      );

      if (user != null) {
        return user;
      }
    }

    return null;
  }

  // =============================================================
  // USERNAME — EXACT COMPATIBILITY API
  // =============================================================

  Future<DiscoveryUser?> searchByUsername(
      String value, {
        bool excludeCurrentUser = true,
      }) async {
    final String normalized =
    normalizeUsername(
      value,
    );

    if (!isValidUsername(
      normalized,
    )) {
      return null;
    }

    final String? reservedUid =
    await _resolveReservationUid(
      collection: usernamesCollection,
      normalizedValue: normalized,
    );

    if (reservedUid != null) {
      final DiscoveryUser? user =
      await getUserByUid(
        reservedUid,
        excludeCurrentUser:
        excludeCurrentUser,
      );

      if (user != null &&
          normalizeUsername(
            user.username ?? '',
          ) ==
              normalized) {
        return user;
      }
    }

    const List<String> fields =
    <String>[
      'usernameLowercase',
      'usernameLower',
      'normalizedUsername',
      'username',
    ];

    for (final String field
    in fields) {
      final DiscoveryUser? user =
      await _findExactUserByField(
        field: field,
        value: normalized,
        excludeCurrentUser:
        excludeCurrentUser,
        compare: (
            DiscoveryUser candidate,
            ) {
          return normalizeUsername(
            candidate.username ?? '',
          ) ==
              normalized;
        },
      );

      if (user != null) {
        return user;
      }
    }

    return null;
  }

  // =============================================================
  // NAME
  //
  // Public API now uses GLOBAL CONTAINS search.
  // =============================================================

  Future<DiscoveryPage> searchByName(
      String value, {
        int limit = defaultPageSize,
        DocumentSnapshot<Map<String, dynamic>>? cursor,
        bool excludeCurrentUser = true,
      }) {
    return search(
      value,
      type: DiscoverySearchType.name,
      limit: limit,
      cursor: cursor,
      excludeCurrentUser:
      excludeCurrentUser,
    );
  }

  // =============================================================
  // LEGACY NAME PREFIX FALLBACK
  // =============================================================

  Future<DiscoveryPage> _searchLegacyNamePrefix(
      String value, {
        required int limit,
        required bool excludeCurrentUser,
      }) async {
    final String normalized =
    normalizeName(
      value,
    );

    if (normalized.isEmpty) {
      return DiscoveryPage.empty;
    }

    final int safeLimit =
    _safeLimit(
      limit,
    );

    const List<String> fields =
    <String>[
      'fullNameLowercase',
      'fullNameLower',
      'normalizedName',
      'nameLowercase',
      'nameLower',
    ];

    for (final String field
    in fields) {
      final DiscoveryPage page =
      await _queryLegacyNameField(
        field: field,
        normalized: normalized,
        limit: safeLimit,
        excludeCurrentUser:
        excludeCurrentUser,
      );

      if (page.users.isNotEmpty) {
        return page;
      }
    }

    return DiscoveryPage.empty;
  }

  Future<DiscoveryPage> _queryLegacyNameField({
    required String field,
    required String normalized,
    required int limit,
    required bool excludeCurrentUser,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
    await _users
        .orderBy(
      field,
    )
        .startAt(
      <Object?>[
        normalized,
      ],
    )
        .endAt(
      <Object?>[
        '$normalized\uf8ff',
      ],
    )
        .limit(
      limit,
    )
        .get();

    final List<DiscoveryUser> users =
    <DiscoveryUser>[];

    final Set<String> uids =
    <String>{};

    for (final QueryDocumentSnapshot<Map<String, dynamic>>
    document in snapshot.docs) {
      final DiscoveryUser? user =
      _acceptedDiscoveryUser(
        document,
        excludeCurrentUser:
        excludeCurrentUser,
      );

      if (user == null ||
          !uids.add(
            user.uid,
          )) {
        continue;
      }

      users.add(
        user,
      );
    }

    return DiscoveryPage(
      users:
      List<DiscoveryUser>.unmodifiable(
        users,
      ),
      hasMore: false,
    );
  }

  // =============================================================
  // EMAIL — EXACT COMPATIBILITY API
  // =============================================================

  Future<DiscoveryUser?> searchByEmail(
      String value, {
        bool excludeCurrentUser = true,
        bool skipIndexedSearch = false,
      }) async {
    final String normalized =
    normalizeEmail(
      value,
    );

    if (!_isValidEmail(
      normalized,
    )) {
      return null;
    }

    // -----------------------------------------------------------
    // CURRENT INDEX
    // -----------------------------------------------------------

    if (!skipIndexedSearch) {
      final DiscoveryPage page =
      await _searchIndexed(
        normalized,
        type: DiscoverySearchType.email,
        limit: 10,
        cursor: null,
        excludeCurrentUser:
        excludeCurrentUser,
      );

      for (final DiscoveryUser user
      in page.users) {
        if (user.isDiscoverableByEmail &&
            user.normalizedEmail ==
                normalized) {
          return user;
        }
      }
    }

    // -----------------------------------------------------------
    // LEGACY EXACT FIELDS
    // -----------------------------------------------------------

    const List<String> fields =
    <String>[
      'emailNormalized',
      'email',
    ];

    for (final String field
    in fields) {
      final DiscoveryUser? user =
      await _findExactUserByField(
        field: field,
        value: normalized,
        excludeCurrentUser:
        excludeCurrentUser,
        compare: (
            DiscoveryUser candidate,
            ) {
          return candidate
              .isDiscoverableByEmail &&
              candidate.normalizedEmail ==
                  normalized;
        },
      );

      if (user != null) {
        return user;
      }
    }

    return null;
  }

  // =============================================================
  // PHONE — EXACT COMPATIBILITY API
  // =============================================================

  Future<DiscoveryUser?> searchByPhone(
      String value, {
        bool excludeCurrentUser = true,
        bool skipIndexedSearch = false,
      }) async {
    final List<String> candidates =
    await _buildGlobalPhoneCandidates(
      value,
    );

    if (candidates.isEmpty) {
      return null;
    }

    // -----------------------------------------------------------
    // CURRENT UNIFIED INDEX
    // -----------------------------------------------------------

    if (!skipIndexedSearch) {
      final DiscoveryPage page =
      await _searchIndexed(
        value,
        type: DiscoverySearchType.phone,
        limit: 20,
        cursor: null,
        excludeCurrentUser:
        excludeCurrentUser,
      );

      for (final DiscoveryUser user
      in page.users) {
        if (!user.isDiscoverableByPhone) {
          continue;
        }

        if (_phoneMatchesExactCandidates(
          user,
          candidates,
        )) {
          return user;
        }
      }
    }

    // -----------------------------------------------------------
    // LEGACY phoneSearchKeys
    // -----------------------------------------------------------

    final List<String> safeCandidates =
    candidates
        .take(
      _maximumArrayContainsAnyValues,
    )
        .toList(
      growable: false,
    );

    if (safeCandidates.isNotEmpty) {
      try {
        final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _users
            .where(
          'phoneSearchKeys',
          arrayContainsAny:
          safeCandidates,
        )
            .limit(
          20,
        )
            .get();

        for (final QueryDocumentSnapshot<Map<String, dynamic>>
        document in snapshot.docs) {
          final DiscoveryUser? user =
          _acceptedDiscoveryUser(
            document,
            excludeCurrentUser:
            excludeCurrentUser,
          );

          if (user == null ||
              !user.isDiscoverableByPhone) {
            continue;
          }

          if (_phoneMatchesExactCandidates(
            user,
            candidates,
          )) {
            return user;
          }
        }
      } on FirebaseException {
        // Continue through older fields.
      }
    }

    // -----------------------------------------------------------
    // OLDER PHONE FIELDS
    // -----------------------------------------------------------

    const List<String> fields =
    <String>[
      'phoneNormalized',
      'phoneNumber',
      'phone',
    ];

    for (final String field
    in fields) {
      for (final String candidate
      in candidates) {
        final DiscoveryUser? user =
        await _findExactUserByField(
          field: field,
          value: candidate,
          excludeCurrentUser:
          excludeCurrentUser,
          compare: (
              DiscoveryUser result,
              ) {
            return result
                .isDiscoverableByPhone &&
                _phoneMatchesExactCandidates(
                  result,
                  candidates,
                );
          },
        );

        if (user != null) {
          return user;
        }
      }
    }

    return null;
  }

  bool _phoneMatchesExactCandidates(
      DiscoveryUser user,
      Iterable<String> candidates,
      ) {
    final String? phone =
        user.normalizedPhone;

    final String? digits =
        user.phoneDigits;

    if (phone == null &&
        digits == null) {
      return false;
    }

    for (final String candidate
    in candidates) {
      final String normalized =
      normalizePhone(
        candidate,
      );

      final String candidateDigits =
      candidate.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      if (phone != null &&
          normalized.isNotEmpty &&
          phone == normalized) {
        return true;
      }

      if (digits != null &&
          candidateDigits.isNotEmpty &&
          digits == candidateDigits) {
        return true;
      }
    }

    return false;
  }

  // =============================================================
  // PHONE CONTAINS CANDIDATES
  //
  // Unlike exact phone validation, this supports a single digit.
  //
  // Example:
  // "7"
  // "017"
  // "5222"
  // "+88017"
  //
  // Full local numbers additionally receive country-assisted
  // international alternatives.
  // =============================================================

  Future<List<String>> _buildPhoneContainsCandidates(
      String value,
      ) async {
    final String trimmed =
    value.trim();

    if (trimmed.isEmpty ||
        !_isPhoneCompatibleText(
          trimmed,
        )) {
      return const <String>[];
    }

    final LinkedHashSet<String> candidates =
    LinkedHashSet<String>();

    void addCandidate(
        String? raw,
        ) {
      final String candidate =
          raw?.trim() ?? '';

      if (candidate.isEmpty) {
        return;
      }

      candidates.add(
        candidate,
      );
    }

    final bool hasPlus =
    trimmed.startsWith('+');

    final String digits =
    trimmed.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (digits.isEmpty) {
      return const <String>[];
    }

    addCandidate(
      hasPlus
          ? '+$digits'
          : digits,
    );

    addCandidate(
      digits,
    );

    // 00 international prefix.
    if (digits.startsWith('00') &&
        digits.length > 2) {
      final String international =
      digits.substring(
        2,
      );

      addCandidate(
        international,
      );

      addCandidate(
        '+$international',
      );
    }

    // Country conversion is only meaningful for a sufficiently
    // complete local number. Never turn one digit into a fake
    // international search value.
    if (!hasPlus &&
        digits.length >= 6) {
      final Country? country =
      await _resolveCurrentUserCountry();

      if (country != null) {
        final String phoneCode =
        country.phoneCode.replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );

        if (phoneCode.isNotEmpty) {
          if (digits.startsWith('0') &&
              digits.length > 1) {
            final String withoutTrunk =
            digits.substring(
              1,
            );

            addCandidate(
              '$phoneCode$withoutTrunk',
            );

            addCandidate(
              '+$phoneCode$withoutTrunk',
            );
          }

          addCandidate(
            '$phoneCode$digits',
          );

          addCandidate(
            '+$phoneCode$digits',
          );
        }
      }
    }

    return List<String>.unmodifiable(
      candidates,
    );
  }

  // =============================================================
  // GLOBAL PHONE CANDIDATES — EXACT
  // =============================================================

  Future<List<String>> _buildGlobalPhoneCandidates(
      String value,
      ) async {
    final String trimmed =
    value.trim();

    if (trimmed.isEmpty) {
      return const <String>[];
    }

    final LinkedHashSet<String> candidates =
    LinkedHashSet<String>();

    void addCandidate(
        String? value,
        ) {
      final String candidate =
          value?.trim() ?? '';

      if (candidate.isNotEmpty &&
          _isValidPhoneQuery(
            candidate,
          )) {
        candidates.add(
          candidate,
        );
      }
    }

    final String normalized =
    normalizePhone(
      trimmed,
    );

    if (normalized.isEmpty) {
      return const <String>[];
    }

    for (final String candidate
    in _basicPhoneCandidates(
      trimmed,
    )) {
      addCandidate(
        candidate,
      );
    }

    final String rawDigits =
    trimmed.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    // 00880... -> +880...
    if (rawDigits.startsWith('00') &&
        rawDigits.length > 2) {
      final String international =
      rawDigits.substring(
        2,
      );

      addCandidate(
        '+$international',
      );

      addCandidate(
        international,
      );
    }

    // 880... -> +880...
    if (!normalized.startsWith('+')) {
      final String digits =
      normalized.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      if (digits.length >= 8 &&
          digits.length <= 15 &&
          !digits.startsWith('0')) {
        addCandidate(
          '+$digits',
        );
      }
    }

    // Local number -> current user's country calling code.
    final Country? country =
    await _resolveCurrentUserCountry();

    if (country != null &&
        !normalized.startsWith('+')) {
      final String phoneCode =
      country.phoneCode.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      final String digits =
      normalized.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      if (phoneCode.isNotEmpty &&
          digits.isNotEmpty) {
        if (digits.startsWith('0') &&
            digits.length > 1) {
          final String localWithoutTrunk =
          digits.substring(
            1,
          );

          addCandidate(
            '+$phoneCode$localWithoutTrunk',
          );

          addCandidate(
            '$phoneCode$localWithoutTrunk',
          );
        }

        addCandidate(
          '+$phoneCode$digits',
        );

        addCandidate(
          '$phoneCode$digits',
        );
      }
    }

    return List<String>.unmodifiable(
      candidates,
    );
  }

  // =============================================================
  // BASIC PHONE CANDIDATES
  // =============================================================

  List<String> _basicPhoneCandidates(
      String value,
      ) {
    final String trimmed =
    value.trim();

    if (trimmed.isEmpty) {
      return const <String>[];
    }

    final LinkedHashSet<String> candidates =
    LinkedHashSet<String>();

    final String normalized =
    normalizePhone(
      trimmed,
    );

    if (normalized.isEmpty) {
      return const <String>[];
    }

    if (_isValidPhoneQuery(
      normalized,
    )) {
      candidates.add(
        normalized,
      );
    }

    final String digits =
    normalized.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (_isValidLocalPhone(
      digits,
    )) {
      candidates.add(
        digits,
      );
    }

    if (normalized.startsWith('+') &&
        _isValidE164Phone(
          normalized,
        )) {
      candidates.add(
        normalized,
      );

      candidates.add(
        normalized.substring(
          1,
        ),
      );
    }

    final String rawDigits =
    trimmed.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (rawDigits.startsWith('00') &&
        rawDigits.length > 2) {
      final String without00 =
      rawDigits.substring(
        2,
      );

      if (_isValidE164Phone(
        '+$without00',
      )) {
        candidates.add(
          '+$without00',
        );

        candidates.add(
          without00,
        );
      }
    }

    return List<String>.unmodifiable(
      candidates,
    );
  }

  // =============================================================
  // COUNTRY RESOLUTION
  // =============================================================

  Future<Country?> _resolveCurrentUserCountry() async {
    final String uid =
        _auth.currentUser?.uid.trim() ?? '';

    if (uid.isEmpty) {
      return null;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
      await _users
          .doc(
        uid,
      )
          .get();

      final Map<String, dynamic> data =
          snapshot.data() ??
              const <String, dynamic>{};

      final String? storedCode =
      _firstNonEmptyString(
        <Object?>[
          data['countryCode'],
          data['countryIsoCode'],
          data['isoCountryCode'],
        ],
      );

      final Country? country =
      _resolveCountryFromStoredCode(
        storedCode,
      );

      if (country != null) {
        return country;
      }

      final String? phone =
      _firstNonEmptyString(
        <Object?>[
          data['phoneNormalized'],
          data['phoneNumber'],
          data['phone'],
          _auth.currentUser?.phoneNumber,
        ],
      );

      return _inferCountryFromE164(
        phone,
      );
    } catch (_) {
      return null;
    }
  }

  Country? _resolveCountryFromStoredCode(
      String? value,
      ) {
    final String clean =
        value?.trim() ?? '';

    if (clean.isEmpty) {
      return null;
    }

    if (RegExp(
      r'^[A-Za-z]{2}$',
    ).hasMatch(
      clean,
    )) {
      return _countryService.findByCode(
        clean.toUpperCase(),
      );
    }

    final String phoneCode =
    clean.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    return phoneCode.isEmpty
        ? null
        : _countryService.findByPhoneCode(
      phoneCode,
    );
  }

  Country? _inferCountryFromE164(
      String? rawPhone,
      ) {
    final String phone =
    normalizePhone(
      rawPhone ?? '',
    );

    if (!_isValidE164Phone(
      phone,
    )) {
      return null;
    }

    final String digits =
    phone.substring(
      1,
    );

    Country? bestMatch;

    int bestLength = 0;

    for (final Country country
    in _countryService.getAll()) {
      final String code =
      country.phoneCode.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      if (code.isEmpty ||
          !digits.startsWith(
            code,
          )) {
        continue;
      }

      if (code.length > bestLength) {
        bestLength =
            code.length;

        bestMatch =
            country;
      }
    }

    return bestMatch;
  }

  // =============================================================
  // UID
  // =============================================================

  Future<DiscoveryUser?> getUserByUid(
      String uid, {
        bool excludeCurrentUser = false,
      }) async {
    final String normalizedUid =
    uid.trim();

    if (normalizedUid.isEmpty) {
      return null;
    }

    final DocumentSnapshot<Map<String, dynamic>> document =
    await _users
        .doc(
      normalizedUid,
    )
        .get();

    if (!document.exists) {
      return null;
    }

    return _acceptedDiscoveryUser(
      document,
      excludeCurrentUser:
      excludeCurrentUser,
    );
  }

  Future<String?> resolveUid(
      String value, {
        DiscoverySearchType type =
            DiscoverySearchType.automatic,
      }) async {
    final DiscoveryPage result =
    await search(
      value,
      type: type,
      limit: 1,
      excludeCurrentUser: false,
    );

    if (result.users.isEmpty) {
      return null;
    }

    final String uid =
    result.users.first.uid.trim();

    return uid.isEmpty
        ? null
        : uid;
  }

  Future<DiscoveryUser?> resolveUser(
      String value, {
        DiscoverySearchType type =
            DiscoverySearchType.automatic,
        bool excludeCurrentUser = true,
      }) async {
    final DiscoveryPage result =
    await search(
      value,
      type: type,
      limit: 1,
      excludeCurrentUser:
      excludeCurrentUser,
    );

    return result.users.isEmpty
        ? null
        : result.users.first;
  }

  // =============================================================
  // EXACT FIELD
  // =============================================================

  Future<DiscoveryUser?> _findExactUserByField({
    required String field,
    required String value,
    required bool excludeCurrentUser,
    bool Function(DiscoveryUser user)? compare,
  }) async {
    final String cleanField =
    field.trim();

    final String cleanValue =
    value.trim();

    if (cleanField.isEmpty ||
        cleanValue.isEmpty) {
      return null;
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot =
    await _users
        .where(
      cleanField,
      isEqualTo: cleanValue,
    )
        .limit(
      5,
    )
        .get();

    final Set<String> checkedUids =
    <String>{};

    for (final QueryDocumentSnapshot<Map<String, dynamic>>
    document in snapshot.docs) {
      final DiscoveryUser? user =
      _acceptedDiscoveryUser(
        document,
        excludeCurrentUser:
        excludeCurrentUser,
      );

      if (user == null ||
          !checkedUids.add(
            user.uid,
          )) {
        continue;
      }

      if (compare != null &&
          !compare(
            user,
          )) {
        continue;
      }

      return user;
    }

    return null;
  }

  // =============================================================
  // RESERVATIONS
  // =============================================================

  Future<String?> _resolveReservationUid({
    required String collection,
    required String normalizedValue,
  }) async {
    final String collectionName =
    collection.trim();

    final String documentId =
    normalizedValue.trim();

    if (collectionName.isEmpty ||
        documentId.isEmpty) {
      return null;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> reservation =
      await _firestore
          .collection(
        collectionName,
      )
          .doc(
        documentId,
      )
          .get();

      if (!reservation.exists) {
        return null;
      }

      final Map<String, dynamic> data =
          reservation.data() ??
              const <String, dynamic>{};

      return _firstNonEmptyString(
        <Object?>[
          data['uid'],
          data['ownerUid'],
          data['userId'],
        ],
      );
    } on FirebaseException {
      return null;
    }
  }

  // =============================================================
  // PRIVACY FILTER
  // =============================================================

  DiscoveryUser? _acceptedDiscoveryUser(
      DocumentSnapshot<Map<String, dynamic>> document, {
        required bool excludeCurrentUser,
      }) {
    if (!document.exists) {
      return null;
    }

    final Map<String, dynamic> data =
        document.data() ??
            const <String, dynamic>{};

    if (_readBool(
      data['isDeleted'],
    ) ==
        true) {
      return null;
    }

    if (_readBool(
      data['isBlocked'],
    ) ==
        true) {
      return null;
    }

    final DiscoveryUser user =
    DiscoveryUser.fromDocument(
      document,
    );

    if (user.uid.trim().isEmpty ||
        !user.isDiscoverable) {
      return null;
    }

    final String currentUid =
        _auth.currentUser?.uid.trim() ?? '';

    if (excludeCurrentUser &&
        currentUid.isNotEmpty &&
        currentUid ==
            user.uid.trim()) {
      return null;
    }

    return user;
  }

  // =============================================================
  // NORMALIZATION
  // =============================================================

  String normalizeJrCallId(
      String value,
      ) {
    return _normalizePublicIdentityValue(
      value,
    );
  }

  String normalizeUsername(
      String value,
      ) {
    return _normalizePublicIdentityValue(
      value,
    );
  }

  String normalizeName(
      String value,
      ) {
    return _normalizeSearchTextValue(
      value,
    );
  }

  String normalizeEmail(
      String value,
      ) {
    return value
        .trim()
        .toLowerCase();
  }

  String normalizePhone(
      String value,
      ) {
    return _normalizePhoneValue(
      value,
    );
  }

  String _normalizePublicIdentityQuery(
      String value,
      ) {
    return _normalizePublicIdentityValue(
      value,
    );
  }

  // =============================================================
  // VALIDATION
  // =============================================================

  bool isValidUsername(
      String value,
      ) {
    final String normalized =
    normalizeUsername(
      value,
    );

    return RegExp(
      r'^[a-z0-9._]{3,30}$',
    ).hasMatch(
      normalized,
    ) &&
        !normalized.startsWith('.') &&
        !normalized.endsWith('.') &&
        !normalized.contains('..');
  }

  bool isValidJrCallId(
      String value,
      ) {
    final String normalized =
    normalizeJrCallId(
      value,
    );

    return RegExp(
      r'^[a-z0-9._-]{3,64}$',
    ).hasMatch(
      normalized,
    ) &&
        !normalized.startsWith('.') &&
        !normalized.endsWith('.') &&
        !normalized.contains('..');
  }

  bool isValidEmail(
      String value,
      ) {
    return _isValidEmail(
      normalizeEmail(
        value,
      ),
    );
  }

  bool isValidPhone(
      String value,
      ) {
    final String normalized =
    normalizePhone(
      value,
    );

    if (_isValidPhoneQuery(
      normalized,
    )) {
      return true;
    }

    final String digits =
    normalized.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    return digits.startsWith('00') &&
        digits.length > 2 &&
        _isValidE164Phone(
          '+${digits.substring(2)}',
        );
  }

  bool _isValidEmail(
      String value,
      ) {
    return value.isNotEmpty &&
        value.length <= 254 &&
        RegExp(
          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
        ).hasMatch(
          value,
        );
  }

  bool _isValidE164Phone(
      String value,
      ) {
    return RegExp(
      r'^\+[1-9]\d{7,14}$',
    ).hasMatch(
      value,
    );
  }

  bool _isValidLocalPhone(
      String value,
      ) {
    return RegExp(
      r'^\d{6,15}$',
    ).hasMatch(
      value,
    );
  }

  bool _isValidPhoneQuery(
      String value,
      ) {
    if (value.isEmpty) {
      return false;
    }

    return value.startsWith('+')
        ? _isValidE164Phone(
      value,
    )
        : _isValidLocalPhone(
      value,
    );
  }

  bool _looksLikeEmail(
      String value,
      ) {
    return _isValidEmail(
      normalizeEmail(
        value,
      ),
    );
  }

  bool _looksLikePhone(
      String value,
      ) {
    final String trimmed =
    value.trim();

    if (trimmed.isEmpty ||
        !_isPhoneCompatibleText(
          trimmed,
        )) {
      return false;
    }

    final String digits =
    trimmed.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    return digits.length >= 6 &&
        digits.length <= 17;
  }

  bool _isPhoneCompatibleText(
      String value,
      ) {
    final String trimmed =
    value.trim();

    if (trimmed.isEmpty) {
      return false;
    }

    return RegExp(
      r'^[0-9+\-().\s]+$',
    ).hasMatch(
      trimmed,
    );
  }

  // =============================================================
  // HELPERS
  // =============================================================

  int _safeLimit(
      int value,
      ) {
    if (value < 1) {
      return 1;
    }

    return value > maximumPageSize
        ? maximumPageSize
        : value;
  }

  DiscoveryPage _singleResultPage(
      DiscoveryUser? user,
      ) {
    return user == null
        ? DiscoveryPage.empty
        : DiscoveryPage(
      users:
      List<DiscoveryUser>.unmodifiable(
        <DiscoveryUser>[
          user,
        ],
      ),
      hasMore: false,
    );
  }
}

// ===============================================================
// PRIVATE QUERY PLAN
// ===============================================================

class _DiscoveryQueryPlan {
  const _DiscoveryQueryPlan({
    required this.type,
    required this.raw,
    required this.text,
    required this.identity,
    required this.email,
    required this.phoneFragments,
    required this.indexFragments,
  });

  final DiscoverySearchType type;

  final String raw;

  final String text;

  final String identity;

  final String email;

  final List<String> phoneFragments;

  final List<String> indexFragments;
}

// ===============================================================
// PRIVATE SEARCH HIT
// ===============================================================

class _DiscoveryHit {
  const _DiscoveryHit({
    required this.user,
    required this.document,
    required this.rank,
  });

  final DiscoveryUser user;

  final DocumentSnapshot<Map<String, dynamic>> document;

  final int rank;
}

// ===============================================================
// SHARED NORMALIZATION
// ===============================================================

String _normalizeSearchTextValue(
    String value,
    ) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
}

String _normalizePublicIdentityValue(
    String value,
    ) {
  String normalized =
  value
      .trim()
      .toLowerCase();

  if (normalized.startsWith('@')) {
    normalized =
        normalized.substring(
          1,
        );
  }

  return normalized.trim();
}

String _normalizePhoneValue(
    String value,
    ) {
  final String trimmed =
  value.trim();

  if (trimmed.isEmpty) {
    return '';
  }

  final bool hasPlus =
  trimmed.startsWith('+');

  final String digits =
  trimmed.replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );

  if (digits.isEmpty) {
    return '';
  }

  return hasPlus
      ? '+$digits'
      : digits;
}

// ===============================================================
// SHARED PARSING
// ===============================================================

String? _firstNonEmptyString(
    Iterable<Object?> values,
    ) {
  for (final Object? value
  in values) {
    if (value is! String) {
      continue;
    }

    final String normalized =
    value.trim();

    if (normalized.isEmpty) {
      continue;
    }

    if (normalized.toLowerCase() ==
        'null') {
      continue;
    }

    return normalized;
  }

  return null;
}

bool? _readBool(
    Object? value,
    ) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    if (value == 1) {
      return true;
    }

    if (value == 0) {
      return false;
    }
  }

  if (value is String) {
    switch (value
        .trim()
        .toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'y':
        return true;

      case 'false':
      case '0':
      case 'no':
      case 'n':
        return false;
    }
  }

  return null;
}

// ===============================================================
// END OF FILE
//
// FILE 5 — GLOBAL DISCOVERY GUARANTEES
//
// SEARCH:
// ✓ Full Name contains
// ✓ Username contains
// ✓ JR CALL ID contains
// ✓ Email contains only when permitted
// ✓ Phone contains only when permitted
// ✓ Single-character indexed search
// ✓ Single-digit indexed search
// ✓ Beginning / middle / ending substring matching
// ✓ Case-insensitive matching
// ✓ @ normalization
// ✓ Phone formatting normalization
//
// GLOBAL PHONE:
// ✓ E.164
// ✓ International 00 prefix
// ✓ Country-code form
// ✓ Digits-only form
// ✓ Current-user country assisted local full-number resolution
// ✓ Legacy phoneSearchKeys fallback
// ✓ Legacy phoneNormalized fallback
// ✓ Legacy phoneNumber fallback
// ✓ Legacy phone fallback
//
// SECURITY:
// ✓ Firebase UID is canonical internal identity
// ✓ Firebase UID is NOT a public search keyword
// ✓ Global discoverability respected
// ✓ Missing Email discovery consent = PRIVATE
// ✓ Missing Phone discovery consent = PRIVATE
// ✓ Blocked users rejected
// ✓ Deleted users rejected
// ✓ No full users collection download
//
// COMPATIBILITY:
// ✓ Existing DiscoverySearchType API preserved
// ✓ Existing DiscoveryUser API preserved
// ✓ Existing DiscoveryPage API preserved
// ✓ Existing resolveUid() preserved
// ✓ Existing resolveUser() preserved
// ✓ Exact Username lookup preserved
// ✓ Exact JR CALL ID lookup preserved
// ✓ Exact Email lookup preserved
// ✓ Exact Phone lookup preserved
// ✓ Reservation compatibility preserved
// ✓ CountryService compatibility preserved
//
// PAGINATION:
// ✓ DocumentSnapshot cursor preserved
// ✓ Stable Firestore document ordering
// ✓ No accepted next-page result intentionally skipped
//
// PROTECTED:
// ✓ Call Engine untouched
// ✓ Message Engine untouched
// ✓ WebRTC untouched
// ✓ OTP/Auth ownership untouched
//
// IMPORTANT:
// Existing legacy profiles without searchFragments cannot support
// arbitrary middle-substring discovery until their search index is
// created/refreshed. FILE 4 progressively self-heals this on profile
// and authentication updates. A one-time production backfill can be
// added separately if every historic offline account must become
// substring-searchable immediately.
//
// NEXT:
// FILE 6
// lib/services/contact_discovery_service.dart
// ===============================================================