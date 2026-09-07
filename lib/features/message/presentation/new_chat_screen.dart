// ============================================================================
// JR CALL
// File: new_chat_screen.dart
// Location: lib/features/message/presentation/new_chat_screen.dart
// Description:
// Starts a new JR CALL conversation using the existing discovery pipeline.
// This screen never treats username/public ID/email/phone as internal identity.
// The selected discovery result must already contain the canonical Firebase UID.
// Conversation creation/opening is delegated through the supplied repository
// binding so this presentation file never talks directly to Firestore.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef NewChatSearchCallback =
    Future<List<NewChatUser>> Function(String query);

typedef NewChatOpenConversationCallback =
    Future<void> Function(String firebaseUid);

typedef NewChatAuthenticationRequiredCallback = FutureOr<void> Function();

@immutable
final class NewChatUser {
  const NewChatUser({
    required this.uid,
    required this.displayName,
    this.username,
    this.publicId,
    this.email,
    this.phone,
    this.avatarUrl,
    this.isVerified = false,
    this.isOnline = false,
  });

  /// Canonical Firebase Auth UID.
  ///
  /// This is the only identity allowed to be forwarded into
  /// ConversationRepository for direct-conversation ownership.
  final String uid;

  final String displayName;
  final String? username;
  final String? publicId;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final bool isVerified;
  final bool isOnline;

  bool get hasValidUid => uid.trim().isNotEmpty;
}

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({
    super.key,
    required this.isAuthenticated,
    required this.currentUserUid,
    required this.onSearch,
    required this.onOpenConversation,
    required this.onAuthenticationRequired,
  });

  final bool isAuthenticated;

  /// Canonical Firebase Auth UID of the signed-in user.
  final String currentUserUid;

  /// Must delegate to the existing UserDiscoveryService.
  ///
  /// Search may resolve:
  /// - name
  /// - username
  /// - JR CALL public ID
  /// - email
  /// - phone
  ///
  /// Returned [NewChatUser.uid] must be the canonical Firebase UID.
  final NewChatSearchCallback onSearch;

  /// Must delegate to ConversationRepository find/create direct conversation
  /// using the canonical Firebase UID.
  final NewChatOpenConversationCallback onOpenConversation;

  final NewChatAuthenticationRequiredCallback onAuthenticationRequired;

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  static const Duration _searchDebounce = Duration(milliseconds: 350);
  static const int _minimumQueryLength = 2;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounceTimer;

  List<NewChatUser> _results = const <NewChatUser>[];

  bool _isSearching = false;
  bool _isOpeningConversation = false;

  String? _openingUid;
  String? _errorMessage;

  int _searchGeneration = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isAuthenticated) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant NewChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isAuthenticated != widget.isAuthenticated &&
        widget.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }

    if (oldWidget.currentUserUid != widget.currentUserUid) {
      _resetSearchState();
    }
  }

  @override
  void dispose() {
    _disposed = true;

    _debounceTimer?.cancel();
    _debounceTimer = null;

    _searchController.dispose();
    _searchFocusNode.dispose();

    super.dispose();
  }

  void _resetSearchState() {
    _debounceTimer?.cancel();
    _searchGeneration++;

    _searchController.clear();

    if (!mounted) {
      return;
    }

    setState(() {
      _results = const <NewChatUser>[];
      _isSearching = false;
      _errorMessage = null;
      _openingUid = null;
      _isOpeningConversation = false;
    });
  }

  void _handleQueryChanged(String rawValue) {
    _debounceTimer?.cancel();

    final String query = _normalizeQuery(rawValue);

    _searchGeneration++;
    final int generation = _searchGeneration;

    if (query.length < _minimumQueryLength) {
      if (mounted) {
        setState(() {
          _results = const <NewChatUser>[];
          _isSearching = false;
          _errorMessage = null;
        });
      }
      return;
    }

    if (!widget.isAuthenticated) {
      if (mounted) {
        setState(() {
          _results = const <NewChatUser>[];
          _isSearching = false;
          _errorMessage = null;
        });
      }
      return;
    }

    _debounceTimer = Timer(_searchDebounce, () {
      unawaited(_performSearch(query: query, generation: generation));
    });
  }

  Future<void> _performSearch({
    required String query,
    required int generation,
  }) async {
    if (_disposed || !widget.isAuthenticated) {
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final List<NewChatUser> discovered = await widget.onSearch(query);

      if (_disposed ||
          !mounted ||
          generation != _searchGeneration ||
          query != _normalizeQuery(_searchController.text)) {
        return;
      }

      final String currentUid = widget.currentUserUid.trim();

      final Map<String, NewChatUser> uniqueByUid = <String, NewChatUser>{};

      for (final NewChatUser user in discovered) {
        final String uid = user.uid.trim();

        if (uid.isEmpty || uid == currentUid) {
          continue;
        }

        uniqueByUid.putIfAbsent(uid, () => user);
      }

      final List<NewChatUser> sanitized = uniqueByUid.values.toList(
        growable: false,
      )..sort(_compareUsers);

      setState(() {
        _results = List<NewChatUser>.unmodifiable(sanitized);
        _isSearching = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (_disposed || !mounted || generation != _searchGeneration) {
        return;
      }

      setState(() {
        _results = const <NewChatUser>[];
        _isSearching = false;
        _errorMessage =
            'Unable to search right now. Check your connection and try again.';
      });
    }
  }

  Future<void> _openUser(NewChatUser user) async {
    if (_isOpeningConversation) {
      return;
    }

    if (!widget.isAuthenticated) {
      await _requireAuthentication();
      return;
    }

    final String canonicalUid = user.uid.trim();

    if (canonicalUid.isEmpty) {
      _showSafeMessage('This account cannot be opened right now.');
      return;
    }

    if (canonicalUid == widget.currentUserUid.trim()) {
      _showSafeMessage(
        'You cannot start a conversation with your own account.',
      );
      return;
    }

    setState(() {
      _isOpeningConversation = true;
      _openingUid = canonicalUid;
      _errorMessage = null;
    });

    try {
      await widget.onOpenConversation(canonicalUid);

      if (_disposed || !mounted) {
        return;
      }

      setState(() {
        _isOpeningConversation = false;
        _openingUid = null;
      });
    } catch (_) {
      if (_disposed || !mounted) {
        return;
      }

      setState(() {
        _isOpeningConversation = false;
        _openingUid = null;
      });

      _showSafeMessage('Unable to open this conversation right now.');
    }
  }

  /// Normalizes a synchronous or asynchronous authentication callback into
  /// `Future<void>`, allowing it to be safely awaited or passed to unawaited().
  Future<void> _requireAuthentication() async {
    await widget.onAuthenticationRequired();
  }

  void _showSafeMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _searchGeneration++;

    _searchController.clear();

    setState(() {
      _results = const <NewChatUser>[];
      _isSearching = false;
      _errorMessage = null;
    });

    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FF),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFFDFDFF),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            Navigator.of(context).maybePop();
          },
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Color(0xFF30384C),
          ),
        ),
        titleSpacing: 2,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'New Message',
              style: TextStyle(
                color: Color(0xFF151D31),
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 1),
            Text(
              'Find people on JR CALL',
              style: TextStyle(
                color: Color(0xFF8A92A5),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE9ECF4)),
        ),
      ),
      body: widget.isAuthenticated
          ? _buildAuthenticatedBody()
          : _buildGuestBody(),
    );
  }

  Widget _buildAuthenticatedBody() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: _buildSearchField(),
        ),
        Expanded(child: _buildSearchContent()),
      ],
    );
  }

  Widget _buildSearchField() {
    final bool hasText = _searchController.text.trim().isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E8F2)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F2C3960),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.search,
        autofillHints: null,
        enableSuggestions: false,
        autocorrect: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        inputFormatters: <TextInputFormatter>[
          LengthLimitingTextInputFormatter(160),
        ],
        onChanged: (String value) {
          setState(() {});
          _handleQueryChanged(value);
        },
        onSubmitted: (String value) {
          _debounceTimer?.cancel();

          final String query = _normalizeQuery(value);

          if (query.length < _minimumQueryLength) {
            return;
          }

          _searchGeneration++;
          final int generation = _searchGeneration;

          unawaited(_performSearch(query: query, generation: generation));
        },
        decoration: InputDecoration(
          hintText: 'Name, username, JR ID, email or phone',
          hintStyle: const TextStyle(color: Color(0xFF9AA1B3), fontSize: 13.5),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF7166E9),
          ),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: 'Clear',
                  onPressed: _clearSearch,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Color(0xFF8A91A4),
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchContent() {
    final String query = _normalizeQuery(_searchController.text);

    if (_isSearching) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.8,
            color: Color(0xFF6654E8),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return _SearchMessageView(
        icon: Icons.cloud_off_rounded,
        title: 'Search unavailable',
        message: _errorMessage!,
      );
    }

    if (query.length < _minimumQueryLength) {
      return const _SearchMessageView(
        icon: Icons.person_search_rounded,
        title: 'Find someone',
        message: 'Search by name, username, JR CALL ID, email or phone number.',
      );
    }

    if (_results.isEmpty) {
      return const _SearchMessageView(
        icon: Icons.search_off_rounded,
        title: 'No account found',
        message:
            'Try another name, username, JR CALL ID, email or phone number.',
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: _results.length,
      separatorBuilder: (BuildContext context, int index) {
        return const SizedBox(height: 8);
      },
      itemBuilder: (BuildContext context, int index) {
        final NewChatUser user = _results[index];

        return _NewChatUserTile(
          user: user,
          isOpening: _isOpeningConversation && _openingUid == user.uid.trim(),
          disabled: _isOpeningConversation,
          onTap: () {
            unawaited(_openUser(user));
          },
        );
      },
    );
  }

  Widget _buildGuestBody() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7EAF2)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x12293760),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFF557DFF),
                      Color(0xFF7558F5),
                      Color(0xFFE052AB),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Sign in to start messaging',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF172036),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'JR CALL messaging uses your authenticated account so every conversation stays connected to the correct Firebase identity.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF7D869A),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    unawaited(_requireAuthentication());
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5E4CF5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'Login / Create Account',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _normalizeQuery(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static int _compareUsers(NewChatUser first, NewChatUser second) {
    if (first.isOnline != second.isOnline) {
      return first.isOnline ? -1 : 1;
    }

    if (first.isVerified != second.isVerified) {
      return first.isVerified ? -1 : 1;
    }

    return first.displayName.trim().toLowerCase().compareTo(
      second.displayName.trim().toLowerCase(),
    );
  }
}

class _NewChatUserTile extends StatelessWidget {
  const _NewChatUserTile({
    required this.user,
    required this.isOpening,
    required this.disabled,
    required this.onTap,
  });

  final NewChatUser user;
  final bool isOpening;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String title = _displayName(user);
    final String? subtitle = _subtitle(user);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7EAF2)),
          ),
          child: Row(
            children: <Widget>[
              _DiscoveryAvatar(
                displayName: title,
                avatarUrl: user.avatarUrl,
                isOnline: user.isOnline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF172036),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (user.isVerified) ...<Widget>[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: Color(0xFF4385F5),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7F879A),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isOpening)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    color: Color(0xFF6654E8),
                  ),
                )
              else
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F0FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    size: 19,
                    color: Color(0xFF6654E8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _displayName(NewChatUser user) {
    final String value = user.displayName.trim();

    if (value.isNotEmpty) {
      return value;
    }

    final String username = user.username?.trim() ?? '';

    if (username.isNotEmpty) {
      return '@$username';
    }

    final String publicId = user.publicId?.trim() ?? '';

    if (publicId.isNotEmpty) {
      return publicId;
    }

    return 'JR CALL User';
  }

  static String? _subtitle(NewChatUser user) {
    final String username = user.username?.trim() ?? '';

    if (username.isNotEmpty) {
      return username.startsWith('@') ? username : '@$username';
    }

    final String publicId = user.publicId?.trim() ?? '';

    if (publicId.isNotEmpty) {
      return 'JR ID: $publicId';
    }

    final String email = user.email?.trim() ?? '';

    if (email.isNotEmpty) {
      return email;
    }

    final String phone = user.phone?.trim() ?? '';

    if (phone.isNotEmpty) {
      return phone;
    }

    return null;
  }
}

class _DiscoveryAvatar extends StatelessWidget {
  const _DiscoveryAvatar({
    required this.displayName,
    required this.avatarUrl,
    required this.isOnline,
  });

  final String displayName;
  final String? avatarUrl;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final String? safeUrl = _safeUrl(avatarUrl);

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: 50,
          height: 50,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFFE5EDFF), Color(0xFFF8E7F6)],
            ),
          ),
          child: safeUrl == null
              ? Center(
                  child: Text(
                    _initials(displayName),
                    style: const TextStyle(
                      color: Color(0xFF6257BB),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                )
              : Image.network(
                  safeUrl,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                      ) {
                        return Center(
                          child: Text(
                            _initials(displayName),
                            style: const TextStyle(
                              color: Color(0xFF6257BB),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
                ),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF36C477),
                border: Border.all(color: Colors.white, width: 2.5),
              ),
            ),
          ),
      ],
    );
  }

  static String? _safeUrl(String? value) {
    final String raw = value?.trim() ?? '';

    if (raw.isEmpty) {
      return null;
    }

    final Uri? uri = Uri.tryParse(raw);

    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }

    return raw;
  }

  static String _initials(String value) {
    final List<String> words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .toList(growable: false);

    if (words.isEmpty) {
      return 'JR';
    }

    if (words.length == 1) {
      final String word = words.first;

      return word.substring(0, word.length > 1 ? 2 : 1).toUpperCase();
    }

    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}

class _SearchMessageView extends StatelessWidget {
  const _SearchMessageView({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 70,
              height: 70,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF0EEFF),
              ),
              child: Icon(icon, size: 32, color: const Color(0xFF6A5BE7)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF192137),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF838B9D),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// END OF FILE: lib/features/message/presentation/new_chat_screen.dart
// ============================================================================
