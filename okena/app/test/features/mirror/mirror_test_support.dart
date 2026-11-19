import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:okena_app/src/mirror/mirror_asset_hasher.dart';
import 'package:okena_app/src/mirror/mirror_asset_materializer.dart';
import 'package:okena_app/src/mirror/background_mirror_transfer.dart';
import 'package:okena_app/src/mirror/mirror_engine.dart';
import 'package:okena_app/src/mirror/mirror_foreground.dart';
import 'package:okena_app/src/mirror/mirror_library.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_app/src/mirror/mirror_settings.dart';
import 'package:okena_app/src/mirror/mirror_transfer.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

const mirrorOfflineError = NetworkError('offline');
const mirrorQuotaError = ApiError(
  code: 'storage_quota_exceeded',
  status: 422,
  serverMessage: 'storage quota exceeded',
);

final class MirrorTestLibrary implements MirrorLibrary {
  MirrorTestLibrary({
    this.access = MirrorLibraryAccess.full,
    this.requestedAccess = MirrorLibraryAccess.full,
    this.currentAccessHandler,
  });

  MirrorLibraryAccess access;
  MirrorLibraryAccess requestedAccess;
  Future<TainaResult<MirrorLibraryAccess>> Function()? currentAccessHandler;
  int currentAccessCalls = 0;
  int requestAccessCalls = 0;
  int settingsCalls = 0;
  int limitedPickerCalls = 0;

  @override
  Future<TainaResult<MirrorLibraryAccess>> currentAccess() async {
    currentAccessCalls++;
    final handler = currentAccessHandler;
    if (handler != null) return handler();
    return Ok(access);
  }

  @override
  Future<TainaResult<MirrorLibraryAccess>> requestAccess() async {
    requestAccessCalls++;
    access = requestedAccess;
    return Ok(requestedAccess);
  }

  @override
  Future<TainaResult<void>> openSettings() async {
    settingsCalls++;
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<MirrorAssetPage>> page({
    required int page,
    int size = 200,
  }) async => Ok(MirrorAssetPage(assets: const [], hasMore: false));

  @override
  Future<TainaResult<void>> presentLimitedSelection() async {
    limitedPickerCalls++;
    return const Ok<void>(null);
  }
}

final class MirrorTestStore implements MirrorStore {
  MirrorTestStore({MirrorLedger? ledger})
    : _inner = InMemoryMirrorStore(ledger);

  final InMemoryMirrorStore _inner;
  int loadCalls = 0;
  TainaError? loadError;

  @override
  Future<TainaResult<MirrorLedger?>> load() async {
    loadCalls++;
    final error = loadError;
    return error == null ? _inner.load() : Err(error);
  }

  @override
  Future<TainaResult<void>> save(MirrorLedger ledger) => _inner.save(ledger);

  @override
  Future<TainaResult<void>> clear() => _inner.clear();
}

final class MirrorTestOwner {
  MirrorTestOwner({
    required this.owner,
    required this.library,
    required this.store,
    required this.events,
  });

  final MirrorOwnerMirror owner;
  final MirrorTestLibrary library;
  final MirrorTestStore store;
  final StreamController<MirrorTransferEvent> events;

  Future<void> dispose() async {
    await owner.dispose();
  }
}

MirrorTestOwner makeMirrorTestOwner({
  required String ownerId,
  MirrorTestLibrary? library,
  MirrorTestStore? store,
  MirrorLedger? ledger,
  bool enabled = false,
  bool wifiOnly = true,
  bool isForeground = false,
  bool activate = true,
  Future<TainaResult<void>> Function(MirrorPreferences preferences)?
  persistPreferences,
}) {
  final selectedLibrary = library ?? MirrorTestLibrary();
  final selectedStore = store ?? MirrorTestStore(ledger: ledger);
  final events = StreamController<MirrorTransferEvent>.broadcast(sync: true);
  final api = _MirrorTestApi();
  final engine = MirrorEngine(
    session: _MirrorTestGateway(api),
    store: selectedStore,
    hasher: _MirrorTestHasher(),
    transfer: _MirrorTestTransfer(),
    ownerId: ownerId,
    progressBatchWindow: Duration.zero,
  );
  final owner = MirrorOwnerMirror(
    engine: engine,
    library: selectedLibrary,
    store: selectedStore,
    materializer: _MirrorTestMaterializer(),
    transferEvents: events.stream,
    startTransfer: () async => const Ok<void>(null),
    disposeTransfer: events.close,
    enabled: enabled,
    wifiOnly: wifiOnly,
    persistPreferences: persistPreferences,
  );
  owner.setForeground(isForeground);
  if (activate) owner.activate();
  return MirrorTestOwner(
    owner: owner,
    library: selectedLibrary,
    store: selectedStore,
    events: events,
  );
}

MirrorLedger mirrorLedger({
  required String ownerId,
  required Iterable<MirrorEntry> entries,
}) => MirrorLedger(
  ownerId: ownerId,
  entries: {for (final entry in entries) entry.assetId: entry},
);

MirrorEntry mirrorEntry({
  required String assetId,
  required MirrorState state,
  int? size = 100,
  double progress = 0,
}) => MirrorEntry(
  assetId: assetId,
  modificationDate: DateTime.utc(2026, 11, 18),
  filename: '$assetId.jpg',
  mime: 'image/jpeg',
  size: size,
  takenAt: null,
  sha256: null,
  localPath: null,
  state: state,
  rkey: null,
  backgroundTaskId: state == MirrorState.uploading ? 'task-$assetId' : null,
  attempts: state == MirrorState.failed ? 1 : 0,
  lastError: state == MirrorState.failed ? 'offline' : null,
  progress: progress,
  updatedAt: DateTime.utc(2026, 11, 18),
);

final class MirrorTestChanges extends ChangeNotifier {
  MirrorTestChanges(this.identity);

  Me? identity;

  void setIdentity(Me? value) {
    identity = value;
    notifyListeners();
  }
}

final class MirrorTestForeground implements MirrorForeground {
  MirrorTestForeground({this.isForeground = false});

  @override
  bool isForeground;

  void Function(bool isForeground)? _listener;

  @override
  void attach(void Function(bool isForeground) onChanged) {
    _listener = onChanged;
  }

  void set(bool value) {
    isForeground = value;
    _listener?.call(value);
  }

  @override
  void dispose() {
    _listener = null;
  }
}

Me mirrorTestIdentity({
  String tekoaId = 'tekoa-test',
  String avaId = 'ava-test',
}) => Me(
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

final class _MirrorTestGateway implements SessionGateway {
  _MirrorTestGateway(this.api);

  @override
  final TainaApi api;

  @override
  ThumbnailStore get thumbnails => ThumbnailStore(api: api);

  @override
  Me? get identity => null;

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async => outcome;
}

final class _MirrorTestApi implements TainaApi {
  @override
  Future<TainaResult<Page<FileRecord>>> manifest({
    String? after,
    int? limit,
    ManifestMode mode = ManifestMode.readable,
  }) async => Ok(Page(items: const [], nextCursor: null));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not used in mirror tests',
  );
}

final class _MirrorTestHasher implements MirrorAssetHasher {
  @override
  Future<TainaResult<MirrorHashResult>> hash(MirrorEntry entry) async =>
      const Ok(
        MirrorHashResult(
          sha256: 'mirror-test-hash',
          localPath: '/support/mirror-test',
        ),
      );
}

final class _MirrorTestTransfer implements MirrorTransfer {
  @override
  Future<TainaResult<void>> ensureStarted({
    required MirrorEntry entry,
    required String folderRkey,
  }) async => const Ok<void>(null);

  @override
  Future<TainaResult<void>> cancel(String backgroundTaskId) async =>
      const Ok<void>(null);
}

final class _MirrorTestMaterializer implements MirrorAssetMaterializer {
  @override
  Future<TainaResult<MaterializedAsset>> materialize(MirrorEntry entry) async =>
      const Ok(MaterializedAsset(path: '/support/mirror-test', size: 100));

  @override
  Future<TainaResult<void>> prune({required Set<String> retainedPaths}) async =>
      const Ok<void>(null);
}
