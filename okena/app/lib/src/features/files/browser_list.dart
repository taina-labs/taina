import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import 'file_row.dart';
import 'files_logic.dart';
import 'files_view_model.dart';

/// The list the root and any folder show: one loading logic, the model's
/// pure transitions, no copy between screens. The screen names where an
/// upload lands and the freshly uploaded rows still carry the one-tap publish
/// to the praca.
final class BrowserList extends StatelessWidget {
  const BrowserList({
    required this.destinationZona,
    required this.onNewFolder,
    required this.onOpenFolder,
    required this.onOpenFile,
    required this.onPublish,
    super.key,
  });

  final Zona destinationZona;
  final VoidCallback onNewFolder;
  final ValueChanged<Folder> onOpenFolder;
  final ValueChanged<FileRecord> onOpenFile;
  final Future<void> Function(FileRecord file) onPublish;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<FilesViewModel>();
    if (model.isEmpty) {
      return RefreshIndicator(
        onRefresh: model.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: TainaSpacing.space16),
            _state(context, model),
          ],
        ),
      );
    }
    final cells = _cells(context, model);
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

  Widget _state(BuildContext context, FilesViewModel model) {
    if (model.loading) {
      return const TainaLoadingList();
    }
    final error = model.error;
    if (error != null) {
      return TainaErrorState(error: error, onRetry: model.load);
    }
    return TainaEmptyState(
      icon: Icons.folder_outlined,
      title: 'Esta pasta está vazia',
      message:
          'Guarde um arquivo com o botão de enviar, no topo da tela, ou crie '
          'uma pasta para organizar. '
          '${FilesLogic.uploadDestinationMessage(destinationZona)}',
      actionLabel: 'Nova pasta',
      onAction: onNewFolder,
    );
  }

  List<Widget> _cells(BuildContext context, FilesViewModel model) {
    final thumbnails = model.session.thumbnails;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: TainaSpacing.space2),
        child: TainaText(
          FilesLogic.uploadDestinationMessage(destinationZona),
          style: TainaTypography.bodySm,
          color: TainaPalette.textMuted,
        ),
      ),
      for (final folder in model.entries.folders) ...[
        _FolderRow(folder: folder, onTap: () => onOpenFolder(folder)),
        const SizedBox(height: TainaSpacing.space2),
      ],
      if (model.entries.files.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(
            top: TainaSpacing.space2,
            bottom: TainaSpacing.space2,
          ),
          child: TainaText(
            FilesLogic.countLabel(
              count: model.entries.files.length,
              hasMore: model.nextCursor != null,
            ),
            style: TainaTypography.overline,
            color: TainaPalette.textMuted,
            uppercase: true,
          ),
        ),
      ],
      for (final file in model.entries.files) ...[
        FileRow(
          file: file,
          thumbnails: thumbnails,
          onTap: () => onOpenFile(file),
        ),
        if (model.showsPublishAction(file))
          Padding(
            padding: const EdgeInsets.only(top: TainaSpacing.space2),
            child: _PublishAction(
              publishing: model.publishingRkey == file.rkey,
              disabled: model.publishingRkey != null,
              onTap: () => onPublish(file),
            ),
          ),
        const SizedBox(height: TainaSpacing.space2),
      ],
      if (model.nextCursor != null)
        _LoadMoreSentinel(model: model, key: ValueKey(model.nextCursor)),
    ];
  }
}

final class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder, required this.onTap});

  final Folder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TainaRowCard(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(
            Icons.folder_rounded,
            size: TainaFontSizes.xl,
            color: TainaPalette.serviceYbira,
          ),
          const SizedBox(width: TainaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TainaText(
                  folder.name,
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (folder.zona == Zona.praca) ...[
                  const SizedBox(height: TainaSpacing.space1),
                  const TainaZonaBadge.praca(),
                ],
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: TainaFontSizes.md,
            color: TainaPalette.textFaint,
          ),
        ],
      ),
    );
  }
}

/// The completed upload's action, its own card under the row so the tap never
/// shares a surface with the navigation. While the file stays in the casa,
/// the action is the way to the praca.
final class _PublishAction extends StatelessWidget {
  const _PublishAction({
    required this.publishing,
    required this.disabled,
    required this.onTap,
  });

  final bool publishing;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TainaRowCard(
      onTap: disabled ? null : onTap,
      child: Row(
        children: [
          if (publishing)
            const SizedBox(
              width: TainaSizes.controlMd,
              height: TainaSizes.controlMd,
              child: Padding(
                padding: EdgeInsets.all(TainaSpacing.space3),
                child: CircularProgressIndicator(
                  strokeWidth: TainaSizes.thick,
                  color: TainaPalette.serviceYbira,
                ),
              ),
            )
          else
            const Icon(
              Icons.people_alt_rounded,
              size: TainaFontSizes.xl,
              color: TainaPalette.serviceYbira,
            ),
          const SizedBox(width: TainaSpacing.space3),
          Expanded(
            child: TainaText(
              FilesLogic.zonaActionLabel(Zona.casa),
              style: TainaTypography.label,
              color: TainaPalette.serviceYbira,
            ),
          ),
        ],
      ),
    );
  }
}

/// The next page of files: a spinner that loads on sight, or the retry when a
/// page failed. It only exists while the server still has rows.
final class _LoadMoreSentinel extends StatefulWidget {
  const _LoadMoreSentinel({required this.model, super.key});

  final FilesViewModel model;

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
              'Não foi possível carregar mais arquivos.',
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
