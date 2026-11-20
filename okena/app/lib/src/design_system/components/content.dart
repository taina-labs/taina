import 'package:flutter/material.dart';

import '../tokens.dart';
import 'actions.dart';
import 'icons.dart';
import 'identity.dart';

enum TainaCardKind { standard, raised }

enum ServiceCardService { ybira, jaci }

enum TainaListRowKind {
  file,
  folder,
  person,
  civic,
  mural,
  trash,
  upload,
  pedido,
}

enum TainaListRowTrailing { chevron, kebab, action, none }

enum TainaPedidoState { esperando, dado, recusado }

enum TainaProgressTone { ybira, jaci, sky, success, neutral, warning }

enum TainaStorageDetail { compact, full }

enum TainaStorageTone { normal, warning }

enum TainaStatusState { ok, attention, problem, unknown }

enum TainaStatusDetail { none, withDetail }

/// A token-backed surface for grouping related content.
final class TainaCard extends StatelessWidget {
  const TainaCard({
    required this.child,
    this.kind = TainaCardKind.standard,
    this.padding = const EdgeInsets.all(TainaSpacing.space4),
    super.key,
  });

  final Widget child;
  final TainaCardKind kind;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (kind) {
      TainaCardKind.standard => TainaPalette.surfaceDefault,
      TainaCardKind.raised => TainaPalette.surfaceRaised,
    };
    final List<BoxShadow> shadows = switch (kind) {
      TainaCardKind.standard => const [],
      TainaCardKind.raised => TainaElevation.soft,
    };

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: TainaRadii.lgAll,
          boxShadow: shadows,
        ),
        child: Material(
          color: color,
          elevation: 0,
          shadowColor: TainaPalette.bgDeep,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: TainaRadii.lgAll,
            side: BorderSide(
              color: TainaPalette.borderSubtle,
              width: TainaSizes.hairline,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A reusable file, folder, people, civic, mural, trash, upload, or request row.
///
/// Provide [leadingBuilder] for data-specific content such as a person's
/// avatar. Pedido rows use [state] and may place their decision controls in
/// [actionsBuilder].
final class TainaListRow extends StatelessWidget {
  const TainaListRow({
    required this.kind,
    required this.title,
    this.meta,
    this.trailing = TainaListRowTrailing.none,
    this.state,
    this.stateSummary,
    this.leadingBuilder,
    this.actionsBuilder,
    this.trailingBuilder,
    this.trailingLabel,
    this.onTap,
    this.onTrailingPressed,
    this.showDivider = true,
    super.key,
  });

  final TainaListRowKind kind;
  final String title;
  final String? meta;
  final TainaListRowTrailing trailing;
  final TainaPedidoState? state;
  final String? stateSummary;
  final WidgetBuilder? leadingBuilder;
  final WidgetBuilder? actionsBuilder;
  final WidgetBuilder? trailingBuilder;
  final String? trailingLabel;
  final VoidCallback? onTap;
  final VoidCallback? onTrailingPressed;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final Widget leading = leadingBuilder?.call(context) ?? _leading();
    final String semanticLabel = meta == null ? title : '$title, $meta';
    final bool showTrailing =
        trailing != TainaListRowTrailing.none &&
        !(kind == TainaListRowKind.pedido &&
            trailing == TainaListRowTrailing.action);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TainaSpacing.space4,
            vertical: TainaSpacing.space2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  button: onTap != null,
                  enabled: onTap != null,
                  label: semanticLabel,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: TainaRadii.smAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: TainaSpacing.space2,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: TainaSizes.controlMd,
                                height: TainaSizes.controlMd,
                                child: Center(
                                  child: ExcludeSemantics(child: leading),
                                ),
                              ),
                              const SizedBox(width: TainaSpacing.space3),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TainaTypography.label.copyWith(
                                        color: TainaPalette.textPrimary,
                                      ),
                                    ),
                                    if (meta != null) ...[
                                      const SizedBox(
                                        height: TainaSpacing.space1,
                                      ),
                                      Text(
                                        meta!,
                                        style: TainaTypography.caption.copyWith(
                                          color: TainaPalette.textMuted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (showTrailing) ...[
                const SizedBox(width: TainaSpacing.space2),
                _trailingControl(context),
              ],
            ],
          ),
        ),
        if (state != null && state != TainaPedidoState.esperando)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: TainaSpacing.space4,
              end: TainaSpacing.space4,
              bottom: TainaSpacing.space3,
            ),
            child: StatusLine(
              state: switch (state!) {
                TainaPedidoState.esperando => TainaStatusState.attention,
                TainaPedidoState.dado => TainaStatusState.ok,
                TainaPedidoState.recusado => TainaStatusState.problem,
              },
              title: stateSummary ?? _pedidoSummary(state!),
            ),
          ),
        if (state == TainaPedidoState.esperando && actionsBuilder != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: TainaSpacing.space4,
              end: TainaSpacing.space4,
              bottom: TainaSpacing.space3,
            ),
            child: actionsBuilder!(context),
          ),
        if (showDivider)
          const Divider(
            color: TainaPalette.borderSubtle,
            thickness: TainaSizes.hairline,
            height: TainaSizes.hairline,
          ),
      ],
    );
  }

  Widget _leading() {
    if (kind == TainaListRowKind.person) {
      return TainaAvatar(name: title);
    }
    if (kind == TainaListRowKind.civic) {
      return const ServiceSquare(mark: TainaServiceMark.moradores);
    }
    if (kind == TainaListRowKind.folder) {
      return const ServiceSquare(
        mark: TainaServiceMark.ybira,
        tone: TainaServiceSquareTone.service,
      );
    }
    final (
      TainaIcon icon,
      Color background,
      Color foreground,
      BorderRadiusGeometry radius,
    ) = switch (kind) {
      TainaListRowKind.file => (
        TainaIcon.file,
        TainaPalette.surfaceRaised,
        TainaPalette.textSecondary,
        TainaRadii.mdAll,
      ),
      TainaListRowKind.folder ||
      TainaListRowKind.person ||
      TainaListRowKind.civic => (
        TainaIcon.moradores,
        TainaPalette.surfaceRaised,
        TainaPalette.textSecondary,
        TainaRadii.mdAll,
      ),
      TainaListRowKind.mural => (
        TainaIcon.moradores,
        TainaPalette.serviceMaracaSoft,
        TainaPalette.serviceMaraca,
        TainaRadii.lgAll,
      ),
      TainaListRowKind.trash => (
        TainaIcon.trash,
        TainaPalette.surfaceRaised,
        TainaPalette.textSecondary,
        TainaRadii.mdAll,
      ),
      TainaListRowKind.upload => (
        TainaIcon.upload,
        TainaPalette.surfaceRaised,
        TainaPalette.textSecondary,
        TainaRadii.mdAll,
      ),
      TainaListRowKind.pedido => (
        TainaIcon.user,
        TainaPalette.serviceMaracaTint,
        TainaPalette.serviceMaraca,
        TainaRadii.mdAll,
      ),
    };

    return SizedBox(
      width: TainaSizes.touch,
      height: TainaSizes.touch,
      child: DecoratedBox(
        decoration: BoxDecoration(color: background, borderRadius: radius),
        child: Center(child: _icon(icon, color: foreground)),
      ),
    );
  }

  Widget _trailing() {
    return switch (trailing) {
      TainaListRowTrailing.chevron => _icon(
        TainaIcon.chevR,
        color: TainaPalette.textMuted,
      ),
      TainaListRowTrailing.kebab => TainaIconButton(
        icon: TainaIcon.kebab,
        label: trailingLabel ?? 'Mais ações',
        action: onTrailingPressed,
      ),
      TainaListRowTrailing.action =>
        trailingLabel == null
            ? const SizedBox.shrink()
            : TainaButton(
                title: trailingLabel!,
                action: onTrailingPressed,
                kind: TainaButtonKind.ghost,
                size: TainaButtonSize.sm,
              ),
      TainaListRowTrailing.none => const SizedBox.shrink(),
    };
  }

  Widget _trailingControl(BuildContext context) {
    final Widget child = trailingBuilder?.call(context) ?? _trailing();
    if (trailing == TainaListRowTrailing.action) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: TainaSizes.touch,
          minHeight: TainaSizes.touch,
        ),
        child: child,
      );
    }
    return SizedBox(
      width: TainaSizes.touch,
      height: TainaSizes.touch,
      child: Center(child: child),
    );
  }

  static String _pedidoSummary(TainaPedidoState state) {
    return switch (state) {
      TainaPedidoState.esperando => 'Aguardando resposta',
      TainaPedidoState.dado => 'Acesso dado',
      TainaPedidoState.recusado => 'Acesso recusado',
    };
  }
}

/// A service entry card with the service's own accent.
final class ServiceCard extends StatelessWidget {
  const ServiceCard({
    required this.service,
    required this.title,
    required this.body,
    this.onTap,
    super.key,
  });

  final ServiceCardService service;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool documentos = service == ServiceCardService.ybira;
    final TainaServiceMark mark = documentos
        ? TainaServiceMark.ybira
        : TainaServiceMark.jaci;

    return Material(
      color: TainaPalette.surfaceDefault,
      borderRadius: TainaRadii.lgAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: TainaRadii.lgAll,
        child: Padding(
          padding: const EdgeInsets.all(TainaSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ServiceSquare(
                mark: mark,
                size: TainaServiceSquareSize.lg,
                tone: TainaServiceSquareTone.service,
              ),
              const SizedBox(height: TainaSpacing.space3),
              Text(
                title,
                style: TainaTypography.h3.copyWith(
                  color: TainaPalette.textPrimary,
                ),
              ),
              const SizedBox(height: TainaSpacing.space2),
              Text(
                body,
                style: TainaTypography.bodySm.copyWith(
                  color: TainaPalette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A community access request that deserves a visible, direct response.
final class CareLine extends StatelessWidget {
  const CareLine({
    required this.text,
    required this.actionLabel,
    required this.action,
    super.key,
  });

  final String text;
  final String actionLabel;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) {
    return TainaCard(
      kind: TainaCardKind.raised,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: TainaSizes.iconMd,
            height: TainaSizes.iconMd,
            child: Center(
              child: _icon(
                TainaIcon.pedidos,
                color: TainaPalette.serviceMaracaTint,
              ),
            ),
          ),
          const SizedBox(width: TainaSpacing.space3),
          Expanded(
            child: Text(
              text,
              style: TainaTypography.body.copyWith(
                color: TainaPalette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: TainaSpacing.space2),
          TextButton(
            onPressed: action,
            style: TextButton.styleFrom(
              minimumSize: const Size(TainaSizes.touch, TainaSizes.touch),
              padding: const EdgeInsets.symmetric(
                horizontal: TainaSpacing.space2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel,
                  style: TainaTypography.label.copyWith(
                    color: TainaPalette.textPrimary,
                  ),
                ),
                const SizedBox(width: TainaSpacing.space1),
                _icon(TainaIcon.chevR, color: TainaPalette.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The labels and pure numeric progress value shown by [StorageCard].
final class StorageSummary {
  const StorageSummary({
    required this.usedLabel,
    required this.caption,
    required this.progress,
    this.freeLabel,
  });

  final String usedLabel;
  final String caption;
  final double progress;
  final String? freeLabel;
}

/// A compact or detailed view of community-wide storage use.
final class StorageCard extends StatelessWidget {
  const StorageCard({
    required this.summary,
    this.detail = TainaStorageDetail.compact,
    this.tone = TainaStorageTone.normal,
    this.onAction,
    this.actionLabel = 'Ver detalhes',
    super.key,
  });

  final StorageSummary summary;
  final TainaStorageDetail detail;
  final TainaStorageTone tone;
  final VoidCallback? onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final TainaProgressTone progressTone = switch (tone) {
      TainaStorageTone.normal => TainaProgressTone.ybira,
      TainaStorageTone.warning => TainaProgressTone.warning,
    };

    if (detail == TainaStorageDetail.full) {
      return TainaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Espaço da comunidade',
              style: TainaTypography.label.copyWith(
                color: TainaPalette.textSecondary,
              ),
            ),
            const SizedBox(height: TainaSpacing.space1),
            Text(
              summary.usedLabel,
              style: TainaTypography.h2.copyWith(
                color: TainaPalette.textPrimary,
              ),
            ),
            const SizedBox(height: TainaSpacing.space3),
            TainaProgress(
              value: summary.progress,
              tone: progressTone,
              semanticLabel: 'Espaço usado',
            ),
            const SizedBox(height: TainaSpacing.space2),
            Text(
              summary.caption,
              style: TainaTypography.caption.copyWith(
                color: TainaPalette.textMuted,
              ),
            ),
            if (summary.freeLabel != null) ...[
              const SizedBox(height: TainaSpacing.space1),
              Text(
                summary.freeLabel!,
                style: TainaTypography.caption.copyWith(
                  color: tone == TainaStorageTone.warning
                      ? TainaPalette.feedbackWarning
                      : TainaPalette.feedbackSuccess,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return TainaCard(
      padding: const EdgeInsets.all(TainaSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Espaço da comunidade',
                  style: TainaTypography.label.copyWith(
                    color: TainaPalette.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  minimumSize: const Size(TainaSizes.touch, TainaSizes.touch),
                  padding: const EdgeInsets.symmetric(
                    horizontal: TainaSpacing.space2,
                  ),
                ),
                child: Text(
                  actionLabel,
                  style: TainaTypography.label.copyWith(
                    color: TainaPalette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: TainaSpacing.space2),
          TainaProgress(
            value: summary.progress,
            tone: progressTone,
            semanticLabel: 'Espaço usado',
          ),
          const SizedBox(height: TainaSpacing.space2),
          Text(
            summary.caption,
            style: TainaTypography.caption.copyWith(
              color: TainaPalette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A determinate progress bar using a semantic tone.
final class TainaProgress extends StatelessWidget {
  const TainaProgress({
    required this.value,
    this.tone = TainaProgressTone.neutral,
    this.semanticLabel = 'Progresso',
    super.key,
  });

  final double value;
  final TainaProgressTone tone;
  final String semanticLabel;

  double get _normalizedValue {
    if (value.isNaN) return 0;
    return value.clamp(0.0, 1.0).toDouble();
  }

  Color get _color => switch (tone) {
    TainaProgressTone.ybira => TainaPalette.serviceYbira,
    TainaProgressTone.jaci => TainaPalette.serviceJaci,
    TainaProgressTone.sky => TainaPalette.serviceNhaman,
    TainaProgressTone.success => TainaPalette.feedbackSuccess,
    TainaProgressTone.neutral => TainaPalette.textFaint,
    TainaProgressTone.warning => TainaPalette.feedbackWarning,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      value: '${(_normalizedValue * 100).round()}%',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: TainaRadii.pillAll,
          child: SizedBox(
            width: double.infinity,
            height: TainaSizes.progress,
            child: ColoredBox(
              color: TainaPalette.surfaceHigh,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: _normalizedValue,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _color,
                      borderRadius: TainaRadii.pillAll,
                    ),
                    child: const SizedBox.expand(),
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

/// A health status with a visible icon and a human-readable status word.
final class StatusLine extends StatelessWidget {
  const StatusLine({
    required this.state,
    required this.title,
    this.detail = TainaStatusDetail.none,
    this.detailText,
    super.key,
  });

  final TainaStatusState state;
  final String title;
  final TainaStatusDetail detail;
  final String? detailText;

  @override
  Widget build(BuildContext context) {
    final (TainaIcon icon, Color color) = switch (state) {
      TainaStatusState.ok => (TainaIcon.check, TainaPalette.feedbackSuccess),
      TainaStatusState.attention => (
        TainaIcon.clock,
        TainaPalette.feedbackWarning,
      ),
      TainaStatusState.problem => (
        TainaIcon.warning,
        TainaPalette.feedbackError,
      ),
      TainaStatusState.unknown => (TainaIcon.dots, TainaPalette.textMuted),
    };
    final bool showDetail =
        detail == TainaStatusDetail.withDetail && detailText != null;

    return Semantics(
      container: true,
      label: title,
      value: showDetail ? detailText : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: _icon(icon, color: color)),
          const SizedBox(width: TainaSpacing.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TainaTypography.label.copyWith(color: color),
                ),
                if (showDetail) ...[
                  const SizedBox(height: TainaSpacing.space1),
                  Text(
                    detailText!,
                    style: TainaTypography.caption.copyWith(
                      color: TainaPalette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _icon(TainaIcon icon, {Color? color, double? size}) {
  return TainaIconView(
    icon: icon,
    size: size ?? TainaSizes.iconMd,
    color: color ?? TainaPalette.textSecondary,
  );
}
