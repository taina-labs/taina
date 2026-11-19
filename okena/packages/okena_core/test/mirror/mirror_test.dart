import 'dart:convert';

import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

final modifiedAt = DateTime.utc(2026, 10, 14, 8);
final changedAt = DateTime.utc(2026, 10, 15, 9);
final operationAt = DateTime.utc(2026, 10, 15, 10);

MirrorAsset asset({
  String assetId = 'asset-a',
  DateTime? modificationDate,
  String filename = 'photo.jpg',
  String mime = 'image/jpeg',
  int? size = 120,
  DateTime? takenAt,
}) => MirrorAsset(
  assetId: assetId,
  modificationDate: modificationDate ?? modifiedAt,
  filename: filename,
  mime: mime,
  size: size,
  takenAt: takenAt,
);

MirrorEntry entry({
  String assetId = 'asset-a',
  DateTime? modificationDate,
  DateTime? takenAt,
  String? sha256,
  String? localPath,
  MirrorState state = MirrorState.newAsset,
  String? rkey,
  String? backgroundTaskId,
  int attempts = 0,
  String? lastError,
  double progress = 0,
  DateTime? updatedAt,
}) => MirrorEntry(
  assetId: assetId,
  modificationDate: modificationDate ?? modifiedAt,
  filename: '$assetId.jpg',
  mime: 'image/jpeg',
  size: 120,
  takenAt: takenAt,
  sha256: sha256,
  localPath: localPath,
  state: state,
  rkey: rkey,
  backgroundTaskId: backgroundTaskId,
  attempts: attempts,
  lastError: lastError,
  progress: progress,
  updatedAt: updatedAt ?? modifiedAt,
);

MirrorLedger ledger(Iterable<MirrorEntry> values) => MirrorLedger(
  ownerId: 'owner-a',
  entries: {for (final value in values) value.assetId: value},
);

FileRecord uploadedFile({
  String rkey = 'file-rkey',
  String sha256 =
      'aa11bb22cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66',
}) => FileRecord(
  rkey: rkey,
  cid: 'cid',
  blobCid: 'blob-cid',
  sha256: sha256,
  name: 'photo.jpg',
  mime: 'image/jpeg',
  size: 120,
  zona: Zona.casa,
  folder: null,
  takenAt: null,
  width: null,
  height: null,
  rendition: Rendition.none,
  deletedAt: null,
  createdAt: '2026-10-15T10:00:00Z',
  updatedAt: '2026-10-15T10:00:00Z',
);

void main() {
  group('MirrorPlan', () {
    test('a new asset is added for hashing', () {
      final result = MirrorPlan.plan([asset()], ledger([]), {});

      expect(result.toHash, hasLength(1));
      expect(result.toHash.single.state, MirrorState.newAsset);
      expect(result.toHash.single.assetId, 'asset-a');
      expect(result.toUpload, isEmpty);
      expect(result.updatedLedger.entries['asset-a'], result.toHash.single);
    });

    test(
      'a large new library is planned without mutating the original ledger',
      () {
        final original = ledger([]);
        final assets = [
          for (var index = 0; index < 10000; index++)
            asset(assetId: 'asset-${index.toString().padLeft(5, '0')}'),
        ];

        final result = MirrorPlan.plan(assets, original, {});

        expect(result.toHash, hasLength(10000));
        expect(result.updatedLedger.entries, hasLength(10000));
        expect(original.entries, isEmpty);
        expect(
          () => result.updatedLedger.entries.clear(),
          throwsUnsupportedError,
        );
      },
    );

    test('a modified asset resets old transfer state and is rehashed', () {
      final previous = entry(
        modificationDate: modifiedAt,
        sha256: 'old-hash',
        localPath: '/cache/old.jpg',
        state: MirrorState.failed,
        rkey: 'old-rkey',
        backgroundTaskId: 'old-task',
        attempts: 4,
        lastError: 'old failure',
        progress: 0.7,
      );
      final result = MirrorPlan.plan(
        [asset(modificationDate: changedAt, filename: 'new.jpg')],
        ledger([previous]),
        {},
      );

      final reset = result.toHash.single;
      expect(reset.modificationDate, changedAt);
      expect(reset.filename, 'new.jpg');
      expect(reset.state, MirrorState.newAsset);
      expect(reset.sha256, isNull);
      expect(reset.localPath, isNull);
      expect(reset.rkey, isNull);
      expect(reset.backgroundTaskId, isNull);
      expect(reset.lastError, isNull);
      expect(reset.progress, 0);
      expect(reset.attempts, 0);
    });

    test('terminal entries have no work on a later pass', () {
      final terminal = [
        entry(state: MirrorState.uploaded, sha256: 'no-longer-known'),
        entry(
          assetId: 'asset-b',
          state: MirrorState.skipped,
          sha256: 'also-no-longer-known',
        ),
        entry(
          assetId: 'asset-c',
          state: MirrorState.suppressed,
          sha256: 'suppressed-hash',
        ),
      ];
      final result = MirrorPlan.plan(
        [asset(), asset(assetId: 'asset-b'), asset(assetId: 'asset-c')],
        ledger(terminal),
        {},
      );

      expect(result.toHash, isEmpty);
      expect(result.toUpload, isEmpty);
      expect(result.toSkip, isEmpty);
      expect(result.unchanged, hasLength(3));
    });

    test(
      'known hashes skip queued records without clearing active task IDs',
      () {
        final queued = entry(
          assetId: 'asset-a',
          sha256: 'known-live',
          localPath: '/cache/a.jpg',
          state: MirrorState.queued,
        );
        final uploading = entry(
          assetId: 'asset-b',
          sha256: 'known-trash',
          localPath: '/cache/b.jpg',
          state: MirrorState.uploading,
          backgroundTaskId: 'task-b',
        );

        final result = MirrorPlan.plan(
          [asset(), asset(assetId: 'asset-b')],
          ledger([queued, uploading]),
          {'known-live', 'known-trash'},
        );

        expect(result.toSkip.map((item) => item.assetId), ['asset-a']);
        expect(result.toHash, isEmpty);
        expect(result.toUpload, isEmpty);
        expect(result.unchanged.map((item) => item.assetId), ['asset-b']);
        expect(
          result.updatedLedger.entries['asset-a']!.state,
          MirrorState.skipped,
        );
        expect(
          result.updatedLedger.entries['asset-b']!.state,
          MirrorState.uploading,
        );
        expect(
          result.updatedLedger.entries['asset-b']!.backgroundTaskId,
          'task-b',
        );
      },
    );

    test('an active background task waits, an orphaned task is requeued', () {
      final active = entry(
        assetId: 'asset-a',
        sha256: 'active-hash',
        state: MirrorState.uploading,
        backgroundTaskId: 'platform-task',
      );
      final orphaned = entry(
        assetId: 'asset-b',
        sha256: 'orphan-hash',
        state: MirrorState.uploading,
      );
      final initial = ledger([active, orphaned]);

      final result = MirrorPlan.plan(
        [asset(), asset(assetId: 'asset-b')],
        initial,
        {},
      );

      expect(result.unchanged.map((item) => item.assetId), ['asset-a']);
      expect(result.toUpload.map((item) => item.assetId), ['asset-b']);
      expect(
        result.updatedLedger.entries['asset-b']!.state,
        MirrorState.queued,
      );
      expect(result.updatedLedger.entries['asset-b']!.backgroundTaskId, isNull);
      expect(initial.entries['asset-b']!.state, MirrorState.uploading);
    });

    test(
      'unknown hashes are queued after hashing and known hashes are skipped',
      () {
        final initial = ledger([entry()]);
        final unknown = initial.classifyHashedAsset(
          assetId: 'asset-a',
          sha256: 'new-hash',
          localPath: '/cache/photo.jpg',
          knownHashes: {},
          updatedAt: operationAt,
        );
        final known = initial.classifyHashedAsset(
          assetId: 'asset-a',
          sha256: 'existing-hash',
          localPath: '/cache/photo.jpg',
          knownHashes: {'existing-hash'},
          updatedAt: operationAt,
        );

        expect(unknown.entries['asset-a']!.state, MirrorState.queued);
        expect(unknown.entries['asset-a']!.sha256, 'new-hash');
        expect(known.entries['asset-a']!.state, MirrorState.skipped);
        expect(known.entries['asset-a']!.sha256, 'existing-hash');
      },
    );
  });

  group('MirrorLedger transitions', () {
    test(
      'upload completion records hash and rkey, stale completion is ignored',
      () {
        final started = ledger([
          entry(
            modificationDate: changedAt,
            sha256: 'upload-hash',
            state: MirrorState.uploading,
            backgroundTaskId: 'task',
          ),
        ]);

        final completed = started.markUploaded(
          assetId: 'asset-a',
          modificationDate: changedAt,
          file: uploadedFile(),
          updatedAt: operationAt,
        );
        expect(completed.entries['asset-a']!.state, MirrorState.uploaded);
        expect(completed.entries['asset-a']!.rkey, 'file-rkey');
        expect(completed.entries['asset-a']!.sha256, uploadedFile().sha256);
        expect(completed.entries['asset-a']!.progress, 1);

        final newer = completed.upsert(
          MirrorEntry.fromAsset(
            asset(modificationDate: DateTime.utc(2026, 10, 16)),
          ),
        );
        final stale = newer.markUploaded(
          assetId: 'asset-a',
          modificationDate: changedAt,
          file: uploadedFile(rkey: 'stale-rkey'),
          updatedAt: operationAt,
        );
        expect(stale, newer);
        expect(stale.entries['asset-a']!.rkey, isNull);
        expect(stale.entries['asset-a']!.state, MirrorState.newAsset);
      },
    );

    test('failed attempts use bounded exponential retry delay', () {
      var value = ledger([entry()]);
      value = value.markFailed(
        assetId: 'asset-a',
        error: 'network',
        updatedAt: operationAt,
      );
      expect(value.entries['asset-a']!.attempts, 1);
      expect(value.entries['asset-a']!.lastError, 'network');
      expect(MirrorLedger.retryDelay(1), const Duration(seconds: 5));

      value = value.markFailed(
        assetId: 'asset-a',
        error: 'still offline',
        updatedAt: operationAt,
      );
      expect(value.entries['asset-a']!.attempts, 2);
      expect(MirrorLedger.retryDelay(2), const Duration(seconds: 10));
      expect(MirrorLedger.retryDelay(1000), const Duration(hours: 1));
    });

    test('progress and cancellation return work to the queue', () {
      var value = ledger([entry(sha256: 'hash', state: MirrorState.queued)]);
      value = value.markUploading(
        assetId: 'asset-a',
        backgroundTaskId: 'task',
        progress: 0.2,
        updatedAt: operationAt,
      );
      value = value.updateProgress(
        assetId: 'asset-a',
        progress: 0.6,
        updatedAt: operationAt,
      );
      expect(value.entries['asset-a']!.progress, 0.6);

      value = value.cancelUpload(assetId: 'asset-a', updatedAt: operationAt);
      expect(value.entries['asset-a']!.state, MirrorState.queued);
      expect(value.entries['asset-a']!.backgroundTaskId, isNull);
      expect(value.entries['asset-a']!.progress, 0);
      expect(value.nextUploads(), hasLength(1));
    });

    test('suppression is terminal and clears transfer state', () {
      final value = ledger([
        entry(
          sha256: 'suppressed-hash',
          state: MirrorState.uploading,
          rkey: 'stale-rkey',
          backgroundTaskId: 'native-task',
          progress: 0.7,
        ),
      ]);

      final suppressed = value.markSuppressed(
        assetId: 'asset-a',
        updatedAt: operationAt,
      );

      final suppressedEntry = suppressed.entries['asset-a']!;
      expect(suppressedEntry.state, MirrorState.suppressed);
      expect(suppressedEntry.isTerminal, isTrue);
      expect(suppressedEntry.rkey, isNull);
      expect(suppressedEntry.backgroundTaskId, isNull);
      expect(suppressedEntry.progress, 0);
    });

    test('nextUploads chooses one copy per hash in stable order', () {
      final value = ledger([
        entry(assetId: 'asset-z', sha256: 'shared', state: MirrorState.queued),
        entry(assetId: 'asset-a', sha256: 'shared', state: MirrorState.failed),
        entry(
          assetId: 'asset-b',
          sha256: 'busy',
          state: MirrorState.uploading,
          backgroundTaskId: 'busy-task',
        ),
        entry(assetId: 'asset-c', sha256: 'busy', state: MirrorState.queued),
        entry(assetId: 'asset-d', sha256: 'unique', state: MirrorState.queued),
      ]);

      expect(value.nextUploads().map((item) => item.assetId), [
        'asset-a',
        'asset-d',
      ]);
    });

    test('requeueInterrupted keeps entries with a task for reattachment', () {
      final value = ledger([
        entry(
          assetId: 'asset-a',
          sha256: 'a',
          state: MirrorState.uploading,
          backgroundTaskId: 'active-task',
        ),
        entry(assetId: 'asset-b', sha256: 'b', state: MirrorState.uploading),
      ]);

      final resumed = value.requeueInterrupted();
      expect(resumed.entries['asset-a']!.state, MirrorState.uploading);
      expect(resumed.entries['asset-a']!.backgroundTaskId, 'active-task');
      expect(resumed.entries['asset-b']!.state, MirrorState.queued);
    });
  });

  group('MirrorLedger persistence', () {
    test('the complete ledger round trips with stable state wire values', () {
      final value = MirrorLedger(
        ownerId: 'owner-a',
        destinationFolderRkey: 'folder-rkey',
        entries: {
          'asset-a': entry(
            state: MirrorState.newAsset,
            takenAt: DateTime.utc(2026, 6, 21, 21, 12),
          ),
          'asset-b': entry(
            assetId: 'asset-b',
            state: MirrorState.uploading,
            sha256: 'hash-b',
            localPath: '/cache/b.jpg',
            backgroundTaskId: 'task-b',
            attempts: 2,
            lastError: 'previous failure',
            progress: 0.45,
            updatedAt: operationAt,
          ),
          'asset-c': entry(
            assetId: 'asset-c',
            state: MirrorState.skipped,
            sha256: 'live-duplicate',
          ),
          'asset-d': entry(
            assetId: 'asset-d',
            state: MirrorState.suppressed,
            sha256: 'suppressed-hash',
          ),
        },
      );

      final decoded = MirrorLedger.decode(utf8.encode(value.encode()));

      expect(decoded.value, value);
      expect(value.toJson()['schema_version'], 1);
      expect((value.toJson()['entries']! as List).first['state'], 'new');
      final states = {
        for (final item in value.toJson()['entries']! as List)
          (item as Map<String, Object?>)['asset_id'] as String:
              item['state'] as String,
      };
      expect(states['asset-c'], 'skipped');
      expect(states['asset-d'], 'suppressed');
      expect(MirrorState.byWire['new'], MirrorState.newAsset);
      expect(MirrorState.byWire['skipped'], MirrorState.skipped);
      expect(MirrorState.byWire['suppressed'], MirrorState.suppressed);
      expect(decoded.value!.entries['asset-c']!.state, MirrorState.skipped);
      expect(decoded.value!.entries['asset-d']!.state, MirrorState.suppressed);
    });

    test(
      'malformed JSON and invalid field types fail at the decode boundary',
      () {
        expect(
          MirrorLedger.decode(utf8.encode('{')).error,
          isA<InvalidResponseError>(),
        );
        expect(
          MirrorLedger.decode(
            utf8.encode(
              '{"schema_version":1,"owner_id":4,'
              '"destination_folder_rkey":null,"entries":[]}',
            ),
          ).error,
          isA<InvalidResponseError>(),
        );
        expect(
          MirrorLedger.decode(
            utf8.encode(
              '{"schema_version":1,"owner_id":"owner",'
              '"destination_folder_rkey":null,"entries":[{"state":"future"}]}',
            ),
          ).error,
          isA<InvalidResponseError>(),
        );
      },
    );

    test(
      'the in-memory store loads, saves, clears, and keeps defensive copies',
      () async {
        final sourceEntries = {'asset-a': entry()};
        final source = MirrorLedger(ownerId: 'owner-a', entries: sourceEntries);
        final store = InMemoryMirrorStore();

        expect((await store.load()).value, isNull);
        expect((await store.save(source)).isSuccess, isTrue);
        sourceEntries.clear();
        expect((await store.load()).value, source);

        final loaded = (await store.load()).value!;
        expect(() => loaded.entries.clear(), throwsUnsupportedError);
        expect((await store.clear()).isSuccess, isTrue);
        expect((await store.load()).value, isNull);
      },
    );
  });
}
