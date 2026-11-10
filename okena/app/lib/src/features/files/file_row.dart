import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';

import '../../design_system/design_system.dart';

/// The thumbnail, from the shared store: a placeholder while it loads and a
/// document glyph when the file has none.
final class FileThumbnail extends StatefulWidget {
  const FileThumbnail({
    required this.thumbnails,
    required this.rkey,
    this.size = ThumbnailSize.sm,
    this.side = TainaSizes.controlMd,
    super.key,
  });

  final ThumbnailStore thumbnails;
  final String rkey;
  final ThumbnailSize size;
  final double side;

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

final class _FileThumbnailState extends State<FileThumbnail> {
  Uint8List? _bytes;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rkey == widget.rkey && oldWidget.size == widget.size) {
      return;
    }
    _bytes = null;
    _missing = false;
    _load();
  }

  Future<void> _load() async {
    final result = await widget.thumbnails.data(
      rkey: widget.rkey,
      size: widget.size,
    );
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        setState(() => _bytes = value);
      case Err():
        setState(() => _missing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: TainaRadii.smAll,
      child: SizedBox(
        width: widget.side,
        height: widget.side,
        child: _content(),
      ),
    );
  }

  Widget _content() {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _glyph(),
      );
    }
    if (_missing) return _glyph();
    return TainaSkeleton(
      width: widget.side,
      height: widget.side,
      borderRadius: TainaRadii.smAll,
    );
  }

  Widget _glyph() {
    return ColoredBox(
      color: TainaPalette.surfaceRaised,
      child: Icon(
        Icons.description_outlined,
        size: TainaFontSizes.xl,
        color: TainaPalette.textFaint,
      ),
    );
  }
}

/// A file row: the thumbnail (a document glyph when there is none), the name,
/// and a secondary line of size and date, scanned in mono. The praca badge
/// shows only for the praca, where being public is the news.
final class FileRow extends StatelessWidget {
  const FileRow({
    required this.file,
    required this.thumbnails,
    this.onTap,
    super.key,
  });

  final FileRecord file;
  final ThumbnailStore thumbnails;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TainaRowCard(
      onTap: onTap,
      child: Row(
        children: [
          FileThumbnail(thumbnails: thumbnails, rkey: file.rkey),
          const SizedBox(width: TainaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TainaText(
                  file.name,
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: TainaSpacing.space1),
                TainaText(
                  '${TainaFormat.bytes(file.size)} / '
                  '${TainaFormat.relative(file.createdAt)}',
                  style: TainaTypography.monoSm,
                  color: TainaPalette.textMuted,
                ),
                if (file.zona == Zona.praca) ...[
                  const SizedBox(height: TainaSpacing.space1),
                  const TainaZonaBadge.praca(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
