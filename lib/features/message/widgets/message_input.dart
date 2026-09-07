// ============================================================================
// JR CALL
// File: message_input.dart
// Location: lib/features/message/widgets/message_input.dart
//
// Composer presentation widget for durable messages and JR CALL Live Chat.
// UI only: no Firestore, Storage, repository, authentication, or Call Engine.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef MessageInputTextChanged = void Function(String value);
typedef MessageInputSubmit = void Function(String value);

class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSend,
    this.focusNode,
    this.onAttachmentPressed,
    this.onVoicePressed,
    this.onTypingChanged,
    this.onLiveChatChanged,
    this.onCancelReply,
    this.onCancelEdit,
    this.replyPreview,
    this.replySenderName,
    this.editPreview,
    this.liveChatEnabled = false,
    this.isSending = false,
    this.enabled = true,
    this.voiceEnabled = true,
    this.attachmentEnabled = true,
    this.liveChatAvailable = true,
    this.maxLines = 6,
    this.maxLength = 10000,
    this.hintText = 'Message',
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  final MessageInputTextChanged onChanged;
  final MessageInputSubmit onSend;

  final VoidCallback? onAttachmentPressed;
  final VoidCallback? onVoicePressed;
  final ValueChanged<bool>? onTypingChanged;
  final ValueChanged<bool>? onLiveChatChanged;

  final VoidCallback? onCancelReply;
  final VoidCallback? onCancelEdit;

  final String? replyPreview;
  final String? replySenderName;
  final String? editPreview;

  final bool liveChatEnabled;
  final bool isSending;
  final bool enabled;
  final bool voiceEnabled;
  final bool attachmentEnabled;
  final bool liveChatAvailable;

  final int maxLines;
  final int maxLength;
  final String hintText;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  bool _hasText = false;
  bool _typingReported = false;

  bool get _canInteract => widget.enabled && !widget.isSending;

  bool get _hasReply =>
      widget.replyPreview != null && widget.replyPreview!.trim().isNotEmpty;

  bool get _hasEdit =>
      widget.editPreview != null && widget.editPreview!.trim().isNotEmpty;

  bool get _canSend => _canInteract && _hasText;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _hasText = widget.controller.text.trim().isNotEmpty;
    }

    if ((!widget.enabled || widget.isSending) && _typingReported) {
      _reportTyping(false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);

    if (_typingReported) {
      widget.onTypingChanged?.call(false);
    }

    super.dispose();
  }

  void _handleControllerChanged() {
    final bool hasText = widget.controller.text.trim().isNotEmpty;

    if (_hasText != hasText && mounted) {
      setState(() {
        _hasText = hasText;
      });
    }

    if (!_canInteract) {
      _reportTyping(false);
      return;
    }

    _reportTyping(hasText);
  }

  void _reportTyping(bool typing) {
    if (_typingReported == typing) {
      return;
    }

    _typingReported = typing;
    widget.onTypingChanged?.call(typing);
  }

  void _handleTextChanged(String value) {
    widget.onChanged(value);

    if (!_canInteract) {
      _reportTyping(false);
      return;
    }

    _reportTyping(value.trim().isNotEmpty);
  }

  void _handleSend() {
    if (!_canSend) {
      return;
    }

    final String value = widget.controller.text.trim();

    if (value.isEmpty) {
      return;
    }

    _reportTyping(false);
    widget.onSend(value);
  }

  void _handleSubmitted(String value) {
    if (!_canSend) {
      return;
    }

    final String normalized = value.trim();

    if (normalized.isEmpty) {
      return;
    }

    _reportTyping(false);
    widget.onSend(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final bool keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFAFFFFFF),
            border: Border(top: BorderSide(color: Color(0xFFE9EAF0))),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x0A1E2740),
                blurRadius: 14,
                offset: Offset(0, -3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_hasReply || _hasEdit) _buildContextPreview(),
              if (widget.liveChatAvailable) _buildLiveChatBar(),
              Padding(
                padding: EdgeInsets.fromLTRB(8, 6, 8, keyboardVisible ? 6 : 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _buildAttachmentButton(),
                    const SizedBox(width: 6),
                    Expanded(child: _buildTextField()),
                    const SizedBox(width: 6),
                    _buildTrailingAction(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContextPreview() {
    final bool editing = _hasEdit;
    final String preview = editing
        ? widget.editPreview!.trim()
        : widget.replyPreview!.trim();

    final String title = editing
        ? 'Editing message'
        : (widget.replySenderName?.trim().isNotEmpty ?? false)
        ? 'Replying to ${widget.replySenderName!.trim()}'
        : 'Replying';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 9, 12, 1),
      padding: const EdgeInsets.fromLTRB(11, 8, 7, 8),
      decoration: BoxDecoration(
        color: editing ? const Color(0xFFF4F1FF) : const Color(0xFFF7F5FF),
        borderRadius: BorderRadius.circular(13),
        border: const Border(
          left: BorderSide(color: Color(0xFF705AE9), width: 3),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            editing ? Icons.edit_rounded : Icons.reply_rounded,
            size: 18,
            color: const Color(0xFF6654D9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6554D8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF73798A),
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: editing ? 'Cancel edit' : 'Cancel reply',
            visualDensity: VisualDensity.compact,
            onPressed: editing ? widget.onCancelEdit : widget.onCancelReply,
            icon: const Icon(
              Icons.close_rounded,
              size: 19,
              color: Color(0xFF858A99),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveChatBar() {
    final bool active = widget.liveChatEnabled;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 1),
      child: Semantics(
        button: true,
        toggled: active,
        label: active ? 'Live Chat enabled' : 'Live Chat disabled',
        child: InkWell(
          onTap: !_canInteract || widget.onLiveChatChanged == null
              ? null
              : () => widget.onLiveChatChanged!(!active),
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              gradient: active
                  ? const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: <Color>[Color(0xFFF1ECFF), Color(0xFFFFEDF7)],
                    )
                  : null,
              color: active ? null : const Color(0xFFF7F7FA),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: active
                    ? const Color(0xFFDCCEFF)
                    : const Color(0xFFE8E8EF),
              ),
            ),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 27,
                  height: 27,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: active
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              Color(0xFF755BE8),
                              Color(0xFFE75BA7),
                            ],
                          )
                        : null,
                    color: active ? null : const Color(0xFFE9E9EF),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: active ? Colors.white : const Color(0xFF858A99),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Live Chat',
                        style: TextStyle(
                          color: active
                              ? const Color(0xFF5E4BCB)
                              : const Color(0xFF666C7C),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        active
                            ? 'Live text is visible while you type'
                            : 'Share ephemeral text while typing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8A8F9E),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: active,
                  onChanged: !_canInteract || widget.onLiveChatChanged == null
                      ? null
                      : widget.onLiveChatChanged,
                  activeTrackColor: const Color(0xFFB9A9F7),
                  activeThumbColor: const Color(0xFF6554E8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentButton() {
    final bool enabled =
        _canInteract &&
        widget.attachmentEnabled &&
        widget.onAttachmentPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Add attachment',
      child: Material(
        color: const Color(0xFFF3F2F8),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? widget.onAttachmentPressed : null,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              Icons.add_rounded,
              size: 26,
              color: enabled
                  ? const Color(0xFF6554E8)
                  : const Color(0xFFB9BBC5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(
          color: widget.liveChatEnabled
              ? const Color(0xFFD8CCFA)
              : const Color(0xFFE5E6EC),
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        readOnly: widget.isSending,
        minLines: 1,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        autofillHints: null,
        enableSuggestions: true,
        autocorrect: true,
        smartDashesType: SmartDashesType.enabled,
        smartQuotesType: SmartQuotesType.enabled,
        enableIMEPersonalizedLearning: true,
        inputFormatters: <TextInputFormatter>[
          LengthLimitingTextInputFormatter(widget.maxLength),
        ],
        onChanged: _handleTextChanged,
        onSubmitted: _handleSubmitted,
        decoration: InputDecoration(
          hintText: widget.liveChatEnabled
              ? 'Type live or send normally...'
              : widget.hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF9A9EAB),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          counterText: '',
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 11,
          ),
        ),
        style: const TextStyle(
          color: Color(0xFF242938),
          fontSize: 14.5,
          height: 1.3,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildTrailingAction() {
    if (widget.isSending) {
      return const SizedBox(
        width: 42,
        height: 42,
        child: Padding(
          padding: EdgeInsets.all(11),
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Color(0xFF6554E8),
          ),
        ),
      );
    }

    if (_hasText) {
      return _buildSendButton();
    }

    return _buildVoiceButton();
  }

  Widget _buildSendButton() {
    return Semantics(
      button: true,
      enabled: _canSend,
      label: _hasEdit ? 'Save edited message' : 'Send message',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _canSend ? _handleSend : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _canSend
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0xFF4F7EF7),
                        Color(0xFF705AE9),
                        Color(0xFFD858A8),
                      ],
                    )
                  : null,
              color: _canSend ? null : const Color(0xFFE5E6EC),
              boxShadow: _canSend
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x286655E8),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              _hasEdit ? Icons.check_rounded : Icons.send_rounded,
              size: 20,
              color: _canSend ? Colors.white : const Color(0xFFA9ADB9),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceButton() {
    final bool enabled =
        _canInteract && widget.voiceEnabled && widget.onVoicePressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Voice message',
      child: Material(
        color: const Color(0xFFF3F2F8),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? widget.onVoicePressed : null,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              Icons.mic_rounded,
              size: 21,
              color: enabled
                  ? const Color(0xFF7557DD)
                  : const Color(0xFFB9BBC5),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// END OF FILE
// File: message_input.dart
// Location: lib/features/message/widgets/message_input.dart
// ============================================================================
