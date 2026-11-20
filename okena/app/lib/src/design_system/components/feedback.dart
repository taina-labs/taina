import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../tokens.dart';
import 'actions.dart';
import 'content.dart';
import 'icons.dart';

enum TainaSkeletonKind { listRow, photoGrid, card }

enum TainaToastKind { info, error }

/// A quiet empty state with one optional way forward.
final class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.actionBuilder,
    super.key,
  });

  final TainaIcon icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final WidgetBuilder? actionBuilder;

  @override
  Widget build(BuildContext context) {
    final WidgetBuilder? builder = actionBuilder;
    final bool hasAction =
        builder != null || (actionLabel != null && onAction != null);

    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space6),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: TainaIconView(
                icon: icon,
                size: TainaSizes.iconMd,
                color: TainaPalette.textFaint,
              ),
            ),
            const SizedBox(height: TainaSpacing.space3),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TainaTypography.h3.copyWith(
                color: TainaPalette.textPrimary,
              ),
            ),
            const SizedBox(height: TainaSpacing.space3),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TainaTypography.bodySm.copyWith(
                color: TainaPalette.textMuted,
              ),
            ),
            if (hasAction) ...[
              const SizedBox(height: TainaSpacing.space4),
              if (builder != null)
                builder(context)
              else
                TainaButton(
                  title: actionLabel!,
                  action: onAction,
                  kind: TainaButtonKind.primary,
                  size: TainaButtonSize.lg,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An error with explicit retry and optional contact actions.
final class ErrorCard extends StatelessWidget {
  const ErrorCard({
    required this.title,
    required this.body,
    this.retry,
    this.contact,
    this.retryLabel = 'Tentar de novo',
    this.contactLabel = 'Falar com quem cuida',
    super.key,
  });

  final String title;
  final String body;
  final VoidCallback? retry;
  final VoidCallback? contact;
  final String retryLabel;
  final String contactLabel;

  @override
  Widget build(BuildContext context) {
    return TainaCard(
      kind: TainaCardKind.raised,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: TainaIconView(
                  icon: TainaIcon.warning,
                  size: TainaSizes.iconMd,
                  color: TainaPalette.feedbackWarning,
                ),
              ),
              const SizedBox(width: TainaSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TainaTypography.body.copyWith(
                        color: TainaPalette.textPrimary,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: TainaSpacing.space1),
                      Text(
                        body,
                        style: TainaTypography.bodySm.copyWith(
                          color: TainaPalette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (retry != null || contact != null) ...[
            const SizedBox(height: TainaSpacing.space4),
            Wrap(
              spacing: TainaSpacing.space3,
              runSpacing: TainaSpacing.space2,
              children: [
                if (retry != null)
                  TainaButton(
                    title: retryLabel,
                    action: retry,
                    kind: TainaButtonKind.secondary,
                    size: TainaButtonSize.sm,
                  ),
                if (contact != null)
                  TainaButton(
                    title: contactLabel,
                    action: contact,
                    kind: TainaButtonKind.ghost,
                    size: TainaButtonSize.sm,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A skeleton that follows the shape of the content while it loads.
final class SkeletonView extends StatefulWidget {
  const SkeletonView({required this.kind, this.count = 4, super.key});

  final TainaSkeletonKind kind;
  final int count;

  @override
  State<SkeletonView> createState() => _SkeletonViewState();
}

final class _SkeletonViewState extends State<SkeletonView>
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
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Carregando',
      child: ExcludeSemantics(
        child: FadeTransition(opacity: _opacity, child: _layout()),
      ),
    );
  }

  Widget _layout() {
    return switch (widget.kind) {
      TainaSkeletonKind.listRow => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int index = 0; index < widget.count; index++) ...[
            if (index > 0) const SizedBox(height: TainaSpacing.space2),
            _listRow(),
          ],
        ],
      ),
      TainaSkeletonKind.photoGrid => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.count,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: TainaSpacing.space2,
          mainAxisSpacing: TainaSpacing.space2,
        ),
        itemBuilder: (context, index) =>
            _placeholder(borderRadius: TainaRadii.mdAll),
      ),
      TainaSkeletonKind.card => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int index = 0; index < widget.count; index++) ...[
            if (index > 0) const SizedBox(height: TainaSpacing.space3),
            _card(),
          ],
        ],
      ),
    };
  }

  Widget _listRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TainaSpacing.space4,
        vertical: TainaSpacing.space2,
      ),
      child: SizedBox(
        height: TainaSizes.controlLg,
        child: Row(
          children: [
            _placeholder(
              width: TainaSpacing.space10,
              height: TainaSpacing.space10,
              borderRadius: TainaRadii.mdAll,
            ),
            const SizedBox(width: TainaSpacing.space3),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.56,
                    alignment: AlignmentDirectional.centerStart,
                    child: _SkeletonBar(),
                  ),
                  SizedBox(height: TainaSpacing.space2),
                  FractionallySizedBox(
                    widthFactor: 0.76,
                    alignment: AlignmentDirectional.centerStart,
                    child: _SkeletonBar(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _placeholder(
          height: TainaSpacing.space16 + TainaSpacing.space6,
          borderRadius: TainaRadii.mdAll,
        ),
        const SizedBox(height: TainaSpacing.space3),
        const FractionallySizedBox(
          widthFactor: 0.56,
          alignment: AlignmentDirectional.centerStart,
          child: _SkeletonBar(),
        ),
        const SizedBox(height: TainaSpacing.space2),
        const FractionallySizedBox(
          widthFactor: 0.4,
          alignment: AlignmentDirectional.centerStart,
          child: _SkeletonBar(),
        ),
      ],
    );
  }

  Widget _placeholder({
    double? width,
    double? height,
    BorderRadiusGeometry borderRadius = TainaRadii.mdAll,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TainaPalette.surfaceHigh,
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

final class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TainaSpacing.space3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TainaPalette.surfaceHigh,
          borderRadius: TainaRadii.mdAll,
        ),
      ),
    );
  }
}

/// A visible confirmation message. It leaves dismissal timing to its parent.
final class TainaToast extends StatelessWidget {
  const TainaToast({required this.kind, required this.text, super.key});

  final TainaToastKind kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    final bool isError = kind == TainaToastKind.error;
    final Color color = isError
        ? TainaPalette.feedbackError
        : TainaPalette.feedbackInfo;
    final TainaIcon icon = isError ? TainaIcon.warning : TainaIcon.check;

    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: TainaCard(
        kind: TainaCardKind.raised,
        padding: const EdgeInsets.all(TainaSpacing.space4),
        child: Row(
          children: [
            ExcludeSemantics(
              child: TainaIconView(icon: icon, color: color),
            ),
            const SizedBox(width: TainaSpacing.space3),
            Expanded(
              child: Text(
                text,
                style: TainaTypography.bodySm.copyWith(
                  color: TainaPalette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An invitation link with a scannable QR code and a copy action.
final class QRCard extends StatelessWidget {
  const QRCard({
    required this.link,
    required this.description,
    required this.onCopy,
    this.copyLabel = 'Copiar link',
    super.key,
  });

  final String link;
  final String description;
  final VoidCallback onCopy;
  final String copyLabel;

  @override
  Widget build(BuildContext context) {
    return TainaCard(
      kind: TainaCardKind.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'LINK DO CONVITE',
            textAlign: TextAlign.center,
            style: TainaTypography.overline.copyWith(
              color: TainaPalette.textMuted,
            ),
          ),
          const SizedBox(height: TainaSpacing.space3),
          ClipRRect(
            borderRadius: TainaRadii.mdAll,
            child: QrImageView(
              data: link,
              size: TainaSizes.qr,
              backgroundColor: TainaPalette.bgQr,
              semanticsLabel: 'Código QR do convite',
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: TainaPalette.textOnBrand,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: TainaPalette.textOnBrand,
              ),
            ),
          ),
          const SizedBox(height: TainaSpacing.space3),
          Text(
            link,
            textAlign: TextAlign.center,
            style: TainaTypography.monoSm.copyWith(
              color: TainaPalette.textPrimary,
            ),
          ),
          const SizedBox(height: TainaSpacing.space4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TainaTypography.bodySm.copyWith(
              color: TainaPalette.textSecondary,
            ),
          ),
          const SizedBox(height: TainaSpacing.space4),
          TainaButton(
            title: copyLabel,
            action: onCopy,
            kind: TainaButtonKind.primary,
            size: TainaButtonSize.md,
          ),
        ],
      ),
    );
  }
}
