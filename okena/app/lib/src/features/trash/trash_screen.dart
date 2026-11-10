import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_gateway.dart';
import '../files/dialogs.dart';
import 'trash_logic.dart';
import 'trash_view_model.dart';

/// The lixeira: what was discarded in the last 30 days, with restore.
/// Mirrors the web's TrashLive, retention line and all.
final class TrashScreen extends StatelessWidget {
  const TrashScreen({required this.session, this.model, super.key});

  final SessionGateway session;

  /// An already built model, for tests and previews.
  final TrashViewModel? model;

  @override
  Widget build(BuildContext context) {
    const scaffold = _TrashScaffold();
    final injected = model;
    if (injected != null) {
      return ChangeNotifierProvider<TrashViewModel>.value(
        value: injected,
        child: scaffold,
      );
    }
    return ChangeNotifierProvider<TrashViewModel>(
      create: (context) {
        final created = TrashViewModel(session: session);
        unawaited(created.load());
        return created;
      },
      child: scaffold,
    );
  }
}

final class _TrashScaffold extends StatelessWidget {
  const _TrashScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lixeira')),
      body: const _TrashList(),
    );
  }
}

final class _TrashList extends StatefulWidget {
  const _TrashList();

  @override
  State<_TrashList> createState() => _TrashListState();
}

final class _TrashListState extends State<_TrashList> {
  Future<void> _restore(String rkey) async {
    final model = context.read<TrashViewModel>();
    final result = await model.restore(rkey: rkey);
    if (!mounted) return;
    final error = result.error;
    if (error != null) {
      await showFailure(
        context,
        error.message.isEmpty
            ? 'Não foi possível restaurar o arquivo.'
            : error.message,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<TrashViewModel>();
    if (model.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: model.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: TainaSpacing.space16),
            _state(model),
          ],
        ),
      );
    }
    final cells = _cells(model);
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(TainaSpacing.space4),
        itemCount: cells.length,
        itemBuilder: (context, index) => cells[index],
      ),
    );
  }

  Widget _state(TrashViewModel model) {
    if (model.loading) return const TainaLoadingList();
    final error = model.error;
    if (error != null) {
      return TainaErrorState(error: error, onRetry: model.load);
    }
    return const TainaEmptyState(
      icon: Icons.delete_outline,
      title: 'Lixeira vazia',
      message: 'Nada esperando para ser apagado.',
    );
  }

  List<Widget> _cells(TrashViewModel model) {
    return [
      const TainaRowCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.schedule,
              size: TainaFontSizes.xl,
              color: TainaPalette.feedbackWarning,
            ),
            SizedBox(width: TainaSpacing.space3),
            Expanded(
              child: TainaText(
                'Itens são apagados para sempre após '
                '${TrashLogic.retentionDays} dias na lixeira.',
                style: TainaTypography.bodySm,
                color: TainaPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: TainaSpacing.space4),
      TainaText(
        TrashLogic.countLabel(
          count: model.items.length,
          hasMore: model.nextCursor != null,
        ),
        style: TainaTypography.overline,
        color: TainaPalette.textMuted,
        uppercase: true,
      ),
      const SizedBox(height: TainaSpacing.space3),
      for (final file in model.items) ...[
        _TrashRow(
          file: file,
          restoring: model.restoringRkey == file.rkey,
          onRestore: () => unawaited(_restore(file.rkey)),
        ),
        const SizedBox(height: TainaSpacing.space2),
      ],
      if (model.nextCursor != null)
        _LoadMoreSentinel(model: model, key: ValueKey(model.nextCursor)),
    ];
  }
}

/// One discarded file: the mime glyph, the name, the size and the trash meta
/// (in warning color when the purge is close), and the restore.
final class _TrashRow extends StatelessWidget {
  const _TrashRow({
    required this.file,
    required this.restoring,
    required this.onRestore,
  });

  final FileRecord file;
  final bool restoring;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final warning = TrashLogic.isWarning(file);
    return TainaRowCard(
      child: Row(
        children: [
          Container(
            width: TainaSizes.controlMd,
            height: TainaSizes.controlMd,
            decoration: const BoxDecoration(
              color: TainaPalette.surfaceRaised,
              borderRadius: TainaRadii.smAll,
            ),
            child: Icon(
              _glyph(TrashLogic.glyph(file.mime)),
              size: TainaFontSizes.xl,
              color: TainaPalette.textFaint,
            ),
          ),
          const SizedBox(width: TainaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TainaText(
                  file.name,
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: TainaSpacing.space1),
                TainaText(
                  '${TainaFormat.bytes(file.size)} / '
                  '${TrashLogic.meta(file)}',
                  style: TainaTypography.monoSm,
                  color: warning
                      ? TainaPalette.feedbackWarning
                      : TainaPalette.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(width: TainaSpacing.space2),
          if (restoring)
            const SizedBox(
              width: TainaSizes.touch,
              height: TainaSizes.touch,
              child: Center(
                child: SizedBox(
                  width: TainaSizes.controlSm / 2,
                  height: TainaSizes.controlSm / 2,
                  child: CircularProgressIndicator(
                    strokeWidth: TainaSizes.thick,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'Restaurar',
              color: TainaPalette.serviceYbira,
              onPressed: onRestore,
            ),
        ],
      ),
    );
  }

  static IconData _glyph(TrashGlyph glyph) {
    return switch (glyph) {
      TrashGlyph.photo => Icons.photo_outlined,
      TrashGlyph.film => Icons.movie_outlined,
      TrashGlyph.audio => Icons.graphic_eq,
      TrashGlyph.pdf => Icons.picture_as_pdf_outlined,
      TrashGlyph.text => Icons.description_outlined,
      TrashGlyph.document => Icons.insert_drive_file_outlined,
    };
  }
}

/// The next page: a spinner that loads on sight, or the retry when a page
/// failed. It only exists while the server still has rows.
final class _LoadMoreSentinel extends StatefulWidget {
  const _LoadMoreSentinel({required this.model, super.key});

  final TrashViewModel model;

  @override
  State<_LoadMoreSentinel> createState() => _LoadMoreSentinelState();
}

final class _LoadMoreSentinelState extends State<_LoadMoreSentinel> {
  @override
  void initState() {
    super.initState();
    _kick();
  }

  void _kick() {
    if (widget.model.moreError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.model.loadMore());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.model.moreError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: TainaSpacing.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TainaText(
              'Não foi possível carregar mais itens.',
              style: TainaTypography.caption,
              color: TainaPalette.textMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: TainaSpacing.space2),
            TainaSecondaryButton(
              label: 'Tentar de novo',
              onPressed: () => unawaited(widget.model.loadMore()),
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: TainaSpacing.space4),
      child: Center(
        child: SizedBox(
          width: TainaSizes.controlSm / 2,
          height: TainaSizes.controlSm / 2,
          child: CircularProgressIndicator(
            strokeWidth: TainaSizes.thick,
            color: TainaPalette.textMuted,
          ),
        ),
      ),
    );
  }
}
