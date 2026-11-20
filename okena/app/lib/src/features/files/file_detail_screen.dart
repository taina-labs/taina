import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_gateway.dart';
import 'file_actions.dart';
import 'file_detail_view_model.dart';
import 'files_logic.dart';
import 'file_row.dart';

/// File metadata, preview, download/share and owner-only removal.
final class FileDetailScreen extends StatefulWidget {
  const FileDetailScreen({
    required this.session,
    required this.actions,
    required this.file,
    this.model,
    this.backLabel = 'Documentos',
    this.onBack,
    this.onChanged,
    this.onDeleted,
    this.onRequested,
    super.key,
  });

  final SessionGateway session;
  final FileActions actions;
  final FileRecord file;
  final FileDetailViewModel? model;
  final String backLabel;
  final VoidCallback? onBack;
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
  void initState() {
    super.initState();
    unawaited(_model.loadMetadata());
  }

  @override
  void dispose() {
    if (_injected == null) _model.dispose();
    super.dispose();
  }

  void _showToast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
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

  void _showModelError() {
    final message = _model.errorMessage;
    if (message == null) return;
    _model.dismissError();
    _showToast(message, error: true);
  }

  Future<void> _download() async {
    final ok = await _model.download();
    if (!mounted) return;
    if (!ok) _showModelError();
  }

  Future<void> _share() async {
    final ok = await _model.share();
    if (!mounted) return;
    if (ok) {
      _showToast('Arquivo pronto para compartilhar.');
    } else {
      _showModelError();
    }
  }

  Future<void> _preview() async {
    final ok = await _model.preview();
    if (!mounted) return;
    if (!ok) _showModelError();
  }

  Future<void> _remove() async {
    final confirmed = await TainaDialog.destructive(
      context: context,
      title: FilesLogic.deleteFileTitle(_model.file.name),
      message: FilesLogic.deleteFileMessage,
      confirmLabel: 'Remover',
    );
    if (!mounted || confirmed != true) return;
    final removed = await _model.delete();
    if (!mounted) return;
    if (!removed) {
      _showModelError();
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
    final confirmed = await TainaDialog.confirm(
      context: context,
      title: 'Pedir acesso a ${target.name}?',
      message: 'Quem guardou este arquivo decide se libera o acesso.',
      confirmLabel: 'Pedir acesso',
    );
    if (!mounted || confirmed != true) return;
    final sent = await _model.requestAccess();
    if (!mounted) return;
    if (!sent) {
      _showModelError();
      return;
    }
    final requested = widget.onRequested;
    if (requested != null) {
      requested();
    } else {
      _showToast('Pedido enviado. A resposta aparece em Pedidos.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FileDetailViewModel>.value(
      value: _model,
      child: Consumer<FileDetailViewModel>(
        builder: (context, model, child) {
          return Scaffold(
            body: CustomScrollView(
              slivers: [
                PageHeaderSliver(
                  title: model.file.name,
                  backLabel: widget.backLabel,
                  onBack:
                      widget.onBack ?? () => Navigator.of(context).maybePop(),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: TainaSpacing.space8),
                  sliver: SliverToBoxAdapter(child: _body(model)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _body(FileDetailViewModel model) {
    if (model.resolving) {
      return const Padding(
        padding: EdgeInsets.all(TainaSpacing.space8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final denied = model.denied;
    if (denied != null) return _deniedContent(model);
    return _fileContent(model);
  }

  Widget _deniedContent(FileDetailViewModel model) {
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      child: model.requested
          ? const Column(
              children: [
                SizedBox(height: TainaSpacing.space16),
                TainaToast(
                  kind: TainaToastKind.info,
                  text: 'Pedido enviado. A resposta aparece em Pedidos.',
                ),
              ],
            )
          : EmptyStateView(
              icon: TainaIcon.shield,
              title: 'Esta casa é particular',
              body: 'Este arquivo está na casa de outra pessoa. Só quem guardou pode liberar.',
              actionLabel: 'Pedir acesso',
              onAction: model.working ? null : _askAccess,
            ),
    );
  }

  Widget _fileContent(FileDetailViewModel model) {
    final file = model.file;
    final owner = model.ownerName;
    final location = file.zona == Zona.praca ? 'Praça' : 'Casa';
    final folderName = model.folderName;
    final where = folderName == null
        ? location
        : '$location, pasta $folderName';
    return Padding(
      padding: const EdgeInsets.only(top: TainaSpacing.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: FileThumbnail(
              thumbnails: widget.session.thumbnails,
              rkey: file.rkey,
              size: ThumbnailSize.md,
              side: TainaSizes.qr,
            ),
          ),
          const SizedBox(height: TainaSpacing.space4),
          TainaListRow(
            kind: TainaListRowKind.file,
            title: FilesLogic.fileKind(file.mime),
            meta:
                '${TainaFormat.bytes(file.size)}, na ${location.toLowerCase()}',
            showDivider: true,
          ),
          TainaListRow(
            kind: TainaListRowKind.person,
            title: 'Enviado por $owner',
            meta: TainaFormat.date(file.createdAt),
            showDivider: true,
          ),
          TainaListRow(
            kind: TainaListRowKind.folder,
            title: 'Onde',
            meta: where,
            showDivider: false,
          ),
          const SizedBox(height: TainaSpacing.space4),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TainaSpacing.space4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TainaButton(
                    title: model.working
                        ? 'Carregando'
                        : model.downloadedPath == null
                        ? 'Baixar'
                        : 'Compartilhar',
                    action: model.working
                        ? null
                        : model.downloadedPath == null
                        ? () => unawaited(_download())
                        : () => unawaited(_share()),
                    kind: TainaButtonKind.secondary,
                  ),
                ),
                const SizedBox(width: TainaSpacing.space3),
                Expanded(
                  child: TainaButton(
                    title: 'Pré-visualizar',
                    action: model.working ? null : () => unawaited(_preview()),
                    kind: TainaButtonKind.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (model.isOwner) ...[
            const SizedBox(height: TainaSpacing.space3),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TainaSpacing.space4,
              ),
              child: TainaButton(
                title: 'Remover',
                action: model.working ? null : () => unawaited(_remove()),
                kind: TainaButtonKind.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
