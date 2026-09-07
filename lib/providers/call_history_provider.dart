// ===============================================================
// JR CALL
// File: call_history_provider.dart
// Location: lib/providers/call_history_provider.dart
//
// MASTER PRODUCTION CALL HISTORY PROVIDER
//
// RESPONSIBILITIES:
//
// - Hold real call-history presentation state.
// - Keep newest-first deterministic ordering.
// - Protect against duplicate real history records.
// - Preserve repository/model supplied call metadata exactly.
// - Expose safe aggregates/search/filter/lookup APIs.
// - Maintain loading/error/revision presentation state.
//
// OWNERSHIP:
//
// CallHistoryProvider:
// - In-memory presentation state only.
//
// Repository / Signaling layer:
// - History persistence and server truth.
//
// IMPORTANT:
//
// - No fake/demo call records.
// - No Firestore ownership.
// - No signaling ownership.
// - No WebRTC ownership.
// - No ICE ownership.
// - No recovery ownership.
// - No call lifecycle mutation.
// - No invented call-history statuses.
// ===============================================================

import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/call_history_model.dart';

class CallHistoryProvider extends ChangeNotifier {
  // =============================================================
  // STATE
  // =============================================================

  final List<CallHistoryModel> _callHistory = <CallHistoryModel>[];

  bool _isLoading = false;
  bool _isDisposed = false;

  String? _error;

  int _revision = 0;

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  UnmodifiableListView<CallHistoryModel> get callHistory {
    return UnmodifiableListView<CallHistoryModel>(
      _callHistory,
    );
  }

  bool get isLoading => _isLoading;

  bool get hasError => _error?.isNotEmpty == true;

  String? get error => _error;

  bool get isEmpty => _callHistory.isEmpty;

  bool get isNotEmpty => _callHistory.isNotEmpty;

  int get totalCalls => _callHistory.length;

  int get revision => _revision;

  CallHistoryModel? get latestCall {
    if (_callHistory.isEmpty) {
      return null;
    }

    return _callHistory.first;
  }

  // =============================================================
  // AGGREGATES
  // =============================================================

  int get missedCalls {
    return _count(
          (CallHistoryModel call) =>
      call.status == CallStatus.missed,
    );
  }

  int get completedCalls {
    return _count(
          (CallHistoryModel call) =>
      call.status == CallStatus.completed,
    );
  }

  int get voiceCalls {
    return _count(
          (CallHistoryModel call) =>
      call.callType == CallType.voice,
    );
  }

  int get videoCalls {
    return _count(
          (CallHistoryModel call) =>
      call.callType == CallType.video,
    );
  }

  int get incomingCalls {
    return _count(
          (CallHistoryModel call) =>
      call.direction == CallDirection.incoming,
    );
  }

  int get outgoingCalls {
    return _count(
          (CallHistoryModel call) =>
      call.direction == CallDirection.outgoing,
    );
  }

  int _count(
      bool Function(CallHistoryModel call) test,
      ) {
    return _callHistory.where(test).length;
  }

  // =============================================================
  // DURATION
  // =============================================================

  int get totalCallDurationSeconds {
    return _callHistory.fold<int>(
      0,
          (
          int total,
          CallHistoryModel call,
          ) {
        final int safeDuration =
        call.duration < 0 ? 0 : call.duration;

        return total + safeDuration;
      },
    );
  }

  Duration get totalCallDuration {
    return Duration(
      seconds: totalCallDurationSeconds,
    );
  }

  double get averageCallDurationSeconds {
    if (_callHistory.isEmpty) {
      return 0.0;
    }

    return totalCallDurationSeconds /
        _callHistory.length;
  }

  // =============================================================
  // LOADING / ERROR
  // =============================================================

  void setLoading(
      bool value,
      ) {
    if (_isDisposed ||
        _isLoading == value) {
      return;
    }

    _isLoading = value;

    _notify();
  }

  void setError(
      String? message,
      ) {
    if (_isDisposed) {
      return;
    }

    final String normalized =
        message?.trim() ?? '';

    final String? nextError =
    normalized.isEmpty
        ? null
        : normalized;

    if (_error == nextError) {
      return;
    }

    _error = nextError;

    _notify();
  }

  void clearError() {
    setError(null);
  }

  // =============================================================
  // LOAD / REPLACE
  // =============================================================

  Future<void> loadHistory(
      Iterable<CallHistoryModel> history,
      ) async {
    if (_isDisposed) {
      return;
    }

    _isLoading = true;
    _error = null;

    _notify();

    try {
      final List<CallHistoryModel> normalized =
      _normalize(
        history,
      );

      if (_isDisposed) {
        return;
      }

      if (!_sameHistory(
        _callHistory,
        normalized,
      )) {
        _callHistory
          ..clear()
          ..addAll(normalized);

        _revision++;
      }
    } catch (error, stackTrace) {
      if (_isDisposed) {
        return;
      }

      _error = _errorText(
        error,
      );

      _reportError(
        'loadHistory',
        error,
        stackTrace,
      );
    } finally {
      if (!_isDisposed) {
        _isLoading = false;

        _notify();
      }
    }
  }

  void replaceHistory(
      Iterable<CallHistoryModel> history,
      ) {
    if (_isDisposed) {
      return;
    }

    try {
      final List<CallHistoryModel> normalized =
      _normalize(
        history,
      );

      final bool historyChanged =
      !_sameHistory(
        _callHistory,
        normalized,
      );

      final bool hadError =
          _error != null;

      if (historyChanged) {
        _callHistory
          ..clear()
          ..addAll(normalized);

        _revision++;
      }

      _error = null;

      if (historyChanged ||
          hadError) {
        _notify();
      }
    } catch (error, stackTrace) {
      _error = _errorText(
        error,
      );

      _reportError(
        'replaceHistory',
        error,
        stackTrace,
      );

      _notify();
    }
  }

  // =============================================================
  // MERGE / ADD / UPDATE / UPSERT
  // =============================================================

  void mergeHistory(
      Iterable<CallHistoryModel> history,
      ) {
    if (_isDisposed) {
      return;
    }

    try {
      final List<CallHistoryModel> merged =
      <CallHistoryModel>[
        ..._callHistory,
        ...history,
      ];

      final List<CallHistoryModel> normalized =
      _normalize(
        merged,
      );

      final bool historyChanged =
      !_sameHistory(
        _callHistory,
        normalized,
      );

      final bool hadError =
          _error != null;

      if (historyChanged) {
        _callHistory
          ..clear()
          ..addAll(normalized);

        _revision++;
      }

      _error = null;

      if (historyChanged ||
          hadError) {
        _notify();
      }
    } catch (error, stackTrace) {
      _error = _errorText(
        error,
      );

      _reportError(
        'mergeHistory',
        error,
        stackTrace,
      );

      _notify();
    }
  }

  void addCall(
      CallHistoryModel call,
      ) {
    if (_isDisposed) {
      return;
    }

    final int index =
    _findIndex(
      call,
    );

    if (index >= 0) {
      if (_sameCall(
        _callHistory[index],
        call,
      )) {
        return;
      }

      _callHistory[index] =
          call;
    } else {
      _callHistory.add(
        call,
      );
    }

    _finishMutation();
  }

  void addCalls(
      Iterable<CallHistoryModel> calls,
      ) {
    mergeHistory(
      calls,
    );
  }

  bool updateCall(
      CallHistoryModel updatedCall,
      ) {
    if (_isDisposed) {
      return false;
    }

    final int index =
    _findIndex(
      updatedCall,
    );

    if (index < 0) {
      return false;
    }

    if (_sameCall(
      _callHistory[index],
      updatedCall,
    )) {
      return true;
    }

    _callHistory[index] =
        updatedCall;

    _finishMutation();

    return true;
  }

  void upsertCall(
      CallHistoryModel call,
      ) {
    if (_isDisposed) {
      return;
    }

    final int index =
    _findIndex(
      call,
    );

    if (index < 0) {
      _callHistory.add(
        call,
      );

      _finishMutation();

      return;
    }

    if (_sameCall(
      _callHistory[index],
      call,
    )) {
      return;
    }

    _callHistory[index] =
        call;

    _finishMutation();
  }

  // =============================================================
  // REMOVE
  // =============================================================

  bool removeCall(
      String id,
      ) {
    if (_isDisposed) {
      return false;
    }

    final String normalized =
    id.trim();

    if (normalized.isEmpty) {
      return false;
    }

    final int previousLength =
        _callHistory.length;

    _callHistory.removeWhere(
          (CallHistoryModel call) {
        return _matchesExternalId(
          call,
          normalized,
        );
      },
    );

    if (_callHistory.length ==
        previousLength) {
      return false;
    }

    _error = null;
    _revision++;

    _notify();

    return true;
  }

  int removeCalls(
      Iterable<String> ids,
      ) {
    if (_isDisposed) {
      return 0;
    }

    final Set<String> normalizedIds =
    ids
        .map(
          (String id) =>
          id.trim(),
    )
        .where(
          (String id) =>
      id.isNotEmpty,
    )
        .toSet();

    if (normalizedIds.isEmpty) {
      return 0;
    }

    final int previousLength =
        _callHistory.length;

    _callHistory.removeWhere(
          (CallHistoryModel call) {
        final String recordId =
        call.id.trim();

        final String sessionId =
        call.sessionId.trim();

        return normalizedIds.contains(
          recordId,
        ) ||
            normalizedIds.contains(
              sessionId,
            );
      },
    );

    final int removed =
        previousLength -
            _callHistory.length;

    if (removed > 0) {
      _error = null;
      _revision++;

      _notify();
    }

    return removed;
  }

  void clearHistory() {
    if (_isDisposed) {
      return;
    }

    final bool hadHistory =
        _callHistory.isNotEmpty;

    final bool hadLoading =
        _isLoading;

    final bool hadError =
        _error != null;

    if (!hadHistory &&
        !hadLoading &&
        !hadError) {
      return;
    }

    _callHistory.clear();

    _isLoading = false;
    _error = null;

    if (hadHistory) {
      _revision++;
    }

    _notify();
  }

  // =============================================================
  // SEARCH / FILTER
  // =============================================================

  List<CallHistoryModel> search(
      String keyword,
      ) {
    final String query =
    keyword
        .trim()
        .toLowerCase();

    if (query.isEmpty) {
      return List<CallHistoryModel>.unmodifiable(
        _callHistory,
      );
    }

    return List<CallHistoryModel>.unmodifiable(
      _callHistory.where(
            (CallHistoryModel call) {
          return call.contactName
              .trim()
              .toLowerCase()
              .contains(query) ||
              call.phoneNumber
                  .trim()
                  .toLowerCase()
                  .contains(query) ||
              call.contactId
                  .trim()
                  .toLowerCase()
                  .contains(query) ||
              call.userId
                  .trim()
                  .toLowerCase()
                  .contains(query) ||
              call.id
                  .trim()
                  .toLowerCase()
                  .contains(query) ||
              call.sessionId
                  .trim()
                  .toLowerCase()
                  .contains(query);
        },
      ),
    );
  }

  List<CallHistoryModel> byType(
      CallType type,
      ) {
    return List<CallHistoryModel>.unmodifiable(
      _callHistory.where(
            (CallHistoryModel call) =>
        call.callType == type,
      ),
    );
  }

  List<CallHistoryModel> byStatus(
      CallStatus status,
      ) {
    return List<CallHistoryModel>.unmodifiable(
      _callHistory.where(
            (CallHistoryModel call) =>
        call.status == status,
      ),
    );
  }

  List<CallHistoryModel> byDirection(
      CallDirection direction,
      ) {
    return List<CallHistoryModel>.unmodifiable(
      _callHistory.where(
            (CallHistoryModel call) =>
        call.direction == direction,
      ),
    );
  }

  List<CallHistoryModel> byContactId(
      String contactId,
      ) {
    final String normalized =
    contactId.trim();

    if (normalized.isEmpty) {
      return const <CallHistoryModel>[];
    }

    return List<CallHistoryModel>.unmodifiable(
      _callHistory.where(
            (CallHistoryModel call) =>
        call.contactId.trim() ==
            normalized,
      ),
    );
  }

  // =============================================================
  // LOOKUP
  // =============================================================

  CallHistoryModel? getById(
      String id,
      ) {
    final String normalized =
    id.trim();

    if (normalized.isEmpty) {
      return null;
    }

    for (final CallHistoryModel call
    in _callHistory) {
      if (_matchesExternalId(
        call,
        normalized,
      )) {
        return call;
      }
    }

    return null;
  }

  CallHistoryModel? getBySessionId(
      String sessionId,
      ) {
    final String normalized =
    sessionId.trim();

    if (normalized.isEmpty) {
      return null;
    }

    for (final CallHistoryModel call
    in _callHistory) {
      if (call.sessionId.trim() ==
          normalized) {
        return call;
      }
    }

    return null;
  }

  // =============================================================
  // REFRESH / RESET
  // =============================================================

  Future<void> refresh() async {
    if (_isDisposed ||
        _callHistory.length < 2) {
      return;
    }

    final List<CallHistoryModel> previous =
    List<CallHistoryModel>.of(
      _callHistory,
    );

    _callHistory.sort(
      _compareCalls,
    );

    if (!_sameHistory(
      previous,
      _callHistory,
    )) {
      _revision++;

      _notify();
    }
  }

  void reset() {
    if (_isDisposed) {
      return;
    }

    final bool hadHistory =
        _callHistory.isNotEmpty;

    final bool hadLoading =
        _isLoading;

    final bool hadError =
        _error != null;

    if (!hadHistory &&
        !hadLoading &&
        !hadError) {
      return;
    }

    _callHistory.clear();

    _isLoading = false;
    _error = null;

    _revision++;

    _notify();
  }

  // =============================================================
  // NORMALIZATION / DUPLICATE PROTECTION
  //
  // sessionId and record id are both real identity aliases.
  //
  // If multiple supplied records become linked by either alias,
  // the latest supplied repository state wins for that group.
  //
  // Fallback identity is used ONLY when both canonical IDs are
  // absent, preventing unrelated real calls from being collapsed.
  // =============================================================

  List<CallHistoryModel> _normalize(
      Iterable<CallHistoryModel> history,
      ) {
    final List<_HistoryIdentityGroup> groups =
    <_HistoryIdentityGroup>[];

    final Map<String, _HistoryIdentityGroup>
    sessionGroups =
    <String, _HistoryIdentityGroup>{};

    final Map<String, _HistoryIdentityGroup>
    recordGroups =
    <String, _HistoryIdentityGroup>{};

    final Map<String, _HistoryIdentityGroup>
    fallbackGroups =
    <String, _HistoryIdentityGroup>{};

    for (final CallHistoryModel call
    in history) {
      final String sessionId =
      call.sessionId.trim();

      final String recordId =
      call.id.trim();

      final Set<_HistoryIdentityGroup> matches =
      <_HistoryIdentityGroup>{};

      if (sessionId.isNotEmpty) {
        final _HistoryIdentityGroup?
        sessionGroup =
        sessionGroups[sessionId];

        if (sessionGroup != null) {
          matches.add(
            sessionGroup,
          );
        }
      }

      if (recordId.isNotEmpty) {
        final _HistoryIdentityGroup?
        recordGroup =
        recordGroups[recordId];

        if (recordGroup != null) {
          matches.add(
            recordGroup,
          );
        }
      }

      final String? fallbackKey =
      sessionId.isEmpty &&
          recordId.isEmpty
          ? _fallbackIdentity(call)
          : null;

      if (fallbackKey != null) {
        final _HistoryIdentityGroup?
        fallbackGroup =
        fallbackGroups[fallbackKey];

        if (fallbackGroup != null) {
          matches.add(
            fallbackGroup,
          );
        }
      }

      final _HistoryIdentityGroup target;

      if (matches.isEmpty) {
        target = _HistoryIdentityGroup(
          call,
        );

        groups.add(
          target,
        );
      } else {
        target = matches.first;

        if (matches.length > 1) {
          final List<_HistoryIdentityGroup>
          duplicateGroups =
          matches
              .where(
                (_HistoryIdentityGroup group) =>
            !identical(
              group,
              target,
            ),
          )
              .toList(
            growable: false,
          );

          for (final _HistoryIdentityGroup duplicate
          in duplicateGroups) {
            target.sessionIds.addAll(
              duplicate.sessionIds,
            );

            target.recordIds.addAll(
              duplicate.recordIds,
            );

            target.fallbackKeys.addAll(
              duplicate.fallbackKeys,
            );

            groups.remove(
              duplicate,
            );
          }
        }

        // Later repository/model state wins.
        target.call = call;
      }

      if (sessionId.isNotEmpty) {
        target.sessionIds.add(
          sessionId,
        );
      }

      if (recordId.isNotEmpty) {
        target.recordIds.add(
          recordId,
        );
      }

      if (fallbackKey != null) {
        target.fallbackKeys.add(
          fallbackKey,
        );
      }

      for (final String alias
      in target.sessionIds) {
        sessionGroups[alias] =
            target;
      }

      for (final String alias
      in target.recordIds) {
        recordGroups[alias] =
            target;
      }

      for (final String alias
      in target.fallbackKeys) {
        fallbackGroups[alias] =
            target;
      }
    }

    final List<CallHistoryModel> normalized =
    groups
        .map(
          (_HistoryIdentityGroup group) =>
      group.call,
    )
        .toList(
      growable: true,
    );

    normalized.sort(
      _compareCalls,
    );

    return List<CallHistoryModel>.unmodifiable(
      normalized,
    );
  }

  int _findIndex(
      CallHistoryModel call,
      ) {
    return _findIndexIn(
      _callHistory,
      call,
    );
  }

  int _findIndexIn(
      List<CallHistoryModel> source,
      CallHistoryModel call,
      ) {
    return source.indexWhere(
          (CallHistoryModel item) =>
          _sameIdentity(
            item,
            call,
          ),
    );
  }

  bool _sameIdentity(
      CallHistoryModel first,
      CallHistoryModel second,
      ) {
    final String firstSession =
    first.sessionId.trim();

    final String secondSession =
    second.sessionId.trim();

    if (firstSession.isNotEmpty &&
        secondSession.isNotEmpty &&
        firstSession == secondSession) {
      return true;
    }

    final String firstId =
    first.id.trim();

    final String secondId =
    second.id.trim();

    if (firstId.isNotEmpty &&
        secondId.isNotEmpty &&
        firstId == secondId) {
      return true;
    }

    if (firstSession.isEmpty &&
        secondSession.isEmpty &&
        firstId.isEmpty &&
        secondId.isEmpty) {
      return _fallbackIdentity(first) ==
          _fallbackIdentity(second);
    }

    return false;
  }

  bool _matchesExternalId(
      CallHistoryModel call,
      String id,
      ) {
    return call.id.trim() == id ||
        call.sessionId.trim() == id;
  }

  String _fallbackIdentity(
      CallHistoryModel call,
      ) {
    return '${call.userId.trim()}|'
        '${call.contactId.trim()}|'
        '${call.direction.name}|'
        '${call.callType.name}|'
        '${call.startedAt.microsecondsSinceEpoch}';
  }

  String _sortIdentity(
      CallHistoryModel call,
      ) {
    final String sessionId =
    call.sessionId.trim();

    if (sessionId.isNotEmpty) {
      return 'session:$sessionId';
    }

    final String recordId =
    call.id.trim();

    if (recordId.isNotEmpty) {
      return 'id:$recordId';
    }

    return 'fallback:${_fallbackIdentity(call)}';
  }

  // =============================================================
  // SORT
  // =============================================================

  int _compareCalls(
      CallHistoryModel first,
      CallHistoryModel second,
      ) {
    final int timestamp =
    second.startedAt.compareTo(
      first.startedAt,
    );

    if (timestamp != 0) {
      return timestamp;
    }

    return _sortIdentity(
      second,
    ).compareTo(
      _sortIdentity(first),
    );
  }

  // =============================================================
  // MUTATION FINALIZATION
  // =============================================================

  void _finishMutation() {
    if (_isDisposed) {
      return;
    }

    final List<CallHistoryModel> normalized =
    _normalize(
      _callHistory,
    );

    _callHistory
      ..clear()
      ..addAll(normalized);

    _error = null;

    _revision++;

    _notify();
  }

  // =============================================================
  // CHANGE DETECTION
  // =============================================================

  bool _sameHistory(
      List<CallHistoryModel> current,
      List<CallHistoryModel> next,
      ) {
    if (identical(
      current,
      next,
    )) {
      return true;
    }

    if (current.length !=
        next.length) {
      return false;
    }

    for (int index = 0;
    index < current.length;
    index++) {
      if (!_sameCall(
        current[index],
        next[index],
      )) {
        return false;
      }
    }

    return true;
  }

  bool _sameCall(
      CallHistoryModel first,
      CallHistoryModel second,
      ) {
    if (identical(
      first,
      second,
    )) {
      return true;
    }

    return first.id == second.id &&
        first.sessionId == second.sessionId &&
        first.userId == second.userId &&
        first.contactId == second.contactId &&
        first.contactName == second.contactName &&
        first.phoneNumber == second.phoneNumber &&
        first.avatarUrl == second.avatarUrl &&
        first.callType == second.callType &&
        first.direction == second.direction &&
        first.status == second.status &&
        first.quality == second.quality &&
        first.duration == second.duration &&
        first.averagePing == second.averagePing &&
        first.averageJitter == second.averageJitter &&
        first.packetLoss == second.packetLoss &&
        first.isEncrypted == second.isEncrypted &&
        first.isRecorded == second.isRecorded &&
        first.isHd == second.isHd &&
        first.startedAt == second.startedAt &&
        first.endedAt == second.endedAt;
  }

  // =============================================================
  // ERROR HELPERS
  // =============================================================

  String _errorText(
      Object error,
      ) {
    final String normalized =
    error
        .toString()
        .trim();

    return normalized.isEmpty
        ? 'Unable to process call history.'
        : normalized;
  }

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [CallHistoryProvider/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL '
            '[CallHistoryProvider/$source]',
        stackTrace:
        stackTrace,
      );
    }
  }

  // =============================================================
  // NOTIFICATION
  // =============================================================

  void _notify() {
    if (_isDisposed) {
      return;
    }

    notifyListeners();
  }

  // =============================================================
  // DISPOSE
  // =============================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    _callHistory.clear();

    _isLoading = false;

    _error = null;

    super.dispose();
  }
}

/// =============================================================
/// INTERNAL HISTORY IDENTITY GROUP
///
/// Used only while normalizing real repository/model records.
/// It is not exposed to UI and does not create any history data.
/// =============================================================

class _HistoryIdentityGroup {
  _HistoryIdentityGroup(
      this.call,
      );

  CallHistoryModel call;

  final Set<String> sessionIds =
  <String>{};

  final Set<String> recordIds =
  <String>{};

  final Set<String> fallbackKeys =
  <String>{};
}