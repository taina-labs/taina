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
    this.byZone,
    this.diskBytes,
    this.videos,
    this.diskTotalBytes,
    this.diskFreeBytes,
  });

  factory StorageStats.fromJson(JsonReader reader) {
    final diskBytes =
        reader.integerOrNull('disk_bytes') ??
        reader.integerOrNull('disk_total_bytes');
    return StorageStats(
      usedBytes: reader.integer('used_bytes'),
      quotaBytes: reader.integerOrNull('quota_bytes'),
      byKind: StorageByKind.fromJson(reader.object('by_kind')),
      files: reader.integer('files'),
      photos: reader.integer('photos'),
      trash: StorageTrash.fromJson(reader.object('trash')),
      byZone: switch (reader.objectOrNull('by_zone')) {
        final zone? => StorageByZone.fromJson(zone),
        null => null,
      },
      diskBytes: diskBytes,
      videos: reader.integerOrNull('videos'),
      diskTotalBytes: reader.integerOrNull('disk_total_bytes') ?? diskBytes,
      diskFreeBytes: reader.integerOrNull('disk_free_bytes'),
    );
  }

  final int usedBytes;
  final int? quotaBytes;
  final StorageByZone? byZone;
  final int? diskBytes;
  final int? videos;

  /// Legacy physical-disk names retained for boxes that still send them.
  final int? diskTotalBytes;
  final int? diskFreeBytes;
  final StorageByKind byKind;
  final int files;
  final int photos;
  final StorageTrash trash;

  @override
  bool operator ==(Object other) =>
      other is StorageStats &&
      other.usedBytes == usedBytes &&
      other.quotaBytes == quotaBytes &&
      other.byZone == byZone &&
      other.diskBytes == diskBytes &&
      other.videos == videos &&
      other.diskTotalBytes == diskTotalBytes &&
      other.diskFreeBytes == diskFreeBytes &&
      other.byKind == byKind &&
      other.files == files &&
      other.photos == photos &&
      other.trash == trash;

  @override
  int get hashCode => Object.hash(
    StorageStats,
    usedBytes,
    quotaBytes,
    byZone,
    diskBytes,
    videos,
    diskTotalBytes,
    diskFreeBytes,
    byKind,
    files,
    photos,
    trash,
  );
}

/// Bytes currently attributed to each community zone.
final class StorageByZone {
  const StorageByZone({
    required this.casa,
    required this.praca,
    required this.lixeira,
  });

  factory StorageByZone.fromJson(JsonReader reader) {
    return StorageByZone(
      casa: reader.integer('casa'),
      praca: reader.integer('praca'),
      lixeira: reader.integer('lixeira'),
    );
  }

  final int casa;
  final int praca;
  final int lixeira;

  @override
  bool operator ==(Object other) =>
      other is StorageByZone &&
      other.casa == casa &&
      other.praca == praca &&
      other.lixeira == lixeira;

  @override
  int get hashCode => Object.hash(StorageByZone, casa, praca, lixeira);
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
    this.summary,
    this.update,
  });

  factory Saude.fromJson(JsonReader reader) {
    final summary = reader.objectOrNull('summary');
    final update = reader.objectOrNull('update');
    return Saude(
      storage: StorageStats.fromJson(reader.object('storage')),
      jobs: reader.integerMap('jobs'),
      backup: SaudeBackup.fromJson(reader.object('backup')),
      summary: summary == null ? null : SaudeSummary.fromJson(summary),
      update: update == null ? null : SaudeUpdate.fromJson(update),
    );
  }

  final StorageStats storage;

  /// Work waiting or running, by queue.
  final Map<String, int> jobs;
  final SaudeBackup backup;
  final SaudeSummary? summary;
  final SaudeUpdate? update;

  @override
  bool operator ==(Object other) =>
      other is Saude &&
      other.storage == storage &&
      mapEquals(other.jobs, jobs) &&
      other.backup == backup &&
      other.summary == summary &&
      other.update == update;

  @override
  int get hashCode => Object.hash(
    Saude,
    storage,
    Object.hashAllUnordered([
      for (final entry in jobs.entries) Object.hash(entry.key, entry.value),
    ]),
    backup,
    summary,
    update,
  );
}

enum SaudeSummaryState {
  ok,
  attention;

  static const Map<String, SaudeSummaryState> byWire = {
    'ok': ok,
    'attention': attention,
  };
}

/// A ready-to-show health sentence supplied by the box when BE-4 is available.
final class SaudeSummary {
  const SaudeSummary({required this.state, required this.line});

  factory SaudeSummary.fromJson(JsonReader reader) {
    return SaudeSummary(
      state: reader.enumValue('state', SaudeSummaryState.byWire),
      line: reader.string('line'),
    );
  }

  final SaudeSummaryState state;
  final String line;

  @override
  bool operator ==(Object other) =>
      other is SaudeSummary && other.state == state && other.line == line;

  @override
  int get hashCode => Object.hash(SaudeSummary, state, line);
}

enum SaudeUpdateStatus {
  upToDate,
  updateAvailable,
  checking,
  checkOff,
  unavailable,
  unknown;

  static const Map<String, SaudeUpdateStatus> byWire = {
    'up_to_date': upToDate,
    'update_available': updateAvailable,
    'checking': checking,
    'check_off': checkOff,
    'unavailable': unavailable,
    'unknown': unknown,
  };
}

/// The box version and the result of its optional release check.
final class SaudeUpdate {
  const SaudeUpdate({
    required this.status,
    required this.running,
    required this.latest,
  });

  factory SaudeUpdate.fromJson(JsonReader reader) {
    return SaudeUpdate(
      status: reader.enumValue('status', SaudeUpdateStatus.byWire),
      running: reader.stringOrNull('running'),
      latest: reader.stringOrNull('latest'),
    );
  }

  final SaudeUpdateStatus status;
  final String? running;
  final String? latest;

  @override
  bool operator ==(Object other) =>
      other is SaudeUpdate &&
      other.status == status &&
      other.running == running &&
      other.latest == latest;

  @override
  int get hashCode => Object.hash(SaudeUpdate, status, running, latest);
}

/// The backup state the box reports in the community health panel.
enum SaudeBackupStatus {
  ok,
  none,
  never,
  failed,
  disabled,
  notConfigured,
  unreadable;

  static const Map<String, SaudeBackupStatus> byWire = {
    'ok': ok,
    'none': none,
    'never': never,
    'failed': failed,
    'disabled': disabled,
    'not_configured': notConfigured,
    'unreadable': unreadable,
  };
}

/// The backup state, when the last one ran and how much it carried.
final class SaudeBackup {
  const SaudeBackup({
    required this.status,
    required this.at,
    required this.bytes,
  });

  factory SaudeBackup.fromJson(JsonReader reader) {
    return SaudeBackup(
      status: reader.enumValue('status', SaudeBackupStatus.byWire),
      at: reader.stringOrNull('at'),
      bytes: reader.integerOrNull('bytes'),
    );
  }

  final SaudeBackupStatus status;
  final String? at;
  final int? bytes;

  @override
  bool operator ==(Object other) =>
      other is SaudeBackup &&
      other.status == status &&
      other.at == at &&
      other.bytes == bytes;

  @override
  int get hashCode => Object.hash(SaudeBackup, status, at, bytes);
}
