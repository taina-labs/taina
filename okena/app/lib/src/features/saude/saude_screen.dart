import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/saude/saude_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The box's health, in four short status lines.
final class SaudeScreen extends StatefulWidget {
  const SaudeScreen({required this.session, this.onBack, super.key});

  final SessionGateway session;
  final VoidCallback? onBack;

  @override
  State<SaudeScreen> createState() => _SaudeScreenState();
}

final class _SaudeScreenState extends State<SaudeScreen> {
  late final SaudeModel _model;

  @override
  void initState() {
    super.initState();
    _model = SaudeModel(gateway: widget.session);
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SaudeModel>.value(
      value: _model,
      child: _SaudeView(onBack: widget.onBack),
    );
  }
}

final class _SaudeView extends StatelessWidget {
  const _SaudeView({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final SaudeModel model = context.watch<SaudeModel>();
    final Saude? saude = model.saude;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: model.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              PageHeaderSliver(
                title: 'Saúde da comunidade',
                backLabel: 'Início',
                onBack: () => _handleBack(context),
              ),
              if (saude case final Saude value)
                _panel(context, model, value)
              else if (model.loading)
                const SliverPadding(
                  padding: EdgeInsets.all(TainaSpacing.space4),
                  sliver: SliverToBoxAdapter(
                    child: SkeletonView(kind: TainaSkeletonKind.listRow),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(TainaSpacing.space4),
                  sliver: SliverToBoxAdapter(
                    child: ErrorCard(
                      title: 'Não conseguimos falar com a nuvem agora.',
                      body: '',
                      retry: () => unawaited(model.load()),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, SaudeModel model, Saude saude) {
    final List<SaudeStatus> statuses = SaudeModel.statuses(saude);
    final SaudePanelState state = model.panelState;
    final String? zeladorName = model.zeladorNames.firstOrNull;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        TainaSpacing.space4,
        TainaSpacing.space2,
        TainaSpacing.space4,
        TainaSpacing.space6,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ESTADO DA NUVEM',
              style: TainaTypography.overline.copyWith(
                color: TainaPalette.textMuted,
              ),
            ),
            const SizedBox(height: TainaSpacing.space2),
            for (int index = 0; index < statuses.length; index++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: TainaSpacing.space4,
                ),
                child: StatusLine(
                  state: statuses[index].state,
                  title: statuses[index].title,
                ),
              ),
              if (index < statuses.length - 1)
                const Divider(
                  color: TainaPalette.borderSubtle,
                  height: TainaSizes.hairline,
                  thickness: TainaSizes.hairline,
                ),
            ],
            if (model.canTriggerBackup) ...[
              const SizedBox(height: TainaSpacing.space5),
              TainaPrimaryButton(
                label: model.triggering ? 'Agendando...' : 'Fazer backup agora',
                loading: model.triggering,
                onPressed: model.triggering
                    ? null
                    : () => unawaited(_backupNow(model, context)),
              ),
            ],
            const SizedBox(height: TainaSpacing.space4),
            Text(
              SaudeModel.footer(state, zeladorName: zeladorName),
              style: TainaTypography.bodySm.copyWith(
                color: TainaPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleBack(BuildContext context) {
    final VoidCallback? callback = onBack;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _backupNow(SaudeModel model, BuildContext context) async {
    final TainaResult<void> result = await model.backupNow();
    if (!context.mounted) return;

    switch (result) {
      case Ok():
        _showToast(context, 'Backup agendado.', TainaToastKind.info);
      case Err(:final error):
        _showToast(context, error.message, TainaToastKind.error);
    }
  }

  void _showToast(BuildContext context, String text, TainaToastKind kind) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: TainaToast(kind: kind, text: text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      );
  }
}
