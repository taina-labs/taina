import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/background_mirror_transfer.dart';
import 'package:okena_app/src/mirror/mirror_asset_hasher.dart';
import 'package:okena_app/src/mirror/mirror_asset_materializer.dart';
import 'package:okena_app/src/mirror/mirror_engine.dart';
import 'package:okena_app/src/mirror/mirror_foreground.dart';
import 'package:okena_app/src/mirror/mirror_library.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_app/src/mirror/mirror_settings.dart';
import 'package:okena_app/src/mirror/mirror_transfer.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

final _now = DateTime.utc(2026, 11, 18, 12);
final _modified = DateTime.utc(2026, 11, 17, 10);
const _notFound = ApiError(
  code: 'not_found',
  status: 404,
  serverMessage: 'not found',
);
const _offline = NetworkError('offline');
const _quotaExceeded = ApiError(
  code: 'storage_quota_exceeded',
  status: 422,
  serverMessage: 'storage quota exceeded',
);

MirrorAsset _asset({String id = 'asset-a'}) => MirrorAsset(
  assetId: id,
  modificationDate: _modified,
  filename: '$id.jpg',
  mime: 'image/jpeg',
  size: 100,
  takenAt: null,
);

MirrorEntry _entry({
  required String id,
  required MirrorState state,
  String? path,
  String? taskId,
}) => MirrorEntry(
  assetId: id,
  modificationDate: _modified,
  filename: '$id.jpg',
  mime: 'image/jpeg',
  size: 100,
  takenAt: null,
  sha256: 'a' * 64,
  localPath: path,
  state: state,
  rkey: null,
  backgroundTaskId: taskId,
  attempts: 0,
  lastError: null,
  progress: 0,
  updatedAt: _now,
);

MirrorLedger _ledger(
  Iterable<MirrorEntry> entries, {
  required String ownerId,
}) => MirrorLedger(
  ownerId: ownerId,
  destinationFolderRkey: 'folder-camera',
  entries: {for (final entry in entries) entry.assetId: entry},
);

FileRecord _file() => FileRecord(
  rkey: 'file-a',
  cid: 'cid-file-a',
  blobCid: 'blob-file-a',
  sha256: 'a' * 64,
  name: 'asset-a.jpg',
  mime: 'image/jpeg',
  size: 100,
  zona: Zona.casa,
  folder: 'folder-camera',
  takenAt: null,
  width: null,
  height: null,
  rendition: Rendition.none,
  deletedAt: null,
  createdAt: '2026-11-17T10:00:00Z',
  updatedAt: '2026-11-17T10:00:00Z',
);

Me _identity({String tekoaId = 'tekoa-a', String avaId = 'ava-a'}) => Me(
  ava: Ava(
    publicId: avaId,
    username: avaId,
    displayName: null,
    papel: Papel.morador,
    activatedAt: null,
    deactivatedAt: null,
    createdAt: '2026-01-01T00:00:00Z',
  ),
  tekoa: Tekoa(
    publicId: tekoaId,
    name: tekoaId,
    domain: 'example.test',
    storageQuotaBytes: null,
    storageUsedBytes: 0,
    createdAt: '2026-01-01T00:00:00Z',
  ),
  device: null,
);

class _FakeSession implements SessionGateway {
  _FakeSession(this.api);

  @override
  final TainaApi api;

  @override
  ThumbnailStore get thumbnails => ThumbnailStore(api: api);

  @override
  Me? get identity => null;

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async => outcome;
}

class _FakeApi implements TainaApi {
  int manifestCalls = 0;
  TainaResult<Page<FileRecord>>? manifestFailure;

  @override
  Future<TainaResult<Page<FileRecord>>> manifest({
    String? after,
    int? limit,
    ManifestMode mode = ManifestMode.readable,
  }) async {
    manifestCalls++;
    return manifestFailure ?? Ok(Page(items: const [], nextCursor: null));
  }

  @override
  Future<TainaResult<MirrorHashLookup>> hashLookup({
    required String sha256,
  }) async => const Err(_notFound);

  @override
  Future<TainaResult<List<Folder>>> listFolders() async => Ok([
    Folder(
      rkey: 'folder-camera',
      cid: 'cid-folder-camera',
      name: MirrorEngine.destinationFolderName,
      zona: Zona.casa,
      folder: null,
      deletedAt: null,
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    ),
  ]);

  @override
  Future<TainaResult<Folder>> createFolder({
    required String name,
    String? parentRkey,
  }) async => Ok(
    Folder(
      rkey: 'folder-camera',
      cid: 'cid-folder-camera',
      name: name,
      zona: Zona.casa,
      folder: parentRkey,
      deletedAt: null,
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransfer implements MirrorTransfer {
  final List<String> startedTaskIds = [];
  final List<String> cancelledTaskIds = [];
  Future<TainaResult<void>> Function(String backgroundTaskId)? cancelHandler;

  @override
  Future<TainaResult<void>> ensureStarted({
    required MirrorEntry entry,
    required String folderRkey,
  }) async {
    final taskId = entry.backgroundTaskId;
    if (taskId != null) startedTaskIds.add(taskId);
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<void>> cancel(String backgroundTaskId) async {
    cancelledTaskIds.add(backgroundTaskId);
    return cancelHandler == null
        ? const Ok<void>(null)
        : cancelHandler!(backgroundTaskId);
  }
}

class _FakeHasher implements MirrorAssetHasher {
  @override
  Future<TainaResult<MirrorHashResult>> hash(MirrorEntry entry) async => Ok(
    MirrorHashResult(
      sha256: 'a' * 64,
      localPath: '/support/taina_mirror/${entry.assetId}.jpg',
    ),
  );
}

class _FakeLibrary implements MirrorLibrary {
  _FakeLibrary({
    this.assets = const [],
    this.access = MirrorLibraryAccess.full,
  });

  final List<MirrorAsset> assets;
  MirrorLibraryAccess access;
  TainaResult<MirrorLibraryAccess>? accessFailure;
  int currentAccessCalls = 0;
  Completer<void>? accessEntered;
  Completer<void>? accessGate;
  int pageCalls = 0;
  TainaResult<MirrorAssetPage>? pageFailure;
  Object? pageThrow;
  Completer<void>? pageEntered;
  Completer<void>? pageGate;

  @override
  Future<TainaResult<MirrorLibraryAccess>> currentAccess() async {
    currentAccessCalls++;
    if (accessEntered case final entered? when !entered.isCompleted) {
      entered.complete();
    }
    final gate = accessGate;
    if (gate != null) await gate.future;
    return accessFailure ?? Ok(access);
  }

  @override
  Future<TainaResult<MirrorLibraryAccess>> requestAccess() async =>
      const Ok(MirrorLibraryAccess.full);

  @override
  Future<TainaResult<void>> openSettings() async => const Ok<void>(null);

  @override
  Future<TainaResult<MirrorAssetPage>> page({
    required int page,
    int size = 200,
  }) async {
    pageCalls++;
    if (pageEntered case final entered? when !entered.isCompleted) {
      entered.complete();
    }
    final thrown = pageThrow;
    if (thrown != null) throw thrown;
    final gate = pageGate;
    if (gate != null) await gate.future;
    return pageFailure ??
        Ok(
          MirrorAssetPage(
            assets: page == 0 ? assets : const [],
            hasMore: false,
          ),
        );
  }

  @override
  Future<TainaResult<void>> presentLimitedSelection() async =>
      const Ok<void>(null);
}

class _RecordingMaterializer implements MirrorAssetMaterializer {
  final List<Set<String>> retainedOnPrune = [];
  final Set<String> files = {};
  TainaResult<void>? pruneResult;
  Completer<void>? secondPrune;

  @override
  Future<TainaResult<MaterializedAsset>> materialize(MirrorEntry entry) async =>
      Ok(MaterializedAsset(path: entry.localPath ?? '/support/asset', size: 1));

  @override
  Future<TainaResult<void>> prune({required Set<String> retainedPaths}) async {
    retainedOnPrune.add(Set.unmodifiable(retainedPaths));
    files.removeWhere((path) => !retainedPaths.contains(path));
    final completer = secondPrune;
    if (retainedOnPrune.length == 2 &&
        completer != null &&
        !completer.isCompleted) {
      completer.complete();
    }
    return pruneResult ?? const Ok<void>(null);
  }
}

class _WatchingStore implements MirrorStore {
  _WatchingStore([MirrorLedger? initial])
    : _inner = InMemoryMirrorStore(initial);

  final InMemoryMirrorStore _inner;
  final Completer<void> uploaded = Completer<void>();

  @override
  Future<TainaResult<MirrorLedger?>> load() => _inner.load();

  @override
  Future<TainaResult<void>> save(MirrorLedger ledger) async {
    final result = await _inner.save(ledger);
    if (ledger.entries.values.any(
      (entry) => entry.state == MirrorState.uploaded,
    )) {
      if (!uploaded.isCompleted) uploaded.complete();
    }
    return result;
  }

  @override
  Future<TainaResult<void>> clear() => _inner.clear();
}

class _FailingSaveStore implements MirrorStore {
  _FailingSaveStore([MirrorLedger? initial])
    : _inner = InMemoryMirrorStore(initial);

  final InMemoryMirrorStore _inner;
  bool failNextSave = false;
  final Completer<void> failedSave = Completer<void>();

  @override
  Future<TainaResult<MirrorLedger?>> load() => _inner.load();

  @override
  Future<TainaResult<void>> save(MirrorLedger ledger) {
    if (failNextSave) {
      failNextSave = false;
      if (!failedSave.isCompleted) failedSave.complete();
      return Future.value(const Err(_offline));
    }
    return _inner.save(ledger);
  }

  @override
  Future<TainaResult<void>> clear() => _inner.clear();
}

class _MadeOwner {
  const _MadeOwner({
    required this.owner,
    required this.store,
    required this.library,
    required this.materializer,
    required this.events,
    required this.disposeTransfer,
    required this.transfer,
  });

  final MirrorOwnerMirror owner;
  final MirrorStore store;
  final _FakeLibrary library;
  final _RecordingMaterializer materializer;
  final StreamController<MirrorTransferEvent> events;
  final Future<void> Function() disposeTransfer;
  final _FakeTransfer transfer;
}

_MadeOwner _makeOwner({
  required String ownerId,
  MirrorStore? store,
  _FakeLibrary? library,
  _RecordingMaterializer? materializer,
  Future<TainaResult<void>> Function()? startTransfer,
  Future<void> Function()? onDispose,
  StreamController<MirrorTransferEvent>? events,
  Stream<MirrorTransferEvent>? transferEventStream,
  _FakeApi? api,
  bool enabled = true,
  bool wifiOnly = true,
  Future<TainaResult<void>> Function(MirrorPreferences preferences)?
  persistPreferences,
}) {
  final selectedStore = store ?? InMemoryMirrorStore();
  final selectedLibrary = library ?? _FakeLibrary();
  final selectedMaterializer = materializer ?? _RecordingMaterializer();
  final selectedApi = api ?? _FakeApi();
  final selectedEvents =
      events ?? StreamController<MirrorTransferEvent>.broadcast(sync: true);
  final transfer = _FakeTransfer();
  final engine = MirrorEngine(
    session: _FakeSession(selectedApi),
    store: selectedStore,
    hasher: _FakeHasher(),
    transfer: transfer,
    ownerId: ownerId,
    clock: () => _now,
  );
  Future<void> disposeTransfer() async {
    await onDispose?.call();
    await selectedEvents.close();
  }

  final owner = MirrorOwnerMirror(
    engine: engine,
    library: selectedLibrary,
    store: selectedStore,
    materializer: selectedMaterializer,
    transferEvents: transferEventStream ?? selectedEvents.stream,
    startTransfer: startTransfer ?? () async => const Ok<void>(null),
    disposeTransfer: disposeTransfer,
    enabled: enabled,
    wifiOnly: wifiOnly,
    persistPreferences: persistPreferences,
  );
  return _MadeOwner(
    owner: owner,
    store: selectedStore,
    library: selectedLibrary,
    materializer: selectedMaterializer,
    events: selectedEvents,
    disposeTransfer: disposeTransfer,
    transfer: transfer,
  );
}

class _IdentityChanges extends ChangeNotifier {
  _IdentityChanges(this.value);

  Me? value;

  void set(Me? next) {
    value = next;
    notifyListeners();
  }
}

class _ManualForeground implements MirrorForeground {
  // ignore: prefer_initializing_formals
  _ManualForeground({bool isForeground = true}) : _isForeground = isForeground;

  bool _isForeground;
  void Function(bool isForeground)? _onChanged;

  @override
  bool get isForeground => _isForeground;

  @override
  void attach(void Function(bool isForeground) onChanged) {
    _onChanged = onChanged;
  }

  void set(bool next) {
    if (_isForeground == next) return;
    _isForeground = next;
    _onChanged?.call(next);
  }

  @override
  void dispose() {
    _onChanged = null;
  }
}

final class _CancelFailingStream extends Stream<MirrorTransferEvent> {
  const _CancelFailingStream(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  StreamSubscription<MirrorTransferEvent> listen(
    void Function(MirrorTransferEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _CancelFailingSubscription(error, stackTrace);
}

final class _CancelFailingSubscription
    implements StreamSubscription<MirrorTransferEvent> {
  _CancelFailingSubscription(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  Future<void> cancel() => Future<void>.error(error, stackTrace);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MirrorOwnerMirror', () {
    test('cleans up after event cancellation fails and rethrows its original error', () async {
      final cancelError = StateError('event cancellation failed');
      final cancelStackTrace = StackTrace.current;
      final library = _FakeLibrary()
        ..accessEntered = Completer<void>()
        ..accessGate = Completer<void>();
      var disposeCalls = 0;
      final made = _makeOwner(
        ownerId: 'tekoa-a:ava-a',
        library: library,
        transferEventStream: _CancelFailingStream(
          cancelError,
          cancelStackTrace,
        ),
        onDispose: () async {
          disposeCalls++;
        },
      );
      var notifications = 0;
      made.owner.changes.addListener(() => notifications++);
      made.owner.activate();
      final reconciliation = made.owner.reconcile();
      await library.accessEntered!.future;

      Object? caughtError;
      StackTrace? caughtStackTrace;
      final disposing = made.owner.dispose();
      expect(disposeCalls, 0);
      library.accessGate!.complete();
      expect((await reconciliation).isFailure, isTrue);
      try {
        await disposing;
      } catch (error, stackTrace) {
        caughtError = error;
        caughtStackTrace = stackTrace;
      }

      expect(caughtError, same(cancelError));
      expect(caughtStackTrace, same(cancelStackTrace));
      expect(disposeCalls, 1);
      final notificationsAfterDispose = notifications;
      made.owner.setForeground(false);
      expect(notifications, notificationsAfterDispose);
    });

    test(
      'subscribes before start and applies a completion emitted during start',
      () async {
        final initial = _ledger([
          _entry(
            id: 'asset-a',
            state: MirrorState.uploading,
            path: '/support/retained.jpg',
            taskId: 'task-a',
          ),
        ], ownerId: 'tekoa-a:ava-a');
        final store = _WatchingStore(initial);
        final library = _FakeLibrary(assets: [_asset()]);
        final materializer = _RecordingMaterializer()
          ..secondPrune = Completer<void>();
        final events = StreamController<MirrorTransferEvent>.broadcast(
          sync: true,
        );
        final owner = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          store: store,
          library: library,
          materializer: materializer,
          events: events,
          startTransfer: () async {
            expect(events.hasListener, isTrue);
            events.add(
              MirrorTransferCompleted(
                assetId: 'asset-a',
                taskId: 'task-a',
                modificationDate: _modified,
                file: _file(),
              ),
            );
            return const Ok<void>(null);
          },
        ).owner;
        owner.activate();

        expect((await owner.reconcile()).isSuccess, isTrue);
        await store.uploaded.future;
        await materializer.secondPrune!.future;

        final persisted = (await store.load()).value!;
        expect(persisted.entries['asset-a']!.state, MirrorState.uploaded);
        expect(library.pageCalls, 1);
        expect(materializer.retainedOnPrune, hasLength(2));

        await owner.dispose();
      },
    );

    test(
      'does not follow completion with reconcile when ledger save fails',
      () async {
        final store = _FailingSaveStore(
          _ledger([
            _entry(
              id: 'asset-a',
              state: MirrorState.uploading,
              path: '/support/retained.jpg',
              taskId: 'task-a',
            ),
          ], ownerId: 'tekoa-a:ava-a'),
        );
        final library = _FakeLibrary(assets: [_asset()]);
        final materializer = _RecordingMaterializer();
        final events = StreamController<MirrorTransferEvent>.broadcast(
          sync: true,
        );
        final owner = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          store: store,
          library: library,
          materializer: materializer,
          events: events,
        ).owner;
        owner.activate();
        expect((await owner.reconcile()).isSuccess, isTrue);

        store.failNextSave = true;
        events.add(
          MirrorTransferCompleted(
            assetId: 'asset-a',
            taskId: 'task-a',
            modificationDate: _modified,
            file: _file(),
          ),
        );
        await store.failedSave.future;
        await _waitFor(() => owner.lastError == _offline);

        expect(library.pageCalls, 1);
        expect(materializer.retainedOnPrune, hasLength(1));
        await owner.dispose();
      },
    );

    test(
      'collects, reconciles and prunes only retained ledger paths',
      () async {
        final store = InMemoryMirrorStore(
          _ledger([
            _entry(
              id: 'uploading',
              state: MirrorState.uploading,
              path: '/saved/uploading',
              taskId: 'task-uploading',
            ),
            _entry(
              id: 'terminal',
              state: MirrorState.uploaded,
              path: '/saved/terminal',
            ),
            _entry(
              id: 'terminal-task',
              state: MirrorState.uploaded,
              path: '/saved/terminal-task',
              taskId: 'task-terminal',
            ),
            _entry(
              id: 'skipped',
              state: MirrorState.skipped,
              path: '/saved/skipped',
            ),
            _entry(
              id: 'failed',
              state: MirrorState.failed,
              path: '/old-root/taina_mirror/failed',
            ),
            _entry(id: 'missing-path', state: MirrorState.failed),
          ], ownerId: 'tekoa-a:ava-a'),
        );
        final library = _FakeLibrary(assets: [_asset(id: 'uploading')]);
        final materializer = _RecordingMaterializer();
        final made = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          store: store,
          library: library,
          materializer: materializer,
        );
        made.owner.activate();

        final result = await made.owner.reconcile();

        expect(result.isSuccess, isTrue);
        expect(library.pageCalls, 1);
        expect(materializer.retainedOnPrune.single, {
          '/saved/uploading',
          '/saved/terminal-task',
          '/old-root/taina_mirror/failed',
        });
        await made.owner.dispose();
      },
    );

    test(
      'skips pruning after library collection or engine reconciliation fails',
      () async {
        final collectionLibrary = _FakeLibrary()
          ..pageFailure = const Err(
            MirrorAssetReadError('library unavailable'),
          );
        final collectionMaterializer = _RecordingMaterializer();
        final collectionOwner = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          library: collectionLibrary,
          materializer: collectionMaterializer,
        ).owner;
        collectionOwner.activate();

        expect((await collectionOwner.reconcile()).isFailure, isTrue);
        expect(collectionMaterializer.retainedOnPrune, isEmpty);
        await collectionOwner.dispose();

        final failingApi = _FakeApi()..manifestFailure = const Err(_offline);
        final reconcileMaterializer = _RecordingMaterializer();
        final reconcileOwner = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          materializer: reconcileMaterializer,
          api: failingApi,
        ).owner;
        reconcileOwner.activate();

        expect((await reconcileOwner.reconcile()).isFailure, isTrue);
        expect(reconcileMaterializer.retainedOnPrune, isEmpty);
        await reconcileOwner.dispose();
      },
    );

    test('checks access before starting a refreshed library pass', () async {
      const accessFailure = MirrorAssetReadError('access state unavailable');
      final library = _FakeLibrary()..accessFailure = const Err(accessFailure);
      final api = _FakeApi();
      final materializer = _RecordingMaterializer();
      var startCalls = 0;
      final made = _makeOwner(
        ownerId: 'tekoa-a:ava-a',
        library: library,
        api: api,
        materializer: materializer,
        startTransfer: () async {
          startCalls++;
          return const Ok<void>(null);
        },
      );
      made.owner.activate();

      final result = await made.owner.reconcile(refreshLibrary: true);

      expect(result.error, accessFailure);
      expect(made.owner.lastError, accessFailure);
      expect(library.currentAccessCalls, 1);
      expect(library.pageCalls, 0);
      expect(startCalls, 0);
      expect(api.manifestCalls, 0);
      expect(materializer.retainedOnPrune, isEmpty);

      await made.owner.dispose();
    });

    test('does not enumerate when photo access is not determined', () async {
      final library = _FakeLibrary(access: MirrorLibraryAccess.notDetermined);
      final api = _FakeApi();
      final materializer = _RecordingMaterializer();
      var startCalls = 0;
      final made = _makeOwner(
        ownerId: 'tekoa-a:ava-a',
        library: library,
        api: api,
        materializer: materializer,
        startTransfer: () async {
          startCalls++;
          return const Ok<void>(null);
        },
      );
      made.owner.activate();

      final result = await made.owner.reconcile(refreshLibrary: true);

      expect(result.error, isA<MirrorAssetReadError>());
      expect(made.owner.lastError, isA<MirrorAssetReadError>());
      expect(library.currentAccessCalls, 1);
      expect(library.pageCalls, 0);
      expect(startCalls, 0);
      expect(api.manifestCalls, 0);
      expect(materializer.retainedOnPrune, isEmpty);

      await made.owner.dispose();
    });

    test('cached-assets reconciliation does not reread photo access', () async {
      final library = _FakeLibrary(assets: [_asset()]);
      final made = _makeOwner(ownerId: 'tekoa-a:ava-a', library: library);
      made.owner.activate();

      expect(
        (await made.owner.reconcile(refreshLibrary: true)).isSuccess,
        isTrue,
      );
      expect(library.currentAccessCalls, 1);

      expect(
        (await made.owner.reconcile(refreshLibrary: false)).isSuccess,
        isTrue,
      );

      expect(library.currentAccessCalls, 1);
      await made.owner.dispose();
    });

    test(
      'failed refresh invalidates the snapshot used after native completion',
      () async {
        final assets = <MirrorAsset>[
          _asset(id: 'asset-a'),
          _asset(id: 'asset-b'),
        ];
        final library = _FakeLibrary(assets: assets);
        final events = StreamController<MirrorTransferEvent>.broadcast(
          sync: true,
        );
        final made = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          library: library,
          events: events,
        );
        made.owner.activate();

        expect((await made.owner.reconcile()).isSuccess, isTrue);
        expect(library.currentAccessCalls, 1);
        expect(library.pageCalls, 1);

        library.pageFailure = const Err(
          MirrorAssetReadError('library unavailable'),
        );
        expect(
          (await made.owner.reconcile(refreshLibrary: true)).isFailure,
          isTrue,
        );
        expect(library.currentAccessCalls, 2);
        expect(library.pageCalls, 2);

        assets.removeWhere((asset) => asset.assetId == 'asset-b');
        library.pageFailure = null;
        events.add(
          MirrorTransferCompleted(
            assetId: 'asset-a',
            taskId: 'task-a',
            modificationDate: _modified,
            file: _file(),
          ),
        );
        await _waitFor(
          () => library.currentAccessCalls == 3 && library.pageCalls == 3,
        );

        expect(library.currentAccessCalls, 3);
        expect(library.pageCalls, 3);
        await made.owner.dispose();
      },
    );

    test(
      'native completion rechecks access after a refreshed snapshot is revoked',
      () async {
        for (final revokedAccess in <TainaResult<MirrorLibraryAccess>>[
          const Err(MirrorAssetReadError('access state unavailable')),
          const Ok(MirrorLibraryAccess.denied),
          const Ok(MirrorLibraryAccess.restricted),
          const Ok(MirrorLibraryAccess.notDetermined),
        ]) {
          final initial = _ledger([
            _entry(
              id: 'asset-a',
              state: MirrorState.uploading,
              path: '/support/asset-a.jpg',
              taskId: 'task-a',
            ),
          ], ownerId: 'tekoa-a:ava-a');
          final library = _FakeLibrary(assets: [_asset()]);
          final api = _FakeApi();
          final events = StreamController<MirrorTransferEvent>.broadcast(
            sync: true,
          );
          final made = _makeOwner(
            ownerId: 'tekoa-a:ava-a',
            store: InMemoryMirrorStore(initial),
            library: library,
            api: api,
            events: events,
          );
          made.owner.activate();

          expect((await made.owner.reconcile()).isSuccess, isTrue);
          expect(library.currentAccessCalls, 1);
          final manifestCalls = api.manifestCalls;
          final pruneCalls = made.materializer.retainedOnPrune.length;
          library.accessFailure = revokedAccess;

          final revoked = await made.owner.reconcile(refreshLibrary: true);
          expect(revoked.error, isA<MirrorAssetReadError>());
          expect(library.currentAccessCalls, 2);

          events.add(
            MirrorTransferCompleted(
              assetId: 'asset-a',
              taskId: 'task-a',
              modificationDate: _modified,
              file: _file(),
            ),
          );
          await _waitFor(() => library.currentAccessCalls == 3);

          expect(made.owner.lastError, isA<MirrorAssetReadError>());
          expect(library.pageCalls, 1);
          expect(api.manifestCalls, manifestCalls);
          expect(made.materializer.retainedOnPrune, hasLength(pruneCalls));
          await made.owner.dispose();
        }
      },
    );

    test(
      'disable during pending access stops before transfer startup',
      () async {
        final library = _FakeLibrary()
          ..accessEntered = Completer<void>()
          ..accessGate = Completer<void>();
        var startCalls = 0;
        final api = _FakeApi();
        final made = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          library: library,
          api: api,
          startTransfer: () async {
            startCalls++;
            return const Ok<void>(null);
          },
        );
        made.owner.activate();

        final reconciliation = made.owner.reconcile();
        await library.accessEntered!.future;
        final disabling = made.owner.setEnabled(false);
        expect(made.owner.enabled, isFalse);
        library.accessGate!.complete();

        expect((await reconciliation).isSuccess, isTrue);
        expect((await disabling).isSuccess, isTrue);
        expect(startCalls, 0);
        expect(library.pageCalls, 0);
        expect(api.manifestCalls, 0);
        expect(made.transfer.startedTaskIds, isEmpty);
        expect(made.materializer.retainedOnPrune, isEmpty);
        await made.owner.dispose();
      },
    );

    test(
      'records prune errors as housekeeping without failing reconciliation',
      () async {
        final materializer = _RecordingMaterializer()
          ..pruneResult = const Err(MirrorAssetReadError('prune failed'));
        final made = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          materializer: materializer,
        );
        made.owner.activate();

        final result = await made.owner.reconcile();

        expect(result.isSuccess, isTrue);
        expect(made.owner.lastError, isA<MirrorAssetReadError>());
        await made.owner.dispose();
      },
    );

    test(
      'coalesces foreground refreshes into one subsequent snapshot',
      () async {
        final library = _FakeLibrary(assets: [_asset()])
          ..pageEntered = Completer<void>()
          ..pageGate = Completer<void>();
        final materializer = _RecordingMaterializer();
        final owner = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          library: library,
          materializer: materializer,
        ).owner;
        owner.activate();

        final first = owner.reconcile();
        await library.pageEntered!.future;
        final concurrent = List.generate(20, (_) => owner.reconcile());
        expect(concurrent.every((future) => identical(first, future)), isTrue);
        library.pageGate!.complete();

        expect((await first).isSuccess, isTrue);
        expect(library.pageCalls, 2);
        expect(materializer.retainedOnPrune, hasLength(2));
        await owner.dispose();
      },
    );

    test(
      'propagates programmer errors and clears reconcile scheduling',
      () async {
        final library = _FakeLibrary()..pageThrow = StateError('unexpected');
        final owner = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          library: library,
        ).owner;
        owner.activate();

        await expectLater(owner.reconcile(), throwsA(isA<StateError>()));
        expect(owner.lastError, isNull);

        library.pageThrow = null;
        expect((await owner.reconcile()).isSuccess, isTrue);
        await owner.dispose();
      },
    );

    test('disabled reconcile is a quiet no-op', () async {
      var startCalls = 0;
      final api = _FakeApi();
      final made = _makeOwner(
        ownerId: 'tekoa-a:ava-a',
        enabled: false,
        api: api,
        startTransfer: () async {
          startCalls++;
          return const Ok<void>(null);
        },
      );
      made.owner.activate();

      expect((await made.owner.reconcile()).isSuccess, isTrue);
      expect(startCalls, 0);
      expect(made.library.pageCalls, 0);
      expect(api.manifestCalls, 0);
      expect(made.materializer.retainedOnPrune, isEmpty);

      await made.owner.dispose();
    });

    test(
      'disabled completion updates the ledger without follow-up work',
      () async {
        final store = _WatchingStore(
          _ledger([
            _entry(
              id: 'asset-a',
              state: MirrorState.uploading,
              path: '/support/retained.jpg',
              taskId: 'task-a',
            ),
          ], ownerId: 'tekoa-a:ava-a'),
        );
        final api = _FakeApi();
        var startCalls = 0;
        final made = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          enabled: false,
          store: store,
          api: api,
          startTransfer: () async {
            startCalls++;
            return const Ok<void>(null);
          },
        );
        made.owner.activate();

        made.events.add(
          MirrorTransferCompleted(
            assetId: 'asset-a',
            taskId: 'task-a',
            modificationDate: _modified,
            file: _file(),
          ),
        );
        await store.uploaded.future;

        expect(
          (await store.load()).value!.entries['asset-a']!.state,
          MirrorState.uploaded,
        );
        expect(startCalls, 0);
        expect(made.library.pageCalls, 0);
        expect(api.manifestCalls, 0);
        expect(made.materializer.retainedOnPrune, isEmpty);

        await made.owner.dispose();
      },
    );

    test(
      'pause stops a pending collection before scheduling new tasks',
      () async {
        final library = _FakeLibrary(assets: [_asset()])
          ..pageEntered = Completer<void>()
          ..pageGate = Completer<void>();
        final made = _makeOwner(ownerId: 'tekoa-a:ava-a', library: library);
        made.owner.activate();

        final reconciliation = made.owner.reconcile();
        await library.pageEntered!.future;
        final pausing = made.owner.setEnabled(false);
        expect(made.owner.enabled, isFalse);
        expect((await made.owner.reconcile()).isSuccess, isTrue);

        library.pageGate!.complete();
        expect((await reconciliation).isSuccess, isTrue);
        expect((await pausing).isSuccess, isTrue);

        expect(made.transfer.startedTaskIds, isEmpty);
        expect(made.transfer.cancelledTaskIds, isEmpty);
        expect((await made.store.load()).value, isNull);

        await made.owner.dispose();
      },
    );

    test(
      'failed cancellation retains task and path and pause retries all',
      () async {
        final initial = _ledger([
          _entry(
            id: 'asset-a',
            state: MirrorState.uploading,
            path: '/support/a.jpg',
            taskId: 'task-a',
          ),
          _entry(
            id: 'asset-b',
            state: MirrorState.uploading,
            path: '/support/b.jpg',
            taskId: 'task-b',
          ),
        ], ownerId: 'tekoa-a:ava-a');
        final made = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          store: InMemoryMirrorStore(initial),
        );
        var failFirst = true;
        made.transfer.cancelHandler = (taskId) async {
          if (taskId == 'task-a' && failFirst) {
            failFirst = false;
            return const Err(_offline);
          }
          return const Ok<void>(null);
        };
        made.owner.activate();

        final disabled = await made.owner.setEnabled(false);
        expect(disabled.error, _offline);
        expect(made.transfer.cancelledTaskIds, ['task-a', 'task-b']);

        final afterFailure = (await made.store.load()).value!;
        expect(afterFailure.entries['asset-a']!.state, MirrorState.queued);
        expect(afterFailure.entries['asset-a']!.backgroundTaskId, 'task-a');
        expect(afterFailure.entries['asset-a']!.localPath, '/support/a.jpg');
        expect(afterFailure.entries['asset-b']!.backgroundTaskId, isNull);

        expect((await made.owner.pause()).isSuccess, isTrue);
        expect(made.transfer.cancelledTaskIds, ['task-a', 'task-b', 'task-a']);
        final afterRetry = (await made.store.load()).value!;
        expect(afterRetry.entries['asset-a']!.backgroundTaskId, isNull);
        expect(afterRetry.entries['asset-a']!.localPath, '/support/a.jpg');

        await made.owner.dispose();
      },
    );

    test('disable still cancels when saving the preference fails', () async {
      const saveFailure = InvalidResponseError('settings unavailable');
      final initial = _ledger([
        _entry(
          id: 'asset-a',
          state: MirrorState.uploading,
          path: '/support/a.jpg',
          taskId: 'task-a',
        ),
      ], ownerId: 'tekoa-a:ava-a');
      final made = _makeOwner(
        ownerId: 'tekoa-a:ava-a',
        store: InMemoryMirrorStore(initial),
        persistPreferences: (_) async => const Err(saveFailure),
      );
      made.transfer.cancelHandler = (_) async => const Err(_offline);
      made.owner.activate();

      final result = await made.owner.setEnabled(false);

      expect(result.error, saveFailure);
      expect(made.owner.enabled, isFalse);
      expect(made.transfer.cancelledTaskIds, ['task-a']);
      final retained = (await made.store.load()).value!.entries['asset-a']!;
      expect(retained.backgroundTaskId, 'task-a');
      expect(retained.localPath, '/support/a.jpg');

      await made.owner.dispose();
    });

    test(
      'enable persists first and only activates after a successful save',
      () async {
        var failSave = true;
        final saved = <MirrorPreferences>[];
        var startCalls = 0;
        final made = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          enabled: false,
          wifiOnly: false,
          persistPreferences: (preferences) async {
            saved.add(preferences);
            if (failSave) return const Err(_offline);
            return const Ok<void>(null);
          },
          startTransfer: () async {
            startCalls++;
            return const Ok<void>(null);
          },
        );
        made.owner.activate();

        expect((await made.owner.setEnabled(true)).error, _offline);
        expect(made.owner.enabled, isFalse);
        expect(startCalls, 0);
        expect(made.library.pageCalls, 0);

        failSave = false;
        expect((await made.owner.setEnabled(true)).isSuccess, isTrue);
        await _waitFor(() => made.library.pageCalls == 1);
        expect(made.owner.enabled, isTrue);
        expect(saved, const [
          MirrorPreferences(enabled: true, wifiOnly: false),
          MirrorPreferences(enabled: true, wifiOnly: false),
        ]);
        expect(startCalls, 1);

        await made.owner.dispose();
      },
    );

    test('Wi-Fi preference persistence preserves enabled state', () async {
      final saved = <MirrorPreferences>[];
      final made = _makeOwner(
        ownerId: 'tekoa-a:ava-a',
        enabled: false,
        persistPreferences: (preferences) async {
          saved.add(preferences);
          return const Ok<void>(null);
        },
      );
      made.owner.activate();

      expect((await made.owner.setWifiOnly(false)).isSuccess, isTrue);
      expect(made.owner.wifiOnly, isFalse);
      expect(saved, const [MirrorPreferences(enabled: false, wifiOnly: false)]);

      await made.owner.dispose();
    });

    test('notifies listeners for activation, foreground, preferences, reconcile and progress', () async {
      final initial = _ledger([
        _entry(
          id: 'asset-a',
          state: MirrorState.uploading,
          path: '/support/asset-a.jpg',
          taskId: 'task-a',
        ),
      ], ownerId: 'tekoa-a:ava-a');
      final library = _FakeLibrary(assets: [_asset()]);
      final made = _makeOwner(
        ownerId: 'tekoa-a:ava-a',
        store: InMemoryMirrorStore(initial),
        library: library,
      );
      final enabledStates = <bool>[];
      final wifiStates = <bool>[];
      final foregroundStates = <bool>[];
      final reconcileStates = <bool>[];
      var notifications = 0;
      made.owner.changes.addListener(() {
        notifications++;
        enabledStates.add(made.owner.enabled);
        wifiStates.add(made.owner.wifiOnly);
        foregroundStates.add(made.owner.isForeground);
        reconcileStates.add(made.owner.reconciling);
      });

      made.owner.activate();
      expect(notifications, 1);
      final reconciliation = made.owner.reconcile();
      expect((await reconciliation).isSuccess, isTrue);
      expect(reconcileStates, containsAll([true, false]));

      final beforeProgress = notifications;
      made.events.add(
        const MirrorTransferProgress(
          assetId: 'asset-a',
          taskId: 'task-a',
          value: 0.4,
        ),
      );
      await _waitFor(() => notifications > beforeProgress);
      final progressed = (await made.store.load()).value!;
      expect(progressed.entries['asset-a']!.progress, 0.4);

      expect((await made.owner.setEnabled(false)).isSuccess, isTrue);
      expect((await made.owner.setWifiOnly(false)).isSuccess, isTrue);
      made.owner.setForeground(false);
      expect(enabledStates, contains(false));
      expect(wifiStates, contains(false));
      expect(foregroundStates, contains(false));

      await made.owner.dispose();
    });

    test('quota transfer failure pauses and cancels other work without reconciling', () async {
      final initial = _ledger([
        _entry(
          id: 'failed',
          state: MirrorState.uploading,
          path: '/support/failed.jpg',
          taskId: 'task-failed',
        ),
        _entry(
          id: 'other',
          state: MirrorState.uploading,
          path: '/support/other.jpg',
          taskId: 'task-other',
        ),
      ], ownerId: 'tekoa-a:ava-a');
      final store = InMemoryMirrorStore(initial);
      final library = _FakeLibrary(assets: [_asset()]);
      final api = _FakeApi();
      final saved = <MirrorPreferences>[];
      var startCalls = 0;
      final made = _makeOwner(
        ownerId: 'tekoa-a:ava-a',
        store: store,
        library: library,
        api: api,
        persistPreferences: (preferences) async {
          saved.add(preferences);
          return const Ok<void>(null);
        },
        startTransfer: () async {
          startCalls++;
          return const Ok<void>(null);
        },
      );
      made.owner.activate();

      made.events.add(
        const MirrorTransferFailed(
          assetId: 'failed',
          taskId: 'task-failed',
          error: _quotaExceeded,
        ),
      );
      await _waitFor(
        () =>
            made.owner.lastError == _quotaExceeded &&
            made.transfer.cancelledTaskIds.isNotEmpty,
      );

      expect(made.owner.enabled, isFalse);
      expect(saved, const [MirrorPreferences(enabled: false, wifiOnly: true)]);
      expect(made.transfer.cancelledTaskIds, ['task-other']);
      final ledger = (await store.load()).value!;
      expect(ledger.entries.keys, {'failed', 'other'});
      expect(ledger.entries['failed']!.state, MirrorState.failed);
      expect(ledger.entries['failed']!.lastError, _quotaExceeded.message);
      expect(ledger.entries['failed']!.backgroundTaskId, isNull);
      expect(ledger.entries['failed']!.localPath, '/support/failed.jpg');
      expect(ledger.entries['other']!.state, MirrorState.queued);
      expect(ledger.entries['other']!.backgroundTaskId, isNull);
      expect(ledger.entries['other']!.localPath, '/support/other.jpg');
      expect(startCalls, 0);
      expect(library.pageCalls, 0);
      expect(api.manifestCalls, 0);
      expect(made.materializer.retainedOnPrune, isEmpty);
      expect((await made.owner.reconcile()).isSuccess, isTrue);
      expect(library.pageCalls, 0);
      expect(api.manifestCalls, 0);

      expect((await made.owner.setEnabled(true)).isSuccess, isTrue);
      await _waitFor(() => library.pageCalls == 1);
      expect(made.owner.enabled, isTrue);
      expect(
        saved.last,
        const MirrorPreferences(enabled: true, wifiOnly: true),
      );

      await made.owner.dispose();
    });
  });

  group('MirrorRuntime', () {
    test(
      'notifies for owner creation, foreground changes and retirement only',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final runtimeStates = <MirrorOwnerMirror?>[];
        final ownerActiveStates = <bool>[];
        final ownerForegroundStates = <bool>[];
        late final _MadeOwner made;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            made = _makeOwner(ownerId: ownerId, enabled: false);
            made.owner.changes.addListener(() {
              ownerActiveStates.add(made.owner.isActive);
              ownerForegroundStates.add(made.owner.isForeground);
            });
            return Ok(made.owner);
          },
        );
        runtime.changes.addListener(() {
          runtimeStates.add(runtime.currentOwner);
        });

        runtime.attach();
        await _waitFor(() => runtime.currentOwner != null);
        expect(runtimeStates, contains(same(made.owner)));
        expect(ownerActiveStates, contains(true));

        foreground.set(false);
        expect(ownerForegroundStates, contains(false));
        changes.set(null);
        expect(runtime.currentOwner, isNull);
        expect(runtimeStates, contains(isNull));
        await runtime.dispose();

        final runtimeCountAfterDispose = runtimeStates.length;
        final ownerActiveCountAfterDispose = ownerActiveStates.length;
        final ownerForegroundCountAfterDispose = ownerForegroundStates.length;
        changes.set(_identity(tekoaId: 'tekoa-b'));
        foreground.set(true);
        made.owner.setForeground(true);
        expect(runtimeStates, hasLength(runtimeCountAfterDispose));
        expect(ownerActiveStates, hasLength(ownerActiveCountAfterDispose));
        expect(
          ownerForegroundStates,
          hasLength(ownerForegroundCountAfterDispose),
        );
      },
    );

    test(
      'disabled owner activation stays quiet with an empty ledger',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        var startCalls = 0;
        _MadeOwner? made;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            made = _makeOwner(
              ownerId: ownerId,
              enabled: false,
              startTransfer: () async {
                startCalls++;
                return const Ok<void>(null);
              },
            );
            return Ok(made!.owner);
          },
        );

        runtime.attach();
        await _waitFor(() => runtime.currentOwner != null);
        expect(identical(runtime.currentOwner, made!.owner), isTrue);
        expect(startCalls, 0);
        expect(made!.library.pageCalls, 0);
        expect(made!.materializer.retainedOnPrune, isEmpty);

        foreground.set(false);
        foreground.set(true);
        await Future<void>.delayed(Duration.zero);
        expect(startCalls, 0);
        expect(made!.library.pageCalls, 0);

        await runtime.dispose();
        await made!.owner.dispose();
      },
    );

    test(
      'disabled activation cancels persisted task without reading library',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground(isForeground: false);
        final store = InMemoryMirrorStore(
          _ledger([
            _entry(
              id: 'asset-a',
              state: MirrorState.uploading,
              path: '/support/retained.jpg',
              taskId: 'task-a',
            ),
          ], ownerId: 'tekoa-a:ava-a'),
        );
        final api = _FakeApi();
        var startCalls = 0;
        _MadeOwner? made;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            made = _makeOwner(
              ownerId: ownerId,
              enabled: false,
              store: store,
              api: api,
              startTransfer: () async {
                startCalls++;
                return const Ok<void>(null);
              },
            );
            return Ok(made!.owner);
          },
        );

        runtime.attach();
        await _waitFor(
          () => made?.transfer.cancelledTaskIds.isNotEmpty == true,
        );

        expect(made!.transfer.cancelledTaskIds, ['task-a']);
        final entry = (await store.load()).value!.entries['asset-a']!;
        expect(entry.backgroundTaskId, isNull);
        expect(entry.localPath, '/support/retained.jpg');
        expect(startCalls, 0);
        expect(made!.library.pageCalls, 0);
        expect(api.manifestCalls, 0);
        expect(made!.materializer.retainedOnPrune, isEmpty);

        await runtime.dispose();
        await made!.owner.dispose();
      },
    );

    test('uses the composite community and Ava owner key', () async {
      final changes = _IdentityChanges(_identity());
      final foreground = _ManualForeground();
      final requestedKeys = <String>[];
      final owners = <_MadeOwner>[];
      final runtime = MirrorRuntime(
        changes: changes,
        identity: () => changes.value,
        foreground: foreground,
        ownerFactory: ({required ownerId, required identity}) async {
          requestedKeys.add(ownerId);
          final made = _makeOwner(ownerId: ownerId);
          owners.add(made);
          return Ok(made.owner);
        },
      );

      runtime.attach();
      await _waitFor(() => requestedKeys.length == 1);
      changes.set(_identity(tekoaId: 'tekoa-b', avaId: 'ava-a'));
      await _waitFor(() => requestedKeys.length == 2);

      expect(requestedKeys, ['tekoa-a:ava-a', 'tekoa-b:ava-a']);
      await runtime.dispose();
      await Future.wait(owners.map((made) => made.owner.dispose()));
    });

    test(
      'owner change disposes A and a stale A operation never prunes',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final libraryA = _FakeLibrary()
          ..pageEntered = Completer<void>()
          ..pageGate = Completer<void>();
        final storeA = InMemoryMirrorStore(
          _ledger([
            _entry(id: 'a', state: MirrorState.failed, path: '/owner-a/file'),
          ], ownerId: 'tekoa-a:ava-a'),
        );
        final materializerA = _RecordingMaterializer();
        final disposedA = Completer<void>();
        final libraryB = _FakeLibrary();
        final storeB = InMemoryMirrorStore(
          _ledger([
            _entry(id: 'b', state: MirrorState.failed, path: '/owner-b/file'),
          ], ownerId: 'tekoa-b:ava-a'),
        );
        final materializerB = _RecordingMaterializer();
        _MadeOwner? ownerA;
        _MadeOwner? ownerB;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            if (ownerId == 'tekoa-a:ava-a') {
              ownerA = _makeOwner(
                ownerId: ownerId,
                store: storeA,
                library: libraryA,
                materializer: materializerA,
                onDispose: () async => disposedA.complete(),
              );
              return Ok(ownerA!.owner);
            }
            ownerB = _makeOwner(
              ownerId: ownerId,
              store: storeB,
              library: libraryB,
              materializer: materializerB,
            );
            return Ok(ownerB!.owner);
          },
        );
        runtime.attach();
        await libraryA.pageEntered!.future;

        changes.set(_identity(tekoaId: 'tekoa-b', avaId: 'ava-a'));
        expect(ownerA!.owner.isActive, isFalse);
        libraryA.pageGate!.complete();
        await _waitFor(
          () => ownerB != null && materializerB.retainedOnPrune.isNotEmpty,
        );
        await disposedA.future;

        expect(materializerA.retainedOnPrune, isEmpty);
        expect(materializerB.retainedOnPrune.single, {'/owner-b/file'});
        expect((await storeA.load()).value!.entries, contains('a'));
        expect((await storeB.load()).value!.entries, contains('b'));

        await runtime.dispose();
        await ownerA!.owner.dispose();
        await ownerB!.owner.dispose();
      },
    );

    test(
      'reselected owner waits for its in-flight retirement before recreation',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final deactivationEntered = Completer<void>();
        final allowDeactivation = Completer<void>();
        final owners = <_MadeOwner>[];
        var ownerFactoryCalls = 0;
        var reselected = false;
        late final MirrorRuntime runtime;
        runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            ownerFactoryCalls++;
            final made = _makeOwner(
              ownerId: ownerId,
              enabled: false,
              onDispose: ownerFactoryCalls == 1
                  ? () async {
                      deactivationEntered.complete();
                      await allowDeactivation.future;
                    }
                  : null,
            );
            owners.add(made);
            return Ok(made.owner);
          },
        );
        runtime.changes.addListener(() {
          if (runtime.currentOwner == null && !reselected) {
            reselected = true;
            changes.set(_identity());
          }
        });

        runtime.attach();
        await _waitFor(() => runtime.currentOwner != null);
        changes.set(_identity(tekoaId: 'tekoa-b'));
        await deactivationEntered.future;
        await Future<void>.delayed(Duration.zero);

        expect(reselected, isTrue);
        expect(ownerFactoryCalls, 1);
        expect(runtime.currentOwner, isNull);

        allowDeactivation.complete();
        await _waitFor(
          () => ownerFactoryCalls == 2 && runtime.currentOwner != null,
        );
        expect(runtime.currentOwner, same(owners.last.owner));

        await runtime.dispose();
      },
    );

    test(
      'logout deactivates without clearing the ledger or local files',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final store = InMemoryMirrorStore(
          _ledger([
            _entry(
              id: 'kept',
              state: MirrorState.failed,
              path: '/support/kept',
            ),
          ], ownerId: 'tekoa-a:ava-a'),
        );
        final materializer = _RecordingMaterializer();
        materializer.files.add('/support/kept');
        final disposed = Completer<void>();
        late final _MadeOwner made;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            made = _makeOwner(
              ownerId: ownerId,
              store: store,
              materializer: materializer,
              onDispose: () async => disposed.complete(),
            );
            return Ok(made.owner);
          },
        );
        runtime.attach();
        await _waitFor(() => materializer.retainedOnPrune.isNotEmpty);
        final pruneCount = materializer.retainedOnPrune.length;

        changes.set(null);
        await disposed.future;

        expect(made.owner.isActive, isFalse);
        expect(materializer.retainedOnPrune, hasLength(pruneCount));
        expect((await store.load()).value!.entries.keys, {'kept'});
        expect(materializer.files, {'/support/kept'});

        await runtime.dispose();
      },
    );

    test(
      'a failed start is retried after the next foreground activation',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        var startCalls = 0;
        var factoryCalls = 0;
        final owners = <_MadeOwner>[];
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            factoryCalls++;
            final made = _makeOwner(
              ownerId: ownerId,
              startTransfer: () async {
                startCalls++;
                if (startCalls == 1) return const Err(_offline);
                return const Ok<void>(null);
              },
            );
            owners.add(made);
            return Ok(made.owner);
          },
        );
        runtime.attach();
        await _waitFor(() => startCalls == 1);
        expect(owners.first.library.pageCalls, 0);

        foreground.set(false);
        expect(owners.single.owner.isActive, isTrue);
        foreground.set(true);
        await _waitFor(() => startCalls == 2);

        expect(factoryCalls, 1);
        expect(owners, hasLength(1));
        expect(owners.single.library.pageCalls, 1);
        await runtime.dispose();
        await Future.wait(owners.map((made) => made.owner.dispose()));
      },
    );

    test(
      'a current factory error retries on resume without concurrent factories',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final firstStarted = Completer<void>();
        final firstResult = Completer<TainaResult<MirrorOwnerMirror>>();
        var factoryCalls = 0;
        _MadeOwner? successfulOwner;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            factoryCalls++;
            if (factoryCalls == 1) {
              firstStarted.complete();
              return firstResult.future;
            }
            successfulOwner = _makeOwner(ownerId: ownerId);
            return Ok(successfulOwner!.owner);
          },
        );

        runtime.attach();
        await firstStarted.future;
        foreground.set(false);
        foreground.set(true);
        expect(factoryCalls, 1);

        firstResult.complete(const Err(_offline));
        await _waitFor(() => runtime.lastError == _offline);
        expect(successfulOwner, isNull);

        foreground.set(false);
        foreground.set(true);
        await _waitFor(() => successfulOwner != null);

        expect(factoryCalls, 2);
        expect(successfulOwner!.owner.isActive, isTrue);
        await runtime.dispose();
        await successfulOwner!.owner.dispose();
      },
    );

    test(
      'refresh retries a failed owner factory for the current identity',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground(isForeground: false);
        var factoryCalls = 0;
        _MadeOwner? made;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            factoryCalls++;
            if (factoryCalls == 1) return const Err(_offline);
            made = _makeOwner(ownerId: ownerId, enabled: false);
            return Ok(made!.owner);
          },
        );

        runtime.attach();
        await _waitFor(() => runtime.lastError == _offline);

        await runtime.refresh();

        expect(factoryCalls, 2);
        expect(runtime.currentOwner, same(made!.owner));
        expect(runtime.lastError, isNull);
        await runtime.dispose();
        await made!.owner.dispose();
      },
    );

    test(
      'background preserves the owner and subscription, resume reconciles it',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground(isForeground: false);
        var factoryCalls = 0;
        var startCalls = 0;
        _MadeOwner? made;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            factoryCalls++;
            made = _makeOwner(
              ownerId: ownerId,
              startTransfer: () async {
                startCalls++;
                return const Ok<void>(null);
              },
            );
            return Ok(made!.owner);
          },
        );

        runtime.attach();
        await _waitFor(() => made != null);
        expect(made!.owner.isActive, isTrue);
        expect(startCalls, 0);
        expect(made!.library.pageCalls, 0);
        expect(made!.events.hasListener, isTrue);

        foreground.set(true);
        await _waitFor(
          () =>
              startCalls == 1 &&
              made!.library.pageCalls == 1 &&
              made!.materializer.retainedOnPrune.isNotEmpty,
        );
        final owner = made!.owner;
        final events = made!.events;

        foreground.set(false);
        expect(owner.isActive, isTrue);
        expect(events.hasListener, isTrue);
        events.add(const MirrorTransferStreamFailed(error: _offline));
        expect(owner.lastError, _offline);

        foreground.set(true);
        await _waitFor(() => startCalls == 2 && made!.library.pageCalls == 2);
        expect(factoryCalls, 1);
        expect(identical(made!.owner, owner), isTrue);
        expect(events.hasListener, isTrue);

        await runtime.dispose();
        await owner.dispose();
      },
    );

    test(
      'background completion persists without reconciling until resume',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final store = _WatchingStore(
          _ledger([
            _entry(
              id: 'asset-a',
              state: MirrorState.uploading,
              path: '/support/retained.jpg',
              taskId: 'task-a',
            ),
          ], ownerId: 'tekoa-a:ava-a'),
        );
        final library = _FakeLibrary(assets: [_asset()]);
        final materializer = _RecordingMaterializer();
        final api = _FakeApi();
        var factoryCalls = 0;
        var startCalls = 0;
        late final _MadeOwner made;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            factoryCalls++;
            made = _makeOwner(
              ownerId: ownerId,
              store: store,
              library: library,
              materializer: materializer,
              api: api,
              startTransfer: () async {
                startCalls++;
                return const Ok<void>(null);
              },
            );
            return Ok(made.owner);
          },
        );

        runtime.attach();
        await _waitFor(
          () =>
              startCalls == 1 &&
              library.pageCalls == 1 &&
              materializer.retainedOnPrune.length == 1,
        );
        final owner = made.owner;
        final events = made.events;
        final startsBeforeBackground = startCalls;
        final pagesBeforeBackground = library.pageCalls;
        final manifestsBeforeBackground = api.manifestCalls;
        final prunesBeforeBackground = materializer.retainedOnPrune.length;

        foreground.set(false);
        expect(owner.isActive, isTrue);
        expect(events.hasListener, isTrue);
        events.add(
          MirrorTransferCompleted(
            assetId: 'asset-a',
            taskId: 'task-a',
            modificationDate: _modified,
            file: _file(),
          ),
        );
        await store.uploaded.future;
        await Future<void>.delayed(Duration.zero);

        expect(
          (await store.load()).value!.entries['asset-a']!.state,
          MirrorState.uploaded,
        );
        expect(startCalls, startsBeforeBackground);
        expect(library.pageCalls, pagesBeforeBackground);
        expect(api.manifestCalls, manifestsBeforeBackground);
        expect(materializer.retainedOnPrune, hasLength(prunesBeforeBackground));
        expect(events.hasListener, isTrue);

        foreground.set(true);
        await _waitFor(
          () =>
              startCalls == startsBeforeBackground + 1 &&
              library.pageCalls == pagesBeforeBackground + 1 &&
              materializer.retainedOnPrune.length == prunesBeforeBackground + 1,
        );
        expect(factoryCalls, 1);
        expect(identical(made.owner, owner), isTrue);
        expect(events.hasListener, isTrue);

        await runtime.dispose();
        await owner.dispose();
      },
    );

    test(
      'a factory that resolves after an owner change cannot activate',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final firstFactory = Completer<void>();
        final staleDisposed = Completer<void>();
        final staleOwner = _makeOwner(
          ownerId: 'tekoa-a:ava-a',
          onDispose: () async => staleDisposed.complete(),
        );
        _MadeOwner? currentOwner;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            if (ownerId == 'tekoa-a:ava-a') {
              firstFactory.complete();
              await Future<void>.delayed(Duration.zero);
              return Ok(staleOwner.owner);
            }
            currentOwner = _makeOwner(ownerId: ownerId);
            return Ok(currentOwner!.owner);
          },
        );

        runtime.attach();
        await firstFactory.future;
        changes.set(_identity(tekoaId: 'tekoa-b', avaId: 'ava-a'));
        await _waitFor(() => currentOwner != null);
        await staleDisposed.future;

        expect(staleOwner.owner.isActive, isFalse);
        expect(staleOwner.library.pageCalls, 0);
        expect(currentOwner!.owner.isActive, isTrue);
        await runtime.dispose();
        await staleOwner.owner.dispose();
        await currentOwner!.owner.dispose();
      },
    );

    test(
      'same-key creation waits for retirement while another key proceeds',
      () async {
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final firstPageEntered = Completer<void>();
        final firstPageGate = Completer<void>();
        final secondPageEntered = Completer<void>();
        final secondPageGate = Completer<void>();
        final firstDisposed = Completer<void>();
        final secondDisposed = Completer<void>();
        var factoryCalls = 0;
        _MadeOwner? secondOwner;
        _MadeOwner? otherCommunity;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            factoryCalls++;
            if (factoryCalls == 1) {
              final library = _FakeLibrary(assets: [_asset()])
                ..pageEntered = firstPageEntered
                ..pageGate = firstPageGate;
              return Ok(
                _makeOwner(
                  ownerId: ownerId,
                  library: library,
                  onDispose: () async => firstDisposed.complete(),
                ).owner,
              );
            }
            if (factoryCalls == 2) {
              final library = _FakeLibrary(assets: [_asset()])
                ..pageEntered = secondPageEntered
                ..pageGate = secondPageGate;
              secondOwner = _makeOwner(
                ownerId: ownerId,
                library: library,
                onDispose: () async => secondDisposed.complete(),
              );
              return Ok(secondOwner!.owner);
            }
            otherCommunity = _makeOwner(ownerId: ownerId);
            return Ok(otherCommunity!.owner);
          },
        );

        runtime.attach();
        await firstPageEntered.future;
        changes.set(null);
        changes.set(_identity());
        await Future<void>.delayed(Duration.zero);
        expect(factoryCalls, 1);

        firstPageGate.complete();
        await secondPageEntered.future;
        await firstDisposed.future;
        expect(factoryCalls, 2);

        changes.set(_identity(tekoaId: 'tekoa-b', avaId: 'ava-a'));
        await _waitFor(
          () =>
              otherCommunity != null &&
              otherCommunity!.materializer.retainedOnPrune.isNotEmpty,
        );
        expect(factoryCalls, 3);
        expect(secondDisposed.isCompleted, isFalse);

        secondPageGate.complete();
        await secondDisposed.future;
        expect(otherCommunity!.owner.isActive, isTrue);

        await runtime.dispose();
        await secondOwner!.owner.dispose();
        await otherCommunity!.owner.dispose();
      },
    );

    test(
      'a stale same-key factory error does not block logout and login',
      () async {
        final reports = <FlutterErrorDetails>[];
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = reports.add;
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final firstStarted = Completer<void>();
        final firstResult = Completer<TainaResult<MirrorOwnerMirror>>();
        var factoryCalls = 0;
        _MadeOwner? currentOwner;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            factoryCalls++;
            if (factoryCalls == 1) {
              firstStarted.complete();
              return firstResult.future;
            }
            currentOwner = _makeOwner(ownerId: ownerId);
            return Ok(currentOwner!.owner);
          },
        );

        try {
          runtime.attach();
          await firstStarted.future;
          changes.set(null);
          changes.set(_identity());
          await Future<void>.delayed(Duration.zero);
          expect(factoryCalls, 1);

          final originalError = StateError('stale factory failure');
          final originalStack = StackTrace.current;
          firstResult.completeError(originalError, originalStack);
          await _waitFor(() => currentOwner?.owner.isActive == true);
          await _waitFor(() => reports.isNotEmpty);

          expect(factoryCalls, 2);
          expect(currentOwner!.owner.isActive, isTrue);
          expect(reports, hasLength(1));
          expect(reports.single.exception, same(originalError));
          expect(reports.single.stack, same(originalStack));
        } finally {
          await runtime.dispose();
          await currentOwner?.owner.dispose();
          FlutterError.onError = previousErrorHandler;
        }
      },
    );

    test(
      'automatic resume errors are reported; explicit errors remain visible',
      () async {
        final reports = <FlutterErrorDetails>[];
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = reports.add;
        final changes = _IdentityChanges(_identity());
        final foreground = _ManualForeground();
        final library = _FakeLibrary();
        _MadeOwner? made;
        final runtime = MirrorRuntime(
          changes: changes,
          identity: () => changes.value,
          foreground: foreground,
          ownerFactory: ({required ownerId, required identity}) async {
            made = _makeOwner(ownerId: ownerId, library: library);
            return Ok(made!.owner);
          },
        );

        try {
          runtime.attach();
          await _waitFor(
            () => made?.materializer.retainedOnPrune.isNotEmpty == true,
          );
          final owner = made!.owner;
          final failure = StateError('resume library failure');
          library.pageThrow = failure;
          foreground.set(false);
          foreground.set(true);
          await _waitFor(() => reports.isNotEmpty);

          expect(identical(reports.single.exception, failure), isTrue);
          expect(reports.single.stack, isNotNull);
          await expectLater(owner.reconcile(), throwsA(same(failure)));

          library.pageThrow = null;
          expect((await owner.reconcile()).isSuccess, isTrue);
        } finally {
          await runtime.dispose();
          await made?.owner.dispose();
          FlutterError.onError = previousErrorHandler;
        }
      },
    );

    test('automatic completion follow-up reports errors without hiding explicit errors', () async {
      final reports = <FlutterErrorDetails>[];
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = reports.add;
      final store = _WatchingStore(
        _ledger([
          _entry(
            id: 'asset-a',
            state: MirrorState.uploading,
            path: '/support/retained.jpg',
            taskId: 'task-a',
          ),
        ], ownerId: 'tekoa-a:ava-a'),
      );
      final library = _FakeLibrary()
        ..pageThrow = StateError('completion library failure');
      final events = StreamController<MirrorTransferEvent>.broadcast(
        sync: true,
      );
      final owner = _makeOwner(
        ownerId: 'tekoa-a:ava-a',
        store: store,
        library: library,
        events: events,
      ).owner;
      owner.activate();

      try {
        events.add(
          MirrorTransferCompleted(
            assetId: 'asset-a',
            taskId: 'task-a',
            modificationDate: _modified,
            file: _file(),
          ),
        );
        await store.uploaded.future;
        await _waitFor(() => reports.isNotEmpty);

        final failure = library.pageThrow;
        expect(reports.single.exception, same(failure));
        expect(reports.single.stack, isNotNull);
        await expectLater(owner.reconcile(), throwsA(same(failure)));

        library.pageThrow = null;
        expect((await owner.reconcile()).isSuccess, isTrue);
      } finally {
        await owner.dispose();
        FlutterError.onError = previousErrorHandler;
      }
    });
  });
}

Future<void> _waitFor(bool Function() condition) async {
  while (!condition()) {
    await Future<void>.delayed(Duration.zero);
  }
}
