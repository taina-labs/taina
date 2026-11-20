import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import 'icons.dart';

enum TainaFieldKind { text, password, search, address }

/// A labeled input with help/error text and the Penpot field variants.
final class TainaField extends StatefulWidget {
  const TainaField({
    required this.label,
    this.kind = TainaFieldKind.text,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.help,
    this.errorMessages = const [],
    this.enabled = true,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final TainaFieldKind kind;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final String? help;
  final List<String> errorMessages;
  final bool enabled;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<TainaField> createState() => _TainaFieldState();
}

final class _TainaFieldState extends State<TainaField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  bool _focused = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _attachFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(TainaField oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    final bool hasErrors = widget.errorMessages.isNotEmpty;
    final Color borderColor = hasErrors
        ? TainaPalette.feedbackError
        : _focused
        ? TainaPalette.brandPrimary
        : TainaPalette.borderDefault;
    final double borderWidth = _focused
        ? TainaSizes.thick
        : TainaSizes.hairline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: TainaTypography.label.copyWith(
            color: TainaPalette.textSecondary,
          ),
        ),
        const SizedBox(height: TainaSpacing.space1),
        Semantics(
          label: widget.label,
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText:
                widget.kind == TainaFieldKind.password && !_showPassword,
            keyboardType: _keyboardType,
            keyboardAppearance: Brightness.dark,
            textInputAction: widget.textInputAction,
            textCapitalization: widget.textCapitalization,
            autofillHints: widget.autofillHints,
            inputFormatters: widget.inputFormatters,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            readOnly: widget.readOnly,
            enabled: widget.enabled,
            autocorrect:
                widget.kind != TainaFieldKind.password &&
                widget.kind != TainaFieldKind.address,
            enableSuggestions:
                widget.kind != TainaFieldKind.password &&
                widget.kind != TainaFieldKind.address,
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
              prefixIcon: _leadingIcon,
              prefixIconConstraints: _leadingIcon == null
                  ? null
                  : const BoxConstraints(
                      minWidth: TainaSizes.controlMd,
                      minHeight: TainaSizes.controlMd,
                    ),
              suffixIcon: widget.kind == TainaFieldKind.password
                  ? _passwordToggle
                  : null,
              suffixIconConstraints: widget.kind == TainaFieldKind.password
                  ? const BoxConstraints(
                      minWidth: TainaSizes.touch,
                      minHeight: TainaSizes.touch,
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: TainaSpacing.space3,
                vertical: TainaSpacing.space3,
              ),
              constraints: const BoxConstraints(
                minHeight: TainaSizes.controlMd,
              ),
              border: _border(borderColor, borderWidth),
              enabledBorder: _border(borderColor, borderWidth),
              focusedBorder: _border(borderColor, borderWidth),
              disabledBorder: _border(
                TainaPalette.borderSubtle,
                TainaSizes.hairline,
              ),
            ),
          ),
        ),
        if (hasErrors)
          for (final String message in widget.errorMessages)
            Padding(
              padding: const EdgeInsets.only(top: TainaSpacing.space1),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: TainaTypography.caption.copyWith(
                    color: TainaPalette.feedbackError,
                  ),
                ),
              ),
            )
        else if (widget.help != null)
          Padding(
            padding: const EdgeInsets.only(top: TainaSpacing.space1),
            child: Text(
              widget.help!,
              style: TainaTypography.caption.copyWith(
                color: TainaPalette.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  TextInputType? get _keyboardType => switch (widget.kind) {
    TainaFieldKind.search => TextInputType.text,
    TainaFieldKind.address => TextInputType.url,
    _ => widget.keyboardType,
  };

  Widget? get _leadingIcon => switch (widget.kind) {
    TainaFieldKind.search => const Padding(
      padding: EdgeInsets.only(
        left: TainaSpacing.space3,
        right: TainaSpacing.space2,
      ),
      child: TainaIconView(
        icon: TainaIcon.search,
        size: TainaSizes.iconMd,
        color: TainaPalette.textFaint,
      ),
    ),
    TainaFieldKind.address => const Padding(
      padding: EdgeInsets.only(
        left: TainaSpacing.space3,
        right: TainaSpacing.space2,
      ),
      child: TainaIconView(
        icon: TainaIcon.servidor,
        size: TainaSizes.iconMd,
        color: TainaPalette.textFaint,
      ),
    ),
    TainaFieldKind.text || TainaFieldKind.password => null,
  };

  Widget get _passwordToggle {
    final String label = _showPassword ? 'Ocultar senha' : 'Mostrar senha';
    final String visibleText = _showPassword ? 'Ocultar' : 'Mostrar';

    return Semantics(
      button: true,
      label: label,
      toggled: _showPassword,
      onTap: _togglePassword,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: _togglePassword,
          style: TextButton.styleFrom(
            minimumSize: const Size(TainaSizes.touch, TainaSizes.touch),
            padding: const EdgeInsets.symmetric(
              horizontal: TainaSpacing.space2,
            ),
            foregroundColor: TainaPalette.brandPrimary,
            textStyle: TainaTypography.label,
            shape: const RoundedRectangleBorder(borderRadius: TainaRadii.mdAll),
          ),
          child: Text(visibleText),
        ),
      ),
    );
  }

  void _togglePassword() {
    setState(() => _showPassword = !_showPassword);
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

  OutlineInputBorder _border(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: TainaRadii.mdAll,
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// One selectable option in a [TainaSegmented] control.
final class TainaSegmentOption<T> {
  const TainaSegmentOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// A controlled, equally divided segmented selection.
final class TainaSegmented<T> extends StatelessWidget {
  const TainaSegmented({
    required this.label,
    required this.options,
    required this.selection,
    required this.onChanged,
    super.key,
  });

  final String label;
  final List<TainaSegmentOption<T>> options;
  final T selection;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final TainaSegmentOption<T>? selected = _selectedOption;

    return Semantics(
      container: true,
      label: label,
      value: selected?.label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TainaPalette.fieldBg,
          border: Border.all(
            color: TainaPalette.borderDefault,
            width: TainaSizes.hairline,
          ),
          borderRadius: TainaRadii.pillAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(TainaSpacing.space1),
          child: Row(
            children: [
              for (final TainaSegmentOption<T> option in options)
                Expanded(
                  child: _SegmentOptionButton<T>(
                    option: option,
                    selected: option.value == selection,
                    enabled: onChanged != null,
                    onTap: onChanged == null
                        ? null
                        : () => onChanged!(option.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  TainaSegmentOption<T>? get _selectedOption {
    for (final TainaSegmentOption<T> option in options) {
      if (option.value == selection) return option;
    }
    return null;
  }
}

final class _SegmentOptionButton<T> extends StatelessWidget {
  const _SegmentOptionButton({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TainaSegmentOption<T> option;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected
        ? TainaPalette.textPrimary
        : TainaPalette.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: option.label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? TainaPalette.surfaceRaised : Colors.transparent,
              borderRadius: TainaRadii.pillAll,
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: TainaRadii.pillAll,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: TainaSizes.touch),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TainaSpacing.space3,
                    ),
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TainaTypography.label.copyWith(
                        color: enabled
                            ? foreground
                            : foreground.withValues(
                                alpha: TainaOpacity.disabled,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A selectable card for one option in a radio group.
final class TainaRadioCard extends StatelessWidget {
  const TainaRadioCard({
    required this.title,
    required this.selected,
    required this.action,
    this.description,
    super.key,
  });

  final String title;
  final String? description;
  final bool selected;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = selected
        ? TainaPalette.brandPrimary
        : TainaPalette.borderStrong;

    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: action != null,
      label: description == null ? title : '$title. $description',
      onTap: action,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: TainaPalette.surfaceRaised,
              border: Border.all(
                color: borderColor.withValues(
                  alpha: action == null ? TainaOpacity.muted : null,
                ),
                width: TainaSizes.hairline,
              ),
              borderRadius: TainaRadii.mdAll,
            ),
            child: InkWell(
              onTap: action,
              borderRadius: TainaRadii.mdAll,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: TainaSizes.controlLg,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(TainaSpacing.space4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TainaTypography.body.copyWith(
                                color: selected
                                    ? TainaPalette.textPrimary
                                    : TainaPalette.textSecondary,
                              ),
                            ),
                            if (description != null) ...[
                              const SizedBox(height: TainaSpacing.space1),
                              Text(
                                description!,
                                style: TainaTypography.caption.copyWith(
                                  color: TainaPalette.textFaint,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: TainaSpacing.space3),
                      _RadioIndicator(
                        selected: selected,
                        enabled: action != null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _RadioIndicator extends StatelessWidget {
  const _RadioIndicator({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: TainaSizes.badge,
      height: TainaSizes.badge,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? TainaPalette.brandPrimary
              : TainaPalette.borderDefault,
          width: TainaSizes.thick,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: TainaSpacing.space3,
              height: TainaSpacing.space3,
              decoration: BoxDecoration(
                color: enabled
                    ? TainaPalette.brandPrimary
                    : TainaPalette.brandPrimary.withValues(
                        alpha: TainaOpacity.muted,
                      ),
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}
