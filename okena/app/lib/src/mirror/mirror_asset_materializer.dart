import 'dart:io';

import 'package:okena_core/okena_core.dart';

final class MaterializedAsset {
  const MaterializedAsset({required this.path, required this.size});

  final String path;
  final int size;
}

abstract class MirrorOriginalFileProvider {
  Future<TainaResult<File>> originalFile(String assetId);
}

abstract class MirrorAssetMaterializer {
  Future<TainaResult<MaterializedAsset>> materialize(MirrorEntry entry);

  Future<TainaResult<void>> prune({required Set<String> retainedPaths});
}
