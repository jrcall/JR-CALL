// ============================================================================
// JR CALL
// File: chat_tile.dart
// Location: lib/features/message/widgets/chat_tile.dart
//
// Pure presentation widget for a JR CALL conversation-list row.
// Displays only real state supplied by the controller/presentation layer.
// No Firestore, repository, authentication, or Call Engine access.
// ============================================================================

import 'package:flutter/material.dart';

class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.displayName,
    required this.lastMessagePreview,
    required this.timeLabel,
    required this.onTap,
    this.avatarUrl,
    this.isVerified = false,
    this.isOnline = false,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.onLongPress,
    this.semanticLabel,
  });

  final String displayName;
  final String lastMessagePreview;
  final String timeLabel;
  final String? avatarUrl;

  final bool isVerified;
  final bool isOnline;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  static const Color _jrBlue = Color(0xFF3978F6);
  static const Color _messagePurple = Color(0xFF7157E8);
  static const Color _messagePink = Color(0xFFE45AA7);

  bool get _hasUnread => unreadCount > 0;

  String get _safeName {
    final String value = displayName.trim();
    return value.isEmpty ? 'JR CALL User' : value;
  }

  String get _safePreview {
    final String value = lastMessagePreview.trim();
    return value.isEmpty ? 'No messages yet' : value;
  }

  String get _safeTime => timeLabel.trim();

  String get _initials {
    final String name = _safeName;
    final List<String> parts = name
        .split(RegExp(r'\s+'))
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) {
      return 'J';
    }

    if (parts.length == 1) {
      final String first = parts.first;
      return first.characters.first.toUpperCase();
    }

    return '${parts.first.characters.first}'
            '${parts.last.characters.first}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final String accessibilityLabel = semanticLabel?.trim().isNotEmpty == true
        ? semanticLabel!.trim()
        : _buildSemanticLabel();

    return Semantics(
      button: true,
      label: accessibilityLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _hasUnread ? const Color(0xFFFBFAFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _buildAvatar(),
                const SizedBox(width: 12),
                Expanded(child: _buildContent()),
                const SizedBox(width: 8),
                _buildTrailing(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final String? normalizedUrl = avatarUrl?.trim();
    final bool hasImage = normalizedUrl != null && normalizedUrl.isNotEmpty;

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFFECE8FF), Color(0xFFFFE8F4)],
                ),
                border: Border.all(color: const Color(0xFFE5E1F4)),
              ),
              child: ClipOval(
                child: hasImage
                    ? Image.network(
                        normalizedUrl,
                        fit: BoxFit.cover,
                        width: 56,
                        height: 56,
                        errorBuilder:
                            (
                              BuildContext context,
                              Object error,
                              StackTrace? stackTrace,
                            ) {
                              return _buildAvatarFallback();
                            },
                      )
                    : _buildAvatarFallback(),
              ),
            ),
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 1,
              child: Semantics(
                label: 'Online',
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: const Color(0xFF32C879),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF6D84F8),
            Color(0xFF7659E6),
            Color(0xFFE15AA5),
          ],
        ),
      ),
      child: Text(
        _initials,
        maxLines: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                _safeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF202534),
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: _hasUnread ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ),
            if (isVerified) ...<Widget>[
              const SizedBox(width: 5),
              const _VerifiedBadge(),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: <Widget>[
            if (isPinned) ...<Widget>[
              const Icon(
                Icons.push_pin_rounded,
                size: 13,
                color: Color(0xFF777D8D),
              ),
              const SizedBox(width: 4),
            ],
            if (isMuted) ...<Widget>[
              const Icon(
                Icons.notifications_off_rounded,
                size: 13,
                color: Color(0xFF8B8F9C),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                _safePreview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _hasUnread
                      ? const Color(0xFF555B6C)
                      : const Color(0xFF858A98),
                  fontSize: 12.5,
                  height: 1.25,
                  fontWeight: _hasUnread ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrailing() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 42, maxWidth: 72),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (_safeTime.isNotEmpty)
            Text(
              _safeTime,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _hasUnread ? _messagePurple : const Color(0xFF989CA8),
                fontSize: 10.5,
                fontWeight: _hasUnread ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          const SizedBox(height: 7),
          if (_hasUnread)
            _UnreadBadge(count: unreadCount)
          else
            const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _buildSemanticLabel() {
    final StringBuffer buffer = StringBuffer(_safeName);

    if (isVerified) {
      buffer.write(', verified');
    }

    if (isOnline) {
      buffer.write(', online');
    }

    if (_safePreview.isNotEmpty) {
      buffer.write(', $_safePreview');
    }

    if (_safeTime.isNotEmpty) {
      buffer.write(', $_safeTime');
    }

    if (_hasUnread) {
      buffer.write(
        ', $unreadCount unread ${unreadCount == 1 ? 'message' : 'messages'}',
      );
    }

    if (isMuted) {
      buffer.write(', muted');
    }

    if (isPinned) {
      buffer.write(', pinned');
    }

    return buffer.toString();
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Verified',
      child: Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: ChatTile._jrBlue,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final String label = count > 99 ? '99+' : count.toString();

    return Semantics(
      label: '$count unread ${count == 1 ? 'message' : 'messages'}',
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[ChatTile._messagePurple, ChatTile._messagePink],
          ),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// END OF FILE
// File: chat_tile.dart
// Location: lib/features/message/widgets/chat_tile.dart
// ============================================================================
