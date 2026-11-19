import 'dart:io';

import 'package:okena_core/okena_core.dart';

Future<TainaResult<String>> resolveMirrorStoredPath({
  required String storedPath,
  required Future<Directory> Function() supportDirectoryProvider,
}) async {
  if (storedPath.trim().isEmpty) {
    return const Err(MirrorAssetReadError('mirror local path is missing'));
  }

  try {
    final pathType = await FileSystemEntity.type(
      storedPath,
      followLinks: false,
    );
    if (pathType != FileSystemEntityType.notFound) return Ok(storedPath);

    final segments = Uri.file(storedPath).pathSegments;
    final markerIndex = segments.indexOf('taina_mirror');
    if (markerIndex < 0) {
      return const Err(
        MirrorAssetReadError('stale mirror path has no taina_mirror segment'),
      );
    }
    final suffix = segments.skip(markerIndex).toList(growable: false);
    if (suffix.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      return const Err(
        MirrorAssetReadError('stale mirror path suffix is invalid'),
      );
    }

    final supportDirectory = await supportDirectoryProvider();
    final supportPath = Directory(supportDirectory.path).absolute.path;
    final resolved = File(
      '$supportPath${Platform.pathSeparator}'
      '${suffix.join(Platform.pathSeparator)}',
    ).absolute.path;
    if (!_isWithinDirectory(resolved, supportPath)) {
      return const Err(
        MirrorAssetReadError('stale mirror path escapes application support'),
      );
    }

    final canonicalRoot = await supportDirectory.resolveSymbolicLinks();
    final canonicalPath = await File(resolved).resolveSymbolicLinks();
    if (!_isWithinDirectory(canonicalPath, canonicalRoot)) {
      return const Err(
        MirrorAssetReadError('stale mirror path escapes application support'),
      );
    }
    return Ok(resolved);
  } on Exception catch (error) {
    return Err(MirrorAssetReadError(error.toString()));
  }
}

bool _isWithinDirectory(String path, String directory) {
  final separator = Platform.pathSeparator;
  final root = Directory(directory).absolute.path;
  final prefix = root.endsWith(separator) ? root : '$root$separator';
  return path == root || path.startsWith(prefix);
}
