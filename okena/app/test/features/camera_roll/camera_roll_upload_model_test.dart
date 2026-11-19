import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/camera_roll/camera_roll_upload_model.dart';
import 'package:okena_app/src/features/camera_roll/media_picker.dart';
import 'package:okena_core/okena_core.dart';

import 'support/camera_roll_fakes.dart';

FileRecord _record(UploadCall call) {
  return FileRecord(
    rkey: 'uploaded-${call.name}',
    cid: 'cid-${call.name}',
    blobCid: 'blob-${call.name}',
    sha256: 'sha-${call.name}',
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
    createdAt: '2026-03-11T09:30:00Z',
    updatedAt: '2026-03-11T09:30:00Z',
  );
}

void main() {
  test(
    'uploads selected photos and videos with their MIME types to root casa',
    () async {
      final api = CameraUploadApiFake();
      final session = CameraSessionFake(api: api);
      final picker = CameraMediaPickerFake()
        ..photosOutcome = MediaPickerSelected([
          picked('festa.jpg', 'image/jpeg'),
          picked('video.mp4', 'video/mp4'),
        ]);
      final model = CameraRollUploadModel(picker: picker, session: session);

      await model.pickPhotos();

      expect(api.uploadCalls.map((call) => call.name), [
        'festa.jpg',
        'video.mp4',
      ]);
      expect(api.uploadCalls.map((call) => call.mime), [
        'image/jpeg',
        'video/mp4',
      ]);
      expect(api.uploadCalls.every((call) => call.folderRkey == null), isTrue);
      expect(session.screenCalls, 2);
      expect(model.phase, CameraRollUploadPhase.complete);
      expect(model.total, 2);
      expect(model.attempted, 2);
      expect(model.succeeded, 2);
      expect(model.failedCount, 0);
      expect(model.anySuccess, isTrue);
      model.dispose();
    },
  );

  test(
    'a failed upload does not block later files or count as success',
    () async {
      final api = CameraUploadApiFake(
        uploadHandler: (call) async {
          if (call.name == 'falha.jpg') return const Err(NetworkError());
          return Ok(_record(call));
        },
      );
      final session = CameraSessionFake(api: api);
      final picker = CameraMediaPickerFake()
        ..photosOutcome = MediaPickerSelected([
          picked('falha.jpg', 'image/jpeg'),
          picked('depois.mp4', 'video/mp4'),
        ]);
      final model = CameraRollUploadModel(picker: picker, session: session);

      await model.pickPhotos();

      expect(api.uploadCalls.map((call) => call.name), [
        'falha.jpg',
        'depois.mp4',
      ]);
      expect(model.phase, CameraRollUploadPhase.failed);
      expect(model.attempted, 2);
      expect(model.succeeded, 1);
      expect(model.failedCount, 1);
      expect(model.anySuccess, isTrue);
      expect(model.canRetry, isTrue);
      expect(model.lastMessage, const NetworkError().message);
      model.dispose();
    },
  );

  test(
    'stop next lets the active upload finish and leaves later files pending',
    () async {
      final activeUpload = Completer<TainaResult<FileRecord>>();
      final api = CameraUploadApiFake(
        uploadHandler: (call) => activeUpload.future,
      );
      final session = CameraSessionFake(api: api);
      final picker = CameraMediaPickerFake()
        ..photosOutcome = MediaPickerSelected([
          picked('um.jpg', 'image/jpeg'),
          picked('dois.jpg', 'image/jpeg'),
          picked('tres.mp4', 'video/mp4'),
        ]);
      final model = CameraRollUploadModel(picker: picker, session: session);

      final picking = model.pickPhotos();
      await Future<void>.delayed(Duration.zero);
      expect(api.uploadCalls, hasLength(1));

      model.stopNext();
      expect(model.stopRequested, isTrue);
      activeUpload.complete(Ok(_record(api.uploadCalls.first)));
      await picking;

      expect(api.uploadCalls, hasLength(1));
      expect(model.phase, CameraRollUploadPhase.stopped);
      expect(model.succeeded, 1);
      expect(model.unstarted, 2);
      expect(model.canRetry, isTrue);
      model.dispose();
    },
  );

  test(
    'retry includes failed and unstarted files but skips successes',
    () async {
      final failedUpload = Completer<TainaResult<FileRecord>>();
      var uploadCalls = 0;
      final api = CameraUploadApiFake(
        uploadHandler: (call) async {
          uploadCalls += 1;
          if (call.name == 'dois.jpg' && uploadCalls == 2) {
            return failedUpload.future;
          }
          return Ok(_record(call));
        },
      );
      final session = CameraSessionFake(api: api);
      final picker = CameraMediaPickerFake()
        ..photosOutcome = MediaPickerSelected([
          picked('um.jpg', 'image/jpeg'),
          picked('dois.jpg', 'image/jpeg'),
          picked('tres.mp4', 'video/mp4'),
        ]);
      final model = CameraRollUploadModel(picker: picker, session: session);

      final picking = model.pickPhotos();
      await Future<void>.delayed(Duration.zero);
      expect(api.uploadCalls.map((call) => call.name), ['um.jpg', 'dois.jpg']);
      model.stopNext();
      failedUpload.complete(const Err(NetworkError()));
      await picking;

      expect(model.phase, CameraRollUploadPhase.stopped);
      expect(model.succeeded, 1);
      expect(model.failedCount, 1);
      expect(model.unstarted, 1);
      await model.retryRemaining();

      expect(api.uploadCalls.map((call) => call.name), [
        'um.jpg',
        'dois.jpg',
        'dois.jpg',
        'tres.mp4',
      ]);
      expect(model.phase, CameraRollUploadPhase.complete);
      expect(model.attempted, 3);
      expect(model.succeeded, 3);
      expect(model.failedCount, 0);
      model.dispose();
    },
  );

  test('cancellation leaves the model idle without uploading', () async {
    final api = CameraUploadApiFake();
    final session = CameraSessionFake(api: api);
    final picker = CameraMediaPickerFake()
      ..photosOutcome = const MediaPickerCancelled();
    final model = CameraRollUploadModel(picker: picker, session: session);

    await model.pickPhotos();

    expect(model.phase, CameraRollUploadPhase.idle);
    expect(model.total, 0);
    expect(model.lastMessage, isNull);
    expect(api.uploadCalls, isEmpty);
    model.dispose();
  });

  test(
    'interruption stops new starts and retry resumes the remaining files',
    () async {
      final activeUpload = Completer<TainaResult<FileRecord>>();
      final api = CameraUploadApiFake(
        uploadHandler: (call) {
          if (call.name == 'um.jpg') return activeUpload.future;
          return Future.value(Ok(_record(call)));
        },
      );
      final session = CameraSessionFake(api: api);
      final picker = CameraMediaPickerFake()
        ..photosOutcome = MediaPickerSelected([
          picked('um.jpg', 'image/jpeg'),
          picked('dois.mp4', 'video/mp4'),
        ]);
      final model = CameraRollUploadModel(picker: picker, session: session);

      final picking = model.pickPhotos();
      await Future<void>.delayed(Duration.zero);
      model.interrupt();

      expect(model.phase, CameraRollUploadPhase.stopped);
      expect(model.interrupted, isTrue);
      expect(model.busy, isTrue);
      expect(model.canRetry, isFalse);
      activeUpload.complete(Ok(_record(api.uploadCalls.first)));
      await picking;

      expect(api.uploadCalls, hasLength(1));
      expect(model.unstarted, 1);
      expect(model.canRetry, isTrue);
      await model.retryRemaining();

      expect(api.uploadCalls.map((call) => call.name), ['um.jpg', 'dois.mp4']);
      expect(model.phase, CameraRollUploadPhase.complete);
      expect(model.interrupted, isFalse);
      expect(model.succeeded, 2);
      model.dispose();
    },
  );

  test(
    'interruption while the picker is pending stops the returned selection',
    () async {
      final pendingPicker = Completer<MediaPickerOutcome>();
      final api = CameraUploadApiFake();
      final session = CameraSessionFake(api: api);
      final picker = CameraMediaPickerFake()
        ..photosFuture = pendingPicker.future;
      final model = CameraRollUploadModel(picker: picker, session: session);

      final picking = model.pickPhotos();
      expect(model.busy, isTrue);
      expect(model.phase, CameraRollUploadPhase.picking);

      model.interrupt();
      expect(model.interrupted, isTrue);
      expect(model.stopRequested, isTrue);

      pendingPicker.complete(
        MediaPickerSelected([
          picked('um.jpg', 'image/jpeg'),
          picked('dois.mp4', 'video/mp4'),
        ]),
      );
      await picking;

      expect(api.uploadCalls, isEmpty);
      expect(model.phase, CameraRollUploadPhase.stopped);
      expect(model.interrupted, isTrue);
      expect(model.unstarted, 2);
      expect(model.canRetry, isTrue);

      await model.retryRemaining();

      expect(api.uploadCalls.map((call) => call.name), ['um.jpg', 'dois.mp4']);
      expect(model.phase, CameraRollUploadPhase.complete);
      expect(model.interrupted, isFalse);
      expect(model.succeeded, 2);
      model.dispose();
    },
  );

  test(
    'picker programmer errors propagate and leave the model ready for action',
    () async {
      final api = CameraUploadApiFake();
      final session = CameraSessionFake(api: api);
      final picker = CameraMediaPickerFake()
        ..photosFailure = StateError('unexpected')
        ..photosOutcome = MediaPickerSelected([
          picked('depois.jpg', 'image/jpeg'),
        ]);
      final model = CameraRollUploadModel(picker: picker, session: session);

      await expectLater(model.pickPhotos(), throwsA(isA<StateError>()));

      expect(model.busy, isFalse);
      expect(model.phase, CameraRollUploadPhase.idle);
      picker.photosFailure = null;
      await model.pickPhotos();

      expect(api.uploadCalls.map((call) => call.name), ['depois.jpg']);
      expect(model.phase, CameraRollUploadPhase.complete);
      model.dispose();
    },
  );

  test(
    'upload programmer errors propagate and leave the model ready for action',
    () async {
      var shouldFail = true;
      final api = CameraUploadApiFake(
        uploadHandler: (call) async {
          if (shouldFail) {
            shouldFail = false;
            throw StateError('unexpected');
          }
          return Ok(_record(call));
        },
      );
      final session = CameraSessionFake(api: api);
      final picker = CameraMediaPickerFake()
        ..photosOutcome = MediaPickerSelected([
          picked('foto.jpg', 'image/jpeg'),
        ]);
      final model = CameraRollUploadModel(picker: picker, session: session);

      await expectLater(model.pickPhotos(), throwsA(isA<StateError>()));

      expect(model.busy, isFalse);
      await model.pickPhotos();

      expect(api.uploadCalls.map((call) => call.name), [
        'foto.jpg',
        'foto.jpg',
      ]);
      expect(model.phase, CameraRollUploadPhase.complete);
      model.dispose();
    },
  );

  test('recover lost data resumes the recovered selection', () async {
    final api = CameraUploadApiFake();
    final session = CameraSessionFake(api: api);
    final picker = CameraMediaPickerFake()
      ..lostDataOutcome = MediaPickerSelected([
        picked('recuperada.mp4', 'video/mp4'),
      ]);
    final model = CameraRollUploadModel(picker: picker, session: session);

    await model.recoverLostData();

    expect(picker.lostDataCalls, 1);
    expect(api.uploadCalls.map((call) => call.name), ['recuperada.mp4']);
    expect(api.uploadCalls.single.folderRkey, isNull);
    expect(session.screenCalls, 1);
    expect(model.phase, CameraRollUploadPhase.complete);
    model.dispose();
  });

  test('selected media list cannot be modified', () {
    final selection = MediaPickerSelected([picked('foto.jpg', 'image/jpeg')]);

    expect(
      () => selection.files.add(picked('outro.jpg', 'image/jpeg')),
      throwsUnsupportedError,
    );
  });
}
