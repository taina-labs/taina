import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

final _modifiedAt = DateTime.utc(2026, 10, 14, 8);

MirrorEntry _entry({
  required String assetId,
  int? size = 120,
  String? sha256,
  MirrorState state = MirrorState.newAsset,
  double progress = 0,
}) => MirrorEntry(
  assetId: assetId,
  modificationDate: _modifiedAt,
  filename: '$assetId.jpg',
  mime: 'image/jpeg',
  size: size,
  takenAt: null,
  sha256: sha256,
  localPath: null,
  state: state,
  rkey: null,
  backgroundTaskId: null,
  attempts: 0,
  lastError: null,
  progress: progress,
  updatedAt: _modifiedAt,
);

MirrorLedger _ledger(Iterable<MirrorEntry> entries) => MirrorLedger(
  ownerId: 'owner-a',
  entries: {for (final entry in entries) entry.assetId: entry},
);

void main() {
  group('MirrorSummary', () {
    test('summarizes an empty ledger', () {
      final summary = MirrorSummary.fromLedger(_ledger([]));

      expect(summary.totalEntries, 0);
      expect(summary.storedCount, 0);
      expect(summary.suppressedCount, 0);
      expect(summary.pendingCount, 0);
      expect(summary.uploadingCount, 0);
      expect(summary.failedCount, 0);
      expect(summary.knownPendingBytes, 0);
      expect(summary.hasPendingUnknownSize, isFalse);
    });

    test(
      'counts live skips as stored and suppression separately from pending',
      () {
        final summary = MirrorSummary.fromLedger(
          _ledger([
            _entry(assetId: 'uploaded', state: MirrorState.uploaded),
            _entry(assetId: 'skipped', state: MirrorState.skipped),
            _entry(assetId: 'suppressed', state: MirrorState.suppressed),
            _entry(assetId: 'new', state: MirrorState.newAsset),
            _entry(assetId: 'hashed', state: MirrorState.hashed),
            _entry(assetId: 'queued', state: MirrorState.queued),
            _entry(assetId: 'uploading', state: MirrorState.uploading),
            _entry(assetId: 'failed', state: MirrorState.failed),
          ]),
        );

        expect(summary.totalEntries, 8);
        expect(summary.storedCount, 2);
        expect(summary.suppressedCount, 1);
        expect(summary.pendingCount, 5);
        expect(summary.uploadingCount, 1);
        expect(summary.failedCount, 1);
      },
    );

    test(
      'reports unknown sizes without adding them as zero-sized certainty',
      () {
        final summary = MirrorSummary.fromLedger(
          _ledger([
            _entry(assetId: 'known', size: 80, state: MirrorState.queued),
            _entry(assetId: 'unknown', size: null, state: MirrorState.newAsset),
            _entry(
              assetId: 'terminal-unknown',
              size: null,
              state: MirrorState.uploaded,
            ),
          ]),
        );

        expect(summary.knownPendingBytes, 80);
        expect(summary.hasPendingUnknownSize, isTrue);
      },
    );

    test('suppressed entries do not add pending bytes or unknown sizes', () {
      final summary = MirrorSummary.fromLedger(
        _ledger([
          _entry(
            assetId: 'suppressed',
            size: null,
            state: MirrorState.suppressed,
          ),
        ]),
      );

      expect(summary.totalEntries, 1);
      expect(summary.storedCount, 0);
      expect(summary.suppressedCount, 1);
      expect(summary.pendingCount, 0);
      expect(summary.knownPendingBytes, 0);
      expect(summary.hasPendingUnknownSize, isFalse);
    });

    test('subtracts the reported sent fraction for uploading entries', () {
      final summary = MirrorSummary.fromLedger(
        _ledger([
          _entry(
            assetId: 'uploading',
            size: 100,
            state: MirrorState.uploading,
            progress: 0.25,
          ),
          _entry(assetId: 'queued', size: 40, state: MirrorState.queued),
        ]),
      );

      expect(summary.knownPendingBytes, 115);
    });

    test('failed entries remain pending with their full known size', () {
      final summary = MirrorSummary.fromLedger(
        _ledger([
          _entry(assetId: 'failed', size: 120, state: MirrorState.failed),
        ]),
      );

      expect(summary.pendingCount, 1);
      expect(summary.failedCount, 1);
      expect(summary.storedCount, 0);
      expect(summary.knownPendingBytes, 120);
    });

    test('counts duplicate content as separate ledger entries', () {
      final summary = MirrorSummary.fromLedger(
        _ledger([
          _entry(
            assetId: 'asset-a',
            sha256: 'same-content',
            size: 50,
            state: MirrorState.queued,
          ),
          _entry(
            assetId: 'asset-b',
            sha256: 'same-content',
            size: 50,
            state: MirrorState.queued,
          ),
        ]),
      );

      expect(summary.totalEntries, 2);
      expect(summary.pendingCount, 2);
      expect(summary.knownPendingBytes, 100);
    });
  });
}
