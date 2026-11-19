import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/mirror_asset_hasher.dart';
import 'package:okena_app/src/mirror/mirror_asset_materializer.dart';
import 'package:okena_app/src/mirror/streaming_mirror_hasher.dart';
import 'package:okena_core/okena_core.dart';

void main() {
  group('StreamingMirrorAssetHasher', () {
    test('hashes empty, small, and multi-chunk content', () async {
      final root = await Directory.systemTemp.createTemp('mirror-hasher-');
      addTearDown(() => root.delete(recursive: true));

      await _expectHash(
        root: root,
        name: 'empty',
        bytes: const [],
        expected:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      await _expectHash(
        root: root,
        name: 'abc',
        bytes: 'abc'.codeUnits,
        expected:
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      await _expectHash(
        root: root,
        name: 'million-a',
        bytes: List<int>.filled(1000000, 97, growable: false),
        expected:
            'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });

    test(
      'returns the stable materialized path and ignores metadata size',
      () async {
        final root = await Directory.systemTemp.createTemp('mirror-hasher-');
        addTearDown(() => root.delete(recursive: true));
        final file = File('${root.path}/stable/photo.jpg');
        await file.parent.create(recursive: true);
        await file.writeAsString('abc');
        final materializer = _FakeMaterializer(
          Ok(MaterializedAsset(path: file.path, size: 900)),
        );
        final hasher = StreamingMirrorAssetHasher(materializer);

        final result = await hasher.hash(_entry(size: 1));

        expect(result, isA<Ok<MirrorHashResult>>());
        final hash = (result as Ok<MirrorHashResult>).value;
        expect(
          hash.sha256,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        );
        expect(hash.localPath, file.path);
        expect(materializer.entries, hasLength(1));
      },
    );

    test(
      'forwards materialization errors and reports hash IO failures',
      () async {
        const materializationError = MirrorAssetReadError('asset disappeared');
        final failingMaterializer = _FakeMaterializer(
          const Err<MaterializedAsset>(materializationError),
        );
        final forwarded = await StreamingMirrorAssetHasher(failingMaterializer)
            .hash(_entry());
        expect(forwarded.error, materializationError);

        final missingMaterializer = _FakeMaterializer(
          const Ok(MaterializedAsset(path: '/missing/mirror-object', size: 0)),
        );
        final hashFailure = await StreamingMirrorAssetHasher(
          missingMaterializer,
        ).hash(_entry());
        expect(hashFailure.error, isA<MirrorAssetReadError>());
      },
    );
  });
}

Future<void> _expectHash({
  required Directory root,
  required String name,
  required List<int> bytes,
  required String expected,
}) async {
  final file = File('${root.path}/$name.bin');
  await file.writeAsBytes(bytes);
  final hasher = StreamingMirrorAssetHasher(
    _FakeMaterializer(
      Ok(MaterializedAsset(path: file.path, size: bytes.length)),
    ),
  );

  final result = await hasher.hash(_entry());

  expect(result.value?.sha256, expected);
  expect(result.value?.localPath, file.path);
}

MirrorEntry _entry({int? size = 1}) => MirrorEntry(
  assetId: 'asset',
  modificationDate: DateTime.utc(2026, 11, 18),
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
  updatedAt: DateTime.utc(2026, 11, 18),
);

final class _FakeMaterializer implements MirrorAssetMaterializer {
  _FakeMaterializer(this.result);

  final TainaResult<MaterializedAsset> result;
  final List<MirrorEntry> entries = [];

  @override
  Future<TainaResult<MaterializedAsset>> materialize(MirrorEntry entry) async {
    entries.add(entry);
    return result;
  }

  @override
  Future<TainaResult<void>> prune({required Set<String> retainedPaths}) async =>
      const Ok<void>(null);
}
