import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import 'file_row.dart';
import 'files_logic.dart';
import 'files_view_model.dart';

/// The list contents inside the Documents service scroll view.
final class BrowserList extends StatelessWidget {
  const BrowserList({
    required this.onUpload,
    required this.onOpenFolder,
    required this.onOpenFile,
    required this.onPublish,
    this.onMoreFolder,
    this.onMoreFile,
    this.canManageFolder,
    this.tab = TainaDocumentTab.casa,
    this.folder,
    super.key,
  });

  final VoidCallback onUpload;
  final ValueChanged<Folder> onOpenFolder;
  final ValueChanged<FileRecord> onOpenFile;
  final Future<void> Function(FileRecord file) onPublish;
  final ValueChanged<Folder>? onMoreFolder;
  final ValueChanged<FileRecord>? onMoreFile;
  final bool Function(Folder folder)? canManageFolder;
  final TainaDocumentTab tab;
  final Folder? folder;

  bool _showsFolderMenu(Folder folder) =>
      onMoreFolder != null && (canManageFolder?.call(folder) ?? false);

  @override
  Widget build(BuildContext context) {
    final model = context.watch<FilesViewModel>();
    if (model.isEmpty) return _emptyState(model);

    final rows = <Widget>[
      for (final child in model.entries.folders)
        TainaListRow(
          kind: TainaListRowKind.folder,
          title: child.name,
          meta: 'Pasta',
          trailing: _showsFolderMenu(child)
              ? TainaListRowTrailing.kebab
              : TainaListRowTrailing.chevron,
          trailingLabel: _showsFolderMenu(child) ? 'Ações da pasta' : null,
          onTrailingPressed: _showsFolderMenu(child)
              ? () => onMoreFolder!(child)
              : null,
          onTap: () => onOpenFolder(child),
        ),
      for (final file in model.entries.files)
        FileRow(
          file: file,
          thumbnails: model.session.thumbnails,
          tab: tab,
          me: model.session.identity,
          names: model.ownerNames,
          onTap: () => onOpenFile(file),
          onMore: onMoreFile == null ? null : () => onMoreFile!(file),
        ),
      for (final file in model.entries.files)
        if (model.showsPublishAction(file))
          TainaListRow(
            kind: TainaListRowKind.file,
            title: FilesLogic.zonaActionLabel(Zona.casa),
            meta: 'Este envio está na sua casa.',
            trailing: TainaListRowTrailing.action,
            trailingLabel: model.publishingRkey == file.rkey
                ? 'Publicando'
                : 'Publicar',
            onTrailingPressed: model.publishingRkey == file.rkey
                ? null
                : () => unawaited(onPublish(file)),
            showDivider: false,
          ),
    ];

    return SliverMainAxisGroup(
      slivers: [
        if (model.entries.files.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                TainaSpacing.space4,
                TainaSpacing.space2,
                TainaSpacing.space4,
                TainaSpacing.space2,
              ),
              child: TainaText(
                folder == null
                    ? FilesLogic.documentCountLabel(
                        tab: tab,
                        count:
                            model.entries.files.length +
                            model.entries.folders.length,
                        hasMore: model.nextCursor != null,
                      )
                    : FilesLogic.folderCountLabel(
                        count:
                            model.entries.files.length +
                            model.entries.folders.length,
                        hasMore: model.nextCursor != null,
                      ),
                style: TainaTypography.bodySm,
                color: TainaPalette.textSecondary,
              ),
            ),
          ),
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index],
        ),
        if (model.nextCursor != null)
          SliverToBoxAdapter(
            child: _LoadMoreSentinel(
              model: model,
              key: ValueKey(model.nextCursor),
            ),
          ),
      ],
    );
  }

  Widget _emptyState(FilesViewModel model) {
    if (model.loading ||
        (model.lastFilteredPageEmpty &&
            model.nextCursor != null &&
            !model.moreError)) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: TainaLoadingList(),
      );
    }
    if (model.moreError && model.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(TainaSpacing.space4),
            child: ErrorCard(
              title: 'Não foi possível carregar mais arquivos.',
              body: '',
              retry: () => unawaited(model.loadMore()),
            ),
          ),
        ),
      );
    }
    final error = model.error;
    if (error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(TainaSpacing.space4),
            child: ErrorCard(
              title: 'Não conseguimos carregar os arquivos.',
              body: error.message,
              retry: () => unawaited(model.load()),
            ),
          ),
        ),
      );
    }

    final isFolder = folder != null;
    final (String title, String body) = switch ((isFolder, tab)) {
      (true, _) => (
        'Esta pasta está vazia',
        'Envie um arquivo ou crie uma pasta para organizar.',
      ),
      (false, TainaDocumentTab.praca) => (
        'A praça está vazia',
        'Quando alguém publicar um arquivo na praça, ele aparece aqui para toda a comunidade.',
      ),
      (false, TainaDocumentTab.casa) => (
        'Sua casa está vazia',
        'Envie um arquivo. Ele fica só com você até você publicar na praça.',
      ),
      (false, TainaDocumentTab.lixeira) => (
        'Lixeira vazia',
        'Nada foi apagado.',
      ),
    };
    final showUploadAction = !isFolder && tab == TainaDocumentTab.casa;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(TainaSpacing.space6),
          child: EmptyStateView(
            icon: isFolder ? TainaIcon.folder : TainaIcon.file,
            title: title,
            body: body,
            actionLabel: showUploadAction ? 'Enviar um arquivo' : null,
            onAction: showUploadAction ? onUpload : null,
          ),
        ),
      ),
    );
  }
}

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
    if (widget.model.moreError || widget.model.lastFilteredPageEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.model.loadMore());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.model.moreError) {
      return Padding(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        child: ErrorCard(
          title: 'Não foi possível carregar mais arquivos.',
          body: '',
          retry: () => unawaited(widget.model.loadMore()),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(TainaSpacing.space4),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
