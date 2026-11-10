import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import 'browser_list.dart';
import 'dialogs.dart';
import 'files_logic.dart';
import 'files_view_model.dart';
import 'folder_actions_view_model.dart';
import 'move_sheet.dart';

/// The scaffold the root and any folder share: the toolbar, the list, the
/// folder's own menu, and the pt-BR dialogs. One loading logic, one set of
/// confirmations.
final class BrowserScaffold extends StatefulWidget {
  const BrowserScaffold({
    required this.title,
    required this.destinationZona,
    this.folder,
    this.onOpenFolder,
    this.onOpenFile,
    this.onOpenTrash,
    this.onFolderChanged,
    this.onFolderDeleted,
    super.key,
  });

  final String title;
  final Zona destinationZona;

  /// The folder being browsed, null at the root. Its presence adds the menu
  /// with the folder's own acts.
  final Folder? folder;
  final ValueChanged<Folder>? onOpenFolder;
  final ValueChanged<FileRecord>? onOpenFile;
  final VoidCallback? onOpenTrash;
  final ValueChanged<Folder>? onFolderChanged;
  final VoidCallback? onFolderDeleted;

  @override
  State<BrowserScaffold> createState() => _BrowserScaffoldState();
}

final class _BrowserScaffoldState extends State<BrowserScaffold> {
  Future<void> _newFolder() async {
    final model = context.read<FilesViewModel>();
    final name = await showNamePrompt(
      context,
      title: 'Nova pasta',
      label: FilesLogic.newFolderName,
      help: FilesLogic.newFolderHint,
      confirmLabel: 'Criar',
    );
    if (!mounted || name == null) return;
    final result = await model.createFolder(name);
    if (!mounted) return;
    final error = result.error;
    if (error != null) await showFailure(context, error.message);
  }

  Future<void> _upload() async {
    final model = context.read<FilesViewModel>();
    final message = await model.pickAndUpload();
    if (!mounted || message == null) return;
    await showFailure(context, message);
  }

  Future<void> _publish(FileRecord file) async {
    final model = context.read<FilesViewModel>();
    final result = await model.publish(file);
    if (!mounted) return;
    final error = result.error;
    if (error != null) await showFailure(context, error.message);
  }

  // MARK: folder acts

  Future<void> _renameFolder(Folder folder) async {
    final actions = context.read<FolderActionsViewModel>();
    final name = await showNamePrompt(
      context,
      title: 'Renomear',
      label: 'Novo nome',
      initial: folder.name,
      confirmLabel: 'Renomear',
    );
    if (!mounted || name == null || name == folder.name) return;
    final result = await actions.rename(folder, name);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        widget.onFolderChanged?.call(value);
      case Err(:final error):
        await showFailure(context, error.message);
    }
  }

  Future<void> _moveFolder(Folder folder) async {
    final actions = context.read<FolderActionsViewModel>();
    final files = context.read<FilesViewModel>();
    await showMoveSheet(
      context,
      session: files.session,
      sourceRkey: folder.rkey,
      name: folder.name,
      isFolder: true,
      onPick: (parent) async {
        final result = await actions.move(folder, parent);
        if (!mounted) return result.map<void>((_) {});
        if (result case Ok(:final value)) {
          widget.onFolderChanged?.call(value);
        }
        return result.map<void>((_) {});
      },
    );
  }

  Future<void> _changeFolderZona(Folder folder) async {
    final actions = context.read<FolderActionsViewModel>();
    final target = folder.zona == Zona.casa ? Zona.praca : Zona.casa;
    final confirmed = await showConfirm(
      context,
      title: FilesLogic.zonaConfirmTitle(folder.name, folder.zona),
      message: FilesLogic.zonaFolderBody(folder.name, folder.zona),
      confirmLabel: FilesLogic.zonaConfirmPrimary(folder.zona),
    );
    if (!mounted || !confirmed) return;
    final result = await actions.setZona(folder, target);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        widget.onFolderChanged?.call(value);
      case Err(:final error):
        await showFailure(context, error.message);
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    final actions = context.read<FolderActionsViewModel>();
    final confirmed = await showConfirm(
      context,
      title: FilesLogic.deleteFolderTitle(folder.name),
      message: FilesLogic.deleteFolderMessage,
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    final result = await actions.delete(folder);
    if (!mounted) return;
    switch (result) {
      case Ok():
        final deleted = widget.onFolderDeleted;
        if (deleted != null) {
          deleted();
        } else {
          Navigator.of(context).maybePop();
        }
      case Err(:final error):
        await showFailure(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploading = context.select<FilesViewModel, bool>(
      (model) => model.uploading,
    );
    final folder = widget.folder;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Nova pasta',
            onPressed: _newFolder,
          ),
          if (widget.onOpenTrash != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Lixeira',
              onPressed: widget.onOpenTrash,
            ),
          if (uploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
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
              icon: const Icon(Icons.upload_file),
              tooltip: 'Enviar arquivo',
              onPressed: _upload,
            ),
          if (folder != null) _FolderMenu(folder: folder, host: this),
        ],
      ),
      body: BrowserList(
        destinationZona: widget.destinationZona,
        onNewFolder: _newFolder,
        onOpenFolder: (value) => widget.onOpenFolder?.call(value),
        onOpenFile: (value) => widget.onOpenFile?.call(value),
        onPublish: _publish,
      ),
    );
  }
}

final class _FolderMenu extends StatelessWidget {
  const _FolderMenu({required this.folder, required this.host});

  final Folder folder;
  final _BrowserScaffoldState host;

  @override
  Widget build(BuildContext context) {
    final working = context.select<FolderActionsViewModel, bool>(
      (actions) => actions.working,
    );
    return PopupMenuButton<_FolderAction>(
      enabled: !working,
      tooltip: 'Mais opções',
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) {
        switch (action) {
          case _FolderAction.zona:
            unawaited(host._changeFolderZona(folder));
          case _FolderAction.rename:
            unawaited(host._renameFolder(folder));
          case _FolderAction.move:
            unawaited(host._moveFolder(folder));
          case _FolderAction.delete:
            unawaited(host._deleteFolder(folder));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _FolderAction.zona,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              folder.zona == Zona.casa
                  ? Icons.people_alt_rounded
                  : Icons.lock_outline,
            ),
            title: Text(FilesLogic.zonaActionLabel(folder.zona)),
          ),
        ),
        const PopupMenuItem(
          value: _FolderAction.rename,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Renomear'),
          ),
        ),
        const PopupMenuItem(
          value: _FolderAction.move,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_outlined),
            title: Text('Mover'),
          ),
        ),
        PopupMenuItem(
          value: _FolderAction.delete,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.delete_outline,
              color: TainaPalette.feedbackError,
            ),
            title: const Text(
              'Excluir',
              style: TextStyle(color: TainaPalette.feedbackError),
            ),
          ),
        ),
      ],
    );
  }
}

enum _FolderAction { zona, rename, move, delete }
