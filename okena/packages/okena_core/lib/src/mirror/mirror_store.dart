import 'package:okena_core/src/mirror/mirror_ledger.dart';
import 'package:okena_core/src/result.dart';

/// Persistence boundary for the local camera-roll ledger.
abstract class MirrorStore {
  Future<TainaResult<MirrorLedger?>> load();

  Future<TainaResult<void>> save(MirrorLedger ledger);

  Future<TainaResult<void>> clear();
}

/// In-memory implementation for tests and previews.
final class InMemoryMirrorStore implements MirrorStore {
  InMemoryMirrorStore([MirrorLedger? stored]) : _stored = _copy(stored);

  MirrorLedger? _stored;

  @override
  Future<TainaResult<MirrorLedger?>> load() async => Ok(_copy(_stored));

  @override
  Future<TainaResult<void>> save(MirrorLedger ledger) async {
    _stored = _copy(ledger);
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<void>> clear() async {
    _stored = null;
    return const Ok<void>(null);
  }

  static MirrorLedger? _copy(MirrorLedger? ledger) {
    if (ledger == null) return null;
    return MirrorLedger(
      ownerId: ledger.ownerId,
      destinationFolderRkey: ledger.destinationFolderRkey,
      entries: ledger.entries,
    );
  }
}
