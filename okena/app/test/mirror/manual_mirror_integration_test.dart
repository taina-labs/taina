import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/camera_roll/camera_roll_upload_model.dart';
import 'package:okena_app/src/features/camera_roll/media_picker.dart';
import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/mirror/mirror_asset_hasher.dart';
import 'package:okena_app/src/mirror/mirror_engine.dart';
import 'package:okena_app/src/mirror/mirror_transfer.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../features/camera_roll/support/camera_roll_fakes.dart';

final _now = DateTime.utc(2026, 11, 18, 12);
final _modified = DateTime.utc(2026, 11, 17, 10);

MirrorAsset _asset({required String id, required String filename}) =>
    MirrorAsset(
      assetId: id,
      modificationDate: _modified,
      filename: filename,
      mime: 'image/jpeg',
      size: 1,
      takenAt: null,
    );

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

class _FakeHasher implements MirrorAssetHasher {
  _FakeHasher(this.hashes, this.paths);

  final Map<String, String> hashes;
  final Map<String, String> paths;

  @override
  Future<TainaResult<MirrorHashResult>> hash(MirrorEntry entry) async {
    final hash = hashes[entry.assetId];
    if (hash == null) {
      return const Err(InvalidResponseError('test hash is missing'));
    }
    return Ok(
      MirrorHashResult(
        sha256: hash,
        localPath: paths[entry.assetId] ?? '/mirror/${entry.assetId}.jpg',
      ),
    );
  }
}

class _TransferCall {
  const _TransferCall(this.entry, this.folderRkey);

  final MirrorEntry entry;
  final String folderRkey;
}

class _RecordingTransfer implements MirrorTransfer {
  final List<_TransferCall> started = [];
  final List<String> cancelled = [];

  @override
  Future<TainaResult<void>> ensureStarted({
    required MirrorEntry entry,
    required String folderRkey,
  }) async {
    started.add(_TransferCall(entry, folderRkey));
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<void>> cancel(String backgroundTaskId) async {
    cancelled.add(backgroundTaskId);
    return const Ok<void>(null);
  }
}

MirrorEngine _engine({
  required SessionGateway session,
  required MirrorStore store,
  required MirrorAssetHasher hasher,
  required MirrorTransfer transfer,
}) => MirrorEngine(
  session: session,
  store: store,
  hasher: hasher,
  transfer: transfer,
  ownerId: 'manual-mirror-test',
  random: math.Random(42),
  clock: () => _now,
  progressBatchWindow: Duration.zero,
);

Future<FileRecord> _uploadManually(
  FakeTainaApi api, {
  required String path,
  required String name,
}) async {
  final picker = CameraMediaPickerFake()
    ..photosOutcome = MediaPickerSelected([
      PickedFile(path: path, name: name, mime: 'image/jpeg'),
    ]);
  final model = CameraRollUploadModel(
    picker: picker,
    session: _TestSession(api),
  );

  await model.pickPhotos();

  expect(model.phase, CameraRollUploadPhase.complete);
  expect(model.succeeded, 1);
  model.dispose();
  return _fileNamed(api, name);
}

Future<FileRecord> _fileNamed(FakeTainaApi api, String name) async {
  final response = await api.manifest(mode: ManifestMode.mirror);
  expect(response, isA<Ok<Page<FileRecord>>>());
  final files = (response as Ok<Page<FileRecord>>).value.items
      .where((file) => file.name == name)
      .toList();
  expect(files, hasLength(1));
  return files.single;
}

FileRecord _uploadedRecord(UploadCall call) => FileRecord(
  rkey: 'manual-${call.name}',
  cid: 'cid-${call.name}',
  blobCid: 'blob-${call.name}',
  sha256: 'manual-${call.name}',
  name: call.name,
  mime: call.mime,
  size: 1,
  zona: Zona.casa,
  folder: call.folderRkey,
  takenAt: null,
  width: null,
  height: null,
  rendition: Rendition.none,
  deletedAt: null,
  createdAt: '2026-11-18T12:00:00Z',
  updatedAt: '2026-11-18T12:00:00Z',
);

void main() {
  test('manual root-casa upload is reused while mirror schedules only Y to its camera-roll folder', () async {
    final directory = await Directory.systemTemp.createTemp(
      'manual-mirror-integration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final xPath = '${directory.path}/X.jpg';
    final yPath = '${directory.path}/Y.jpg';
    await File(xPath).writeAsBytes([1, 2, 3]);
    await File(yPath).writeAsBytes([4, 5, 6]);

    final api = FakeTainaApi(delay: Duration.zero);
    final manualX = await _uploadManually(api, path: xPath, name: 'X.jpg');
    expect(manualX.zona, Zona.casa);
    expect(manualX.folder, isNull);

    final transfer = _RecordingTransfer();
    final store = InMemoryMirrorStore();
    final engine = _engine(
      session: _TestSession(api),
      store: store,
      hasher: _FakeHasher(
        {'asset-x': manualX.sha256, 'asset-y': 'f' * 64},
        {'asset-x': xPath, 'asset-y': yPath},
      ),
      transfer: transfer,
    );

    final reconciled = await engine.reconcile([
      _asset(id: 'asset-x', filename: 'X.jpg'),
      _asset(id: 'asset-y', filename: 'Y.jpg'),
    ]);

    expect(reconciled.isSuccess, isTrue);
    expect(transfer.started.map((call) => call.entry.assetId), ['asset-y']);
    expect(transfer.started, hasLength(1));
    final ledger = (await store.load()).value!;
    expect(ledger.entries['asset-x']!.state, MirrorState.uploaded);
    expect(ledger.entries['asset-x']!.rkey, manualX.rkey);
    expect(ledger.entries['asset-y']!.state, MirrorState.uploading);

    final foldersResult = await api.listFolders();
    expect(foldersResult, isA<Ok<List<Folder>>>());
    final cameraFolder = (foldersResult as Ok<List<Folder>>).value.singleWhere(
      (folder) => folder.name == MirrorEngine.destinationFolderName,
    );
    expect(cameraFolder.zona, Zona.casa);
    expect(cameraFolder.folder, isNull);
    expect(transfer.started.single.folderRkey, cameraFolder.rkey);

    final storedManualX = await api.file(rkey: manualX.rkey);
    expect(storedManualX, isA<Ok<FileRecord>>());
    expect((storedManualX as Ok<FileRecord>).value, manualX);
    expect(await _fileNamed(api, 'X.jpg'), manualX);
  });

  test(
    'MirrorEngine.cancel isolation leaves a pending manual upload running',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'manual-mirror-cancel-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final manualPath = '${directory.path}/manual.jpg';
      await File(manualPath).writeAsBytes([1, 2, 3]);

      final pendingUpload = Completer<TainaResult<FileRecord>>();
      final api = CameraUploadApiFake(
        uploadHandler: (_) => pendingUpload.future,
      );
      final session = CameraSessionFake(api: api);
      final picker = CameraMediaPickerFake()
        ..photosOutcome = MediaPickerSelected([
          PickedFile(path: manualPath, name: 'manual.jpg', mime: 'image/jpeg'),
        ]);
      final model = CameraRollUploadModel(picker: picker, session: session);
      final entry = MirrorEntry(
        assetId: 'mirror-asset',
        modificationDate: _modified,
        filename: 'mirror.jpg',
        mime: 'image/jpeg',
        size: 1,
        takenAt: null,
        sha256: 'a' * 64,
        localPath: '/mirror/mirror.jpg',
        state: MirrorState.uploading,
        rkey: null,
        backgroundTaskId: 'native-mirror-task',
        attempts: 0,
        lastError: null,
        progress: 0,
        updatedAt: _now,
      );
      final store = InMemoryMirrorStore(
        MirrorLedger(
          ownerId: 'manual-mirror-test',
          destinationFolderRkey: 'camera-folder',
          entries: {entry.assetId: entry},
        ),
      );
      final transfer = _RecordingTransfer();
      final engine = _engine(
        session: session,
        store: store,
        hasher: _FakeHasher(const {}, const {}),
        transfer: transfer,
      );

      final picking = model.pickPhotos();
      await Future<void>.delayed(Duration.zero);
      expect(api.uploadCalls, hasLength(1));
      expect(model.busy, isTrue);

      // This uses the engine's mirror-task cancellation boundary, not
      // MirrorOwnerMirror preference orchestration. Only its native task ID
      // is visible to the cancellation seam.
      expect((await engine.cancel(assetId: entry.assetId)).isSuccess, isTrue);
      expect(transfer.cancelled, ['native-mirror-task']);

      pendingUpload.complete(Ok(_uploadedRecord(api.uploadCalls.single)));
      await picking;

      expect(model.phase, CameraRollUploadPhase.complete);
      expect(model.succeeded, 1);
      expect(api.uploadCalls, hasLength(1));
      expect(api.uploadCalls.single.folderRkey, isNull);
      final persisted = (await store.load()).value!;
      expect(persisted.entries[entry.assetId]!.state, MirrorState.queued);
      expect(persisted.entries[entry.assetId]!.backgroundTaskId, isNull);
      model.dispose();
    },
  );

  test('trashing a manual upload suppresses the same mirror asset without resurrection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'manual-mirror-trash-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final xPath = '${directory.path}/X.jpg';
    await File(xPath).writeAsBytes([1, 2, 3]);

    final api = FakeTainaApi(delay: Duration.zero);
    final manualX = await _uploadManually(api, path: xPath, name: 'X.jpg');
    expect((await api.deleteFile(rkey: manualX.rkey)).isSuccess, isTrue);
    final trashedX = await api.file(rkey: manualX.rkey);
    expect(trashedX, isA<Ok<FileRecord>>());
    final tombstone = (trashedX as Ok<FileRecord>).value;
    expect(tombstone.deletedAt, isNotNull);

    final transfer = _RecordingTransfer();
    final engine = _engine(
      session: _TestSession(api),
      store: InMemoryMirrorStore(),
      hasher: _FakeHasher({'asset-x': manualX.sha256}, {'asset-x': xPath}),
      transfer: transfer,
    );

    final reconciled = await engine.reconcile([
      _asset(id: 'asset-x', filename: 'X.jpg'),
    ]);

    expect(reconciled.isSuccess, isTrue);
    expect(transfer.started, isEmpty);
    final stillTrashed = await api.file(rkey: manualX.rkey);
    expect(stillTrashed, isA<Ok<FileRecord>>());
    expect((stillTrashed as Ok<FileRecord>).value, tombstone);
    expect(await _fileNamed(api, 'X.jpg'), tombstone);
  });
}
