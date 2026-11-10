import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../session/session_gateway.dart';
import 'browser_scaffold.dart';
import 'file_actions.dart';
import 'files_view_model.dart';
import 'folder_actions_view_model.dart';

/// The same browser one level down: its own model over the folder's rkey, so
/// the loading logic and the pure transitions are [FilesViewModel]'s, not a
/// copy. The menu holds the folder's own acts: publish or take back, rename,
/// move, delete, each with the confirmation the web asks for.
final class FolderScreen extends StatefulWidget {
  const FolderScreen({
    required this.session,
    required this.actions,
    required this.folder,
    this.filesModel,
    this.actionsModel,
    this.onOpenFolder,
    this.onOpenFile,
    this.onOpenTrash,
    this.onFolderChanged,
    this.onDeleted,
    super.key,
  });

  final SessionGateway session;
  final FileActions actions;
  final Folder folder;

  /// Already built models, for tests and previews.
  final FilesViewModel? filesModel;
  final FolderActionsViewModel? actionsModel;

  final ValueChanged<Folder>? onOpenFolder;
  final ValueChanged<FileRecord>? onOpenFile;
  final VoidCallback? onOpenTrash;
  final ValueChanged<Folder>? onFolderChanged;

  /// Called after the folder goes to the trash. When null the screen pops.
  final VoidCallback? onDeleted;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

final class _FolderScreenState extends State<FolderScreen> {
  late Folder _folder = widget.folder;

  @override
  void didUpdateWidget(FolderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder != widget.folder) {
      _folder = widget.folder;
    }
  }

  void _folderChanged(Folder folder) {
    setState(() => _folder = folder);
    widget.onFolderChanged?.call(folder);
  }

  @override
  Widget build(BuildContext context) {
    final filesModel = widget.filesModel;
    final actionsModel = widget.actionsModel;
    return MultiProvider(
      providers: [
        if (filesModel != null)
          ChangeNotifierProvider<FilesViewModel>.value(value: filesModel)
        else
          ChangeNotifierProvider<FilesViewModel>(
            create: (context) {
              final created = FilesViewModel(
                session: widget.session,
                actions: widget.actions,
                folderRkey: _folder.rkey,
              );
              unawaited(created.load());
              return created;
            },
          ),
        if (actionsModel != null)
          ChangeNotifierProvider<FolderActionsViewModel>.value(
            value: actionsModel,
          )
        else
          ChangeNotifierProvider<FolderActionsViewModel>(
            create: (context) =>
                FolderActionsViewModel(session: widget.session),
          ),
      ],
      child: BrowserScaffold(
        title: _folder.name,
        destinationZona: _folder.zona,
        folder: _folder,
        onOpenFolder: widget.onOpenFolder,
        onOpenFile: widget.onOpenFile,
        onOpenTrash: widget.onOpenTrash,
        onFolderChanged: _folderChanged,
        onFolderDeleted: widget.onDeleted,
      ),
    );
  }
}
