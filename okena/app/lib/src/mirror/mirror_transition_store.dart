import 'package:okena_core/okena_core.dart';

/// A store that can persist one ledger transition without scanning every entry.
abstract class MirrorTransitionStore implements MirrorStore {
  /// Persists [changedEntries] and [removedAssetIds] against the confirmed
  /// snapshot, then records [ledger] as the new confirmed state.
  ///
  /// A store without a confirmed snapshot may fall back to a full load and
  /// replacement. Changed entries must be the exact entry instances in
  /// [ledger], and removed IDs must be absent from it.
  Future<TainaResult<void>> saveTransition(
    MirrorLedger ledger, {
    required Iterable<MirrorEntry> changedEntries,
    required Iterable<String> removedAssetIds,
  });
}
