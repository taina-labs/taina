import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import 'actions.dart';
import 'icons.dart';
import 'text.dart';

/// A modal bottom sheet with a persistent title and a visible close action.
final class TainaSheet extends StatelessWidget {
  const TainaSheet({
    required this.title,
    required this.child,
    this.onClose,
    super.key,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    bool isScrollControlled = false,
    bool useRootNavigator = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return TainaSheet(
          title: title,
          onClose: () => Navigator.of(sheetContext).maybePop(),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TainaPalette.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TainaRadii.xl),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: TainaSpacing.space2),
              child: Center(
                child: Container(
                  width: TainaSizes.controlSm,
                  height: TainaSpacing.space1,
                  decoration: const BoxDecoration(
                    color: TainaPalette.surfaceDim,
                    borderRadius: TainaRadii.pillAll,
                  ),
                ),
              ),
            ),
            const SizedBox(height: TainaSpacing.space1),
            SizedBox(
              height: TainaSizes.controlLg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TainaSpacing.space4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TainaText(
                        title,
                        style: TainaTypography.h3,
                        color: TainaPalette.textPrimary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed:
                          onClose ?? () => Navigator.of(context).maybePop(),
                      style: TextButton.styleFrom(
                        foregroundColor: TainaPalette.textPrimary,
                        minimumSize: const Size(
                          TainaSizes.touch,
                          TainaSizes.controlMd,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: TainaSpacing.space4,
                        ),
                      ),
                      child: const TainaText(
                        'Fechar',
                        style: TainaTypography.label,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(
              height: TainaSizes.hairline,
              thickness: TainaSizes.hairline,
              color: TainaPalette.borderSubtle,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: TainaSpacing.space4),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An action that can be presented by [ActionsMenu].
final class TainaMenuAction {
  const TainaMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final TainaIcon icon;
  final VoidCallback onSelected;
  final bool destructive;
  final bool enabled;
}

/// Shows a short list of actions in a bottom sheet instead of a platform menu.
abstract final class ActionsMenu {
  static Future<void> show({
    required BuildContext context,
    required List<TainaMenuAction> actions,
    String title = 'Ações do arquivo',
    bool useRootNavigator = false,
  }) {
    return TainaSheet.show<void>(
      context: context,
      title: title,
      useRootNavigator: useRootNavigator,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int index = 0; index < actions.length; index++) ...[
            if (index > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
                child: Divider(
                  height: TainaSizes.hairline,
                  thickness: TainaSizes.hairline,
                  color: TainaPalette.borderSubtle,
                ),
              ),
            _MenuActionRow(action: actions[index]),
          ],
        ],
      ),
    );
  }
}

final class _MenuActionRow extends StatelessWidget {
  const _MenuActionRow({required this.action});

  final TainaMenuAction action;

  @override
  Widget build(BuildContext context) {
    final Color color = action.destructive
        ? TainaPalette.feedbackError
        : TainaPalette.textPrimary;
    return Semantics(
      button: true,
      enabled: action.enabled,
      label: action.label,
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: TainaPalette.surfaceRaised,
          child: InkWell(
            onTap: action.enabled
                ? () {
                    final VoidCallback callback = action.onSelected;
                    Navigator.of(context).pop();
                    callback();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TainaSpacing.space4,
              ),
              child: SizedBox(
                height: TainaSizes.controlLg,
                child: Row(
                  children: [
                    TainaIconView(
                      icon: action.icon,
                      color: color,
                      size: TainaSizes.iconMd,
                    ),
                    const SizedBox(width: TainaSpacing.space3),
                    Expanded(
                      child: TainaText(
                        action.label,
                        style: TainaTypography.body,
                        color: color,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A themed confirmation dialog with equally weighted safe and confirm actions.
final class TainaDialog extends StatelessWidget {
  const TainaDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.isDestructive = false,
    super.key,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool isDestructive;

  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String cancelLabel = 'Cancelar',
    String confirmLabel = 'Continuar',
    VoidCallback? onConfirm,
    bool useRootNavigator = true,
  }) {
    return _show(
      context: context,
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      onConfirm: onConfirm,
      useRootNavigator: useRootNavigator,
    );
  }

  static Future<bool?> destructive({
    required BuildContext context,
    required String title,
    required String message,
    String cancelLabel = 'Cancelar',
    required String confirmLabel,
    VoidCallback? onConfirm,
    bool useRootNavigator = true,
  }) {
    return _show(
      context: context,
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      onConfirm: onConfirm,
      destructive: true,
      useRootNavigator: useRootNavigator,
    );
  }

  static Future<bool?> _show({
    required BuildContext context,
    required String title,
    required String message,
    required String cancelLabel,
    required String confirmLabel,
    required VoidCallback? onConfirm,
    bool destructive = false,
    required bool useRootNavigator,
  }) {
    return showDialog<bool>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (BuildContext dialogContext) {
        return TainaDialog(
          title: title,
          message: message,
          cancelLabel: cancelLabel,
          confirmLabel: confirmLabel,
          isDestructive: destructive,
          onCancel: () => Navigator.of(dialogContext).pop(false),
          onConfirm: () {
            if (destructive) unawaited(HapticFeedback.lightImpact());
            Navigator.of(dialogContext).pop(true);
            onConfirm?.call();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double buttonWidth = _equalActionWidth(context);
    return AlertDialog(
      backgroundColor: TainaPalette.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: TainaRadii.lgAll),
      title: TainaText(
        title,
        style: TainaTypography.h3,
        color: TainaPalette.textPrimary,
      ),
      content: TainaText(
        message,
        style: TainaTypography.bodySm,
        color: TainaPalette.textSecondary,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        TainaSpacing.space4,
        0,
        TainaSpacing.space4,
        TainaSpacing.space4,
      ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: buttonWidth,
              child: TainaButton(
                title: cancelLabel,
                action: onCancel,
                kind: TainaButtonKind.secondary,
                size: TainaButtonSize.md,
              ),
            ),
            const SizedBox(width: TainaSpacing.space3),
            SizedBox(
              width: buttonWidth,
              child: TainaButton(
                title: confirmLabel,
                action: onConfirm,
                kind: isDestructive
                    ? TainaButtonKind.danger
                    : TainaButtonKind.secondary,
                size: TainaButtonSize.md,
              ),
            ),
          ],
        ),
      ],
    );
  }

  double _equalActionWidth(BuildContext context) {
    final TextDirection textDirection = Directionality.of(context);
    final TextScaler textScaler = MediaQuery.textScalerOf(context);

    double labelWidth(String label) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: label, style: TainaTypography.label),
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      return painter.width;
    }

    return math.max(labelWidth(cancelLabel), labelWidth(confirmLabel)) +
        TainaSpacing.space4 * 2 +
        TainaSizes.hairline * 2;
  }
}
