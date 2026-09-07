// ============================================================================
// JR CALL
// File: message_bubble.dart
// Location: lib/features/message/widgets/message_bubble.dart
//
// Description:
// Reusable durable JR CALL message bubble.
//
// Responsibilities:
// - Pure durable-message presentation.
// - Outgoing / incoming message rendering.
// - Text / image / video / audio / voice / file / system rendering.
// - Reply preview.
// - Edited / deleted state.
// - Durable sent / delivered / read / failed state.
// - Reaction presentation.
// - Retry presentation.
// - Selection / long-press actions.
// - Attachment tap delegation.
//
// Important:
// - No Firestore access.
// - No Firebase Storage access.
// - No repository access.
// - No Call Engine / WebRTC access.
// - MessageEntity remains the canonical source of message data.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/attachment_entity.dart';
import '../data/message_entity.dart';
import '../data/message_status.dart';
import '../data/message_type.dart';

typedef MessageBubbleCallback = void Function(MessageEntity message);

typedef MessageBubbleReactionCallback =
    void Function(MessageEntity message, String reaction);

typedef MessageBubbleAttachmentCallback =
    void Function(MessageEntity message, AttachmentEntity attachment);

@immutable
class MessageBubbleReaction {
  const MessageBubbleReaction({
    required this.value,
    required this.count,
    this.selectedByCurrentUser = false,
  }) : assert(count > 0);

  final String value;
  final int count;
  final bool selectedByCurrentUser;
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isOutgoing,
    this.reactions = const <MessageBubbleReaction>[],
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onRetry,
    this.onReaction,
    this.onRemoveReaction,
    this.onAttachmentTap,
    this.onLongPress,
    this.onSelect,
    this.isSelected = false,
    this.showSenderName = false,
    this.senderName,
    this.maxBubbleWidth = 340,
  });

  final MessageEntity message;
  final bool isOutgoing;

  final List<MessageBubbleReaction> reactions;

  final MessageBubbleCallback? onReply;
  final MessageBubbleCallback? onEdit;
  final MessageBubbleCallback? onDelete;
  final MessageBubbleCallback? onRetry;

  final MessageBubbleReactionCallback? onReaction;
  final MessageBubbleCallback? onRemoveReaction;

  final MessageBubbleAttachmentCallback? onAttachmentTap;

  final MessageBubbleCallback? onLongPress;
  final MessageBubbleCallback? onSelect;

  final bool isSelected;
  final bool showSenderName;
  final String? senderName;
  final double maxBubbleWidth;

  bool get _isDeleted => message.deletedAt != null;

  bool get _isEdited => message.editedAt != null && !_isDeleted;

  String get _messageText => _safeText(message.text);

  bool get _hasText => _messageText.isNotEmpty;

  bool get _canCopy {
    return !_isDeleted && message.type == MessageType.text && _hasText;
  }

  bool get _canEdit {
    return isOutgoing &&
        !_isDeleted &&
        message.type == MessageType.text &&
        _hasText;
  }

  bool get _canDelete => isOutgoing && !_isDeleted;

  bool get _canRetry {
    return isOutgoing && !_isDeleted && message.status == MessageStatus.failed;
  }

  bool get _hasMenu {
    return onReply != null ||
        _canCopy ||
        (_canEdit && onEdit != null) ||
        (_canDelete && onDelete != null) ||
        (_canRetry && onRetry != null) ||
        onReaction != null ||
        onRemoveReaction != null;
  }

  bool get _hasReplyMetadata {
    return _safeText(message.replyToMessageId).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final Widget bubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelect == null ? null : () => onSelect!(message),
      onLongPress: () => _handleLongPress(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: EdgeInsets.fromLTRB(
          _isDeleted ? 12 : 10,
          _isDeleted ? 10 : 8,
          _isDeleted ? 12 : 10,
          7,
        ),
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        decoration: BoxDecoration(
          color: _bubbleColor,
          borderRadius: _bubbleRadius,
          border: Border.all(
            color: isSelected ? const Color(0xFF6554E8) : _borderColor,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x0B1D2948),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: _buildBubbleContent(context),
      ),
    );

    return Semantics(
      container: true,
      selected: isSelected,
      label: _semanticLabel,
      child: Align(
        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isOutgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: <Widget>[
            bubble,
            if (reactions.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  left: isOutgoing ? 0 : 18,
                  right: isOutgoing ? 18 : 0,
                  top: 1,
                  bottom: 2,
                ),
                child: _buildReactionSummary(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleContent(BuildContext context) {
    if (_isDeleted) {
      return _buildDeletedContent();
    }

    final String normalizedSenderName = _safeText(senderName);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!isOutgoing && showSenderName && normalizedSenderName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 5),
            child: Text(
              normalizedSenderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6655D9),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (_hasReplyMetadata) _buildReplyPreview(),
        _buildMessageBody(context),
        const SizedBox(height: 5),
        _buildMetadataRow(),
        if (_canRetry && onRetry != null) ...<Widget>[
          const SizedBox(height: 7),
          _buildRetryButton(),
        ],
      ],
    );
  }

  Widget _buildMessageBody(BuildContext context) {
    switch (message.type) {
      case MessageType.text:
        return _buildTextMessage();

      case MessageType.image:
        return _buildImageMessage();

      case MessageType.video:
        return _buildVideoMessage();

      case MessageType.audio:
        return _buildAudioMessage(voice: false);

      case MessageType.voice:
        return _buildAudioMessage(voice: true);

      case MessageType.file:
        return _buildFileMessage();

      case MessageType.system:
        return _buildSystemMessage();
    }
  }

  Widget _buildTextMessage() {
    final String text = _messageText;

    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SelectableText(
        text,
        style: TextStyle(
          color: isOutgoing ? const Color(0xFF20213A) : const Color(0xFF202636),
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildImageMessage() {
    final AttachmentEntity? attachment = message.attachment;

    if (attachment == null) {
      return _buildUnavailableAttachment(
        icon: Icons.image_not_supported_outlined,
        label: 'Image unavailable',
      );
    }

    final String url = _safeText(attachment.downloadUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AttachmentTapRegion(
          enabled: onAttachmentTap != null,
          onTap: () => onAttachmentTap?.call(message, attachment),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 180,
                minHeight: 130,
                maxWidth: 300,
                maxHeight: 360,
              ),
              color: const Color(0xFFEDEFF6),
              child: url.isEmpty
                  ? _buildAttachmentPlaceholder(Icons.image_outlined, 'Image')
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorBuilder:
                          (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) {
                            return _buildAttachmentPlaceholder(
                              Icons.broken_image_outlined,
                              'Image unavailable',
                            );
                          },
                      loadingBuilder:
                          (
                            BuildContext context,
                            Widget child,
                            ImageChunkEvent? progress,
                          ) {
                            if (progress == null) {
                              return child;
                            }

                            final int? expected = progress.expectedTotalBytes;

                            final double? value =
                                expected == null || expected <= 0
                                ? null
                                : progress.cumulativeBytesLoaded / expected;

                            return SizedBox(
                              width: 220,
                              height: 180,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: value,
                                  strokeWidth: 2.4,
                                  color: const Color(0xFF6554E8),
                                ),
                              ),
                            );
                          },
                    ),
            ),
          ),
        ),
        if (_hasText) ...<Widget>[
          const SizedBox(height: 7),
          _buildAttachmentCaption(),
        ],
      ],
    );
  }

  Widget _buildVideoMessage() {
    final AttachmentEntity? attachment = message.attachment;

    if (attachment == null) {
      return _buildUnavailableAttachment(
        icon: Icons.videocam_off_outlined,
        label: 'Video unavailable',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AttachmentTapRegion(
          enabled: onAttachmentTap != null,
          onTap: () => onAttachmentTap?.call(message, attachment),
          child: Container(
            width: 230,
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFF20253A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[Color(0xFF2C3350), Color(0xFF171B2D)],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xEFFFFFFF),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 34,
                    color: Color(0xFF6554E8),
                  ),
                ),
                if (attachment.duration != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _DurationBadge(duration: attachment.duration!),
                  ),
              ],
            ),
          ),
        ),
        if (_hasText) ...<Widget>[
          const SizedBox(height: 7),
          _buildAttachmentCaption(),
        ],
      ],
    );
  }

  Widget _buildAudioMessage({required bool voice}) {
    final AttachmentEntity? attachment = message.attachment;

    if (attachment == null) {
      return _buildUnavailableAttachment(
        icon: voice ? Icons.mic_off_outlined : Icons.audio_file_outlined,
        label: voice ? 'Voice message unavailable' : 'Audio unavailable',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AttachmentTapRegion(
          enabled: onAttachmentTap != null,
          onTap: () => onAttachmentTap?.call(message, attachment),
          child: Container(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 290),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: isOutgoing
                  ? const Color(0x24FFFFFF)
                  : const Color(0xFFF4F2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6554E8),
                  ),
                  child: Icon(
                    voice ? Icons.mic_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: voice ? 21 : 26,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        voice ? 'Voice message' : _safeFileName(attachment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF292D40),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD8D4F7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          if (attachment.duration != null) ...<Widget>[
                            const SizedBox(width: 8),
                            Text(
                              _formatDuration(attachment.duration!),
                              style: const TextStyle(
                                color: Color(0xFF777D90),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_hasText) ...<Widget>[
          const SizedBox(height: 7),
          _buildAttachmentCaption(),
        ],
      ],
    );
  }

  Widget _buildFileMessage() {
    final AttachmentEntity? attachment = message.attachment;

    if (attachment == null) {
      return _buildUnavailableAttachment(
        icon: Icons.insert_drive_file_outlined,
        label: 'File unavailable',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AttachmentTapRegion(
          enabled: onAttachmentTap != null,
          onTap: () => onAttachmentTap?.call(message, attachment),
          child: Container(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: isOutgoing
                  ? const Color(0x24FFFFFF)
                  : const Color(0xFFF5F4FA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 43,
                  height: 43,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E5FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.description_rounded,
                    color: Color(0xFF6554E8),
                    size: 23,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _safeFileName(attachment),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF292D40),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _fileDescription(attachment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7D8394),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 17,
                  color: Color(0xFF777D90),
                ),
              ],
            ),
          ),
        ),
        if (_hasText) ...<Widget>[
          const SizedBox(height: 7),
          _buildAttachmentCaption(),
        ],
      ],
    );
  }

  Widget _buildSystemMessage() {
    final String text = _messageText;

    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF737B90),
        fontSize: 12.5,
        height: 1.35,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildAttachmentCaption() {
    final String caption = _messageText;

    if (caption.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SelectableText(
        caption,
        style: const TextStyle(
          color: Color(0xFF252A3A),
          fontSize: 14.5,
          height: 1.32,
        ),
      ),
    );
  }

  Widget _buildUnavailableAttachment({
    required IconData icon,
    required String label,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 190),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F7),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 22, color: const Color(0xFF7B8294)),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6F7688),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentPlaceholder(IconData icon, String label) {
    return SizedBox(
      width: 220,
      height: 180,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 36, color: const Color(0xFF8B91A1)),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF747B8D),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    final String sender = _safeText(message.replyToSenderUid);

    // MessageEntity canonical API uses replyPreview.
    // There is intentionally no replyToText field.
    final String preview = _safeText(message.replyPreview);

    final String fallback =
        message.replyType?.previewLabel ?? 'Original message';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      decoration: BoxDecoration(
        color: isOutgoing ? const Color(0x24FFFFFF) : const Color(0xFFF1F0F8),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: Color(0xFF705AE9), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (sender.isNotEmpty)
            Text(
              sender == message.senderUid ? 'You' : 'Reply',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6654D9),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          if (sender.isNotEmpty) const SizedBox(height: 2),
          Text(
            preview.isEmpty ? fallback : preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6E7485),
              fontSize: 11.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeletedContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.block_rounded, size: 16, color: Color(0xFF8B91A0)),
        const SizedBox(width: 7),
        const Flexible(
          child: Text(
            'This message was deleted',
            style: TextStyle(
              color: Color(0xFF858B99),
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formattedTime,
          style: const TextStyle(
            color: Color(0xFF9A9FAD),
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (_isEdited) ...<Widget>[
          Text(
            'edited',
            style: TextStyle(
              color: _metadataColor,
              fontSize: 9.5,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Text(
          _formattedTime,
          style: TextStyle(
            color: _metadataColor,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (isOutgoing) ...<Widget>[
          const SizedBox(width: 4),
          _buildStatusIcon(),
        ],
      ],
    );
  }

  Widget _buildStatusIcon() {
    switch (message.status) {
      case MessageStatus.queued:
        return Icon(Icons.schedule_rounded, size: 14, color: _metadataColor);

      case MessageStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: _metadataColor,
          ),
        );

      case MessageStatus.sent:
        return Icon(Icons.check_rounded, size: 15, color: _metadataColor);

      case MessageStatus.delivered:
        return Icon(Icons.done_all_rounded, size: 16, color: _metadataColor);

      case MessageStatus.read:
        return const Icon(
          Icons.done_all_rounded,
          size: 16,
          color: Color(0xFF3F86F5),
        );

      case MessageStatus.failed:
        return const Icon(
          Icons.error_outline_rounded,
          size: 15,
          color: Color(0xFFE15163),
        );
    }
  }

  Widget _buildRetryButton() {
    return InkWell(
      onTap: () => onRetry?.call(message),
      borderRadius: BorderRadius.circular(10),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.refresh_rounded, size: 15, color: Color(0xFFE15163)),
            SizedBox(width: 4),
            Text(
              'Retry',
              style: TextStyle(
                color: Color(0xFFE15163),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionSummary() {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions
          .map((MessageBubbleReaction reaction) {
            return InkWell(
              onTap: reaction.selectedByCurrentUser && onRemoveReaction != null
                  ? () => onRemoveReaction!(message)
                  : onReaction == null
                  ? null
                  : () => onReaction!(message, reaction.value),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: reaction.selectedByCurrentUser
                      ? const Color(0xFFEAE6FF)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: reaction.selectedByCurrentUser
                        ? const Color(0xFF8B79EE)
                        : const Color(0xFFE0E3EC),
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x0B20283D),
                      blurRadius: 5,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(reaction.value, style: const TextStyle(fontSize: 13)),
                    if (reaction.count > 1) ...<Widget>[
                      const SizedBox(width: 3),
                      Text(
                        '${reaction.count}',
                        style: const TextStyle(
                          color: Color(0xFF606779),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Future<void> _handleLongPress(BuildContext context) async {
    onLongPress?.call(message);

    if (!_hasMenu) {
      return;
    }

    final _MessageMenuAction? action =
        await showModalBottomSheet<_MessageMenuAction>(
          context: context,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (BuildContext context) {
            return _MessageActionSheet(
              canReply: onReply != null && !_isDeleted,
              canCopy: _canCopy,
              canEdit: _canEdit && onEdit != null,
              canDelete: _canDelete && onDelete != null,
              canRetry: _canRetry && onRetry != null,
              canReact: onReaction != null && !_isDeleted,
              canRemoveReaction:
                  onRemoveReaction != null &&
                  reactions.any(
                    (MessageBubbleReaction reaction) =>
                        reaction.selectedByCurrentUser,
                  ),
            );
          },
        );

    if (action == null || !context.mounted) {
      return;
    }

    switch (action) {
      case _MessageMenuAction.reply:
        onReply?.call(message);
        return;

      case _MessageMenuAction.copy:
        final String text = _messageText;

        if (text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
        }
        return;

      case _MessageMenuAction.edit:
        onEdit?.call(message);
        return;

      case _MessageMenuAction.delete:
        onDelete?.call(message);
        return;

      case _MessageMenuAction.retry:
        onRetry?.call(message);
        return;

      case _MessageMenuAction.removeReaction:
        onRemoveReaction?.call(message);
        return;

      case _MessageMenuAction.reactHeart:
        onReaction?.call(message, '❤️');
        return;

      case _MessageMenuAction.reactLike:
        onReaction?.call(message, '👍');
        return;

      case _MessageMenuAction.reactLaugh:
        onReaction?.call(message, '😂');
        return;

      case _MessageMenuAction.reactWow:
        onReaction?.call(message, '😮');
        return;

      case _MessageMenuAction.reactSad:
        onReaction?.call(message, '😢');
        return;
    }
  }

  Color get _bubbleColor {
    if (_isDeleted) {
      return const Color(0xFFF2F3F6);
    }

    if (isOutgoing) {
      return const Color(0xFFECE9FF);
    }

    return Colors.white;
  }

  Color get _borderColor {
    if (_isDeleted) {
      return const Color(0xFFE2E4EA);
    }

    if (isOutgoing) {
      return const Color(0xFFDCD5FF);
    }

    return const Color(0xFFE6E8EF);
  }

  BorderRadius get _bubbleRadius {
    return BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isOutgoing ? 18 : 5),
      bottomRight: Radius.circular(isOutgoing ? 5 : 18),
    );
  }

  Color get _metadataColor {
    return isOutgoing ? const Color(0xFF77718F) : const Color(0xFF8A8F9D);
  }

  DateTime get _displayTimestamp {
    return (message.serverCreatedAt ?? message.clientCreatedAt).toUtc();
  }

  String get _formattedTime {
    final DateTime value = _displayTimestamp.toLocal();

    final int hour = value.hour;
    final int minute = value.minute;

    final String suffix = hour >= 12 ? 'PM' : 'AM';

    final int displayHour = hour == 0
        ? 12
        : hour > 12
        ? hour - 12
        : hour;

    return '$displayHour:'
        '${minute.toString().padLeft(2, '0')} '
        '$suffix';
  }

  String get _semanticLabel {
    if (_isDeleted) {
      return isOutgoing
          ? 'Outgoing deleted message'
          : 'Incoming deleted message';
    }

    final String direction = isOutgoing ? 'Outgoing' : 'Incoming';

    final String content = _hasText
        ? _messageText
        : _messageTypeLabel(message.type);

    return '$direction message, '
        '$content, '
        '$_formattedTime';
  }

  static String _messageTypeLabel(MessageType type) {
    switch (type) {
      case MessageType.text:
        return 'text message';

      case MessageType.image:
        return 'image';

      case MessageType.video:
        return 'video';

      case MessageType.audio:
        return 'audio';

      case MessageType.voice:
        return 'voice message';

      case MessageType.file:
        return 'file';

      case MessageType.system:
        return 'system message';
    }
  }

  static String _safeFileName(AttachmentEntity attachment) {
    final String name = _safeText(attachment.fileName);

    return name.isEmpty ? 'Attachment' : name;
  }

  static String _fileDescription(AttachmentEntity attachment) {
    final List<String> values = <String>[];

    final String mime = _safeText(attachment.mimeType);

    if (mime.isNotEmpty) {
      values.add(mime);
    }

    if (attachment.byteSize > 0) {
      values.add(_formatBytes(attachment.byteSize));
    }

    if (values.isEmpty) {
      return 'File';
    }

    return values.join(' • ');
  }

  static String _safeText(String? value) {
    return value?.trim() ?? '';
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }

    if (bytes < 1024) {
      return '$bytes B';
    }

    final double kb = bytes / 1024;

    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    }

    final double mb = kb / 1024;

    if (mb < 1024) {
      return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
    }

    final double gb = mb / 1024;

    return '${gb.toStringAsFixed(gb >= 100 ? 0 : 1)} GB';
  }

  static String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds.clamp(0, 359999);

    final int hours = totalSeconds ~/ 3600;

    final int minutes = (totalSeconds % 3600) ~/ 60;

    final int seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

enum _MessageMenuAction {
  reply,
  copy,
  edit,
  delete,
  retry,
  removeReaction,
  reactHeart,
  reactLike,
  reactLaugh,
  reactWow,
  reactSad,
}

class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({
    required this.canReply,
    required this.canCopy,
    required this.canEdit,
    required this.canDelete,
    required this.canRetry,
    required this.canReact,
    required this.canRemoveReaction,
  });

  final bool canReply;
  final bool canCopy;
  final bool canEdit;
  final bool canDelete;
  final bool canRetry;
  final bool canReact;
  final bool canRemoveReaction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFD9DCE4),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            if (canReact) ...<Widget>[
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _ReactionAction(
                    value: '❤️',
                    action: _MessageMenuAction.reactHeart,
                  ),
                  _ReactionAction(
                    value: '👍',
                    action: _MessageMenuAction.reactLike,
                  ),
                  _ReactionAction(
                    value: '😂',
                    action: _MessageMenuAction.reactLaugh,
                  ),
                  _ReactionAction(
                    value: '😮',
                    action: _MessageMenuAction.reactWow,
                  ),
                  _ReactionAction(
                    value: '😢',
                    action: _MessageMenuAction.reactSad,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 6),
            ],
            if (canReply)
              const _ActionTile(
                icon: Icons.reply_rounded,
                label: 'Reply',
                action: _MessageMenuAction.reply,
              ),
            if (canCopy)
              const _ActionTile(
                icon: Icons.copy_rounded,
                label: 'Copy text',
                action: _MessageMenuAction.copy,
              ),
            if (canEdit)
              const _ActionTile(
                icon: Icons.edit_rounded,
                label: 'Edit',
                action: _MessageMenuAction.edit,
              ),
            if (canRetry)
              const _ActionTile(
                icon: Icons.refresh_rounded,
                label: 'Retry',
                action: _MessageMenuAction.retry,
              ),
            if (canRemoveReaction)
              const _ActionTile(
                icon: Icons.emoji_emotions_outlined,
                label: 'Remove reaction',
                action: _MessageMenuAction.removeReaction,
              ),
            if (canDelete)
              const _ActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                action: _MessageMenuAction.delete,
                destructive: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.action,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final _MessageMenuAction action;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color color = destructive
        ? const Color(0xFFE04D61)
        : const Color(0xFF343A4D);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: Icon(icon, color: color, size: 21),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => Navigator.of(context).pop(action),
    );
  }
}

class _ReactionAction extends StatelessWidget {
  const _ReactionAction({required this.value, required this.action});

  final String value;
  final _MessageMenuAction action;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: () => Navigator.of(context).pop(action),
      radius: 27,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(value, style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}

class _AttachmentTapRegion extends StatelessWidget {
  const _AttachmentTapRegion({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: child,
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xB8000000),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        MessageBubble._formatDuration(duration),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ============================================================================
// END OF FILE
// File: message_bubble.dart
// Location: lib/features/message/widgets/message_bubble.dart
// ============================================================================
