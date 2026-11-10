import 'package:okena_core/src/internal/equality.dart';
import 'package:okena_core/src/json/api_coding.dart';

/// The portrait of the storage that `GET /storage` answers with.
final class StorageStats {
  const StorageStats({
    required this.usedBytes,
    required this.quotaBytes,
    required this.byKind,
    required this.files,
    required this.photos,
    required this.trash,
  });

  factory StorageStats.fromJson(JsonReader reader) {
    return StorageStats(
      usedBytes: reader.integer('used_bytes'),
      quotaBytes: reader.integerOrNull('quota_bytes'),
      byKind: StorageByKind.fromJson(reader.object('by_kind')),
      files: reader.integer('files'),
      photos: reader.integer('photos'),
      trash: StorageTrash.fromJson(reader.object('trash')),
    );
  }

  final int usedBytes;
  final int? quotaBytes;
  final StorageByKind byKind;
  final int files;
  final int photos;
  final StorageTrash trash;

  @override
  bool operator ==(Object other) =>
      other is StorageStats &&
      other.usedBytes == usedBytes &&
      other.quotaBytes == quotaBytes &&
      other.byKind == byKind &&
      other.files == files &&
      other.photos == photos &&
      other.trash == trash;

  @override
  int get hashCode => Object.hash(
    StorageStats,
    usedBytes,
    quotaBytes,
    byKind,
    files,
    photos,
    trash,
  );
}

/// Bytes at rest, by kind of content.
final class StorageByKind {
  const StorageByKind({
    required this.photos,
    required this.videos,
    required this.documents,
    required this.others,
  });

  factory StorageByKind.fromJson(JsonReader reader) {
    return StorageByKind(
      photos: reader.integer('photos'),
      videos: reader.integer('videos'),
      documents: reader.integer('documents'),
      others: reader.integer('others'),
    );
  }

  final int photos;
  final int videos;
  final int documents;
  final int others;

  @override
  bool operator ==(Object other) =>
      other is StorageByKind &&
      other.photos == photos &&
      other.videos == videos &&
      other.documents == documents &&
      other.others == others;

  @override
  int get hashCode =>
      Object.hash(StorageByKind, photos, videos, documents, others);
}

/// What sits in the trash: how many items and the bytes they hold.
final class StorageTrash {
  const StorageTrash({required this.count, required this.bytes});

  factory StorageTrash.fromJson(JsonReader reader) {
    return StorageTrash(
      count: reader.integer('count'),
      bytes: reader.integer('bytes'),
    );
  }

  final int count;
  final int bytes;

  @override
  bool operator ==(Object other) =>
      other is StorageTrash && other.count == count && other.bytes == bytes;

  @override
  int get hashCode => Object.hash(StorageTrash, count, bytes);
}

/// The community's health panel: storage, queued work and the last backup, in
/// plain words.
final class Saude {
  const Saude({
    required this.storage,
    required this.jobs,
    required this.backup,
  });

  factory Saude.fromJson(JsonReader reader) {
    return Saude(
      storage: StorageStats.fromJson(reader.object('storage')),
      jobs: reader.integerMap('jobs'),
      backup: SaudeBackup.fromJson(reader.object('backup')),
    );
  }

  final StorageStats storage;

  /// Work waiting or running, by queue.
  final Map<String, int> jobs;
  final SaudeBackup backup;

  @override
  bool operator ==(Object other) =>
      other is Saude &&
      other.storage == storage &&
      mapEquals(other.jobs, jobs) &&
      other.backup == backup;

  @override
  int get hashCode => Object.hash(
    Saude,
    storage,
    Object.hashAllUnordered([
      for (final entry in jobs.entries) Object.hash(entry.key, entry.value),
    ]),
    backup,
  );
}

/// When the last backup ran and how much it carried; never, so far.
final class SaudeBackup {
  const SaudeBackup({required this.at, required this.bytes});

  factory SaudeBackup.fromJson(JsonReader reader) {
    return SaudeBackup(
      at: reader.stringOrNull('at'),
      bytes: reader.integerOrNull('bytes'),
    );
  }

  final String? at;
  final int? bytes;

  @override
  bool operator ==(Object other) =>
      other is SaudeBackup && other.at == at && other.bytes == bytes;

  @override
  int get hashCode => Object.hash(SaudeBackup, at, bytes);
}
