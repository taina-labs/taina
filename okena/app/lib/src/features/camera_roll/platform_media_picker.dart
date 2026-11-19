import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;

import '../files/file_actions.dart';
import '../files/files_logic.dart';
import 'media_picker.dart';

/// The production media picker. It keeps the plugin at the platform edge and
/// passes local paths through without loading or transforming file bytes.
final class PlatformMediaPicker implements MediaPicker {
  PlatformMediaPicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  static const String _selectionFailure =
      'Não foi possível abrir a seleção de fotos e vídeos. Tente de novo.';
  static const String _cameraFailure =
      'Não foi possível abrir a câmera. Confira a permissão e tente de novo.';

  @override
  Future<MediaPickerOutcome> pickPhotos() async {
    try {
      final files = await _imagePicker.pickMultipleMedia(
        requestFullMetadata: false,
      );
      if (files.isEmpty) return const MediaPickerCancelled();
      return MediaPickerSelected(files.map(_pickedFile));
    } on Exception {
      return const MediaPickerFailed(_selectionFailure);
    }
  }

  @override
  Future<MediaPickerOutcome> takePhoto() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        requestFullMetadata: false,
      );
      if (file == null) return const MediaPickerCancelled();
      return MediaPickerSelected([_pickedFile(file)]);
    } on Exception {
      return const MediaPickerFailed(_cameraFailure);
    }
  }

  @override
  Future<MediaPickerOutcome> recoverLostData() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const MediaPickerCancelled();
    }

    try {
      final response = await _imagePicker.retrieveLostData();
      if (response.exception != null) {
        return const MediaPickerFailed(_selectionFailure);
      }
      final files =
          response.files ?? [if (response.file != null) response.file!];
      if (files.isEmpty) return const MediaPickerCancelled();
      return MediaPickerSelected(files.map(_pickedFile));
    } on Exception {
      return const MediaPickerFailed(_selectionFailure);
    }
  }

  PickedFile _pickedFile(XFile file) {
    return PickedFile(
      path: file.path,
      name: file.name,
      mime: FilesLogic.mimeFor(file.name),
    );
  }
}
