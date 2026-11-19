import 'package:okena_core/okena_core.dart';

enum MirrorLibraryAccess { full, limited, denied, restricted, notDetermined }

final class MirrorAssetPage {
  MirrorAssetPage({required List<MirrorAsset> assets, required this.hasMore})
    : assets = List<MirrorAsset>.unmodifiable(assets);

  final List<MirrorAsset> assets;
  final bool hasMore;
}

abstract class MirrorLibrary {
  Future<TainaResult<MirrorLibraryAccess>> currentAccess();

  Future<TainaResult<MirrorLibraryAccess>> requestAccess();

  Future<TainaResult<void>> openSettings();

  Future<TainaResult<MirrorAssetPage>> page({
    required int page,
    int size = 200,
  });

  Future<TainaResult<void>> presentLimitedSelection();
}

Future<TainaResult<List<MirrorAsset>>> collectMirrorAssets(
  MirrorLibrary library, {
  int pageSize = 200,
}) async {
  if (pageSize <= 0) {
    return const Err(InvalidResponseError('mirror library page size'));
  }

  final assetsById = <String, MirrorAsset>{};
  var page = 0;
  while (true) {
    final result = await library.page(page: page, size: pageSize);
    if (result case Err<MirrorAssetPage>(:final error)) return Err(error);

    final assetPage = (result as Ok<MirrorAssetPage>).value;
    for (final asset in assetPage.assets) {
      assetsById[asset.assetId] = asset;
    }
    if (!assetPage.hasMore) {
      return Ok(List<MirrorAsset>.unmodifiable(assetsById.values));
    }
    page++;
  }
}
