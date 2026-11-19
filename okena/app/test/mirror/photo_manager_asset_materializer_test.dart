import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/mirror_asset_materializer.dart';
import 'package:okena_app/src/mirror/photo_manager_asset_materializer.dart';
import 'package:okena_core/okena_core.dart';

void main() {
  group('mirrorObjectPath', () {
    test(
      'encodes identifiers, includes revisions, and sanitizes extensions',
      () {
        final modified = DateTime.utc(2026, 11, 19, 9, 30);
        final path = mirrorObjectPath(
          supportDirectoryPath: '/support',
          ownerId: '../owner/one',
          assetId: 'album/photo:1',
          modificationDate: modified,
          originalPath: '/photos/photo.h!e_i-c-with-a-long-extension',
        );
        final segments = path.split(Platform.pathSeparator);

        expect(
          segments,
          contains(base64Url.encode(utf8.encode('../owner/one'))),
        );
        expect(
          segments,
          contains(
            base64Url.encode(utf8.encode('album/photo:1')).replaceAll('=', ''),
          ),
        );
        expect(segments, contains('objects'));
        expect(
          segments.last,
          '${modified.microsecondsSinceEpoch}.heicwithalon',
        );
        expect(segments, isNot(contains('../owner/one')));
        expect(segments, isNot(contains('album/photo:1')));
      },
    );

    test('omits an absent or unsafe extension', () {
      final path = mirrorObjectPath(
        supportDirectoryPath: '/support',
        ownerId: 'owner',
        assetId: 'asset',
        modificationDate: DateTime.utc(2026),
        originalPath: '/photos/photo.bad-ext!',
      );

      expect(
        path.split(Platform.pathSeparator).last,
        '1767225600000000.badext',
      );
      expect(
        mirrorObjectPath(
          supportDirectoryPath: '/support',
          ownerId: 'owner',
          assetId: 'asset',
          modificationDate: DateTime.utc(2026),
        ).split(Platform.pathSeparator).last,
        '1767225600000000',
      );
    });
  });

  group('PhotoManagerAssetMaterializer', () {
    test('streams large originals into a stable app-owned path', () async {
      final root = await Directory.systemTemp.createTemp(
        'mirror-materializer-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/source/photo.HEIC');
      await source.parent.create(recursive: true);
      final content = List<int>.generate(
        700 * 1024 + 31,
        (index) => index % 251,
        growable: false,
      );
      await source.writeAsBytes(content);
      final provider = _FakeOriginalFileProvider(Ok(source));
      final materializer = PhotoManagerAssetMaterializer(
        ownerId: '../owner',
        originalFileProvider: provider,
        rootDirectory: Directory('${root.path}/support'),
      );

      final first = await materializer.materialize(_entry(size: 1));
      expect(first, isA<Ok<MaterializedAsset>>());
      final firstAsset = (first as Ok<MaterializedAsset>).value;
      expect(firstAsset.size, content.length);
      expect(firstAsset.path, contains('/objects/'));
      expect(firstAsset.path, endsWith('.heic'));
      expect(await File(firstAsset.path).readAsBytes(), content);

      final temporaryFiles = await _filesEndingWith(
        Directory('${root.path}/support'),
        '.part',
      );
      expect(temporaryFiles, isEmpty);
    });

    test(
      'reuses same-size revisions and does not overwrite a native task file',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'mirror-materializer-',
        );
        addTearDown(() => root.delete(recursive: true));
        final source = File('${root.path}/source/photo.jpg');
        await source.parent.create(recursive: true);
        await source.writeAsString('original bytes');
        final provider = _FakeOriginalFileProvider(Ok(source));
        final materializer = PhotoManagerAssetMaterializer(
          ownerId: 'owner',
          originalFileProvider: provider,
          rootDirectory: Directory('${root.path}/support'),
        );
        final entry = _entry();

        final first = (await materializer.materialize(
          entry,
        ) as Ok<MaterializedAsset>).value;
        await source.writeAsString('updated bytes!');
        final secondResult = await materializer.materialize(entry);
        final second = (secondResult as Ok<MaterializedAsset>).value;

        expect(second.path, first.path);
        expect(second.size, first.size);
        expect(await File(second.path).readAsString(), 'original bytes');
      },
    );

    test(
      'same-revision size conflicts return an error without replacing the file',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'mirror-materializer-',
        );
        addTearDown(() => root.delete(recursive: true));
        final source = File('${root.path}/source/photo.jpg');
        await source.parent.create(recursive: true);
        await source.writeAsString('source');
        final support = Directory('${root.path}/support');
        final entry = _entry();
        final targetPath = mirrorObjectPath(
          supportDirectoryPath: support.path,
          ownerId: 'owner',
          assetId: entry.assetId,
          modificationDate: entry.modificationDate,
          originalPath: source.path,
        );
        final target = File(targetPath);
        await target.parent.create(recursive: true);
        await target.writeAsString('native task is using this');
        final materializer = PhotoManagerAssetMaterializer(
          ownerId: 'owner',
          originalFileProvider: _FakeOriginalFileProvider(Ok(source)),
          rootDirectory: support,
        );

        final result = await materializer.materialize(entry);

        expect(result.error, isA<MirrorAssetReadError>());
        expect(await target.readAsString(), 'native task is using this');
      },
    );

    test(
      'missing originals and provider failures leave no object files',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'mirror-materializer-',
        );
        addTearDown(() => root.delete(recursive: true));
        final support = Directory('${root.path}/support');
        final missing = File('${root.path}/source/missing.jpg');
        final materializer = PhotoManagerAssetMaterializer(
          ownerId: 'owner',
          originalFileProvider: _FakeOriginalFileProvider(Ok(missing)),
          rootDirectory: support,
        );

        expect(
          (await materializer.materialize(_entry())).error,
          isA<MirrorAssetReadError>(),
        );
        expect(await _filesUnder(support), isEmpty);

        const failure = MirrorAssetReadError('plugin failed');
        final failedMaterializer = PhotoManagerAssetMaterializer(
          ownerId: 'owner',
          originalFileProvider: _FakeOriginalFileProvider(
            const Err<File>(failure),
          ),
          rootDirectory: support,
        );
        expect((await failedMaterializer.materialize(_entry())).error, failure);
        expect(await _filesUnder(support), isEmpty);
      },
    );

    test('concurrent materialization keeps one complete final file', () async {
      final root = await Directory.systemTemp.createTemp(
        'mirror-materializer-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/source/photo.jpg');
      await source.parent.create(recursive: true);
      final bytes = List<int>.filled(600 * 1024, 91);
      await source.writeAsBytes(bytes);
      final materializer = PhotoManagerAssetMaterializer(
        ownerId: 'owner',
        originalFileProvider: _FakeOriginalFileProvider(Ok(source)),
        rootDirectory: Directory('${root.path}/support'),
      );

      final results = await Future.wait([
        materializer.materialize(_entry()),
        materializer.materialize(_entry()),
      ]);

      expect(results.every((result) => result.isSuccess), isTrue);
      final paths = results.map((result) => result.value!.path).toSet();
      expect(paths, hasLength(1));
      expect(await File(paths.single).readAsBytes(), bytes);
      expect(
        await _filesEndingWith(Directory('${root.path}/support'), '.part'),
        isEmpty,
      );
    });

    test('prune keeps retained files, deletes stale and part files, and does not follow links', () async {
      final root = await Directory.systemTemp.createTemp(
        'mirror-materializer-',
      );
      addTearDown(() => root.delete(recursive: true));
      final support = Directory('${root.path}/support');
      final entry = _entry();
      final retained = File(
        mirrorObjectPath(
          supportDirectoryPath: support.path,
          ownerId: 'owner',
          assetId: 'retained',
          modificationDate: entry.modificationDate,
          originalPath: '/source/retained.jpg',
        ),
      );
      final stale = File(
        mirrorObjectPath(
          supportDirectoryPath: support.path,
          ownerId: 'owner',
          assetId: 'stale',
          modificationDate: entry.modificationDate,
          originalPath: '/source/stale.jpg',
        ),
      );
      final part = File('${stale.path}.interrupted.part');
      await retained.parent.create(recursive: true);
      await retained.writeAsString('keep');
      await stale.parent.create(recursive: true);
      await stale.writeAsString('remove');
      await part.writeAsString('remove');

      final outside = File('${root.path}/outside.jpg');
      await outside.writeAsString('outside');
      final link = Link('${stale.parent.path}/external-link');
      await link.create(outside.path);
      final materializer = PhotoManagerAssetMaterializer(
        ownerId: 'owner',
        originalFileProvider: _FakeOriginalFileProvider(
          const Err<File>(MirrorAssetReadError('unused')),
        ),
        rootDirectory: support,
      );

      final result = await materializer.prune(retainedPaths: {retained.path});

      expect(result.isSuccess, isTrue);
      expect(await retained.exists(), isTrue);
      expect(await stale.exists(), isFalse);
      expect(await part.exists(), isFalse);
      expect(await outside.readAsString(), 'outside');
      expect(await link.exists(), isTrue);
    });
  });
}

MirrorEntry _entry({String id = 'asset/one', int? size = 128}) => MirrorEntry(
  assetId: id,
  modificationDate: DateTime.utc(2026, 11, 18, 10),
  filename: 'photo.jpg',
  mime: 'image/jpeg',
  size: size,
  takenAt: null,
  sha256: null,
  localPath: null,
  state: MirrorState.newAsset,
  rkey: null,
  backgroundTaskId: null,
  attempts: 0,
  lastError: null,
  progress: 0,
  updatedAt: DateTime.utc(2026, 11, 18, 10),
);

Future<List<File>> _filesUnder(Directory directory) async {
  if (!await directory.exists()) return const [];
  final files = <File>[];
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) files.add(entity);
  }
  return files;
}

Future<List<File>> _filesEndingWith(Directory directory, String suffix) async {
  final files = await _filesUnder(directory);
  return files.where((file) => file.path.endsWith(suffix)).toList();
}

final class _FakeOriginalFileProvider implements MirrorOriginalFileProvider {
  _FakeOriginalFileProvider(this.result);

  final TainaResult<File> result;

  @override
  Future<TainaResult<File>> originalFile(String assetId) async => result;
}
