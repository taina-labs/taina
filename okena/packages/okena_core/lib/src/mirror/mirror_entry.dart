import 'package:okena_core/src/json/api_coding.dart';
import 'package:okena_core/src/mirror/mirror_asset.dart';

/// The persisted lifecycle of one camera-roll asset.
enum MirrorState {
  newAsset,
  hashed,
  queued,
  uploading,
  uploaded,
  skipped,
  failed;

  String get wireValue => switch (this) {
    newAsset => 'new',
    hashed => 'hashed',
    queued => 'queued',
    uploading => 'uploading',
    uploaded => 'uploaded',
    skipped => 'skipped',
    failed => 'failed',
  };

  static const Map<String, MirrorState> byWire = {
    'new': newAsset,
    'hashed': hashed,
    'queued': queued,
    'uploading': uploading,
    'uploaded': uploaded,
    'skipped': skipped,
    'failed': failed,
  };
}

/// One local asset and its last known mirror state.
final class MirrorEntry {
  MirrorEntry({
    required this.assetId,
    required DateTime modificationDate,
    required this.filename,
    required this.mime,
    required this.size,
    required DateTime? takenAt,
    required this.sha256,
    required this.localPath,
    required this.state,
    required this.rkey,
    required this.backgroundTaskId,
    required this.attempts,
    required this.lastError,
    required this.progress,
    required DateTime updatedAt,
  }) : modificationDate = modificationDate.toUtc(),
       takenAt = takenAt?.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (size != null && size! < 0) {
      throw ArgumentError.value(size, 'size', 'must not be negative');
    }
    if (attempts < 0) {
      throw ArgumentError.value(attempts, 'attempts', 'must not be negative');
    }
    _validateProgress(progress);
  }

  factory MirrorEntry.fromAsset(
    MirrorAsset asset, {
    MirrorState state = MirrorState.newAsset,
    DateTime? updatedAt,
  }) {
    return MirrorEntry(
      assetId: asset.assetId,
      modificationDate: asset.modificationDate,
      filename: asset.filename,
      mime: asset.mime,
      size: asset.size,
      takenAt: asset.takenAt,
      sha256: null,
      localPath: null,
      state: state,
      rkey: null,
      backgroundTaskId: null,
      attempts: 0,
      lastError: null,
      progress: 0,
      updatedAt: updatedAt ?? asset.modificationDate,
    );
  }

  factory MirrorEntry.fromJson(JsonReader reader) {
    final size = _integerOrNull(reader, 'size');
    final attempts = _integer(reader, 'attempts');
    final progress = _number(reader, 'progress');
    if (size != null && size < 0) {
      throw FormatException('${reader.label}.size must not be negative');
    }
    if (attempts < 0) {
      throw FormatException('${reader.label}.attempts must not be negative');
    }
    if (progress < 0 || progress > 1) {
      throw FormatException('${reader.label}.progress must be between 0 and 1');
    }

    return MirrorEntry(
      assetId: reader.string('asset_id'),
      modificationDate: _dateTime(reader, 'modification_date'),
      filename: reader.string('filename'),
      mime: reader.string('mime'),
      size: size,
      takenAt: _optionalDateTime(reader, 'taken_at'),
      sha256: reader.stringOrNull('sha256'),
      localPath: reader.stringOrNull('local_path'),
      state: reader.enumValue('state', MirrorState.byWire),
      rkey: reader.stringOrNull('rkey'),
      backgroundTaskId: reader.stringOrNull('background_task_id'),
      attempts: attempts,
      lastError: reader.stringOrNull('last_error'),
      progress: progress,
      updatedAt: _dateTime(reader, 'updated_at'),
    );
  }

  final String assetId;
  final DateTime modificationDate;
  final String filename;
  final String mime;
  final int? size;
  final DateTime? takenAt;
  final String? sha256;
  final String? localPath;
  final MirrorState state;
  final String? rkey;
  final String? backgroundTaskId;
  final int attempts;
  final String? lastError;
  final double progress;
  final DateTime updatedAt;

  bool get isTerminal =>
      state == MirrorState.uploaded || state == MirrorState.skipped;

  MirrorEntry copyWith({
    String? assetId,
    DateTime? modificationDate,
    String? filename,
    String? mime,
    int? size,
    bool clearSize = false,
    DateTime? takenAt,
    bool clearTakenAt = false,
    String? sha256,
    bool clearSha256 = false,
    String? localPath,
    bool clearLocalPath = false,
    MirrorState? state,
    String? rkey,
    bool clearRkey = false,
    String? backgroundTaskId,
    bool clearBackgroundTaskId = false,
    int? attempts,
    String? lastError,
    bool clearLastError = false,
    double? progress,
    DateTime? updatedAt,
  }) {
    return MirrorEntry(
      assetId: assetId ?? this.assetId,
      modificationDate: modificationDate ?? this.modificationDate,
      filename: filename ?? this.filename,
      mime: mime ?? this.mime,
      size: clearSize ? null : size ?? this.size,
      takenAt: clearTakenAt ? null : takenAt ?? this.takenAt,
      sha256: clearSha256 ? null : sha256 ?? this.sha256,
      localPath: clearLocalPath ? null : localPath ?? this.localPath,
      state: state ?? this.state,
      rkey: clearRkey ? null : rkey ?? this.rkey,
      backgroundTaskId: clearBackgroundTaskId
          ? null
          : backgroundTaskId ?? this.backgroundTaskId,
      attempts: attempts ?? this.attempts,
      lastError: clearLastError ? null : lastError ?? this.lastError,
      progress: progress ?? this.progress,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'asset_id': assetId,
    'modification_date': modificationDate.toIso8601String(),
    'filename': filename,
    'mime': mime,
    'size': size,
    'taken_at': takenAt?.toIso8601String(),
    'sha256': sha256,
    'local_path': localPath,
    'state': state.wireValue,
    'rkey': rkey,
    'background_task_id': backgroundTaskId,
    'attempts': attempts,
    'last_error': lastError,
    'progress': progress,
    'updated_at': updatedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is MirrorEntry &&
      other.assetId == assetId &&
      other.modificationDate == modificationDate &&
      other.filename == filename &&
      other.mime == mime &&
      other.size == size &&
      other.takenAt == takenAt &&
      other.sha256 == sha256 &&
      other.localPath == localPath &&
      other.state == state &&
      other.rkey == rkey &&
      other.backgroundTaskId == backgroundTaskId &&
      other.attempts == attempts &&
      other.lastError == lastError &&
      other.progress == progress &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
    MirrorEntry,
    assetId,
    modificationDate,
    filename,
    mime,
    size,
    takenAt,
    sha256,
    localPath,
    state,
    rkey,
    backgroundTaskId,
    attempts,
    lastError,
    progress,
    updatedAt,
  ]);
}

DateTime _dateTime(JsonReader reader, String key) {
  try {
    return DateTime.parse(reader.string(key)).toUtc();
  } on FormatException {
    throw FormatException('${reader.label}.$key is not a valid date-time');
  }
}

DateTime? _optionalDateTime(JsonReader reader, String key) {
  final raw = reader.stringOrNull(key);
  if (raw == null) return null;
  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    throw FormatException('${reader.label}.$key is not a valid date-time');
  }
}

int _integer(JsonReader reader, String key) {
  final value = reader.json[key];
  if (value is int) return value;
  throw FormatException('${reader.label}.$key is not an integer');
}

int? _integerOrNull(JsonReader reader, String key) {
  final value = reader.json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw FormatException('${reader.label}.$key is not an integer');
}

double _number(JsonReader reader, String key) {
  final value = reader.json[key];
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('${reader.label}.$key is not a finite number');
}

void _validateProgress(double progress) {
  if (!progress.isFinite || progress < 0 || progress > 1) {
    throw ArgumentError.value(progress, 'progress', 'must be between 0 and 1');
  }
}
