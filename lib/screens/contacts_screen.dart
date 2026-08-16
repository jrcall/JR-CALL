// ===============================================================
// JR CALL
// File: contacts_screen.dart
// Location: lib/screens/contacts_screen.dart
//
// Fixes:
// - BUG 03: Search result -> resolved Firebase UID/public profile handoff
// - BUG 05: Search field must never behave as credential input
// - BUG 07: Voice call now enters the REAL CallService lifecycle
// - BUG 08: Video call now enters the REAL CallService lifecycle
//
// PRODUCTION-SAFE REPLACEMENT
//
// IMPORTANT:
// - Firebase UID remains canonical internal identity.
// - Search/display identity never replaces Firebase UID.
// - CallService.startCall() owns real outgoing call creation.
// - No duplicate signaling/WebRTC/Firestore call implementation here.
// - Guest search/public profile remains available.
// - Voice/Video/Message remain authentication protected.
// - Existing ContactsScreen constructor preserved.
// - Existing ContactModel / Discovery APIs preserved.
// ===============================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/theme/jr_colors.dart';
import '../models/contact_model.dart';
import '../services/call/call_service.dart';
import '../services/user_discovery_service.dart';
import '../widgets/caller_avatar.dart';
import '../widgets/video_button.dart';
import 'create_account_screen.dart';
import 'login_screen.dart';
import 'outgoing_call_screen.dart';
import 'profile_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, this.contacts = const <ContactModel>[]});

  final List<ContactModel> contacts;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  // =============================================================
  // CONSTANTS
  // =============================================================

  static const Duration _debounce = Duration(milliseconds: 420);

  static const int _pageSize = UserDiscoveryService.defaultPageSize;

  static const double _maxWidth = 720;

  // =============================================================
  // SERVICES
  // =============================================================

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final UserDiscoveryService _discovery = UserDiscoveryService.instance;

  final CallService _callService = CallService();

  // =============================================================
  // CONTROLLERS
  // =============================================================

  final TextEditingController _search = TextEditingController();

  final ScrollController _scroll = ScrollController();

  final FocusNode _searchFocus = FocusNode(
    debugLabel: 'JR_CALL_PUBLIC_DISCOVERY_SEARCH',
  );

  // =============================================================
  // DATA
  // =============================================================

  late List<ContactModel> _contacts;

  late List<ContactModel> _localResults;

  List<DiscoveryUser> _remoteResults = <DiscoveryUser>[];

  DocumentSnapshot<Map<String, dynamic>>? _cursor;

  Timer? _timer;

  String _activeQuery = '';

  String? _error;

  bool _searching = false;

  bool _loadingMore = false;

  bool _hasMore = false;

  bool _startingCall = false;

  int _generation = 0;

  // =============================================================
  // AUTH
  // =============================================================

  bool get _authenticated => _auth.currentUser != null;

  String? get _currentUid {
    final String value = _auth.currentUser?.uid.trim() ?? '';

    return value.isEmpty ? null : value;
  }

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _contacts = List<ContactModel>.unmodifiable(widget.contacts);

    _localResults = List<ContactModel>.of(_contacts);

    _search.addListener(_onSearchChanged);

    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ContactsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (identical(oldWidget.contacts, widget.contacts)) {
      return;
    }

    _contacts = List<ContactModel>.unmodifiable(widget.contacts);

    final String query = _search.text.trim();

    if (query.isEmpty) {
      _localResults = List<ContactModel>.of(_contacts);
    } else {
      _filterLocal(query);
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _generation++;

    _timer?.cancel();

    _search.removeListener(_onSearchChanged);

    _scroll.removeListener(_onScroll);

    _search.dispose();

    _scroll.dispose();

    _searchFocus.dispose();

    // CallService is a shared singleton.
    // DO NOT dispose it from this screen.

    super.dispose();
  }

  // =============================================================
  // AUTH GATE
  // =============================================================

  Future<bool> _requireAuthentication(String action) async {
    if (_authenticated) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final String? choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: JrColors.border),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x180F172A),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFD8E0EC),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Icon(
                Icons.lock_person_outlined,
                color: JrColors.primaryBlue,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'JR CALL Account Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: JrColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Login or create your JR CALL account to $action.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JrColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop('login');
                  },
                  child: const Text('LOGIN'),
                ),
              ),
              const SizedBox(height: 10),
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
        );
      },
    );

    if (!mounted || choice == null) {
      return false;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return choice == 'create'
              ? const CreateAccountScreen()
              : const LoginScreen();
        },
        settings: RouteSettings(
          arguments: <String, dynamic>{
            'guestReturn': true,
            'requestedAction': action,
          },
        ),
      ),
    );

    return mounted && _authenticated;
  }

  // =============================================================
  // SEARCH
  // =============================================================

  void _onSearchChanged() {
    _timer?.cancel();

    final String query = _search.text.trim();

    if (query.isEmpty) {
      _resetSearch();
      return;
    }

    _filterLocal(query);

    if (mounted) {
      setState(() {
        _error = null;
      });
    }

    _timer = Timer(_debounce, () {
      unawaited(_searchRemote(query));
    });
  }

  void _filterLocal(String query) {
    final String normalized = query.trim().toLowerCase();

    if (normalized.isEmpty) {
      _localResults = List<ContactModel>.of(_contacts);
      return;
    }

    final String usernameQuery = normalized.startsWith('@')
        ? normalized.substring(1)
        : normalized;

    _localResults = _contacts
        .where((ContactModel contact) {
      String username = contact.username?.trim().toLowerCase() ?? '';

      if (username.startsWith('@')) {
        username = username.substring(1);
      }

      final List<String> searchable =
      <String>[
        contact.name,
        contact.phoneNumber,
        contact.email,
        contact.userId,
        contact.linkedUid ?? '',
        contact.jrCallUserId ?? '',
      ]
          .map((String value) {
        return value.trim().toLowerCase();
      })
          .toList(growable: false);

      return searchable.any((String value) => value.contains(normalized)) ||
          username.contains(usernameQuery);
    })
        .toList(growable: false);
  }

  Future<void> _searchRemote(String query) async {
    final String normalized = query.trim();

    if (normalized.isEmpty) {
      return;
    }

    final int generation = ++_generation;

    if (mounted) {
      setState(() {
        _activeQuery = normalized;
        _searching = true;
        _loadingMore = false;
        _error = null;
        _remoteResults = <DiscoveryUser>[];
        _cursor = null;
        _hasMore = false;
      });
    }

    try {
      final DiscoveryPage page = await _discovery.search(
        normalized,
        type: DiscoverySearchType.automatic,
        limit: _pageSize,
        excludeCurrentUser: _authenticated,
      );

      if (!_validSearch(generation, normalized)) {
        return;
      }

      setState(() {
        _remoteResults = List<DiscoveryUser>.unmodifiable(
          _uniqueUsers(page.users),
        );

        _cursor = page.nextCursor;

        _hasMore = page.hasMore && page.nextCursor != null;

        _searching = false;
      });
    } catch (error) {
      if (!_validSearch(generation, normalized)) {
        return;
      }

      setState(() {
        _searching = false;
        _loadingMore = false;
        _hasMore = false;
        _cursor = null;
        _error = _friendlySearchError(error);
      });
    }
  }

  bool _validSearch(int generation, String query) {
    return mounted && generation == _generation && _search.text.trim() == query;
  }

  // =============================================================
  // PAGINATION
  // =============================================================

  Future<void> _loadMore() async {
    if (_searching ||
        _loadingMore ||
        !_hasMore ||
        _cursor == null ||
        _activeQuery.isEmpty) {
      return;
    }

    final String query = _activeQuery;

    final int generation = _generation;

    final DocumentSnapshot<Map<String, dynamic>> cursor = _cursor!;

    setState(() {
      _loadingMore = true;
    });

    try {
      final DiscoveryPage page = await _discovery.search(
        query,
        type: DiscoverySearchType.automatic,
        limit: _pageSize,
        cursor: cursor,
        excludeCurrentUser: _authenticated,
      );

      if (!_validSearch(generation, query)) {
        return;
      }

      setState(() {
        _remoteResults = List<DiscoveryUser>.unmodifiable(
          _uniqueUsers(<DiscoveryUser>[
            ..._remoteResults,
            ...page.users,
          ]),
        );

        _cursor = page.nextCursor;

        _hasMore = page.hasMore && page.nextCursor != null;

        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }

      setState(() {
        _loadingMore = false;
        _error = _friendlySearchError(error);
      });
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }

    if (_scroll.position.extentAfter <= 280) {
      unawaited(_loadMore());
    }
  }

  // =============================================================
  // RESET / RETRY
  // =============================================================

  void _resetSearch() {
    _timer?.cancel();

    _generation++;

    if (!mounted) {
      return;
    }

    setState(() {
      _activeQuery = '';
      _searching = false;
      _loadingMore = false;
      _hasMore = false;
      _cursor = null;
      _error = null;
      _remoteResults = <DiscoveryUser>[];
      _localResults = List<ContactModel>.of(_contacts);
    });
  }

  void _clearSearch() {
    if (_search.text.isEmpty) {
      return;
    }

    _search.clear();
    _searchFocus.requestFocus();
  }

  Future<void> _retrySearch() async {
    final String query = _search.text.trim();

    if (query.isNotEmpty) {
      await _searchRemote(query);
    }
  }

  List<DiscoveryUser> _uniqueUsers(Iterable<DiscoveryUser> users) {
    final Map<String, DiscoveryUser> unique = <String, DiscoveryUser>{};

    for (final DiscoveryUser user in users) {
      final String uid = user.uid.trim();

      if (uid.isNotEmpty) {
        unique[uid] = user;
      }
    }

    return unique.values.toList(growable: false);
  }

  // =============================================================
  // DISCOVERY -> CONTACT
  // =============================================================

  ContactModel _toContact(DiscoveryUser user) {
    final String uid = user.uid.trim();

    final DateTime now = DateTime.now();

    return ContactModel(
      id: uid,
      userId: uid,
      linkedUid: uid,
      jrCallUserId: _nonEmpty(user.jrCallUserId),
      username: _usernameForContact(user.username),
      registeredState: ContactRegisteredState.registered,
      name: _safeName(user.displayName),
      phoneNumber: user.phoneNumber ?? '',
      email: user.email ?? '',
      photoUrl: user.profilePhotoUrl ?? '',
      countryCode: user.countryCode ?? '',
      country: user.country ?? '',
      bio: user.bio ?? '',
      isFavorite: false,
      isBlocked: false,
      isVerified: user.verified,
      status: user.online ? ContactStatus.online : ContactStatus.offline,
      lastSeen: now,
      createdAt: now,
    );
  }

  // =============================================================
  // PROFILE
  // =============================================================

  Future<void> _openProfile(ContactModel contact) async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return ProfileScreen(
            contact: contact,
            onVoiceCall: () {
              unawaited(_startVoice(contact));
            },
            onVideoCall: () {
              unawaited(_startVideo(contact));
            },
            onMessage: () {
              unawaited(_message(contact));
            },
          );
        },
      ),
    );
  }

  Future<void> _openDiscoveryProfile(DiscoveryUser user) {
    return _openProfile(_toContact(user));
  }

  // =============================================================
  // CALL TARGET
  // =============================================================

  String? _resolvedTargetUid(ContactModel contact) {
    final String value = contact.resolvedUid?.trim() ?? '';

    return value.isEmpty ? null : value;
  }

  // =============================================================
  // REAL OUTGOING CALL
  // =============================================================

  Future<void> _startCall(
      ContactModel contact, {
        required bool video,
      }) async {
    if (_startingCall) {
      return;
    }

    final bool authenticated = await _requireAuthentication(
      video ? 'start a video call' : 'start a voice call',
    );

    if (!authenticated || !mounted) {
      return;
    }

    final String? callerUid = _currentUid;
    final String? receiverUid = _resolvedTargetUid(contact);

    if (callerUid == null) {
      _showMessage(
        'Your authenticated JR CALL session is unavailable.',
      );
      return;
    }

    if (receiverUid == null) {
      _showMessage(
        'This JR CALL user could not be resolved for calling.',
      );
      return;
    }

    if (callerUid == receiverUid) {
      _showMessage(
        'You cannot call your own JR CALL account.',
      );
      return;
    }

    if (_callService.isCallActive) {
      _showMessage(
        'Another JR CALL call is already active.',
      );
      return;
    }

    setState(() {
      _startingCall = true;
    });

    String? callId;

    try {
      callId = await _callService.startCall(
        callerId: callerUid,
        receiverId: receiverUid,
        isVideoCall: video,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL [Contacts/startCall] $error',
      );

      debugPrintStack(
        label: 'JR CALL [Contacts/startCall]',
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() {
          _startingCall = false;
        });
      }
    }

    if (!mounted) {
      return;
    }

    if (callId == null || callId.trim().isEmpty) {
      _showMessage(
        video
            ? 'Video call could not be started.'
            : 'Voice call could not be started.',
      );

      return;
    }

    final String normalizedCallId = callId.trim();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          return OutgoingCallScreen(
            callerName: _safeName(contact.displayName),
            callerImage: _nonEmpty(contact.photoUrl),
            isVideoCall: video,
            statusStream: _callService.callStatusStream,
            durationStream: _callService.callDurationStream,
            initialStatus: CallServiceStatus.calling,
            onEndCall: () async {
              if (_callService.currentCallId == normalizedCallId) {
                await _callService.cancelCall(
                  callId: normalizedCallId,
                );
              }
            },
          );
        },
      ),
    );
  }

  // =============================================================
  // VOICE
  // =============================================================

  Future<void> _startVoice(ContactModel contact) {
    return _startCall(
      contact,
      video: false,
    );
  }

  Future<void> _startDiscoveryVoice(DiscoveryUser user) {
    return _startVoice(
      _toContact(user),
    );
  }

  // =============================================================
  // VIDEO
  // =============================================================

  Future<void> _startVideo(ContactModel contact) {
    return _startCall(
      contact,
      video: true,
    );
  }

  Future<void> _startDiscoveryVideo(DiscoveryUser user) {
    return _startVideo(
      _toContact(user),
    );
  }

  // =============================================================
  // MESSAGE
  // =============================================================

  Future<void> _message(ContactModel contact) async {
    if (!await _requireAuthentication('send messages')) {
      return;
    }

    if (!mounted) {
      return;
    }

    final String? receiverUid = _resolvedTargetUid(contact);

    if (receiverUid == null) {
      _showMessage(
        'This JR CALL user could not be resolved for messaging.',
      );

      return;
    }

    _showMessage(
      'Messaging will be activated in the Messaging phase.',
    );
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = _search.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: JrColors.background,
      appBar: _appBar(),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _maxWidth,
            ),
            child: Column(
              children: <Widget>[
                _searchArea(),
                Expanded(
                  child: hasQuery
                      ? _discoveryBody()
                      : _contactsBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // APP BAR
  // =============================================================

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: JrColors.surface,
      foregroundColor: JrColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 18,
      title: const Row(
        children: <Widget>[
          _BrandLogo(),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'JR CALL',
                  style: TextStyle(
                    color: JrColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Find People',
                  style: TextStyle(
                    color: JrColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // SEARCH UI
  // =============================================================

  Widget _searchArea() {
    return Container(
      color: JrColors.surface,
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16,
      ),
      child: TextField(
        controller: _search,
        focusNode: _searchFocus,

        // -------------------------------------------------------
        // JR CALL PUBLIC DISCOVERY SEARCH
        //
        // This field is NOT a credential field.
        // Do not expose it to Android/Web autofill services.
        // -------------------------------------------------------
        autofillHints: null,

        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.search,
        textCapitalization: TextCapitalization.none,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,

        style: const TextStyle(
          color: JrColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText:
          'Name, Username, JR CALL ID, Email or Phone',
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: JrColors.primaryBlue,
          ),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
            tooltip: 'Clear search',
            onPressed: _clearSearch,
            icon: const Icon(
              Icons.close_rounded,
            ),
          ),
          filled: true,
          fillColor: const Color(0xFFF8FAFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(19),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(19),
            borderSide: const BorderSide(
              color: JrColors.border,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(19),
            borderSide: const BorderSide(
              color: JrColors.primaryBlue,
              width: 1.35,
            ),
          ),
        ),
        onSubmitted: (String value) {
          _timer?.cancel();

          final String query = value.trim();

          if (query.isNotEmpty) {
            unawaited(
              _searchRemote(query),
            );
          }
        },
      ),
    );
  }

  // =============================================================
  // LOCAL CONTACTS
  // =============================================================

  Widget _contactsBody() {
    if (_contacts.isEmpty) {
      return _emptyState(
        Icons.person_search_rounded,
        'Find people',
        'Search by Name, Username, JR CALL ID, Email or Phone.',
      );
    }

    return _contactList(_localResults);
  }

  Widget _contactList(List<ContactModel> contacts) {
    return ListView.separated(
      controller: _scroll,
      keyboardDismissBehavior:
      ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        14,
        14,
        14,
        28,
      ),
      itemCount: contacts.length,
      separatorBuilder: (_, _) {
        return const SizedBox(height: 10);
      },
      itemBuilder: (_, int index) {
        return _localCard(
          contacts[index],
        );
      },
    );
  }

  // =============================================================
  // DISCOVERY RESULTS
  // =============================================================

  Widget _discoveryBody() {
    if (_searching && _remoteResults.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null && _remoteResults.isEmpty) {
      return _errorState();
    }

    if (_remoteResults.isEmpty) {
      if (_localResults.isNotEmpty) {
        return _contactList(
          _localResults,
        );
      }

      return _emptyState(
        Icons.person_search_rounded,
        'No matching people',
        'Try another Name, Username, JR CALL ID, Email or Phone.',
      );
    }

    return RefreshIndicator(
      onRefresh: () {
        return _searchRemote(
          _search.text.trim(),
        );
      },
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior:
        ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          14,
          14,
          14,
          28,
        ),
        itemCount:
        _remoteResults.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) {
          return const SizedBox(height: 10);
        },
        itemBuilder: (_, int index) {
          if (index >= _remoteResults.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          return _discoveryCard(
            _remoteResults[index],
          );
        },
      ),
    );
  }

  // =============================================================
  // DISCOVERY CARD
  // =============================================================

  Widget _discoveryCard(DiscoveryUser user) {
    final String name = _safeName(
      user.displayName,
    );

    return _PremiumContactCard(
      onTap: () {
        unawaited(
          _openDiscoveryProfile(user),
        );
      },
      avatar: CallerAvatar(
        name: name,
        imageUrl: _nonEmpty(
          user.profilePhotoUrl,
        ),
        radius: 25,
        isOnline: user.online,
      ),
      title: name,
      subtitle: _discoverySubtitle(user),
      verified: user.verified,
      actions: <Widget>[
        _VoiceButton(
          enabled: !_startingCall,
          onPressed: () {
            unawaited(
              _startDiscoveryVoice(user),
            );
          },
        ),
        const SizedBox(width: 7),
        VideoButton(
          size: 42,
          tooltip: 'Video call',
          onPressed: _startingCall
              ? null
              : () {
            unawaited(
              _startDiscoveryVideo(user),
            );
          },
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(
            Icons.more_vert_rounded,
            color: JrColors.textSecondary,
          ),
          onSelected: (String value) {
            switch (value) {
              case 'profile':
                unawaited(
                  _openDiscoveryProfile(user),
                );
                break;

              case 'message':
                unawaited(
                  _message(
                    _toContact(user),
                  ),
                );
                break;
            }
          },
          itemBuilder: (_) {
            return const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'profile',
                child: Text(
                  'View profile',
                ),
              ),
              PopupMenuItem<String>(
                value: 'message',
                child: Text(
                  'Message',
                ),
              ),
            ];
          },
        ),
      ],
    );
  }

  // =============================================================
  // LOCAL CARD
  // =============================================================

  Widget _localCard(ContactModel contact) {
    final String name = _safeName(
      contact.displayName,
    );

    return _PremiumContactCard(
      onTap: () {
        unawaited(
          _openProfile(contact),
        );
      },
      avatar: CallerAvatar(
        name: name,
        imageUrl: _nonEmpty(
          contact.photoUrl,
        ),
        radius: 25,
        isOnline: contact.isOnline,
      ),
      title: name,
      subtitle: _localSubtitle(contact),
      verified: contact.isVerified,
      actions: <Widget>[
        _VoiceButton(
          enabled: !_startingCall,
          onPressed: () {
            unawaited(
              _startVoice(contact),
            );
          },
        ),
        const SizedBox(width: 7),
        VideoButton(
          size: 42,
          tooltip: 'Video call',
          onPressed: _startingCall
              ? null
              : () {
            unawaited(
              _startVideo(contact),
            );
          },
        ),
      ],
    );
  }

  // =============================================================
  // SUBTITLES
  // =============================================================

  String _discoverySubtitle(
      DiscoveryUser user,
      ) {
    final List<String> values = <String>[];

    _addIfNotEmpty(
      values,
      user.usernameLabel,
    );

    _addIfNotEmpty(
      values,
      user.jrCallUserId,
    );

    if (values.isEmpty) {
      _addIfNotEmpty(
        values,
        user.email,
      );
    }

    if (values.isEmpty) {
      _addIfNotEmpty(
        values,
        user.phoneNumber,
      );
    }

    return values.isEmpty
        ? 'JR CALL user'
        : values.join('  •  ');
  }

  String _localSubtitle(
      ContactModel contact,
      ) {
    final List<String> values = <String>[];

    _addIfNotEmpty(
      values,
      contact.usernameLabel,
    );

    _addIfNotEmpty(
      values,
      contact.jrCallUserId,
    );

    if (values.isEmpty) {
      _addIfNotEmpty(
        values,
        contact.phoneNumber,
      );
    }

    if (values.isEmpty) {
      _addIfNotEmpty(
        values,
        contact.email,
      );
    }

    if (values.isEmpty) {
      return contact.isRegistered
          ? 'JR CALL user'
          : 'Contact';
    }

    return values.join('  •  ');
  }

  void _addIfNotEmpty(
      List<String> target,
      String? value,
      ) {
    final String? normalized = _nonEmpty(value);

    if (normalized != null) {
      target.add(normalized);
    }
  }

  // =============================================================
  // EMPTY / ERROR
  // =============================================================

  Widget _emptyState(
      IconData icon,
      String title,
      String message,
      ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _stateIcon(
              icon,
              JrColors.primaryBlue,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JrColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JrColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _stateIcon(
              Icons.cloud_off_rounded,
              JrColors.error,
            ),
            const SizedBox(height: 20),
            const Text(
              'Search unavailable',
              style: TextStyle(
                color: JrColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _error ??
                  'Unable to search JR CALL users.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JrColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _retrySearch,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text(
                'Try again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stateIcon(
      IconData icon,
      Color color,
      ) {
    return Container(
      width: 86,
      height: 86,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(
          alpha: 0.07,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.11,
          ),
        ),
      ),
      child: Icon(
        icon,
        size: 38,
        color: color,
      ),
    );
  }

  // =============================================================
  // HELPERS
  // =============================================================

  String _safeName(String value) {
    final String normalized = value.trim();

    return normalized.isEmpty
        ? 'JR CALL User'
        : normalized;
  }

  String? _nonEmpty(String? value) {
    final String normalized =
        value?.trim() ?? '';

    return normalized.isEmpty
        ? null
        : normalized;
  }

  String? _usernameForContact(
      String? value,
      ) {
    String normalized =
        value?.trim() ?? '';

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    normalized = normalized.trim();

    return normalized.isEmpty
        ? null
        : normalized;
  }

  String _friendlySearchError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Search permission is currently unavailable.';

        case 'failed-precondition':
          return 'This search is not available yet.';

        case 'unavailable':
        case 'network-request-failed':
          return 'Check your Internet connection and try again.';

        case 'deadline-exceeded':
          return 'Search took too long. Try again.';
      }
    }

    return 'Unable to search JR CALL users right now.';
  }

  void _showMessage(String message) {
    if (!mounted || message.trim().isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

// ===============================================================
// CONTACT CARD
// ===============================================================

class _PremiumContactCard extends StatelessWidget {
  const _PremiumContactCard({
    required this.onTap,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.verified,
    required this.actions,
  });

  final VoidCallback onTap;
  final Widget avatar;
  final String title;
  final String subtitle;
  final bool verified;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(
            14,
            13,
            9,
            13,
          ),
          decoration: BoxDecoration(
            color: JrColors.surface.withValues(
              alpha: 0.96,
            ),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(
              color: JrColors.border,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: 0.035,
                ),
                blurRadius: 20,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              avatar,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow:
                            TextOverflow.ellipsis,
                            style: const TextStyle(
                              color:
                              JrColors.textPrimary,
                              fontSize: 15.5,
                              fontWeight:
                              FontWeight.w700,
                            ),
                          ),
                        ),
                        if (verified) ...<Widget>[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color:
                            JrColors.primaryBlue,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style: const TextStyle(
                        color:
                        JrColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// VOICE BUTTON
// ===============================================================

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.onPressed,
    this.enabled = true,
  });

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Voice call',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Voice call',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.45,
              duration: const Duration(
                milliseconds: 150,
              ),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: JrColors.callGreen.withValues(
                    alpha: 0.09,
                  ),
                  border: Border.all(
                    color:
                    JrColors.callGreen.withValues(
                      alpha: 0.18,
                    ),
                  ),
                ),
                child: const Icon(
                  Icons.call_rounded,
                  color: JrColors.callGreen,
                  size: 21,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// BRAND LOGO
// ===============================================================

class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.contain,
          errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stackTrace,
              ) {
            return const Center(
              child: Icon(
                Icons.call_rounded,
                color: JrColors.primaryBlue,
                size: 24,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ===============================================================
// END OF FILE
//
// FIXED:
// BUG 03 — Discovery result uses resolved Firebase UID
// BUG 05 — Public search removed from autofill/password-manager
// BUG 07 — Voice call starts through CallService
// BUG 08 — Video call starts through CallService
//
// PRESERVED:
// - Existing ContactsScreen API
// - Existing UI/colors/layout
// - UserDiscoveryService automatic search
// - Name / Username / JR CALL ID / Email / Phone search
// - Firebase UID handoff
// - Public profile navigation
// - CallService ownership
// - OutgoingCallScreen flow
//
// STATUS: SAVE THIS FILE
//
// REMAINING MAIN FILE: 1
//
// NEXT FILE: call_service.dart
// Location: lib/services/call/call_service.dart
// ===============================================================