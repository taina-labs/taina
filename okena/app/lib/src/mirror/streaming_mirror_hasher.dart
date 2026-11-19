import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:okena_core/okena_core.dart';

import 'mirror_asset_hasher.dart';
import 'mirror_asset_materializer.dart';

final class StreamingMirrorAssetHasher implements MirrorAssetHasher {
  const StreamingMirrorAssetHasher(this._materializer);

  final MirrorAssetMaterializer _materializer;

  @override
  Future<TainaResult<MirrorHashResult>> hash(MirrorEntry entry) async {
    try {
      final materializedResult = await _materializer.materialize(entry);
      if (materializedResult case Err<MaterializedAsset>(:final error)) {
        return Err(error);
      }
      final materialized = (materializedResult as Ok<MaterializedAsset>).value;
      final digest = await sha256
          .bind(File(materialized.path).openRead())
          .single;
      return Ok(
        MirrorHashResult(
          sha256: digest.toString(),
          localPath: materialized.path,
        ),
      );
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }
}
