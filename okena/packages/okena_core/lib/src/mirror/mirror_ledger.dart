import 'dart:convert';

import 'package:okena_core/src/json/api_coding.dart';
import 'package:okena_core/src/models/wire.dart';
import 'package:okena_core/src/mirror/mirror_entry.dart';
import 'package:okena_core/src/result.dart';

/// An immutable, device-local record of one owner's camera-roll mirror.
final class MirrorLedger {
  MirrorLedger({
    required this.ownerId,
    this.destinationFolderRkey,
    Map<String, MirrorEntry> entries = const {},
  }) : entries = _immutableEntries(entries);

  static const int schemaVersion = 1;
  static const Duration retryBaseDelay = Duration(seconds: 5);
  static const Duration retryMaximumDelay = Duration(hours: 1);

  factory MirrorLedger.fromJson(JsonReader reader) {
    final version = reader.json['schema_version'];
    if (version is! int || version != schemaVersion) {
      throw FormatException('${reader.label}.schema_version is not supported');
    }

    final decoded = reader.list('entries', MirrorEntry.fromJson);
    final entries = <String, MirrorEntry>{};
    for (final entry in decoded) {
      if (entries.containsKey(entry.assetId)) {
        throw FormatException(
          '${reader.label}.entries contains duplicate asset "${entry.assetId}"',
        );
      }
      entries[entry.assetId] = entry;
    }
    return MirrorLedger(
      ownerId: reader.string('owner_id'),
      destinationFolderRkey: reader.stringOrNull('destination_folder_rkey'),
      entries: entries,
    );
  }

  /// Decodes the persisted document at a result boundary.
  static TainaResult<MirrorLedger> decode(List<int> body) =>
      decodeJsonBody(body, 'mirror ledger', MirrorLedger.fromJson);

  final String ownerId;
  final String? destinationFolderRkey;
  final Map<String, MirrorEntry> entries;

  MirrorLedger withDestinationFolder(String? rkey) => MirrorLedger(
    ownerId: ownerId,
    destinationFolderRkey: rkey,
    entries: entries,
  );

  MirrorLedger upsert(MirrorEntry entry) {
    final updated = Map<String, MirrorEntry>.of(entries)
      ..[entry.assetId] = entry;
    return _copy(entries: updated);
  }

  MirrorLedger markHashed({
    required String assetId,
    required String sha256,
    required String? localPath,
    required DateTime updatedAt,
  }) {
    final entry = entries[assetId];
    if (entry == null) return this;
    return _replace(
      entry.copyWith(
        sha256: sha256,
        localPath: localPath,
        clearLocalPath: localPath == null,
        state: MirrorState.hashed,
        clearBackgroundTaskId: true,
        clearLastError: true,
        progress: 0,
        updatedAt: updatedAt,
      ),
    );
  }

  /// Completes the hash phase, avoiding upload when the box already knows it.
  MirrorLedger classifyHashedAsset({
    required String assetId,
    required String sha256,
    required String? localPath,
    required Set<String> knownHashes,
    required DateTime updatedAt,
  }) {
    final entry = entries[assetId];
    if (entry == null) return this;
    return _replace(
      entry.copyWith(
        sha256: sha256,
        localPath: localPath,
        clearLocalPath: localPath == null,
        state: knownHashes.contains(sha256)
            ? MirrorState.skipped
            : MirrorState.queued,
        clearRkey: true,
        clearBackgroundTaskId: true,
        attempts: 0,
        clearLastError: true,
        progress: 0,
        updatedAt: updatedAt,
      ),
    );
  }

  MirrorLedger markQueued({
    required String assetId,
    required DateTime updatedAt,
  }) {
    final entry = entries[assetId];
    if (entry == null) return this;
    return _replace(
      entry.copyWith(
        state: MirrorState.queued,
        clearRkey: true,
        clearBackgroundTaskId: true,
        clearLastError: true,
        progress: 0,
        updatedAt: updatedAt,
      ),
    );
  }

  MirrorLedger markUploading({
    required String assetId,
    required String backgroundTaskId,
    required double progress,
    required DateTime updatedAt,
  }) {
    final entry = entries[assetId];
    if (entry == null) return this;
    return _replace(
      entry.copyWith(
        state: MirrorState.uploading,
        backgroundTaskId: backgroundTaskId,
        clearLastError: true,
        progress: progress,
        updatedAt: updatedAt,
      ),
    );
  }

  /// Applies a completed transfer only to the exact asset revision it started
  /// from. A late response cannot replace the state of a newer edit.
  MirrorLedger markUploaded({
    required String assetId,
    required DateTime modificationDate,
    required FileRecord file,
    required DateTime updatedAt,
  }) {
    final entry = entries[assetId];
    if (entry == null || entry.modificationDate != modificationDate.toUtc()) {
      return this;
    }
    return _replace(
      entry.copyWith(
        sha256: file.sha256,
        state: MirrorState.uploaded,
        rkey: file.rkey,
        clearBackgroundTaskId: true,
        clearLastError: true,
        progress: 1,
        updatedAt: updatedAt,
      ),
    );
  }

  MirrorLedger markSkipped({
    required String assetId,
    required DateTime updatedAt,
  }) {
    final entry = entries[assetId];
    if (entry == null) return this;
    return _replace(
      entry.copyWith(
        state: MirrorState.skipped,
        clearRkey: true,
        clearBackgroundTaskId: true,
        clearLastError: true,
        progress: 0,
        updatedAt: updatedAt,
      ),
    );
  }

  /// Records a failed attempt and leaves it eligible for a later retry.
  MirrorLedger markFailed({
    required String assetId,
    required String error,
    required DateTime updatedAt,
  }) {
    final entry = entries[assetId];
    if (entry == null) return this;
    return _replace(
      entry.copyWith(
        state: MirrorState.failed,
        attempts: entry.attempts + 1,
        lastError: error,
        clearBackgroundTaskId: true,
        updatedAt: updatedAt,
      ),
    );
  }

  MirrorLedger updateProgress({
    required String assetId,
    required double progress,
    required DateTime updatedAt,
  }) {
    final entry = entries[assetId];
    if (entry == null || entry.state != MirrorState.uploading) return this;
    return _replace(entry.copyWith(progress: progress, updatedAt: updatedAt));
  }

  /// A local cancellation releases the transfer slot without discarding work.
  MirrorLedger cancelUpload({
    required String assetId,
    required DateTime updatedAt,
  }) {
    final entry = entries[assetId];
    if (entry == null || entry.state != MirrorState.uploading) return this;
    return _replace(
      entry.copyWith(
        state: MirrorState.queued,
        clearBackgroundTaskId: true,
        clearLastError: true,
        progress: 0,
        updatedAt: updatedAt,
      ),
    );
  }

  /// Requeues work that cannot be reattached to a platform background task.
  MirrorLedger requeueInterrupted({DateTime? updatedAt}) {
    var changed = false;
    final updated = <String, MirrorEntry>{};
    for (final entry in entries.values) {
      final requeued =
          entry.state == MirrorState.uploading && entry.backgroundTaskId == null
          ? entry.copyWith(
              state: MirrorState.queued,
              clearLastError: true,
              progress: 0,
              updatedAt: updatedAt ?? entry.updatedAt,
            )
          : entry;
      if (!identical(requeued, entry)) changed = true;
      updated[entry.assetId] = requeued;
    }
    return changed ? _copy(entries: updated) : this;
  }

  /// Stable exponential backoff. Attempts keep retrying, with the delay capped.
  static Duration retryDelay(int attempts) {
    if (attempts <= 1) return retryBaseDelay;
    var delay = retryBaseDelay;
    for (var attempt = 1; attempt < attempts; attempt++) {
      if (delay >= retryMaximumDelay ~/ 2) return retryMaximumDelay;
      delay *= 2;
    }
    return delay > retryMaximumDelay ? retryMaximumDelay : delay;
  }

  /// Queued and failed entries in asset-id order, with duplicate content
  /// suppressed while an equal hash is uploading or already selected.
  List<MirrorEntry> nextUploads() {
    final ordered = entries.values.toList()
      ..sort((a, b) => a.assetId.compareTo(b.assetId));
    final inFlightHashes = <String>{
      for (final entry in ordered)
        if (entry.state == MirrorState.uploading && entry.sha256 != null)
          entry.sha256!,
    };
    final selectedHashes = <String>{};
    final candidates = <MirrorEntry>[];

    for (final entry in ordered) {
      if ((entry.state != MirrorState.queued &&
              entry.state != MirrorState.failed) ||
          entry.sha256 == null) {
        continue;
      }
      final hash = entry.sha256!;
      if (inFlightHashes.contains(hash) || !selectedHashes.add(hash)) {
        continue;
      }
      candidates.add(entry);
    }
    return List.unmodifiable(candidates);
  }

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'owner_id': ownerId,
    'destination_folder_rkey': destinationFolderRkey,
    'entries': [for (final entry in _orderedEntries()) entry.toJson()],
  };

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) {
    if (other is! MirrorLedger ||
        other.ownerId != ownerId ||
        other.destinationFolderRkey != destinationFolderRkey ||
        other.entries.length != entries.length) {
      return false;
    }
    for (final item in entries.entries) {
      if (other.entries[item.key] != item.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    MirrorLedger,
    ownerId,
    destinationFolderRkey,
    Object.hashAllUnordered([
      for (final entry in entries.entries) Object.hash(entry.key, entry.value),
    ]),
  );

  MirrorLedger _replace(MirrorEntry entry) {
    final updated = Map<String, MirrorEntry>.of(entries)
      ..[entry.assetId] = entry;
    return _copy(entries: updated);
  }

  MirrorLedger _copy({Map<String, MirrorEntry>? entries}) => MirrorLedger(
    ownerId: ownerId,
    destinationFolderRkey: destinationFolderRkey,
    entries: entries ?? this.entries,
  );

  List<MirrorEntry> _orderedEntries() {
    final ordered = entries.values.toList()
      ..sort((a, b) => a.assetId.compareTo(b.assetId));
    return ordered;
  }
}

Map<String, MirrorEntry> _immutableEntries(Map<String, MirrorEntry> entries) {
  final copy = <String, MirrorEntry>{};
  for (final entry in entries.entries) {
    if (entry.key != entry.value.assetId) {
      throw ArgumentError.value(
        entry.key,
        'entries',
        'must match the entry assetId',
      );
    }
    copy[entry.key] = entry.value;
  }
  return Map.unmodifiable(copy);
}
