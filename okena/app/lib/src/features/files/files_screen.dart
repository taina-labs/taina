import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_gateway.dart';
import '../../session/upload_center.dart';
import '../camera_roll/media_picker.dart';
import '../trash/trash_screen.dart';
import 'browser_scaffold.dart';
import 'file_actions.dart';
import 'files_view_model.dart';
import 'folder_actions_view_model.dart';

/// The Documentos tab root. The selected zone is a route, not a list filter.
final class FilesScreen extends StatefulWidget {
  const FilesScreen({
    required this.session,
    required this.actions,
    this.model,
    this.mediaPicker,
    this.title = 'Documentos',
    this.selectedTab = TainaDocumentTab.praca,
    this.onSelectTab,
    this.onBack,
    this.onOpenFolder,
    this.onOpenFile,
    this.onOpenTrash,
    this.uploadCenter,
    this.onOpenUpload,
    this.onViewSpace,
    super.key,
  });

  final SessionGateway session;
  final FileActions actions;
  final FilesViewModel? model;
  final MediaPicker? mediaPicker;
  final String title;
  final TainaDocumentTab selectedTab;
  final ValueChanged<TainaDocumentTab>? onSelectTab;
  final VoidCallback? onBack;
  final ValueChanged<Folder>? onOpenFolder;
  final ValueChanged<FileRecord>? onOpenFile;
  final VoidCallback? onOpenTrash;
  final UploadCenter? uploadCenter;
  final ValueChanged<UploadRequest>? onOpenUpload;
  final VoidCallback? onViewSpace;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

final class _FilesScreenState extends State<FilesScreen> {
  late TainaDocumentTab _tab = widget.selectedTab;

  @override
  void didUpdateWidget(FilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      _tab = widget.selectedTab;
    }
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

    final injected = widget.model;
    final zone = _tab == TainaDocumentTab.praca ? Zona.praca : Zona.casa;
    final filesModel = injected;
    final browser = BrowserScaffold(
      title: widget.title,
      selectedTab: _tab,
      onSelectTab: _selectTab,
      onBack: widget.onBack,
      onOpenFolder: widget.onOpenFolder,
      onOpenFile: widget.onOpenFile,
      onOpenTrash: widget.onOpenTrash,
      mediaPicker: widget.mediaPicker,
      uploadCenter: widget.uploadCenter,
      onOpenUpload: widget.onOpenUpload,
      onViewSpace: widget.onViewSpace,
    );

    return MultiProvider(
      providers: [
        if (filesModel != null)
          ChangeNotifierProvider<FilesViewModel>.value(value: filesModel)
        else
          ChangeNotifierProvider<FilesViewModel>(
            key: ValueKey(
              'files-${identityHashCode(widget.session)}-${_tab.name}',
            ),
            create: (context) {
              final created = FilesViewModel(
                session: widget.session,
                actions: widget.actions,
                zona: zone,
              );
              unawaited(created.load());
              return created;
            },
          ),
        ChangeNotifierProvider<FolderActionsViewModel>(
          key: ValueKey('folder-actions-${identityHashCode(widget.session)}'),
          create: (_) => FolderActionsViewModel(session: widget.session),
        ),
      ],
      child: browser,
    );
  }
}
