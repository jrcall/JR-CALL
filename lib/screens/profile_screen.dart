// ===============================================================
// JR CALL
// File: profile_screen.dart
// Location: lib/screens/profile_screen.dart
//
// FINAL PRODUCTION PROFILE COORDINATOR
//
// OWNERSHIP:
//
// ✓ Own Profile loading.
// ✓ Own Profile in-memory fast cache.
// ✓ Firestore Profile refresh.
// ✓ Realtime Profile stream.
// ✓ Guest Profile entry.
// ✓ Public / Contact Profile.
// ✓ Full Name editing.
// ✓ Username editing.
// ✓ JR CALL User ID editing.
// ✓ Bio editing.
// ✓ Country editing.
// ✓ Date of Birth editing.
// ✓ Profile photo upload/remove.
// ✓ Cover photo upload/remove.
// ✓ Public Profile actions.
// ✓ Profile Studio coordination.
// ✓ Authentication account-information display.
//
// PERFORMANCE:
//
// ✓ Previously loaded own profile opens immediately from memory.
// ✓ Existing profile is not blanked during refresh.
// ✓ Realtime listener binds without unnecessary recreation.
// ✓ Expensive ensure/sync operation runs after first display.
// ✓ Duplicate initialization is single-flight protected.
// ✓ Background refresh cannot overwrite another Firebase UID.
// ✓ Public profile remains visible during refresh.
// ✓ Image/network work does not block ProfileScreen construction.
//
// SECURITY:
//
// ✓ Firebase UID remains canonical private identity.
// ✓ JR CALL ID remains public searchable identity.
// ✓ No password persistence.
// ✓ No OTP persistence.
// ✓ Email/Password ownership remains Settings/AuthService.
// ✓ Phone OTP remains Firebase Authentication owned.
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
//
// IMPORTANT:
//
// profile_screen_part2.dart DOES NOT EXIST.
// This file is the complete ProfileScreen implementation.
// ===============================================================

import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/contact_model.dart';
import '../models/user_model.dart';
import '../services/firebase/firestore_service.dart' show UserProfileField;
import '../services/profile_service.dart';
import '../utils/permissions.dart';
import '../widgets/caller_avatar.dart';
import 'create_account_screen.dart';
import 'login_screen.dart';
import 'profile_studio_screen.dart';

// ===============================================================
// MEDIA PICKER CONTRACT
// ===============================================================

typedef ProfileMediaPicker = Future<String?> Function();

// ===============================================================
// PROFILE SCREEN
// ===============================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.contact,
    this.onPickProfilePhoto,
    this.onPickCoverPhoto,
    this.onVoiceCall,
    this.onVideoCall,
    this.onMessage,
    this.onBlockContact,
    this.onDeleteContact,
  });

  final ContactModel? contact;

  final ProfileMediaPicker? onPickProfilePhoto;
  final ProfileMediaPicker? onPickCoverPhoto;

  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onMessage;
  final VoidCallback? onBlockContact;
  final VoidCallback? onDeleteContact;

  bool get isContactProfile => contact != null;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

// ===============================================================
// STATE
// ===============================================================

class _ProfileScreenState extends State<ProfileScreen> {
  // =============================================================
  // MEDIA LIMITS
  // =============================================================

  static const int _profileMaxBytes = 5 * 1024 * 1024;
  static const int _coverMaxBytes = 10 * 1024 * 1024;

  // =============================================================
  // DESIGN
  // =============================================================

  static const double _maxContentWidth = 760;

  static const Color _background = Color(0xFFF7F9FD);
  static const Color _surface = Colors.white;

  static const Color _primary = Color(0xFF1769F5);
  static const Color _violet = Color(0xFF7C3AED);
  static const Color _success = Color(0xFF16A34A);
  static const Color _error = Color(0xFFDC2626);

  static const Color _text = Color(0xFF111827);
  static const Color _secondary = Color(0xFF64748B);
  static const Color _border = Color(0xFFE5EAF2);

  // =============================================================
  // FAST SESSION CACHE
  //
  // Memory-only.
  // Never persisted.
  // =============================================================

  static final Map<String, UserModel> _profileMemoryCache =
  <String, UserModel>{};

  // =============================================================
  // SERVICES
  // =============================================================

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ProfileService _profileService = ProfileService.instance;
  final ImagePicker _picker = ImagePicker();

  // =============================================================
  // SUBSCRIPTIONS
  // =============================================================

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<UserModel?>? _profileSubscription;
  StreamSubscription<UserModel?>? _publicProfileSubscription;

  // =============================================================
  // OWN PROFILE
  // =============================================================

  UserModel? _user;

  Object? _loadError;

  bool _loading = true;
  bool _saving = false;
  bool _pickingMedia = false;

  String? _boundUid;

  int _loadGeneration = 0;

  // =============================================================
  // OWN PROFILE INITIALIZATION SINGLE-FLIGHT
  // =============================================================

  Future<void>? _initializeFuture;
  String? _initializingUid;

  // =============================================================
  // BACKGROUND REFRESH SINGLE-FLIGHT
  // =============================================================

  Future<void>? _backgroundRefreshFuture;
  String? _backgroundRefreshUid;

  // =============================================================
  // PUBLIC PROFILE
  // =============================================================

  UserModel? _publicUser;

  bool _publicProfileLoading = false;

  String? _publicBoundUid;

  // =============================================================
  // DERIVED
  // =============================================================

  User? get _firebaseUser => _auth.currentUser;

  bool get _authenticated => _firebaseUser != null;

  bool get _busy => _saving || _pickingMedia;

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _ensureAuthSubscription();

    if (widget.isContactProfile) {
      _loading = false;

      unawaited(
        _initializePublicProfile(),
      );

      return;
    }

    _restoreOwnProfileFromMemory();

    unawaited(
      _initialize(),
    );
  }

  @override
  void didUpdateWidget(
      covariant ProfileScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.contact == widget.contact) {
      return;
    }

    if (widget.isContactProfile) {
      unawaited(
        _switchToPublicProfile(),
      );
      return;
    }

    unawaited(
      _switchToOwnProfile(),
    );
  }

  @override
  void dispose() {
    _loadGeneration++;

    final StreamSubscription<User?>? authSubscription =
        _authSubscription;
    final StreamSubscription<UserModel?>? profileSubscription =
        _profileSubscription;
    final StreamSubscription<UserModel?>? publicSubscription =
        _publicProfileSubscription;

    _authSubscription = null;
    _profileSubscription = null;
    _publicProfileSubscription = null;

    if (authSubscription != null) {
      unawaited(
        authSubscription.cancel(),
      );
    }

    if (profileSubscription != null) {
      unawaited(
        profileSubscription.cancel(),
      );
    }

    if (publicSubscription != null) {
      unawaited(
        publicSubscription.cancel(),
      );
    }

    super.dispose();
  }

  // =============================================================
  // AUTH SUBSCRIPTION
  // =============================================================

  void _ensureAuthSubscription() {
    if (_authSubscription != null) {
      return;
    }

    _authSubscription = _auth.userChanges().listen(
      _handleAuthStreamEvent,
      onError: (
          Object error,
          StackTrace stackTrace,
          ) {
        _reportError(
          'Auth stream',
          error,
          stackTrace,
        );
      },
    );
  }

  // =============================================================
  // MODE SWITCH
  // =============================================================

  Future<void> _switchToPublicProfile() async {
    _loadGeneration++;

    await _cancelOwnProfileSubscription();

    if (!mounted) {
      return;
    }

    setState(() {
      _user = null;
      _boundUid = null;
      _loadError = null;
      _loading = false;
    });

    await _initializePublicProfile(
      force: true,
    );
  }

  Future<void> _switchToOwnProfile() async {
    _ensureAuthSubscription();

    await _cancelPublicProfileSubscription();

    if (!mounted) {
      return;
    }

    setState(() {
      _publicUser = null;
      _publicBoundUid = null;
      _publicProfileLoading = false;
    });

    _restoreOwnProfileFromMemory();

    await _initialize(
      force: true,
    );
  }

  // =============================================================
  // FAST MEMORY RESTORE
  // =============================================================

  void _restoreOwnProfileFromMemory() {
    final User? firebaseUser = _firebaseUser;

    if (firebaseUser == null) {
      return;
    }

    final String uid = firebaseUser.uid.trim();

    if (uid.isEmpty) {
      return;
    }

    final UserModel? cached = _profileMemoryCache[uid];

    if (cached == null || cached.isDeleted) {
      return;
    }

    _boundUid = uid;
    _user = cached;
    _loading = false;
    _loadError = null;
  }

  void _cacheProfile(
      UserModel profile,
      ) {
    final String uid = profile.uid.trim();

    if (uid.isEmpty) {
      return;
    }

    if (profile.isDeleted) {
      _profileMemoryCache.remove(uid);
      return;
    }

    _profileMemoryCache[uid] = profile;
  }

  void _removeCachedProfile(
      String uid,
      ) {
    final String normalized = uid.trim();

    if (normalized.isEmpty) {
      return;
    }

    _profileMemoryCache.remove(
      normalized,
    );
  }

  // =============================================================
  // AUTH STREAM
  // =============================================================

  void _handleAuthStreamEvent(
      User? firebaseUser,
      ) {
    unawaited(
      _handleAuthChange(
        firebaseUser,
      ),
    );
  }

  Future<void> _handleAuthChange(
      User? firebaseUser,
      ) async {
    if (!mounted) {
      return;
    }

    if (widget.isContactProfile) {
      await _initializePublicProfile(
        force: true,
      );
      return;
    }

    final String? uid = _clean(
      firebaseUser?.uid,
    );

    if (uid == null) {
      await _cancelOwnProfileSubscription();

      if (!mounted) {
        return;
      }

      setState(() {
        _boundUid = null;
        _user = null;
        _loading = false;
        _loadError = null;
      });

      return;
    }

    if (uid == _boundUid &&
        _profileSubscription != null) {
      _scheduleBackgroundProfileRefresh(
        uid,
      );
      return;
    }

    final UserModel? cached = _profileMemoryCache[uid];

    if (cached != null &&
        !cached.isDeleted &&
        mounted) {
      setState(() {
        _boundUid = uid;
        _user = cached;
        _loading = false;
        _loadError = null;
      });
    }

    await _initialize(
      force: true,
    );
  }

  // =============================================================
  // OWN PROFILE INITIALIZATION
  // =============================================================

  Future<void> _initialize({
    bool force = false,
  }) {
    if (!mounted || widget.isContactProfile) {
      return Future<void>.value();
    }

    final String? requestedUid = _clean(
      _firebaseUser?.uid,
    );

    final Future<void>? running = _initializeFuture;

    if (running != null &&
        _initializingUid == requestedUid) {
      if (force && requestedUid != null) {
        _scheduleBackgroundProfileRefresh(
          requestedUid,
        );
      }

      return running;
    }

    final Future<void> operation =
    _initializeInternal(
      requestedUid: requestedUid,
      force: force,
    );

    _initializeFuture = operation;
    _initializingUid = requestedUid;

    operation.whenComplete(() {
      if (!identical(
        _initializeFuture,
        operation,
      )) {
        return;
      }

      _initializeFuture = null;
      _initializingUid = null;
    });

    return operation;
  }

  Future<void> _initializeInternal({
    required String? requestedUid,
    required bool force,
  }) async {
    if (!mounted || widget.isContactProfile) {
      return;
    }

    final int generation = ++_loadGeneration;

    try {
      final User? firebaseUser = _firebaseUser;

      // ---------------------------------------------------------
      // GUEST
      // ---------------------------------------------------------

      if (firebaseUser == null) {
        await _cancelOwnProfileSubscription();

        if (!_validLoad(
          generation,
        )) {
          return;
        }

        setState(() {
          _boundUid = null;
          _user = null;
          _loading = false;
          _loadError = null;
        });

        return;
      }

      final String uid = firebaseUser.uid.trim();

      if (uid.isEmpty) {
        throw StateError(
          'Authenticated Firebase UID is invalid.',
        );
      }

      if (requestedUid != null &&
          requestedUid != uid) {
        return;
      }

      // ---------------------------------------------------------
      // IMMEDIATE MEMORY PROFILE
      // ---------------------------------------------------------

      final UserModel? cached =
      _profileMemoryCache[uid];

      if (cached != null &&
          !cached.isDeleted &&
          _user == null &&
          _validOwnUser(
            generation,
            uid,
          )) {
        setState(() {
          _boundUid = uid;
          _user = cached;
          _loading = false;
          _loadError = null;
        });
      }

      // ---------------------------------------------------------
      // SAME PROFILE ALREADY DISPLAYED
      // ---------------------------------------------------------

      if (_boundUid == uid &&
          _user != null) {
        await _ensureOwnProfileStream(
          uid: uid,
          generation: generation,
        );

        if (force || cached == null) {
          _scheduleBackgroundProfileRefresh(
            uid,
          );
        }

        return;
      }

      if (_user == null &&
          _validOwnUser(
            generation,
            uid,
          )) {
        setState(() {
          _loading = true;
          _loadError = null;
        });
      }

      // ---------------------------------------------------------
      // FAST FIRESTORE PROFILE READ
      // ---------------------------------------------------------

      final UserModel? existing =
      await _profileService.getCurrentProfile();

      if (!_validOwnUser(
        generation,
        uid,
      )) {
        return;
      }

      if (existing != null) {
        if (existing.isDeleted) {
          _removeCachedProfile(
            uid,
          );

          throw StateError(
            'This JR CALL profile is no longer available.',
          );
        }

        _cacheProfile(
          existing,
        );

        setState(() {
          _boundUid = uid;
          _user = existing;
          _loading = false;
          _loadError = null;
        });

        await _ensureOwnProfileStream(
          uid: uid,
          generation: generation,
        );

        _scheduleBackgroundProfileRefresh(
          uid,
        );

        return;
      }

      // ---------------------------------------------------------
      // PROFILE MISSING
      //
      // Existing ProfileService ownership is preserved.
      // ---------------------------------------------------------

      final UserModel ensured =
      await _profileService.ensureCurrentProfile();

      if (!_validOwnUser(
        generation,
        uid,
      )) {
        return;
      }

      if (ensured.isDeleted) {
        _removeCachedProfile(
          uid,
        );

        throw StateError(
          'This JR CALL profile is no longer available.',
        );
      }

      final UserModel? freshest =
      await _profileService.getCurrentProfile();

      if (!_validOwnUser(
        generation,
        uid,
      )) {
        return;
      }

      final UserModel resolved =
          freshest ?? ensured;

      if (resolved.isDeleted) {
        _removeCachedProfile(
          uid,
        );

        throw StateError(
          'This JR CALL profile is no longer available.',
        );
      }

      _cacheProfile(
        resolved,
      );

      setState(() {
        _boundUid = uid;
        _user = resolved;
        _loading = false;
        _loadError = null;
      });

      await _ensureOwnProfileStream(
        uid: uid,
        generation: generation,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Own profile initialization',
        error,
        stackTrace,
      );

      if (!_validLoad(
        generation,
      )) {
        return;
      }

      // Never replace an already-visible valid profile
      // with a temporary refresh/read error.
      if (_user != null) {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }

        return;
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = error;
        });
      }
    }
  }

  // =============================================================
  // BACKGROUND PROFILE ENSURE / AUTH METADATA SYNC
  // =============================================================

  void _scheduleBackgroundProfileRefresh(
      String uid,
      ) {
    if (!mounted ||
        widget.isContactProfile ||
        _firebaseUser?.uid != uid) {
      return;
    }

    final Future<void>? running =
        _backgroundRefreshFuture;

    if (running != null &&
        _backgroundRefreshUid == uid) {
      return;
    }

    final Future<void> operation =
    _refreshProfileInBackground(
      uid,
    );

    _backgroundRefreshFuture = operation;
    _backgroundRefreshUid = uid;

    operation.whenComplete(() {
      if (!identical(
        _backgroundRefreshFuture,
        operation,
      )) {
        return;
      }

      _backgroundRefreshFuture = null;
      _backgroundRefreshUid = null;
    });
  }

  Future<void> _refreshProfileInBackground(
      String uid,
      ) async {
    try {
      if (!mounted ||
          _firebaseUser?.uid != uid) {
        return;
      }

      final UserModel ensured =
      await _profileService.ensureCurrentProfile();

      if (!mounted ||
          widget.isContactProfile ||
          _firebaseUser?.uid != uid) {
        return;
      }

      if (ensured.isDeleted) {
        _removeCachedProfile(
          uid,
        );
        return;
      }

      final UserModel? freshest =
      await _profileService.getCurrentProfile();

      if (!mounted ||
          widget.isContactProfile ||
          _firebaseUser?.uid != uid) {
        return;
      }

      final UserModel resolved =
          freshest ?? ensured;

      if (resolved.isDeleted) {
        _removeCachedProfile(
          uid,
        );
        return;
      }

      _cacheProfile(
        resolved,
      );

      if (!mounted ||
          _firebaseUser?.uid != uid) {
        return;
      }

      setState(() {
        _boundUid = uid;
        _user = resolved;
        _loading = false;
        _loadError = null;
      });
    } catch (error, stackTrace) {
      _reportError(
        'Background profile refresh',
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // OWN PROFILE REALTIME STREAM
  // =============================================================

  Future<void> _ensureOwnProfileStream({
    required String uid,
    required int generation,
  }) async {
    if (!_validOwnUser(
      generation,
      uid,
    )) {
      return;
    }

    if (_boundUid == uid &&
        _profileSubscription != null) {
      return;
    }

    await _cancelOwnProfileSubscription();

    if (!_validOwnUser(
      generation,
      uid,
    )) {
      return;
    }

    _boundUid = uid;

    _profileSubscription =
        _profileService.profileStream(uid).listen(
              (UserModel? profile) {
            if (!mounted ||
                widget.isContactProfile ||
                _firebaseUser?.uid != uid ||
                profile == null) {
              return;
            }

            if (profile.isDeleted) {
              _removeCachedProfile(
                uid,
              );

              setState(() {
                _user = null;
                _loading = false;
                _loadError = StateError(
                  'This JR CALL profile is no longer available.',
                );
              });

              return;
            }

            _cacheProfile(
              profile,
            );

            setState(() {
              _boundUid = uid;
              _user = profile;
              _loading = false;
              _loadError = null;
            });
          },
          onError: (
              Object error,
              StackTrace stackTrace,
              ) {
            _reportError(
              'Own profile stream',
              error,
              stackTrace,
            );

            if (!mounted ||
                _firebaseUser?.uid != uid) {
              return;
            }

            if (_user != null) {
              return;
            }

            setState(() {
              _loading = false;
              _loadError = error;
            });
          },
        );
  }

  Future<void> _cancelOwnProfileSubscription() async {
    final StreamSubscription<UserModel?>? previous =
        _profileSubscription;

    _profileSubscription = null;

    if (previous != null) {
      await previous.cancel();
    }
  }

  bool _validLoad(
      int generation,
      ) {
    return mounted &&
        generation == _loadGeneration;
  }

  bool _validOwnUser(
      int generation,
      String uid,
      ) {
    return _validLoad(
      generation,
    ) &&
        _firebaseUser?.uid == uid;
  }

  // =============================================================
  // PUBLIC PROFILE
  // =============================================================

  Future<void> _initializePublicProfile({
    bool force = false,
  }) async {
    final ContactModel? contact = widget.contact;

    if (contact == null || !mounted) {
      return;
    }

    final String? uid = _clean(
      contact.resolvedUid,
    );

    if (!_authenticated || uid == null) {
      await _cancelPublicProfileSubscription();

      if (!mounted) {
        return;
      }

      setState(() {
        _publicUser = null;
        _publicBoundUid = null;
        _publicProfileLoading = false;
      });

      return;
    }

    final UserModel? cached =
    _profileMemoryCache[uid];

    if (cached != null &&
        !cached.isDeleted &&
        _publicUser == null) {
      _publicUser = cached;
      _publicBoundUid = uid;
      _publicProfileLoading = false;
    }

    if (!force &&
        _publicBoundUid == uid &&
        _publicUser != null &&
        _publicProfileSubscription != null) {
      return;
    }

    if (_publicUser == null && mounted) {
      setState(() {
        _publicProfileLoading = true;
      });
    }

    try {
      final UserModel? profile =
      await _profileService.getProfile(
        uid,
      );

      if (!_isCurrentPublicUid(
        uid,
      )) {
        return;
      }

      if (profile == null ||
          profile.isDeleted) {
        _removeCachedProfile(
          uid,
        );

        setState(() {
          _publicUser = null;
          _publicBoundUid = uid;
          _publicProfileLoading = false;
        });

        await _bindPublicProfileStream(
          uid,
        );

        return;
      }

      _cacheProfile(
        profile,
      );

      setState(() {
        _publicUser = profile;
        _publicBoundUid = uid;
        _publicProfileLoading = false;
      });

      await _bindPublicProfileStream(
        uid,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Public profile load',
        error,
        stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _publicProfileLoading = false;
      });
    }
  }

  Future<void> _bindPublicProfileStream(
      String uid,
      ) async {
    if (!_isCurrentPublicUid(
      uid,
    )) {
      return;
    }

    if (_publicBoundUid == uid &&
        _publicProfileSubscription != null) {
      return;
    }

    await _cancelPublicProfileSubscription();

    if (!_isCurrentPublicUid(
      uid,
    )) {
      return;
    }

    _publicBoundUid = uid;

    _publicProfileSubscription =
        _profileService.profileStream(uid).listen(
              (UserModel? profile) {
            if (!_isCurrentPublicUid(
              uid,
            ) ||
                profile == null) {
              return;
            }

            if (profile.isDeleted) {
              _removeCachedProfile(
                uid,
              );

              setState(() {
                _publicUser = null;
                _publicProfileLoading = false;
              });

              return;
            }

            _cacheProfile(
              profile,
            );

            setState(() {
              _publicUser = profile;
              _publicBoundUid = uid;
              _publicProfileLoading = false;
            });
          },
          onError: (
              Object error,
              StackTrace stackTrace,
              ) {
            _reportError(
              'Public profile stream',
              error,
              stackTrace,
            );

            if (!_isCurrentPublicUid(
              uid,
            )) {
              return;
            }

            setState(() {
              _publicProfileLoading = false;
            });
          },
        );
  }

  Future<void> _cancelPublicProfileSubscription() async {
    final StreamSubscription<UserModel?>? previous =
        _publicProfileSubscription;

    _publicProfileSubscription = null;

    if (previous != null) {
      await previous.cancel();
    }
  }

  bool _isCurrentPublicUid(
      String uid,
      ) {
    return mounted &&
        widget.contact?.resolvedUid?.trim() == uid;
  }

  // =============================================================
  // AUTH GATE
  // =============================================================

  Future<void> _openAuthentication() async {
    if (_authenticated || !mounted) {
      return;
    }

    final String? choice =
    await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (
          BuildContext sheetContext,
          ) {
        return Container(
          margin: const EdgeInsets.all(
            12,
          ),
          padding: const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            22,
          ),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(
              26,
            ),
            border: Border.all(
              color: _border,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(
                  0x180F172A,
                ),
                blurRadius: 28,
                offset: Offset(
                  0,
                  10,
                ),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(
                  bottom: 18,
                ),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFD8E0EC,
                  ),
                  borderRadius: BorderRadius.circular(
                    99,
                  ),
                ),
              ),
              const Icon(
                Icons.account_circle_outlined,
                color: _primary,
                size: 48,
              ),
              const SizedBox(
                height: 12,
              ),
              const Text(
                'JR CALL Account Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _text,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(
                height: 8,
              ),
              const Text(
                'Login or create an account to manage your profile, '
                    'make calls, send messages and use private features.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _secondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(
                height: 20,
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(
                      sheetContext,
                    ).pop(
                      'login',
                    );
                  },
                  child: const Text(
                    'LOG IN',
                  ),
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(
                      sheetContext,
                    ).pop(
                      'create',
                    );
                  },
                  child: const Text(
                    'CREATE ACCOUNT',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (
            BuildContext context,
            ) {
          if (choice == 'create') {
            return const CreateAccountScreen();
          }

          return const LoginScreen();
        },
        settings: const RouteSettings(
          arguments: <String, dynamic>{
            'guestReturn': true,
            'requestedAction': 'profile',
          },
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    _restoreOwnProfileFromMemory();

    await _initialize(
      force: true,
    );
  }

  // =============================================================
  // GENERIC TEXT EDITOR
  // =============================================================

  Future<void> _editText({
    required String title,
    required String value,
    required Future<void> Function(String value) onSave,
    int maxLength = 100,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
  }) async {
    if (_busy || !mounted) {
      return;
    }

    final TextEditingController controller =
    TextEditingController(
      text: value,
    );

    try {
      final String? result =
      await showDialog<String>(
        context: context,
        builder: (
            BuildContext dialogContext,
            ) {
          return AlertDialog(
            title: Text(
              title,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: keyboardType,
              textCapitalization: capitalization,
              textInputAction: maxLines > 1
                  ? TextInputAction.newline
                  : TextInputAction.done,
              maxLength: maxLength,
              maxLines: maxLines,
              autocorrect: maxLines > 1,
              enableSuggestions: maxLines > 1,
              autofillHints: const <String>[],
              decoration: InputDecoration(
                labelText: title,
                filled: true,
                fillColor: const Color(
                  0xFFF8FAFC,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                ),
              ),
              onSubmitted: maxLines > 1
                  ? null
                  : (
                  String text,
                  ) {
                Navigator.of(
                  dialogContext,
                ).pop(
                  text.trim(),
                );
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop();
                },
                child: const Text(
                  'Cancel',
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(
                    controller.text.trim(),
                  );
                },
                child: const Text(
                  'Save',
                ),
              ),
            ],
          );
        },
      );

      if (result == null) {
        return;
      }

      await _performSave(
            () => onSave(
          result,
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  // =============================================================
  // FULL NAME
  // =============================================================

  Future<void> _updateName() async {
    final UserModel? user = _user;

    if (user == null) {
      return;
    }

    await _editText(
      title: 'Full Name',
      value: user.name,
      maxLength: 80,
      keyboardType: TextInputType.name,
      capitalization: TextCapitalization.words,
      onSave: (
          String value,
          ) async {
        final String normalized =
        value.trim();

        if (normalized.isEmpty) {
          await _profileService.clearProfileField(
            UserProfileField.name,
          );
          return;
        }

        await _profileService.updateFullName(
          normalized,
        );
      },
    );
  }

  // =============================================================
  // USERNAME
  // =============================================================

  Future<void> _updateUsername() async {
    final UserModel? user = _user;

    if (user == null) {
      return;
    }

    await _editText(
      title: 'Username',
      value: user.username ?? '',
      maxLength: 30,
      onSave: (
          String value,
          ) async {
        final String normalized =
        _normalizeUsername(
          value,
        );

        if (normalized.isEmpty) {
          await _profileService.clearUsername();
          return;
        }

        if (!_validUsername(
          normalized,
        )) {
          throw ArgumentError(
            'Username must contain 3-30 lowercase letters, '
                'numbers, dots or underscores.',
          );
        }

        await _profileService.updateUsername(
          normalized,
        );
      },
    );
  }

  // =============================================================
  // JR CALL USER ID
  // =============================================================

  Future<void> _updateUserAddress() async {
    final UserModel? user = _user;

    if (user == null) {
      return;
    }

    await _editText(
      title: 'JR CALL User ID',
      value: user.userAddress ?? '',
      maxLength: 64,
      onSave: (
          String value,
          ) async {
        final String normalized =
        _normalizePublicId(
          value,
        );

        if (!_validPublicId(
          normalized,
        )) {
          throw ArgumentError(
            'JR CALL User ID must contain 3-64 lowercase letters, '
                'numbers, dots, underscores or hyphens.',
          );
        }

        await _profileService.updateJrCallUserId(
          normalized,
        );
      },
    );
  }

  // =============================================================
  // BIO
  // =============================================================

  Future<void> _updateBio() async {
    final UserModel? user = _user;

    if (user == null) {
      return;
    }

    await _editText(
      title: 'Bio',
      value: user.bio ?? '',
      maxLength: 300,
      maxLines: 5,
      keyboardType: TextInputType.multiline,
      capitalization: TextCapitalization.sentences,
      onSave: (
          String value,
          ) async {
        final String normalized =
        value.trim();

        if (normalized.isEmpty) {
          await _profileService.clearBio();
          return;
        }

        await _profileService.updateBio(
          normalized,
        );
      },
    );
  }

  // =============================================================
  // COUNTRY
  // =============================================================

  Future<void> _updateCountry() async {
    if (_user == null ||
        _busy ||
        !mounted) {
      return;
    }

    showCountryPicker(
      context: context,
      showPhoneCode: true,
      useSafeArea: true,
      countryListTheme: CountryListThemeData(
        backgroundColor: _surface,
        bottomSheetHeight: 650,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(
            24,
          ),
        ),
        searchTextStyle: const TextStyle(
          color: _text,
        ),
        textStyle: const TextStyle(
          color: _text,
        ),
        inputDecoration: InputDecoration(
          labelText: 'Search Country',
          hintText: 'Country name or code',
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: _primary,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
              14,
            ),
          ),
        ),
      ),
      onSelect: (
          Country country,
          ) {
        unawaited(
          _performSave(
                () => _profileService.updateCountry(
              country: country.name.trim(),
              countryCode:
              country.countryCode.trim().toUpperCase(),
            ),
          ),
        );
      },
    );
  }

  // =============================================================
  // DATE OF BIRTH
  // =============================================================

  Future<void> _updateDateOfBirth() async {
    final UserModel? user = _user;

    if (user == null ||
        _busy ||
        !mounted) {
      return;
    }

    final DateTime now = DateTime.now();

    final DateTime fallback = DateTime(
      now.year - 18,
      now.month,
      now.day,
    );

    final DateTime current;

    if (user.dateOfBirth == null ||
        user.dateOfBirth!.isAfter(
          now,
        )) {
      current = fallback;
    } else {
      current = user.dateOfBirth!;
    }

    final DateTime? selected =
    await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(
        1900,
      ),
      lastDate: now,
    );

    if (selected == null) {
      return;
    }

    await _performSave(
          () => _profileService.updateDateOfBirth(
        DateTime(
          selected.year,
          selected.month,
          selected.day,
        ),
      ),
    );
  }

  // =============================================================
  // PROFILE PHOTO SOURCE
  // =============================================================

  Future<ImageSource?> _chooseProfileImageSource(
      UserModel user,
      ) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _surface,
      builder: (
          BuildContext sheetContext,
          ) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_supportsCamera)
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: _primary,
                ),
                title: const Text(
                  'Take Photo',
                ),
                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop(
                    ImageSource.camera,
                  );
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: _primary,
              ),
              title: const Text(
                'Choose from Gallery',
              ),
              onTap: () {
                Navigator.of(
                  sheetContext,
                ).pop(
                  ImageSource.gallery,
                );
              },
            ),
            if (user.hasProfilePhoto)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: _error,
                ),
                title: const Text(
                  'Remove Profile Photo',
                  style: TextStyle(
                    color: _error,
                  ),
                ),
                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop();

                  unawaited(
                    _removeProfilePhoto(),
                  );
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.close_rounded,
              ),
              title: const Text(
                'Cancel',
              ),
              onTap: () {
                Navigator.of(
                  sheetContext,
                ).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // =============================================================
  // PROFILE PHOTO
  // =============================================================

  Future<void> _changeProfilePhoto() async {
    final UserModel? user = _user;

    if (user == null || _busy) {
      return;
    }

    final ProfileMediaPicker? external =
        widget.onPickProfilePhoto;

    if (external != null) {
      await _performSave(
            () async {
          final String? url =
          await external();

          final String normalized =
              url?.trim() ?? '';

          if (normalized.isEmpty) {
            return;
          }

          await _profileService.updateProfile(
            profilePhotoUrl: normalized,
          );
        },
      );

      return;
    }

    final ImageSource? source =
    await _chooseProfileImageSource(
      user,
    );

    if (source == null || !mounted) {
      return;
    }

    await _pickAndUpload(
      user: user,
      source: source,
      profilePhoto: true,
    );
  }

  // =============================================================
  // COVER PHOTO
  // =============================================================

  Future<void> _changeCoverPhoto() async {
    final UserModel? user = _user;

    if (user == null || _busy) {
      return;
    }

    final ProfileMediaPicker? external =
        widget.onPickCoverPhoto;

    if (external != null) {
      await _performSave(
            () async {
          final String? url =
          await external();

          final String normalized =
              url?.trim() ?? '';

          if (normalized.isEmpty) {
            return;
          }

          await _profileService.updateProfile(
            coverPhotoUrl: normalized,
          );
        },
      );

      return;
    }

    await _pickAndUpload(
      user: user,
      source: ImageSource.gallery,
      profilePhoto: false,
    );
  }

  // =============================================================
  // PICK / CROP / UPLOAD
  // =============================================================

  Future<void> _pickAndUpload({
    required UserModel user,
    required ImageSource source,
    required bool profilePhoto,
  }) async {
    if (_busy) {
      return;
    }

    _setPicking(
      true,
    );

    try {
      _requireOwner(
        user.uid,
      );

      final bool permissionGranted =
      await AppPermissions.requestProfileMediaPermission(
        sourceCamera:
        source == ImageSource.camera,
      );

      if (!permissionGranted) {
        _showMessage(
          source == ImageSource.camera
              ? 'Camera permission is required.'
              : 'Photo access is required.',
        );

        return;
      }

      if (!mounted) {
        return;
      }

      final XFile? picked =
      await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: profilePhoto
            ? 2400
            : 3200,
        maxHeight: profilePhoto
            ? 2400
            : 2200,
        requestFullMetadata: false,
      );

      if (picked == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      final Uint8List? bytes =
      await _cropImage(
        picked: picked,
        title: profilePhoto
            ? 'Crop Profile Photo'
            : 'Crop Cover Photo',
        ratio: profilePhoto
            ? const CropAspectRatio(
          ratioX: 1,
          ratioY: 1,
        )
            : const CropAspectRatio(
          ratioX: 16,
          ratioY: 9,
        ),
        maxWidth: profilePhoto
            ? 1200
            : 1920,
        maxHeight: profilePhoto
            ? 1200
            : 1080,
      );

      if (bytes == null) {
        return;
      }

      _validateBytes(
        bytes,
        profilePhoto
            ? _profileMaxBytes
            : _coverMaxBytes,
        profilePhoto
            ? 'Profile photo'
            : 'Cover photo',
      );

      _requireOwner(
        user.uid,
      );

      if (profilePhoto) {
        await _profileService.uploadProfilePhoto(
          bytes: bytes,
          contentType: 'image/jpeg',
        );
      } else {
        await _profileService.uploadCoverPhoto(
          bytes: bytes,
          contentType: 'image/jpeg',
        );
      }

      if (_firebaseUser?.uid != user.uid) {
        return;
      }

      final UserModel? refreshed =
      await _profileService.getCurrentProfile();

      if (_firebaseUser?.uid != user.uid) {
        return;
      }

      if (refreshed != null &&
          !refreshed.isDeleted) {
        _cacheProfile(
          refreshed,
        );

        if (mounted) {
          setState(() {
            _boundUid = refreshed.uid;
            _user = refreshed;
            _loadError = null;
            _loading = false;
          });
        }
      }

      if (mounted) {
        _showMessage(
          profilePhoto
              ? 'Profile photo updated.'
              : 'Cover photo updated.',
        );
      }
    } on FirebaseException catch (error) {
      _showMessage(
        _firebaseError(
          error,
        ),
      );
    } on ArgumentError catch (error) {
      _showMessage(
        error.message?.toString() ??
            'Invalid selected image.',
      );
    } on StateError catch (error) {
      _showMessage(
        error.message,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Profile media update',
        error,
        stackTrace,
      );

      _showMessage(
        'Selected image could not be updated.',
      );
    } finally {
      _setPicking(
        false,
      );
    }
  }

  // =============================================================
  // IMAGE CROP
  // =============================================================

  Future<Uint8List?> _cropImage({
    required XFile picked,
    required String title,
    required CropAspectRatio ratio,
    required int maxWidth,
    required int maxHeight,
  }) async {
    if (!_supportsCropper) {
      return picked.readAsBytes();
    }

    if (!mounted) {
      return null;
    }

    final CroppedFile? cropped =
    await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: ratio,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: title,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: title,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(
            width: 560,
            height: 560,
          ),
        ),
      ],
    );

    if (cropped == null) {
      return null;
    }

    return cropped.readAsBytes();
  }

  void _validateBytes(
      Uint8List bytes,
      int maximum,
      String label,
      ) {
    if (bytes.isEmpty) {
      throw ArgumentError(
        '$label is empty.',
      );
    }

    if (bytes.lengthInBytes <= maximum) {
      return;
    }

    throw ArgumentError(
      '$label must be '
          '${maximum ~/ (1024 * 1024)} MB or smaller.',
    );
  }

  // =============================================================
  // REMOVE PROFILE PHOTO
  // =============================================================

  Future<void> _removeProfilePhoto() async {
    final UserModel? user = _user;

    if (user == null ||
        !user.hasProfilePhoto ||
        _busy) {
      return;
    }

    final bool confirmed =
    await _confirm(
      title: 'Remove Profile Photo?',
      message:
      'Your current profile photo will be removed.',
    );

    if (!confirmed) {
      return;
    }

    await _performSave(
      _profileService.deleteProfilePhoto,
    );
  }

  // =============================================================
  // REMOVE COVER PHOTO
  // =============================================================

  Future<void> _removeCoverPhoto() async {
    final UserModel? user = _user;

    if (user == null ||
        !user.hasCoverPhoto ||
        _busy) {
      return;
    }

    final bool confirmed =
    await _confirm(
      title: 'Remove Cover Photo?',
      message:
      'Your current cover photo will be removed.',
    );

    if (!confirmed) {
      return;
    }

    await _performSave(
      _profileService.deleteCoverPhoto,
    );
  }

  // =============================================================
  // CLEAR PROFILE FIELD
  // =============================================================

  Future<void> _clearField(
      UserProfileField field,
      String title,
      ) async {
    if (_user == null || _busy) {
      return;
    }

    final bool confirmed =
    await _confirm(
      title: 'Remove $title?',
      message:
      '$title will be removed from your profile.',
    );

    if (!confirmed) {
      return;
    }

    await _performSave(
          () async {
        switch (field) {
          case UserProfileField.username:
            await _profileService.clearUsername();
            return;

          case UserProfileField.userAddress:
            await _profileService.clearJrCallUserId();
            return;

          case UserProfileField.bio:
            await _profileService.clearBio();
            return;

          case UserProfileField.dateOfBirth:
            await _profileService.clearDateOfBirth();
            return;

          case UserProfileField.country:
          case UserProfileField.countryCode:
            await _profileService.clearCountry();
            return;

          default:
            await _profileService.clearProfileField(
              field,
            );
            return;
        }
      },
    );
  }

  // =============================================================
  // EMAIL INFO
  // =============================================================

  Future<void> _showEmailInfo() async {
    final User? firebaseUser = _firebaseUser;

    if (firebaseUser == null) {
      _showMessage(
        'No authenticated JR CALL user is available.',
      );
      return;
    }

    final String? email = _clean(
      firebaseUser.email,
    );

    final String message;

    if (email == null) {
      message =
      'No email is currently linked.\n\n'
          'Use Settings → Account & Security to add one.';
    } else {
      message =
      '${firebaseUser.emailVerified ? 'Verified' : 'Verification pending'}'
          '\n\n$email\n\n'
          'Use Settings → Account & Security for email actions.';
    }

    await _info(
      'Email',
      message,
    );
  }

  // =============================================================
  // PHONE INFO
  // =============================================================

  Future<void> _showPhoneInfo() async {
    final User? firebaseUser = _firebaseUser;

    if (firebaseUser == null) {
      _showMessage(
        'No authenticated JR CALL user is available.',
      );
      return;
    }

    final String? phone = _clean(
      firebaseUser.phoneNumber,
    );

    final String message;

    if (phone == null) {
      message =
      'No phone number is currently linked.\n\n'
          'Use Settings → Account & Security to add one.';
    } else {
      message =
      'Firebase verified\n\n'
          '$phone\n\n'
          'Use Settings → Account & Security for phone actions.';
    }

    await _info(
      'Phone Number',
      message,
    );
  }

  // =============================================================
  // VERIFICATION INFO
  // =============================================================

  Future<void> _showVerificationInfo() async {
    final User? firebaseUser = _firebaseUser;

    if (firebaseUser == null) {
      _showMessage(
        'No authenticated JR CALL user is available.',
      );
      return;
    }

    final List<String> lines =
    <String>[];

    final String? email = _clean(
      firebaseUser.email,
    );

    final String? phone = _clean(
      firebaseUser.phoneNumber,
    );

    if (email != null) {
      lines.add(
        'Email: '
            '${firebaseUser.emailVerified ? 'Verified' : 'Pending'}',
      );
    }

    if (phone != null) {
      lines.add(
        'Phone: Verified',
      );
    }

    if (lines.isEmpty) {
      lines.add(
        'No email or phone verification information is available.',
      );
    }

    await _info(
      'Verification',
      '${lines.join('\n')}\n\n'
          'Security actions are available in '
          'Settings → Account & Security.',
    );
  }

  // =============================================================
  // PROVIDER INFO
  // =============================================================

  Future<void> _showProviderInfo() async {
    final User? firebaseUser = _firebaseUser;

    if (firebaseUser == null) {
      _showMessage(
        'No authenticated JR CALL user is available.',
      );
      return;
    }

    final Set<String> providers =
    firebaseUser.providerData
        .map(
          (
          UserInfo provider,
          ) =>
          provider.providerId.trim(),
    )
        .where(
          (
          String providerId,
          ) =>
      providerId.isNotEmpty,
    )
        .map(
      _providerLabel,
    )
        .toSet();

    await _info(
      'Sign-in Providers',
      providers.isEmpty
          ? 'No provider information is available.'
          : providers.join(
        '\n',
      ),
    );
  }

  // =============================================================
  // INFO DIALOG
  // =============================================================

  Future<void> _info(
      String title,
      String message,
      ) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (
          BuildContext dialogContext,
          ) {
        return AlertDialog(
          title: Text(
            title,
          ),
          content: Text(
            message,
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: const Text(
                'Done',
              ),
            ),
          ],
        );
      },
    );
  }

  // =============================================================
  // SAVE WRAPPER
  // =============================================================

  Future<void> _performSave(
      Future<void> Function() action,
      ) async {
    if (_busy || !mounted) {
      return;
    }

    final UserModel? current = _user;
    final String? ownerUid = current?.uid.trim();

    if (current != null) {
      _requireOwner(
        current.uid,
      );
    }

    setState(() {
      _saving = true;
    });

    try {
      await action();

      if (ownerUid != null &&
          ownerUid.isNotEmpty &&
          _firebaseUser?.uid != ownerUid) {
        return;
      }

      final UserModel? refreshed =
      await _profileService.getCurrentProfile();

      if (ownerUid != null &&
          ownerUid.isNotEmpty &&
          _firebaseUser?.uid != ownerUid) {
        return;
      }

      if (refreshed != null &&
          !refreshed.isDeleted) {
        _cacheProfile(
          refreshed,
        );

        if (mounted) {
          setState(() {
            _boundUid = refreshed.uid;
            _user = refreshed;
            _loadError = null;
            _loading = false;
          });
        }
      }

      if (mounted) {
        _showMessage(
          'Profile updated successfully.',
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        _showMessage(
          _firebaseError(
            error,
          ),
        );
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        _showMessage(
          error.message?.toString() ??
              'Invalid profile information.',
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        _showMessage(
          error.message,
        );
      }
    } catch (error, stackTrace) {
      _reportError(
        'Profile update',
        error,
        stackTrace,
      );

      if (mounted) {
        _showMessage(
          'Unable to update profile.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // =============================================================
  // OWNERSHIP
  // =============================================================

  void _requireOwner(
      String uid,
      ) {
    final User? current = _firebaseUser;

    if (current == null) {
      throw StateError(
        'Your authenticated session is no longer available.',
      );
    }

    if (current.uid != uid) {
      throw StateError(
        'Authenticated Firebase user does not own this profile.',
      );
    }
  }

  // =============================================================
  // PLATFORM SUPPORT
  // =============================================================

  bool get _supportsCropper {
    return kIsWeb ||
        defaultTargetPlatform ==
            TargetPlatform.android ||
        defaultTargetPlatform ==
            TargetPlatform.iOS;
  }

  bool get _supportsCamera {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform ==
        TargetPlatform.android ||
        defaultTargetPlatform ==
            TargetPlatform.iOS;
  }

  // =============================================================
  // CONTACT ACTION
  // =============================================================

  void _contactAction(
      VoidCallback? action,
      String unavailable,
      ) {
    if (action != null) {
      action();
      return;
    }

    _showMessage(
      unavailable,
    );
  }

  // =============================================================
  // ROOT BUILD
  // =============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    if (widget.isContactProfile) {
      return _buildContactProfile();
    }

    if (!_authenticated) {
      return _buildGuestProfile();
    }

    return _buildCurrentProfile();
  }

  // =============================================================
  // CURRENT PROFILE
  // =============================================================

  Widget _buildCurrentProfile() {
    final UserModel? user = _user;

    if (user != null) {
      return ProfileStudioScreen(
        user: user,
        busy: _busy,
        onRefresh: () => _initialize(
          force: true,
        ),
        onEditName: () {
          unawaited(
            _updateName(),
          );
        },
        onEditUsername: () {
          unawaited(
            _updateUsername(),
          );
        },
        onEditJrCallId: () {
          unawaited(
            _updateUserAddress(),
          );
        },
        onEditBio: () {
          unawaited(
            _updateBio(),
          );
        },
        onEditDateOfBirth: () {
          unawaited(
            _updateDateOfBirth(),
          );
        },
        onEditCountry: () {
          unawaited(
            _updateCountry(),
          );
        },
        onChangeProfilePhoto: () {
          unawaited(
            _changeProfilePhoto(),
          );
        },
        onRemoveProfilePhoto: () {
          unawaited(
            _removeProfilePhoto(),
          );
        },
        onChangeCoverPhoto: () {
          unawaited(
            _changeCoverPhoto(),
          );
        },
        onRemoveCoverPhoto: () {
          unawaited(
            _removeCoverPhoto(),
          );
        },
        onRemoveName: () {
          unawaited(
            _clearField(
              UserProfileField.name,
              'Full Name',
            ),
          );
        },
        onRemoveUsername: () {
          unawaited(
            _clearField(
              UserProfileField.username,
              'Username',
            ),
          );
        },
        onRemoveBio: () {
          unawaited(
            _clearField(
              UserProfileField.bio,
              'Bio',
            ),
          );
        },
        onRemoveDateOfBirth: () {
          unawaited(
            _clearField(
              UserProfileField.dateOfBirth,
              'Date of Birth',
            ),
          );
        },
        onRemoveCountry: () {
          unawaited(
            _clearField(
              UserProfileField.country,
              'Country',
            ),
          );
        },
        onEmailTap: () {
          unawaited(
            _showEmailInfo(),
          );
        },
        onPhoneTap: () {
          unawaited(
            _showPhoneInfo(),
          );
        },
        onVerificationTap: () {
          unawaited(
            _showVerificationInfo(),
          );
        },
        onProviderTap: () {
          unawaited(
            _showProviderInfo(),
          );
        },
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: _background,
        appBar: _simpleAppBar(
          'Profile Studio',
        ),
        body: _buildLoadError(),
      );
    }

    if (_loading) {
      return Scaffold(
        backgroundColor: _background,
        appBar: _simpleAppBar(
          'Profile Studio',
        ),
        body: const Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.7,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _background,
      appBar: _simpleAppBar(
        'Profile Studio',
      ),
      body: const Center(
        child: Text(
          'Profile unavailable',
          style: TextStyle(
            color: _secondary,
          ),
        ),
      ),
    );
  }

  // =============================================================
  // GUEST PROFILE
  // =============================================================

  Widget _buildGuestProfile() {
    return Scaffold(
      backgroundColor: _background,
      appBar: _simpleAppBar(
        'My Profile',
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(
              24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 480,
              ),
              child: _glassCard(
                padding: const EdgeInsets.all(
                  28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 94,
                      height: 94,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _primary.withValues(
                          alpha: 0.08,
                        ),
                      ),
                      child: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: _primary,
                        size: 48,
                      ),
                    ),
                    const SizedBox(
                      height: 22,
                    ),
                    const Text(
                      'Create your JR CALL identity',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    const Text(
                      'You can explore JR CALL as a guest. '
                          'An account is required for your own profile, '
                          'calls, messages, uploads and private features.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _secondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(
                      height: 26,
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _openAuthentication,
                        child: const Text(
                          'LOGIN / CREATE ACCOUNT',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // CONTACT / PUBLIC PROFILE
  // =============================================================

  Widget _buildContactProfile() {
    final ContactModel contact =
    widget.contact!;

    final UserModel? publicUser =
        _publicUser;

    final String displayName =
    _publicDisplayName(
      contact,
      publicUser,
    );

    final String? photoUrl =
        _clean(
          publicUser?.photoUrl,
        ) ??
            _clean(
              contact.photoUrl,
            );

    final String? coverUrl = _clean(
      publicUser?.coverPhoto,
    );

    final String? username =
        _clean(
          publicUser?.username,
        ) ??
            _clean(
              contact.username,
            );

    final String? jrCallId =
        _clean(
          publicUser?.userAddress,
        ) ??
            _clean(
              contact.jrCallUserId,
            );

    final String? bio =
        _clean(
          publicUser?.bio,
        ) ??
            _clean(
              contact.bio,
            );

    final String? country =
        _clean(
          publicUser?.country,
        ) ??
            _clean(
              contact.country,
            );

    final bool online =
        publicUser?.online ??
            contact.isOnline;

    final bool verified =
        publicUser?.verified ??
            contact.isVerified;

    return Scaffold(
      backgroundColor: _background,
      appBar: _simpleAppBar(
        'Profile',
      ),
      body: RefreshIndicator(
        onRefresh: () => _initializePublicProfile(
          force: true,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _maxContentWidth,
            ),
            child: ListView(
              physics:
              const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                bottom: 36,
              ),
              children: <Widget>[
                _buildPublicHero(
                  name: displayName,
                  photoUrl: photoUrl,
                  coverUrl: coverUrl,
                  username: username,
                  jrCallId: jrCallId,
                  bio: bio,
                  online: online,
                  verified: verified,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    18,
                    16,
                    0,
                  ),
                  child: Column(
                    children: <Widget>[
                      _buildPublicActions(),
                      const SizedBox(
                        height: 16,
                      ),
                      _buildPublicAbout(
                        contact: contact,
                        publicUser: publicUser,
                        country: country,
                      ),
                      if (_publicProfileLoading)
                        ...<Widget>[
                          const SizedBox(
                            height: 14,
                          ),
                          const LinearProgressIndicator(
                            minHeight: 2,
                          ),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // PUBLIC PROFILE HERO
  // =============================================================

  Widget _buildPublicHero({
    required String name,
    required String? photoUrl,
    required String? coverUrl,
    required String? username,
    required String? jrCallId,
    required String? bio,
    required bool online,
    required bool verified,
  }) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 230,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                bottom: 58,
                child: _publicCoverSurface(
                  coverUrl,
                ),
              ),
              Positioned(
                left: 20,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(
                    4,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(
                          0x220F172A,
                        ),
                        blurRadius: 18,
                        offset: Offset(
                          0,
                          7,
                        ),
                      ),
                    ],
                  ),
                  child: CallerAvatar(
                    name: name,
                    imageUrl: photoUrl,
                    radius: 58,
                    isOnline: online,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            20,
            7,
            20,
            0,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 25,
                        height: 1.1,
                        fontWeight:
                        FontWeight.w900,
                      ),
                    ),
                  ),
                  if (verified)
                    ...<Widget>[
                      const SizedBox(
                        width: 6,
                      ),
                      const Icon(
                        Icons.verified_rounded,
                        color: _primary,
                        size: 20,
                      ),
                    ],
                ],
              ),
              if (username != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: 5,
                  ),
                  child: Text(
                    '@${_normalizeUsername(username)}',
                    style: const TextStyle(
                      color: _primary,
                      fontSize: 15,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ),
              if (jrCallId != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: 4,
                  ),
                  child: Text(
                    'JR ID: ${jrCallId.trim()}',
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _secondary,
                      fontSize: 13,
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),
                ),
              if (bio != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: 10,
                  ),
                  child: Text(
                    bio.trim(),
                    style: const TextStyle(
                      color: _secondary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // =============================================================
  // PUBLIC COVER
  // =============================================================

  Widget _publicCoverSurface(
      String? coverUrl,
      ) {
    return ClipRRect(
      borderRadius:
      const BorderRadius.vertical(
        bottom: Radius.circular(
          28,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: coverUrl == null
              ? const LinearGradient(
            begin:
            Alignment.topLeft,
            end:
            Alignment.bottomRight,
            colors: <Color>[
              Color(
                0xFFDCEAFF,
              ),
              Color(
                0xFFECE7FF,
              ),
              Color(
                0xFFE7FBFF,
              ),
            ],
          )
              : null,
          image: coverUrl == null
              ? null
              : DecorationImage(
            image:
            NetworkImage(
              coverUrl,
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: coverUrl == null
            ? const Center(
          child: Icon(
            Icons.landscape_rounded,
            size: 58,
            color: Color(
              0x663B82F6,
            ),
          ),
        )
            : const DecoratedBox(
          decoration: BoxDecoration(
            gradient:
            LinearGradient(
              begin:
              Alignment.topCenter,
              end:
              Alignment.bottomCenter,
              colors: <Color>[
                Color(
                  0x05000000,
                ),
                Color(
                  0x44000000,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // PUBLIC ACTIONS
  // =============================================================

  Widget _buildPublicActions() {
    return _glassCard(
      padding: const EdgeInsets.all(
        14,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _PublicActionButton(
              icon: Icons.call_rounded,
              label: 'Voice',
              color: _success,
              onTap: () => _contactAction(
                widget.onVoiceCall,
                'Voice call action is not available.',
              ),
            ),
          ),
          const SizedBox(
            width: 9,
          ),
          Expanded(
            child: _PublicActionButton(
              icon:
              Icons.videocam_rounded,
              label: 'Video',
              color: _primary,
              onTap: () => _contactAction(
                widget.onVideoCall,
                'Video call action is not available.',
              ),
            ),
          ),
          const SizedBox(
            width: 9,
          ),
          Expanded(
            child: _PublicActionButton(
              icon:
              Icons.message_rounded,
              label: 'Message',
              color: _violet,
              onTap: () => _contactAction(
                widget.onMessage,
                'Message action is not available.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // PUBLIC ABOUT
  // =============================================================

  Widget _buildPublicAbout({
    required ContactModel contact,
    required UserModel? publicUser,
    required String? country,
  }) {
    final List<Widget> rows =
    <Widget>[];

    final String? username =
        _clean(
          publicUser?.username,
        ) ??
            _clean(
              contact.username,
            );

    final String? jrCallId =
        _clean(
          publicUser?.userAddress,
        ) ??
            _clean(
              contact.jrCallUserId,
            );

    final String? bio =
        _clean(
          publicUser?.bio,
        ) ??
            _clean(
              contact.bio,
            );

    final String? email = _clean(
      contact.email,
    );

    final String? phone = _clean(
      contact.phoneNumber,
    );

    void addRow(
        IconData icon,
        String title,
        String value,
        ) {
      rows.add(
        _readOnlyRow(
          icon: icon,
          title: title,
          value: value,
        ),
      );
    }

    if (username != null) {
      addRow(
        Icons.alternate_email_rounded,
        'Username',
        '@${_normalizeUsername(username)}',
      );
    }

    if (jrCallId != null) {
      addRow(
        Icons.badge_outlined,
        'JR CALL User ID',
        jrCallId,
      );
    }

    if (bio != null) {
      addRow(
        Icons.notes_rounded,
        'Bio',
        bio,
      );
    }

    if (country != null) {
      addRow(
        Icons.public_rounded,
        'Country',
        country,
      );
    }

    if (email != null) {
      addRow(
        Icons.email_outlined,
        'Email',
        email,
      );
    }

    if (phone != null) {
      addRow(
        Icons.phone_outlined,
        'Phone',
        phone,
      );
    }

    if (rows.isEmpty) {
      rows.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(
            6,
            8,
            6,
            14,
          ),
          child: Text(
            'No additional public profile information is available.',
            style: TextStyle(
              color: _secondary,
              height: 1.45,
            ),
          ),
        ),
      );
    }

    return _glassCard(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        8,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionHeader(
            'Public Information',
            Icons.person_search_outlined,
            _primary,
          ),
          ...rows,
          if (widget.onBlockContact != null ||
              widget.onDeleteContact != null)
            ...<Widget>[
              const Divider(
                height: 24,
              ),
              if (widget.onBlockContact !=
                  null)
                _actionRow(
                  icon:
                  Icons.block_rounded,
                  title: 'Block Contact',
                  color: _error,
                  onTap:
                  widget.onBlockContact!,
                ),
              if (widget.onDeleteContact !=
                  null)
                _actionRow(
                  icon:
                  Icons.delete_outline,
                  title: 'Delete Contact',
                  color: _error,
                  onTap:
                  widget.onDeleteContact!,
                ),
            ],
        ],
      ),
    );
  }

  // =============================================================
  // COMMON UI
  // =============================================================

  PreferredSizeWidget _simpleAppBar(
      String title,
      ) {
    return AppBar(
      backgroundColor: _background,
      foregroundColor: _text,
      surfaceTintColor:
      Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding =
    const EdgeInsets.all(
      16,
    ),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _surface.withValues(
          alpha: 0.96,
        ),
        borderRadius:
        BorderRadius.circular(
          22,
        ),
        border: Border.all(
          color: _border,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(
              0x0F0F172A,
            ),
            blurRadius: 24,
            offset: Offset(
              0,
              9,
            ),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(
      String title,
      IconData icon,
      Color color,
      ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        children: <Widget>[
          _iconBubble(
            icon,
            color,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _text,
                fontSize: 15,
                fontWeight:
                FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 2,
      ),
      leading: _iconBubble(
        icon,
        _primary,
      ),
      title: _tileTitle(
        title,
      ),
      subtitle: _tileValue(
        value,
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 1,
      ),
      leading: _iconBubble(
        icon,
        color,
      ),
      title: _tileTitle(
        title,
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(
          0xFF94A3B8,
        ),
      ),
      onTap: _busy ? null : onTap,
    );
  }

  Widget _tileTitle(
      String title,
      ) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _text,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _tileValue(
      String value,
      ) {
    return Text(
      value,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _secondary,
        height: 1.35,
      ),
    );
  }

  Widget _iconBubble(
      IconData icon,
      Color color,
      ) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(
          alpha: 0.09,
        ),
      ),
      child: Icon(
        icon,
        color: color,
        size: 21,
      ),
    );
  }

  // =============================================================
  // LOAD ERROR
  // =============================================================

  Widget _buildLoadError() {
    final Object? error = _loadError;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 54,
              color: _error,
            ),
            const SizedBox(
              height: 16,
            ),
            const Text(
              'Unable to load profile',
              style: TextStyle(
                color: _text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              error == null
                  ? 'JR CALL could not load your profile.'
                  : _friendlyError(
                error,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _secondary,
                height: 1.4,
              ),
            ),
            const SizedBox(
              height: 20,
            ),
            FilledButton.icon(
              onPressed: () {
                unawaited(
                  _initialize(
                    force: true,
                  ),
                );
              },
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text(
                'Retry',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // HELPERS
  // =============================================================

  void _setPicking(
      bool value,
      ) {
    if (!mounted ||
        _pickingMedia == value) {
      return;
    }

    setState(() {
      _pickingMedia = value;
    });
  }

  String? _clean(
      String? value,
      ) {
    final String normalized =
        value?.trim() ?? '';

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  String _normalizeUsername(
      String value,
      ) {
    String normalized =
    value.trim().toLowerCase();

    if (normalized.startsWith(
      '@',
    )) {
      normalized = normalized.substring(
        1,
      );
    }

    return normalized.trim();
  }

  String _normalizePublicId(
      String value,
      ) {
    String normalized =
    value.trim().toLowerCase();

    if (normalized.startsWith(
      '@',
    )) {
      normalized = normalized.substring(
        1,
      );
    }

    return normalized.trim();
  }

  bool _validUsername(
      String value,
      ) {
    return RegExp(
      r'^[a-z0-9._]{3,30}$',
    ).hasMatch(
      value,
    ) &&
        !value.startsWith(
          '.',
        ) &&
        !value.endsWith(
          '.',
        ) &&
        !value.contains(
          '..',
        );
  }

  bool _validPublicId(
      String value,
      ) {
    return RegExp(
      r'^[a-z0-9._-]{3,64}$',
    ).hasMatch(
      value,
    ) &&
        !value.startsWith(
          '.',
        ) &&
        !value.endsWith(
          '.',
        ) &&
        !value.contains(
          '..',
        );
  }

  String _publicDisplayName(
      ContactModel contact,
      UserModel? publicUser,
      ) {
    return _clean(
      publicUser?.name,
    ) ??
        _clean(
          contact.displayName,
        ) ??
        'JR CALL User';
  }

  String _providerLabel(
      String providerId,
      ) {
    final String normalized =
    providerId.trim();

    switch (normalized) {
      case 'password':
        return 'Email / Password';

      case 'phone':
        return 'Phone';

      case 'google.com':
        return 'Google';

      case 'apple.com':
        return 'Apple';

      case 'facebook.com':
        return 'Facebook';

      default:
        return normalized;
    }
  }

  String _friendlyError(
      Object error,
      ) {
    if (error is FirebaseException) {
      return _firebaseError(
        error,
      );
    }

    if (error is StateError) {
      return error.message;
    }

    if (error is ArgumentError) {
      return error.message?.toString() ??
          'Invalid profile information.';
    }

    return 'JR CALL could not load your profile. '
        'Please try again.';
  }

  String _firebaseError(
      FirebaseException error,
      ) {
    switch (error.code) {
      case 'unauthorized':
      case 'permission-denied':
      case 'storage/unauthorized':
        return 'Permission denied while accessing this account.';

      case 'canceled':
      case 'storage/canceled':
        return 'Upload was cancelled.';

      case 'retry-limit-exceeded':
      case 'storage/retry-limit-exceeded':
        return 'Upload failed because of network problems.';

      case 'quota-exceeded':
      case 'storage/quota-exceeded':
        return 'Firebase Storage quota has been exceeded.';

      case 'object-not-found':
      case 'storage/object-not-found':
        return 'The requested Storage object was not found.';

      case 'network-request-failed':
      case 'unavailable':
        return 'Firebase service is temporarily unavailable.';

      default:
        return error.message ??
            'Firebase operation failed.';
    }
  }

  // =============================================================
  // CONFIRM
  // =============================================================

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return false;
    }

    final bool? result =
    await showDialog<bool>(
      context: context,
      builder: (
          BuildContext dialogContext,
          ) {
        return AlertDialog(
          title: Text(
            title,
          ),
          content: Text(
            message,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _error,
              ),
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  true,
                );
              },
              child: const Text(
                'Remove',
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  // =============================================================
  // MESSAGE
  // =============================================================

  void _showMessage(
      String message,
      ) {
    final String normalized =
    message.trim();

    if (!mounted ||
        normalized.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    )
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            normalized,
          ),
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }

  // =============================================================
  // ERROR REPORT
  // =============================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [ProfileScreen/$source] error: $error',
    );

    if (stackTrace == null) {
      return;
    }

    debugPrintStack(
      label:
      'JR CALL [ProfileScreen/$source]',
      stackTrace: stackTrace,
    );
  }
}

// ===============================================================
// PUBLIC ACTION BUTTON
// ===============================================================

class _PublicActionButton extends StatelessWidget {
  const _PublicActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(
          17,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(
            17,
          ),
          onTap: onTap,
          child: Container(
            constraints:
            const BoxConstraints(
              minHeight: 70,
            ),
            padding:
            const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              borderRadius:
              BorderRadius.circular(
                17,
              ),
              color: color.withValues(
                alpha: 0.08,
              ),
              border: Border.all(
                color: color.withValues(
                  alpha: 0.16,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
                const SizedBox(
                  height: 6,
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// END OF FILE
//
// FINAL PRODUCTION GUARANTEES:
//
// ✓ Single profile_screen.dart only.
// ✓ profile_screen_part2.dart is NOT referenced.
// ✓ ProfileService project path:
//   lib/services/profile_service.dart
//
// ✓ Invalid Dart catch syntax removed.
// ✓ All catch(error, stackTrace) syntax valid.
// ✓ All typed catch(error) syntax valid.
// ✓ No trailing comma inside catch parameters.
// ✓ Captured stack traces are actually used.
// ✓ Unnecessary dart:typed_data import removed.
// ✓ No unnecessary firebase_core import.
//
// ✓ Fast in-memory own-profile restore.
// ✓ Fast existing-profile read.
// ✓ Background ensure/sync.
// ✓ Realtime own-profile updates.
// ✓ Realtime public-profile updates.
// ✓ Auth changes refresh public/own profile safely.
// ✓ Same-user listener reuse.
// ✓ Duplicate initialization protection.
// ✓ Existing screen never blanked during background refresh.
//
// ✓ Own Profile.
// ✓ Guest Profile.
// ✓ Public/Contact Profile.
// ✓ Full Name.
// ✓ Username.
// ✓ JR CALL User ID.
// ✓ Bio.
// ✓ Country.
// ✓ Date of Birth.
// ✓ Profile photo.
// ✓ Cover photo.
// ✓ Remove Profile photo.
// ✓ Remove Cover photo.
// ✓ Remove Profile fields.
// ✓ Email information.
// ✓ Phone information.
// ✓ Verification information.
// ✓ Provider information.
// ✓ Profile Studio callbacks.
//
// ✓ Voice action callback.
// ✓ Video action callback.
// ✓ Message action callback.
// ✓ Block callback.
// ✓ Delete-contact callback.
//
// ✓ Firebase UID canonical.
// ✓ No OTP persistence.
// ✓ No Password persistence.
// ✓ Phone OTP ownership unchanged.
// ✓ Email/Password ownership unchanged.
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
//
// SAVE THIS FILE:
//
// lib/screens/profile_screen.dart
//
// DO NOT CREATE:
//
// lib/screens/profile_screen_part2.dart
// ===============================================================