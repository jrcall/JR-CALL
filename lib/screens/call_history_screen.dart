import 'dart:async';

import 'package:flutter/material.dart';

import '../models/call_history_model.dart';
import '../providers/call_history_provider.dart';
import '../widgets/caller_avatar.dart';
import 'contacts_screen.dart';

/// ===============================================================
/// JR CALL
/// File: call_history_screen.dart
/// Location: lib/screens/call_history_screen.dart
///
/// Production call-history presentation screen.
///
/// Ownership:
///
/// CallHistoryProvider:
/// - Call-history source of truth.
/// - History loading.
/// - History refresh.
/// - History error state.
///
/// CallHistoryScreen:
/// - History presentation.
/// - Local history search/filter.
/// - Newest-first presentation ordering.
/// - Voice/video callback forwarding.
/// - Contacts navigation.
/// - Refresh presentation.
///
/// This screen does NOT:
/// - Create call-history records.
/// - Mutate call-history records.
/// - Persist call-history records.
/// - Own CallService lifecycle.
/// - Own Firestore signaling.
/// - Own WebRTC.
/// - Own ICE.
/// - Own recovery.
/// - Own call duration.
/// - Invent call-history states.
///
/// Finalized history enum contract:
///
/// CallType:
/// - voice
/// - video
///
/// CallDirection:
/// - incoming
/// - outgoing
///
/// CallStatus:
/// - missed
/// - rejected
/// - cancelled
/// - completed
/// - failed
/// - busy
/// - declined
/// ===============================================================

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({
    super.key,
    required this.historyProvider,
    this.onCallTap,
    this.onVoiceCall,
    this.onVideoCall,
    this.onRefresh,
  });

  final CallHistoryProvider historyProvider;

  final ValueChanged<CallHistoryModel>? onCallTap;

  final ValueChanged<CallHistoryModel>? onVoiceCall;

  final ValueChanged<CallHistoryModel>? onVideoCall;

  final Future<void> Function()? onRefresh;

  @override
  State<CallHistoryScreen> createState() =>
      _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  // =============================================================
  // Design
  // =============================================================

  static const Color _background = Color(0xFFF8FAFE);

  static const Color _surface = Colors.white;

  static const Color _blue = Color(0xFF087AF5);

  static const Color _green = Color(0xFF00C782);

  static const Color _red = Color(0xFFFF163D);

  static const Color _purple = Color(0xFF8B39F7);

  static const Color _orange = Color(0xFFFF9F0A);

  static const Color _text = Color(0xFF101828);

  static const Color _muted = Color(0xFF51617C);

  static const Color _border = Color(0xFFE4EAF3);

  // =============================================================
  // Limits / Guards
  // =============================================================

  static const Duration _callActionLockDuration = Duration(
    milliseconds: 650,
  );

  // =============================================================
  // Search
  // =============================================================

  final TextEditingController _searchController =
  TextEditingController();

  final FocusNode _searchFocusNode = FocusNode();

  String _query = '';

  bool _searchVisible = false;

  // =============================================================
  // Operation Guards
  // =============================================================

  Future<void>? _refreshFuture;

  bool _contactsRouteOpen = false;

  bool _callSheetVisible = false;

  bool _callActionLocked = false;

  Timer? _callActionUnlockTimer;

  // =============================================================
  // Lifecycle
  // =============================================================

  @override
  void dispose() {
    _callActionUnlockTimer?.cancel();
    _callActionUnlockTimer = null;

    _searchController.dispose();
    _searchFocusNode.dispose();

    super.dispose();
  }

  // =============================================================
  // Refresh
  // =============================================================

  Future<void> _refresh() async {
    final Future<void>? active = _refreshFuture;

    if (active != null) {
      await active;
      return;
    }

    final Future<void> operation = _runRefreshOperation();

    _refreshFuture = operation;

    try {
      await operation;
    } finally {
      if (identical(
        _refreshFuture,
        operation,
      )) {
        _refreshFuture = null;
      }
    }
  }

  Future<void> _runRefreshOperation() async {
    try {
      await _performRefresh();
    } catch (error, stackTrace) {
      _reportError(
        'Refresh call history',
        error,
        stackTrace,
      );

      if (mounted) {
        _showMessage(
          'Unable to refresh call history.',
        );
      }
    }
  }

  Future<void> _performRefresh() async {
    final Future<void> Function()? callback =
        widget.onRefresh;

    if (callback != null) {
      await callback();
      return;
    }

    await widget.historyProvider.refresh();
  }

  // =============================================================
  // Visible History
  // =============================================================

  List<CallHistoryModel> _visibleHistory(
      List<CallHistoryModel> source,
      ) {
    final String query = _query.trim().toLowerCase();

    final List<CallHistoryModel> result = source
        .where(
          (CallHistoryModel call) {
        if (query.isEmpty) {
          return true;
        }

        final String contactName =
        call.contactName.trim().toLowerCase();

        final String phoneNumber =
        call.phoneNumber.trim().toLowerCase();

        return contactName.contains(query) ||
            phoneNumber.contains(query);
      },
    )
        .toList(
      growable: false,
    );

    result.sort(
          (
          CallHistoryModel first,
          CallHistoryModel second,
          ) {
        return second.startedAt.compareTo(
          first.startedAt,
        );
      },
    );

    return result;
  }

  // =============================================================
  // Search Actions
  // =============================================================

  void _openSearch() {
    if (!_searchVisible) {
      setState(() {
        _searchVisible = true;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback(
          (_) {
        if (!mounted) {
          return;
        }

        _searchFocusNode.requestFocus();
      },
    );
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();

    if (!_searchVisible && _query.isEmpty) {
      return;
    }

    setState(() {
      _query = '';
      _searchVisible = false;
    });
  }

  // =============================================================
  // Contacts
  // =============================================================

  Future<void> _openContacts() async {
    if (!mounted || _contactsRouteOpen) {
      return;
    }

    _contactsRouteOpen = true;

    final NavigatorState navigator = Navigator.of(context);

    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) {
            return const ContactsScreen();
          },
        ),
      );
    } catch (error, stackTrace) {
      _reportError(
        'Open contacts',
        error,
        stackTrace,
      );

      if (mounted) {
        _showMessage(
          'Unable to open contacts.',
        );
      }
    } finally {
      _contactsRouteOpen = false;
    }
  }

  // =============================================================
  // Call Actions
  // =============================================================

  void _openCall(
      CallHistoryModel call,
      ) {
    final ValueChanged<CallHistoryModel>? callback =
        widget.onCallTap;

    if (callback != null) {
      _invokeCallCallback(
        callback: callback,
        call: call,
        source: 'History item',
      );

      return;
    }

    unawaited(
      _showCallActions(
        call,
      ),
    );
  }

  Future<void> _showCallActions(
      CallHistoryModel call,
      ) async {
    if (!mounted || _callSheetVisible) {
      return;
    }

    final ValueChanged<CallHistoryModel>? voiceCallback =
        widget.onVoiceCall;

    final ValueChanged<CallHistoryModel>? videoCallback =
        widget.onVideoCall;

    final bool voiceAvailable = voiceCallback != null;

    final bool videoAvailable = videoCallback != null;

    if (!voiceAvailable && !videoAvailable) {
      final ValueChanged<CallHistoryModel>? fallback =
          widget.onCallTap;

      if (fallback != null) {
        _invokeCallCallback(
          callback: fallback,
          call: call,
          source: 'History fallback',
        );
      }

      return;
    }

    _callSheetVisible = true;

    final String name = _safeContactName(
      call,
    );

    final String phone = call.phoneNumber.trim();

    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (
            BuildContext sheetContext,
            ) {
          return Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(
              18,
              10,
              18,
              20,
            ),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(
                27,
              ),
              border: Border.all(
                color: _border,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x180F172A),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFD8E0EB,
                    ),
                    borderRadius: BorderRadius.circular(
                      99,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 18,
                ),

                CallerAvatar(
                  name: name,
                  imageUrl: _avatar(
                    call,
                  ),
                  radius: 34,
                  isOnline: false,
                ),

                const SizedBox(
                  height: 10,
                ),

                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                if (phone.isNotEmpty) ...<Widget>[
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                    ),
                  ),
                ],

                const SizedBox(
                  height: 18,
                ),

                Row(
                  children: <Widget>[
                    if (voiceAvailable)
                      Expanded(
                        child: _SheetButton(
                          icon: Icons.call_rounded,
                          label: 'Voice Call',
                          color: _green,
                          onTap: () {
                            Navigator.of(
                              sheetContext,
                            ).pop();

                            _invokeCallCallback(
                              callback: voiceCallback,
                              call: call,
                              source: 'Voice call',
                            );
                          },
                        ),
                      ),

                    if (voiceAvailable && videoAvailable)
                      const SizedBox(
                        width: 10,
                      ),

                    if (videoAvailable)
                      Expanded(
                        child: _SheetButton(
                          icon: Icons.videocam_rounded,
                          label: 'Video Call',
                          color: _purple,
                          onTap: () {
                            Navigator.of(
                              sheetContext,
                            ).pop();

                            _invokeCallCallback(
                              callback: videoCallback,
                              call: call,
                              source: 'Video call',
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } catch (error, stackTrace) {
      _reportError(
        'Show call actions',
        error,
        stackTrace,
      );

      if (mounted) {
        _showMessage(
          'Unable to open call actions.',
        );
      }
    } finally {
      _callSheetVisible = false;
    }
  }

  void _invokeCallCallback({
    required ValueChanged<CallHistoryModel> callback,
    required CallHistoryModel call,
    required String source,
  }) {
    if (_callActionLocked) {
      return;
    }

    _callActionLocked = true;

    _callActionUnlockTimer?.cancel();
    _callActionUnlockTimer = null;

    try {
      callback(
        call,
      );
    } catch (error, stackTrace) {
      _releaseCallActionLock();

      _reportError(
        source,
        error,
        stackTrace,
      );

      if (mounted) {
        _showMessage(
          'Unable to start this call action.',
        );
      }

      return;
    }

    _callActionUnlockTimer = Timer(
      _callActionLockDuration,
      _releaseCallActionLock,
    );
  }

  void _releaseCallActionLock() {
    _callActionUnlockTimer?.cancel();
    _callActionUnlockTimer = null;

    _callActionLocked = false;
  }

  // =============================================================
  // Safe Model Presentation
  // =============================================================

  String _safeContactName(
      CallHistoryModel call,
      ) {
    final String value = call.contactName.trim();

    return value.isEmpty
        ? 'Unknown caller'
        : value;
  }

  String? _avatar(
      CallHistoryModel call,
      ) {
    final String url = call.avatarUrl.trim();

    return url.isEmpty ? null : url;
  }

  // =============================================================
  // Build
  // =============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.historyProvider,
          builder: (
              BuildContext context,
              Widget? _,
              ) {
            final CallHistoryProvider provider =
                widget.historyProvider;

            final List<CallHistoryModel> history =
            _visibleHistory(
              provider.callHistory,
            );

            return RefreshIndicator(
              color: _blue,
              onRefresh: _refresh,
              child: CustomScrollView(
                physics:
                const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior
                    .onDrag,
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: _TopActions(
                      onSearch: _openSearch,
                      onContacts: () {
                        unawaited(
                          _openContacts(),
                        );
                      },
                      onAdd: () {
                        unawaited(
                          _openContacts(),
                        );
                      },
                    ),
                  ),

                  if (_searchVisible)
                    SliverPadding(
                      padding:
                      const EdgeInsets.fromLTRB(
                        18,
                        0,
                        18,
                        12,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _SearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: (
                              String value,
                              ) {
                            if (value == _query) {
                              return;
                            }

                            setState(() {
                              _query = value;
                            });
                          },
                          onClose: _closeSearch,
                        ),
                      ),
                    ),

                  if (provider.isLoading &&
                      provider.callHistory.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child:
                        CircularProgressIndicator(
                          color: _blue,
                        ),
                      ),
                    )
                  else if (provider.error != null &&
                      provider.callHistory.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _StatusView(
                        icon:
                        Icons.error_outline_rounded,
                        color: _red,
                        title:
                        'Unable to load call history',
                        subtitle:
                        'Please check your connection and try again.',
                        onRetry: _refresh,
                      ),
                    )
                  else if (history.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _StatusView(
                          icon: _query.trim().isEmpty
                              ? Icons.history_rounded
                              : Icons.search_off_rounded,
                          color: _blue,
                          title: _query.trim().isEmpty
                              ? 'No call history'
                              : 'No matching calls',
                          subtitle: _query.trim().isEmpty
                              ? 'Incoming, outgoing, missed and video calls will appear here.'
                              : 'Try another name or phone number.',
                        ),
                      )
                    else
                      SliverPadding(
                        padding:
                        const EdgeInsets.fromLTRB(
                          18,
                          2,
                          18,
                          28,
                        ),
                        sliver: SliverList.separated(
                          itemCount: history.length,
                          separatorBuilder: (
                              _,
                              _,
                              ) {
                            return const SizedBox(
                              height: 10,
                            );
                          },
                          itemBuilder: (
                              _,
                              int index,
                              ) {
                            final CallHistoryModel call =
                            history[index];

                            return _HistoryCard(
                              call: call,
                              onTap: () {
                                _openCall(
                                  call,
                                );
                              },
                              onCall: () {
                                unawaited(
                                  _showCallActions(
                                    call,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // =============================================================
  // Message / Error
  // =============================================================

  void _showMessage(
      String message,
      ) {
    if (!mounted || message.trim().isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            message,
          ),
        ),
      );
  }

  void _reportError(
      String source,
      Object error,
      StackTrace stackTrace,
      ) {
    debugPrint(
      'JR CALL '
          '[CallHistoryScreen/$source] '
          'error: $error',
    );

    debugPrintStack(
      label:
      'JR CALL '
          '[CallHistoryScreen/$source]',
      stackTrace: stackTrace,
    );
  }
}

// ===============================================================
// Top Actions
// ===============================================================

class _TopActions extends StatelessWidget {
  const _TopActions({
    required this.onSearch,
    required this.onContacts,
    required this.onAdd,
  });

  final VoidCallback onSearch;

  final VoidCallback onContacts;

  final VoidCallback onAdd;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        10,
        18,
        14,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          _TopButton(
            icon: Icons.search_rounded,
            label: 'Search',
            onTap: onSearch,
          ),

          const SizedBox(
            width: 10,
          ),

          _TopButton(
            icon: Icons.contact_page_outlined,
            label: 'Contacts',
            onTap: onContacts,
          ),

          const SizedBox(
            width: 10,
          ),

          _TopButton(
            icon: Icons.add_rounded,
            label: 'Add',
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;

  final String label;

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
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            16,
          ),
          child: Padding(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                    BorderRadius.circular(
                      14,
                    ),
                    border: Border.all(
                      color: const Color(
                        0xFFEDF1F7,
                      ),
                    ),
                    boxShadow:
                    const <BoxShadow>[
                      BoxShadow(
                        color:
                        Color(0x1017233B),
                        blurRadius: 12,
                        offset: Offset(
                          0,
                          4,
                        ),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: Colors.black,
                    size: 23,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color:
                    _CallHistoryScreenState
                        ._text,
                    fontSize: 9.5,
                    fontWeight:
                    FontWeight.w600,
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
// Search Field
// ===============================================================

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;

  final FocusNode focusNode;

  final ValueChanged<String> onChanged;

  final VoidCallback onClose;

  @override
  Widget build(
      BuildContext context,
      ) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: null,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      style: const TextStyle(
        color:
        _CallHistoryScreenState._text,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText:
        'Search name or phone number',
        hintStyle: const TextStyle(
          color: Color(0xFF8793A6),
          fontSize: 12,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color:
          _CallHistoryScreenState._blue,
          size: 21,
        ),
        suffixIcon: IconButton(
          tooltip: 'Close search',
          onPressed: onClose,
          icon: const Icon(
            Icons.close_rounded,
            size: 20,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            19,
          ),
          borderSide: const BorderSide(
            color:
            _CallHistoryScreenState
                ._border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            19,
          ),
          borderSide: const BorderSide(
            color:
            _CallHistoryScreenState
                ._blue,
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// History Card
// ===============================================================

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.call,
    required this.onTap,
    required this.onCall,
  });

  final CallHistoryModel call;

  final VoidCallback onTap;

  final VoidCallback onCall;

  @override
  Widget build(
      BuildContext context,
      ) {
    final _HistoryPresentation presentation =
    _HistoryPresentation.from(
      call,
    );

    final String name =
    call.contactName.trim().isEmpty
        ? 'Unknown caller'
        : call.contactName.trim();

    final String phone =
    call.phoneNumber.trim();

    final String avatar =
    call.avatarUrl.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          22,
        ),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(
            13,
            12,
            12,
            12,
          ),
          decoration: BoxDecoration(
            color: presentation.background,
            borderRadius:
            BorderRadius.circular(
              22,
            ),
            border: Border.all(
              color: presentation.border,
            ),
            boxShadow:
            const <BoxShadow>[
              BoxShadow(
                color:
                Color(0x0917233B),
                blurRadius: 13,
                offset: Offset(
                  0,
                  4,
                ),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              CallerAvatar(
                name: name,
                imageUrl:
                avatar.isEmpty
                    ? null
                    : avatar,
                radius: 29,
                isOnline: false,
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style:
                      const TextStyle(
                        color:
                        _CallHistoryScreenState
                            ._text,
                        fontSize: 15,
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),

                    if (phone.isNotEmpty)
                      ...<Widget>[
                        const SizedBox(
                          height: 2,
                        ),
                        Text(
                          phone,
                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style:
                          const TextStyle(
                            color:
                            _CallHistoryScreenState
                                ._muted,
                            fontSize: 11,
                            fontWeight:
                            FontWeight
                                .w500,
                          ),
                        ),
                      ],

                    const SizedBox(
                      height: 3,
                    ),

                    Row(
                      children: <Widget>[
                        Icon(
                          presentation.statusIcon,
                          color:
                          presentation.accent,
                          size: 15,
                        ),

                        const SizedBox(
                          width: 5,
                        ),

                        Flexible(
                          child: Text(
                            presentation
                                .statusLabel,
                            maxLines: 1,
                            overflow:
                            TextOverflow
                                .ellipsis,
                            style: TextStyle(
                              color:
                              presentation
                                  .accent,
                              fontSize: 11.5,
                              fontWeight:
                              FontWeight
                                  .w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 6,
              ),

              Column(
                crossAxisAlignment:
                CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    _formatDate(
                      call.startedAt,
                    ),
                    style: const TextStyle(
                      color:
                      _CallHistoryScreenState
                          ._muted,
                      fontSize: 10.5,
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  Semantics(
                    button: true,
                    label: presentation
                        .actionSemanticLabel,
                    child: Material(
                      color: Colors.white,
                      shape:
                      const CircleBorder(),
                      elevation: 3,
                      shadowColor:
                      presentation.accent
                          .withValues(
                        alpha: 0.20,
                      ),
                      child: InkWell(
                        onTap: onCall,
                        customBorder:
                        const CircleBorder(),
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(
                            presentation
                                .actionIcon,
                            color:
                            presentation
                                .accent,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =============================================================
  // Date / Time
  // =============================================================

  static String _formatDate(
      DateTime value,
      ) {
    final DateTime local = value.toLocal();

    final DateTime now = DateTime.now();

    final DateTime today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final DateTime date = DateTime(
      local.year,
      local.month,
      local.day,
    );

    final int difference =
        today.difference(date).inDays;

    if (difference == 0) {
      return _formatClock(
        local,
      );
    }

    if (difference == 1) {
      return 'Yesterday';
    }

    if (difference > 1 && difference < 7) {
      return '$difference Days Ago';
    }

    final String day =
    local.day.toString().padLeft(
      2,
      '0',
    );

    final String month =
    local.month.toString().padLeft(
      2,
      '0',
    );

    return '$day/$month/${local.year}';
  }

  static String _formatClock(
      DateTime value,
      ) {
    int hour = value.hour;

    final String period =
    hour >= 12 ? 'PM' : 'AM';

    hour %= 12;

    if (hour == 0) {
      hour = 12;
    }

    final String minute =
    value.minute.toString().padLeft(
      2,
      '0',
    );

    return '$hour:$minute $period';
  }
}

// ===============================================================
// History Presentation
// ===============================================================

class _HistoryPresentation {
  const _HistoryPresentation({
    required this.accent,
    required this.background,
    required this.border,
    required this.statusLabel,
    required this.statusIcon,
    required this.actionIcon,
    required this.actionSemanticLabel,
  });

  final Color accent;

  final Color background;

  final Color border;

  final String statusLabel;

  final IconData statusIcon;

  final IconData actionIcon;

  final String actionSemanticLabel;

  factory _HistoryPresentation.from(
      CallHistoryModel call,
      ) {
    final bool outgoing =
        call.direction ==
            CallDirection.outgoing;

    final bool video =
        call.callType ==
            CallType.video;

    final IconData actionIcon = video
        ? Icons.videocam_rounded
        : Icons.call_rounded;

    final String actionSemanticLabel = video
        ? 'Start video call'
        : 'Start voice call';

    switch (call.status) {
      case CallStatus.missed:
        return _HistoryPresentation(
          accent:
          _CallHistoryScreenState._red,
          background:
          const Color(0xFFFFF4F6),
          border:
          const Color(0xFFFFD8DE),
          statusLabel: 'Missed call',
          statusIcon:
          Icons.call_missed_rounded,
          actionIcon: actionIcon,
          actionSemanticLabel:
          actionSemanticLabel,
        );

      case CallStatus.rejected:
        return _HistoryPresentation(
          accent:
          _CallHistoryScreenState._red,
          background:
          const Color(0xFFFFF7F8),
          border:
          const Color(0xFFFFE0E5),
          statusLabel: 'Call rejected',
          statusIcon:
          Icons.call_end_rounded,
          actionIcon: actionIcon,
          actionSemanticLabel:
          actionSemanticLabel,
        );

      case CallStatus.declined:
        return _HistoryPresentation(
          accent:
          _CallHistoryScreenState._red,
          background:
          const Color(0xFFFFF7F8),
          border:
          const Color(0xFFFFE0E5),
          statusLabel: 'Call declined',
          statusIcon:
          Icons.call_end_rounded,
          actionIcon: actionIcon,
          actionSemanticLabel:
          actionSemanticLabel,
        );

      case CallStatus.cancelled:
        return _HistoryPresentation(
          accent:
          _CallHistoryScreenState
              ._orange,
          background:
          const Color(0xFFFFFBF2),
          border:
          const Color(0xFFFFE8B8),
          statusLabel: 'Call cancelled',
          statusIcon:
          Icons.call_end_rounded,
          actionIcon: actionIcon,
          actionSemanticLabel:
          actionSemanticLabel,
        );

      case CallStatus.busy:
        return _HistoryPresentation(
          accent:
          _CallHistoryScreenState
              ._orange,
          background:
          const Color(0xFFFFFBF2),
          border:
          const Color(0xFFFFE8B8),
          statusLabel: 'User busy',
          statusIcon:
          Icons.phone_disabled_rounded,
          actionIcon: actionIcon,
          actionSemanticLabel:
          actionSemanticLabel,
        );

      case CallStatus.failed:
        return _HistoryPresentation(
          accent:
          _CallHistoryScreenState._red,
          background:
          const Color(0xFFFFF7F8),
          border:
          const Color(0xFFFFE0E5),
          statusLabel: 'Call failed',
          statusIcon:
          Icons.error_outline_rounded,
          actionIcon: actionIcon,
          actionSemanticLabel:
          actionSemanticLabel,
        );

      case CallStatus.completed:
        break;
    }

    if (video) {
      return _HistoryPresentation(
        accent:
        _CallHistoryScreenState._purple,
        background:
        const Color(0xFFFBF7FF),
        border:
        const Color(0xFFE9DDFF),
        statusLabel: outgoing
            ? 'Outgoing video call'
            : 'Incoming video call',
        statusIcon: outgoing
            ? Icons.call_made_rounded
            : Icons.call_received_rounded,
        actionIcon:
        Icons.videocam_rounded,
        actionSemanticLabel:
        'Start video call',
      );
    }

    if (outgoing) {
      return const _HistoryPresentation(
        accent:
        _CallHistoryScreenState._blue,
        background:
        Color(0xFFF9FBFF),
        border:
        Color(0xFFDDE8F7),
        statusLabel: 'Outgoing call',
        statusIcon:
        Icons.call_made_rounded,
        actionIcon:
        Icons.call_rounded,
        actionSemanticLabel:
        'Start voice call',
      );
    }

    return const _HistoryPresentation(
      accent:
      _CallHistoryScreenState._green,
      background:
      Color(0xFFF6FFFB),
      border:
      Color(0xFFD5F2E6),
      statusLabel: 'Incoming call',
      statusIcon:
      Icons.call_received_rounded,
      actionIcon:
      Icons.call_rounded,
      actionSemanticLabel:
      'Start voice call',
    );
  }
}

// ===============================================================
// Call Sheet Button
// ===============================================================

class _SheetButton extends StatelessWidget {
  const _SheetButton({
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
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 19,
      ),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize:
        const Size.fromHeight(
          48,
        ),
        shape: RoundedRectangleBorder(
          borderRadius:
          BorderRadius.circular(
            16,
          ),
        ),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ===============================================================
// Empty / Error State
// ===============================================================

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;

  final Color color;

  final String title;

  final String subtitle;

  final Future<void> Function()? onRetry;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: color.withValues(
                  alpha: 0.08,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(
                    alpha: 0.16,
                  ),
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 36,
              ),
            ),

            const SizedBox(
              height: 16,
            ),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color:
                _CallHistoryScreenState
                    ._text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(
              height: 6,
            ),

            Text(
              subtitle,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color:
                _CallHistoryScreenState
                    ._muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),

            if (onRetry != null) ...<Widget>[
              const SizedBox(
                height: 17,
              ),
              FilledButton.icon(
                onPressed: () {
                  unawaited(
                    onRetry!(),
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
          ],
        ),
      ),
    );
  }
}