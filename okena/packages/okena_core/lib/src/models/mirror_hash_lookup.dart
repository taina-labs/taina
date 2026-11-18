import 'package:okena_core/src/json/api_coding.dart';
import 'package:okena_core/src/models/wire.dart';

/// The result of looking up a file hash for a one-way mirror.
sealed class MirrorHashLookup {
  const MirrorHashLookup();

  factory MirrorHashLookup.fromJson(JsonReader reader) {
    return switch (reader.string('status')) {
      'present' => MirrorHashPresent(
        file: FileRecord.fromJson(reader.object('file')),
      ),
      'suppressed' => _suppressedFromJson(reader),
      final status => throw FormatException(
        '${reader.label}.status: unknown "$status"',
      ),
    };
  }
}

/// This person's live file has the requested hash.
final class MirrorHashPresent extends MirrorHashLookup {
  const MirrorHashPresent({required this.file});

  final FileRecord file;

  @override
  bool operator ==(Object other) =>
      other is MirrorHashPresent && other.file == file;

  @override
  int get hashCode => Object.hash(MirrorHashPresent, file);
}

/// This person's trash or purge tombstone suppresses the requested hash.
final class MirrorHashSuppressed extends MirrorHashLookup {
  const MirrorHashSuppressed();

  @override
  bool operator ==(Object other) => other is MirrorHashSuppressed;

  @override
  int get hashCode => (MirrorHashSuppressed).hashCode;
}

MirrorHashLookup _suppressedFromJson(JsonReader reader) {
  if (!reader.json.containsKey('file') || reader.json['file'] != null) {
    throw FormatException('${reader.label}.file: expected null');
  }
  return const MirrorHashSuppressed();
}
