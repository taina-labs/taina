import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_gateway.dart';
import '../../session/upload_center.dart';
import '../trash/trash_screen.dart';
import 'browser_scaffold.dart';
import 'file_actions.dart';
import 'files_view_model.dart';
import 'folder_actions_view_model.dart';

/// A folder route in the selected Documentos zone.
final class FolderScreen extends StatefulWidget {
  const FolderScreen({
    required this.session,
    required this.actions,
    required this.folder,
    this.filesModel,
    this.actionsModel,
    this.selectedTab,
    this.onSelectTab,
    this.onBack,
    this.onOpenFolder,
    this.onOpenFile,
    this.onOpenTrash,
    this.onFolderChanged,
    this.onDeleted,
    this.uploadCenter,
    this.onOpenUpload,
    this.onViewSpace,
    super.key,
  });

  final SessionGateway session;
  final FileActions actions;
  final Folder folder;
  final FilesViewModel? filesModel;
  final FolderActionsViewModel? actionsModel;
  final TainaDocumentTab? selectedTab;
  final ValueChanged<TainaDocumentTab>? onSelectTab;
  final VoidCallback? onBack;
  final ValueChanged<Folder>? onOpenFolder;
  final ValueChanged<FileRecord>? onOpenFile;
  final VoidCallback? onOpenTrash;
  final ValueChanged<Folder>? onFolderChanged;
  final VoidCallback? onDeleted;
  final UploadCenter? uploadCenter;
  final ValueChanged<UploadRequest>? onOpenUpload;
  final VoidCallback? onViewSpace;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

final class _FolderScreenState extends State<FolderScreen> {
  late Folder _folder = widget.folder;
  late TainaDocumentTab _tab = widget.selectedTab ?? _tabFor(widget.folder);

  static TainaDocumentTab _tabFor(Folder folder) => folder.zona == Zona.praca
      ? TainaDocumentTab.praca
      : TainaDocumentTab.casa;

  @override
  void didUpdateWidget(FolderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab &&
        widget.selectedTab != null) {
      _tab = widget.selectedTab!;
    }
    if (oldWidget.folder != widget.folder) {
      _folder = widget.folder;
      _tab = widget.selectedTab ?? _tabFor(widget.folder);
    }
  }

  void _folderChanged(Folder folder) {
    setState(() => _folder = folder);
    widget.onFolderChanged?.call(folder);
  }

  void _selectTab(TainaDocumentTab tab) {
    setState(() => _tab = tab);
    widget.onSelectTab?.call(tab);
  }

  @override
  Widget build(BuildContext context) {
    if (_tab == TainaDocumentTab.lixeira) {
      return TrashScreen(
        session: widget.session,
        selectedTab: _tab,
        onSelectTab: _selectTab,
        onBack: widget.onBack,
      );
    }
    final filesModel = widget.filesModel;
    final actionsModel = widget.actionsModel;
    final zone = _tab == TainaDocumentTab.praca ? Zona.praca : Zona.casa;
    return MultiProvider(
      providers: [
        if (filesModel != null)
          ChangeNotifierProvider<FilesViewModel>.value(value: filesModel)
        else
          ChangeNotifierProvider<FilesViewModel>(
            key: ValueKey(
              'folder-${identityHashCode(widget.session)}-${_folder.rkey}-${_tab.name}',
            ),
            create: (context) {
              final created = FilesViewModel(
                session: widget.session,
                actions: widget.actions,
                folderRkey: _folder.rkey,
                zona: zone,
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
            key: ValueKey('folder-actions-${identityHashCode(widget.session)}'),
            create: (_) => FolderActionsViewModel(session: widget.session),
          ),
      ],
      child: BrowserScaffold(
        title: 'Documentos',
        folder: _folder,
        selectedTab: _tab,
        onSelectTab: _selectTab,
        onBack: widget.onBack,
        onOpenFolder: widget.onOpenFolder,
        onOpenFile: widget.onOpenFile,
        onOpenTrash: widget.onOpenTrash,
        onFolderChanged: _folderChanged,
        onFolderDeleted: widget.onDeleted,
        uploadCenter: widget.uploadCenter,
        onOpenUpload: widget.onOpenUpload,
        onViewSpace: widget.onViewSpace,
      ),
    );
  }
}
