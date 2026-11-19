import 'package:okena_core/src/mirror/mirror_asset.dart';
import 'package:okena_core/src/mirror/mirror_entry.dart';
import 'package:okena_core/src/mirror/mirror_ledger.dart';

/// A deterministic decision over the current library and the local ledger.
final class MirrorPlanResult {
  MirrorPlanResult({
    required Iterable<MirrorEntry> toHash,
    required Iterable<MirrorEntry> toUpload,
    required Iterable<MirrorEntry> toSkip,
    required Iterable<MirrorEntry> unchanged,
    required this.updatedLedger,
  }) : toHash = List.unmodifiable(toHash),
       toUpload = List.unmodifiable(toUpload),
       toSkip = List.unmodifiable(toSkip),
       unchanged = List.unmodifiable(unchanged);

  final List<MirrorEntry> toHash;
  final List<MirrorEntry> toUpload;
  final List<MirrorEntry> toSkip;
  final List<MirrorEntry> unchanged;
  final MirrorLedger updatedLedger;
}

/// Pure planning for a one-way camera-roll mirror.
final class MirrorPlan {
  const MirrorPlan._();

  static MirrorPlanResult plan(
    Iterable<MirrorAsset> assets,
    MirrorLedger ledger,
    Set<String> knownHashes, {
    DateTime? updatedAt,
  }) {
    final orderedAssets = _uniqueAssets(assets);
    final requeuedLedger = ledger.requeueInterrupted();
    final entries = Map<String, MirrorEntry>.of(requeuedLedger.entries);
    final toHash = <MirrorEntry>[];
    final toUpload = <MirrorEntry>[];
    final toSkip = <MirrorEntry>[];
    final unchanged = <MirrorEntry>[];

    for (final asset in orderedAssets) {
      final current = entries[asset.assetId];
      if (current == null ||
          current.modificationDate != asset.modificationDate) {
        final reset = MirrorEntry.fromAsset(asset, updatedAt: updatedAt);
        entries[reset.assetId] = reset;
        toHash.add(reset);
        continue;
      }

      if (current.isTerminal) {
        unchanged.add(current);
        continue;
      }

      if (current.state == MirrorState.uploading &&
          current.backgroundTaskId != null) {
        unchanged.add(current);
        continue;
      }

      final hash = current.sha256;
      if (hash != null && knownHashes.contains(hash)) {
        final skipped = current.copyWith(
          state: MirrorState.skipped,
          clearRkey: true,
          clearBackgroundTaskId: true,
          clearLastError: true,
          progress: 0,
          updatedAt: updatedAt ?? current.updatedAt,
        );
        entries[current.assetId] = skipped;
        toSkip.add(skipped);
        continue;
      }

      if (hash != null &&
          (current.state == MirrorState.queued ||
              current.state == MirrorState.hashed ||
              current.state == MirrorState.failed)) {
        if (current.state == MirrorState.hashed) {
          final queued = current.copyWith(
            state: MirrorState.queued,
            clearRkey: true,
            clearBackgroundTaskId: true,
            clearLastError: true,
            progress: 0,
            updatedAt: updatedAt ?? current.updatedAt,
          );
          entries[current.assetId] = queued;
          toUpload.add(queued);
        } else {
          toUpload.add(current);
        }
        continue;
      }

      toHash.add(current);
    }

    return MirrorPlanResult(
      toHash: toHash,
      toUpload: toUpload,
      toSkip: toSkip,
      unchanged: unchanged,
      updatedLedger: MirrorLedger(
        ownerId: ledger.ownerId,
        destinationFolderRkey: ledger.destinationFolderRkey,
        entries: entries,
      ),
    );
  }
}

List<MirrorAsset> _uniqueAssets(Iterable<MirrorAsset> assets) {
  final ordered = assets.toList()
    ..sort((a, b) {
      final byId = a.assetId.compareTo(b.assetId);
      if (byId != 0) return byId;
      final byDate = b.modificationDate.compareTo(a.modificationDate);
      if (byDate != 0) return byDate;
      final byFilename = a.filename.compareTo(b.filename);
      if (byFilename != 0) return byFilename;
      final byMime = a.mime.compareTo(b.mime);
      if (byMime != 0) return byMime;
      final bySize = (a.size ?? -1).compareTo(b.size ?? -1);
      if (bySize != 0) return bySize;
      return (a.takenAt?.toIso8601String() ?? '').compareTo(
        b.takenAt?.toIso8601String() ?? '',
      );
    });

  final seen = <String>{};
  return List.unmodifiable([
    for (final asset in ordered)
      if (seen.add(asset.assetId)) asset,
  ]);
}
