import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:okena_core/okena_core.dart';
import 'package:path_provider/path_provider.dart';

import 'mirror_asset_materializer.dart';

String mirrorObjectPath({
  required String supportDirectoryPath,
  required String ownerId,
  required String assetId,
  required DateTime modificationDate,
  String? originalPath,
}) {
  if (ownerId.isEmpty) {
    throw ArgumentError.value(ownerId, 'ownerId', 'must not be empty');
  }
  if (assetId.isEmpty) {
    throw ArgumentError.value(assetId, 'assetId', 'must not be empty');
  }

  final ownerSegment = _encodedSegment(ownerId);
  final assetSegment = _encodedSegment(assetId);
  final revision =
      '${modificationDate.toUtc().microsecondsSinceEpoch}${_safeExtension(originalPath)}';
  return _joinPath([
    supportDirectoryPath,
    'taina_mirror',
    ownerSegment,
    'objects',
    assetSegment,
    revision,
  ]);
}

final class PhotoManagerAssetMaterializer implements MirrorAssetMaterializer {
  PhotoManagerAssetMaterializer({
    required this.ownerId,
    required this.originalFileProvider,
    this.rootDirectory,
  });

  static int _temporarySequence = 0;
  static final Random _random = Random.secure();
  static final Map<String, Future<void>> _pathLocks = {};

  final String ownerId;
  final MirrorOriginalFileProvider originalFileProvider;
  final Directory? rootDirectory;

  @override
  Future<TainaResult<MaterializedAsset>> materialize(MirrorEntry entry) async {
    if (ownerId.isEmpty || entry.assetId.isEmpty) {
      return const Err(MirrorAssetReadError('mirror asset identity is empty'));
    }

    try {
      final originalResult = await originalFileProvider.originalFile(
        entry.assetId,
      );
      if (originalResult case Err<File>(:final error)) return Err(error);
      final original = (originalResult as Ok<File>).value;
      if (!await original.exists() ||
          await FileSystemEntity.type(original.path) !=
              FileSystemEntityType.file) {
        return const Err(MirrorAssetReadError('original asset is missing'));
      }
      final originalSize = await original.length();
      final appRoot = rootDirectory ?? await getApplicationSupportDirectory();
      final targetPath = mirrorObjectPath(
        supportDirectoryPath: appRoot.path,
        ownerId: ownerId,
        assetId: entry.assetId,
        modificationDate: entry.modificationDate,
        originalPath: original.path,
      );

      return await _withPathLock(
        targetPath,
        () => _materializeFile(
          original: original,
          originalSize: originalSize,
          target: File(targetPath),
        ),
      );
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  @override
  Future<TainaResult<void>> prune({required Set<String> retainedPaths}) async {
    if (ownerId.isEmpty) {
      return const Err(MirrorAssetReadError('mirror owner identity is empty'));
    }
    try {
      final appRoot = rootDirectory ?? await getApplicationSupportDirectory();
      final mirrorDirectory = Directory(
        _joinPath([appRoot.path, 'taina_mirror']),
      );
      final ownerDirectory = Directory(
        _joinPath([mirrorDirectory.path, _encodedSegment(ownerId)]),
      );
      final objectsDirectory = Directory(
        _joinPath([ownerDirectory.path, 'objects']),
      );
      for (final directory in [
        mirrorDirectory,
        ownerDirectory,
        objectsDirectory,
      ]) {
        final type = await FileSystemEntity.type(
          directory.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) return const Ok<void>(null);
        if (type != FileSystemEntityType.directory) {
          return const Err(
            MirrorAssetReadError('mirror object path is not a directory'),
          );
        }
      }

      await for (final entity in objectsDirectory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (!retainedPaths.contains(entity.path)) await entity.delete();
      }
      return const Ok<void>(null);
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  Future<TainaResult<MaterializedAsset>> _materializeFile({
    required File original,
    required int originalSize,
    required File target,
  }) async {
    File? temporary;
    IOSink? sink;
    TainaResult<MaterializedAsset> result = const Err(
      MirrorAssetReadError('materialization did not complete'),
    );
    try {
      await target.parent.create(recursive: true);
      final existingSize = await _existingSize(target);
      if (existingSize != null) {
        if (existingSize == originalSize) {
          result = Ok(MaterializedAsset(path: target.path, size: existingSize));
        } else {
          result = const Err(
            MirrorAssetReadError('materialized revision has a different size'),
          );
        }
      } else {
        final temporaryFile = await _createTemporaryFile(
          target.parent,
          target.path,
        );
        temporary = temporaryFile;
        final output = temporaryFile.openWrite();
        sink = output;
        await output.addStream(original.openRead());
        await output.flush();
        await output.close();
        sink = null;

        final copiedSize = await temporaryFile.length();
        if (copiedSize != originalSize) {
          result = const Err(
            MirrorAssetReadError('original asset changed while materializing'),
          );
        } else {
          final racedSize = await _existingSize(target);
          if (racedSize != null) {
            result = racedSize == originalSize
                ? Ok(MaterializedAsset(path: target.path, size: racedSize))
                : const Err(
                    MirrorAssetReadError(
                      'materialized revision has a different size',
                    ),
                  );
          } else {
            try {
              await temporaryFile.rename(target.path);
              temporary = null;
              result = Ok(
                MaterializedAsset(path: target.path, size: copiedSize),
              );
            } on FileSystemException {
              final renameRaceSize = await _existingSize(target);
              if (renameRaceSize == null) rethrow;
              if (renameRaceSize != originalSize) {
                result = const Err(
                  MirrorAssetReadError(
                    'materialized revision has a different size',
                  ),
                );
              } else {
                await temporaryFile.delete();
                temporary = null;
                result = Ok(
                  MaterializedAsset(path: target.path, size: renameRaceSize),
                );
              }
            }
          }
        }
      }
    } catch (error) {
      final cleanupError = await _cleanupTemporary(temporary, sink);
      temporary = null;
      sink = null;
      if (error is Exception) {
        final cause = cleanupError == null
            ? error.toString()
            : '${error.toString()}; temporary cleanup failed: $cleanupError';
        return Err(MirrorAssetReadError(cause));
      }
      rethrow;
    }

    if (temporary != null) {
      final cleanupError = await _cleanupTemporary(temporary, sink);
      temporary = null;
      sink = null;
      if (cleanupError != null) {
        return Err(
          MirrorAssetReadError('temporary cleanup failed: $cleanupError'),
        );
      }
    }
    return result;
  }

  Future<int?> _existingSize(File target) async {
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw FileSystemException(
        'materialized revision is not a regular file',
        target.path,
      );
    }
    return target.length();
  }

  Future<File> _createTemporaryFile(
    Directory directory,
    String targetPath,
  ) async {
    for (var attempt = 0; attempt < 16; attempt++) {
      final nonce =
          '${DateTime.now().microsecondsSinceEpoch}-'
          '${_temporarySequence++}-'
          '${_random.nextInt(1 << 32).toRadixString(16)}';
      final temporary = File('$targetPath.$nonce.part');
      try {
        await temporary.create(exclusive: true);
        return temporary;
      } on FileSystemException {
        if (await FileSystemEntity.type(temporary.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          rethrow;
        }
      }
    }
    throw FileSystemException(
      'could not create a unique temporary file',
      directory.path,
    );
  }

  Future<String?> _cleanupTemporary(File? temporary, IOSink? sink) async {
    String? cleanupFailure;
    if (sink != null) {
      try {
        await sink.close();
      } on Exception catch (error) {
        cleanupFailure = error.toString();
      }
    }
    if (temporary != null) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on Exception catch (error) {
        cleanupFailure = cleanupFailure == null
            ? error.toString()
            : '$cleanupFailure; ${error.toString()}';
      }
    }
    return cleanupFailure;
  }

  Future<TainaResult<MaterializedAsset>> _withPathLock(
    String path,
    Future<TainaResult<MaterializedAsset>> Function() operation,
  ) async {
    final previous = _pathLocks[path] ?? Future<void>.value();
    final released = Completer<void>();
    _pathLocks[path] = released.future;
    await previous;
    try {
      return await operation();
    } finally {
      released.complete();
      if (identical(_pathLocks[path], released.future)) {
        _pathLocks.remove(path);
      }
    }
  }
}

String _encodedSegment(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

String _safeExtension(String? originalPath) {
  if (originalPath == null || originalPath.isEmpty) return '';
  final filename = _basename(originalPath);
  final dot = filename.lastIndexOf('.');
  if (dot <= 0 || dot == filename.length - 1) return '';
  final extension = filename.substring(dot + 1);
  final safe = extension.replaceAll(RegExp('[^A-Za-z0-9]'), '').toLowerCase();
  if (safe.isEmpty) return '';
  return '.${safe.length <= 12 ? safe : safe.substring(0, 12)}';
}

String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

String _joinPath(List<String> segments) {
  var path = segments.first;
  for (final segment in segments.skip(1)) {
    path = path.endsWith(Platform.pathSeparator)
        ? '$path$segment'
        : '$path${Platform.pathSeparator}$segment';
  }
  return path;
}
