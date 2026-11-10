import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import 'text.dart';

/// The labeled form field: `field-bg` fill, `border-default` stroke, the
/// focus ring in `brand-primary`, and the field's error messages in
/// `feedback-error`.
///
/// The label, help and errors are rendered here, not by [InputDecoration],
/// so a field can show every server message at once and keep the Swift
/// layout: 4px between the parts, errors instead of help while they exist.
final class TainaTextField extends StatefulWidget {
  const TainaTextField({
    required this.label,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.help,
    this.errorMessages = const [],
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.readOnly = false,
    this.enabled = true,
    this.maxLines = 1,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final String? help;
  final List<String> errorMessages;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;
  final bool enabled;
  final int maxLines;

  @override
  State<TainaTextField> createState() => _TainaTextFieldState();
}

final class _TainaTextFieldState extends State<TainaTextField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _attachFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(TainaTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _detachFocusNode();
      _attachFocusNode(widget.focusNode);
    }
  }

  @override
  void dispose() {
    _detachFocusNode();
    super.dispose();
  }

  void _attachFocusNode(FocusNode? node) {
    _focusNode = node ?? FocusNode();
    _ownsFocusNode = node == null;
    _focused = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChange);
  }

  void _detachFocusNode() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasErrors = widget.errorMessages.isNotEmpty;
    final Color strokeColor = hasErrors
        ? TainaPalette.feedbackError
        : _focused
        ? TainaPalette.brandPrimary
        : TainaPalette.borderDefault;
    final double strokeWidth = _focused
        ? TainaSizes.thick
        : TainaSizes.hairline;
    final OutlineInputBorder border = _border(strokeColor, strokeWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TainaText(
          widget.label,
          style: TainaTypography.label,
          color: TainaPalette.textSecondary,
        ),
        const SizedBox(height: TainaSpacing.space1),
        Semantics(
          label: widget.label,
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            keyboardAppearance: Brightness.dark,
            textInputAction: widget.textInputAction,
            textCapitalization: widget.textCapitalization,
            autofillHints: widget.autofillHints,
            inputFormatters: widget.inputFormatters,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            readOnly: widget.readOnly,
            enabled: widget.enabled,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            autocorrect: false,
            enableSuggestions: !widget.obscureText,
            cursorColor: TainaPalette.brandPrimary,
            style: TainaTypography.body.copyWith(
              color: TainaPalette.textPrimary,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: TainaPalette.fieldBg,
              isDense: true,
              hintText: widget.placeholder,
              hintStyle: TainaTypography.body.copyWith(
                color: TainaPalette.textFaint,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: TainaSpacing.space3,
                vertical: TainaSpacing.space3,
              ),
              constraints: const BoxConstraints(
                minHeight: TainaSizes.controlMd,
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: border,
              disabledBorder: _border(
                TainaPalette.borderSubtle,
                TainaSizes.hairline,
              ),
              errorBorder: _border(
                TainaPalette.feedbackError,
                TainaSizes.hairline,
              ),
              focusedErrorBorder: _border(
                TainaPalette.feedbackError,
                TainaSizes.thick,
              ),
            ),
          ),
        ),
        for (final String message in widget.errorMessages)
          Padding(
            padding: const EdgeInsets.only(top: TainaSpacing.space1),
            child: TainaText(
              message,
              style: TainaTypography.caption,
              color: TainaPalette.feedbackError,
            ),
          ),
        if (!hasErrors && widget.help != null)
          Padding(
            padding: const EdgeInsets.only(top: TainaSpacing.space1),
            child: TainaText(
              widget.help!,
              style: TainaTypography.caption,
              color: TainaPalette.textMuted,
            ),
          ),
      ],
    );
  }

  OutlineInputBorder _border(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: TainaRadii.mdAll,
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
