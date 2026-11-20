import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/upload_center.dart';
import '../camera_roll/camera_roll_upload_model.dart';
import '../camera_roll/camera_roll_upload_sheet.dart';
import '../camera_roll/media_picker.dart';
import '../trash/trash_screen.dart';
import 'browser_list.dart';
import 'dialogs.dart';
import 'file_actions.dart';
import 'file_detail_view_model.dart';
import 'files_logic.dart';
import 'files_view_model.dart';
import 'folder_actions_view_model.dart';
import 'move_sheet.dart';
import 'upload_screen.dart';

/// Shared Documentos shell for the Praça, Casa and Lixeira route tabs.
final class BrowserScaffold extends StatefulWidget {
  const BrowserScaffold({
    required this.title,
    this.folder,
    this.selectedTab = TainaDocumentTab.praca,
    this.onSelectTab,
    this.onBack,
    this.onOpenFolder,
    this.onOpenFile,
    this.onOpenTrash,
    this.onFolderChanged,
    this.onFolderDeleted,
    this.mediaPicker,
    this.uploadCenter,
    this.onOpenUpload,
    this.onViewSpace,
    super.key,
  });

  final String title;
  final Folder? folder;
  final TainaDocumentTab selectedTab;
  final ValueChanged<TainaDocumentTab>? onSelectTab;
  final VoidCallback? onBack;
  final ValueChanged<Folder>? onOpenFolder;
  final ValueChanged<FileRecord>? onOpenFile;
  final VoidCallback? onOpenTrash;
  final ValueChanged<Folder>? onFolderChanged;
  final VoidCallback? onFolderDeleted;
  final MediaPicker? mediaPicker;
  final UploadCenter? uploadCenter;
  final ValueChanged<UploadRequest>? onOpenUpload;
  final VoidCallback? onViewSpace;

  @override
  State<BrowserScaffold> createState() => _BrowserScaffoldState();
}

final class _BrowserScaffoldState extends State<BrowserScaffold> {
  UploadCenter? _listenedCenter;
  UploadState? _lastUploadState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenToUploadCenter(widget.uploadCenter);
    _syncCompletedUpload();
  }

  @override
  void didUpdateWidget(BrowserScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uploadCenter != widget.uploadCenter) {
      _listenToUploadCenter(widget.uploadCenter);
      _syncCompletedUpload();
    }
  }

  @override
  void dispose() {
    _listenedCenter?.removeListener(_uploadChanged);
    super.dispose();
  }

  void _listenToUploadCenter(UploadCenter? center) {
    if (_listenedCenter == center) return;
    _listenedCenter?.removeListener(_uploadChanged);
    _listenedCenter = center;
    _lastUploadState = center?.state;
    center?.addListener(_uploadChanged);
  }

  void _syncCompletedUpload() {
    final state = widget.uploadCenter?.state;
    if (state is UploadSucceeded) {
      context.read<FilesViewModel>().recordUpload(state.file);
    }
  }

  void _uploadChanged() {
    final center = _listenedCenter;
    if (center == null || !mounted) return;
    final current = center.state;
    final completed = current is UploadSucceeded && current != _lastUploadState;
    _lastUploadState = current;
    if (!completed) return;
    final model = context.read<FilesViewModel>();
    if (current case UploadSucceeded(:final file)) model.recordUpload(file);
    unawaited(model.load());
    if (ModalRoute.of(context)?.isCurrent ?? true) {
      _showToast('Arquivo guardado na sua casa.');
    }
  }

  void _showToast(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        content: TainaToast(
          kind: error ? TainaToastKind.error : TainaToastKind.info,
          text: message,
        ),
      ),
    );
  }

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
    if (error != null) _showToast(error.message, error: true);
  }

  Future<void> _upload() async {
    if (widget.uploadCenter?.isUploading ?? false) return;
    final model = context.read<FilesViewModel>();
    final result = await model.actions.pick();
    if (!mounted) return;
    switch (result) {
      case PickedFileCancelled():
        return;
      case PickedFileFailed(:final message):
        _showToast(message, error: true);
      case PickedFileSelected(:final file):
        final request = UploadRequest(
          path: file.path,
          name: file.name,
          mime: file.mime,
          folderRkey: widget.folder?.rkey,
          folderName: widget.folder?.name,
        );
        final openUpload = widget.onOpenUpload;
        if (openUpload != null) {
          openUpload(request);
          return;
        }
        final center = widget.uploadCenter;
        if (center != null) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => EnviarScreen(
                center: center,
                request: request,
                backLabel: widget.folder?.name,
                onViewSpace: widget.onViewSpace,
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
          );
          if (mounted) await model.load();
          return;
        }
        _showToast(
          'Não foi possível abrir o envio. Volte para Documentos e tente de novo.',
          error: true,
        );
    }
  }

  Future<void> _addMedia() async {
    final picker = widget.mediaPicker;
    if (picker == null ||
        widget.folder != null ||
        (widget.uploadCenter?.isUploading ?? false)) {
      return;
    }
    final files = context.read<FilesViewModel>();
    final model = CameraRollUploadModel(picker: picker, session: files.session);
    final anySuccess = await showCameraRollUploadSheet(context, model: model);
    model.dispose();
    if (!mounted || anySuccess != true) return;
    await files.load();
  }

  Future<void> _publish(FileRecord file) async {
    final model = context.read<FilesViewModel>();
    final result = await model.publish(file);
    if (!mounted) return;
    final error = result.error;
    if (error != null) {
      _showToast(error.message, error: true);
    } else {
      _showToast('Arquivo publicado na praça.');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final confirmed = destructive
        ? await TainaDialog.destructive(
            context: context,
            title: title,
            message: message,
            confirmLabel: confirmLabel,
          )
        : await TainaDialog.confirm(
            context: context,
            title: title,
            message: message,
            confirmLabel: confirmLabel,
          );
    return confirmed == true;
  }

  bool _ownsFolder(Folder folder) {
    final model = context.read<FilesViewModel>();
    final created = model.createdFolderRkeys.contains(folder.rkey);
    return FilesLogic.canManage(
      me: model.session.identity,
      ownerPublicId: folder.dono,
      createdInSession: created,
    );
  }

  Future<void> _fileMenu(FileRecord file) async {
    final model = context.read<FilesViewModel>();
    final created = model.uploadedRkeys.contains(file.rkey);
    final entries = FilesLogic.actionsForFile(
      file: file,
      me: model.session.identity,
      createdInSession: created,
    );
    await ActionsMenu.show(
      context: context,
      title: 'Ações do arquivo',
      actions: [
        for (final action in entries)
          TainaMenuAction(
            label: _fileActionLabel(action),
            icon: _fileActionIcon(action),
            destructive: action == FileMenuAction.remove,
            onSelected: () => unawaited(_runFileAction(action, file)),
          ),
      ],
    );
  }

  String _fileActionLabel(FileMenuAction action) => switch (action) {
    FileMenuAction.open => 'Abrir',
    FileMenuAction.download => 'Baixar',
    FileMenuAction.publish => 'Publicar na praça',
    FileMenuAction.returnHome => 'Voltar para a casa',
    FileMenuAction.move => 'Mover',
    FileMenuAction.rename => 'Renomear',
    FileMenuAction.remove => 'Remover',
  };

  TainaIcon _fileActionIcon(FileMenuAction action) => switch (action) {
    FileMenuAction.open => TainaIcon.file,
    FileMenuAction.download => TainaIcon.download,
    FileMenuAction.publish => TainaIcon.praca,
    FileMenuAction.returnHome => TainaIcon.casa,
    FileMenuAction.move => TainaIcon.folder,
    FileMenuAction.rename => TainaIcon.file,
    FileMenuAction.remove => TainaIcon.trash,
  };

  Future<void> _runFileAction(FileMenuAction action, FileRecord file) async {
    switch (action) {
      case FileMenuAction.open:
        widget.onOpenFile?.call(file);
      case FileMenuAction.download:
        await _download(file);
      case FileMenuAction.publish:
      case FileMenuAction.returnHome:
        final target = action == FileMenuAction.publish
            ? Zona.praca
            : Zona.casa;
        final confirmed = await _confirm(
          title: FilesLogic.zonaConfirmTitle(file.name, file.zona),
          message: FilesLogic.zonaConfirmBody(file.zona),
          confirmLabel: FilesLogic.zonaConfirmPrimary(file.zona),
        );
        if (!mounted || !confirmed) return;
        final result = await context.read<FilesViewModel>().setZona(
          file,
          target,
        );
        if (!mounted) return;
        if (result.error case final error?) {
          _showToast(error.message, error: true);
        } else {
          await context.read<FilesViewModel>().load();
          _showToast(
            target == Zona.praca
                ? 'Arquivo publicado na praça.'
                : 'Arquivo voltou para a casa.',
          );
        }
      case FileMenuAction.move:
        await _moveFile(file);
      case FileMenuAction.rename:
        await _renameFile(file);
      case FileMenuAction.remove:
        await _deleteFile(file);
    }
  }

  Future<void> _download(FileRecord file) async {
    final files = context.read<FilesViewModel>();
    final model = FileDetailViewModel(
      session: files.session,
      actions: files.actions,
      file: file,
    );
    final success = await model.share();
    if (!mounted) {
      model.dispose();
      return;
    }
    if (success) {
      _showToast('Arquivo pronto para compartilhar.');
    } else if (model.denied != null) {
      widget.onOpenFile?.call(file);
    } else {
      _showToast(
        model.errorMessage ?? 'Não foi possível baixar este arquivo.',
        error: true,
      );
    }
    model.dispose();
  }

  Future<void> _renameFile(FileRecord file) async {
    final name = await showNamePrompt(
      context,
      title: 'Renomear',
      label: 'Novo nome',
      initial: file.name,
      confirmLabel: 'Renomear',
    );
    if (!mounted || name == null || name == file.name) return;
    final files = context.read<FilesViewModel>();
    final model = FileDetailViewModel(
      session: files.session,
      actions: files.actions,
      file: file,
    );
    final success = await model.rename(name);
    if (!mounted) {
      model.dispose();
      return;
    }
    if (!success) {
      _showToast(
        model.errorMessage ?? 'Não foi possível renomear o arquivo.',
        error: true,
      );
    } else {
      await files.load();
      _showToast('Arquivo renomeado.');
    }
    model.dispose();
  }

  Future<void> _moveFile(FileRecord file) async {
    final model = context.read<FilesViewModel>();
    final fileActions = FileDetailViewModel(
      session: model.session,
      actions: model.actions,
      file: file,
    );
    await showMoveSheet(
      context,
      session: model.session,
      sourceRkey: file.rkey,
      name: file.name,
      onPick: (folder) async {
        final moved = await fileActions.move(folder);
        if (mounted && moved) await model.load();
        return moved
            ? const Ok<void>(null)
            : Err(fileActions.failure ?? const CancelledError());
      },
    );
    fileActions.dispose();
  }

  Future<void> _deleteFile(FileRecord file) async {
    final confirmed = await _confirm(
      title: FilesLogic.deleteFileTitle(file.name),
      message: FilesLogic.deleteFileMessage,
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    final files = context.read<FilesViewModel>();
    final model = FileDetailViewModel(
      session: files.session,
      actions: files.actions,
      file: file,
    );
    final success = await model.delete();
    if (!mounted) {
      model.dispose();
      return;
    }
    if (!success) {
      _showToast(
        model.errorMessage ?? 'Não foi possível remover o arquivo.',
        error: true,
      );
    } else {
      await files.load();
      _showToast('Arquivo removido.');
    }
    model.dispose();
  }

  Future<void> _folderMenu(Folder folder) async {
    final model = context.read<FilesViewModel>();
    final created = model.createdFolderRkeys.contains(folder.rkey);
    final actions = FilesLogic.actionsForFolder(
      folder: folder,
      me: model.session.identity,
      createdInSession: created,
    );
    await ActionsMenu.show(
      context: context,
      title: 'Ações da pasta',
      actions: [
        for (final action in actions)
          TainaMenuAction(
            label: _folderActionLabel(action),
            icon: _folderActionIcon(action),
            destructive: action == FolderMenuAction.remove,
            onSelected: () => unawaited(_runFolderAction(action, folder)),
          ),
      ],
    );
  }

  String _folderActionLabel(FolderMenuAction action) => switch (action) {
    FolderMenuAction.open => 'Abrir',
    FolderMenuAction.publish => 'Publicar na praça',
    FolderMenuAction.returnHome => 'Voltar para a casa',
    FolderMenuAction.move => 'Mover',
    FolderMenuAction.rename => 'Renomear',
    FolderMenuAction.remove => 'Remover',
  };

  TainaIcon _folderActionIcon(FolderMenuAction action) => switch (action) {
    FolderMenuAction.open => TainaIcon.folder,
    FolderMenuAction.publish => TainaIcon.praca,
    FolderMenuAction.returnHome => TainaIcon.casa,
    FolderMenuAction.move => TainaIcon.folder,
    FolderMenuAction.rename => TainaIcon.folder,
    FolderMenuAction.remove => TainaIcon.trash,
  };

  Future<void> _runFolderAction(FolderMenuAction action, Folder folder) async {
    switch (action) {
      case FolderMenuAction.open:
        widget.onOpenFolder?.call(folder);
      case FolderMenuAction.publish:
      case FolderMenuAction.returnHome:
        await _changeFolderZona(folder);
      case FolderMenuAction.move:
        await _moveFolder(folder);
      case FolderMenuAction.rename:
        await _renameFolder(folder);
      case FolderMenuAction.remove:
        await _deleteFolder(folder);
    }
  }

  Future<void> _renameFolder(Folder folder) async {
    final name = await showNamePrompt(
      context,
      title: 'Renomear pasta',
      label: 'Novo nome',
      initial: folder.name,
      confirmLabel: 'Renomear',
    );
    if (!mounted || name == null || name == folder.name) return;
    final result = await context.read<FolderActionsViewModel>().rename(
      folder,
      name,
    );
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        widget.onFolderChanged?.call(value);
      case Err(:final error):
        _showToast(error.message, error: true);
    }
  }

  Future<void> _moveFolder(Folder folder) async {
    final files = context.read<FilesViewModel>();
    final actions = context.read<FolderActionsViewModel>();
    await showMoveSheet(
      context,
      session: files.session,
      sourceRkey: folder.rkey,
      name: folder.name,
      isFolder: true,
      onPick: (parent) async {
        final result = await actions.move(folder, parent);
        if (result case Ok(:final value)) {
          if (mounted) widget.onFolderChanged?.call(value);
        }
        return result.map<void>((_) {});
      },
    );
  }

  Future<void> _changeFolderZona(Folder folder) async {
    final actions = context.read<FolderActionsViewModel>();
    final target = folder.zona == Zona.casa ? Zona.praca : Zona.casa;
    final confirmed = await _confirm(
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
        _showToast(error.message, error: true);
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    final actions = context.read<FolderActionsViewModel>();
    final confirmed = await _confirm(
      title: FilesLogic.deleteFolderTitle(folder.name),
      message: FilesLogic.deleteFolderMessage,
      confirmLabel: 'Remover',
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
        _showToast(error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<FilesViewModel>();
    if (widget.selectedTab == TainaDocumentTab.lixeira) {
      return TrashScreen(
        session: model.session,
        selectedTab: widget.selectedTab,
        onSelectTab: widget.onSelectTab,
        onBack: widget.onBack,
      );
    }
    final folder = widget.folder;
    final title = folder?.name ?? widget.title;
    final hint = folder != null
        ? FilesLogic.uploadDestinationMessage()
        : switch (widget.selectedTab) {
            TainaDocumentTab.praca => null,
            TainaDocumentTab.casa => 'Só você vê o que está na casa.',
            TainaDocumentTab.lixeira => null,
          };
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: widget.selectedTab == TainaDocumentTab.lixeira
            ? () async {}
            : model.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ServiceHeaderSliver(
              title: 'Documentos',
              backLabel: 'Início',
              onBack: widget.onBack ?? () => Navigator.of(context).maybePop(),
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.mediaPicker != null) _mediaAction(),
                  if (folder != null && _ownsFolder(folder))
                    TainaIconButton(
                      icon: TainaIcon.kebab,
                      label: 'Ações da pasta',
                      action: () => unawaited(_folderMenu(folder)),
                    ),
                  TainaIconButton(
                    icon: TainaIcon.plus,
                    label: 'Nova pasta',
                    action: widget.selectedTab == TainaDocumentTab.lixeira
                        ? null
                        : _newFolder,
                  ),
                ],
              ),
            ),
            if (folder != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TainaSpacing.space4,
                    TainaSpacing.space2,
                    TainaSpacing.space4,
                    TainaSpacing.space3,
                  ),
                  child: TainaText(
                    title,
                    style: TainaTypography.h1,
                    color: TainaPalette.textPrimary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (hint != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TainaSpacing.space4,
                    TainaSpacing.space2,
                    TainaSpacing.space4,
                    TainaSpacing.space3,
                  ),
                  child: TainaText(
                    hint,
                    style: TainaTypography.bodySm,
                    color: TainaPalette.textSecondary,
                  ),
                ),
              ),
            BrowserList(
              onUpload: _upload,
              onOpenFolder: (value) => widget.onOpenFolder?.call(value),
              onOpenFile: (value) => widget.onOpenFile?.call(value),
              onPublish: _publish,
              onMoreFile: (value) => unawaited(_fileMenu(value)),
              onMoreFolder: (value) => unawaited(_folderMenu(value)),
              tab: widget.selectedTab,
              folder: folder,
              canManageFolder: _ownsFolder,
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: widget.uploadCenter == null
          ? TainaFAB(label: 'Enviar', action: _upload)
          : ListenableBuilder(
              listenable: widget.uploadCenter!,
              builder: (context, _) => TainaFAB(
                label: 'Enviar',
                uploading: widget.uploadCenter!.isUploading,
                action: _upload,
              ),
            ),
      bottomNavigationBar: ServiceTabBar.documents(
        selected: widget.selectedTab,
        onSelected: (tab) {
          final selectTab = widget.onSelectTab;
          if (selectTab != null) {
            selectTab(tab);
          } else if (tab == TainaDocumentTab.lixeira &&
              widget.onOpenTrash != null) {
            widget.onOpenTrash!.call();
          }
        },
      ),
    );
  }

  Widget _mediaAction() {
    final center = widget.uploadCenter;
    if (center == null) {
      return TainaIconButton(
        icon: TainaIcon.image,
        label: 'Adicionar fotos e vídeos',
        action: _addMedia,
      );
    }
    return ListenableBuilder(
      listenable: center,
      builder: (context, _) => TainaIconButton(
        icon: TainaIcon.image,
        label: 'Adicionar fotos e vídeos',
        action: center.isUploading ? null : _addMedia,
      ),
    );
  }
}
