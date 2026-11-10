import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/saude/saude_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The box's health, in sentences a person reads: the disk, the last backup
/// and the queued work.
///
/// Read only, for every morador; the backup trigger is the zeladora's and the
/// server enforces it.
final class SaudeScreen extends StatefulWidget {
  const SaudeScreen({required this.session, super.key});

  final SessionGateway session;

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
      child: const _SaudeView(),
    );
  }
}

final class _SaudeView extends StatelessWidget {
  const _SaudeView();

  @override
  Widget build(BuildContext context) {
    final SaudeModel model = context.watch<SaudeModel>();
    final Saude? saude = model.saude;
    return Scaffold(
      appBar: AppBar(title: const Text('Saúde da comunidade')),
      body: SafeArea(
        child: switch (saude) {
          final Saude value => _panel(context, model, value),
          null when model.error != null => TainaErrorState(
            error: model.error!,
            onRetry: model.load,
          ),
          null => const TainaLoadingList(),
        },
      ),
    );
  }

  Widget _panel(BuildContext context, SaudeModel model, Saude saude) {
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        children: [
          for (final SaudeRow row in SaudeModel.rows(saude))
            Padding(
              padding: const EdgeInsets.only(bottom: TainaSpacing.space3),
              child: TainaRowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SaudeRowView(row: row),
                    if (model.isZelador &&
                        row.label == SaudeModel.backupLabel) ...[
                      const SizedBox(height: TainaSpacing.space3),
                      _backupButton(context, model),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The zeladora's own act: the box queues the backup and answers. The copy
  /// says queued, because that is what happened.
  Widget _backupButton(BuildContext context, SaudeModel model) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TainaSecondaryButton(
          label: model.triggering ? 'Agendando...' : 'Fazer backup agora',
          onPressed: model.triggering
              ? null
              : () => unawaited(_backupNow(context, model)),
        ),
        const SizedBox(height: TainaSpacing.space2),
        TainaText(
          'O backup fica na fila da caixa e roda em seguida.',
          style: TainaTypography.caption,
          color: TainaPalette.textMuted,
        ),
      ],
    );
  }

  Future<void> _backupNow(BuildContext context, SaudeModel model) async {
    final result = await model.backupNow();
    if (!context.mounted) return;
    switch (result) {
      case Ok():
        _showFlash(
          context,
          'Backup agendado',
          'A caixa faz o backup em seguida. A linha do último backup muda '
              'quando ele terminar.',
        );
      case Err(:final error):
        _showFlash(context, 'Não deu certo', error.message);
    }
    await model.load();
  }

  void _showFlash(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }
}

/// One row: the icon and the label, the facts as lines, the warning when the
/// fact needs one.
final class _SaudeRowView extends StatelessWidget {
  const _SaudeRowView({required this.row});

  final SaudeRow row;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              _icon(row.icon),
              size: TainaFontSizes.md,
              color: TainaPalette.textMuted,
            ),
            const SizedBox(width: TainaSpacing.space3),
            TainaText(
              row.label,
              style: TainaTypography.label,
              color: TainaPalette.textPrimary,
            ),
          ],
        ),
        for (final String line in row.lines) ...[
          const SizedBox(height: TainaSpacing.space1),
          TainaText(
            line,
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
          ),
        ],
        if (row.warning case final String warning) ...[
          const SizedBox(height: TainaSpacing.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: TainaFontSizes.sm,
                color: TainaPalette.feedbackWarning,
              ),
              const SizedBox(width: TainaSpacing.space2),
              Expanded(
                child: TainaText(
                  warning,
                  style: TainaTypography.bodySm,
                  color: TainaPalette.feedbackWarning,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  IconData _icon(SaudeRowIcon icon) {
    return switch (icon) {
      SaudeRowIcon.disk => Icons.storage_outlined,
      SaudeRowIcon.backup => Icons.shield_outlined,
      SaudeRowIcon.jobs => Icons.schedule_outlined,
    };
  }
}
