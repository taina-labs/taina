import 'package:okena_core/src/mirror/mirror_entry.dart';
import 'package:okena_core/src/mirror/mirror_ledger.dart';

/// An approximate, immutable summary of the entries in a [MirrorLedger].
///
/// Uploaded and skipped entries count as stored because both are represented
/// on the box. Suppressed entries are terminal but are not stored or pending.
final class MirrorSummary {
  factory MirrorSummary.fromLedger(MirrorLedger ledger) {
    var storedCount = 0;
    var suppressedCount = 0;
    var pendingCount = 0;
    var uploadingCount = 0;
    var failedCount = 0;
    var knownPendingBytes = 0.0;
    var hasPendingUnknownSize = false;

    for (final entry in ledger.entries.values) {
      if (entry.state == MirrorState.suppressed) {
        suppressedCount++;
        continue;
      }
      if (entry.isTerminal) {
        storedCount++;
        continue;
      }

      pendingCount++;
      if (entry.state == MirrorState.uploading) uploadingCount++;
      if (entry.state == MirrorState.failed) failedCount++;

      final size = entry.size;
      if (size == null) {
        hasPendingUnknownSize = true;
        continue;
      }

      final pendingFraction = entry.state == MirrorState.uploading
          ? 1 - entry.progress.clamp(0.0, 1.0).toDouble()
          : 1.0;
      knownPendingBytes += size * pendingFraction;
    }

    return MirrorSummary._(
      totalEntries: ledger.entries.length,
      storedCount: storedCount,
      suppressedCount: suppressedCount,
      pendingCount: pendingCount,
      uploadingCount: uploadingCount,
      failedCount: failedCount,
      knownPendingBytes: knownPendingBytes,
      hasPendingUnknownSize: hasPendingUnknownSize,
    );
  }

  const MirrorSummary._({
    required this.totalEntries,
    required this.storedCount,
    required this.suppressedCount,
    required this.pendingCount,
    required this.uploadingCount,
    required this.failedCount,
    required this.knownPendingBytes,
    required this.hasPendingUnknownSize,
  });

  final int totalEntries;
  final int storedCount;
  final int suppressedCount;
  final int pendingCount;
  final int uploadingCount;
  final int failedCount;

  /// Estimated bytes still pending for entries with a known size.
  ///
  /// Uploading entries account for their reported progress. This is an
  /// approximation, not a byte-accurate transfer measurement.
  final double knownPendingBytes;

  /// Whether at least one pending entry has no known size.
  ///
  /// When true, [knownPendingBytes] is only the sum for entries with known
  /// sizes and does not represent the complete pending amount.
  final bool hasPendingUnknownSize;
}
