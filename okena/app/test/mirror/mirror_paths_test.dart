import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/mirror_paths.dart';
import 'package:okena_core/okena_core.dart';

void main() {
  group('resolveMirrorStoredPath', () {
    test(
      'returns an existing path unchanged without reading support',
      () async {
        final root = await _createTemporaryDirectory();
        addTearDown(() => root.delete(recursive: true));
        final file = File('${root.path}${Platform.pathSeparator}photo.jpg');
        await file.writeAsString('photo');
        var supportDirectoryCalls = 0;

        final result = await resolveMirrorStoredPath(
          storedPath: file.path,
          supportDirectoryProvider: () async {
            supportDirectoryCalls += 1;
            return root;
          },
        );

        expect(result, isA<Ok<String>>());
        expect(result.value, file.path);
        expect(supportDirectoryCalls, 0);
      },
    );

    test(
      'reroots a stale container path under current application support',
      () async {
        final root = await _createTemporaryDirectory();
        addTearDown(() => root.delete(recursive: true));
        final supportDirectory = Directory(
          '${root.path}${Platform.pathSeparator}current-support',
        );
        final currentPath = File(
          '${supportDirectory.path}${Platform.pathSeparator}'
          'taina_mirror${Platform.pathSeparator}'
          'album${Platform.pathSeparator}photo.jpg',
        );
        await currentPath.parent.create(recursive: true);
        await currentPath.writeAsString('photo');
        var supportDirectoryCalls = 0;
        final separator = Platform.pathSeparator;
        final stalePath =
            '${root.path}${separator}old-container${separator}app-support'
            '${separator}taina_mirror${separator}album${separator}photo.jpg';

        final result = await resolveMirrorStoredPath(
          storedPath: stalePath,
          supportDirectoryProvider: () async {
            supportDirectoryCalls += 1;
            return supportDirectory;
          },
        );

        expect(result, isA<Ok<String>>());
        expect(result.value, currentPath.absolute.path);
        expect(supportDirectoryCalls, 1);
      },
    );

    test('rejects a stale path without a taina_mirror segment', () async {
      final root = await _createTemporaryDirectory();
      addTearDown(() => root.delete(recursive: true));
      var supportDirectoryCalls = 0;

      final result = await resolveMirrorStoredPath(
        storedPath:
            '${root.path}${Platform.pathSeparator}old-container/photo.jpg',
        supportDirectoryProvider: () async {
          supportDirectoryCalls += 1;
          return root;
        },
      );

      expect(
        result.error,
        const MirrorAssetReadError(
          'stale mirror path has no taina_mirror segment',
        ),
      );
      expect(supportDirectoryCalls, 0);
    });

    test('rejects a blank stored path', () async {
      final root = await _createTemporaryDirectory();
      addTearDown(() => root.delete(recursive: true));
      var supportDirectoryCalls = 0;

      final result = await resolveMirrorStoredPath(
        storedPath: '  ',
        supportDirectoryProvider: () async {
          supportDirectoryCalls += 1;
          return root;
        },
      );

      expect(
        result.error,
        const MirrorAssetReadError('mirror local path is missing'),
      );
      expect(supportDirectoryCalls, 0);
    });

    test('rejects an empty segment after taina_mirror', () async {
      final root = await _createTemporaryDirectory();
      addTearDown(() => root.delete(recursive: true));
      var supportDirectoryCalls = 0;
      final separator = Platform.pathSeparator;
      final storedPath =
          '${root.path}${separator}old-container${separator}taina_mirror'
          '$separator$separator'
          'album${separator}missing.jpg';

      final result = await resolveMirrorStoredPath(
        storedPath: storedPath,
        supportDirectoryProvider: () async {
          supportDirectoryCalls += 1;
          return root;
        },
      );

      expect(
        (result.error! as MirrorAssetReadError).cause,
        'stale mirror path suffix is invalid',
      );
      expect(supportDirectoryCalls, 0);
    });

    test('rejects a parent traversal after taina_mirror', () async {
      final root = await _createTemporaryDirectory();
      addTearDown(() => root.delete(recursive: true));
      final supportDirectory = Directory(
        '${root.path}${Platform.pathSeparator}support',
      );
      final currentPath = File(
        '${supportDirectory.path}${Platform.pathSeparator}'
        'taina_mirror${Platform.pathSeparator}photo.jpg',
      );
      await currentPath.parent.create(recursive: true);
      await currentPath.writeAsString('photo');
      var supportDirectoryCalls = 0;
      final separator = Platform.pathSeparator;
      final storedPath =
          '${root.path}${separator}old-container${separator}taina_mirror'
          '${separator}album$separator..${separator}photo.jpg';

      final result = await resolveMirrorStoredPath(
        storedPath: storedPath,
        supportDirectoryProvider: () async {
          supportDirectoryCalls += 1;
          return supportDirectory;
        },
      );

      expect(
        result.error,
        const MirrorAssetReadError('stale mirror path suffix is invalid'),
      );
      expect(supportDirectoryCalls, 0);
    });

    test('rejects a symlink whose canonical target escapes support', () async {
      final root = await _createTemporaryDirectory();
      addTearDown(() => root.delete(recursive: true));
      final supportDirectory = Directory(
        '${root.path}${Platform.pathSeparator}support',
      );
      final outsideFile = File(
        '${root.path}${Platform.pathSeparator}outside${Platform.pathSeparator}'
        'photo.jpg',
      );
      final linkedPath = File(
        '${supportDirectory.path}${Platform.pathSeparator}'
        'taina_mirror${Platform.pathSeparator}album${Platform.pathSeparator}'
        'photo.jpg',
      );
      await outsideFile.parent.create(recursive: true);
      await outsideFile.writeAsString('photo');
      await linkedPath.parent.create(recursive: true);
      await Link(linkedPath.path).create(outsideFile.path);
      final separator = Platform.pathSeparator;
      final stalePath =
          '${root.path}${separator}old-container${separator}taina_mirror'
          '${separator}album${separator}photo.jpg';

      final result = await resolveMirrorStoredPath(
        storedPath: stalePath,
        supportDirectoryProvider: () async => supportDirectory,
      );

      expect(
        result.error,
        const MirrorAssetReadError(
          'stale mirror path escapes application support',
        ),
      );
    });

    test(
      'accepts a symlink whose canonical target stays inside support',
      () async {
        final root = await _createTemporaryDirectory();
        addTearDown(() => root.delete(recursive: true));
        final supportDirectory = Directory(
          '${root.path}${Platform.pathSeparator}support',
        );
        final target = File(
          '${supportDirectory.path}${Platform.pathSeparator}canonical'
          '${Platform.pathSeparator}photo.jpg',
        );
        final linkedPath = File(
          '${supportDirectory.path}${Platform.pathSeparator}'
          'taina_mirror${Platform.pathSeparator}album${Platform.pathSeparator}'
          'photo.jpg',
        );
        await target.parent.create(recursive: true);
        await target.writeAsString('photo');
        await linkedPath.parent.create(recursive: true);
        await Link(linkedPath.path).create(target.path);
        final separator = Platform.pathSeparator;
        final stalePath =
            '${root.path}${separator}old-container${separator}taina_mirror'
            '${separator}album${separator}photo.jpg';

        final result = await resolveMirrorStoredPath(
          storedPath: stalePath,
          supportDirectoryProvider: () async => supportDirectory,
        );

        expect(result, isA<Ok<String>>());
        expect(result.value, linkedPath.absolute.path);
        expect(
          await File(result.value!).resolveSymbolicLinks(),
          await target.resolveSymbolicLinks(),
        );
      },
    );
  });
}

Future<Directory> _createTemporaryDirectory() {
  return Directory.systemTemp.createTemp('mirror_paths_test_');
}
