import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/storage/storage_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The vault's size: used against the quota, broken down by kind, with the
/// counts and what the trash holds. Read only, for every morador; the quota is
/// the zeladora's act from this screen.
final class StorageScreen extends StatefulWidget {
  const StorageScreen({required this.session, super.key});

  final SessionGateway session;

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
      child: const _StorageView(),
    );
  }
}

final class _StorageView extends StatelessWidget {
  const _StorageView();

  @override
  Widget build(BuildContext context) {
    final StorageModel model = context.watch<StorageModel>();
    final StorageStats? stats = model.stats;
    return Scaffold(
      appBar: AppBar(title: const Text('Armazenamento')),
      body: SafeArea(
        child: switch (stats) {
          final StorageStats value => _panel(context, model, value),
          null when model.error != null => TainaErrorState(
            error: model.error!,
            onRetry: model.load,
          ),
          null => const TainaLoadingList(),
        },
      ),
    );
  }

  Widget _panel(BuildContext context, StorageModel model, StorageStats stats) {
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        children: [
          _usageCard(stats),
          const SizedBox(height: TainaSpacing.space3),
          TainaText(
            'Só entra o que está na praça, a sua casa e o que te deixarem ver. '
            'A casa dos outros fica de fora.',
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
          ),
          const SizedBox(height: TainaSpacing.space5),
          _kindList(stats),
          const SizedBox(height: TainaSpacing.space3),
          TainaText(
            'Soma do que você vê: '
            '${TainaFormat.bytes(StorageModel.byKindTotal(stats))}',
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
          ),
          const SizedBox(height: TainaSpacing.space5),
          _counts(stats),
          if (model.isZelador) ...[
            const SizedBox(height: TainaSpacing.space5),
            _quotaCard(context, model, stats),
          ],
        ],
      ),
    );
  }

  /// The big card: the used bytes, the quota line, the bar by kind.
  Widget _usageCard(StorageStats stats) {
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TainaText(
            'Espaço da comunidade',
            style: TainaTypography.overline,
            uppercase: true,
            color: TainaPalette.textMuted,
          ),
          const SizedBox(height: TainaSpacing.space1),
          TainaText(
            TainaFormat.bytes(stats.usedBytes),
            style: TainaTypography.display.copyWith(
              fontFamily: TainaFonts.mono,
            ),
            color: TainaPalette.textPrimary,
          ),
          const SizedBox(height: TainaSpacing.space2),
          _quotaLine(stats),
          const SizedBox(height: TainaSpacing.space3),
          _UsageBar(segments: StorageModel.segments(stats)),
          const SizedBox(height: TainaSpacing.space2),
          TainaText(
            'Uso por tipo',
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
          ),
        ],
      ),
    );
  }

  /// "de X usados" with the free room beside it, or the absence of a limit
  /// said as a state. The color never works alone: the word "livres" carries
  /// the meaning, the color only underlines it. A limit set below the use says
  /// so, instead of a negative number of livres.
  Widget _quotaLine(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    if (quota == null) {
      return TainaText(
        'Sem limite definido.',
        style: TainaTypography.bodySm,
        color: TainaPalette.textMuted,
      );
    }
    if (StorageModel.isOverQuota(stats)) {
      return Row(
        children: [
          Expanded(
            child: TainaText(
              'de ${TainaFormat.bytes(quota)} usados',
              style: TainaTypography.bodySm,
              color: TainaPalette.textMuted,
            ),
          ),
          const SizedBox(width: TainaSpacing.space2),
          Expanded(
            child: TainaText(
              'O limite está abaixo do que já está guardado.',
              style: TainaTypography.bodySm,
              color: TainaPalette.feedbackWarning,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: TainaText(
            'de ${TainaFormat.bytes(quota)} usados',
            style: TainaTypography.bodySm,
            color: TainaPalette.textMuted,
          ),
        ),
        TainaText(
          '${TainaFormat.bytes(quota - stats.usedBytes)} livres',
          style: TainaTypography.bodySm,
          color: StorageModel.isLowFree(stats)
              ? TainaPalette.feedbackWarning
              : TainaPalette.feedbackSuccess,
        ),
      ],
    );
  }

  /// The zeladora's limit card: the number as it stands and the way to change
  /// it. The act is the box's to accept or refuse.
  Widget _quotaCard(
    BuildContext context,
    StorageModel model,
    StorageStats stats,
  ) {
    final int? quota = stats.quotaBytes;
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TainaText(
            'Limite da comunidade',
            style: TainaTypography.overline,
            uppercase: true,
            color: TainaPalette.textMuted,
          ),
          const SizedBox(height: TainaSpacing.space2),
          TainaText(
            quota != null
                ? '${TainaFormat.bytes(quota)} por mês de espaço para os '
                      'arquivos de todo mundo.'
                : 'Nenhum limite definido. A caixa usa o espaço que o disco '
                      'tem.',
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
          ),
          const SizedBox(height: TainaSpacing.space3),
          TainaSecondaryButton(
            label: 'Mudar o limite',
            onPressed: () => _openQuota(context, model),
          ),
        ],
      ),
    );
  }

  Widget _kindList(StorageStats stats) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final StorageKindLine line in StorageModel.kinds(stats))
          Padding(
            padding: const EdgeInsets.only(bottom: TainaSpacing.space2),
            child: TainaRowCard(
              child: Row(
                children: [
                  Container(
                    width: TainaSizes.navDot,
                    height: TainaSizes.navDot,
                    decoration: BoxDecoration(
                      color: _kindColor(line.kind),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: TainaSpacing.space3),
                  TainaText(
                    line.kind.label,
                    style: TainaTypography.body,
                    color: TainaPalette.textPrimary,
                  ),
                  const Spacer(),
                  TainaText(
                    TainaFormat.bytes(line.bytes),
                    style: TainaTypography.monoSm,
                    color: TainaPalette.textPrimary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _counts(StorageStats stats) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _countRow(
          icon: Icons.folder_outlined,
          label: 'Arquivos',
          value: '${stats.files}',
        ),
        const SizedBox(height: TainaSpacing.space2),
        _countRow(
          icon: Icons.photo_outlined,
          label: 'Fotos',
          value: '${stats.photos}',
        ),
        const SizedBox(height: TainaSpacing.space2),
        _countRow(
          icon: Icons.delete_outline,
          label: 'Lixeira',
          value: StorageModel.trashSummary(stats.trash),
        ),
      ],
    );
  }

  Widget _countRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return TainaRowCard(
      child: Row(
        children: [
          Icon(icon, size: TainaFontSizes.md, color: TainaPalette.serviceYbira),
          const SizedBox(width: TainaSpacing.space3),
          TainaText(
            label,
            style: TainaTypography.body,
            color: TainaPalette.textPrimary,
          ),
          const Spacer(),
          TainaText(
            value,
            style: TainaTypography.monoSm,
            color: TainaPalette.textPrimary,
          ),
        ],
      ),
    );
  }

  Future<void> _openQuota(BuildContext context, StorageModel model) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _QuotaSheet(
        model: model,
        onFailure: (TainaError error) {
          if (context.mounted) _showFailure(context, error);
        },
      ),
    );
  }

  void _showFailure(BuildContext context, TainaError error) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Não deu certo'),
        content: Text(error.message),
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

Color _kindColor(StorageKind kind) {
  return switch (kind) {
    StorageKind.photos => TainaPalette.serviceJaci,
    StorageKind.videos => TainaPalette.serviceVideo,
    StorageKind.documents => TainaPalette.serviceYbira,
    StorageKind.others => TainaPalette.textFaint,
  };
}

/// The segmented bar: one fill per kind with bytes, widest first, on a quiet
/// track. The height is the progress token, the colors the same the legend
/// rows use.
final class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.segments});

  final List<StorageSegment> segments;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: TainaRadii.smAll,
      child: SizedBox(
        height: TainaSizes.progress,
        child: ColoredBox(
          color: TainaPalette.surfaceHigh,
          child: Row(
            children: [
              for (final StorageSegment segment in segments)
                Expanded(
                  flex: (segment.fraction * 1000)
                      .round()
                      .clamp(1, 1000)
                      .toInt(),
                  child: ColoredBox(color: _kindColor(segment.kind)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The zeladora's limit form: whole gigabytes, the number the box's quota card
/// speaks. Below the current use is allowed and said on the spot; the box has
/// the last word.
final class _QuotaSheet extends StatefulWidget {
  const _QuotaSheet({required this.model, required this.onFailure});

  final StorageModel model;
  final ValueChanged<TainaError> onFailure;

  @override
  State<_QuotaSheet> createState() => _QuotaSheetState();
}

final class _QuotaSheetState extends State<_QuotaSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: '${StorageModel.gigabytes(widget.model.stats?.quotaBytes)}',
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _gigabytes {
    final int? parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 1) return null;
    return parsed;
  }

  String? get _warning {
    final int? gigabytes = _gigabytes;
    final int? used = widget.model.stats?.usedBytes;
    if (gigabytes == null || used == null) return null;
    final int bytes = StorageModel.bytesFromGigabytes(gigabytes);
    return bytes < used
        ? 'Este limite é menor do que já está guardado. Nada é apagado; a '
              'caixa só não aceita mais nada até o limite subir.'
        : null;
  }

  Future<void> _save() async {
    final int? gigabytes = _gigabytes;
    if (gigabytes == null) return;
    setState(() => _saving = true);
    final result = await widget.model.setQuota(
      StorageModel.bytesFromGigabytes(gigabytes),
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
    final bool valid = _gigabytes != null;
    final String? warning = _warning;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(TainaSpacing.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TainaText(
              'Mudar o limite',
              style: TainaTypography.h3,
              color: TainaPalette.textPrimary,
            ),
            const SizedBox(height: TainaSpacing.space2),
            TainaText(
              'O espaço total da comunidade, em gigabytes. A lixeira conta até '
              'a limpeza passar.',
              style: TainaTypography.bodySm,
              color: TainaPalette.textSecondary,
            ),
            const SizedBox(height: TainaSpacing.space4),
            TainaTextField(
              label: 'Gigabytes',
              controller: _controller,
              placeholder: '250',
              help: 'Por exemplo: 250',
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            if (warning != null) ...[
              const SizedBox(height: TainaSpacing.space2),
              TainaText(
                warning,
                style: TainaTypography.caption,
                color: TainaPalette.feedbackWarning,
              ),
            ],
            const SizedBox(height: TainaSpacing.space4),
            TainaPrimaryButton(
              label: 'Salvar',
              loading: _saving,
              onPressed: valid && !_saving ? () => unawaited(_save()) : null,
            ),
            const SizedBox(height: TainaSpacing.space2),
            TainaSecondaryButton(
              label: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
