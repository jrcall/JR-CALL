import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/jr_colors.dart';
import '../core/theme/jr_radius.dart';
import '../core/theme/jr_typography.dart';

/// ===============================================================
/// JR CALL — Premium Reusable Input Field
/// File: jr_input_field.dart
/// Location: lib/widgets/jr_input_field.dart
///
/// DESIGN:
/// Premium Light UI
/// Modern Glassmorphism
/// Soft Neon / Blue Focus
///
/// PURPOSE:
/// JR CALL-এর Login, Create Account, Profile, Settings এবং
/// অন্যান্য form screen-এর input UI এক জায়গা থেকে নিয়ন্ত্রণ করা.
///
/// IMPORTANT:
/// - Authentication fields proper autofill support করে.
/// - Public profile fields-এ autofillHints না দিলে
///   Google Password Manager trigger করার প্রয়োজন নেই.
/// - Firebase/Auth/Call business logic এই widget-এর ভিতরে থাকবে না.
/// ===============================================================
class JrInputField extends StatefulWidget {
  const JrInputField({
    required this.controller,
    super.key,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixPressed,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofillHints,
    this.inputFormatters,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.enablePasswordToggle = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.prefix,
    this.suffix,
    this.onTap,
  }) : assert(maxLines > 0),
       assert(minLines == null || minLines > 0),
       assert(
         minLines == null || minLines <= maxLines,
         'minLines cannot be greater than maxLines.',
       ),
       assert(
         !obscureText || maxLines == 1,
         'Obscured fields must use maxLines: 1.',
       );

  // =============================================================
  // CORE
  // =============================================================

  final TextEditingController controller;
  final FocusNode? focusNode;

  final String? label;
  final String? hint;

  // =============================================================
  // ICONS / CONTENT
  // =============================================================

  final IconData? prefixIcon;
  final IconData? suffixIcon;

  final VoidCallback? onSuffixPressed;

  final Widget? prefix;
  final Widget? suffix;

  // =============================================================
  // INPUT BEHAVIOR
  // =============================================================

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  final bool enabled;
  final bool readOnly;

  final bool obscureText;

  /// Password fields-এ eye icon দেখানোর জন্য।
  final bool enablePasswordToggle;

  final bool enableSuggestions;
  final bool autocorrect;

  final int maxLines;
  final int? minLines;
  final int? maxLength;

  final TextCapitalization textCapitalization;

  final Iterable<String>? autofillHints;

  final List<TextInputFormatter>? inputFormatters;

  // =============================================================
  // CALLBACKS
  // =============================================================

  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  @override
  State<JrInputField> createState() => _JrInputFieldState();
}

class _JrInputFieldState extends State<JrInputField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
  }

  @override
  void didUpdateWidget(covariant JrInputField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.obscureText != widget.obscureText) {
      _obscureText = widget.obscureText;
    }
  }

  void _togglePasswordVisibility() {
    if (!widget.enabled || widget.readOnly) {
      return;
    }

    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showPasswordToggle =
        widget.enablePasswordToggle && widget.obscureText;

    final Widget? suffixWidget = _buildSuffix(
      showPasswordToggle: showPasswordToggle,
    );

    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,

      enabled: widget.enabled,
      readOnly: widget.readOnly,

      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,

      obscureText: _obscureText,

      enableSuggestions: widget.obscureText ? false : widget.enableSuggestions,

      autocorrect: widget.obscureText ? false : widget.autocorrect,

      textCapitalization: widget.textCapitalization,

      autofillHints: widget.autofillHints,

      inputFormatters: widget.inputFormatters,

      maxLines: widget.obscureText ? 1 : widget.maxLines,
      minLines: widget.obscureText ? 1 : widget.minLines,
      maxLength: widget.maxLength,

      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      onTap: widget.onTap,

      style: JrTypography.inputText,

      cursorColor: JrColors.primaryBlue,

      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,

        labelStyle: JrTypography.inputLabel,
        floatingLabelStyle: JrTypography.inputLabel.copyWith(
          color: JrColors.primaryBlue,
          fontWeight: FontWeight.w700,
        ),

        hintStyle: JrTypography.inputHint,

        errorStyle: JrTypography.inputError,

        counterStyle: JrTypography.metadata,

        filled: true,
        fillColor: widget.enabled
            ? JrColors.surfaceGlass
            : JrColors.disabled.withValues(alpha: 0.12),

        prefixIcon: widget.prefixIcon == null
            ? null
            : Icon(
                widget.prefixIcon,
                color: widget.enabled
                    ? JrColors.primaryBlue
                    : JrColors.disabled,
                size: 23,
              ),

        prefix: widget.prefix,

        suffixIcon: suffixWidget,
        suffix: widget.suffix,

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),

        border: _border(color: JrColors.border, width: 1),

        enabledBorder: _border(color: JrColors.border, width: 1),

        disabledBorder: _border(
          color: JrColors.border.withValues(alpha: 0.55),
          width: 1,
        ),

        focusedBorder: _border(color: JrColors.primaryBlue, width: 1.6),

        errorBorder: _border(color: JrColors.error, width: 1.2),

        focusedErrorBorder: _border(color: JrColors.error, width: 1.6),

        errorMaxLines: 2,
      ),
    );
  }

  Widget? _buildSuffix({required bool showPasswordToggle}) {
    if (showPasswordToggle) {
      return IconButton(
        tooltip: _obscureText ? 'Show password' : 'Hide password',
        onPressed: _togglePasswordVisibility,
        icon: Icon(
          _obscureText
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          color: JrColors.primaryBlue,
          size: 23,
        ),
      );
    }

    if (widget.suffixIcon != null) {
      if (widget.onSuffixPressed != null) {
        return IconButton(
          onPressed: widget.enabled ? widget.onSuffixPressed : null,
          icon: Icon(
            widget.suffixIcon,
            color: widget.enabled ? JrColors.primaryBlue : JrColors.disabled,
            size: 23,
          ),
        );
      }

      return Icon(
        widget.suffixIcon,
        color: widget.enabled ? JrColors.textSecondary : JrColors.disabled,
        size: 23,
      );
    }

    return null;
  }

  OutlineInputBorder _border({required Color color, required double width}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(JrRadius.input),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
