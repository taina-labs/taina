import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../design_system/design_system.dart';
import 'camera_roll_upload_model.dart';

/// Opens the manual media upload flow and returns whether it uploaded anything.
Future<bool?> showCameraRollUploadSheet(
  BuildContext context, {
  required CameraRollUploadModel model,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => CameraRollUploadSheet(model: model),
  );
}

final class CameraRollUploadSheet extends StatefulWidget {
  const CameraRollUploadSheet({required this.model, super.key});

  final CameraRollUploadModel model;

  @override
  State<CameraRollUploadSheet> createState() => _CameraRollUploadSheetState();
}

final class _CameraRollUploadSheetState extends State<CameraRollUploadSheet>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.model.recoverLostData());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      widget.model.interrupt();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _close(CameraRollUploadModel model) {
    Navigator.of(context).pop(model.anySuccess);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final model = widget.model;
        return PopScope<bool>(
          canPop: !model.busy && !model.anySuccess,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height,
            ),
            child: SingleChildScrollView(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(TainaSpacing.space4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TainaText(
                              'Adicionar fotos e vídeos',
                              style: TainaTypography.h3,
                              color: TainaPalette.textPrimary,
                            ),
                          ),
                          TainaIconButton(
                            icon: TainaIcon.close,
                            label: 'Fechar',
                            action: model.busy ? null : () => _close(model),
                          ),
                        ],
                      ),
                      const SizedBox(height: TainaSpacing.space2),
                      const TainaText(
                        'Na sua casa. Nada vai para a praça.',
                        style: TainaTypography.body,
                        color: TainaPalette.textSecondary,
                      ),
                      const SizedBox(height: TainaSpacing.space1),
                      const TainaText(
                        'Este envio pode usar dados móveis.',
                        style: TainaTypography.caption,
                        color: TainaPalette.textMuted,
                      ),
                      const SizedBox(height: TainaSpacing.space5),
                      _content(model),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(CameraRollUploadModel model) {
    return switch (model.phase) {
      CameraRollUploadPhase.idle => _selectionActions(model),
      CameraRollUploadPhase.picking => _picking(),
      CameraRollUploadPhase.uploading => _progress(model),
      CameraRollUploadPhase.complete => _complete(model),
      CameraRollUploadPhase.failed => _failure(model),
      CameraRollUploadPhase.stopped => _stopped(model),
    };
  }

  Widget _selectionActions(CameraRollUploadModel model) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TainaEmptyState(
          icon: TainaIcon.image,
          title: 'Nenhuma foto selecionada',
          message: 'Escolha fotos e vídeos do aparelho ou tire uma foto agora.',
        ),
        TainaPrimaryButton(
          label: 'Escolher fotos e vídeos',
          onPressed: model.busy ? null : () => unawaited(model.pickPhotos()),
        ),
        const SizedBox(height: TainaSpacing.space2),
        TainaSecondaryButton(
          label: 'Tirar foto',
          onPressed: model.busy ? null : () => unawaited(model.takePhoto()),
        ),
      ],
    );
  }

  Widget _picking() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: TainaSpacing.space8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: TainaSpacing.space4),
          TainaText(
            'Abrindo as fotos e vídeos...',
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _progress(CameraRollUploadModel model) {
    final progress = model.total == 0 ? 0.0 : model.attempted / model.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TainaRowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TainaText(
                'Tentados: ${model.attempted} de ${model.total}',
                style: TainaTypography.label,
                color: TainaPalette.textPrimary,
              ),
              const SizedBox(height: TainaSpacing.space1),
              TainaText(
                'Enviados: ${model.succeeded}',
                style: TainaTypography.bodySm,
                color: TainaPalette.textSecondary,
              ),
              const SizedBox(height: TainaSpacing.space3),
              LinearProgressIndicator(
                value: progress,
                minHeight: TainaSizes.progress,
                color: TainaPalette.serviceYbira,
                backgroundColor: TainaPalette.surfaceRaised,
              ),
              if (model.currentFileName case final name?) ...[
                const SizedBox(height: TainaSpacing.space3),
                TainaText(
                  name,
                  style: TainaTypography.bodySm,
                  color: TainaPalette.textMuted,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (model.failedCount > 0) ...[
                const SizedBox(height: TainaSpacing.space3),
                _message(model.lastMessage, color: TainaPalette.feedbackError),
              ],
            ],
          ),
        ),
        const SizedBox(height: TainaSpacing.space3),
        const TainaText(
          'Mantenha o Tainá aberto',
          style: TainaTypography.label,
          color: TainaPalette.textSecondary,
          textAlign: TextAlign.center,
        ),
        if (model.stopRequested) ...[
          const SizedBox(height: TainaSpacing.space2),
          const TainaText(
            'O envio atual continua; os demais não começarão.',
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
            textAlign: TextAlign.center,
          ),
        ] else ...[
          const SizedBox(height: TainaSpacing.space4),
          TainaSecondaryButton(
            label: 'Parar os próximos envios',
            onPressed: model.uploading ? model.stopNext : null,
          ),
          const SizedBox(height: TainaSpacing.space2),
          const TainaText(
            'O envio atual continua; os demais não começarão.',
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _complete(CameraRollUploadModel model) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TainaRowCard(
          child: TainaText(
            '${model.succeeded} de ${model.total} arquivos foram enviados.',
            style: TainaTypography.body,
            color: TainaPalette.feedbackSuccess,
          ),
        ),
        const SizedBox(height: TainaSpacing.space4),
        TainaPrimaryButton(
          label: 'Ver arquivos',
          onPressed: () => _close(model),
        ),
      ],
    );
  }

  Widget _failure(CameraRollUploadModel model) {
    if (model.total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TainaRowCard(
            child: _message(
              model.lastMessage ??
                  'Não foi possível concluir a seleção. Tente de novo.',
              color: TainaPalette.feedbackError,
            ),
          ),
          const SizedBox(height: TainaSpacing.space4),
          ..._selectionButtons(model),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TainaRowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TainaText(
                'Enviados: ${model.succeeded} de ${model.total}. '
                'Não enviados: ${model.failedCount}.',
                style: TainaTypography.body,
                color: model.anySuccess
                    ? TainaPalette.feedbackWarning
                    : TainaPalette.feedbackError,
              ),
              if (model.lastMessage case final message?) ...[
                const SizedBox(height: TainaSpacing.space3),
                _message(message, color: TainaPalette.feedbackError),
              ],
            ],
          ),
        ),
        const SizedBox(height: TainaSpacing.space4),
        if (model.canRetry)
          TainaPrimaryButton(
            label: 'Tentar os que faltam',
            onPressed: () => unawaited(model.retryRemaining()),
          ),
        if (model.anySuccess) ...[
          const SizedBox(height: TainaSpacing.space2),
          TainaSecondaryButton(
            label: 'Ver arquivos',
            onPressed: () => _close(model),
          ),
        ],
      ],
    );
  }

  Widget _stopped(CameraRollUploadModel model) {
    final parts = <String>[
      'Enviados: ${model.succeeded} de ${model.total}.',
      'Não começaram: ${model.unstarted}.',
      if (model.failedCount > 0) 'Falharam: ${model.failedCount}.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TainaRowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TainaText(
                parts.join(' '),
                style: TainaTypography.body,
                color: TainaPalette.textSecondary,
              ),
              if (model.interrupted) ...[
                const SizedBox(height: TainaSpacing.space3),
                _message(
                  model.lastMessage ??
                      'O envio foi pausado ao sair do app. '
                          'Tente os que faltam quando voltar.',
                  color: TainaPalette.feedbackWarning,
                ),
              ] else if (model.lastMessage case final message?) ...[
                const SizedBox(height: TainaSpacing.space3),
                _message(message, color: TainaPalette.feedbackError),
              ],
            ],
          ),
        ),
        if (model.canRetry) ...[
          const SizedBox(height: TainaSpacing.space4),
          TainaPrimaryButton(
            label: 'Tentar os que faltam',
            onPressed: () => unawaited(model.retryRemaining()),
          ),
        ],
        if (model.anySuccess) ...[
          const SizedBox(height: TainaSpacing.space2),
          TainaSecondaryButton(
            label: 'Ver arquivos',
            onPressed: () => _close(model),
          ),
        ],
      ],
    );
  }

  List<Widget> _selectionButtons(CameraRollUploadModel model) {
    return [
      TainaPrimaryButton(
        label: 'Escolher fotos e vídeos',
        onPressed: model.busy ? null : () => unawaited(model.pickPhotos()),
      ),
      const SizedBox(height: TainaSpacing.space2),
      TainaSecondaryButton(
        label: 'Tirar foto',
        onPressed: model.busy ? null : () => unawaited(model.takePhoto()),
      ),
    ];
  }

  Widget _message(String? message, {required Color color}) {
    return TainaText(
      message ?? 'Não foi possível concluir este envio.',
      style: TainaTypography.bodySm,
      color: color,
    );
  }
}
