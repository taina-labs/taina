import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/camera_roll/media_picker.dart';
import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_app/src/session/upload_center.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import 'gallery_model.dart';
import 'gallery_thumbnail.dart';
import 'gallery_video.dart';
import 'gallery_viewer.dart';

/// Reports whether the fullscreen viewer needs the shell chrome hidden.
typedef GalleryImmersiveChanged = void Function(bool immersive);

/// Jaci, the community photo and video gallery.
///
/// The app integration supplies the session boundaries and owns route changes,
/// the system share sheet, and the upload destination.
final class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    required this.gateway,
    this.onShareFile,
    this.onImmersiveChanged,
    this.playerFactory = defaultGalleryVideoPlayer,
    this.initialTab = TainaGalleryTab.grade,
    this.mediaPicker,
    this.uploadCenter,
    this.onNavigateTab,
    this.onBack,
    this.onOpenUpload,
    super.key,
  });

  final SessionGateway gateway;

  /// Hands a downloaded local file to the system share sheet.
  final GalleryShareFile? onShareFile;
  final GalleryImmersiveChanged? onImmersiveChanged;
  final GalleryVideoPlayerFactory playerFactory;

  /// The route represented by this screen when it is mounted.
  final TainaGalleryTab initialTab;

  /// The system media picker and session-owned upload path.
  final MediaPicker? mediaPicker;
  final UploadCenter? uploadCenter;

  /// Replaces the current gallery route when another service tab is selected.
  final ValueChanged<TainaGalleryTab>? onNavigateTab;

  /// Returns to the hub and opens the existing Enviar route, respectively.
  final VoidCallback? onBack;
  final VoidCallback? onOpenUpload;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

final class _GalleryScreenState extends State<GalleryScreen> {
  late final GalleryModel _model = GalleryModel(
    widget.gateway,
    initialTab: _modelTab(widget.initialTab),
  );
  bool _viewerRouteOpen = false;
  bool _picking = false;
  String? _handledAlert;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModelChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_model.ensureLoaded());
      unawaited(_model.ensureCountLoaded());
    });
  }

  @override
  void didUpdateWidget(GalleryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _model.selectTab(_modelTab(widget.initialTab));
      unawaited(_model.ensureLoaded());
    }
  }

  @override
  void dispose() {
    if (_viewerRouteOpen) widget.onImmersiveChanged?.call(false);
    _model.removeListener(_onModelChanged);
    _model.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (!mounted) return;
    final bool viewerOpen = _model.viewer != null;
    if (viewerOpen && !_viewerRouteOpen) {
      _openViewer();
      return;
    }
    if (!viewerOpen) _handleAlert();
  }

  void _openViewer() {
    _viewerRouteOpen = true;
    widget.onImmersiveChanged?.call(true);
    final Route<void> route = PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, animation, secondaryAnimation) {
        return GalleryViewerScreen(
          model: _model,
          gateway: widget.gateway,
          onShareFile: widget.onShareFile,
          playerFactory: widget.playerFactory,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
    unawaited(
      Navigator.of(context).push(route).whenComplete(() {
        _viewerRouteOpen = false;
        widget.onImmersiveChanged?.call(false);
        if (!mounted) return;
        _model.close();
      }),
    );
  }

  void _handleAlert() {
    final String? message = _model.alertMessage;
    if (message == null || message == _handledAlert) return;
    _handledAlert = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showToast(message);
      _handledAlert = null;
      _model.dismissAlert();
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

  void _selectTab(TainaGalleryTab tab) {
    final GalleryTab next = _modelTab(tab);
    if (_model.tab == next) return;
    _model.selectTab(next);
    unawaited(_model.ensureLoaded());
    widget.onNavigateTab?.call(tab);
  }

  Future<void> _pickAndUpload() async {
    if (_picking) return;
    final MediaPicker? picker = widget.mediaPicker;
    if (picker == null) {
      _showToast('A seleção de fotos e vídeos não está disponível.');
      return;
    }
    final UploadCenter? center = widget.uploadCenter;
    if (center == null) {
      _showToast('O envio não está disponível agora.');
      return;
    }
    if (center.isUploading) {
      widget.onOpenUpload?.call();
      return;
    }

    setState(() => _picking = true);
    try {
      final MediaPickerOutcome outcome = await picker.pickPhotos();
      if (!mounted) return;
      switch (outcome) {
        case MediaPickerCancelled():
          return;
        case MediaPickerFailed(:final message):
          _showToast(message);
          return;
        case MediaPickerSelected(:final files):
          await _uploadPickedFiles(files, center);
      }
    } on Exception {
      if (mounted) _showToast('Não foi possível selecionar as fotos e vídeos.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _uploadPickedFiles(
    List<PickedFile> files,
    UploadCenter center,
  ) async {
    bool openedUpload = false;
    for (final PickedFile file in files) {
      final Future<UploadStartResult> transfer = center.start(
        UploadRequest(path: file.path, name: file.name, mime: file.mime),
      );
      if (!openedUpload) {
        openedUpload = true;
        widget.onOpenUpload?.call();
      }
      final UploadStartResult started = await transfer;
      if (started case UploadRejected(:final reason)) {
        if (mounted && widget.onOpenUpload == null) {
          _showToast(
            reason == UploadRejection.busy
                ? 'Já existe um envio em andamento.'
                : 'Não foi possível iniciar o envio.',
          );
        }
        return;
      }
      if (started case UploadFinished(result: Err<FileRecord>(:final error))) {
        if (mounted && widget.onOpenUpload == null) _showToast(error.message);
        return;
      }
    }
    if (openedUpload && widget.onOpenUpload == null && mounted) {
      _showToast('Arquivo enviado para a sua casa.', kind: TainaToastKind.info);
    }
  }

  UploadCenter? _uploadCenter() => widget.uploadCenter;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GalleryModel>.value(
      value: _model,
      child: Builder(
        builder: (context) {
          final UploadCenter? center = _uploadCenter();
          return Scaffold(
            backgroundColor: TainaPalette.bgApp,
            body: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ServiceHeader(
                    title: 'Galeria',
                    backLabel: 'Início',
                    onBack:
                        widget.onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TainaSpacing.space4,
                      TainaSpacing.space2,
                      TainaSpacing.space4,
                      TainaSpacing.space3,
                    ),
                    child: Consumer<GalleryModel>(
                      builder: (context, model, child) => TainaText(
                        model.countLabel,
                        style: TainaTypography.caption,
                        color: TainaPalette.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Consumer<GalleryModel>(
                      builder: (context, model, child) => _GalleryContent(
                        model: model,
                        gateway: widget.gateway,
                        onUpload: _pickAndUpload,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: _fab(center),
            bottomNavigationBar: AnimatedBuilder(
              animation: _model,
              builder: (context, child) => ServiceTabBar.gallery(
                selected: _tabDestination(_model.tab),
                onSelected: _selectTab,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fab(UploadCenter? center) {
    final VoidCallback? action = _picking ? null : _pickAndUpload;
    if (center == null) {
      return TainaFAB(label: 'Enviar', action: action);
    }
    return AnimatedBuilder(
      animation: center,
      builder: (context, child) => TainaFAB(
        label: 'Enviar',
        action: center.isUploading ? null : action,
        uploading: center.isUploading,
      ),
    );
  }
}

final class _GalleryContent extends StatelessWidget {
  const _GalleryContent({
    required this.model,
    required this.gateway,
    required this.onUpload,
  });

  final GalleryModel model;
  final SessionGateway gateway;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    if (model.loading && model.empty) return _loadingGrid;

    if (model.error != null && model.empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(TainaSpacing.space4),
          child: ErrorCard(
            title: 'Não conseguimos carregar a galeria.',
            body: model.error!.message,
            retry: model.refresh,
          ),
        ),
      );
    }

    if (model.showEmpty) {
      return Center(
        child: EmptyStateView(
          icon: TainaIcon.folder,
          title: GalleryModel.noPhotos.title,
          body: GalleryModel.noPhotos.message,
          actionBuilder: (context) => TainaButton(
            title: 'Enviar uma foto',
            icon: TainaIcon.plus,
            action: onUpload,
          ),
        ),
      );
    }

    if (model.empty && model.canLoadMore) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _footer,
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final int columns = GalleryModel.columnsFor(constraints.maxWidth);
        return RefreshIndicator(
          onRefresh: model.refresh,
          child: switch (model.tab) {
            GalleryTab.grid => _grid(columns),
            GalleryTab.timeline => _timeline(columns),
          },
        );
      },
    );
  }

  Widget get _loadingGrid => const Padding(
    padding: EdgeInsets.all(TainaSpacing.space4),
    child: SkeletonView(kind: TainaSkeletonKind.photoGrid, count: 9),
  );

  Widget _grid(int columns) {
    final List<FileRecord> files = model.photos;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            TainaSpacing.space4,
            TainaSpacing.space2,
            TainaSpacing.space4,
            0,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: _delegate(columns),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final FileRecord file = files[index];
              return _GalleryTile(
                gateway: gateway,
                file: file,
                onTap: () => model.open(file),
              );
            },
          ),
        ),
        _footer,
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _timeline(int columns) {
    final List<GalleryDay> days = model.timelineDays;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (int index = 0; index < days.length; index++) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                TainaSpacing.space4,
                index == 0 ? TainaSpacing.space2 : TainaSpacing.space5,
                TainaSpacing.space4,
                TainaSpacing.space2,
              ),
              child: TainaText(
                GalleryModel.sectionTitle(days[index]),
                style: TainaTypography.label,
                color: TainaPalette.textSecondary,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: TainaSpacing.space4,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: _delegate(columns),
              itemCount: days[index].photos.length,
              itemBuilder: (context, photoIndex) {
                final FileRecord file = days[index].photos[photoIndex];
                return _GalleryTile(
                  gateway: gateway,
                  file: file,
                  onTap: () => model.open(file),
                );
              },
            ),
          ),
        ],
        _footer,
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget get _footer {
    if (!model.canLoadMore) return const SliverToBoxAdapter(child: SizedBox());
    return SliverToBoxAdapter(
      child: _GalleryFooter(
        rearmKey: model.loadedPageCount,
        onLoadMore: model.loadMore,
      ),
    );
  }

  static SliverGridDelegateWithFixedCrossAxisCount _delegate(int columns) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: TainaSizes.gapPhoto,
      crossAxisSpacing: TainaSizes.gapPhoto,
    );
  }
}

/// The infinite-scroll sentinel re-arms whenever a page lands.
final class _GalleryFooter extends StatefulWidget {
  const _GalleryFooter({required this.rearmKey, required this.onLoadMore});

  final int rearmKey;
  final Future<void> Function() onLoadMore;

  @override
  State<_GalleryFooter> createState() => _GalleryFooterState();
}

final class _GalleryFooterState extends State<_GalleryFooter> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_GalleryFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rearmKey != widget.rearmKey) _load();
  }

  void _load() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.onLoadMore());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: TainaSizes.controlSm / 2,
            height: TainaSizes.controlSm / 2,
            child: CircularProgressIndicator(
              strokeWidth: TainaSizes.thick,
              color: TainaPalette.textMuted,
            ),
          ),
          const SizedBox(width: TainaSpacing.space2),
          const TainaText(
            'Carregando mais...',
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
          ),
        ],
      ),
    );
  }
}

/// A square thumbnail; videos use the gallery image glyph until their
/// playback page is opened.
final class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.gateway,
    required this.file,
    required this.onTap,
  });

  final SessionGateway gateway;
  final FileRecord file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool video = GalleryModel.isVideo(file);
    return Semantics(
      button: true,
      label: file.name,
      child: GestureDetector(
        key: ValueKey<String>('gallery-tile-${file.name}'),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: TainaRadii.mdAll,
          child: video
              ? const ColoredBox(
                  color: TainaPalette.surfaceHigh,
                  child: Center(
                    child: TainaIconView(
                      icon: TainaIcon.image,
                      size: TainaSizes.iconLg,
                      color: TainaPalette.textSecondary,
                    ),
                  ),
                )
              : GalleryThumbnail(
                  gateway: gateway,
                  rkey: file.rkey,
                  size: ThumbnailSize.sm,
                ),
        ),
      ),
    );
  }
}

GalleryTab _modelTab(TainaGalleryTab tab) => switch (tab) {
  TainaGalleryTab.grade => GalleryTab.grid,
  TainaGalleryTab.linha => GalleryTab.timeline,
};

TainaGalleryTab _tabDestination(GalleryTab tab) => switch (tab) {
  GalleryTab.grid => TainaGalleryTab.grade,
  GalleryTab.timeline => TainaGalleryTab.linha,
};
