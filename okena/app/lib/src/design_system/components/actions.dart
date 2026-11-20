import 'package:flutter/material.dart';

import '../tokens.dart';
import 'icons.dart';

enum TainaButtonKind { primary, secondary, ghost, danger }

enum TainaButtonSize { sm, md, lg }

/// A labeled action with the Button board's kind, size, icon and loading state.
final class TainaButton extends StatelessWidget {
  const TainaButton({
    required this.title,
    this.action,
    this.kind = TainaButtonKind.primary,
    this.size = TainaButtonSize.lg,
    this.icon,
    this.loading = false,
    super.key,
  });

  final String title;
  final VoidCallback? action;
  final TainaButtonKind kind;
  final TainaButtonSize size;
  final TainaIcon? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = action != null && !loading;
    final Color foreground = enabled
        ? _foregroundColor
        : _foregroundColor.withValues(alpha: TainaOpacity.disabled);
    final Color fill = _fillColor;
    final Color? borderColor = _borderColor;

    return Semantics(
      button: true,
      enabled: enabled,
      label: title,
      value: loading ? 'Carregando' : null,
      onTap: enabled ? action : null,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: TainaSizes.touch,
            minHeight: _targetHeight,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? action : null,
              borderRadius: TainaRadii.mdAll,
              child: Center(
                child: Ink(
                  decoration: BoxDecoration(
                    color: enabled
                        ? fill
                        : fill.withValues(alpha: TainaOpacity.disabled),
                    borderRadius: TainaRadii.mdAll,
                    border: borderColor == null
                        ? null
                        : Border.all(
                            color: enabled
                                ? borderColor
                                : borderColor.withValues(
                                    alpha: TainaOpacity.disabled,
                                  ),
                            width: TainaSizes.hairline,
                          ),
                  ),
                  child: SizedBox(
                    height: _controlHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: _horizontalPadding,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (icon != null) ...[
                                TainaIconView(
                                  icon: icon!,
                                  size: TainaSizes.iconMd,
                                  color: foreground,
                                ),
                                const SizedBox(width: TainaSpacing.space2),
                              ],
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _textStyle.copyWith(color: foreground),
                              ),
                            ],
                          ),
                        ),
                        if (loading)
                          Positioned(
                            right: 0,
                            child: TainaIconView(
                              icon: TainaIcon.dots,
                              size: TainaSizes.iconMd,
                              color: foreground,
                            ),
                          ),
                      ],
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

  double get _controlHeight => switch (size) {
    TainaButtonSize.sm => TainaSizes.controlSm,
    TainaButtonSize.md => TainaSizes.controlMd,
    TainaButtonSize.lg => TainaSizes.controlLg,
  };

  double get _targetHeight => switch (size) {
    TainaButtonSize.sm => TainaSizes.touch,
    TainaButtonSize.md => TainaSizes.controlMd,
    TainaButtonSize.lg => TainaSizes.controlLg,
  };

  double get _horizontalPadding => switch (size) {
    TainaButtonSize.sm => TainaSpacing.space3,
    TainaButtonSize.md => TainaSpacing.space4,
    TainaButtonSize.lg => TainaSpacing.space6,
  };

  Color get _foregroundColor => switch (kind) {
    TainaButtonKind.primary => TainaPalette.textOnBrand,
    TainaButtonKind.secondary => TainaPalette.textPrimary,
    TainaButtonKind.ghost => TainaPalette.brandPrimary,
    TainaButtonKind.danger => TainaPalette.actionDanger,
  };

  Color get _fillColor => switch (kind) {
    TainaButtonKind.primary => TainaPalette.brandPrimary,
    TainaButtonKind.secondary => TainaPalette.surfaceDefault,
    TainaButtonKind.ghost || TainaButtonKind.danger => Colors.transparent,
  };

  Color? get _borderColor => switch (kind) {
    TainaButtonKind.primary || TainaButtonKind.ghost => null,
    TainaButtonKind.secondary => TainaPalette.borderStrong,
    TainaButtonKind.danger => TainaPalette.actionDanger,
  };

  TextStyle get _textStyle => switch (size) {
    TainaButtonSize.sm => TainaTypography.bodySm.copyWith(
      fontWeight: FontWeight.w600,
    ),
    TainaButtonSize.md || TainaButtonSize.lg => TainaTypography.label,
  };
}

enum TainaIconButtonKind { defaultAction, danger }

/// A 44-pixel icon-only action with a required accessible [label].
final class TainaIconButton extends StatelessWidget {
  const TainaIconButton({
    required this.icon,
    required this.label,
    required this.action,
    this.kind = TainaIconButtonKind.defaultAction,
    super.key,
  });

  final TainaIcon icon;
  final String label;
  final VoidCallback? action;
  final TainaIconButtonKind kind;

  @override
  Widget build(BuildContext context) {
    final bool enabled = action != null;
    final Color color = kind == TainaIconButtonKind.danger
        ? TainaPalette.actionDanger
        : TainaPalette.textSecondary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: action,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: action,
            borderRadius: TainaRadii.mdAll,
            child: SizedBox(
              width: TainaSizes.touch,
              height: TainaSizes.touch,
              child: Center(
                child: TainaIconView(
                  icon: icon,
                  size: TainaSizes.iconMd,
                  color: enabled
                      ? color
                      : color.withValues(alpha: TainaOpacity.disabled),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The extended mobile action used for file uploads.
final class TainaFAB extends StatelessWidget {
  const TainaFAB({
    required this.label,
    required this.action,
    this.icon = TainaIcon.plus,
    this.uploading = false,
    super.key,
  });

  final String label;
  final VoidCallback? action;
  final TainaIcon icon;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = action != null && !uploading;
    final Color foreground = enabled
        ? TainaPalette.textOnBrand
        : TainaPalette.textOnBrand.withValues(alpha: TainaOpacity.disabled);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: uploading ? 'Enviando' : null,
      onTap: enabled ? action : null,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: enabled
                  ? TainaPalette.brandPrimary
                  : TainaPalette.brandPrimary.withValues(
                      alpha: TainaOpacity.disabled,
                    ),
              borderRadius: TainaRadii.pillAll,
              boxShadow: TainaElevation.lifted,
            ),
            child: InkWell(
              onTap: enabled ? action : null,
              borderRadius: TainaRadii.pillAll,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: TainaSizes.controlLg,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TainaSpacing.space5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TainaIconView(
                        icon: icon,
                        size: TainaSizes.iconMd,
                        color: foreground,
                      ),
                      const SizedBox(width: TainaSpacing.space2),
                      Text(
                        label,
                        style: TainaTypography.label.copyWith(
                          color: foreground,
                        ),
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
