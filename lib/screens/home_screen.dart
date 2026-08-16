// ===============================================================
// JR CALL
// File: home_screen.dart
// Location: lib/screens/home_screen.dart
//
// Fixes:
// - BUG 06, BUG 10 preserved
// - Guest/Auth navigation preserved
// - REAL incoming-call receiver listener added
// - Receiver UID listens only to its own calls
// - Incoming CALLING -> RINGING handoff added
// - IncomingCallScreen opens once per call
// - Accept -> CallService.acceptCall()
// - Reject -> CallService.rejectCall()
// - Firebase UID remains canonical call identity
// - No duplicate WebRTC / ICE / signaling ownership
// - Existing UI/design preserved
// ===============================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/call_history_model.dart';
import '../models/user_model.dart';
import '../providers/call_history_provider.dart';
import '../services/call/call_service.dart';
import '../services/call/signaling_service.dart';
import '../services/firebase/firestore_service.dart';
import 'call_history_screen.dart';
import 'contacts_screen.dart';
import 'create_account_screen.dart';
import 'incoming_call_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // =============================================================
  // DESIGN TOKENS
  // =============================================================

  static const Color _background = Color(0xFFF8FAFE);
  static const Color _text = Color(0xFF101828);
  static const Color _muted = Color(0xFF66758C);
  static const Color _border = Color(0xFFE6ECF5);

  static const Color _blue = Color(0xFF087AF5);
  static const Color _call = Color(0xFF00C98D);
  static const Color _message = Color(0xFFB63CFA);
  static const Color _media = Color(0xFFFF7418);
  static const Color _reels = Color(0xFF008BFF);
  static const Color _tools = Color(0xFF9747FF);

  // =============================================================
  // DESTINATIONS
  // =============================================================

  static const int _callIndex = 0;
  static const int _messageIndex = 1;
  static const int _publicMediaIndex = 2;
  static const int _aiToolsIndex = 4;

  // =============================================================
  // INCOMING CALL
  // =============================================================

  static const Duration _maximumIncomingCallAge = Duration(minutes: 2);

  // =============================================================
  // SERVICES / STATE
  // =============================================================

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirestoreService _firestore = FirestoreService.instance;

  final SignalingService _signalingService = SignalingService.instance;

  final CallService _callService = CallService();

  final CallHistoryProvider _historyProvider = CallHistoryProvider();

  StreamSubscription<User?>? _authSubscription;

  StreamSubscription<UserModel?>? _profileSubscription;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _incomingCallSubscription;

  UserModel? _profile;

  late int _selectedIndex;

  int _profileLoadGeneration = 0;

  int _incomingListenerGeneration = 0;

  String? _presentedIncomingCallId;

  bool _openingIncomingCall = false;

  bool get _signedIn => _auth.currentUser != null;

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _selectedIndex = _resolveStartupIndex(widget.initialIndex);

    _authSubscription = _auth.userChanges().listen(
      _handleAuthChanged,
      onError: (Object error, StackTrace stackTrace) {
        _reportError('auth-stream', error, stackTrace);
      },
    );

    _restartIncomingCallListener(_auth.currentUser);

    unawaited(_loadProfile());
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialIndex == widget.initialIndex) {
      return;
    }

    final int nextIndex = _resolveRequestedIndex(widget.initialIndex);

    if (nextIndex == _selectedIndex) {
      return;
    }

    setState(() {
      _selectedIndex = nextIndex;
    });
  }

  @override
  void dispose() {
    _profileLoadGeneration++;

    _incomingListenerGeneration++;

    unawaited(_authSubscription?.cancel());

    unawaited(_profileSubscription?.cancel());

    unawaited(_incomingCallSubscription?.cancel());

    _historyProvider.dispose();

    super.dispose();
  }

  // =============================================================
  // INDEX / ACCESS
  // =============================================================

  int _normalizeIndex(int value) {
    if (value < _callIndex) {
      return _callIndex;
    }

    if (value > _aiToolsIndex) {
      return _aiToolsIndex;
    }

    return value;
  }

  bool _isProtectedDestination(int index) {
    return index == _callIndex ||
        index == _messageIndex ||
        index == _aiToolsIndex;
  }

  int _resolveStartupIndex(int requestedIndex) {
    final int normalized = _normalizeIndex(requestedIndex);

    if (!_signedIn && _isProtectedDestination(normalized)) {
      return _publicMediaIndex;
    }

    return normalized;
  }

  int _resolveRequestedIndex(int requestedIndex) {
    final int normalized = _normalizeIndex(requestedIndex);

    if (!_signedIn && _isProtectedDestination(normalized)) {
      return _publicMediaIndex;
    }

    return normalized;
  }

  // =============================================================
  // AUTH STATE
  // =============================================================

  void _handleAuthChanged(User? user) {
    if (!mounted) {
      return;
    }

    _restartIncomingCallListener(user);

    if (user == null && _isProtectedDestination(_selectedIndex)) {
      setState(() {
        _selectedIndex = _publicMediaIndex;
        _profile = null;
      });
    }

    unawaited(_loadProfile());
  }

  // =============================================================
  // REAL INCOMING CALL LISTENER
  // =============================================================

  void _restartIncomingCallListener(User? user) {
    final int generation = ++_incomingListenerGeneration;

    final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    previousSubscription = _incomingCallSubscription;

    _incomingCallSubscription = null;

    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }

    _presentedIncomingCallId = null;

    _openingIncomingCall = false;

    final String receiverUid = user?.uid.trim() ?? '';

    if (receiverUid.isEmpty) {
      return;
    }

    // IMPORTANT:
    // Query only calls where THIS authenticated Firebase UID
    // is the receiver.
    //
    // No whole calls collection download.
    // No caller-side private-call lookup.
    // No duplicate listener.
    _incomingCallSubscription = _signalingService.callsCollection
        .where('receiverId', isEqualTo: receiverUid)
        .snapshots()
        .listen(
          (QuerySnapshot<Map<String, dynamic>> snapshot) {
        _handleIncomingCallSnapshot(
          snapshot: snapshot,
          receiverUid: receiverUid,
          generation: generation,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _incomingListenerGeneration) {
          return;
        }

        _reportError('incoming-call-stream', error, stackTrace);
      },
    );
  }

  void _handleIncomingCallSnapshot({
    required QuerySnapshot<Map<String, dynamic>> snapshot,
    required String receiverUid,
    required int generation,
  }) {
    if (!mounted ||
        generation != _incomingListenerGeneration ||
        _auth.currentUser?.uid != receiverUid ||
        _openingIncomingCall) {
      return;
    }

    if (_callService.isCallActive) {
      return;
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? selectedDocument;

    DateTime? selectedCreatedAt;

    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
    in snapshot.docs) {
      final Map<String, dynamic> data = document.data();

      final String? storedReceiverUid = _readString(data['receiverId']);

      if (storedReceiverUid != receiverUid) {
        continue;
      }

      final String status =
          _readString(data['status'])?.toLowerCase() ?? '';

      if (!_isIncomingAlertStatus(status)) {
        continue;
      }

      final String? callerUid = _readString(data['callerId']);

      if (callerUid == null || callerUid == receiverUid) {
        continue;
      }

      final DateTime? createdAt = _timestampToDate(data['createdAt']);

      if (createdAt != null &&
          DateTime.now().difference(createdAt) > _maximumIncomingCallAge) {
        continue;
      }

      if (selectedDocument == null) {
        selectedDocument = document;
        selectedCreatedAt = createdAt;
        continue;
      }

      if (createdAt != null &&
          (selectedCreatedAt == null || createdAt.isAfter(selectedCreatedAt))) {
        selectedDocument = document;
        selectedCreatedAt = createdAt;
      }
    }

    if (selectedDocument == null) {
      return;
    }

    final String callId = selectedDocument.id.trim();

    if (callId.isEmpty || callId == _presentedIncomingCallId) {
      return;
    }

    unawaited(
      _presentIncomingCall(
        callId: callId,
        callData: selectedDocument.data(),
        receiverUid: receiverUid,
        generation: generation,
      ),
    );
  }

  bool _isIncomingAlertStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'calling':
      case 'ringing':
        return true;

      default:
        return false;
    }
  }

  Future<void> _presentIncomingCall({
    required String callId,
    required Map<String, dynamic> callData,
    required String receiverUid,
    required int generation,
  }) async {
    if (!mounted ||
        _openingIncomingCall ||
        generation != _incomingListenerGeneration ||
        _auth.currentUser?.uid != receiverUid) {
      return;
    }

    final String? callerUid = _readString(callData['callerId']);

    if (callerUid == null || callerUid == receiverUid) {
      return;
    }

    if (_callService.isCallActive) {
      return;
    }

    _openingIncomingCall = true;

    _presentedIncomingCallId = callId;

    String callerName =
        _readString(callData['callerName']) ?? 'JR CALL User';

    String? callerPhotoUrl;

    String? callerPublicId;

    try {
      final UserModel? callerProfile = await _firestore.getUser(callerUid);

      if (!mounted ||
          generation != _incomingListenerGeneration ||
          _auth.currentUser?.uid != receiverUid) {
        return;
      }

      if (callerProfile != null) {
        final String profileName = callerProfile.name.trim();

        if (profileName.isNotEmpty) {
          callerName = profileName;
        }

        final String profilePhoto =
            callerProfile.profilePhotoUrl?.trim() ?? '';

        if (profilePhoto.isNotEmpty) {
          callerPhotoUrl = profilePhoto;
        }

        final String jrCallId = callerProfile.jrCallUserId?.trim() ?? '';

        final String username = callerProfile.username?.trim() ?? '';

        if (jrCallId.isNotEmpty) {
          callerPublicId = jrCallId;
        } else if (username.isNotEmpty) {
          callerPublicId = username.startsWith('@')
              ? username
              : '@$username';
        }
      }
    } catch (error, stackTrace) {
      _reportError('incoming-caller-profile', error, stackTrace);
    }

    if (!mounted ||
        generation != _incomingListenerGeneration ||
        _auth.currentUser?.uid != receiverUid) {
      _openingIncomingCall = false;
      _presentedIncomingCallId = null;
      return;
    }

    final bool isVideoCall = _readBool(callData['isVideoCall']) ?? false;

    // Receiver has now actually seen the incoming call.
    // Publish RINGING through SignalingService so caller receives
    // the real ringing state.
    final String currentStatus =
        _readString(callData['status'])?.toLowerCase() ?? '';

    if (currentStatus == 'calling') {
      try {
        await _signalingService.updateCallStatus(callId, 'ringing');
      } catch (error, stackTrace) {
        _reportError('incoming-ringing-status', error, stackTrace);
      }
    }

    if (!mounted ||
        generation != _incomingListenerGeneration ||
        _auth.currentUser?.uid != receiverUid) {
      _openingIncomingCall = false;
      _presentedIncomingCallId = null;
      return;
    }

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext routeContext) {
            return IncomingCallScreen(
              callerName: callerName,
              callerId: callerPublicId,
              callerPhotoUrl: callerPhotoUrl,
              isVideoCall: isVideoCall,

              // =================================================
              // ACCEPT
              // =================================================
              onAccept: () async {
                await _callService.acceptCall(callId: callId);

                // CallService only keeps currentCallId after
                // successful active call establishment.
                if (_callService.currentCallId != callId) {
                  throw StateError(
                    'JR CALL could not establish the incoming call.',
                  );
                }

                if (routeContext.mounted) {
                  Navigator.of(routeContext).pop();
                }
              },

              // =================================================
              // REJECT
              // =================================================
              onReject: () async {
                await _callService.rejectCall(callId: callId);

                if (routeContext.mounted) {
                  Navigator.of(routeContext).pop();
                }
              },
            );
          },
        ),
      );
    } catch (error, stackTrace) {
      _reportError('incoming-call-screen', error, stackTrace);
    } finally {
      if (generation == _incomingListenerGeneration) {
        _openingIncomingCall = false;

        if (_presentedIncomingCallId == callId) {
          _presentedIncomingCallId = null;
        }
      }
    }
  }

  // =============================================================
  // PROFILE
  // =============================================================

  Future<void> _loadProfile() async {
    final int generation = ++_profileLoadGeneration;

    await _profileSubscription?.cancel();

    if (generation != _profileLoadGeneration) {
      return;
    }

    _profileSubscription = null;

    final User? firebaseUser = _auth.currentUser;

    if (firebaseUser == null) {
      if (mounted && generation == _profileLoadGeneration && _profile != null) {
        setState(() {
          _profile = null;
        });
      }

      return;
    }

    final String uid = firebaseUser.uid;

    try {
      final UserModel? initialProfile = await _firestore.getUser(uid);

      if (!mounted ||
          generation != _profileLoadGeneration ||
          _auth.currentUser?.uid != uid) {
        return;
      }

      setState(() {
        _profile = initialProfile;
      });

      _profileSubscription = _firestore
          .watchUser(uid)
          .listen(
            (UserModel? value) {
          if (!mounted ||
              generation != _profileLoadGeneration ||
              _auth.currentUser?.uid != uid) {
            return;
          }

          setState(() {
            _profile = value;
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          _reportError('profile-stream', error, stackTrace);
        },
      );
    } catch (error, stackTrace) {
      _reportError('profile-load', error, stackTrace);
    }
  }

  String? get _profilePhotoUrl {
    final String? firestorePhoto = _profile?.profilePhotoUrl?.trim();

    if (firestorePhoto != null && firestorePhoto.isNotEmpty) {
      return firestorePhoto;
    }

    final String? authPhoto = _auth.currentUser?.photoURL?.trim();

    if (authPhoto != null && authPhoto.isNotEmpty) {
      return authPhoto;
    }

    return null;
  }

  // =============================================================
  // AUTH GATE
  // =============================================================

  Future<bool> _requireAuth(String action) async {
    if (_signedIn) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final String? selectedAction = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            bottom: 14 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 11, 20, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: _border),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1713273F),
                  blurRadius: 32,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7E0EB),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: _blue.withValues(alpha: 0.12),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_person_outlined,
                    color: _blue,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Account Required',
                  style: TextStyle(
                    color: _text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Log in or create an account to $action.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop('login');
                    },
                    child: const Text('LOG IN'),
                  ),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop('create');
                    },
                    child: const Text('CREATE ACCOUNT'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedAction == null) {
      return false;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          if (selectedAction == 'create') {
            return const CreateAccountScreen();
          }

          return const LoginScreen();
        },
      ),
    );

    if (!mounted) {
      return false;
    }

    await _loadProfile();

    return _signedIn;
  }

  // =============================================================
  // BOTTOM DESTINATION NAVIGATION
  // =============================================================

  Future<void> _selectDestination(int value) async {
    final int next = _normalizeIndex(value);

    if (next == _selectedIndex) {
      return;
    }

    if (!_signedIn && _isProtectedDestination(next)) {
      final bool allowed = await _requireAuth(
        switch (next) {
          _callIndex => 'use JR CALL calling',
          _messageIndex => 'open your conversations',
          _aiToolsIndex => 'use AI Edit Post tools',
          _ => 'continue',
        },
      );

      if (!allowed || !mounted) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedIndex = next;
    });
  }

  // =============================================================
  // NAVIGATION
  // =============================================================

  Future<void> _openContacts({bool requireAuthentication = false}) async {
    if (requireAuthentication) {
      final bool allowed = await _requireAuth('open JR CALL contacts');

      if (!allowed || !mounted) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ContactsScreen(),
      ),
    );
  }

  Future<void> _openProfile() async {
    final bool allowed = await _requireAuth('open your profile');

    if (!allowed || !mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ProfileScreen(),
      ),
    );

    if (mounted) {
      await _loadProfile();
    }
  }

  Future<void> _openSettings() async {
    final bool allowed = await _requireAuth('open your settings');

    if (!allowed || !mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SettingsScreen(),
      ),
    );

    if (mounted) {
      await _loadProfile();
    }
  }

  Future<void> _openCallHistory() async {
    final bool allowed = await _requireAuth('view your call history');

    if (!allowed || !mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return CallHistoryScreen(historyProvider: _historyProvider);
        },
      ),
    );
  }

  Future<void> _addContact() async {
    final bool allowed = await _requireAuth('add a JR CALL contact');

    if (!allowed || !mounted) {
      return;
    }

    await _openContacts();
  }

  // =============================================================
  // FEEDBACK
  // =============================================================

  void _showNotice(String message) {
    final String normalizedMessage = message.trim();

    if (!mounted || normalizedMessage.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(normalizedMessage),
        ),
      );
  }

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint('JR CALL [HomeScreen/$source] error: $error');

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [HomeScreen/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // =============================================================
  // CALL DATA HELPERS
  // =============================================================

  String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  bool? _readBool(Object? value) {
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
      final String normalized = value.trim().toLowerCase();

      if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes') {
        return true;
      }

      if (normalized == 'false' ||
          normalized == '0' ||
          normalized == 'no') {
        return false;
      }
    }

    return null;
  }

  DateTime? _timestampToDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value.trim());
    }

    return null;
  }

  // =============================================================
  // ROOT
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFFFBFDFF),
                Color(0xFFF6F9FE),
                Color(0xFFFBFAFF),
              ],
            ),
          ),
          child: Column(
            children: <Widget>[
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: <Widget>[
                    _buildCallPage(),
                    _buildMessagePage(),
                    _buildPublicMediaPage(),
                    _buildVideoReelsPage(),
                    _buildAiToolsPage(),
                  ],
                ),
              ),
              _BottomNavigation(
                index: _selectedIndex,
                onTap: (int index) {
                  unawaited(_selectDestination(index));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =============================================================
  // CALL PAGE
  // =============================================================

  Widget _buildCallPage() {
    return AnimatedBuilder(
      animation: _historyProvider,
      builder: (BuildContext context, Widget? child) {
        final List<CallHistoryModel> history = _historyProvider.callHistory
            .take(8)
            .toList(growable: false);

        return RefreshIndicator(
          color: _blue,
          onRefresh: _historyProvider.refresh,
          child: ListView(
            key: const PageStorageKey<String>('jr-call-home'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            children: <Widget>[
              _TopActions(
                items: <_TopActionData>[
                  _TopActionData(
                    icon: Icons.search_rounded,
                    label: 'Search',
                    onTap: () {
                      unawaited(_openContacts(requireAuthentication: true));
                    },
                  ),
                  _TopActionData(
                    icon: Icons.contacts_outlined,
                    label: 'Contacts',
                    onTap: () {
                      unawaited(_openContacts(requireAuthentication: true));
                    },
                  ),
                  _TopActionData(
                    icon: Icons.add_rounded,
                    label: 'Add',
                    onTap: () {
                      unawaited(_addContact());
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!_signedIn)
                _ProtectedDestinationCard(
                  icon: Icons.call_rounded,
                  color: _call,
                  title: 'JR CALL',
                  description:
                  'Log in to call people, access contacts and view your private call history.',
                  onTap: () {
                    unawaited(_requireAuth('use JR CALL calling'));
                  },
                )
              else if (_historyProvider.isLoading && history.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 56),
                  child: Center(
                    child: CircularProgressIndicator(color: _blue),
                  ),
                )
              else if (_historyProvider.error != null && history.isEmpty)
                  _ProductionStateCard(
                    icon: Icons.error_outline_rounded,
                    color: const Color(0xFFFF2448),
                    title: 'Unable to load call history',
                    description: _historyProvider.error!,
                    actionLabel: 'Retry',
                    onAction: () {
                      unawaited(_historyProvider.refresh());
                    },
                  )
                else if (history.isEmpty)
                    _CallEmptyState(
                      onHistory: () {
                        unawaited(_openCallHistory());
                      },
                      onFind: () {
                        unawaited(_openContacts(requireAuthentication: true));
                      },
                    )
                  else ...<Widget>[
                      ...history.map(
                            (CallHistoryModel call) => Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: _CallTile(
                            call: call,
                            onTap: () {
                              unawaited(_openCallHistory());
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _ViewAllButton(
                        color: _blue,
                        label: 'View complete call history',
                        onTap: () {
                          unawaited(_openCallHistory());
                        },
                      ),
                    ],
            ],
          ),
        );
      },
    );
  }

  // =============================================================
  // MESSAGE PAGE
  // =============================================================

  Widget _buildMessagePage() {
    return ListView(
      key: const PageStorageKey<String>('jr-message-home'),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      children: <Widget>[
        _TopActions(
          items: <_TopActionData>[
            _TopActionData(
              icon: Icons.search_rounded,
              label: 'Search',
              onTap: () {
                if (!_signedIn) {
                  unawaited(_requireAuth('search your messages'));
                  return;
                }

                _showNotice(
                  'Message search will use your real conversations.',
                );
              },
            ),
            _TopActionData(
              icon: Icons.contacts_outlined,
              label: 'Contacts',
              onTap: () {
                unawaited(_openContacts(requireAuthentication: true));
              },
            ),
            _TopActionData(
              icon: Icons.add_rounded,
              label: 'Add',
              onTap: () {
                unawaited(_addContact());
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (!_signedIn)
          _ProtectedDestinationCard(
            icon: Icons.chat_bubble_rounded,
            color: _message,
            title: 'Your conversations',
            description:
            'Log in to access your private JR CALL conversations.',
            onTap: () {
              unawaited(_requireAuth('view your conversations'));
            },
          )
        else
          _ProductionStateCard(
            icon: Icons.chat_bubble_outline_rounded,
            color: _message,
            title: 'No conversations yet',
            description:
            'Your real conversations will appear here. Find a JR CALL user to start messaging.',
            actionLabel: 'Find People',
            onAction: () {
              unawaited(_openContacts());
            },
          ),
      ],
    );
  }

  // =============================================================
  // PUBLIC MEDIA PAGE
  // =============================================================

  Widget _buildPublicMediaPage() {
    return ListView(
      key: const PageStorageKey<String>('jr-public-media'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      children: <Widget>[
        _TopActions(
          items: <_TopActionData>[
            _TopActionData(
              icon: Icons.search_rounded,
              label: 'Search',
              onTap: () {
                _showNotice(
                  'Public Media search will use real published content.',
                );
              },
            ),
            _TopActionData(
              icon: Icons.storefront_outlined,
              label: 'Marketplace',
              onTap: () {
                _showNotice(
                  'Marketplace will open when its production backend is connected.',
                );
              },
            ),
            _TopActionData(
              icon: Icons.person_rounded,
              label: 'Profile',
              imageUrl: _profilePhotoUrl,
              onTap: () {
                unawaited(_openProfile());
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MediaCreateBar(
          onTap: (String type) {
            unawaited(_requireAuth('create a $type post'));
          },
        ),
        const SizedBox(height: 11),
        const _MediaFilters(),
        const SizedBox(height: 14),
        _NewPeopleStrip(
          onFindPeople: () {
            if (_signedIn) {
              unawaited(_openContacts());
            } else {
              unawaited(_requireAuth('discover JR CALL people'));
            }
          },
        ),
        const SizedBox(height: 14),
        _MediaComposer(
          imageUrl: _profilePhotoUrl,
          signedIn: _signedIn,
          onTap: () {
            unawaited(_requireAuth('create a public post'));
          },
        ),
        const SizedBox(height: 14),
        const _PublicFeedEmpty(),
      ],
    );
  }

  // =============================================================
  // VIDEO REELS PAGE
  // =============================================================

  Widget _buildVideoReelsPage() {
    return _VideoReelsProductionSurface(
      signedIn: _signedIn,
      onUpload: () {
        unawaited(_requireAuth('upload a video reel'));
      },
      onProfile: () {
        unawaited(_openProfile());
      },
    );
  }

  // =============================================================
  // AI EDIT POST / ALL TOOLS
  // =============================================================

  Widget _buildAiToolsPage() {
    const List<_ToolData> tools = <_ToolData>[
      _ToolData(
        Icons.text_snippet_rounded,
        'Text to Video',
        'AI Powered',
        Color(0xFF1089F7),
      ),
      _ToolData(
        Icons.video_camera_back_rounded,
        'Video to Video',
        'AI Powered',
        Color(0xFFDF28DF),
      ),
      _ToolData(
        Icons.add_photo_alternate_rounded,
        'Photo to Video',
        'AI Powered',
        Color(0xFF00BFA5),
      ),
      _ToolData(
        Icons.music_note_rounded,
        'Music to Video',
        'AI Powered',
        Color(0xFFFF7A00),
      ),
      _ToolData(
        Icons.mic_rounded,
        'Voice to Video',
        'AI Powered',
        Color(0xFF7D31ED),
      ),
      _ToolData(
        Icons.video_settings_rounded,
        'Video Editing',
        'Pro Tools',
        Color(0xFF00A6F5),
      ),
      _ToolData(
        Icons.person_rounded,
        'My Profile',
        'View & Manage',
        Color(0xFF04BDD0),
      ),
      _ToolData(
        Icons.settings_rounded,
        'Settings',
        'Preferences',
        Color(0xFF3164F4),
      ),
      _ToolData(
        Icons.chat_bubble_rounded,
        'Messages',
        'Conversations',
        Color(0xFFF32976),
      ),
      _ToolData(
        Icons.folder_rounded,
        'My Files',
        'Documents & Media',
        Color(0xFFFFA000),
      ),
      _ToolData(
        Icons.cloud_upload_rounded,
        'Cloud Storage',
        'Save & Sync',
        Color(0xFF1599F5),
      ),
      _ToolData(
        Icons.contacts_rounded,
        'Contacts',
        'All Contacts',
        Color(0xFF00C99A),
      ),
      _ToolData(
        Icons.live_tv_rounded,
        'Live Streaming',
        'Go Live Now',
        Color(0xFF7836F1),
      ),
      _ToolData(
        Icons.event_rounded,
        'Events',
        'Upcoming Events',
        Color(0xFFF32976),
      ),
      _ToolData(
        Icons.storefront_rounded,
        'Marketplace',
        'Buy & Sell',
        Color(0xFFFF7A00),
      ),
      _ToolData(
        Icons.shield_rounded,
        'Privacy & Security',
        'Stay Protected',
        Color(0xFF1599F5),
      ),
    ];

    return GridView.builder(
      key: const PageStorageKey<String>('jr-ai-tools'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      itemCount: tools.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 11,
        mainAxisSpacing: 11,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (BuildContext context, int index) {
        final _ToolData tool = tools[index];

        return _ToolCard(
          tool: tool,
          onTap: () {
            switch (tool.title) {
              case 'My Profile':
                unawaited(_openProfile());
                return;

              case 'Settings':
              case 'Privacy & Security':
                unawaited(_openSettings());
                return;

              case 'Messages':
                unawaited(_selectDestination(_messageIndex));
                return;

              case 'Contacts':
                unawaited(_openContacts(requireAuthentication: true));
                return;

              default:
                unawaited(_requireAuth('use ${tool.title}'));
            }
          },
        );
      },
    );
  }
}

// ===============================================================
// TOP ACTIONS
// ===============================================================

class _TopActions extends StatelessWidget {
  const _TopActions({required this.items});

  final List<_TopActionData> items;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(items.length, (int index) {
          return Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 10),
            child: _TopActionButton(item: items[index]),
          );
        }),
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({required this.item});

  final _TopActionData item;

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = item.imageUrl?.trim();

    return Semantics(
      button: true,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEBF0F7)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x0D12253D),
                        blurRadius: 11,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: imageUrl == null || imageUrl.isEmpty
                      ? Icon(item.icon, size: 23, color: Colors.black)
                      : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder:
                        (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                        ) {
                      return Icon(
                        item.icon,
                        size: 23,
                        color: Colors.black,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _HomeScreenState._text,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
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
// CALL EMPTY
// ===============================================================

class _CallEmptyState extends StatelessWidget {
  const _CallEmptyState({
    required this.onHistory,
    required this.onFind,
  });

  final VoidCallback onHistory;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _SimpleTile(
          icon: Icons.history_rounded,
          color: _HomeScreenState._call,
          title: 'Call History',
          subtitle: 'Open your complete recent call history',
          trailing: Icons.chevron_right_rounded,
          onTap: onHistory,
        ),
        const SizedBox(height: 11),
        _SimpleTile(
          icon: Icons.person_search_rounded,
          color: _HomeScreenState._blue,
          title: 'Find a JR CALL user',
          subtitle: 'Name • JR ID • phone • email',
          trailing: Icons.call_rounded,
          onTap: onFind,
        ),
      ],
    );
  }
}

// ===============================================================
// CALL TILE
// ===============================================================

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.call,
    required this.onTap,
  });

  final CallHistoryModel call;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String status = call.status.name.trim().toLowerCase();

    final String direction = call.direction.name.trim().toLowerCase();

    final String callType = call.callType.name.trim().toLowerCase();

    final bool missed = status == 'missed';

    final bool outgoing = direction == 'outgoing';

    final bool video = callType == 'video';

    final String name = call.contactName.trim().isEmpty
        ? 'Unknown caller'
        : call.contactName.trim();

    final String phone = call.phoneNumber.trim();

    final String avatar = call.avatarUrl.trim();

    final Color accent = missed
        ? const Color(0xFFFF2448)
        : video
        ? const Color(0xFF8B35F5)
        : outgoing
        ? _HomeScreenState._blue
        : _HomeScreenState._call;

    final Color cardColor = missed
        ? const Color(0xFFFFF4F6)
        : video
        ? const Color(0xFFFBF7FF)
        : const Color(0xFFFAFCFF);

    final String label = _callHistoryLabel(
      status: status,
      outgoing: outgoing,
      video: video,
    );

    final IconData statusIcon = _callHistoryIcon(
      status: status,
      outgoing: outgoing,
      video: video,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
          decoration: BoxDecoration(
            color: cardColor.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: missed
                  ? const Color(0xFFFFDCE3)
                  : video
                  ? const Color(0xFFEDE2FF)
                  : const Color(0xFFDFE9F7),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.055),
                blurRadius: 17,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.20),
                      blurRadius: 15,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 29,
                  backgroundColor: accent.withValues(alpha: 0.10),
                  backgroundImage: avatar.isEmpty
                      ? null
                      : NetworkImage(avatar),
                  child: avatar.isEmpty
                      ? Icon(
                    Icons.person_rounded,
                    color: accent,
                    size: 28,
                  )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _HomeScreenState._text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (phone.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _HomeScreenState._muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Icon(
                          statusIcon,
                          size: 15,
                          color: accent,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.10),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  video ? Icons.videocam_rounded : Icons.call_rounded,
                  color: accent,
                  size: 25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _callHistoryLabel({
    required String status,
    required bool outgoing,
    required bool video,
  }) {
    switch (status) {
      case 'missed':
        return 'Missed call';

      case 'rejected':
        return 'Call rejected';

      case 'declined':
        return 'Call declined';

      case 'cancelled':
      case 'canceled':
        return 'Call cancelled';

      case 'failed':
        return 'Call failed';

      case 'timeout':
        return 'Call timed out';

      case 'busy':
      case 'user_busy':
        return 'User busy';
    }

    if (video) {
      return outgoing
          ? 'Outgoing video call'
          : 'Incoming video call';
    }

    return outgoing ? 'Outgoing call' : 'Incoming call';
  }

  IconData _callHistoryIcon({
    required String status,
    required bool outgoing,
    required bool video,
  }) {
    switch (status) {
      case 'missed':
        return Icons.call_missed_rounded;

      case 'rejected':
      case 'declined':
      case 'cancelled':
      case 'canceled':
        return Icons.call_end_rounded;

      case 'failed':
      case 'timeout':
      case 'busy':
      case 'user_busy':
        return Icons.error_outline_rounded;
    }

    if (video) {
      return Icons.videocam_outlined;
    }

    return outgoing
        ? Icons.call_made_rounded
        : Icons.call_received_rounded;
  }
}

// ===============================================================
// PROTECTED DESTINATION
// ===============================================================

class _ProtectedDestinationCard extends StatelessWidget {
  const _ProtectedDestinationCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ProductionStateCard(
      icon: icon,
      color: color,
      title: title,
      description: description,
      actionLabel: 'Log In / Create Account',
      onAction: onTap,
    );
  }
}

// ===============================================================
// MEDIA CREATE BAR
// ===============================================================

class _MediaCreateBar extends StatelessWidget {
  const _MediaCreateBar({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    const List<_MediaActionData> items = <_MediaActionData>[
      _MediaActionData(
        Icons.text_fields_rounded,
        'Text',
        Color(0xFF087AF5),
      ),
      _MediaActionData(
        Icons.photo_rounded,
        'Photo',
        Color(0xFF00BE7B),
      ),
      _MediaActionData(
        Icons.videocam_rounded,
        'Video',
        Color(0xFF087AF5),
      ),
      _MediaActionData(
        Icons.wifi_tethering_rounded,
        'Live',
        Color(0xFFFF1744),
      ),
      _MediaActionData(
        Icons.description_rounded,
        'Document',
        Color(0xFFB63CFA),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 11,
        horizontal: 2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _HomeScreenState._border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0C17233B),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: items
            .map(
              (_MediaActionData item) => Expanded(
            child: InkWell(
              onTap: () {
                onTap(item.label.toLowerCase());
              },
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      item.icon,
                      color: item.color,
                      size: 22,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: _HomeScreenState._text,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
            .toList(growable: false),
      ),
    );
  }
}

// ===============================================================
// MEDIA FILTERS
// ===============================================================

class _MediaFilters extends StatelessWidget {
  const _MediaFilters();

  @override
  Widget build(BuildContext context) {
    const List<String> filters = <String>[
      'All',
      'Following',
      'Trending',
      'Nearby',
      'Live',
      'People',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(filters.length, (int index) {
          final bool selected = index == 0;

          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFEAF3FF)
                  : Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: selected
                    ? const Color(0xFFB8D8FF)
                    : _HomeScreenState._border,
              ),
              boxShadow: selected
                  ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x12087AF5),
                  blurRadius: 12,
                ),
              ]
                  : const <BoxShadow>[],
            ),
            child: Text(
              filters[index],
              style: TextStyle(
                color: selected
                    ? _HomeScreenState._blue
                    : _HomeScreenState._text,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ===============================================================
// NEW PEOPLE
// ===============================================================

class _NewPeopleStrip extends StatelessWidget {
  const _NewPeopleStrip({required this.onFindPeople});

  final VoidCallback onFindPeople;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _HomeScreenState._border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A17233B),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _HomeScreenState._blue.withValues(
                alpha: 0.08,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.group_add_outlined,
              color: _HomeScreenState._blue,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'New People',
                  style: TextStyle(
                    color: _HomeScreenState._text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Discover real JR CALL users',
                  style: TextStyle(
                    color: _HomeScreenState._muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onFindPeople,
            child: const Text('See All'),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// MEDIA COMPOSER
// ===============================================================

class _MediaComposer extends StatelessWidget {
  const _MediaComposer({
    required this.imageUrl,
    required this.signedIn,
    required this.onTap,
  });

  final String? imageUrl;
  final bool signedIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? normalizedImageUrl = imageUrl?.trim();

    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _HomeScreenState._border,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0917233B),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFEAF3FF),
                backgroundImage:
                normalizedImageUrl == null ||
                    normalizedImageUrl.isEmpty
                    ? null
                    : NetworkImage(normalizedImageUrl),
                child:
                normalizedImageUrl == null ||
                    normalizedImageUrl.isEmpty
                    ? Icon(
                  signedIn
                      ? Icons.person_rounded
                      : Icons.public_rounded,
                  color: _HomeScreenState._blue,
                )
                    : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  signedIn
                      ? 'Share something...'
                      : 'Log in to create a post',
                  style: const TextStyle(
                    color: _HomeScreenState._muted,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _HomeScreenState._media.withValues(
                    alpha: 0.08,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: _HomeScreenState._media,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// PUBLIC FEED
// ===============================================================

class _PublicFeedEmpty extends StatelessWidget {
  const _PublicFeedEmpty();

  @override
  Widget build(BuildContext context) {
    return const _ProductionStateCard(
      icon: Icons.dynamic_feed_outlined,
      color: _HomeScreenState._media,
      title: 'Public Media',
      description:
      'Real public posts, photos, videos, live streams and documents will appear here when available.',
    );
  }
}

// ===============================================================
// VIDEO REELS
// ===============================================================

class _VideoReelsProductionSurface extends StatelessWidget {
  const _VideoReelsProductionSurface({
    required this.signedIn,
    required this.onUpload,
    required this.onProfile,
  });

  final bool signedIn;
  final VoidCallback onUpload;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const PageStorageKey<String>('jr-video-reels'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF45576E),
            Color(0xFF202B3A),
            Color(0xFF080B10),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const Positioned(
            top: 18,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'For You',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(width: 28),
                Text(
                  'Following',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 34,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: 0.08,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: 0.17,
                        ),
                      ),
                    ),
                    child: const Icon(
                      Icons.play_circle_outline_rounded,
                      color: Colors.white,
                      size: 43,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Video Reels',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Real short videos will appear here when published.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onUpload,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      signedIn
                          ? 'Upload Reel'
                          : 'Log In to Upload',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 28,
            child: Column(
              children: <Widget>[
                _ReelSideButton(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  onTap: onProfile,
                ),
                const SizedBox(height: 15),
                const _ReelSideButton(
                  icon: Icons.favorite_border_rounded,
                  label: 'Like',
                ),
                const SizedBox(height: 15),
                const _ReelSideButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Comment',
                ),
                const SizedBox(height: 15),
                const _ReelSideButton(
                  icon: Icons.share_outlined,
                  label: 'Share',
                ),
                const SizedBox(height: 15),
                const _ReelSideButton(
                  icon: Icons.search_rounded,
                  label: 'Search',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelSideButton extends StatelessWidget {
  const _ReelSideButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Column(
        children: <Widget>[
          Icon(
            icon,
            color: Colors.white,
            size: 29,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// AI TOOL CARD
// ===============================================================

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
    required this.onTap,
  });

  final _ToolData tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tool.title,
      child: Material(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: tool.color.withValues(alpha: 0.15),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tool.color.withValues(alpha: 0.065),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: Icon(
                      tool.icon,
                      color: tool.color,
                      size: 31,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        tool.title,
                        maxLines: 2,
                        overflow:
                        TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tool.color,
                          fontSize: 11,
                          fontWeight:
                          FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tool.subtitle,
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style: const TextStyle(
                          color:
                          _HomeScreenState
                              ._muted,
                          fontSize: 8.5,
                        ),
                      ),
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
}

// ===============================================================
// PRODUCTION STATE CARD
// ===============================================================

class _ProductionStateCard extends StatelessWidget {
  const _ProductionStateCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 30,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: _HomeScreenState._border,
        ),
        boxShadow: <BoxShadow>[
          const BoxShadow(
            color: Color(0x0C17233B),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
          BoxShadow(
            color: color.withValues(alpha: 0.035),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.11),
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: 35,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _HomeScreenState._text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _HomeScreenState._muted,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

// ===============================================================
// SIMPLE TILE
// ===============================================================

class _SimpleTile extends StatelessWidget {
  const _SimpleTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final IconData trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _HomeScreenState._border,
            ),
            boxShadow: <BoxShadow>[
              const BoxShadow(
                color: Color(0x0917233B),
                blurRadius: 13,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.04),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(
                  alpha: 0.10,
                ),
                child: Icon(
                  icon,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color:
                        _HomeScreenState._text,
                        fontSize: 14,
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style: const TextStyle(
                        color:
                        _HomeScreenState._muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                trailing,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// VIEW ALL
// ===============================================================

class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(
          Icons.history_rounded,
          color: color,
          size: 18,
        ),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// BOTTOM NAVIGATION
// ===============================================================

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.index,
    required this.onTap,
  });

  final int index;
  final ValueChanged<int> onTap;

  static const List<_NavigationData> _items =
  <_NavigationData>[
    _NavigationData(
      Icons.call_rounded,
      'Call',
      _HomeScreenState._call,
    ),
    _NavigationData(
      Icons.chat_bubble_rounded,
      'Message',
      _HomeScreenState._message,
    ),
    _NavigationData(
      Icons.grid_view_rounded,
      'Public Media',
      _HomeScreenState._media,
    ),
    _NavigationData(
      Icons.videocam_rounded,
      'Video Reels',
      _HomeScreenState._reels,
    ),
    _NavigationData(
      Icons.auto_awesome_rounded,
      'AI Edit Post',
      _HomeScreenState._tools,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.fromLTRB(5, 7, 5, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: const Color(0xFFE9EEF6),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1512253D),
            blurRadius: 24,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: List<Widget>.generate(
          _items.length,
              (int itemIndex) {
            final _NavigationData item =
            _items[itemIndex];

            final bool selected =
                itemIndex == index;

            return Expanded(
              child: Semantics(
                selected: selected,
                button: true,
                label: item.label,
                child: InkResponse(
                  onTap: () {
                    onTap(itemIndex);
                  },
                  radius: 31,
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: <Widget>[
                      AnimatedContainer(
                        duration: const Duration(
                          milliseconds: 180,
                        ),
                        curve: Curves.easeOutCubic,
                        width: selected ? 49 : 44,
                        height: selected ? 49 : 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                          BorderRadius.circular(
                            15,
                          ),
                          border: Border.all(
                            color: item.color
                                .withValues(
                              alpha:
                              selected
                                  ? 0.28
                                  : 0.10,
                            ),
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: item.color
                                  .withValues(
                                alpha:
                                selected
                                    ? 0.20
                                    : 0.07,
                              ),
                              blurRadius:
                              selected
                                  ? 15
                                  : 7,
                              offset:
                              const Offset(
                                0,
                                4,
                              ),
                            ),
                          ],
                        ),
                        child: Icon(
                          item.icon,
                          color: item.color,
                          size:
                          selected
                              ? 27
                              : 23,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow:
                        TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color:
                          _HomeScreenState
                              ._text,
                          fontSize: 8.5,
                          fontWeight:
                          selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ===============================================================
// DATA OBJECTS
// ===============================================================

class _TopActionData {
  const _TopActionData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.imageUrl,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? imageUrl;
}

class _MediaActionData {
  const _MediaActionData(
      this.icon,
      this.label,
      this.color,
      );

  final IconData icon;
  final String label;
  final Color color;
}

class _ToolData {
  const _ToolData(
      this.icon,
      this.title,
      this.subtitle,
      this.color,
      );

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _NavigationData {
  const _NavigationData(
      this.icon,
      this.label,
      this.color,
      );

  final IconData icon;
  final String label;
  final Color color;
}

// ===============================================================
// END OF FILE
//
// PRESERVED:
// - Existing approved Home UI
// - Five bottom destinations
// - Call history
// - Public Media
// - Video Reels
// - AI Edit Post
// - Profile/settings/navigation
// - Guest/Auth behavior
//
// ADDED:
// - Receiver-side Firestore listener scoped to receiver UID
// - No whole calls collection download
// - Duplicate incoming-screen protection
// - Old/stale incoming-call protection
// - Caller profile/name/photo/JR ID resolution
// - CALLING -> real RINGING signaling
// - IncomingCallScreen presentation
// - Accept -> CallService.acceptCall()
// - Reject -> CallService.rejectCall()
// - Voice/video type preserved
//
// NO DUPLICATION:
// - No PeerConnection created here
// - No WebRTC ownership here
// - No ICE ownership here
// - No duration timer here
// - No fake CONNECTED state
//
// NEXT:
// Save this entire file as:
// lib/screens/home_screen.dart
// ===============================================================