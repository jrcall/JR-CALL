// ============================================================================
// JR CALL
// File: attachment_button.dart
// Location: lib/features/message/widgets/attachment_button.dart
//
// Pure attachment-action presentation.
// Emits only the selected attachment action.
// Permission, picker, validation, recording, upload, Firestore, and Storage
// logic remain outside this widget.
// ============================================================================

import 'package:flutter/material.dart';

enum AttachmentAction { image, video, audio, voice, file }

class AttachmentButton extends StatelessWidget {
  const AttachmentButton({
    super.key,
    required this.onSelected,
    this.enabled = true,
    this.showVoice = true,
    this.tooltip = 'Attachments',
    this.iconSize = 22,
    this.buttonSize = 42,
  });

  final ValueChanged<AttachmentAction> onSelected;
  final bool enabled;
  final bool showVoice;
  final String tooltip;
  final double iconSize;
  final double buttonSize;

  static const Color _jrBlue = Color(0xFF3978F6);
  static const Color _messagePurple = Color(0xFF7157E8);
  static const Color _messagePink = Color(0xFFE45AA7);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => _openAttachmentSheet(context) : null,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: buttonSize,
              child: Center(
                child: Icon(
                  Icons.add_rounded,
                  size: iconSize,
                  color: enabled
                      ? _messagePurple
                      : Theme.of(context).disabledColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAttachmentSheet(BuildContext context) async {
    if (!enabled) {
      return;
    }

    final AttachmentAction? action =
        await showModalBottomSheet<AttachmentAction>(
          context: context,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.22),
          builder: (BuildContext sheetContext) {
            return _AttachmentSheet(showVoice: showVoice);
          },
        );

    if (action != null) {
      onSelected(action);
    }
  }
}

class _AttachmentSheet extends StatelessWidget {
  const _AttachmentSheet({required this.showVoice});

  final bool showVoice;

  @override
  Widget build(BuildContext context) {
    final List<_AttachmentOption> options = <_AttachmentOption>[
      const _AttachmentOption(
        action: AttachmentAction.image,
        icon: Icons.image_rounded,
        label: 'Image',
        description: 'Choose a photo',
        foreground: Color(0xFF3978F6),
        background: Color(0xFFEAF1FF),
      ),
      const _AttachmentOption(
        action: AttachmentAction.video,
        icon: Icons.videocam_rounded,
        label: 'Video',
        description: 'Choose a video',
        foreground: Color(0xFF7157E8),
        background: Color(0xFFF0ECFF),
      ),
      const _AttachmentOption(
        action: AttachmentAction.audio,
        icon: Icons.headphones_rounded,
        label: 'Audio',
        description: 'Choose an audio file',
        foreground: Color(0xFFE45AA7),
        background: Color(0xFFFFECF6),
      ),
      if (showVoice)
        const _AttachmentOption(
          action: AttachmentAction.voice,
          icon: Icons.mic_rounded,
          label: 'Voice',
          description: 'Record a voice message',
          foreground: Color(0xFF8C55E9),
          background: Color(0xFFF3ECFF),
        ),
      const _AttachmentOption(
        action: AttachmentAction.file,
        icon: Icons.insert_drive_file_rounded,
        label: 'Document',
        description: 'Choose a document or file',
        foreground: Color(0xFF536477),
        background: Color(0xFFEEF2F6),
      ),
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFEFDFF),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFECE8F5)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFD9D7DF),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        AttachmentButton._jrBlue,
                        AttachmentButton._messagePurple,
                        AttachmentButton._messagePink,
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 21,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Add attachment',
                        style: TextStyle(
                          color: Color(0xFF202534),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Choose what you want to send',
                        style: TextStyle(
                          color: Color(0xFF858A98),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: options.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (BuildContext context, int index) {
                return _AttachmentOptionTile(option: options[index]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentOption {
  const _AttachmentOption({
    required this.action,
    required this.icon,
    required this.label,
    required this.description,
    required this.foreground,
    required this.background,
  });

  final AttachmentAction action;
  final IconData icon;
  final String label;
  final String description;
  final Color foreground;
  final Color background;
}

class _AttachmentOptionTile extends StatelessWidget {
  const _AttachmentOptionTile({required this.option});

  final _AttachmentOption option;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: option.label,
      hint: option.description,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop(option.action);
          },
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFFAF9FD),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFECE9F3)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: option.background,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      option.icon,
                      size: 23,
                      color: option.foreground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF303544),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// END OF FILE
// File: attachment_button.dart
// Location: lib/features/message/widgets/attachment_button.dart
// ============================================================================
