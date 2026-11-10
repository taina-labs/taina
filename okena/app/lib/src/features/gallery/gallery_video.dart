import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_core/okena_core.dart';
import 'package:video_player/video_player.dart';

import 'gallery_model.dart';

/// The video page's playback, behind an interface so widget tests never need
/// the platform plugin.
abstract interface class GalleryVideoPlayer {
  Future<void> initialize(String path);

  Future<void> play();

  Future<void> pause();

  Future<void> dispose();

  bool get isInitialized;

  bool get isPlaying;

  double get aspectRatio;

  Widget build();

  Widget buildProgress();
}

typedef GalleryVideoPlayerFactory = GalleryVideoPlayer Function();

/// The real player: the downloaded local file, played by `video_player`.
final class PlatformGalleryVideoPlayer implements GalleryVideoPlayer {
  VideoPlayerController? _controller;

  @override
  Future<void> initialize(String path) async {
    final VideoPlayerController controller = VideoPlayerController.file(
      File(path),
    );
    _controller = controller;
    await controller.initialize();
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> dispose() async {
    final VideoPlayerController? controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  double get aspectRatio {
    final double ratio = _controller?.value.aspectRatio ?? 1;
    return ratio <= 0 ? 1 : ratio;
  }

  @override
  Widget build() {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: VideoPlayer(controller),
    );
  }

  @override
  Widget buildProgress() {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return VideoProgressIndicator(
      controller,
      allowScrubbing: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

/// The viewer's video page: no video thumbnail exists yet, so the page stays
/// the play surface until the person taps it; then the file downloads and
/// plays. The page owns its own player and its own loading state.
final class GalleryVideoPage extends StatefulWidget {
  const GalleryVideoPage({
    required this.model,
    required this.file,
    required this.active,
    this.playerFactory = defaultGalleryVideoPlayer,
    super.key,
  });

  final GalleryModel model;
  final FileRecord file;
  final bool active;
  final GalleryVideoPlayerFactory playerFactory;

  @override
  State<GalleryVideoPage> createState() => _GalleryVideoPageState();
}

GalleryVideoPlayer defaultGalleryVideoPlayer() => PlatformGalleryVideoPlayer();

final class _GalleryVideoPageState extends State<GalleryVideoPage> {
  GalleryVideoPlayer? _player;
  String? _path;
  String? _failedPath;
  bool _initializing = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModelChanged);
    _sync();
  }

  @override
  void didUpdateWidget(GalleryVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.removeListener(_onModelChanged);
      widget.model.addListener(_onModelChanged);
      unawaited(_dropPlayer());
    }
    if (oldWidget.active != widget.active) {
      if (!widget.active) {
        unawaited(_player?.pause());
      } else if (_player != null) {
        unawaited(_player!.play());
      }
    }
    if (oldWidget.file.rkey != widget.file.rkey) {
      unawaited(_dropPlayer());
    }
    _sync();
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    unawaited(_dropPlayer());
    super.dispose();
  }

  void _onModelChanged() {
    if (!mounted) return;
    setState(() {});
    _sync();
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final GalleryVideoState state = widget.model.video;
    if (state is! GalleryVideoReady ||
        state.file.rkey != widget.file.rkey ||
        state.path == _failedPath) {
      await _dropPlayer();
      return;
    }
    if (_path == state.path && _player != null) {
      if (widget.active) await _player!.play();
      return;
    }
    await _dropPlayer();
    final int token = ++_token;
    final GalleryVideoPlayer player = widget.playerFactory();
    setState(() {
      _initializing = true;
    });
    try {
      await player.initialize(state.path);
    } on Object {
      if (token != _token) {
        await player.dispose();
        return;
      }
      await player.dispose();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _failedPath = state.path;
      });
      return;
    }
    if (!mounted || token != _token) {
      await player.dispose();
      return;
    }
    _player = player;
    _path = state.path;
    if (widget.active) await player.play();
    if (!mounted) return;
    setState(() {
      _initializing = false;
    });
  }

  Future<void> _dropPlayer() async {
    final GalleryVideoPlayer? player = _player;
    _player = null;
    _path = null;
    _token += 1;
    if (_initializing && mounted) {
      setState(() {
        _initializing = false;
      });
    }
    if (player != null) {
      await player.pause();
      await player.dispose();
    }
  }

  void _retry() {
    setState(() {
      _failedPath = null;
      _initializing = false;
    });
    unawaited(_dropPlayer());
    unawaited(widget.model.retryVideo(widget.file));
  }

  Future<void> _togglePlayback(GalleryVideoPlayer player) async {
    if (player.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final GalleryVideoState state = widget.model.video;
    final GalleryVideoPlayer? player = _player;

    if (player != null && player.isInitialized) {
      return Padding(
        padding: const EdgeInsets.all(TainaSpacing.space8),
        child: AspectRatio(
          aspectRatio: 1,
          child: Semantics(
            button: true,
            label: player.isPlaying ? 'Pausar vídeo' : 'Reproduzir vídeo',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_togglePlayback(player)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(child: player.build()),
                  if (!player.isPlaying)
                    const Icon(
                      Icons.play_circle_outline,
                      color: Colors.white,
                      size: 56,
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: player.buildProgress(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_initializing) {
      return _surfaceFrame(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: TainaPalette.textMuted),
            SizedBox(height: TainaSpacing.space3),
            TainaText(
              'Abrindo vídeo...',
              style: TainaTypography.caption,
              color: TainaPalette.textMuted,
            ),
          ],
        ),
      );
    }

    return switch (state) {
      GalleryVideoLoading() => _surfaceFrame(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: TainaPalette.textMuted),
            SizedBox(height: TainaSpacing.space3),
            TainaText(
              'Baixando vídeo...',
              style: TainaTypography.caption,
              color: TainaPalette.textMuted,
            ),
          ],
        ),
      ),
      GalleryVideoFailed(file: final FileRecord failed) when _isThis(failed) =>
        _surfaceFrame(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TainaText(
                'Não foi possível abrir o vídeo.',
                style: TainaTypography.caption,
                color: TainaPalette.textMuted,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TainaSpacing.space3),
              SizedBox(
                width: 200,
                child: TainaSecondaryButton(
                  label: 'Tentar de novo',
                  onPressed: _retry,
                ),
              ),
            ],
          ),
        ),
      _ when _failedPath != null && widget.model.video is GalleryVideoReady =>
        _surfaceFrame(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TainaText(
                'Não foi possível abrir o vídeo.',
                style: TainaTypography.caption,
                color: TainaPalette.textMuted,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TainaSpacing.space3),
              SizedBox(
                width: 200,
                child: TainaSecondaryButton(
                  label: 'Tentar de novo',
                  onPressed: _retry,
                ),
              ),
            ],
          ),
        ),
      _ => Semantics(
        button: true,
        label: 'Assistir ${widget.file.name}',
        child: GestureDetector(
          onTap: () => unawaited(widget.model.play(widget.file)),
          child: _surfaceFrame(
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: TainaFontSizes.display,
                  color: TainaPalette.textSecondary,
                ),
                SizedBox(height: TainaSpacing.space3),
                TainaText(
                  'Toque para assistir',
                  style: TainaTypography.caption,
                  color: TainaPalette.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    };
  }

  bool _isThis(FileRecord file) => file.rkey == widget.file.rkey;

  Widget _surfaceFrame(Widget content) {
    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(TainaSpacing.space8),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: TainaPalette.surfaceHigh),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(TainaSpacing.space4),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
