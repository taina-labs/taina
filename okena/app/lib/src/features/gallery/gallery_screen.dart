import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import 'gallery_model.dart';
import 'gallery_thumbnail.dart';
import 'gallery_video.dart';
import 'gallery_viewer.dart';

/// Reports whether the fullscreen viewer needs the shell chrome hidden.
typedef GalleryImmersiveChanged = void Function(bool immersive);

/// Jaci, the Fotos screen: grid and timeline on one segmented row, the
/// casa/praça filter under it, infinite scroll on both, and the fullscreen
/// viewer over whichever list is showing.
///
/// The screen owns its [GalleryModel]; the app integration only provides the
/// [SessionGateway] and the handoffs it cannot own (the share sheet, the
/// video player plugin in tests).
final class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    required this.gateway,
    this.onShareFile,
    this.onImmersiveChanged,
    this.playerFactory = defaultGalleryVideoPlayer,
    super.key,
  });

  final SessionGateway gateway;

  /// Hands a downloaded local file to the system share sheet. The feature
  /// downloads; opening the sheet belongs to the app integration.
  final GalleryShareFile? onShareFile;
  final GalleryImmersiveChanged? onImmersiveChanged;
  final GalleryVideoPlayerFactory playerFactory;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

final class _GalleryScreenState extends State<GalleryScreen> {
  late final GalleryModel _model = GalleryModel(widget.gateway);
  bool _viewerRouteOpen = false;
  String? _handledAlert;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModelChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_model.ensureLoaded());
    });
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
      _handledAlert = null;
      _model.dismissAlert();
    });
  }

  void _selectTab(GalleryTab tab) {
    _model.selectTab(tab);
    unawaited(_model.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GalleryModel>.value(
      value: _model,
      child: Scaffold(
        backgroundColor: TainaPalette.bgApp,
        appBar: AppBar(title: const Text('Fotos')),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: TainaSpacing.space2),
              _GallerySegment(model: _model, onSelect: _selectTab),
              const SizedBox(height: TainaSpacing.space2),
              _GalleryZoneFilter(model: _model),
              const SizedBox(height: TainaSpacing.space2),
              Expanded(
                child: Consumer<GalleryModel>(
                  builder: (context, model, child) =>
                      _GalleryContent(model: model, gateway: widget.gateway),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two tabs on one row; the current one in brand.
final class _GallerySegment extends StatelessWidget {
  const _GallerySegment({required this.model, required this.onSelect});

  final GalleryModel model;
  final ValueChanged<GalleryTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
      child: Row(
        children: [
          for (final GalleryTab tab in GalleryTab.values) ...[
            _GalleryPill(
              title: GalleryModel.labelOfTab(tab),
              current: model.tab == tab,
              onTap: () => onSelect(tab),
            ),
            const SizedBox(width: TainaSpacing.space2),
          ],
        ],
      ),
    );
  }
}

/// The casa/praça filter: the readable set already carries both zones, so the
/// pills only narrow what the screen shows, and everything shows by default.
final class _GalleryZoneFilter extends StatelessWidget {
  const _GalleryZoneFilter({required this.model});

  final GalleryModel model;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
      child: Row(
        children: [
          for (final GalleryFilter filter in GalleryFilter.values) ...[
            _GalleryPill(
              title: GalleryModel.labelOfFilter(filter),
              current: model.filter == filter,
              onTap: () => model.selectFilter(filter),
            ),
            const SizedBox(width: TainaSpacing.space2),
          ],
        ],
      ),
    );
  }
}

/// One capsule pill of a segmented row.
final class _GalleryPill extends StatelessWidget {
  const _GalleryPill({
    required this.title,
    required this.current,
    required this.onTap,
  });

  final String title;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: current,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: TainaRadii.pillAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: TainaSizes.touch),
          padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: current ? TainaPalette.brandPrimary : Colors.transparent,
            borderRadius: TainaRadii.pillAll,
            border: Border.all(
              color: current
                  ? TainaPalette.brandPrimary
                  : TainaPalette.borderDefault,
              width: TainaSizes.hairline,
            ),
          ),
          child: TainaText(
            title,
            style: TainaTypography.label,
            color: current
                ? TainaPalette.textOnBrand
                : TainaPalette.textSecondary,
          ),
        ),
      ),
    );
  }
}

final class _GalleryContent extends StatelessWidget {
  const _GalleryContent({required this.model, required this.gateway});

  final GalleryModel model;
  final SessionGateway gateway;

  @override
  Widget build(BuildContext context) {
    if (model.empty) {
      if (model.loading) return _GalleryLoadingGrid();
      final TainaError? error = model.error;
      if (error != null) {
        return Center(
          child: TainaErrorState(error: error, onRetry: model.refresh),
        );
      }
      if (model.loaded) {
        final GalleryEmptyCopy copy = GalleryModel.emptyCopy(
          rawEmpty: model.rawEmpty,
          filter: model.filter,
        );
        return Center(
          child: TainaEmptyState(
            icon: Icons.photo_outlined,
            title: copy.title,
            message: copy.message,
          ),
        );
      }
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final int columns = GalleryModel.columnsFor(constraints.maxWidth);
        return RefreshIndicator(
          onRefresh: model.refresh,
          child: switch (model.tab) {
            GalleryTab.grid => _grid(columns),
            GalleryTab.timeline => _timeline(columns, context),
          },
        );
      },
    );
  }

  Widget _grid(int columns) {
    final List<FileRecord> files = model.filteredPhotos;
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
        const SliverToBoxAdapter(child: SizedBox(height: TainaSpacing.space4)),
      ],
    );
  }

  Widget _timeline(int columns, BuildContext context) {
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
                style: TainaTypography.h3,
                color: TainaPalette.textPrimary,
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
        const SliverToBoxAdapter(child: SizedBox(height: TainaSpacing.space4)),
      ],
    );
  }

  Widget get _footer {
    if (!model.canLoadMore) return const SliverToBoxAdapter(child: SizedBox());
    return SliverToBoxAdapter(
      child: _GalleryFooter(
        rearmKey: model.loadedCount,
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

/// The infinite-scroll sentinel: it loads the next page when it shows, and
/// re-arms when a page lands (a new [rearmKey]).
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

/// A grid tile: the square thumbnail, a play tile for videos (Jaci does not
/// make video thumbnails yet), and the zone on every tile.
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
          borderRadius: TainaRadii.smAll,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (video)
                const ColoredBox(
                  color: TainaPalette.surfaceHigh,
                  child: Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: TainaFontSizes.xxl,
                      color: TainaPalette.textSecondary,
                    ),
                  ),
                )
              else
                GalleryThumbnail(
                  gateway: gateway,
                  rkey: file.rkey,
                  size: ThumbnailSize.sm,
                ),
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(TainaSpacing.space2),
                  child: file.zona == Zona.casa
                      ? const TainaZonaBadge.casa()
                      : const TainaZonaBadge.praca(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The loading state in the shape of the grid it becomes.
final class _GalleryLoadingGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int columns = GalleryModel.columnsFor(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(TainaSpacing.space4),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: TainaSizes.gapPhoto,
            crossAxisSpacing: TainaSizes.gapPhoto,
          ),
          itemCount: columns * 3,
          itemBuilder: (context, index) =>
              const TainaSkeleton(borderRadius: TainaRadii.smAll),
        );
      },
    );
  }
}
