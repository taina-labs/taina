import 'package:okena_app/src/features/camera_roll/media_picker.dart';
import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

final class UploadCall {
  const UploadCall({
    required this.filePath,
    required this.name,
    required this.mime,
    required this.folderRkey,
  });

  final String filePath;
  final String name;
  final String mime;
  final String? folderRkey;
}

typedef UploadHandler = Future<TainaResult<FileRecord>> Function(
  UploadCall call,
);

final class CameraUploadApiFake implements TainaApi {
  CameraUploadApiFake({UploadHandler? uploadHandler})
    : uploadHandler = uploadHandler ?? _successfulUpload;

  UploadHandler uploadHandler;
  final List<UploadCall> uploadCalls = [];
  int folderContentsCalls = 0;

  @override
  Future<TainaResult<FileRecord>> upload({
    required String filePath,
    required String name,
    required String mime,
    String? folderRkey,
  }) async {
    final call = UploadCall(
      filePath: filePath,
      name: name,
      mime: mime,
      folderRkey: folderRkey,
    );
    uploadCalls.add(call);
    return uploadHandler(call);
  }

  @override
  Future<TainaResult<FolderContents>> folderContents({
    String? folderRkey,
    int? limit,
    String? cursor,
    Sort? sort,
  }) async {
    folderContentsCalls += 1;
    return Ok(
      FolderContents(folders: const [], items: const [], nextCursor: null),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  static Future<TainaResult<FileRecord>> _successfulUpload(
    UploadCall call,
  ) async {
    return Ok(_file(call));
  }

  static FileRecord _file(UploadCall call) {
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
}

final class CameraSessionFake implements SessionGateway {
  CameraSessionFake({required this.api})
    : thumbnails = ThumbnailStore(api: api);

  @override
  final CameraUploadApiFake api;

  @override
  final ThumbnailStore thumbnails;

  int screenCalls = 0;

  @override
  Me? get identity => null;

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async {
    screenCalls += 1;
    return outcome;
  }
}

final class CameraMediaPickerFake implements MediaPicker {
  MediaPickerOutcome photosOutcome = const MediaPickerCancelled();
  MediaPickerOutcome cameraOutcome = const MediaPickerCancelled();
  MediaPickerOutcome lostDataOutcome = const MediaPickerCancelled();
  Future<MediaPickerOutcome>? photosFuture;
  Object? photosFailure;
  int photoCalls = 0;
  int cameraCalls = 0;
  int lostDataCalls = 0;

  @override
  Future<MediaPickerOutcome> pickPhotos() async {
    photoCalls += 1;
    if (photosFailure case final failure?) throw failure;
    if (photosFuture case final future?) return future;
    return photosOutcome;
  }

  @override
  Future<MediaPickerOutcome> takePhoto() async {
    cameraCalls += 1;
    return cameraOutcome;
  }

  @override
  Future<MediaPickerOutcome> recoverLostData() async {
    lostDataCalls += 1;
    return lostDataOutcome;
  }
}

PickedFile picked(String name, String mime) {
  return PickedFile(path: '/local/$name', name: name, mime: mime);
}
