import 'dart:typed_data';

import 'package:okena_core/src/api/taina_api.dart';
import 'package:okena_core/src/result.dart';

/// A bounded in-memory thumbnail cache, keyed by rkey and size. A grid that
/// scrolls must not issue one request per row per pass over the screen.
///
/// Every thumbnail response is small and already webp, so bytes in memory are
/// the whole story: no disk cache yet. A failure is not cached, so a
/// transient miss retries on the next pass.
final class ThumbnailStore {
  ThumbnailStore({required this.api, this.countLimit = 256});

  final TainaApi api;

  /// Zero or negative means unbounded, like `NSCache.countLimit`.
  final int countLimit;
  final Map<String, Uint8List> _cache = {};

  /// Cached by rkey and size. A miss fetches once.
  Future<TainaResult<Uint8List>> data({
    required String rkey,
    required ThumbnailSize size,
  }) async {
    final key = '$rkey-${size.wire}';
    final hit = _cache[key];
    if (hit != null) return Ok(hit);

    final fetched = await api.thumbnail(rkey: rkey, size: size);
    switch (fetched) {
      case Ok(:final value):
        _keep(key, value);
      case Err():
        break;
    }
    return fetched;
  }

  void clear() => _cache.clear();

  void _keep(String key, Uint8List bytes) {
    if (countLimit > 0 && _cache.length >= countLimit) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = bytes;
  }
}
