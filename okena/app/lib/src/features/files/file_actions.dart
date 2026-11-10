/// A file chosen from the system picker, already on local disk.
final class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.mime,
  });

  /// A readable local path. The box streams the bytes from it, so nothing
  /// here holds the whole file in memory.
  final String path;
  final String name;
  final String mime;
}

/// What the picker answered: a file, the person's cancel, or the platform's
/// own failure with a pt-BR sentence ready for the alert.
sealed class PickedFileOutcome {
  const PickedFileOutcome();
}

final class PickedFileSelected extends PickedFileOutcome {
  const PickedFileSelected(this.file);

  final PickedFile file;
}

final class PickedFileCancelled extends PickedFileOutcome {
  const PickedFileCancelled();
}

final class PickedFileFailed extends PickedFileOutcome {
  const PickedFileFailed(this.message);

  final String message;
}

/// The platform operations the files feature needs, behind an explicit
/// boundary so tests and previews are deterministic. The real implementation
/// touches file_picker, share_plus and open_filex; nothing here loads a whole
/// file into memory.
abstract class FileActions {
  /// Opens the system picker for one file. Cancelling is a value, not an
  /// error.
  Future<PickedFileOutcome> pick();

  /// Shares the already downloaded file at [path]. Returns a pt-BR failure
  /// message, or null on success.
  Future<String?> share(String path, {String? subject});

  /// Opens the already downloaded file at [path] with the platform's viewer.
  /// Returns a pt-BR failure message, or null on success.
  Future<String?> open(String path);
}
