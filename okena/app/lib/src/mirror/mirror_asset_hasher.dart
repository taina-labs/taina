import 'package:okena_core/okena_core.dart';

/// The result of reading and hashing one asset from the device's camera roll.
final class MirrorHashResult {
  const MirrorHashResult({required this.sha256, required this.localPath});

  final String sha256;

  /// A stable path that the background transfer boundary can reopen later.
  final String localPath;
}

/// App boundary for hashing a camera-roll asset.
///
/// Production streaming and platform access are implemented behind this
/// boundary. The engine owns persistence of successful hash results.
abstract class MirrorAssetHasher {
  Future<TainaResult<MirrorHashResult>> hash(MirrorEntry entry);
}
