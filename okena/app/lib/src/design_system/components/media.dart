import 'package:flutter/material.dart';

import '../tokens.dart';
import 'actions.dart';
import 'icons.dart';
import 'text.dart';

enum UploadRowStatus { uploading, quotaExceeded, networkError }

String uploadRowStatusLabel(UploadRowStatus status) => switch (status) {
  UploadRowStatus.uploading => 'Enviando',
  UploadRowStatus.quotaExceeded => 'Não deu para enviar',
  UploadRowStatus.networkError => 'Não deu para enviar',
};

double? normalizeUploadProgress(double? progress) {
  if (progress == null || !progress.isFinite) return null;
  return progress.clamp(0.0, 1.0);
}

/// A file transfer row with explicit progress, network and quota states.
final class UploadRow extends StatelessWidget {
  const UploadRow({
    required this.fileName,
    required this.status,
    this.progress,
    this.detail,
    this.help,
    this.onRetry,
    this.onViewSpace,
    super.key,
  });

  final String fileName;
  final UploadRowStatus status;
  final double? progress;
  final String? detail;
  final String? help;
  final VoidCallback? onRetry;
  final VoidCallback? onViewSpace;

  @override
  Widget build(BuildContext context) {
    final double? normalizedProgress = normalizeUploadProgress(progress);
    final String title = status == UploadRowStatus.uploading
        ? 'Enviando $fileName'
        : uploadRowStatusLabel(status);
    final String? supportingText = detail ?? _defaultDetail(status);
    final String? supportingHelp =
        help ??
        (status == UploadRowStatus.uploading
            ? 'Você pode continuar usando o app enquanto envia.'
            : null);
    final String? actionLabel = switch (status) {
      UploadRowStatus.uploading => null,
      UploadRowStatus.quotaExceeded => 'Ver espaço',
      UploadRowStatus.networkError => 'Tentar de novo',
    };
    final VoidCallback? action = switch (status) {
      UploadRowStatus.uploading => null,
      UploadRowStatus.quotaExceeded => onViewSpace,
      UploadRowStatus.networkError => onRetry,
    };

    return Container(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      decoration: BoxDecoration(
        color: TainaPalette.surfaceRaised,
        borderRadius: TainaRadii.lgAll,
        border: Border.all(
          color: status == UploadRowStatus.uploading
              ? TainaPalette.borderDefault
              : TainaPalette.feedbackError,
          width: TainaSizes.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TainaText(
                  title,
                  style: TainaTypography.body,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (status == UploadRowStatus.uploading &&
                  normalizedProgress != null) ...[
                const SizedBox(width: TainaSpacing.space3),
                TainaText(
                  '${(normalizedProgress * 100).round()}%',
                  style: TainaTypography.monoSm,
                  color: TainaPalette.textSecondary,
                ),
              ],
            ],
          ),
          if (status == UploadRowStatus.uploading) ...[
            const SizedBox(height: TainaSpacing.space3),
            Semantics(
              label: 'Progresso do envio',
              value: normalizedProgress == null
                  ? null
                  : '${(normalizedProgress * 100).round()}%',
              child: LinearProgressIndicator(
                value: normalizedProgress,
                color: TainaPalette.serviceYbira,
                backgroundColor: TainaPalette.surfaceHigh,
                borderRadius: TainaRadii.pillAll,
                minHeight: TainaSizes.progress,
              ),
            ),
          ],
          if (supportingText != null) ...[
            const SizedBox(height: TainaSpacing.space3),
            TainaText(
              supportingText,
              style: TainaTypography.bodySm,
              color: TainaPalette.textMuted,
            ),
          ],
          if (supportingHelp != null) ...[
            const SizedBox(height: TainaSpacing.space2),
            TainaText(
              supportingHelp,
              style: TainaTypography.bodySm,
              color: TainaPalette.textSecondary,
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: TainaSpacing.space3),
            TainaButton(
              title: actionLabel,
              action: action,
              kind: TainaButtonKind.secondary,
              size: TainaButtonSize.md,
            ),
          ],
        ],
      ),
    );
  }

  static String? _defaultDetail(UploadRowStatus status) => switch (status) {
    UploadRowStatus.uploading => null,
    UploadRowStatus.quotaExceeded =>
      'O espaço da comunidade acabou. Peça a quem cuida da nuvem para liberar.',
    UploadRowStatus.networkError =>
      'A conexão caiu no meio do envio. O arquivo não saiu da sua casa.',
  };
}

/// Viewer content with close, action, counter and caption controls.
final class ViewerChrome extends StatelessWidget {
  const ViewerChrome({
    required this.child,
    required this.onClose,
    required this.counter,
    required this.caption,
    this.onPrevious,
    this.onNext,
    this.action,
    this.controlsVisible = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onClose;
  final String counter;
  final String caption;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Widget? action;
  final bool controlsVisible;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: TainaPalette.bgViewer, child: child),
        if (controlsVisible) ...[
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TainaSpacing.space2,
                ),
                child: SizedBox(
                  height: TainaSizes.appbar,
                  child: Row(
                    children: [
                      TainaIconButton(
                        icon: TainaIcon.close,
                        label: 'Fechar visualização',
                        action: onClose,
                      ),
                      const Spacer(),
                      SizedBox(
                        width: TainaSizes.touch,
                        height: TainaSizes.touch,
                        child: action,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TainaSpacing.space2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TainaIconButton(
                    icon: TainaIcon.chevL,
                    label: 'Foto anterior',
                    action: onPrevious,
                  ),
                  TainaIconButton(
                    icon: TainaIcon.chevR,
                    label: 'Próxima foto',
                    action: onNext,
                  ),
                ],
              ),
            ),
          ),
          _captionCard(),
        ],
      ],
    );
  }

  Widget _captionCard() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(TainaSpacing.space4),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: TainaPalette.surfaceScrim,
              borderRadius: TainaRadii.mdAll,
            ),
            child: Padding(
              padding: const EdgeInsets.all(TainaSpacing.space3),
              child: Row(
                children: [
                  Expanded(
                    child: TainaText(
                      caption,
                      style: TainaTypography.bodySm,
                      color: TainaPalette.textPrimary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: TainaSpacing.space3),
                  TainaText(
                    counter,
                    style: TainaTypography.monoSm,
                    color: TainaPalette.textSecondary,
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
