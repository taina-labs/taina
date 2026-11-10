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

/// The fullscreen viewer: a dark frame, one photo at a time, swipe between
/// the photos of the list it was opened from, close on top, and the acts the
/// viewer has: share, details, publish or take back, delete.
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
  String? _handledAlert;
  bool _popping = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(GalleryModel.alertTitle),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(GalleryModel.alertDismiss),
            ),
          ],
        ),
      );
      if (!mounted) return;
      widget.model.dismissAlert();
      _handledAlert = null;
    });
  }

  void _close() {
    widget.model.close();
  }

  void _goTo(int index) {
    final GalleryViewerState? viewer = widget.model.viewer;
    if (viewer == null) return;
    if (index < 0 || index >= viewer.files.length) return;
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
    setState(() {
      _sharing = true;
    });
    final TainaResult<String> result = await widget.model.download(file);
    if (!mounted) return;
    if (result case Ok(:final value)) {
      final GalleryShareFile? share = widget.onShareFile;
      if (share == null) {
        widget.model.reportAlert(
          'Compartilhar não está disponível neste aparelho.',
        );
      } else {
        try {
          final message = await share(value);
          if (message != null && mounted) {
            widget.model.reportAlert(message);
          }
        } on Object {
          if (mounted) {
            widget.model.reportAlert(
              'Não foi possível abrir o compartilhamento.',
            );
          }
        }
      }
    }
    if (mounted) {
      setState(() {
        _sharing = false;
      });
    }
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
    if (confirmed == true && mounted) {
      await widget.model.changeZone(file);
    }
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
    if (confirmed == true && mounted) {
      await widget.model.delete(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final GalleryViewerState? viewer = widget.model.viewer;
    if (viewer == null) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: TainaPalette.bgViewer,
      body: SafeArea(
        child: Column(
          children: [
            _header(viewer),
            Expanded(child: _stage(viewer)),
            _caption(viewer),
          ],
        ),
      ),
    );
  }

  Widget _header(GalleryViewerState viewer) {
    final FileRecord? file = viewer.file;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TainaSpacing.space2,
        vertical: TainaSpacing.space2,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Fechar',
            child: IconButton(
              onPressed: _close,
              icon: const Icon(Icons.close_rounded),
              color: TainaPalette.textPrimary,
              tooltip: 'Fechar',
            ),
          ),
          Expanded(
            child: file == null
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TainaText(
                        GalleryModel.uploadedDay(file.createdAt),
                        style: TainaTypography.label,
                        color: TainaPalette.textPrimary,
                        textAlign: TextAlign.center,
                      ),
                      TainaText(
                        '${GalleryModel.positionOf(file, viewer.files)} de '
                        '${viewer.files.length}',
                        style: TainaTypography.caption,
                        color: TainaPalette.textFaint,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: TainaSizes.touch),
        ],
      ),
    );
  }

  Widget _stage(GalleryViewerState viewer) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: viewer.files.length,
          onPageChanged: widget.model.moveViewer,
          itemBuilder: (context, index) {
            final FileRecord file = viewer.files[index];
            if (GalleryModel.isVideo(file)) {
              return GalleryVideoPage(
                model: widget.model,
                file: file,
                active: index == viewer.index,
                playerFactory: widget.playerFactory,
              );
            }
            return GalleryImageView(gateway: widget.gateway, rkey: file.rkey);
          },
        ),
        if (viewer.files.length > 1)
          Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _nav(forward: false, viewer: viewer),
                _nav(forward: true, viewer: viewer),
              ],
            ),
          ),
      ],
    );
  }

  /// The web's prev/next arrows, for the hand the swipe misses. Dead at the
  /// ends, gone when there is nothing to move through.
  Widget _nav({required bool forward, required GalleryViewerState viewer}) {
    final bool reachable = forward
        ? viewer.index < viewer.files.length - 1
        : viewer.index > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space2),
      child: Semantics(
        button: true,
        label: forward ? 'Próxima foto' : 'Foto anterior',
        child: Opacity(
          opacity: reachable ? 1 : TainaOpacity.disabled,
          child: IconButton.filled(
            onPressed: reachable
                ? () => _goTo(viewer.index + (forward ? 1 : -1))
                : null,
            icon: Icon(
              forward
                  ? Icons.chevron_right_rounded
                  : Icons.chevron_left_rounded,
            ),
            style: IconButton.styleFrom(
              backgroundColor: TainaPalette.surfaceScrim,
              foregroundColor: TainaPalette.textPrimary,
              minimumSize: const Size(TainaSizes.touch, TainaSizes.touch),
            ),
          ),
        ),
      ),
    );
  }

  Widget _caption(GalleryViewerState viewer) {
    final FileRecord? file = viewer.file;
    if (file == null) return const SizedBox.shrink();
    return ColoredBox(
      color: TainaPalette.surfaceScrimStrong,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: TainaSpacing.space3,
              horizontal: TainaSpacing.space4,
            ),
            child: Row(
              children: [
                _badge(file.zona),
                const SizedBox(width: TainaSpacing.space2),
                Expanded(
                  child: TainaText(
                    file.name,
                    style: TainaTypography.bodySm,
                    color: TainaPalette.textPrimary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          _actions(file),
          const SizedBox(height: TainaSpacing.space2),
        ],
      ),
    );
  }

  Widget _actions(FileRecord file) {
    final bool disabled = widget.model.working || _sharing;
    return Opacity(
      opacity: disabled ? TainaOpacity.disabled : 1,
      child: IgnorePointer(
        ignoring: disabled,
        child: Row(
          children: [
            _actionButton(
              label: 'Compartilhar',
              icon: Icons.ios_share_rounded,
              busy: _sharing,
              onPressed: () => unawaited(_share(file)),
            ),
            _actionButton(
              label: 'Detalhes',
              icon: Icons.info_outline_rounded,
              onPressed: () => unawaited(showGalleryDetails(context, file)),
            ),
            _actionButton(
              label: GalleryModel.zonaActionLabel(file.zona),
              icon: file.zona == Zona.casa
                  ? Icons.people_rounded
                  : Icons.lock_outline_rounded,
              onPressed: () => unawaited(_confirmZone(file)),
            ),
            _actionButton(
              label: 'Excluir',
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onPressed: () => unawaited(_confirmDelete(file)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool busy = false,
    bool destructive = false,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: TainaSpacing.space2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: TainaSizes.controlSm / 2,
                    height: TainaSizes.controlSm / 2,
                    child: CircularProgressIndicator(
                      strokeWidth: TainaSizes.thick,
                      color: TainaPalette.textPrimary,
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: TainaFontSizes.xl,
                    color: destructive
                        ? TainaPalette.feedbackError
                        : TainaPalette.textPrimary,
                  ),
                const SizedBox(height: TainaSpacing.space1),
                TainaText(
                  label,
                  style: TainaTypography.caption,
                  color: destructive
                      ? TainaPalette.feedbackError
                      : TainaPalette.textPrimary,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _badge(Zona zona) => zona == Zona.casa
    ? const TainaZonaBadge.casa()
    : const TainaZonaBadge.praca();

/// The viewer's picture: the md thumbnail from the shared store, centered, a
/// quiet square when there is none.
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
      setState(() {
        _bytes = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TainaResult<Uint8List>>(
      future: _bytes,
      builder: (context, snapshot) {
        final TainaResult<Uint8List>? result = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            result == null) {
          return const ColoredBox(
            color: TainaPalette.surfaceRaised,
            child: Center(
              child: CircularProgressIndicator(color: TainaPalette.textMuted),
            ),
          );
        }
        return switch (result) {
          Ok(:final value) => Center(
            child: Image.memory(
              value,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: TainaPalette.surfaceRaised,
                child: SizedBox.expand(),
              ),
            ),
          ),
          Err() => const ColoredBox(
            color: TainaPalette.surfaceRaised,
            child: SizedBox.expand(),
          ),
        };
      },
    );
  }
}
