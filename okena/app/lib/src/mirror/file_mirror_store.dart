// The public named parameter cannot be an initializing formal because the
// field it assigns is private.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:okena_core/okena_core.dart';
import 'package:path_provider/path_provider.dart';

import 'mirror_transition_store.dart';

/// Persists an owner's camera-roll ledger as independently updated files.
///
/// One instance is the single writer for its owner. Use a new instance to
/// inspect changes written externally.
final class FileMirrorStore implements MirrorTransitionStore {
  FileMirrorStore({required this.ownerId, Directory? rootDirectory})
    : _rootDirectory = rootDirectory;

  static int _temporarySequence = 0;

  final String ownerId;
  final Directory? _rootDirectory;

  MirrorLedger? _snapshot;
  bool _hasSnapshot = false;

  @override
  Future<TainaResult<MirrorLedger?>> load() async {
    if (ownerId.isEmpty) {
      return const Err<MirrorLedger?>(
        InvalidResponseError('stored mirror ledger'),
      );
    }
    if (_hasSnapshot) return Ok<MirrorLedger?>(_snapshot);

    _invalidateSnapshot();

    try {
      final ownerDirectory = await _ownerDirectory();
      final metadataFile = _metadataFile(ownerDirectory);
      if (!await metadataFile.exists()) {
        _hasSnapshot = true;
        return const Ok<MirrorLedger?>(null);
      }

      final metadata = jsonDecode(await metadataFile.readAsString());
      if (metadata is! Map<String, dynamic>) {
        return _invalidLedger();
      }

      final entryDocuments = <Map<String, Object?>>[];
      final entriesDirectory = _entriesDirectory(ownerDirectory);
      if (await entriesDirectory.exists()) {
        await for (final entity in entriesDirectory.list(followLinks: false)) {
          if (entity is! File) continue;
          final filename = entity.path.split('/').last;
          if (!filename.endsWith('.json')) continue;

          final entry = jsonDecode(await entity.readAsString());
          if (entry is! Map<String, dynamic>) return _invalidLedger();
          final assetId = entry['asset_id'];
          if (assetId is! String || _entryFilename(assetId) != filename) {
            return _invalidLedger();
          }
          entryDocuments.add(Map<String, Object?>.from(entry));
        }
      }

      final document = <String, Object?>{
        ...metadata,
        'entries': entryDocuments,
      };
      final decoded = MirrorLedger.decode(utf8.encode(jsonEncode(document)));
      switch (decoded) {
        case Ok<MirrorLedger>(:final value):
          if (value.ownerId != ownerId) return _invalidLedger();
          _snapshot = value;
          _hasSnapshot = true;
          return Ok<MirrorLedger?>(value);
        case Err<MirrorLedger>(:final error):
          return Err<MirrorLedger?>(error);
      }
    } on Exception {
      return _invalidLedger();
    }
  }

  @override
  Future<TainaResult<void>> save(MirrorLedger ledger) async {
    if (ownerId.isEmpty) {
      return const Err<void>(InvalidResponseError('stored mirror ledger'));
    }

    if (ledger.ownerId != ownerId) {
      _invalidateSnapshot();
      return const Err<void>(InvalidResponseError('stored mirror ledger'));
    }

    try {
      if (!_hasSnapshot) {
        final loaded = await load();
        if (loaded case Err<MirrorLedger?>(:final error)) {
          _invalidateSnapshot();
          return Err<void>(error);
        }
      }

      final current = _snapshot;
      final ownerDirectory = await _ownerDirectory();
      final entriesDirectory = _entriesDirectory(ownerDirectory);
      await entriesDirectory.create(recursive: true);

      final targetFilenames = <String>{};
      final assetIds = ledger.entries.keys.toList()..sort();
      for (final assetId in assetIds) {
        final filename = _entryFilename(assetId);
        targetFilenames.add(filename);
        final entry = ledger.entries[assetId]!;
        if (current?.entries[assetId] == entry) continue;

        await _atomicWrite(
          File('${entriesDirectory.path}/$filename'),
          jsonEncode(entry.toJson()),
        );
      }

      await for (final entity in entriesDirectory.list(followLinks: false)) {
        if (entity is! File) continue;
        final filename = entity.path.split('/').last;
        if (filename.endsWith('.json') && !targetFilenames.contains(filename)) {
          await entity.delete();
        }
      }

      await _writeMetadataIfNeeded(ownerDirectory, ledger);

      _snapshot = ledger;
      _hasSnapshot = true;
      return const Ok<void>(null);
    } on Exception {
      _invalidateSnapshot();
      return const Err<void>(InvalidResponseError('stored mirror ledger'));
    }
  }

  @override
  Future<TainaResult<void>> saveTransition(
    MirrorLedger ledger, {
    required Iterable<MirrorEntry> changedEntries,
    required Iterable<String> removedAssetIds,
  }) async {
    if (ownerId.isEmpty || ledger.ownerId != ownerId) {
      return _invalidTransition();
    }

    final changedById = <String, MirrorEntry>{};
    for (final entry in changedEntries) {
      if (!identical(ledger.entries[entry.assetId], entry)) {
        return _invalidTransition();
      }
      changedById[entry.assetId] = entry;
    }

    final removedIds = removedAssetIds.toSet().toList()..sort();
    for (final assetId in removedIds) {
      if (ledger.entries.containsKey(assetId)) return _invalidTransition();
    }

    if (!_hasSnapshot || _snapshot == null) return save(ledger);

    try {
      final current = _snapshot;
      final ownerDirectory = await _ownerDirectory();
      final entriesDirectory = _entriesDirectory(ownerDirectory);
      await entriesDirectory.create(recursive: true);

      final changedIds = changedById.keys.toList()..sort();
      for (final assetId in changedIds) {
        final entry = changedById[assetId]!;
        if (current?.entries[assetId] == entry) continue;

        await _atomicWrite(
          File('${entriesDirectory.path}/${_entryFilename(assetId)}'),
          jsonEncode(entry.toJson()),
        );
      }

      for (final assetId in removedIds) {
        final file = File(
          '${entriesDirectory.path}/${_entryFilename(assetId)}',
        );
        if (await file.exists()) await file.delete();
      }

      await _writeMetadataIfNeeded(ownerDirectory, ledger);

      _snapshot = ledger;
      _hasSnapshot = true;
      return const Ok<void>(null);
    } on Exception {
      _invalidateSnapshot();
      return const Err<void>(InvalidResponseError('stored mirror ledger'));
    }
  }

  @override
  Future<TainaResult<void>> clear() async {
    if (ownerId.isEmpty) {
      return const Err<void>(InvalidResponseError('stored mirror ledger'));
    }

    try {
      final ownerDirectory = await _ownerDirectory();
      if (await ownerDirectory.exists()) {
        await ownerDirectory.delete(recursive: true);
      }
      _snapshot = null;
      _hasSnapshot = true;
      return const Ok<void>(null);
    } on Exception {
      _invalidateSnapshot();
      return const Err<void>(InvalidResponseError('stored mirror ledger'));
    }
  }

  void _invalidateSnapshot() {
    _snapshot = null;
    _hasSnapshot = false;
  }

  Future<Directory> _ownerDirectory() async {
    final root = _rootDirectory ?? await getApplicationSupportDirectory();
    final encodedOwner = base64Url.encode(utf8.encode(ownerId));
    return Directory('${root.path}/taina_mirror/$encodedOwner');
  }

  Directory _entriesDirectory(Directory ownerDirectory) =>
      Directory('${ownerDirectory.path}/entries');

  File _metadataFile(Directory ownerDirectory) =>
      File('${ownerDirectory.path}/metadata.json');

  Future<void> _writeMetadataIfNeeded(
    Directory ownerDirectory,
    MirrorLedger ledger,
  ) async {
    final metadataFile = _metadataFile(ownerDirectory);
    final metadata = jsonEncode({
      'schema_version': MirrorLedger.schemaVersion,
      'owner_id': ownerId,
      'destination_folder_rkey': ledger.destinationFolderRkey,
    });
    final metadataExists = await metadataFile.exists();
    if (!metadataExists || await metadataFile.readAsString() != metadata) {
      await _atomicWrite(metadataFile, metadata);
    }
  }

  String _entryFilename(String assetId) =>
      '${base64Url.encode(utf8.encode(assetId))}.json';

  Future<void> _atomicWrite(File target, String contents) async {
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch}-${_temporarySequence++}';
    final temporary = File('${target.path}.tmp-$suffix');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(target.path);
  }

  Err<T> _invalidLedger<T>() =>
      Err<T>(const InvalidResponseError('stored mirror ledger'));

  Err<void> _invalidTransition() {
    _invalidateSnapshot();
    return const Err<void>(InvalidResponseError('stored mirror ledger'));
  }
}
