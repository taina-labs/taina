import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/mirror_asset_hasher.dart';
import 'package:okena_app/src/mirror/mirror_engine.dart';
import 'package:okena_app/src/mirror/mirror_transition_store.dart';
import 'package:okena_app/src/mirror/mirror_transfer.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

final _now = DateTime.utc(2026, 11, 18, 12);
final _modified = DateTime.utc(2026, 11, 17, 10);
final _changed = DateTime.utc(2026, 11, 18, 10);
const _notFound = ApiError(
  code: 'not_found',
  status: 404,
  serverMessage: 'not found',
);
const _offline = NetworkError('offline');
const _taskFailure = InvalidResponseError('native start failed');

MirrorAsset _asset({String id = 'asset-a', DateTime? modified}) => MirrorAsset(
  assetId: id,
  modificationDate: modified ?? _modified,
  filename: '$id.jpg',
  mime: 'image/jpeg',
  size: 128,
  takenAt: null,
);

MirrorEntry _entry({
  String id = 'asset-a',
  DateTime? modified,
  String? hash = 'hash-asset-a',
  String? localPath,
  MirrorState state = MirrorState.queued,
  String? taskId,
  int attempts = 0,
  double progress = 0,
  DateTime? updatedAt,
}) => MirrorEntry(
  assetId: id,
  modificationDate: modified ?? _modified,
  filename: '$id.jpg',
  mime: 'image/jpeg',
  size: 128,
  takenAt: null,
  sha256: hash,
  localPath: localPath ?? '/stable/$id.jpg',
  state: state,
  rkey: null,
  backgroundTaskId: taskId,
  attempts: attempts,
  lastError: null,
  progress: progress,
  updatedAt: updatedAt ?? _now,
);

MirrorLedger _ledger(
  Iterable<MirrorEntry> entries, {
  String ownerId = 'owner-a',
  String? destinationFolderRkey,
}) => MirrorLedger(
  ownerId: ownerId,
  destinationFolderRkey: destinationFolderRkey,
  entries: {for (final entry in entries) entry.assetId: entry},
);

FileRecord _file({
  String rkey = 'file-a',
  String hash = 'hash-asset-a',
  String? deletedAt,
}) => FileRecord(
  rkey: rkey,
  cid: 'cid-$rkey',
  blobCid: 'blob-$rkey',
  sha256: hash,
  name: 'photo.jpg',
  mime: 'image/jpeg',
  size: 128,
  zona: Zona.casa,
  folder: null,
  takenAt: null,
  width: null,
  height: null,
  rendition: Rendition.none,
  deletedAt: deletedAt,
  createdAt: '2026-11-17T10:00:00Z',
  updatedAt: '2026-11-17T10:00:00Z',
);

Folder _folder({
  String rkey = 'folder-camera',
  String name = MirrorEngine.destinationFolderName,
  Zona zona = Zona.casa,
  String? parent,
  String? deletedAt,
}) => Folder(
  rkey: rkey,
  cid: 'cid-$rkey',
  name: name,
  zona: zona,
  folder: parent,
  deletedAt: deletedAt,
  createdAt: '2026-11-17T10:00:00Z',
  updatedAt: '2026-11-17T10:00:00Z',
);

void _expectAttemptId(MirrorEntry entry, String prefix) {
  final taskId = entry.backgroundTaskId ?? 'missing';
  expect(taskId, startsWith('$prefix-'));
  final nonce = taskId.split('-').last;
  expect(nonce, hasLength(32));
  expect(nonce, matches(RegExp(r'^[0-9a-f]{32}$')));
}

class _TestSession implements SessionGateway {
  _TestSession(this.api);

  @override
  final TainaApi api;

  int screenCalls = 0;

  @override
  ThumbnailStore get thumbnails => ThumbnailStore(api: api);

  @override
  Me? get identity => null;

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async {
    screenCalls++;
    return outcome;
  }
}

class _TestApi implements TainaApi {
  final List<(String?, int?, ManifestMode)> manifestRequests = [];
  final List<Page<FileRecord>> manifestPages = [
    Page(items: [], nextCursor: null),
  ];
  final Map<String, TainaResult<MirrorHashLookup>> lookupResults = {};
  final List<String> lookupHashes = [];
  final List<Folder> folders = [];
  final List<String> createdFolderNames = [];
  final Completer<void>? manifestGate;
  final Completer<void>? manifestEntered;

  _TestApi({this.manifestGate, this.manifestEntered});

  TainaResult<Page<FileRecord>>? manifestFailure;
  TainaResult<List<Folder>>? listFoldersFailure;
  TainaResult<Folder>? createFolderFailure;
  Folder? folderToCreate;

  @override
  Future<TainaResult<Page<FileRecord>>> manifest({
    String? after,
    int? limit,
    ManifestMode mode = ManifestMode.readable,
  }) async {
    manifestRequests.add((after, limit, mode));
    if (manifestEntered != null && !manifestEntered!.isCompleted) {
      manifestEntered!.complete();
    }
    if (manifestGate != null) await manifestGate!.future;
    final failure = manifestFailure;
    if (failure != null) return failure;
    final index = manifestRequests.length - 1;
    return Ok(
      manifestPages[index < manifestPages.length
          ? index
          : manifestPages.length - 1],
    );
  }

  @override
  Future<TainaResult<MirrorHashLookup>> hashLookup({
    required String sha256,
  }) async {
    lookupHashes.add(sha256);
    return lookupResults[sha256] ?? const Err<MirrorHashLookup>(_notFound);
  }

  @override
  Future<TainaResult<List<Folder>>> listFolders() async {
    final failure = listFoldersFailure;
    if (failure != null) return failure;
    return Ok(List.unmodifiable(folders));
  }

  @override
  Future<TainaResult<Folder>> createFolder({
    required String name,
    String? parentRkey,
  }) async {
    createdFolderNames.add(name);
    final failure = createFolderFailure;
    if (failure != null) return failure;
    final folder = folderToCreate ?? _folder(name: name, parent: parentRkey);
    return Ok(folder);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingStore implements MirrorTransitionStore {
  _RecordingStore([MirrorLedger? stored])
    : _inner = InMemoryMirrorStore(stored);

  final InMemoryMirrorStore _inner;
  final List<MirrorLedger> successfulSaves = [];
  final List<({List<String> changedAssetIds, List<String> removedAssetIds})>
  transitionCalls = [];
  int loadCalls = 0;
  int saveCalls = 0;
  int? failLoadAt;
  int? failSaveAt;
  StateError? throwLoadOnce;

  Future<MirrorLedger?> read() async => (await _inner.load()).value;

  Future<void> seed(MirrorLedger ledger) async {
    await _inner.save(ledger);
  }

  @override
  Future<TainaResult<MirrorLedger?>> load() async {
    loadCalls++;
    final thrown = throwLoadOnce;
    if (thrown != null) {
      throwLoadOnce = null;
      throw thrown;
    }
    if (loadCalls == failLoadAt) return const Err(_offline);
    return _inner.load();
  }

  @override
  Future<TainaResult<void>> save(MirrorLedger ledger) async {
    saveCalls++;
    if (saveCalls == failSaveAt) return const Err(_offline);
    successfulSaves.add(ledger);
    return _inner.save(ledger);
  }

  @override
  Future<TainaResult<void>> saveTransition(
    MirrorLedger ledger, {
    required Iterable<MirrorEntry> changedEntries,
    required Iterable<String> removedAssetIds,
  }) async {
    transitionCalls.add((
      changedAssetIds: changedEntries.map((entry) => entry.assetId).toList(),
      removedAssetIds: removedAssetIds.toList(),
    ));
    return save(ledger);
  }

  @override
  Future<TainaResult<void>> clear() => _inner.clear();
}

class _FakeHasher implements MirrorAssetHasher {
  final List<MirrorEntry> calls = [];
  final Map<String, TainaResult<MirrorHashResult>> answers = {};

  @override
  Future<TainaResult<MirrorHashResult>> hash(MirrorEntry entry) async {
    calls.add(entry);
    return answers[entry.assetId] ??
        Ok(
          MirrorHashResult(
            sha256: 'hash-${entry.assetId}',
            localPath: '/stable/${entry.assetId}.jpg',
          ),
        );
  }
}

class _FakeTransfer implements MirrorTransfer {
  final List<MirrorEntry> ensureCalls = [];
  final List<String> folders = [];
  final List<String> enqueuedTaskIds = [];
  final List<String> cancelCalls = [];
  final List<String> events = [];
  final Set<String> nativeTaskIds = {};
  final Map<String, TainaResult<void>> ensureAnswers = {};
  TainaResult<void>? cancelAnswer;
  Future<void> Function(String taskId)? onCancel;

  @override
  Future<TainaResult<void>> ensureStarted({
    required MirrorEntry entry,
    required String folderRkey,
  }) async {
    ensureCalls.add(entry);
    folders.add(folderRkey);
    final taskId = entry.backgroundTaskId;
    if (taskId == null) {
      return const Err(InvalidResponseError('transfer task id is missing'));
    }
    events.add('ensure:$taskId');
    final answer = ensureAnswers[entry.assetId];
    if (answer != null && answer.error is MirrorTransferRejected) {
      return answer;
    }
    if (nativeTaskIds.add(taskId)) enqueuedTaskIds.add(taskId);
    return answer ?? const Ok<void>(null);
  }

  @override
  Future<TainaResult<void>> cancel(String backgroundTaskId) async {
    cancelCalls.add(backgroundTaskId);
    events.add('cancel:$backgroundTaskId');
    await onCancel?.call(backgroundTaskId);
    final answer = cancelAnswer ?? const Ok<void>(null);
    if (answer.isSuccess) nativeTaskIds.remove(backgroundTaskId);
    return answer;
  }
}

class _Fixture {
  _Fixture({
    MirrorLedger? stored,
    DateTime Function()? clock,
    _TestApi? api,
    _RecordingStore? store,
    math.Random? random,
    Duration progressBatchWindow = Duration.zero,
  }) : api = api ?? _TestApi(),
       store = store ?? _RecordingStore(stored),
       hasher = _FakeHasher(),
       transfer = _FakeTransfer(),
       random = random ?? math.Random(42) {
    session = _TestSession(this.api);
    engine = MirrorEngine(
      session: session,
      store: this.store,
      hasher: hasher,
      transfer: transfer,
      ownerId: 'owner-a',
      random: this.random,
      clock: clock ?? () => _now,
      progressBatchWindow: progressBatchWindow,
    );
  }

  final _TestApi api;
  final _RecordingStore store;
  final _FakeHasher hasher;
  final _FakeTransfer transfer;
  final math.Random random;
  late _TestSession session;
  late MirrorEngine engine;
}

void main() {
  group('MirrorTransferStartError', () {
    test('exposes cause messages and compares by subtype and cause', () {
      final rejected = MirrorTransferRejected(_offline);
      final uncertain = MirrorTransferUncertain(_offline);

      expect(rejected.message, _offline.message);
      expect(rejected.cause, _offline);
      expect(rejected, MirrorTransferRejected(_offline));
      expect(rejected.hashCode, MirrorTransferRejected(_offline).hashCode);
      expect(uncertain.message, _offline.message);
      expect(uncertain.cause, _offline);
      expect(uncertain, MirrorTransferUncertain(_offline));
      expect(uncertain.hashCode, MirrorTransferUncertain(_offline).hashCode);
      expect(rejected, isNot(uncertain));
    });
  });

  group('MirrorEngine reconciliation', () {
    test(
      'new asset hashes, queues, and persists uploading before enqueue',
      () async {
        final fixture = _Fixture();
        final result = await fixture.engine.reconcile([_asset()]);

        expect(result, isA<Ok<void>>());
        expect(fixture.hasher.calls, hasLength(1));
        expect(fixture.transfer.ensureCalls, hasLength(1));
        expect(
          fixture.transfer.ensureCalls.single.state,
          MirrorState.uploading,
        );
        expect(
          fixture.transfer.ensureCalls.single.localPath,
          '/stable/asset-a.jpg',
        );
        _expectAttemptId(
          fixture.transfer.ensureCalls.single,
          'mirror-owner-a-asset-a-${_modified.microsecondsSinceEpoch}',
        );
        expect(fixture.transfer.folders, ['folder-camera']);
        expect(
          fixture.store.successfulSaves.map(
            (ledger) => ledger.entries['asset-a']?.state,
          ),
          containsAllInOrder([
            MirrorState.newAsset,
            MirrorState.hashed,
            MirrorState.queued,
            MirrorState.uploading,
          ]),
        );
        expect(
          fixture.store.transitionCalls.map((call) => call.changedAssetIds),
          [
            ['asset-a'],
            ['asset-a'],
            ['asset-a'],
            <String>[],
            ['asset-a'],
          ],
        );
        expect(
          fixture.store.transitionCalls.map((call) => call.removedAssetIds),
          everyElement(isEmpty),
        );
        expect(
          fixture.store.transitionCalls,
          hasLength(fixture.store.saveCalls),
        );
        expect(
          (await fixture.store.read())!.destinationFolderRkey,
          'folder-camera',
        );
        expect(
          fixture.session.screenCalls,
          fixture.api.manifestRequests.length +
              fixture.api.lookupHashes.length +
              2,
        );
      },
    );

    test('a plain MirrorStore keeps the full-save fallback', () async {
      final api = _TestApi();
      final store = InMemoryMirrorStore();
      final engine = MirrorEngine(
        session: _TestSession(api),
        store: store,
        hasher: _FakeHasher(),
        transfer: _FakeTransfer(),
        ownerId: 'owner-a',
        random: math.Random(42),
        clock: () => _now,
        progressBatchWindow: Duration.zero,
      );

      final result = await engine.reconcile([_asset()]);

      expect(result.isSuccess, isTrue);
      expect(
        (await store.load()).value!.entries['asset-a']!.state,
        MirrorState.uploading,
      );
    });

    test('a terminal pass does not hash or transfer again', () async {
      final fixture = _Fixture(
        stored: _ledger([
          _entry(state: MirrorState.uploaded, hash: 'hash-asset-a'),
        ]),
      );

      final result = await fixture.engine.reconcile([_asset()]);

      expect(result, isA<Ok<void>>());
      expect(fixture.hasher.calls, isEmpty);
      expect(fixture.transfer.ensureCalls, isEmpty);
      expect(fixture.api.lookupHashes, isEmpty);
    });

    test(
      'a changed modification date resets the record and rehashes',
      () async {
        final fixture = _Fixture(
          stored: _ledger([
            _entry(
              state: MirrorState.uploaded,
              hash: 'old-hash',
              modified: _modified,
            ),
          ], destinationFolderRkey: 'saved-folder'),
        );

        await fixture.engine.reconcile([_asset(modified: _changed)]);

        expect(fixture.hasher.calls, hasLength(1));
        expect(fixture.hasher.calls.single.modificationDate, _changed);
        expect(fixture.transfer.ensureCalls, hasLength(1));
        _expectAttemptId(
          fixture.transfer.ensureCalls.single,
          'mirror-owner-a-asset-a-${_changed.microsecondsSinceEpoch}',
        );
        expect(fixture.api.createdFolderNames, isEmpty);
        expect(fixture.api.manifestRequests.length, 1);
      },
    );

    test('all mirror manifest pages are fetched and use limit 1000', () async {
      final fixture = _Fixture();
      fixture.api.manifestPages
        ..clear()
        ..addAll([
          Page(
            items: [_file(rkey: 'a', hash: 'hash-asset-a')],
            nextCursor: 'a',
          ),
          Page(
            items: [_file(rkey: 'b', hash: 'hash-asset-a', deletedAt: 'now')],
            nextCursor: null,
          ),
        ]);
      fixture.api.lookupResults['hash-asset-a'] = Ok(
        MirrorHashPresent(file: _file(hash: 'hash-asset-a')),
      );

      final result = await fixture.engine.reconcile([_asset()]);

      expect(result, isA<Ok<void>>());
      expect(fixture.api.manifestRequests, [
        (null, 1000, ManifestMode.mirror),
        ('a', 1000, ManifestMode.mirror),
      ]);
      expect(fixture.hasher.calls, hasLength(1));
      expect(fixture.api.lookupHashes, ['hash-asset-a']);
      expect(fixture.transfer.ensureCalls, isEmpty);
      expect(
        (await fixture.store.read())!.entries['asset-a']!.state,
        MirrorState.uploaded,
      );
    });

    test('present hash lookup records the exact server file', () async {
      final fixture = _Fixture();
      final remote = _file(rkey: 'remote-rkey', hash: 'hash-asset-a');
      fixture.api.lookupResults['hash-asset-a'] = Ok(
        MirrorHashPresent(file: remote),
      );

      await fixture.engine.reconcile([_asset()]);

      final entry = (await fixture.store.read())!.entries['asset-a']!;
      expect(entry.state, MirrorState.uploaded);
      expect(entry.rkey, 'remote-rkey');
      expect(fixture.transfer.ensureCalls, isEmpty);
    });

    test('suppressed hash lookup skips the asset', () async {
      final fixture = _Fixture();
      fixture.api.lookupResults['hash-asset-a'] = const Ok<MirrorHashLookup>(
        MirrorHashSuppressed(),
      );

      await fixture.engine.reconcile([_asset()]);

      expect(
        (await fixture.store.read())!.entries['asset-a']!.state,
        MirrorState.skipped,
      );
      expect(fixture.transfer.ensureCalls, isEmpty);
    });

    test(
      '404 queues newly hashed work, and API failures stop the pass',
      () async {
        final fixture = _Fixture();

        await fixture.engine.reconcile([_asset()]);

        expect(
          fixture.store.successfulSaves.map(
            (ledger) => ledger.entries['asset-a']?.state,
          ),
          contains(MirrorState.queued),
        );

        final apiFailure = _Fixture(
          api: _TestApi()..manifestFailure = const Err(_offline),
        );
        final failure = await apiFailure.engine.reconcile([_asset()]);
        expect(failure.error, _offline);
        expect(apiFailure.hasher.calls, isEmpty);
        expect(apiFailure.transfer.ensureCalls, isEmpty);
      },
    );

    test(
      'a persisted hash survives lookup failure and prevents rehashing',
      () async {
        final api = _TestApi()
          ..lookupResults['hash-asset-a'] = const Err(_offline);
        final fixture = _Fixture(api: api);

        final first = await fixture.engine.reconcile([_asset()]);
        expect(first.error, _offline);
        expect(
          (await fixture.store.read())!.entries['asset-a']!.state,
          MirrorState.hashed,
        );
        expect(fixture.hasher.calls, hasLength(1));

        api.lookupResults['hash-asset-a'] = Ok(
          MirrorHashPresent(file: _file(hash: 'hash-asset-a')),
        );
        final second = await fixture.engine.reconcile([_asset()]);

        expect(second, isA<Ok<void>>());
        expect(fixture.hasher.calls, hasLength(1));
        expect(fixture.transfer.ensureCalls, isEmpty);
        expect(
          (await fixture.store.read())!.entries['asset-a']!.state,
          MirrorState.uploaded,
        );
      },
    );

    test(
      'a committed upload with a lost response is not enqueued again',
      () async {
        final api = _TestApi()
          ..lookupResults['hash-asset-a'] = Ok(
            MirrorHashPresent(
              file: _file(rkey: 'committed-file', hash: 'hash-asset-a'),
            ),
          );
        final fixture = _Fixture(
          api: api,
          stored: _ledger([
            _entry(
              state: MirrorState.uploading,
              taskId: 'committed-native-task',
            ),
          ], destinationFolderRkey: 'saved-folder'),
        )..transfer.nativeTaskIds.add('committed-native-task');

        await fixture.engine.reconcile([_asset()]);

        expect(fixture.transfer.ensureCalls, isEmpty);
        expect(fixture.transfer.enqueuedTaskIds, isEmpty);
        final entry = (await fixture.store.read())!.entries['asset-a']!;
        expect(entry.state, MirrorState.uploaded);
        expect(entry.rkey, 'committed-file');
      },
    );

    test('an orphaned task is requeued with a deterministic task id', () async {
      final fixture = _Fixture(
        stored: _ledger([_entry(state: MirrorState.uploading, taskId: null)]),
      );

      await fixture.engine.reconcile([_asset()]);

      expect(fixture.hasher.calls, isEmpty);
      expect(fixture.transfer.ensureCalls, hasLength(1));
      _expectAttemptId(
        fixture.transfer.ensureCalls.single,
        'mirror-owner-a-asset-a-${_modified.microsecondsSinceEpoch}',
      );
    });

    test('an active task is reattached without changing its task id', () async {
      final fixture = _Fixture(
        stored: _ledger([
          _entry(state: MirrorState.uploading, taskId: 'existing-native-task'),
        ], destinationFolderRkey: 'saved-folder'),
      )..transfer.nativeTaskIds.add('existing-native-task');

      await fixture.engine.reconcile([_asset()]);

      expect(fixture.transfer.ensureCalls, hasLength(1));
      expect(
        fixture.transfer.ensureCalls.single.backgroundTaskId,
        'existing-native-task',
      );
      expect(fixture.transfer.enqueuedTaskIds, isEmpty);
    });

    test('a superseded active task is cancelled before the newest revision is planned', () async {
      final oldEntry = _entry(
        state: MirrorState.uploading,
        taskId: 'old-native-task',
        hash: 'old-hash',
        localPath: '/persisted/old.jpg',
        progress: 0.7,
      ).copyWith(lastError: 'old error');
      final fixture = _Fixture(
        stored: _ledger([oldEntry], destinationFolderRkey: 'saved-folder'),
      )..transfer.nativeTaskIds.add('old-native-task');
      MirrorEntry? intentAtCancel;
      fixture.transfer.onCancel = (_) async {
        intentAtCancel = (await fixture.store.read())!.entries['asset-a'];
      };

      final result = await fixture.engine.reconcile([
        _asset(modified: _changed),
        _asset(modified: _modified),
      ]);

      expect(result.isSuccess, isTrue);
      expect(fixture.transfer.cancelCalls, ['old-native-task']);
      expect(intentAtCancel?.state, MirrorState.queued);
      expect(intentAtCancel?.backgroundTaskId, 'old-native-task');
      expect(intentAtCancel?.modificationDate, _modified);
      expect(intentAtCancel?.sha256, 'old-hash');
      expect(intentAtCancel?.localPath, '/persisted/old.jpg');
      expect(intentAtCancel?.progress, 0);
      expect(intentAtCancel?.lastError, isNull);
      expect(fixture.hasher.calls, hasLength(1));
      expect(fixture.hasher.calls.single.modificationDate, _changed);
      expect(fixture.transfer.ensureCalls, hasLength(1));
      expect(fixture.transfer.ensureCalls.single.modificationDate, _changed);
      expect(
        fixture.transfer.events.indexOf('cancel:old-native-task'),
        lessThan(
          fixture.transfer.events.indexOf(
            'ensure:${fixture.transfer.ensureCalls.single.backgroundTaskId}',
          ),
        ),
      );
      final current = (await fixture.store.read())!.entries['asset-a']!;
      expect(current.modificationDate, _changed);
      expect(current.sha256, 'hash-asset-a');
      expect(current.localPath, '/stable/asset-a.jpg');
      expect(current.state, MirrorState.uploading);
      expect(current.backgroundTaskId, isNot('old-native-task'));
    });

    test('a local superseded-task cancel failure excludes it but continues independent work', () async {
      final fixture = _Fixture(
        stored: _ledger([
          _entry(
            id: 'asset-a',
            modified: _modified,
            state: MirrorState.uploading,
            taskId: 'old-native-task',
            hash: 'old-hash',
            localPath: '/persisted/old-a.jpg',
            progress: 0.7,
          ),
          _entry(id: 'asset-b', hash: 'independent-hash'),
        ], destinationFolderRkey: 'saved-folder'),
      )..transfer.cancelAnswer = const Err(_taskFailure);

      final result = await fixture.engine.reconcile([
        _asset(id: 'asset-a', modified: _changed),
        _asset(id: 'asset-b'),
      ]);

      expect(result.error, _taskFailure);
      expect(fixture.transfer.cancelCalls, ['old-native-task']);
      expect(fixture.api.manifestRequests, hasLength(1));
      expect(fixture.hasher.calls, isEmpty);
      expect(fixture.api.lookupHashes, ['independent-hash']);
      expect(fixture.transfer.ensureCalls.map((entry) => entry.assetId), [
        'asset-b',
      ]);
      final ledger = (await fixture.store.read())!;
      final pending = ledger.entries['asset-a']!;
      expect(pending.state, MirrorState.queued);
      expect(pending.modificationDate, _modified);
      expect(pending.backgroundTaskId, 'old-native-task');
      expect(pending.sha256, 'old-hash');
      expect(pending.localPath, '/persisted/old-a.jpg');
      expect(pending.progress, 0);
      expect(pending.lastError, isNull);
      expect(ledger.entries['asset-b']!.state, MirrorState.uploading);
    });

    test(
      'global superseded-task cancel failures stop before manifest and work',
      () async {
        final failures = <TainaError>[
          const NetworkError('offline'),
          const NotSignedInError(),
          const ApiError(
            code: 'unauthorized',
            status: 401,
            serverMessage: 'expired',
          ),
          const ApiError(
            code: 'forbidden',
            status: 403,
            serverMessage: 'forbidden',
          ),
          const ApiError(
            code: 'internal_error',
            status: 503,
            serverMessage: 'busy',
          ),
        ];

        for (final error in failures) {
          final fixture = _Fixture(
            stored: _ledger([
              _entry(state: MirrorState.uploading, taskId: 'old-native-task'),
              _entry(id: 'asset-b', hash: 'independent-hash'),
            ], destinationFolderRkey: 'saved-folder'),
          )..transfer.cancelAnswer = Err(error);

          final result = await fixture.engine.reconcile([
            _asset(modified: _changed),
            _asset(id: 'asset-b'),
          ]);

          expect(result.error, error);
          expect(fixture.api.manifestRequests, isEmpty);
          expect(fixture.hasher.calls, isEmpty);
          expect(fixture.transfer.ensureCalls, isEmpty);
          final ledger = (await fixture.store.read())!;
          expect(ledger.entries['asset-a']!.state, MirrorState.queued);
          expect(
            ledger.entries['asset-a']!.backgroundTaskId,
            'old-native-task',
          );
          expect(ledger.entries['asset-b']!.state, MirrorState.queued);
        }
      },
    );

    test(
      'failure to persist superseded cancellation intent stops before cancel',
      () async {
        final store = _RecordingStore(
          _ledger([
            _entry(state: MirrorState.uploading, taskId: 'old-native-task'),
          ], destinationFolderRkey: 'saved-folder'),
        )..failSaveAt = 1;
        final fixture = _Fixture(store: store);

        final result = await fixture.engine.reconcile([
          _asset(modified: _changed),
        ]);

        expect(result.error, _offline);
        expect(fixture.transfer.cancelCalls, isEmpty);
        expect(fixture.api.manifestRequests, isEmpty);
        expect(fixture.hasher.calls, isEmpty);
        expect(fixture.transfer.ensureCalls, isEmpty);
        final entry = (await store.read())!.entries['asset-a']!;
        expect(entry.state, MirrorState.uploading);
        expect(entry.backgroundTaskId, 'old-native-task');
      },
    );

    test(
      'failed uploads respect retry delay while queued uploads are immediate',
      () async {
        var now = _now;
        final fixture = _Fixture(
          stored: _ledger([
            _entry(
              state: MirrorState.failed,
              attempts: 1,
              updatedAt: _now.subtract(const Duration(seconds: 2)),
            ),
          ], destinationFolderRkey: 'saved-folder'),
          clock: () => now,
        );

        await fixture.engine.reconcile([_asset()]);
        expect(fixture.transfer.ensureCalls, isEmpty);

        now = _now.add(const Duration(seconds: 3));
        await fixture.engine.reconcile([_asset()]);
        expect(fixture.transfer.ensureCalls, hasLength(1));
      },
    );

    test(
      'retry after failure receives a new task ID and ignores stale callbacks',
      () async {
        var now = _now;
        final fixture = _Fixture(clock: () => now);

        await fixture.engine.reconcile([_asset()]);
        final firstTaskId =
            fixture.transfer.ensureCalls.single.backgroundTaskId ?? 'missing';
        await fixture.engine.fail(
          assetId: 'asset-a',
          backgroundTaskId: firstTaskId,
          error: _offline,
        );

        now = now.add(const Duration(seconds: 5));
        await fixture.engine.reconcile([_asset()]);
        final secondTaskId =
            fixture.transfer.ensureCalls.last.backgroundTaskId ?? 'missing';

        expect(secondTaskId, isNot(firstTaskId));
        await fixture.engine.updateProgress(
          assetId: 'asset-a',
          backgroundTaskId: secondTaskId,
          progress: 0.4,
        );
        final savesBeforeStaleCallbacks = fixture.store.saveCalls;
        await fixture.engine.fail(
          assetId: 'asset-a',
          backgroundTaskId: firstTaskId,
          error: _offline,
        );
        await fixture.engine.updateProgress(
          assetId: 'asset-a',
          backgroundTaskId: firstTaskId,
          progress: 0.9,
        );

        final entry = (await fixture.store.read())!.entries['asset-a']!;
        expect(entry.state, MirrorState.uploading);
        expect(entry.backgroundTaskId, secondTaskId);
        expect(entry.progress, 0.4);
        expect(entry.attempts, 1);
        expect(fixture.store.saveCalls, savesBeforeStaleCallbacks);
      },
    );

    test('cancel then reconcile starts a fresh attempt ID', () async {
      final fixture = _Fixture();

      await fixture.engine.reconcile([_asset()]);
      final firstTaskId =
          fixture.transfer.ensureCalls.single.backgroundTaskId ?? 'missing';
      await fixture.engine.cancel(assetId: 'asset-a');
      expect(
        (await fixture.store.read())!.entries['asset-a']!.backgroundTaskId,
        isNull,
      );

      await fixture.engine.reconcile([_asset()]);

      final secondTaskId =
          fixture.transfer.ensureCalls.last.backgroundTaskId ?? 'missing';
      expect(secondTaskId, isNot(firstTaskId));
      expect(fixture.transfer.cancelCalls, [firstTaskId]);
    });

    test('duplicate hashes are looked up once and start only once', () async {
      final fixture = _Fixture();
      fixture.hasher
        ..answers['asset-a'] = const Ok(
          MirrorHashResult(sha256: 'same-hash', localPath: '/stable/a.jpg'),
        )
        ..answers['asset-b'] = const Ok(
          MirrorHashResult(sha256: 'same-hash', localPath: '/stable/b.jpg'),
        );

      await fixture.engine.reconcile([_asset(), _asset(id: 'asset-b')]);

      expect(fixture.api.lookupHashes, ['same-hash']);
      expect(fixture.transfer.ensureCalls, hasLength(1));
      expect(fixture.transfer.ensureCalls.single.assetId, 'asset-a');
      expect(
        (await fixture.store.read())!.entries['asset-b']!.state,
        MirrorState.queued,
      );
    });

    test(
      'many distinct hashes each receive one deterministic lookup',
      () async {
        const count = 40;
        final ids = [
          for (var index = 0; index < count; index++)
            'asset-${index.toString().padLeft(2, '0')}',
        ];
        final hashes = [
          for (var index = 0; index < count; index++)
            'hash-${index.toString().padLeft(2, '0')}',
        ];
        final fixture = _Fixture(
          stored: _ledger([
            for (var index = 0; index < count; index++)
              _entry(
                id: ids[index],
                hash: hashes[index],
                state: MirrorState.failed,
                attempts: 1,
                updatedAt: _now,
              ),
          ], destinationFolderRkey: 'saved-folder'),
        );

        final result = await fixture.engine.reconcile([
          for (final id in ids) _asset(id: id),
        ]);

        expect(result.isSuccess, isTrue);
        expect(fixture.api.lookupHashes, hashes);
        expect(fixture.api.lookupHashes.toSet(), hasLength(count));
        expect(fixture.hasher.calls, isEmpty);
        expect(fixture.transfer.ensureCalls, isEmpty);
        final ledger = (await fixture.store.read())!;
        expect(
          ledger.entries.values.map((entry) => entry.state),
          everyElement(MirrorState.failed),
        );
      },
    );

    test('hash errors are saved and do not block independent assets', () async {
      final fixture = _Fixture();
      fixture.hasher.answers['asset-a'] = const Err(_offline);

      final result = await fixture.engine.reconcile([
        _asset(),
        _asset(id: 'asset-b'),
      ]);

      expect(result.error, _offline);
      expect(
        (await fixture.store.read())!.entries['asset-a']!.state,
        MirrorState.failed,
      );
      expect(
        (await fixture.store.read())!.entries['asset-b']!.state,
        MirrorState.uploading,
      );
      expect(fixture.transfer.ensureCalls.map((entry) => entry.assetId), [
        'asset-b',
      ]);
    });

    test(
      'folder reuse requires a live root casa folder; otherwise create casa',
      () async {
        final api = _TestApi()
          ..folders.addAll([
            _folder(rkey: 'public', zona: Zona.praca),
            _folder(rkey: 'nested', parent: 'parent'),
            _folder(rkey: 'deleted', deletedAt: 'yesterday'),
          ]);
        final fixture = _Fixture(api: api);

        await fixture.engine.reconcile([_asset()]);

        expect(api.createdFolderNames, [MirrorEngine.destinationFolderName]);
        expect(
          (await fixture.store.read())!.destinationFolderRkey,
          'folder-camera',
        );
        expect(fixture.transfer.folders, ['folder-camera']);
      },
    );

    test(
      'a matching root casa folder is reused and destination is persisted',
      () async {
        final api = _TestApi()..folders.add(_folder(rkey: 'existing-casa'));
        final fixture = _Fixture(api: api);

        await fixture.engine.reconcile([_asset()]);

        expect(api.createdFolderNames, isEmpty);
        expect(
          (await fixture.store.read())!.destinationFolderRkey,
          'existing-casa',
        );
        expect(fixture.transfer.folders, ['existing-casa']);
      },
    );

    test('a transfer error is persisted as failed and returned', () async {
      final fixture = _Fixture()
        ..transfer.ensureAnswers['asset-a'] = const Err(
          MirrorTransferRejected(_offline),
        );

      final result = await fixture.engine.reconcile([_asset()]);

      expect(result.error, isA<MirrorTransferRejected>());
      final entry = (await fixture.store.read())!.entries['asset-a']!;
      expect(entry.state, MirrorState.failed);
      expect(entry.backgroundTaskId, isNull);
      expect(entry.attempts, 1);
      expect(fixture.transfer.nativeTaskIds, isEmpty);
    });

    test(
      'uncertain initial start preserves its task ID for cancellation',
      () async {
        final fixture = _Fixture()
          ..transfer.ensureAnswers['asset-a'] = const Err(
            MirrorTransferUncertain(_offline),
          );

        final result = await fixture.engine.reconcile([_asset()]);

        expect(result.error, isA<MirrorTransferUncertain>());
        final entry = (await fixture.store.read())!.entries['asset-a']!;
        final taskId = entry.backgroundTaskId ?? 'missing';
        expect(entry.state, MirrorState.uploading);
        expect(fixture.transfer.nativeTaskIds, contains(taskId));

        final cancelled = await fixture.engine.cancel(assetId: 'asset-a');

        expect(cancelled.isSuccess, isTrue);
        expect(fixture.transfer.cancelCalls, [taskId]);
        expect(
          (await fixture.store.read())!.entries['asset-a']!.backgroundTaskId,
          isNull,
        );
      },
    );

    test(
      'uncertain and unclassified reattach errors keep active task IDs',
      () async {
        for (final error in <TainaError>[
          const MirrorTransferUncertain(_offline),
          _offline,
        ]) {
          final fixture = _Fixture(
            stored: _ledger([
              _entry(state: MirrorState.uploading, taskId: 'persisted-task'),
            ], destinationFolderRkey: 'saved-folder'),
          )..transfer.ensureAnswers['asset-a'] = Err(error);

          final result = await fixture.engine.reconcile([_asset()]);

          expect(result.error, error);
          final entry = (await fixture.store.read())!.entries['asset-a']!;
          expect(entry.state, MirrorState.uploading);
          expect(entry.backgroundTaskId, 'persisted-task');
        }
      },
    );

    test(
      'active uncertain start still starts independent queued work',
      () async {
        final fixture =
            _Fixture(
                stored: _ledger([
                  _entry(
                    id: 'asset-a',
                    hash: 'shared-hash',
                    state: MirrorState.uploading,
                    taskId: 'active-a',
                  ),
                  _entry(id: 'asset-b', hash: 'independent-hash'),
                  _entry(id: 'asset-c', hash: 'shared-hash'),
                ], destinationFolderRkey: 'saved-folder'),
              )
              ..transfer.ensureAnswers['asset-a'] = const Err(
                MirrorTransferUncertain(_taskFailure),
              );

        final result = await fixture.engine.reconcile([
          _asset(id: 'asset-a'),
          _asset(id: 'asset-b'),
          _asset(id: 'asset-c'),
        ]);

        expect(result.error, isA<MirrorTransferUncertain>());
        final ledger = (await fixture.store.read())!;
        expect(ledger.entries['asset-a']!.state, MirrorState.uploading);
        expect(ledger.entries['asset-a']!.backgroundTaskId, 'active-a');
        expect(ledger.entries['asset-b']!.state, MirrorState.uploading);
        expect(ledger.entries['asset-c']!.state, MirrorState.queued);
        expect(fixture.transfer.ensureCalls.map((entry) => entry.assetId), [
          'asset-a',
          'asset-b',
        ]);
      },
    );

    test(
      'active rejected start saves failure and starts independent work',
      () async {
        final fixture =
            _Fixture(
                stored: _ledger([
                  _entry(
                    id: 'asset-a',
                    hash: 'shared-hash',
                    state: MirrorState.uploading,
                    taskId: 'active-a',
                  ),
                  _entry(id: 'asset-b', hash: 'independent-hash'),
                  _entry(id: 'asset-c', hash: 'shared-hash'),
                ], destinationFolderRkey: 'saved-folder'),
              )
              ..transfer.ensureAnswers['asset-a'] = const Err(
                MirrorTransferRejected(_taskFailure),
              );

        final result = await fixture.engine.reconcile([
          _asset(id: 'asset-a'),
          _asset(id: 'asset-b'),
          _asset(id: 'asset-c'),
        ]);

        expect(result.error, isA<MirrorTransferRejected>());
        final ledger = (await fixture.store.read())!;
        expect(ledger.entries['asset-a']!.state, MirrorState.failed);
        expect(ledger.entries['asset-a']!.backgroundTaskId, isNull);
        expect(ledger.entries['asset-b']!.state, MirrorState.uploading);
        expect(ledger.entries['asset-c']!.state, MirrorState.queued);
        expect(fixture.transfer.ensureCalls.map((entry) => entry.assetId), [
          'asset-a',
          'asset-b',
        ]);
      },
    );

    test(
      'active rejection stops immediately when saving its failure fails',
      () async {
        final store = _RecordingStore(
          _ledger([
            _entry(
              id: 'asset-a',
              hash: 'shared-hash',
              state: MirrorState.uploading,
              taskId: 'active-a',
            ),
            _entry(id: 'asset-b', hash: 'independent-hash'),
          ], destinationFolderRkey: 'saved-folder'),
        )..failSaveAt = 2;
        final fixture = _Fixture(store: store)
          ..transfer.ensureAnswers['asset-a'] = const Err(
            MirrorTransferRejected(_offline),
          );

        final result = await fixture.engine.reconcile([
          _asset(id: 'asset-a'),
          _asset(id: 'asset-b'),
        ]);

        expect(result.error, _offline);
        expect(
          (await store.read())!.entries['asset-a']!.state,
          MirrorState.uploading,
        );
        expect(fixture.transfer.ensureCalls.map((entry) => entry.assetId), [
          'asset-a',
        ]);
      },
    );

    test(
      'global active start failures stop before queued candidates',
      () async {
        final failures = <TainaError>[
          const NetworkError('offline'),
          const MirrorTransferUncertain(NetworkError('wrapped network')),
          const MirrorTransferUncertain(NotSignedInError()),
          const MirrorTransferRejected(
            ApiError(
              code: 'unauthorized',
              status: 401,
              serverMessage: 'expired',
            ),
          ),
          const MirrorTransferUncertain(
            ApiError(
              code: 'forbidden',
              status: 403,
              serverMessage: 'forbidden',
            ),
          ),
          const MirrorTransferRejected(
            ApiError(
              code: 'internal_error',
              status: 503,
              serverMessage: 'busy',
            ),
          ),
        ];

        for (final error in failures) {
          final fixture = _Fixture(
            stored: _ledger([
              _entry(
                id: 'asset-a',
                state: MirrorState.uploading,
                taskId: 'active-a',
              ),
              _entry(id: 'asset-b', hash: 'independent-hash'),
            ], destinationFolderRkey: 'saved-folder'),
          )..transfer.ensureAnswers['asset-a'] = Err(error);

          final result = await fixture.engine.reconcile([
            _asset(id: 'asset-a'),
            _asset(id: 'asset-b'),
          ]);

          expect(result.error, error);
          expect(fixture.transfer.ensureCalls.map((entry) => entry.assetId), [
            'asset-a',
          ]);
          final ledger = (await fixture.store.read())!;
          if (error is MirrorTransferRejected) {
            expect(ledger.entries['asset-a']!.state, MirrorState.failed);
            expect(ledger.entries['asset-a']!.backgroundTaskId, isNull);
          } else {
            expect(ledger.entries['asset-a']!.state, MirrorState.uploading);
            expect(ledger.entries['asset-a']!.backgroundTaskId, 'active-a');
          }
          expect(ledger.entries['asset-b']!.state, MirrorState.queued);
        }
      },
    );

    test(
      'local new-candidate failures do not block independent candidates',
      () async {
        final errors = <MirrorTransferStartError>[
          const MirrorTransferRejected(_taskFailure),
          const MirrorTransferUncertain(_taskFailure),
        ];

        for (final error in errors) {
          final fixture = _Fixture()
            ..transfer.ensureAnswers['asset-a'] = Err(error);
          final result = await fixture.engine.reconcile([
            _asset(id: 'asset-a'),
            _asset(id: 'asset-b'),
          ]);

          expect(result.error, error);
          final ledger = (await fixture.store.read())!;
          expect(ledger.entries['asset-b']!.state, MirrorState.uploading);
          if (error is MirrorTransferRejected) {
            expect(ledger.entries['asset-a']!.state, MirrorState.failed);
            expect(ledger.entries['asset-a']!.backgroundTaskId, isNull);
          } else {
            expect(ledger.entries['asset-a']!.state, MirrorState.uploading);
            expect(ledger.entries['asset-a']!.backgroundTaskId, isNotNull);
          }
          expect(fixture.transfer.ensureCalls.map((entry) => entry.assetId), [
            'asset-a',
            'asset-b',
          ]);
        }
      },
    );

    test(
      'global new-candidate failure stops before independent candidate',
      () async {
        final fixture = _Fixture()
          ..transfer.ensureAnswers['asset-a'] = const Err(
            MirrorTransferUncertain(NetworkError('wrapped network')),
          );

        final result = await fixture.engine.reconcile([
          _asset(id: 'asset-a'),
          _asset(id: 'asset-b'),
        ]);

        expect(
          result.error,
          const MirrorTransferUncertain(NetworkError('wrapped network')),
        );
        expect(fixture.transfer.ensureCalls.map((entry) => entry.assetId), [
          'asset-a',
        ]);
        final ledger = (await fixture.store.read())!;
        expect(ledger.entries['asset-a']!.state, MirrorState.uploading);
        expect(ledger.entries['asset-a']!.backgroundTaskId, isNotNull);
        expect(ledger.entries['asset-b']!.state, MirrorState.queued);
      },
    );

    test('owner mismatch rejects the stored ledger', () async {
      final fixture = _Fixture(
        stored: _ledger([_entry()], ownerId: 'another-owner'),
      );

      final result = await fixture.engine.reconcile([_asset()]);

      expect(result.error, isA<InvalidResponseError>());
      expect(fixture.api.manifestRequests, isEmpty);
      expect(fixture.hasher.calls, isEmpty);
    });

    test(
      'store failures stop before work and keep the prior ledger recoverable',
      () async {
        final store = _RecordingStore()..failSaveAt = 1;
        final fixture = _Fixture(store: store);

        final result = await fixture.engine.reconcile([_asset()]);

        expect(result.error, _offline);
        expect(await store.read(), isNull);
        expect(fixture.hasher.calls, isEmpty);
        expect(fixture.transfer.ensureCalls, isEmpty);
      },
    );

    test('concurrent reconcile calls share one run', () async {
      final gate = Completer<void>();
      final api = _TestApi(manifestGate: gate);
      final fixture = _Fixture(api: api);

      final first = fixture.engine.reconcile([_asset()]);
      final second = fixture.engine.reconcile([_asset(id: 'other')]);
      expect(second, same(first));

      gate.complete();
      await first;
      expect(api.manifestRequests, hasLength(1));
      expect(fixture.hasher.calls.map((entry) => entry.assetId), ['asset-a']);
    });
  });

  group('MirrorEngine callbacks', () {
    test(
      'cancelling an upload without a task requeues the interrupted entry',
      () async {
        final fixture = _Fixture(
          stored: _ledger([
            _entry(state: MirrorState.uploading, taskId: null, progress: 0.6),
          ]),
        );

        final result = await fixture.engine.cancel(assetId: 'asset-a');

        expect(result.isSuccess, isTrue);
        final entry = (await fixture.store.read())!.entries['asset-a']!;
        expect(entry.state, MirrorState.queued);
        expect(entry.backgroundTaskId, isNull);
        expect(entry.progress, 0);
        expect(fixture.transfer.cancelCalls, isEmpty);
        expect(fixture.store.saveCalls, 1);
      },
    );

    test('progress, cancellation, completion, and stale completion use core transitions', () async {
      final initial = _ledger([
        _entry(
          state: MirrorState.uploading,
          taskId: 'native-task',
          hash: 'hash-asset-a',
        ),
      ], destinationFolderRkey: 'saved-folder');
      final fixture = _Fixture(stored: initial)
        ..transfer.nativeTaskIds.add('native-task');
      MirrorEntry? pendingAtNativeCancel;
      fixture.transfer.onCancel = (_) async {
        pendingAtNativeCancel =
            (await fixture.store.read())!.entries['asset-a'];
      };

      expect(
        (await fixture.engine.updateProgress(
          assetId: 'asset-a',
          backgroundTaskId: 'native-task',
          progress: 0.6,
        )).isSuccess,
        isTrue,
      );
      expect((await fixture.store.read())!.entries['asset-a']!.progress, 0.6);
      expect(
        (await fixture.engine.cancel(assetId: 'asset-a')).isSuccess,
        isTrue,
      );
      expect(fixture.transfer.cancelCalls, ['native-task']);
      expect(
        (await fixture.store.read())!.entries['asset-a']!.state,
        MirrorState.queued,
      );
      expect(pendingAtNativeCancel?.state, MirrorState.queued);
      expect(pendingAtNativeCancel?.backgroundTaskId, 'native-task');
      expect(
        (await fixture.store.read())!.entries['asset-a']!.backgroundTaskId,
        isNull,
      );

      final uploading = (await fixture.store.read())!.markUploading(
        assetId: 'asset-a',
        backgroundTaskId: 'second-task',
        progress: 0,
        updatedAt: _now,
      );
      await fixture.store.seed(uploading);
      expect(
        (await fixture.engine.complete(
          assetId: 'asset-a',
          modificationDate: _modified,
          file: _file(rkey: 'completed'),
        )).isSuccess,
        isTrue,
      );
      expect(
        (await fixture.store.read())!.entries['asset-a']!.rkey,
        'completed',
      );

      final newer = (await fixture.store.read())!.upsert(
        MirrorEntry.fromAsset(_asset(modified: _changed), updatedAt: _now),
      );
      await fixture.store.seed(newer);
      await fixture.engine.complete(
        assetId: 'asset-a',
        modificationDate: _modified,
        file: _file(rkey: 'stale'),
      );
      final stale = (await fixture.store.read())!.entries['asset-a']!;
      expect(stale.modificationDate, _changed);
      expect(stale.state, MirrorState.newAsset);
      expect(stale.rkey, isNull);
    });

    test(
      'native cancellation failure leaves a persisted pending intent',
      () async {
        final fixture = _Fixture(
          stored: _ledger([
            _entry(state: MirrorState.uploading, taskId: 'native-task'),
          ]),
        )..transfer.cancelAnswer = const Err(_offline);
        fixture.transfer.nativeTaskIds.add('native-task');

        final result = await fixture.engine.cancel(assetId: 'asset-a');

        expect(result.error, _offline);
        final entry = (await fixture.store.read())!.entries['asset-a']!;
        expect(entry.state, MirrorState.queued);
        expect(entry.backgroundTaskId, 'native-task');
        expect(entry.progress, 0);
        expect(fixture.store.saveCalls, 1);

        final reconcile = await fixture.engine.reconcile([_asset()]);
        expect(reconcile.error, _offline);
        expect(fixture.api.manifestRequests, isEmpty);
        expect(fixture.transfer.ensureCalls, isEmpty);
        final stillPending = (await fixture.store.read())!.entries['asset-a']!;
        expect(stillPending.state, MirrorState.queued);
        expect(stillPending.backgroundTaskId, 'native-task');
      },
    );

    test(
      'local pending cancel failure does not block independent work',
      () async {
        final fixture = _Fixture(
          stored: _ledger([
            _entry(
              id: 'asset-a',
              hash: 'pending-hash',
              state: MirrorState.queued,
              taskId: 'pending-task',
            ),
            _entry(id: 'asset-b', hash: 'independent-hash'),
          ], destinationFolderRkey: 'saved-folder'),
        )..transfer.cancelAnswer = const Err(_taskFailure);

        final result = await fixture.engine.reconcile([
          _asset(id: 'asset-a'),
          _asset(id: 'asset-b'),
        ]);

        expect(result.error, _taskFailure);
        expect(fixture.transfer.cancelCalls, ['pending-task']);
        expect(fixture.api.manifestRequests, hasLength(1));
        expect(fixture.api.lookupHashes, ['independent-hash']);
        expect(fixture.transfer.ensureCalls.map((entry) => entry.assetId), [
          'asset-b',
        ]);
        final ledger = (await fixture.store.read())!;
        expect(ledger.entries['asset-a']!.state, MirrorState.queued);
        expect(ledger.entries['asset-a']!.backgroundTaskId, 'pending-task');
        expect(ledger.entries['asset-b']!.state, MirrorState.uploading);
      },
    );

    test(
      'repeated cancel retries pending intent without rewriting it first',
      () async {
        final fixture = _Fixture(
          stored: _ledger([
            _entry(state: MirrorState.uploading, taskId: 'native-task'),
          ]),
        )..transfer.cancelAnswer = const Err(_offline);
        final observed = <MirrorEntry?>[];
        fixture.transfer.onCancel = (_) async {
          observed.add((await fixture.store.read())!.entries['asset-a']);
        };

        await fixture.engine.cancel(assetId: 'asset-a');
        fixture.transfer.cancelAnswer = const Ok<void>(null);
        final result = await fixture.engine.cancel(assetId: 'asset-a');

        expect(result.isSuccess, isTrue);
        expect(fixture.store.saveCalls, 2);
        expect(fixture.transfer.cancelCalls, ['native-task', 'native-task']);
        expect(observed.map((entry) => entry?.backgroundTaskId), [
          'native-task',
          'native-task',
        ]);
        expect(observed.map((entry) => entry?.state), [
          MirrorState.queued,
          MirrorState.queued,
        ]);
        expect(
          (await fixture.store.read())!.entries['asset-a']!.backgroundTaskId,
          isNull,
        );
      },
    );

    test(
      'restart resolves pending cancellation before starting a fresh task',
      () async {
        final fixture = _Fixture()..transfer.cancelAnswer = const Err(_offline);

        await fixture.engine.reconcile([_asset()]);
        final firstTaskId =
            fixture.transfer.ensureCalls.single.backgroundTaskId ?? 'missing';
        final failedCancel = await fixture.engine.cancel(assetId: 'asset-a');
        expect(failedCancel.error, _offline);

        final blockedReconcile = await fixture.engine.reconcile([_asset()]);
        expect(blockedReconcile.error, _offline);
        expect(fixture.transfer.ensureCalls, hasLength(1));

        fixture.transfer.cancelAnswer = const Ok<void>(null);
        final restarted = MirrorEngine(
          session: fixture.session,
          store: fixture.store,
          hasher: fixture.hasher,
          transfer: fixture.transfer,
          ownerId: 'owner-a',
          random: fixture.random,
          clock: () => _now,
        );
        final resumed = await restarted.reconcile([_asset()]);

        expect(resumed.isSuccess, isTrue);
        expect(fixture.transfer.cancelCalls, [
          firstTaskId,
          firstTaskId,
          firstTaskId,
        ]);
        expect(fixture.transfer.ensureCalls, hasLength(1));
        expect(fixture.transfer.events.last, 'cancel:$firstTaskId');
        final cancelled = (await fixture.store.read())!.entries['asset-a']!;
        expect(cancelled.state, MirrorState.queued);
        expect(cancelled.backgroundTaskId, isNull);

        await restarted.reconcile([_asset()]);
        expect(fixture.transfer.ensureCalls, hasLength(2));
        final secondTaskId =
            fixture.transfer.ensureCalls.last.backgroundTaskId ?? 'missing';
        expect(secondTaskId, isNot(firstTaskId));
        expect(fixture.transfer.events.last, 'ensure:$secondTaskId');
        expect(
          (await fixture.store.read())!.entries['asset-a']!.backgroundTaskId,
          secondTaskId,
        );
      },
    );

    test(
      'reconcile resolves pending cancellations in asset ID order',
      () async {
        final fixture = _Fixture(
          stored: _ledger([
            _entry(id: 'asset-z', state: MirrorState.queued, taskId: 'task-z'),
            _entry(id: 'asset-a', state: MirrorState.queued, taskId: 'task-a'),
          ]),
        );

        final result = await fixture.engine.reconcile(const []);

        expect(result.isSuccess, isTrue);
        expect(fixture.transfer.cancelCalls, ['task-a', 'task-z']);
        expect(fixture.transfer.ensureCalls, isEmpty);
        final ledger = (await fixture.store.read())!;
        expect(ledger.entries['asset-a']!.backgroundTaskId, isNull);
        expect(ledger.entries['asset-z']!.backgroundTaskId, isNull);
      },
    );

    test('failed final cancellation save is retried after restart', () async {
      final store = _RecordingStore(
        _ledger([
          _entry(state: MirrorState.uploading, taskId: 'native-task'),
        ], destinationFolderRkey: 'saved-folder'),
      )..failSaveAt = 2;
      final fixture = _Fixture(store: store)
        ..transfer.nativeTaskIds.add('native-task');

      final result = await fixture.engine.cancel(assetId: 'asset-a');

      expect(result.error, _offline);
      final pending = (await store.read())!.entries['asset-a']!;
      expect(pending.state, MirrorState.queued);
      expect(pending.backgroundTaskId, 'native-task');

      store.failSaveAt = null;
      final restarted = MirrorEngine(
        session: fixture.session,
        store: store,
        hasher: fixture.hasher,
        transfer: fixture.transfer,
        ownerId: 'owner-a',
        random: fixture.random,
        clock: () => _now,
      );
      await restarted.reconcile([_asset()]);

      expect(fixture.transfer.cancelCalls, ['native-task', 'native-task']);
      expect(
        (await store.read())!.entries['asset-a']!.backgroundTaskId,
        isNull,
      );
      expect(fixture.transfer.ensureCalls, isEmpty);
    });

    test('failure and progress callbacks apply to the current task', () async {
      final fixture = _Fixture(
        stored: _ledger([
          _entry(state: MirrorState.uploading, taskId: 'current-task'),
        ]),
      );

      await fixture.engine.updateProgress(
        assetId: 'asset-a',
        backgroundTaskId: 'current-task',
        progress: 0.5,
      );
      expect((await fixture.store.read())!.entries['asset-a']!.progress, 0.5);
      await fixture.engine.fail(
        assetId: 'asset-a',
        backgroundTaskId: 'current-task',
        error: _offline,
      );
      final entry = (await fixture.store.read())!.entries['asset-a']!;
      expect(entry.state, MirrorState.failed);
      expect(entry.attempts, 1);
      expect(entry.lastError, _offline.message);
    });

    test('stale failure and progress cannot mutate a newer task', () async {
      final fixture = _Fixture(
        stored: _ledger([
          _entry(
            state: MirrorState.uploading,
            taskId: 'new-task',
            attempts: 2,
          ).copyWith(progress: 0.3),
        ]),
      );

      final failure = await fixture.engine.fail(
        assetId: 'asset-a',
        backgroundTaskId: 'old-task',
        error: _offline,
      );
      final progress = await fixture.engine.updateProgress(
        assetId: 'asset-a',
        backgroundTaskId: 'old-task',
        progress: 0.9,
      );

      expect(failure, isA<Ok<void>>());
      expect(progress, isA<Ok<void>>());
      final entry = (await fixture.store.read())!.entries['asset-a']!;
      expect(entry.state, MirrorState.uploading);
      expect(entry.backgroundTaskId, 'new-task');
      expect(entry.progress, 0.3);
      expect(entry.attempts, 2);
      expect(fixture.store.saveCalls, 0);
    });

    test(
      'late events from a superseded revision cannot mutate its replacement',
      () async {
        final fixture = _Fixture(
          stored: _ledger([
            _entry(
              state: MirrorState.uploading,
              taskId: 'old-native-task',
              hash: 'old-hash',
              progress: 0.6,
            ),
          ], destinationFolderRkey: 'saved-folder'),
        );

        final reconciled = await fixture.engine.reconcile([
          _asset(modified: _changed),
        ]);
        expect(reconciled.isSuccess, isTrue);
        final newTaskId =
            fixture.transfer.ensureCalls.single.backgroundTaskId ?? 'missing';
        expect(newTaskId, isNot('old-native-task'));

        await fixture.engine.complete(
          assetId: 'asset-a',
          modificationDate: _modified,
          file: _file(rkey: 'late-old-file', hash: 'old-hash'),
        );
        await fixture.engine.fail(
          assetId: 'asset-a',
          backgroundTaskId: 'old-native-task',
          error: _offline,
        );
        await fixture.engine.updateProgress(
          assetId: 'asset-a',
          backgroundTaskId: 'old-native-task',
          progress: 0.9,
        );

        final entry = (await fixture.store.read())!.entries['asset-a']!;
        expect(entry.modificationDate, _changed);
        expect(entry.state, MirrorState.uploading);
        expect(entry.backgroundTaskId, newTaskId);
        expect(entry.sha256, 'hash-asset-a');
        expect(entry.rkey, isNull);
        expect(entry.progress, 0);
        expect(entry.attempts, 0);
      },
    );

    test(
      'progress bursts coalesce to one load and save per asset task',
      () async {
        final fixture = _Fixture(
          stored: _ledger([
            _entry(state: MirrorState.uploading, taskId: 'task-a'),
            _entry(
              id: 'asset-b',
              state: MirrorState.uploading,
              taskId: 'task-b',
            ),
          ]),
          progressBatchWindow: const Duration(milliseconds: 10),
        );
        final callsA = [
          for (var value = 0; value < 20; value++)
            fixture.engine.updateProgress(
              assetId: 'asset-a',
              backgroundTaskId: 'task-a',
              progress: (value + 1) / 20,
            ),
        ];
        final callsB = [
          for (var value = 0; value < 20; value++)
            fixture.engine.updateProgress(
              assetId: 'asset-b',
              backgroundTaskId: 'task-b',
              progress: (value + 1) / 20,
            ),
        ];

        final resultsA = await Future.wait(callsA);
        final resultsB = await Future.wait(callsB);

        expect(
          resultsA.every((result) => identical(result, resultsA.first)),
          isTrue,
        );
        expect(
          resultsB.every((result) => identical(result, resultsB.first)),
          isTrue,
        );
        expect(fixture.store.loadCalls, 2);
        expect(fixture.store.saveCalls, 2);
        final ledger = (await fixture.store.read())!;
        expect(ledger.entries['asset-a']!.progress, 1);
        expect(ledger.entries['asset-b']!.progress, 1);
      },
    );

    test(
      'completion does not wait for a progress timer or get regressed by it',
      () async {
        final fixture = _Fixture(
          stored: _ledger([
            _entry(state: MirrorState.uploading, taskId: 'native-task'),
          ]),
          progressBatchWindow: Duration.zero,
        );
        var progressCompleted = false;
        final pendingProgress = fixture.engine
            .updateProgress(
              assetId: 'asset-a',
              backgroundTaskId: 'native-task',
              progress: 0.7,
            )
            .then((result) {
              progressCompleted = true;
              return result;
            });

        final completion = await fixture.engine.complete(
          assetId: 'asset-a',
          modificationDate: _modified,
          file: _file(rkey: 'completed-before-progress-flush'),
        );

        expect(completion.isSuccess, isTrue);
        expect(progressCompleted, isFalse);
        expect(fixture.store.saveCalls, 1);

        final flushed = await pendingProgress;

        expect(flushed.isSuccess, isTrue);
        expect(fixture.store.loadCalls, 2);
        expect(fixture.store.saveCalls, 1);
        final entry = (await fixture.store.read())!.entries['asset-a']!;
        expect(entry.state, MirrorState.uploaded);
        expect(entry.rkey, 'completed-before-progress-flush');
        expect(entry.progress, 1);
      },
    );

    test('progress batch completes with storage errors', () async {
      final loadFailure = _Fixture(
        stored: _ledger([
          _entry(state: MirrorState.uploading, taskId: 'load-task'),
        ]),
        store: _RecordingStore(
          _ledger([_entry(state: MirrorState.uploading, taskId: 'load-task')]),
        )..failLoadAt = 1,
      );
      final failedLoad = await loadFailure.engine.updateProgress(
        assetId: 'asset-a',
        backgroundTaskId: 'load-task',
        progress: 0.4,
      );
      expect(failedLoad.error, _offline);
      expect(loadFailure.store.saveCalls, 0);

      final saveStore = _RecordingStore(
        _ledger([_entry(state: MirrorState.uploading, taskId: 'save-task')]),
      )..failSaveAt = 1;
      final saveFailure = _Fixture(store: saveStore);
      final failedSave = await saveFailure.engine.updateProgress(
        assetId: 'asset-a',
        backgroundTaskId: 'save-task',
        progress: 0.4,
      );
      expect(failedSave.error, _offline);
      expect(saveStore.loadCalls, 1);
      expect(saveStore.saveCalls, 1);
    });

    test('unexpected load errors reach every progress waiter and leave FIFO usable', () async {
      final thrown = StateError('store contract violation');
      final store = _RecordingStore(
        _ledger([_entry(state: MirrorState.uploading, taskId: 'batch-task')]),
      )..throwLoadOnce = thrown;
      final fixture = _Fixture(
        store: store,
        progressBatchWindow: const Duration(milliseconds: 10),
      );
      final first = fixture.engine.updateProgress(
        assetId: 'asset-a',
        backgroundTaskId: 'batch-task',
        progress: 0.3,
      );
      final second = fixture.engine.updateProgress(
        assetId: 'asset-a',
        backgroundTaskId: 'batch-task',
        progress: 0.8,
      );
      final firstError = expectLater(first, throwsA(same(thrown)));
      final secondError = expectLater(second, throwsA(same(thrown)));

      await Future.wait([firstError, secondError]);

      final next = await fixture.engine.updateProgress(
        assetId: 'asset-a',
        backgroundTaskId: 'batch-task',
        progress: 0.9,
      );

      expect(next.isSuccess, isTrue);
      expect(store.loadCalls, 2);
      expect(store.saveCalls, 1);
      expect((await store.read())!.entries['asset-a']!.progress, 0.9);
    });

    test('invalid native progress returns an error value', () async {
      final fixture = _Fixture(
        stored: _ledger([
          _entry(state: MirrorState.uploading, taskId: 'native-task'),
        ]),
      );

      final result = await fixture.engine.updateProgress(
        assetId: 'asset-a',
        backgroundTaskId: 'native-task',
        progress: double.nan,
      );

      expect(result.error, isA<InvalidResponseError>());
      expect(fixture.store.loadCalls, 0);
      expect(fixture.store.saveCalls, 0);
      expect((await fixture.store.read())!.entries['asset-a']!.progress, 0);
    });

    test(
      'completion waits for reconcile and cannot be regressed by its saves',
      () async {
        final gate = Completer<void>();
        final entered = Completer<void>();
        final api = _TestApi(manifestGate: gate, manifestEntered: entered);
        final fixture = _Fixture(api: api);

        final reconcile = fixture.engine.reconcile([_asset()]);
        await entered.future;
        expect(fixture.store.loadCalls, 1);

        final completion = fixture.engine.complete(
          assetId: 'asset-a',
          modificationDate: _modified,
          file: _file(rkey: 'native-completion'),
        );
        expect(fixture.store.loadCalls, 1);
        expect(fixture.store.successfulSaves, isEmpty);

        gate.complete();
        expect((await reconcile).isSuccess, isTrue);
        expect((await completion).isSuccess, isTrue);

        final ledger = (await fixture.store.read())!;
        expect(ledger.entries['asset-a']!.state, MirrorState.uploaded);
        expect(ledger.entries['asset-a']!.rkey, 'native-completion');
        expect(
          fixture.store.successfulSaves.last.entries['asset-a']!.state,
          MirrorState.uploaded,
        );
      },
    );
  });
}
