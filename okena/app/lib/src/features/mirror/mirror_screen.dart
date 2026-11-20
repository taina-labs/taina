import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/mirror/mirror_status_model.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_app/src/routing/route_helpers.dart';
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
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              title: 'Rolo de câmera',
              backLabel: 'Conta',
              onBack: () => context.go(AppRoutes.account),
            ),
            Expanded(child: _body(context, model)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, MirrorStatusModel model) {
    if (model.owner == null) {
      final error = model.lastError;
      if (error != null) {
        return _errorState(
          title: 'Não foi possível abrir o rolo de câmera.',
          error: error,
          retry: model.retry,
        );
      }
      return const _LoadingState();
    }

    final summary = model.summary;
    if (summary == null) {
      final error = model.lastError;
      if (error != null && !model.loading) {
        return _errorState(
          title: 'Não foi possível carregar os arquivos.',
          error: error,
          retry: model.retry,
        );
      }
      return const _LoadingState();
    }

    return RefreshIndicator(
      onRefresh: model.retry,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          TainaSpacing.space4,
          TainaSpacing.space2,
          TainaSpacing.space4,
          TainaSpacing.space6,
        ),
        children: [
          _statusCard(context, model, summary),
          if (model.showEmptyState) ...[
            const SizedBox(height: TainaSpacing.space3),
            const EmptyStateView(
              icon: TainaIcon.image,
              title: 'Ainda não há arquivos para enviar',
              body:
                  'Quando houver fotos e vídeos novos, o Tainá vai enviar '
                  'uma cópia para sua casa.',
            ),
          ],
          const SizedBox(height: TainaSpacing.space3),
          _networkCard(model),
        ],
      ),
    );
  }

  Widget _errorState({
    required String title,
    required TainaError error,
    required Future<void> Function() retry,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(TainaSpacing.space4),
      children: [
        ErrorCard(
          title: title,
          body: error.message,
          retry: () => unawaited(retry()),
        ),
      ],
    );
  }

  Widget _statusCard(
    BuildContext context,
    MirrorStatusModel model,
    MirrorSummary summary,
  ) {
    final presentation = model.presentation;
    return TainaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusLine(
            state: _statusState(presentation.kind),
            title: presentation.title,
            detail: TainaStatusDetail.withDetail,
            detailText: model.statusMessage,
          ),
          const SizedBox(height: TainaSpacing.space4),
          Text(
            'Fotos e vídeos deste aparelho vão para Rolo de câmera, na sua '
            'casa, e usam o espaço da comunidade. Nada vai para a praça.',
            style: TainaTypography.bodySm.copyWith(
              color: TainaPalette.textSecondary,
            ),
          ),
          const SizedBox(height: TainaSpacing.space2),
          Text(
            'O envio acontece aos poucos, mais rápido com o Tainá aberto. '
            'Apagar do aparelho não apaga a cópia da sua casa.',
            style: TainaTypography.bodySm.copyWith(
              color: TainaPalette.textSecondary,
            ),
          ),
          if (summary.totalEntries > 0) ...[
            const SizedBox(height: TainaSpacing.space4),
            Text(
              mirrorProgressMessage(summary),
              style: TainaTypography.bodySm.copyWith(
                color: TainaPalette.textPrimary,
              ),
            ),
            if (summary.storedCount + summary.pendingCount > 0) ...[
              const SizedBox(height: TainaSpacing.space2),
              TainaProgress(
                value:
                    summary.storedCount /
                    (summary.storedCount + summary.pendingCount),
                tone: TainaProgressTone.ybira,
                semanticLabel: 'Arquivos enviados',
              ),
            ],
            if (summary.pendingCount > 0 && summary.knownPendingBytes > 0) ...[
              const SizedBox(height: TainaSpacing.space1),
              Text(
                'Faltam cerca de '
                '${TainaFormat.bytes(summary.knownPendingBytes.round())}.',
                style: TainaTypography.caption.copyWith(
                  color: TainaPalette.textMuted,
                ),
              ),
            ],
            if (summary.pendingCount > 0 && summary.hasPendingUnknownSize) ...[
              const SizedBox(height: TainaSpacing.space1),
              Text(
                'O tamanho de alguns arquivos ainda está sendo calculado.',
                style: TainaTypography.caption.copyWith(
                  color: TainaPalette.textMuted,
                ),
              ),
            ],
          ],
          if (model.actionableMessage != null &&
              presentation.kind != MirrorStatusKind.quotaPaused &&
              (presentation.kind == MirrorStatusKind.failed ||
                  model.actionError != null)) ...[
            const SizedBox(height: TainaSpacing.space3),
            TainaToast(
              kind: TainaToastKind.error,
              text: model.actionableMessage!,
            ),
          ],
          if (model.hasLimitedAccess &&
              presentation.kind != MirrorStatusKind.quotaPaused) ...[
            const SizedBox(height: TainaSpacing.space2),
            Text(
              'O Tainá pode enviar as fotos que você escolheu.',
              style: TainaTypography.caption.copyWith(
                color: TainaPalette.textMuted,
              ),
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
        _button(
          'Ver armazenamento',
          kind: TainaButtonKind.primary,
          loading: false,
          enabled: !model.actionRunning,
          onPressed: () => _openStorage(context),
        ),
      );
    }
    if (model.canResumeQuota) {
      buttons.add(
        _button(
          'Retomar espelho',
          kind: TainaButtonKind.secondary,
          enabled: !model.actionRunning,
          onPressed: () => unawaited(model.resumeQuota()),
        ),
      );
    }
    if (model.canRetry) {
      buttons.add(
        _button(
          'Tentar de novo',
          kind: TainaButtonKind.primary,
          loading: model.actionRunning,
          enabled: !model.actionRunning,
          onPressed: () => unawaited(model.retry()),
        ),
      );
    }
    if (model.canEnable) {
      buttons.add(
        _button(
          'Ligar espelho',
          kind: TainaButtonKind.primary,
          loading: model.actionRunning,
          enabled: !model.actionRunning,
          onPressed: () => unawaited(model.enable()),
        ),
      );
    }
    if (model.canOpenSettings) {
      buttons.add(
        _button(
          'Abrir Ajustes',
          kind: TainaButtonKind.secondary,
          enabled: !model.actionRunning,
          onPressed: () => unawaited(model.openSettings()),
        ),
      );
    }
    if (model.canChooseMore) {
      buttons.add(
        _button(
          'Escolher mais fotos',
          kind: TainaButtonKind.secondary,
          enabled: !model.actionRunning,
          onPressed: () => unawaited(model.chooseMore()),
        ),
      );
    }
    if (model.canDisable) {
      buttons.add(
        _button(
          'Desligar neste aparelho',
          kind: TainaButtonKind.secondary,
          enabled: !model.actionRunning,
          onPressed: () => unawaited(model.disable()),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < buttons.length; index++) ...[
          if (index > 0) const SizedBox(height: TainaSpacing.space2),
          buttons[index],
        ],
      ],
    );
  }

  Widget _button(
    String title, {
    required TainaButtonKind kind,
    required bool enabled,
    required VoidCallback onPressed,
    bool loading = false,
  }) => TainaButton(
    title: title,
    kind: kind,
    loading: loading,
    action: enabled ? onPressed : null,
  );

  Widget _networkCard(MirrorStatusModel model) {
    return TainaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Somente no Wi-Fi',
                  style: TainaTypography.body.copyWith(
                    color: TainaPalette.textPrimary,
                  ),
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
          Text(
            model.wifiOnly
                ? 'Esta escolha vale para os próximos envios.'
                : 'Esta escolha vale para os próximos envios, que também '
                      'podem usar dados móveis.',
            style: TainaTypography.caption.copyWith(
              color: TainaPalette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  void _openStorage(BuildContext context) {
    final callback = onOpenStorage;
    if (callback != null) {
      callback();
      return;
    }
    context.go(AppRoutes.storage);
  }
}

TainaStatusState _statusState(MirrorStatusKind kind) => switch (kind) {
  MirrorStatusKind.quotaPaused => TainaStatusState.attention,
  MirrorStatusKind.permissionRevoked ||
  MirrorStatusKind.failed => TainaStatusState.problem,
  MirrorStatusKind.disabled ||
  MirrorStatusKind.preparing => TainaStatusState.unknown,
  MirrorStatusKind.sending => TainaStatusState.attention,
  MirrorStatusKind.idle => TainaStatusState.ok,
};

final class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(TainaSpacing.space4),
    children: const [SkeletonView(kind: TainaSkeletonKind.card)],
  );
}
