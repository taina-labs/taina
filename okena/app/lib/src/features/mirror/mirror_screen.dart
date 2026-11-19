import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/mirror/mirror_status_model.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_app/src/shell/shell_model.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

final class MirrorScreen extends StatefulWidget {
  const MirrorScreen({required this.runtime, this.onOpenStorage, super.key});

  final MirrorRuntime runtime;
  final VoidCallback? onOpenStorage;

  @override
  State<MirrorScreen> createState() => _MirrorScreenState();
}

final class _MirrorScreenState extends State<MirrorScreen>
    with WidgetsBindingObserver {
  late final MirrorStatusModel _model;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _model = MirrorStatusModel.fromRuntime(widget.runtime);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_model.reloadAccess());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MirrorStatusModel>.value(
      value: _model,
      child: _MirrorView(onOpenStorage: widget.onOpenStorage),
    );
  }
}

final class _MirrorView extends StatelessWidget {
  const _MirrorView({this.onOpenStorage});

  final VoidCallback? onOpenStorage;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<MirrorStatusModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Espelho do rolo de câmera')),
      body: SafeArea(child: _body(context, model)),
    );
  }

  Widget _body(BuildContext context, MirrorStatusModel model) {
    if (model.owner == null) {
      final error = model.lastError;
      if (error != null) {
        return TainaErrorState(error: error, onRetry: model.retry);
      }
      return const TainaLoadingList();
    }

    final summary = model.summary;
    if (summary == null) {
      final error = model.lastError;
      if (error != null && !model.loading) {
        return TainaErrorState(error: error, onRetry: model.retry);
      }
      return const TainaLoadingList();
    }

    return RefreshIndicator(
      onRefresh: model.retry,
      child: ListView(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        children: [
          _statusCard(context, model, summary),
          const SizedBox(height: TainaSpacing.space3),
          _networkCard(model),
        ],
      ),
    );
  }

  Widget _statusCard(
    BuildContext context,
    MirrorStatusModel model,
    MirrorSummary summary,
  ) {
    final presentation = model.presentation;
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TainaText(
            presentation.title,
            style: TainaTypography.h3,
            color: presentation.kind == MirrorStatusKind.quotaPaused
                ? TainaPalette.feedbackWarning
                : TainaPalette.textPrimary,
          ),
          const SizedBox(height: TainaSpacing.space2),
          TainaText(
            model.statusMessage,
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
          ),
          const SizedBox(height: TainaSpacing.space3),
          const TainaText(
            'Fotos e vídeos deste aparelho vão para Rolo de câmera, na sua '
            'casa, e usam o espaço da comunidade. Nada vai para a praça.',
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
          ),
          const SizedBox(height: TainaSpacing.space2),
          const TainaText(
            'O envio acontece aos poucos, mais rápido com o Tainá aberto. '
            'Apagar do aparelho não apaga a cópia da sua casa.',
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
          ),
          if (summary.totalEntries > 0) ...[
            const SizedBox(height: TainaSpacing.space3),
            TainaText(
              mirrorProgressMessage(summary),
              style: TainaTypography.bodySm,
              color: TainaPalette.textPrimary,
            ),
            if (summary.pendingCount > 0 && summary.knownPendingBytes > 0) ...[
              const SizedBox(height: TainaSpacing.space1),
              TainaText(
                'Faltam cerca de '
                '${TainaFormat.bytes(summary.knownPendingBytes.round())}.',
                style: TainaTypography.caption,
                color: TainaPalette.textMuted,
              ),
            ],
            if (summary.pendingCount > 0 && summary.hasPendingUnknownSize) ...[
              const SizedBox(height: TainaSpacing.space1),
              const TainaText(
                'O tamanho de alguns arquivos ainda está sendo calculado.',
                style: TainaTypography.caption,
                color: TainaPalette.textMuted,
              ),
            ],
          ],
          if (model.showEmptyState) ...[
            const SizedBox(height: TainaSpacing.space3),
            const TainaEmptyState(
              icon: Icons.photo_library_outlined,
              title: 'Ainda não há arquivos para enviar',
              message:
                  'Quando houver fotos e vídeos novos, o Tainá vai enviar uma '
                  'cópia para sua casa.',
            ),
          ],
          if (presentation.kind != MirrorStatusKind.quotaPaused &&
              model.actionableMessage != null &&
              (presentation.kind == MirrorStatusKind.failed ||
                  model.actionError != null)) ...[
            const SizedBox(height: TainaSpacing.space3),
            TainaText(
              model.actionableMessage!,
              style: TainaTypography.caption,
              color: TainaPalette.feedbackWarning,
            ),
          ],
          if (model.hasLimitedAccess &&
              presentation.kind != MirrorStatusKind.quotaPaused) ...[
            const SizedBox(height: TainaSpacing.space2),
            const TainaText(
              'O Tainá pode enviar as fotos que você escolheu.',
              style: TainaTypography.caption,
              color: TainaPalette.textMuted,
            ),
          ],
          if (model.canOpenSettings ||
              model.canEnable ||
              model.canDisable ||
              model.canChooseMore ||
              model.canOpenStorage ||
              model.canResumeQuota ||
              model.canRetry) ...[
            const SizedBox(height: TainaSpacing.space4),
            _actions(context, model),
          ],
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, MirrorStatusModel model) {
    final buttons = <Widget>[];
    if (model.canOpenStorage) {
      buttons.add(
        TainaPrimaryButton(
          label: 'Ver armazenamento',
          onPressed: model.actionRunning ? null : () => _openStorage(context),
        ),
      );
    }
    if (model.canResumeQuota) {
      buttons.add(
        TainaSecondaryButton(
          label: 'Retomar espelho',
          onPressed: model.actionRunning
              ? null
              : () => unawaited(model.resumeQuota()),
        ),
      );
    }
    if (model.canRetry) {
      buttons.add(
        TainaPrimaryButton(
          label: 'Tentar de novo',
          loading: model.actionRunning,
          onPressed: model.actionRunning
              ? null
              : () => unawaited(model.retry()),
        ),
      );
    }
    if (model.canEnable) {
      buttons.add(
        TainaPrimaryButton(
          label: 'Ligar espelho',
          loading: model.actionRunning,
          onPressed: model.actionRunning
              ? null
              : () => unawaited(model.enable()),
        ),
      );
    }
    if (model.canOpenSettings) {
      buttons.add(
        TainaSecondaryButton(
          label: 'Abrir Ajustes',
          onPressed: model.actionRunning
              ? null
              : () => unawaited(model.openSettings()),
        ),
      );
    }
    if (model.canChooseMore) {
      buttons.add(
        TainaSecondaryButton(
          label: 'Escolher mais fotos',
          onPressed: model.actionRunning
              ? null
              : () => unawaited(model.chooseMore()),
        ),
      );
    }
    if (model.canDisable) {
      buttons.add(
        TainaSecondaryButton(
          label: 'Desligar neste aparelho',
          onPressed: model.actionRunning
              ? null
              : () => unawaited(model.disable()),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < buttons.length; index++) ...[
          if (index > 0) const SizedBox(height: TainaSpacing.space2),
          buttons[index],
        ],
      ],
    );
  }

  Widget _networkCard(MirrorStatusModel model) {
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TainaText(
                  'Somente no Wi-Fi',
                  style: TainaTypography.body,
                  color: TainaPalette.textPrimary,
                ),
              ),
              Semantics(
                label: 'Somente no Wi-Fi',
                toggled: model.wifiOnly,
                child: Switch(
                  value: model.wifiOnly,
                  onChanged: model.actionRunning
                      ? null
                      : (value) => unawaited(model.setWifiOnly(value)),
                ),
              ),
            ],
          ),
          TainaText(
            model.wifiOnly
                ? 'Esta escolha vale para os próximos envios.'
                : 'Esta escolha vale para os próximos envios, que também '
                      'podem usar dados móveis.',
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
          ),
        ],
      ),
    );
  }

  void _openStorage(BuildContext context) {
    if (onOpenStorage case final callback?) {
      callback();
      return;
    }
    context.read<ShellModel>().openMore(MoreRoute.armazenamento);
  }
}
