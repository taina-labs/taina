import '../files/file_actions.dart';

/// What the system media picker answered: a selection, cancellation, or a
/// pt-BR failure message.
sealed class MediaPickerOutcome {
  const MediaPickerOutcome();
}

final class MediaPickerSelected extends MediaPickerOutcome {
  MediaPickerSelected(Iterable<PickedFile> files)
    : files = List.unmodifiable(files);

  final List<PickedFile> files;
}

final class MediaPickerCancelled extends MediaPickerOutcome {
  const MediaPickerCancelled();
}

final class MediaPickerFailed extends MediaPickerOutcome {
  const MediaPickerFailed(this.message);

  final String message;
}

/// The platform operations needed by manual photo and video uploads.
abstract interface class MediaPicker {
  Future<MediaPickerOutcome> pickPhotos();

  Future<MediaPickerOutcome> takePhoto();

  Future<MediaPickerOutcome> recoverLostData();
}
