import 'package:flutter/material.dart';

import '../tokens.dart';
import 'text.dart';

/// The primary action: `brand-primary` fill, `text-on-brand` label, full
/// width, `control-md` tall, `radius-md`.
///
/// While [loading] the button keeps its place, shows a small spinner and is
/// disabled, exactly like the Swift button. Pressing it dims the surface to
/// [TainaOpacity.muted]; a disabled button is drawn at
/// [TainaOpacity.disabled].
final class TainaPrimaryButton extends StatelessWidget {
  const TainaPrimaryButton({
    required this.label,
    this.onPressed,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: _style,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              SizedBox(
                width: TainaSizes.controlSm / 2,
                height: TainaSizes.controlSm / 2,
                child: CircularProgressIndicator(
                  strokeWidth: TainaSizes.thick,
                  color: TainaPalette.textOnBrand.withValues(
                    alpha: TainaOpacity.disabled,
                  ),
                  semanticsLabel: 'Carregando',
                ),
              ),
              const SizedBox(width: TainaSpacing.space2),
            ],
            Flexible(
              child: TainaText(
                label,
                style: TainaTypography.label,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final ButtonStyle _style = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return TainaPalette.brandPrimary.withValues(
          alpha: TainaOpacity.disabled,
        );
      }
      return TainaPalette.brandPrimary;
    }),
    foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return TainaPalette.textOnBrand.withValues(
          alpha: TainaOpacity.disabled,
        );
      }
      return TainaPalette.textOnBrand;
    }),
    overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return TainaPalette.bgApp.withValues(alpha: 1 - TainaOpacity.muted);
      }
      return null;
    }),
    minimumSize: const WidgetStatePropertyAll<Size>(
      Size(0, TainaSizes.controlMd),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(
        horizontal: TainaSpacing.space4,
        vertical: TainaSpacing.space3,
      ),
    ),
    textStyle: const WidgetStatePropertyAll<TextStyle>(TainaTypography.label),
    shape: const WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: TainaRadii.mdAll),
    ),
  );
}

/// The quieter action: `surface-raised` fill, `border-default` stroke and a
/// caller-chosen text color, full width and `control-md` tall.
final class TainaSecondaryButton extends StatelessWidget {
  const TainaSecondaryButton({
    required this.label,
    this.onPressed,
    this.textColor = TainaPalette.textPrimary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: _styleFor(textColor),
        child: TainaText(
          label,
          style: TainaTypography.label,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  static ButtonStyle _styleFor(Color textColor) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return TainaPalette.surfaceRaised.withValues(
            alpha: TainaOpacity.disabled,
          );
        }
        return TainaPalette.surfaceRaised;
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return textColor.withValues(alpha: TainaOpacity.disabled);
        }
        return textColor;
      }),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.pressed)) {
          return TainaPalette.bgApp.withValues(alpha: 1 - TainaOpacity.muted);
        }
        return null;
      }),
      side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
        final Color color = states.contains(WidgetState.disabled)
            ? TainaPalette.borderDefault.withValues(
                alpha: TainaOpacity.disabled,
              )
            : TainaPalette.borderDefault;
        return BorderSide(color: color, width: TainaSizes.hairline);
      }),
      minimumSize: const WidgetStatePropertyAll<Size>(
        Size(0, TainaSizes.controlMd),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(
          horizontal: TainaSpacing.space4,
          vertical: TainaSpacing.space3,
        ),
      ),
      textStyle: const WidgetStatePropertyAll<TextStyle>(TainaTypography.label),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: TainaRadii.mdAll),
      ),
    );
  }
}
