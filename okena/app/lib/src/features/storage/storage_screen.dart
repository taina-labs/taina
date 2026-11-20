import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/storage/storage_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The community-wide storage portrait and, for zeladores, the shared quota.
final class StorageScreen extends StatefulWidget {
  const StorageScreen({required this.session, this.onBack, super.key});

  final SessionGateway session;
  final VoidCallback? onBack;

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

final class _StorageScreenState extends State<StorageScreen> {
  late final StorageModel _model;

  @override
  void initState() {
    super.initState();
    _model = StorageModel(gateway: widget.session);
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StorageModel>.value(
      value: _model,
      child: _StorageView(onBack: widget.onBack),
    );
  }
}

final class _StorageView extends StatelessWidget {
  const _StorageView({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final StorageModel model = context.watch<StorageModel>();
    final StorageStats? stats = model.stats;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: model.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              PageHeaderSliver(
                title: 'Armazenamento',
                backLabel: 'Início',
                onBack: () => _handleBack(context),
              ),
              if (stats case final StorageStats value)
                _panel(context, model, value)
              else if (model.loading)
                const SliverPadding(
                  padding: EdgeInsets.all(TainaSpacing.space4),
                  sliver: SliverToBoxAdapter(
                    child: SkeletonView(kind: TainaSkeletonKind.card, count: 1),
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

  Widget _panel(BuildContext context, StorageModel model, StorageStats stats) {
    final List<StorageZoneLine>? zones = StorageModel.zones(stats);
    final String? zeladorName = model.zeladorNames.firstOrNull;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        TainaSpacing.space4,
        TainaSpacing.space3,
        TainaSpacing.space4,
        TainaSpacing.space6,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StorageCard(
              detail: TainaStorageDetail.full,
              summary: StorageModel.summary(stats),
            ),
            if (zones != null) ...[
              const SizedBox(height: TainaSpacing.space5),
              Text(
                'O que ocupa espaço',
                style: TainaTypography.overline.copyWith(
                  color: TainaPalette.textMuted,
                ),
              ),
              const SizedBox(height: TainaSpacing.space2),
              for (int index = 0; index < zones.length; index++)
                TainaListRow(
                  kind: TainaListRowKind.civic,
                  title: zones[index].title,
                  meta: TainaFormat.bytes(zones[index].bytes),
                  leadingBuilder: (_) => TainaIconView(
                    icon: zones[index].icon,
                    color: TainaPalette.textSecondary,
                  ),
                  showDivider: index < zones.length - 1,
                ),
            ],
            if (model.isZelador) ...[
              const SizedBox(height: TainaSpacing.space4),
              TainaSecondaryButton(
                label: 'Mudar limite',
                onPressed: () => unawaited(_openQuota(context, model, stats)),
              ),
            ] else ...[
              const SizedBox(height: TainaSpacing.space4),
              Text(
                StorageModel.moradorFooter(zeladorName),
                style: TainaTypography.bodySm.copyWith(
                  color: TainaPalette.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openQuota(
    BuildContext context,
    StorageModel model,
    StorageStats stats,
  ) async {
    await TainaSheet.show<void>(
      context: context,
      title: 'Limite de espaço',
      isScrollControlled: true,
      child: _QuotaSheet(
        model: model,
        stats: stats,
        onFailure: (TainaError error) {
          if (context.mounted) _showToast(context, error.message);
        },
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

  void _showToast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: TainaToast(kind: TainaToastKind.error, text: text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      );
  }
}

final class _QuotaSheet extends StatefulWidget {
  const _QuotaSheet({
    required this.model,
    required this.stats,
    required this.onFailure,
  });

  final StorageModel model;
  final StorageStats stats;
  final ValueChanged<TainaError> onFailure;

  @override
  State<_QuotaSheet> createState() => _QuotaSheetState();
}

final class _QuotaSheetState extends State<_QuotaSheet> {
  late final TextEditingController _controller = TextEditingController(
    text:
        '${StorageModel.gigabytes(widget.stats.quotaBytes ?? StorageModel.diskBytes(widget.stats))}',
  );
  late bool _wholeDisk = widget.stats.quotaBytes == null;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _gigabytes {
    final int? parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 1) return null;
    final int? diskBytes = StorageModel.diskBytes(widget.stats);
    if (diskBytes != null && parsed > StorageModel.gigabytes(diskBytes)) {
      return null;
    }
    return parsed;
  }

  String get _help {
    final int? diskBytes = StorageModel.diskBytes(widget.stats);
    if (diskBytes == null) return 'Em GB.';
    return 'Em GB, de 1 a ${StorageModel.gigabytes(diskBytes)}.';
  }

  String? get _warning {
    final int? gigabytes = _gigabytes;
    if (_wholeDisk || gigabytes == null) return null;
    return StorageModel.bytesFromGigabytes(gigabytes) < widget.stats.usedBytes
        ? 'Este limite é menor do que já está guardado. Nada é apagado; a '
              'caixa só não aceita mais nada até o limite subir.'
        : null;
  }

  Future<void> _save() async {
    final int? gigabytes = _wholeDisk ? null : _gigabytes;
    if (!_wholeDisk && gigabytes == null) return;
    setState(() => _saving = true);
    final TainaResult<void> result = await widget.model.setQuota(
      gigabytes == null ? null : StorageModel.bytesFromGigabytes(gigabytes),
    );
    if (!mounted) return;
    switch (result) {
      case Ok():
        Navigator.of(context).pop();
      case Err(:final error):
        setState(() => _saving = false);
        widget.onFailure(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool valid = _wholeDisk || _gigabytes != null;
    final String? warning = _warning;
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TainaRadioCard(
            title: 'Usar o disco inteiro',
            description: 'A comunidade usa todo o disco.',
            selected: _wholeDisk,
            action: () => setState(() => _wholeDisk = true),
          ),
          const SizedBox(height: TainaSpacing.space2),
          TainaRadioCard(
            title: 'Definir um limite',
            selected: !_wholeDisk,
            action: () => setState(() => _wholeDisk = false),
          ),
          if (!_wholeDisk) ...[
            const SizedBox(height: TainaSpacing.space3),
            TainaTextField(
              label: 'Limite (GB)',
              controller: _controller,
              placeholder: _controller.text,
              help: _help,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
            ),
            if (warning != null) ...[
              const SizedBox(height: TainaSpacing.space2),
              Text(
                warning,
                style: TainaTypography.caption.copyWith(
                  color: TainaPalette.feedbackWarning,
                ),
              ),
            ],
          ],
          const SizedBox(height: TainaSpacing.space4),
          TainaPrimaryButton(
            label: 'Salvar',
            loading: _saving,
            onPressed: valid && !_saving ? () => unawaited(_save()) : null,
          ),
        ],
      ),
    );
  }
}
