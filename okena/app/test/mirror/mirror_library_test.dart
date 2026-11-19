import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/mirror_library.dart';
import 'package:okena_core/okena_core.dart';

void main() {
  group('collectMirrorAssets', () {
    test(
      'reads all pages and lets later metadata replace duplicate IDs',
      () async {
        final first = _asset(id: 'duplicate', name: 'old.jpg');
        final latest = _asset(id: 'duplicate', name: 'new.jpg', size: 29);
        final library = _FakeMirrorLibrary([
          MirrorAssetPage(assets: [first], hasMore: true),
          MirrorAssetPage(assets: [], hasMore: true),
          MirrorAssetPage(
            assets: [
              latest,
              _asset(id: 'other'),
            ],
            hasMore: false,
          ),
        ]);

        final result = await collectMirrorAssets(library, pageSize: 12);

        expect(result, isA<Ok<List<MirrorAsset>>>());
        expect((result as Ok<List<MirrorAsset>>).value, [
          latest,
          _asset(id: 'other'),
        ]);
        expect(library.pageCalls, [(0, 12), (1, 12), (2, 12)]);
      },
    );

    test('rejects invalid page sizes without reading a page', () async {
      final library = _FakeMirrorLibrary(const []);

      final result = await collectMirrorAssets(library, pageSize: 0);

      expect(result, isA<Err<List<MirrorAsset>>>());
      expect(library.pageCalls, isEmpty);
    });

    test('forwards page failures unchanged', () async {
      const failure = MirrorAssetReadError('permission changed');
      final library = _FakeMirrorLibrary([
        MirrorAssetPage(assets: [_asset()], hasMore: true),
      ], pageFailure: const Err<MirrorAssetPage>(failure));

      final result = await collectMirrorAssets(library);

      expect(result.error, failure);
      expect(library.pageCalls, [(0, 200), (1, 200)]);
    });
  });
}

MirrorAsset _asset({
  String id = 'asset',
  String name = 'asset.jpg',
  int? size = 10,
}) => MirrorAsset(
  assetId: id,
  modificationDate: DateTime.utc(2026, 11, 19),
  filename: name,
  mime: 'image/jpeg',
  size: size,
  takenAt: null,
);

final class _FakeMirrorLibrary implements MirrorLibrary {
  _FakeMirrorLibrary(this.pages, {this.pageFailure});

  final List<MirrorAssetPage> pages;
  final TainaResult<MirrorAssetPage>? pageFailure;
  final List<(int, int)> pageCalls = [];

  @override
  Future<TainaResult<MirrorLibraryAccess>> currentAccess() async {
    return const Ok(MirrorLibraryAccess.full);
  }

  @override
  Future<TainaResult<MirrorLibraryAccess>> requestAccess() async =>
      const Ok(MirrorLibraryAccess.full);

  @override
  Future<TainaResult<void>> openSettings() async => const Ok<void>(null);

  @override
  Future<TainaResult<MirrorAssetPage>> page({
    required int page,
    int size = 200,
  }) async {
    pageCalls.add((page, size));
    if (pageFailure != null && page == pages.length) return pageFailure!;
    return Ok(pages[page]);
  }

  @override
  Future<TainaResult<void>> presentLimitedSelection() async =>
      const Ok<void>(null);
}
