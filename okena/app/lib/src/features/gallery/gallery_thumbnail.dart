import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// One image from the shared [ThumbnailStore], sized by the caller.
///
/// The future is held in the state and only replaced when the rkey or the
/// size changes, so a rebuild during a scroll pass never issues another
/// request; the store answers the repeat from its cache anyway.
final class GalleryThumbnail extends StatefulWidget {
  const GalleryThumbnail({
    required this.gateway,
    required this.rkey,
    required this.size,
    this.fit = BoxFit.cover,
    super.key,
  });

  final SessionGateway gateway;
  final String rkey;
  final ThumbnailSize size;
  final BoxFit fit;

  @override
  State<GalleryThumbnail> createState() => _GalleryThumbnailState();
}

final class _GalleryThumbnailState extends State<GalleryThumbnail> {
  late Future<TainaResult<Uint8List>> _bytes = _load();

  Future<TainaResult<Uint8List>> _load() {
    return widget.gateway.thumbnails.data(rkey: widget.rkey, size: widget.size);
  }

  @override
  void didUpdateWidget(GalleryThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rkey != widget.rkey ||
        oldWidget.size != widget.size ||
        oldWidget.gateway != widget.gateway) {
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
        if (snapshot.connectionState != ConnectionState.done) {
          return _placeholder(spinner: true);
        }
        final TainaResult<Uint8List>? result = snapshot.data;
        if (result == null) return _placeholder();
        return switch (result) {
          Ok(:final value) => Image.memory(
            value,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => _placeholder(),
          ),
          Err() => _placeholder(),
        };
      },
    );
  }

  Widget _placeholder({bool spinner = false}) {
    return ColoredBox(
      color: TainaPalette.surfaceRaised,
      child: spinner
          ? const Center(
              child: SizedBox(
                width: TainaSizes.controlSm / 2,
                height: TainaSizes.controlSm / 2,
                child: CircularProgressIndicator(
                  strokeWidth: TainaSizes.thick,
                  color: TainaPalette.textMuted,
                ),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}
