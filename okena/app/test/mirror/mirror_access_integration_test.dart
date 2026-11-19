import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/background_mirror_transfer.dart';
import 'package:okena_app/src/mirror/mirror_asset_hasher.dart';
import 'package:okena_app/src/mirror/mirror_asset_materializer.dart';
import 'package:okena_app/src/mirror/mirror_engine.dart';
import 'package:okena_app/src/mirror/mirror_library.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_app/src/mirror/mirror_transfer.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

const _ownerId = 'tekoa-a:ava-a';
final _now = DateTime.utc(2026, 11, 18, 12);
final _modified = DateTime.utc(2026, 11, 17, 10);
const _notFound = ApiError(
  code: 'not_found',
  status: 404,
  serverMessage: 'not found',
);

MirrorAsset _asset(String id) => MirrorAsset(
  assetId: id,
  modificationDate: _modified,
  filename: '$id.jpg',
  mime: 'image/jpeg',
  size: 100,
  takenAt: null,
);

MirrorEntry _persistedEntry({
  required String id,
  required String path,
  required String taskId,
}) => MirrorEntry(
  assetId: id,
  modificationDate: _modified,
  filename: '$id.jpg',
  mime: 'image/jpeg',
  size: 100,
  takenAt: null,
  sha256: _hashFor(id),
  localPath: path,
  state: MirrorState.uploading,
  rkey: null,
  backgroundTaskId: taskId,
  attempts: 0,
  lastError: null,
  progress: 0,
  updatedAt: _now,
);

String _hashFor(String id) => id.codeUnits
    .map((unit) => unit.toRadixString(16).padLeft(2, '0'))
    .join()
    .padRight(64, '0');

String _pathFor(String id) => '/virtual/mirror/$id.jpg';

class _TestSession implements SessionGateway {
  _TestSession(this.api);

  @override
  final TainaApi api;

  @override
  ThumbnailStore get thumbnails => ThumbnailStore(api: api);

  @override
  Me? get identity => null;

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async => outcome;
}

class _TestApi implements TainaApi {
  @override
  Future<TainaResult<Page<FileRecord>>> manifest({
    String? after,
    int? limit,
    ManifestMode mode = ManifestMode.readable,
  }) async => Ok(Page(items: const [], nextCursor: null));

  @override
  Future<TainaResult<MirrorHashLookup>> hashLookup({
    required String sha256,
  }) async => const Err(_notFound);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _TestLibrary implements MirrorLibrary {
  _TestLibrary({
    required this.access,
    required List<MirrorAsset> assets,
    this.assetsAfterLimitedSelection = const [],
  }) : assets = List.of(assets);

  MirrorLibraryAccess access;
  List<MirrorAsset> assets;
  final List<MirrorAsset> assetsAfterLimitedSelection;
  int currentAccessCalls = 0;
  int pageCalls = 0;
  int limitedSelectionCalls = 0;

  @override
  Future<TainaResult<MirrorLibraryAccess>> currentAccess() async {
    currentAccessCalls++;
    return Ok(access);
  }

  @override
  Future<TainaResult<MirrorLibraryAccess>> requestAccess() async => Ok(access);

  @override
  Future<TainaResult<void>> openSettings() async => const Ok<void>(null);

  @override
  Future<TainaResult<MirrorAssetPage>> page({
    required int page,
    int size = 200,
  }) async {
    pageCalls++;
    return Ok(
      MirrorAssetPage(assets: page == 0 ? assets : const [], hasMore: false),
    );
  }

  @override
  Future<TainaResult<void>> presentLimitedSelection() async {
    limitedSelectionCalls++;
    assets = [...assets, ...assetsAfterLimitedSelection];
    return const Ok<void>(null);
  }
}

class _RecordingMaterializer implements MirrorAssetMaterializer {
  final List<Set<String>> retainedPaths = [];
  final Set<String> files = {};

  @override
  Future<TainaResult<MaterializedAsset>> materialize(MirrorEntry entry) async =>
      Ok(
        MaterializedAsset(
          path: entry.localPath ?? _pathFor(entry.assetId),
          size: 1,
        ),
      );

  @override
  Future<TainaResult<void>> prune({required Set<String> retainedPaths}) async {
    this.retainedPaths.add(Set.unmodifiable(retainedPaths));
    files.removeWhere((path) => !retainedPaths.contains(path));
    return const Ok<void>(null);
  }
}

class _RecordingHasher implements MirrorAssetHasher {
  _RecordingHasher(this.materializer);

  final _RecordingMaterializer materializer;
  final List<String> hashedAssetIds = [];

  @override
  Future<TainaResult<MirrorHashResult>> hash(MirrorEntry entry) async {
    hashedAssetIds.add(entry.assetId);
    final path = _pathFor(entry.assetId);
    materializer.files.add(path);
    return Ok(
      MirrorHashResult(sha256: _hashFor(entry.assetId), localPath: path),
    );
  }
}

class _RecordingTransfer implements MirrorTransfer {
  final List<String> ensureStartedAssetIds = [];
  final List<String> newlyScheduledAssetIds = [];
  final Set<String> _scheduledTaskIds = {};

  @override
  Future<TainaResult<void>> ensureStarted({
    required MirrorEntry entry,
    required String folderRkey,
  }) async {
    ensureStartedAssetIds.add(entry.assetId);
    final taskId = entry.backgroundTaskId;
    if (taskId != null && _scheduledTaskIds.add(taskId)) {
      newlyScheduledAssetIds.add(entry.assetId);
    }
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<void>> cancel(String backgroundTaskId) async =>
      const Ok<void>(null);
}

class _OwnerFixture {
  _OwnerFixture({
    required this.owner,
    required this.events,
    required this.library,
    required this.store,
    required this.materializer,
    required this.hasher,
    required this.transfer,
  });

  final MirrorOwnerMirror owner;
  final StreamController<MirrorTransferEvent> events;
  final _TestLibrary library;
  final InMemoryMirrorStore store;
  final _RecordingMaterializer materializer;
  final _RecordingHasher hasher;
  final _RecordingTransfer transfer;

  Future<void> dispose() => owner.dispose();
}

_OwnerFixture _makeOwner({
  required _TestLibrary library,
  required InMemoryMirrorStore store,
  required _RecordingMaterializer materializer,
}) {
  final events = StreamController<MirrorTransferEvent>.broadcast(sync: true);
  final hasher = _RecordingHasher(materializer);
  final transfer = _RecordingTransfer();
  final engine = MirrorEngine(
    session: _TestSession(_TestApi()),
    store: store,
    hasher: hasher,
    transfer: transfer,
    ownerId: _ownerId,
    random: math.Random(42),
    clock: () => _now,
    progressBatchWindow: Duration.zero,
  );
  final owner = MirrorOwnerMirror(
    engine: engine,
    library: library,
    store: store,
    materializer: materializer,
    transferEvents: events.stream,
    startTransfer: () async => const Ok<void>(null),
    disposeTransfer: events.close,
    enabled: true,
  );
  owner.activate();
  owner.setForeground(true);
  return _OwnerFixture(
    owner: owner,
    events: events,
    library: library,
    store: store,
    materializer: materializer,
    hasher: hasher,
    transfer: transfer,
  );
}

void main() {
  test(
    'limited selection refresh hashes and schedules only newly selected assets',
    () async {
      final assetA = _asset('asset-a');
      final assetB = _asset('asset-b');
      final library = _TestLibrary(
        access: MirrorLibraryAccess.limited,
        assets: [assetA],
        assetsAfterLimitedSelection: [assetB],
      );
      final materializer = _RecordingMaterializer();
      final store = InMemoryMirrorStore(
        MirrorLedger(ownerId: _ownerId, destinationFolderRkey: 'camera-folder'),
      );
      final fixture = _makeOwner(
        library: library,
        store: store,
        materializer: materializer,
      );
      addTearDown(fixture.dispose);

      expect(fixture.owner.enabled, isTrue);
      expect(fixture.owner.isForeground, isTrue);
      expect(
        (await fixture.owner.reconcile(refreshLibrary: true)).isSuccess,
        isTrue,
      );

      final firstLedger = (await store.load()).value!;
      final firstEntryA = firstLedger.entries['asset-a']!;
      expect(fixture.hasher.hashedAssetIds, ['asset-a']);
      expect(fixture.transfer.newlyScheduledAssetIds, ['asset-a']);
      expect(firstEntryA.localPath, _pathFor('asset-a'));
      expect(firstEntryA.state, MirrorState.uploading);
      expect(materializer.files, {_pathFor('asset-a')});

      expect((await library.presentLimitedSelection()).isSuccess, isTrue);
      expect(library.limitedSelectionCalls, 1);
      expect(
        (await fixture.owner.reconcile(refreshLibrary: true)).isSuccess,
        isTrue,
      );

      final secondLedger = (await store.load()).value!;
      expect(secondLedger.entries.keys, {'asset-a', 'asset-b'});
      expect(secondLedger.entries['asset-a'], firstEntryA);
      expect(secondLedger.entries['asset-a']!.localPath, _pathFor('asset-a'));
      expect(secondLedger.entries['asset-b']!.localPath, _pathFor('asset-b'));
      expect(fixture.hasher.hashedAssetIds, ['asset-a', 'asset-b']);
      expect(fixture.transfer.newlyScheduledAssetIds, ['asset-a', 'asset-b']);
      expect(fixture.transfer.newlyScheduledAssetIds.toSet(), {
        'asset-a',
        'asset-b',
      });
      expect(materializer.files, {_pathFor('asset-a'), _pathFor('asset-b')});
    },
  );

  for (final revokedAccess in [
    MirrorLibraryAccess.denied,
    MirrorLibraryAccess.restricted,
  ]) {
    test(
      'preserves persisted mirror data when access is $revokedAccess on reconcile',
      () async {
        final entryA = _persistedEntry(
          id: 'asset-a',
          path: _pathFor('asset-a'),
          taskId: 'task-a',
        );
        final entryB = _persistedEntry(
          id: 'asset-b',
          path: _pathFor('asset-b'),
          taskId: 'task-b',
        );
        final initialLedger = MirrorLedger(
          ownerId: _ownerId,
          destinationFolderRkey: 'camera-folder',
          entries: {entryA.assetId: entryA, entryB.assetId: entryB},
        );
        final store = InMemoryMirrorStore(initialLedger);
        final materializer = _RecordingMaterializer()
          ..files.addAll({_pathFor('asset-a'), _pathFor('asset-b')});
        final library = _TestLibrary(
          access: MirrorLibraryAccess.full,
          assets: [_asset('asset-a'), _asset('asset-b')],
        );
        final fixture = _makeOwner(
          library: library,
          store: store,
          materializer: materializer,
        );
        addTearDown(fixture.dispose);

        expect(
          (await fixture.owner.reconcile(refreshLibrary: true)).isSuccess,
          isTrue,
        );
        final scheduledBeforeRevocation = [
          ...fixture.transfer.newlyScheduledAssetIds,
        ];
        final pruneCountBeforeRevocation = materializer.retainedPaths.length;
        final hashCountBeforeRevocation = fixture.hasher.hashedAssetIds.length;
        final ledgerBeforeRevocation = (await store.load()).value!;
        expect(ledgerBeforeRevocation.entries.keys, {'asset-a', 'asset-b'});

        library.access = revokedAccess;
        library.assets = [_asset('asset-c')];
        fixture.owner.setForeground(false);
        fixture.owner.setForeground(true);

        final result = await fixture.owner.reconcile(refreshLibrary: true);

        expect(result.isFailure, isTrue);
        expect(fixture.owner.lastError, isNotNull);
        expect(library.currentAccessCalls, 2);
        expect(library.pageCalls, 1);
        expect(
          materializer.retainedPaths,
          hasLength(pruneCountBeforeRevocation),
        );
        expect(materializer.files, {_pathFor('asset-a'), _pathFor('asset-b')});
        expect(
          fixture.transfer.newlyScheduledAssetIds,
          scheduledBeforeRevocation,
        );
        expect(
          fixture.hasher.hashedAssetIds,
          hasLength(hashCountBeforeRevocation),
        );

        final ledgerAfterRevocation = (await store.load()).value!;
        expect(ledgerAfterRevocation.entries, ledgerBeforeRevocation.entries);
        expect(
          ledgerAfterRevocation.entries['asset-a']!.localPath,
          entryA.localPath,
        );
        expect(
          ledgerAfterRevocation.entries['asset-b']!.localPath,
          entryB.localPath,
        );
      },
    );
  }
}
