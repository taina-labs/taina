import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import 'gallery_details.dart';
import 'gallery_model.dart';
import 'gallery_video.dart';

/// The handoff to the system share sheet, wired by the app integration.
typedef GalleryShareFile = Future<String?> Function(String path);

/// The fullscreen viewer for photos and videos in the visible gallery order.
final class GalleryViewerScreen extends StatefulWidget {
  const GalleryViewerScreen({
    required this.model,
    required this.gateway,
    this.onShareFile,
    this.playerFactory = defaultGalleryVideoPlayer,
    super.key,
  });

  final GalleryModel model;
  final SessionGateway gateway;
  final GalleryShareFile? onShareFile;
  final GalleryVideoPlayerFactory playerFactory;

  @override
  State<GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

final class _GalleryViewerScreenState extends State<GalleryViewerScreen> {
  late final PageController _controller = PageController(
    initialPage: widget.model.viewer?.index ?? 0,
  );
  bool _sharing = false;
  bool _popping = false;
  String? _handledAlert;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (!mounted) return;
    if (widget.model.viewer == null) {
      _popOnce();
      return;
    }
    setState(() {});
    _handleAlert();
  }

  void _popOnce() {
    if (_popping) return;
    _popping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  void _handleAlert() {
    final String? message = widget.model.alertMessage;
    if (message == null || message == _handledAlert) return;
    _handledAlert = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showToast(message);
      _handledAlert = null;
      widget.model.dismissAlert();
    });
  }

  void _showToast(
    String message, {
    TainaToastKind kind = TainaToastKind.error,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: TainaToast(kind: kind, text: message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      );
  }

  void _close() => widget.model.close();

  void _goTo(int index) {
    final GalleryViewerState? viewer = widget.model.viewer;
    if (viewer == null || index < 0 || index >= viewer.files.length) return;
    widget.model.moveViewer(index);
    if (_controller.hasClients) {
      unawaited(
        _controller.animateToPage(
          index,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        ),
      );
    }
  }

  Future<void> _share(FileRecord file) async {
    if (_sharing || widget.model.working) return;
    setState(() => _sharing = true);
    final TainaResult<String> result = await widget.model.download(file);
    if (!mounted) return;
    if (result case Ok<String>(:final value)) {
      final GalleryShareFile? share = widget.onShareFile;
      if (share == null) {
        widget.model.reportAlert(
          'Compartilhar não está disponível neste aparelho.',
        );
      } else {
        try {
          final String? message = await share(value);
          if (message != null && mounted) widget.model.reportAlert(message);
        } on Object {
          if (mounted) {
            widget.model.reportAlert(
              'Não foi possível abrir o compartilhamento.',
            );
          }
        }
      }
    }
    if (mounted) setState(() => _sharing = false);
  }

  Future<void> _confirmZone(FileRecord file) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(GalleryModel.zonaConfirmTitle(file.name, file.zona)),
        content: Text(GalleryModel.zonaConfirmBody(file.zona)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(GalleryModel.zonaConfirmPrimary(file.zona)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await widget.model.changeZone(file);
  }

  Future<void> _confirmDelete(FileRecord file) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(GalleryModel.deleteFileTitle(file.name)),
        content: const Text(GalleryModel.deleteFileMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await widget.model.delete(file);
  }

  Future<void> _showActions(FileRecord file) {
    return ActionsMenu.show(
      context: context,
      title: 'Ações da foto',
      actions: [
        TainaMenuAction(
          label: GalleryModel.zonaActionLabel(file.zona),
          icon: file.zona == Zona.casa ? TainaIcon.praca : TainaIcon.casa,
          onSelected: () => unawaited(_confirmZone(file)),
          enabled: !widget.model.working,
        ),
        TainaMenuAction(
          label: 'Baixar',
          icon: TainaIcon.download,
          onSelected: () => unawaited(_share(file)),
          enabled: !_sharing && !widget.model.working,
        ),
        TainaMenuAction(
          label: 'Compartilhar',
          icon: TainaIcon.file,
          onSelected: () => unawaited(_share(file)),
          enabled: !_sharing && !widget.model.working,
        ),
        TainaMenuAction(
          label: 'Detalhes',
          icon: TainaIcon.info,
          onSelected: () => unawaited(showGalleryDetails(context, file)),
        ),
        TainaMenuAction(
          label: 'Excluir',
          icon: TainaIcon.trash,
          onSelected: () => unawaited(_confirmDelete(file)),
          destructive: true,
          enabled: !widget.model.working,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final GalleryViewerState? viewer = widget.model.viewer;
    final FileRecord? file = viewer?.file;
    if (viewer == null || file == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: TainaPalette.bgViewer,
      body: SafeArea(
        child: ViewerChrome(
          onClose: _close,
          counter:
              '${GalleryModel.positionOf(file, viewer.files)} de '
              '${viewer.files.length}',
          caption: GalleryModel.viewerCaption(file),
          onPrevious: viewer.index > 0 ? () => _goTo(viewer.index - 1) : null,
          onNext: viewer.index < viewer.files.length - 1
              ? () => _goTo(viewer.index + 1)
              : null,
          action: TainaIconButton(
            icon: TainaIcon.dots,
            label: 'Ações da foto',
            action: widget.model.working || _sharing
                ? null
                : () => unawaited(_showActions(file)),
          ),
          child: PageView.builder(
            controller: _controller,
            itemCount: viewer.files.length,
            onPageChanged: widget.model.moveViewer,
            itemBuilder: (context, index) {
              final FileRecord pageFile = viewer.files[index];
              if (GalleryModel.isVideo(pageFile)) {
                return GalleryVideoPage(
                  model: widget.model,
                  file: pageFile,
                  active: index == viewer.index,
                  playerFactory: widget.playerFactory,
                );
              }
              return GalleryImageView(
                gateway: widget.gateway,
                rkey: pageFile.rkey,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A photo from the shared thumbnail cache, with an explicit retry surface
/// when the image cannot be opened.
final class GalleryImageView extends StatefulWidget {
  const GalleryImageView({
    required this.gateway,
    required this.rkey,
    super.key,
  });

  final SessionGateway gateway;
  final String rkey;

  @override
  State<GalleryImageView> createState() => _GalleryImageViewState();
}

final class _GalleryImageViewState extends State<GalleryImageView> {
  late Future<TainaResult<Uint8List>> _bytes = _load();

  Future<TainaResult<Uint8List>> _load() {
    return widget.gateway.thumbnails.data(
      rkey: widget.rkey,
      size: ThumbnailSize.md,
    );
  }

  @override
  void didUpdateWidget(GalleryImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rkey != widget.rkey || oldWidget.gateway != widget.gateway) {
      _bytes = _load();
    }
  }

  void _retry() => setState(() => _bytes = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TainaResult<Uint8List>>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: TainaPalette.bgViewer,
            child: Center(
              child: CircularProgressIndicator(color: TainaPalette.textMuted),
            ),
          );
        }
        if (snapshot.hasError) {
          return _errorCard(snapshot.error.toString());
        }
        final TainaResult<Uint8List>? result = snapshot.data;
        if (result == null) return _errorCard('Tente abrir esta foto de novo.');
        return switch (result) {
          Ok<Uint8List>(:final value) => Center(
            child: Image.memory(
              value,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  _errorCard('Não foi possível exibir esta imagem.'),
            ),
          ),
          Err<Uint8List>(:final error) => _errorCard(error.message),
        };
      },
    );
  }

  Widget _errorCard(String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        child: ErrorCard(
          title: 'Não conseguimos abrir esta foto',
          body: body,
          retry: _retry,
        ),
      ),
    );
  }
}
