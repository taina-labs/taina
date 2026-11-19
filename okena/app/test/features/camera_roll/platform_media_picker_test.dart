import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:okena_app/src/features/camera_roll/media_picker.dart';
import 'package:okena_app/src/features/camera_roll/platform_media_picker.dart';

final class _ImagePickerFake extends ImagePicker {
  List<XFile> media = [];
  XFile? cameraImage;
  LostDataResponse lostData = LostDataResponse.empty();
  Object? failure;
  bool? requestedFullMetadata;
  ImageSource? cameraSource;
  int lostDataCalls = 0;

  @override
  Future<List<XFile>> pickMultipleMedia({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    requestedFullMetadata = requestFullMetadata;
    if (failure case final error?) throw error;
    return media;
  }

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    requestedFullMetadata = requestFullMetadata;
    cameraSource = source;
    if (failure case final error?) throw error;
    return cameraImage;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    lostDataCalls += 1;
    if (failure case final error?) throw error;
    return lostData;
  }
}

void main() {
  test(
    'multi-select maps local paths, names and photo/video MIME types',
    () async {
      final imagePicker = _ImagePickerFake()
        ..media = [XFile('/media/festa.jpg'), XFile('/media/filme.mp4')];
      final picker = PlatformMediaPicker(imagePicker: imagePicker);

      final outcome = await picker.pickPhotos();

      expect(imagePicker.requestedFullMetadata, isFalse);
      expect(outcome, isA<MediaPickerSelected>());
      final files = (outcome as MediaPickerSelected).files;
      expect(files.map((file) => file.path), [
        '/media/festa.jpg',
        '/media/filme.mp4',
      ]);
      expect(files.map((file) => file.name), ['festa.jpg', 'filme.mp4']);
      expect(files.map((file) => file.mime), ['image/jpeg', 'video/mp4']);
    },
  );

  test('camera takes one unmodified photo', () async {
    final imagePicker = _ImagePickerFake()
      ..cameraImage = XFile('/camera/captura.heic');
    final picker = PlatformMediaPicker(imagePicker: imagePicker);

    final outcome = await picker.takePhoto();

    expect(imagePicker.cameraSource, ImageSource.camera);
    expect(imagePicker.requestedFullMetadata, isFalse);
    expect(outcome, isA<MediaPickerSelected>());
    final file = (outcome as MediaPickerSelected).files.single;
    expect(file.path, '/camera/captura.heic');
    expect(file.mime, 'image/heic');
  });

  test('Android lost media can be recovered', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final imagePicker = _ImagePickerFake()
      ..lostData = LostDataResponse(files: [XFile('/recovered/filme.mp4')]);
    final picker = PlatformMediaPicker(imagePicker: imagePicker);

    final outcome = await picker.recoverLostData();

    expect(imagePicker.lostDataCalls, 1);
    expect(outcome, isA<MediaPickerSelected>());
    final file = (outcome as MediaPickerSelected).files.single;
    expect(file.path, '/recovered/filme.mp4');
    expect(file.mime, 'video/mp4');
  });

  test('picker exceptions are returned with action-specific copy', () async {
    final selectionPicker = _ImagePickerFake()
      ..failure = PlatformException(code: 'denied');
    final cameraPicker = _ImagePickerFake()
      ..failure = PlatformException(code: 'denied');

    final selection = await PlatformMediaPicker(imagePicker: selectionPicker)
        .pickPhotos();
    final camera = await PlatformMediaPicker(imagePicker: cameraPicker)
        .takePhoto();

    expect(
      (selection as MediaPickerFailed).message,
      'Não foi possível abrir a seleção de fotos e vídeos. Tente de novo.',
    );
    expect(
      (camera as MediaPickerFailed).message,
      'Não foi possível abrir a câmera. Confira a permissão e tente de novo.',
    );
  });

  test('programmer errors from ImagePicker propagate', () async {
    final picker = PlatformMediaPicker(
      imagePicker: _ImagePickerFake()..failure = StateError('unexpected'),
    );

    await expectLater(picker.pickPhotos(), throwsA(isA<StateError>()));
  });
}
