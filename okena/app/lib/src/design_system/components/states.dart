import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';

import '../tokens.dart';
import 'buttons.dart';
import 'surfaces.dart';
import 'text.dart';

/// The empty state: a glyph, a title, a sentence and one optional way out.
final class TainaEmptyState extends StatelessWidget {
  const TainaEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final bool hasAction = actionLabel != null && onAction != null;
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space8),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: TainaFontSizes.display,
              color: TainaPalette.textFaint,
            ),
            const SizedBox(height: TainaSpacing.space4),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TainaText(
                  title,
                  style: TainaTypography.h3,
                  color: TainaPalette.textPrimary,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: TainaSpacing.space2),
                TainaText(
                  message,
                  style: TainaTypography.bodySm,
                  color: TainaPalette.textMuted,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            if (hasAction) ...[
              const SizedBox(height: TainaSpacing.space4),
              TainaSecondaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// The failure, with a way out.
///
/// For an API error the message is the server's own pt-BR sentence; for local
/// errors it is the error's pt-BR description.
final class TainaErrorState extends StatelessWidget {
  const TainaErrorState({required this.error, this.onRetry, super.key});

  final TainaError error;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space5),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: TainaFontSizes.xxl,
              color: TainaPalette.feedbackWarning,
            ),
            const SizedBox(height: TainaSpacing.space4),
            TainaText(
              error.message,
              style: TainaTypography.body,
              color: TainaPalette.textSecondary,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: TainaSpacing.space4),
              TainaSecondaryButton(
                label: 'Tentar de novo',
                onPressed: () => unawaited(onRetry!()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One skeleton block: `surface-raised` in `radius-md`, pulsing like the web's
/// `skeleton-pulse` (1.6s ease-in-out) and only when motion is allowed.
///
/// Callers frame it to the shape of what is loading. The default width takes
/// the available width; pass [width] inside a row.
final class TainaSkeleton extends StatefulWidget {
  const TainaSkeleton({
    this.width = double.infinity,
    this.height = TainaSizes.controlMd,
    this.borderRadius = TainaRadii.mdAll,
    super.key,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<TainaSkeleton> createState() => _TainaSkeletonState();
}

final class _TainaSkeletonState extends State<TainaSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 1,
    end: TainaOpacity.muted,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  bool _configured = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_configured && reduceMotion == _reduceMotion) return;
    _configured = true;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FadeTransition(
          opacity: _opacity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: TainaPalette.surfaceRaised,
              borderRadius: widget.borderRadius,
            ),
          ),
        ),
      ),
    );
  }
}

/// The loading state as a skeleton in the shape of the layout it becomes: a
/// stack of the row cards most screens settle into, never a generic circular
/// spinner.
final class TainaLoadingList extends StatelessWidget {
  const TainaLoadingList({this.itemCount = 4, super.key});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      child: Semantics(
        container: true,
        label: 'Carregando',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int index = 0; index < itemCount; index++) ...[
              if (index > 0) const SizedBox(height: TainaSpacing.space3),
              const TainaRowCard(
                child: Row(
                  children: [
                    TainaSkeleton(
                      width: TainaSizes.controlMd,
                      height: TainaSizes.controlMd,
                    ),
                    SizedBox(width: TainaSpacing.space3),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TainaSkeleton(height: TainaFontSizes.sm),
                          SizedBox(height: TainaSpacing.space2),
                          TainaSkeleton(
                            width: TainaSpacing.space16,
                            height: TainaFontSizes.xs,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
