import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_gateway.dart';
import 'dialogs.dart';
import 'file_actions.dart';
import 'file_detail_view_model.dart';
import 'file_row.dart';
import 'files_logic.dart';
import 'move_sheet.dart';

/// The file: the thumbnail large, the facts in mono, and the actions.
/// "Baixar" becomes "Compartilhar" once the file is here; the preview opens
/// on the same downloaded file. The owner's acts sit in the menu: publish or
/// take back, rename, move, delete, each with the confirmation the web asks
/// for. A casa the person cannot read turns the screen into the access
/// request: the box says the file is not for our eyes, the person asks, the
/// owner decides.
final class FileDetailScreen extends StatefulWidget {
  const FileDetailScreen({
    required this.session,
    required this.actions,
    required this.file,
    this.model,
    this.onChanged,
    this.onDeleted,
    this.onRequested,
    super.key,
  });

  final SessionGateway session;
  final FileActions actions;
  final FileRecord file;

  /// An already built model, for tests and previews.
  final FileDetailViewModel? model;
  final ValueChanged<FileRecord>? onChanged;
  final VoidCallback? onDeleted;
  final VoidCallback? onRequested;

  @override
  State<FileDetailScreen> createState() => _FileDetailScreenState();
}

final class _FileDetailScreenState extends State<FileDetailScreen> {
  late final FileDetailViewModel? _injected = widget.model;
  late final FileDetailViewModel _model =
      widget.model ??
      FileDetailViewModel(
        session: widget.session,
        actions: widget.actions,
        file: widget.file,
      );

  @override
  void dispose() {
    if (_injected == null) _model.dispose();
    super.dispose();
  }

  Future<void> _showErrorIfAny() async {
    final message = _model.errorMessage;
    if (!mounted || message == null) return;
    _model.dismissError();
    await showFailure(context, message);
  }

  Future<void> _download() async {
    final ok = await _model.download();
    if (!mounted) return;
    if (!ok) await _showErrorIfAny();
  }

  Future<void> _share() async {
    final ok = await _model.share();
    if (!mounted) return;
    if (!ok) await _showErrorIfAny();
  }

  Future<void> _preview() async {
    final ok = await _model.preview();
    if (!mounted) return;
    if (!ok) await _showErrorIfAny();
  }

  Future<void> _rename() async {
    final name = await showNamePrompt(
      context,
      title: 'Renomear',
      label: 'Novo nome',
      initial: _model.file.name,
      confirmLabel: 'Renomear',
    );
    if (!mounted || name == null || name == _model.file.name) return;
    final ok = await _model.rename(name);
    if (!mounted) return;
    if (ok) {
      widget.onChanged?.call(_model.file);
    } else {
      await _showErrorIfAny();
    }
  }

  Future<void> _move() async {
    final file = _model.file;
    await showMoveSheet(
      context,
      session: widget.session,
      sourceRkey: file.rkey,
      name: file.name,
      onPick: (folder) async {
        final ok = await _model.move(folder);
        if (ok) widget.onChanged?.call(_model.file);
        return ok
            ? const Ok<void>(null)
            : Err(_model.failure ?? const CancelledError());
      },
    );
  }

  Future<void> _changeZona() async {
    final file = _model.file;
    final confirmed = await showConfirm(
      context,
      title: FilesLogic.zonaConfirmTitle(file.name, file.zona),
      message: FilesLogic.zonaConfirmBody(file.zona),
      confirmLabel: FilesLogic.zonaConfirmPrimary(file.zona),
    );
    if (!mounted || !confirmed) return;
    final ok = await _model.changeZona();
    if (!mounted) return;
    if (ok) {
      widget.onChanged?.call(_model.file);
    } else {
      await _showErrorIfAny();
    }
  }

  Future<void> _delete() async {
    final confirmed = await showConfirm(
      context,
      title: FilesLogic.deleteFileTitle(_model.file.name),
      message: FilesLogic.deleteFileMessage,
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    final ok = await _model.delete();
    if (!mounted) return;
    if (!ok) {
      await _showErrorIfAny();
      return;
    }
    final deleted = widget.onDeleted;
    if (deleted != null) {
      deleted();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _askAccess() async {
    final target = _model.denied;
    if (target == null) return;
    final confirmed = await showConfirm(
      context,
      title: 'Pedir acesso a "${target.name}"?',
      message:
          'Quem guarda este arquivo vai receber seu pedido e decide se abre. '
          'Você só verá o conteúdo se a pessoa deixar.',
      confirmLabel: 'Pedir acesso',
    );
    if (!mounted || !confirmed) return;
    final ok = await _model.requestAccess();
    if (!mounted) return;
    if (!ok) {
      await _showErrorIfAny();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pedido enviado'),
        content: const Text(
          'A pessoa que guarda o arquivo recebe seu pedido e decide se abre.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final requested = widget.onRequested;
    if (requested != null) {
      requested();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FileDetailViewModel>.value(
      value: _model,
      child: Consumer<FileDetailViewModel>(
        builder: (context, model, child) {
          final denied = model.denied;
          return Scaffold(
            appBar: AppBar(
              title: Text(denied == null ? 'Arquivo' : 'Pedir acesso'),
              actions: [
                if (denied == null && !model.resolving)
                  _FileMenu(
                    file: model.file,
                    working: model.working,
                    onZona: _changeZona,
                    onRename: _rename,
                    onMove: _move,
                    onDelete: _delete,
                  ),
              ],
            ),
            body: _body(context, model),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, FileDetailViewModel model) {
    if (model.resolving) return const TainaLoadingList();
    final denied = model.denied;
    if (denied != null) return _deniedContent(denied);
    return _fileContent(model);
  }

  /// Casa de outra pessoa: a pessoa nao le o conteudo, mas a tela diz a
  /// quem pedir. The owner's menu is gone: there is nothing to own here.
  Widget _deniedContent(AccessTarget target) {
    return ListView(
      children: [
        TainaEmptyState(
          icon: Icons.shield_outlined,
          title: 'Esta casa é particular',
          message:
              'Só quem mora aqui vê este arquivo. Para abrir, peça acesso e a '
              'pessoa decide. O Tainá ainda não criptografa: é promessa de '
              'software, não cadeado.',
          actionLabel: 'Pedir acesso',
          onAction: _askAccess,
        ),
      ],
    );
  }

  Widget _fileContent(FileDetailViewModel model) {
    final file = model.file;
    return ListView(
      padding: const EdgeInsets.all(TainaSpacing.space5),
      children: [
        Center(
          child: FileThumbnail(
            thumbnails: widget.session.thumbnails,
            rkey: file.rkey,
            size: ThumbnailSize.md,
            side: TainaSizes.qr,
          ),
        ),
        const SizedBox(height: TainaSpacing.space5),
        TainaText(
          file.name,
          style: TainaTypography.h2,
          color: TainaPalette.textPrimary,
        ),
        const SizedBox(height: TainaSpacing.space2),
        Align(
          alignment: Alignment.centerLeft,
          child: file.zona == Zona.casa
              ? const TainaZonaBadge.casa()
              : const TainaZonaBadge.praca(),
        ),
        const SizedBox(height: TainaSpacing.space5),
        _meta(file),
        const SizedBox(height: TainaSpacing.space5),
        _actions(model),
      ],
    );
  }

  Widget _meta(FileRecord file) {
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetaRow(label: 'Tamanho', value: TainaFormat.bytes(file.size)),
          const SizedBox(height: TainaSpacing.space3),
          _MetaRow(
            label: 'Tipo',
            value: FilesLogic.fileKind(file.mime),
            note: file.mime,
          ),
          const SizedBox(height: TainaSpacing.space3),
          _MetaRow(label: 'Criado em', value: TainaFormat.date(file.createdAt)),
          const SizedBox(height: TainaSpacing.space3),
          _MetaRow(
            label: 'Atualizado em',
            value: TainaFormat.date(file.updatedAt),
          ),
          const SizedBox(height: TainaSpacing.space3),
          _MetaRow(
            label: FilesLogic.hashLabel,
            value: file.sha256,
            note: FilesLogic.hashNote,
          ),
        ],
      ),
    );
  }

  Widget _actions(FileDetailViewModel model) {
    return Row(
      children: [
        Expanded(
          child: model.working
              ? const SizedBox(
                  height: TainaSizes.controlMd,
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
              : model.downloadedPath != null
              ? TainaPrimaryButton(
                  label: 'Compartilhar',
                  onPressed: () => unawaited(_share()),
                )
              : TainaPrimaryButton(
                  label: 'Baixar',
                  onPressed: () => unawaited(_download()),
                ),
        ),
        const SizedBox(width: TainaSpacing.space3),
        Expanded(
          child: TainaSecondaryButton(
            label: 'Pré-visualizar',
            onPressed: model.working ? null : () => unawaited(_preview()),
          ),
        ),
      ],
    );
  }
}

final class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TainaText(
          label,
          style: TainaTypography.overline,
          color: TainaPalette.textMuted,
          uppercase: true,
        ),
        const SizedBox(height: TainaSpacing.space1),
        SelectableText(
          value,
          style: TainaTypography.monoSm.copyWith(
            color: TainaPalette.textPrimary,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: TainaSpacing.space1),
          TainaText(
            note!,
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
          ),
        ],
      ],
    );
  }
}

final class _FileMenu extends StatelessWidget {
  const _FileMenu({
    required this.file,
    required this.working,
    required this.onZona,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
  });

  final FileRecord file;
  final bool working;
  final VoidCallback onZona;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FileAction>(
      enabled: !working,
      tooltip: 'Mais opções',
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) {
        switch (action) {
          case _FileAction.zona:
            onZona();
          case _FileAction.rename:
            onRename();
          case _FileAction.move:
            onMove();
          case _FileAction.delete:
            onDelete();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _FileAction.zona,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              file.zona == Zona.casa
                  ? Icons.people_alt_rounded
                  : Icons.lock_outline,
            ),
            title: Text(FilesLogic.zonaActionLabel(file.zona)),
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.rename,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Renomear'),
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.move,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_outlined),
            title: Text('Mover'),
          ),
        ),
        PopupMenuItem(
          value: _FileAction.delete,
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_outline,
              color: TainaPalette.feedbackError,
            ),
            title: Text(
              'Excluir',
              style: TextStyle(color: TainaPalette.feedbackError),
            ),
          ),
        ),
      ],
    );
  }
}

enum _FileAction { zona, rename, move, delete }
