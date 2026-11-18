import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/file_mirror_store.dart';
import 'package:okena_core/okena_core.dart';

void main() {
  late Directory rootDirectory;

  setUp(() async {
    rootDirectory = await Directory.systemTemp.createTemp(
      'taina-file-mirror-store-',
    );
  });

  tearDown(() async {
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  });

  group('FileMirrorStore', () {
    test('loads absence as a successful null value', () async {
      final store = _store('owner-a', rootDirectory);

      expect(await store.load(), const Ok<MirrorLedger?>(null));
    });

    test('round trips metadata and every entry field', () async {
      final expected = _ledger('owner-a', [
        _entry(
          'asset-1',
          state: MirrorState.uploaded,
          sha256: 'sha-1',
          localPath: '/photos/one.jpg',
          rkey: 'record-1',
          attempts: 1,
          progress: 1,
        ),
        _entry(
          'asset-2',
          state: MirrorState.failed,
          sha256: 'sha-2',
          localPath: '/photos/two.jpg',
          lastError: 'upload failed',
          attempts: 3,
          progress: 0.25,
        ),
        _entry(
          'asset-3',
          state: MirrorState.uploading,
          sha256: 'sha-3',
          localPath: '/photos/three.jpg',
          backgroundTaskId: 'task-3',
          attempts: 2,
          progress: 0.75,
        ),
      ]);
      final store = _store('owner-a', rootDirectory);

      expect(await store.save(expected), const Ok<void>(null));
      final loaded = await _store('owner-a', rootDirectory).load();

      expect(loaded.isSuccess, isTrue);
      expect(loaded.value, expected);
      final metadata = await _metadataFile(
        rootDirectory,
        'owner-a',
      ).readAsString();
      expect(jsonDecode(metadata), {
        'schema_version': MirrorLedger.schemaVersion,
        'owner_id': 'owner-a',
        'destination_folder_rkey': 'folder-1',
      });
    });

    test('warm loads use the confirmed snapshot without disk access', () async {
      final ledger = _ledger('owner-a', [_entry('asset-a')]);
      final store = _store('owner-a', rootDirectory);
      await store.save(ledger);

      final ownerDirectory = _ownerDirectory(rootDirectory, 'owner-a');
      final backupDirectory = Directory('${rootDirectory.path}/owner-backup');
      await ownerDirectory.rename(backupDirectory.path);
      await File(ownerDirectory.path).writeAsString('blocked');
      expect((await store.load()).value, ledger);

      await File(ownerDirectory.path).delete();
      await backupDirectory.rename(ownerDirectory.path);

      final changedEntry = ledger.entries['asset-a']!.copyWith(
        state: MirrorState.hashed,
        sha256: 'external-change',
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      final externalLedger = _ledger('owner-a', [changedEntry]);
      await _entryFile(
        _entriesDirectory(rootDirectory, 'owner-a'),
        'asset-a',
      ).writeAsString(jsonEncode(changedEntry.toJson()));

      expect((await store.load()).value, ledger);
      expect(
        (await _store('owner-a', rootDirectory).load()).value,
        externalLedger,
      );

      final emptyOwnerStore = _store('owner-empty', rootDirectory);
      expect((await emptyOwnerStore.load()).value, isNull);
      final emptyOwnerPath = _ownerDirectory(rootDirectory, 'owner-empty');
      await File(emptyOwnerPath.path).writeAsString('blocked');
      expect((await emptyOwnerStore.load()).value, isNull);
      await File(emptyOwnerPath.path).delete();
    });

    test('stores one file per entry with safe encoded asset ids', () async {
      const unsafeId = '../../outside/photo';
      final ledger = _ledger('owner-a', [
        _entry('regular-id'),
        _entry(unsafeId),
      ]);
      final store = _store('owner-a', rootDirectory);

      expect(await store.save(ledger), const Ok<void>(null));

      final entriesDirectory = _entriesDirectory(rootDirectory, 'owner-a');
      final files = await entriesDirectory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .toList();
      expect(files, hasLength(2));

      final encodedFilename = _entryFilename(unsafeId);
      expect(encodedFilename, isNot(contains('/')));
      expect(
        await File('${entriesDirectory.path}/$encodedFilename').exists(),
        isTrue,
      );
      expect(
        await File('${rootDirectory.path}/outside/photo.json').exists(),
        isFalse,
      );
    });

    test('updates and removes only changed entry files', () async {
      final initial = _ledger('owner-a', [
        _entry('removed'),
        _entry('changed'),
        _entry('untouched'),
      ]);
      final store = _store('owner-a', rootDirectory);
      await store.save(initial);

      final entriesDirectory = _entriesDirectory(rootDirectory, 'owner-a');
      final removedFile = _entryFile(entriesDirectory, 'removed');
      final changedFile = _entryFile(entriesDirectory, 'changed');
      final untouchedFile = _entryFile(entriesDirectory, 'untouched');
      final metadataFile = _metadataFile(rootDirectory, 'owner-a');
      final untouchedContents = await untouchedFile.readAsString();
      final metadataContents = await metadataFile.readAsString();
      final changedContents = await changedFile.readAsString();
      final oldTimestamp = DateTime.utc(2000);
      await untouchedFile.setLastModified(oldTimestamp);
      await metadataFile.setLastModified(oldTimestamp);

      final changedEntry = initial.entries['changed']!.copyWith(
        state: MirrorState.queued,
        updatedAt: DateTime.utc(2026, 2, 1),
      );
      final updated = _ledger('owner-a', [
        changedEntry,
        initial.entries['untouched']!,
      ]);

      expect(await store.save(updated), const Ok<void>(null));

      expect(await removedFile.exists(), isFalse);
      expect(await changedFile.readAsString(), isNot(changedContents));
      expect(await untouchedFile.readAsString(), untouchedContents);
      expect(
        (await untouchedFile.lastModified()).isAtSameMomentAs(oldTimestamp),
        isTrue,
      );
      expect(await metadataFile.readAsString(), metadataContents);
      expect(
        (await metadataFile.lastModified()).isAtSameMomentAs(oldTimestamp),
        isTrue,
      );
    });

    test(
      'reloads the actual disk state after a partial save failure',
      () async {
        final original = _ledger('owner-a', [_entry('A'), _entry('B')]);
        final store = _store('owner-a', rootDirectory);
        expect(await store.save(original), const Ok<void>(null));

        final entriesDirectory = _entriesDirectory(rootDirectory, 'owner-a');
        final bTarget = _entryFile(entriesDirectory, 'B');
        await bTarget.delete();
        final blockingDirectory = Directory(bTarget.path);
        await blockingDirectory.create();
        await File('${blockingDirectory.path}/blocker').writeAsString('block');

        final changedA = original.entries['A']!.copyWith(
          state: MirrorState.hashed,
          sha256: 'changed-a',
          updatedAt: DateTime.utc(2026, 4, 1),
        );
        final changedB = original.entries['B']!.copyWith(
          state: MirrorState.hashed,
          sha256: 'changed-b',
          updatedAt: DateTime.utc(2026, 4, 1),
        );
        final partialTarget = _ledger('owner-a', [changedA, changedB]);

        expect(
          (await store.save(partialTarget)).error,
          isA<InvalidResponseError>(),
        );
        final partiallyWrittenA = jsonDecode(
          await _entryFile(entriesDirectory, 'A').readAsString(),
        ) as Map<String, dynamic>;
        expect(partiallyWrittenA['sha256'], 'changed-a');

        await blockingDirectory.delete(recursive: true);
        expect(await store.save(original), const Ok<void>(null));

        final restored = await _store('owner-a', rootDirectory).load();
        expect(restored.value, original);
      },
    );

    test('cold transitions fall back to full replacement', () async {
      final initial = _ledger('owner-a', [
        _entry('removed'),
        _entry('changed'),
        _entry('untouched'),
      ]);
      await _store('owner-a', rootDirectory).save(initial);

      final changedEntry = initial.entries['changed']!.copyWith(
        state: MirrorState.hashed,
        sha256: 'new-hash',
        updatedAt: DateTime.utc(2026, 6, 1),
      );
      final target = _ledger('owner-a', [
        changedEntry,
        initial.entries['untouched']!,
      ]);
      final coldStore = _store('owner-a', rootDirectory);

      expect(
        await coldStore.saveTransition(
          target,
          changedEntries: [changedEntry],
          removedAssetIds: ['removed'],
        ),
        const Ok<void>(null),
      );
      expect((await _store('owner-a', rootDirectory).load()).value, target);
      expect(
        await _entryFile(
          _entriesDirectory(rootDirectory, 'owner-a'),
          'removed',
        ).exists(),
        isFalse,
      );
    });

    test(
      'confirmed absence falls back to replacement and removes orphans',
      () async {
        final entriesDirectory = _entriesDirectory(rootDirectory, 'owner-a');
        await entriesDirectory.create(recursive: true);
        final orphan = _entry('A');
        await _entryFile(
          entriesDirectory,
          'A',
        ).writeAsString(jsonEncode(orphan.toJson()));
        final store = _store('owner-a', rootDirectory);

        expect((await store.load()).value, isNull);

        final replacement = _ledger('owner-a', [_entry('B')]);
        expect(
          await store.saveTransition(
            replacement,
            changedEntries: replacement.entries.values,
            removedAssetIds: [],
          ),
          const Ok<void>(null),
        );

        expect(await _entryFile(entriesDirectory, 'A').exists(), isFalse);
        expect(await _entryFile(entriesDirectory, 'B').exists(), isTrue);
        expect(
          (await _store('owner-a', rootDirectory).load()).value,
          replacement,
        );
      },
    );

    test(
      'warm transitions update metadata when the destination changes',
      () async {
        final initial = _ledger('owner-a', [_entry('asset-a')]);
        final store = _store('owner-a', rootDirectory);
        await store.save(initial);

        final entryFile = _entryFile(
          _entriesDirectory(rootDirectory, 'owner-a'),
          'asset-a',
        );
        final entryContents = await entryFile.readAsString();
        final metadataFile = _metadataFile(rootDirectory, 'owner-a');
        final target = MirrorLedger(
          ownerId: 'owner-a',
          destinationFolderRkey: 'folder-2',
          entries: initial.entries,
        );

        expect(
          await store.saveTransition(
            target,
            changedEntries: [],
            removedAssetIds: [],
          ),
          const Ok<void>(null),
        );
        expect(
          (jsonDecode(await metadataFile.readAsString())
              as Map<String, dynamic>)['destination_folder_rkey'],
          'folder-2',
        );
        expect(await entryFile.readAsString(), entryContents);
        expect((await store.load()).value, target);
      },
    );

    test('invalid transition descriptions do not write files', () async {
      final initial = _ledger('owner-a', [
        _entry('asset-a'),
        _entry('asset-b'),
      ]);
      final store = _store('owner-a', rootDirectory);
      await store.save(initial);

      final entriesDirectory = _entriesDirectory(rootDirectory, 'owner-a');
      final entryFile = _entryFile(entriesDirectory, 'asset-a');
      final metadataFile = _metadataFile(rootDirectory, 'owner-a');
      final entryContents = await entryFile.readAsString();
      final metadataContents = await metadataFile.readAsString();
      final marker = DateTime.utc(2000);
      await entryFile.setLastModified(marker);
      await metadataFile.setLastModified(marker);

      final targetEntry = initial.entries['asset-a']!.copyWith();
      final target = _ledger('owner-a', [
        targetEntry,
        initial.entries['asset-b']!,
      ]);
      final equalButDifferentEntry = targetEntry.copyWith();
      expect(equalButDifferentEntry, targetEntry);
      expect(identical(equalButDifferentEntry, targetEntry), isFalse);

      expect(
        (await store.saveTransition(
          target,
          changedEntries: [equalButDifferentEntry],
          removedAssetIds: [],
        )).isFailure,
        isTrue,
      );
      expect(
        (await store.saveTransition(
          target,
          changedEntries: [],
          removedAssetIds: ['asset-b'],
        )).isFailure,
        isTrue,
      );

      expect(await entryFile.readAsString(), entryContents);
      expect(await metadataFile.readAsString(), metadataContents);
      expect((await entryFile.lastModified()).isAtSameMomentAs(marker), isTrue);
      expect(
        (await metadataFile.lastModified()).isAtSameMomentAs(marker),
        isTrue,
      );
    });

    test(
      'partial transition failure reloads disk before restoration',
      () async {
        final original = _ledger('owner-a', [_entry('A'), _entry('B')]);
        final store = _store('owner-a', rootDirectory);
        expect(await store.save(original), const Ok<void>(null));

        final entriesDirectory = _entriesDirectory(rootDirectory, 'owner-a');
        final bTarget = _entryFile(entriesDirectory, 'B');
        await bTarget.delete();
        final blockingDirectory = Directory(bTarget.path);
        await blockingDirectory.create();
        await File('${blockingDirectory.path}/blocker').writeAsString('block');

        final changedA = original.entries['A']!.copyWith(
          state: MirrorState.hashed,
          sha256: 'changed-a',
          updatedAt: DateTime.utc(2026, 7, 1),
        );
        final changedB = original.entries['B']!.copyWith(
          state: MirrorState.hashed,
          sha256: 'changed-b',
          updatedAt: DateTime.utc(2026, 7, 1),
        );
        final partialTarget = _ledger('owner-a', [changedA, changedB]);

        expect(
          (await store.saveTransition(
            partialTarget,
            changedEntries: [changedA, changedB],
            removedAssetIds: [],
          )).error,
          isA<InvalidResponseError>(),
        );
        final partiallyWrittenA = jsonDecode(
          await _entryFile(entriesDirectory, 'A').readAsString(),
        ) as Map<String, dynamic>;
        expect(partiallyWrittenA['sha256'], 'changed-a');

        await blockingDirectory.delete(recursive: true);
        expect(
          await store.saveTransition(
            original,
            changedEntries: original.entries.values,
            removedAssetIds: [],
          ),
          const Ok<void>(null),
        );

        final restored = await _store('owner-a', rootDirectory).load();
        expect(restored.value, original);
      },
    );

    test(
      'warm transitions update one of a thousand entries and remove one',
      () async {
        final entries = <String, MirrorEntry>{
          for (var index = 0; index < 1000; index++)
            'asset-$index': _entry('asset-$index'),
        };
        final initial = _ledger('owner-a', entries.values);
        final store = _store('owner-a', rootDirectory);
        await store.save(initial);

        final entriesDirectory = _entriesDirectory(rootDirectory, 'owner-a');
        final changedFile = _entryFile(entriesDirectory, 'asset-500');
        final removedFile = _entryFile(entriesDirectory, 'asset-501');
        final untouchedFile = _entryFile(entriesDirectory, 'asset-502');
        final metadataFile = _metadataFile(rootDirectory, 'owner-a');
        final changedContents = await changedFile.readAsString();
        final untouchedContents = await untouchedFile.readAsString();
        final metadataContents = await metadataFile.readAsString();
        final marker = DateTime.utc(2000);
        await untouchedFile.setLastModified(marker);
        await metadataFile.setLastModified(marker);

        final changedEntry = entries['asset-500']!.copyWith(
          state: MirrorState.hashed,
          updatedAt: DateTime.utc(2026, 8, 1),
        );
        final targetEntries = Map<String, MirrorEntry>.of(entries)
          ..['asset-500'] = changedEntry
          ..remove('asset-501');
        final target = _ledger('owner-a', targetEntries.values);

        expect(
          await store.saveTransition(
            target,
            changedEntries: [changedEntry],
            removedAssetIds: ['asset-501'],
          ),
          const Ok<void>(null),
        );

        expect(await changedFile.readAsString(), isNot(changedContents));
        expect(await removedFile.exists(), isFalse);
        expect(await untouchedFile.readAsString(), untouchedContents);
        expect(
          (await untouchedFile.lastModified()).isAtSameMomentAs(marker),
          isTrue,
        );
        expect(await metadataFile.readAsString(), metadataContents);
        expect(
          (await metadataFile.lastModified()).isAtSameMomentAs(marker),
          isTrue,
        );
        expect(
          await entriesDirectory
              .list()
              .where(
                (entity) => entity is File && entity.path.endsWith('.json'),
              )
              .length,
          999,
        );
      },
    );

    test('owners are isolated and clear removes only one directory', () async {
      final first = _store('owner-a', rootDirectory);
      final second = _store('owner-b', rootDirectory);
      final firstLedger = _ledger('owner-a', [_entry('asset-a')]);
      final secondLedger = _ledger('owner-b', [_entry('asset-b')]);
      await first.save(firstLedger);
      await second.save(secondLedger);

      expect(await first.clear(), const Ok<void>(null));

      expect((await _store('owner-a', rootDirectory).load()).value, isNull);
      expect(
        (await _store('owner-b', rootDirectory).load()).value,
        secondLedger,
      );
      expect(await _ownerDirectory(rootDirectory, 'owner-b').exists(), isTrue);
      expect(await _ownerDirectory(rootDirectory, 'owner-a').exists(), isFalse);
    });

    test(
      'rejects an empty owner without touching the shared directory',
      () async {
        final first = _store('owner-a', rootDirectory);
        final second = _store('owner-b', rootDirectory);
        final firstLedger = _ledger('owner-a', [_entry('asset-a')]);
        final secondLedger = _ledger('owner-b', [_entry('asset-b')]);
        await first.save(firstLedger);
        await second.save(secondLedger);

        final sharedDirectory = Directory('${rootDirectory.path}/taina_mirror');
        final emptyOwnerStore = _store('', rootDirectory);
        expect((await emptyOwnerStore.load()).isFailure, isTrue);
        expect(
          (await emptyOwnerStore.save(_ledger('', [_entry('empty-asset')])))
              .isFailure,
          isTrue,
        );
        expect((await emptyOwnerStore.clear()).isFailure, isTrue);

        expect(await sharedDirectory.exists(), isTrue);
        expect((await first.load()).value, firstLedger);
        expect((await second.load()).value, secondLedger);
        final children = await sharedDirectory.list().toList();
        expect(children.map((entity) => entity.path.split('/').last).toSet(), {
          base64Url.encode(utf8.encode('owner-a')),
          base64Url.encode(utf8.encode('owner-b')),
        });
      },
    );

    test('does not save a ledger belonging to a different owner', () async {
      final store = _store('owner-a', rootDirectory);

      expect(
        (await store.save(_ledger('owner-b', [_entry('asset-b')]))).error,
        const InvalidResponseError('stored mirror ledger'),
      );
      expect(await _metadataFile(rootDirectory, 'owner-a').exists(), isFalse);
    });

    test(
      'malformed metadata and entry files return invalid responses',
      () async {
        final metadataStore = _store('owner-a', rootDirectory);
        final ownerDirectory = _ownerDirectory(rootDirectory, 'owner-a');
        await ownerDirectory.create(recursive: true);
        await _metadataFile(rootDirectory, 'owner-a').writeAsString('{');
        expect((await metadataStore.load()).error, isA<InvalidResponseError>());

        final entryStore = _store('owner-b', rootDirectory);
        await entryStore.save(_ledger('owner-b', [_entry('asset-b')]));
        await _entryFile(
          _entriesDirectory(rootDirectory, 'owner-b'),
          'asset-b',
        ).writeAsString('{');
        expect(
          (await _store('owner-b', rootDirectory).load()).error,
          isA<InvalidResponseError>(),
        );
      },
    );

    test(
      'rejects metadata for a different owner or unsupported schema',
      () async {
        final ownerDirectory = _ownerDirectory(rootDirectory, 'owner-a');
        await ownerDirectory.create(recursive: true);
        final metadataFile = _metadataFile(rootDirectory, 'owner-a');
        await metadataFile.writeAsString(
          jsonEncode({
            'schema_version': MirrorLedger.schemaVersion,
            'owner_id': 'owner-b',
            'destination_folder_rkey': null,
          }),
        );
        expect(
          (await _store('owner-a', rootDirectory).load()).error,
          const InvalidResponseError('stored mirror ledger'),
        );

        await metadataFile.writeAsString(
          jsonEncode({
            'schema_version': MirrorLedger.schemaVersion + 1,
            'owner_id': 'owner-a',
            'destination_folder_rkey': null,
          }),
        );
        expect(
          (await _store('owner-a', rootDirectory).load()).error,
          isA<InvalidResponseError>(),
        );
      },
    );

    test('converts IO failure to an error and permits retry', () async {
      final blockingFile = File('${rootDirectory.path}/not-a-directory');
      await blockingFile.writeAsString('block');
      final store = _store('owner-a', Directory(blockingFile.path));
      final ledger = _ledger('owner-a', [_entry('asset-a')]);

      expect((await store.save(ledger)).error, isA<InvalidResponseError>());

      await blockingFile.delete();
      await Directory(blockingFile.path).create();
      expect(await store.save(ledger), const Ok<void>(null));
      expect(
        (await _store('owner-a', Directory(blockingFile.path)).load()).value,
        ledger,
      );
    });

    test('persists one changed entry in a thousand-entry ledger', () async {
      final entries = <String, MirrorEntry>{
        for (var index = 0; index < 1000; index++)
          'asset-$index': _entry('asset-$index'),
      };
      final initial = _ledger('owner-a', entries.values);
      final store = _store('owner-a', rootDirectory);
      await store.save(initial);

      final entriesDirectory = _entriesDirectory(rootDirectory, 'owner-a');
      final changedFile = _entryFile(entriesDirectory, 'asset-500');
      final untouchedFile = _entryFile(entriesDirectory, 'asset-501');
      final marker = DateTime.utc(2000);
      await untouchedFile.setLastModified(marker);
      final oldChangedContents = await changedFile.readAsString();

      final changedEntry = entries['asset-500']!.copyWith(
        state: MirrorState.hashed,
        updatedAt: DateTime.utc(2026, 3, 1),
      );
      final updatedEntries = Map<String, MirrorEntry>.of(entries)
        ..['asset-500'] = changedEntry;
      final updated = _ledger('owner-a', updatedEntries.values);

      expect(await store.save(updated), const Ok<void>(null));

      expect(await changedFile.readAsString(), isNot(oldChangedContents));
      expect(
        (await untouchedFile.lastModified()).isAtSameMomentAs(marker),
        isTrue,
      );
      expect(
        await entriesDirectory
            .list()
            .where((entity) => entity is File && entity.path.endsWith('.json'))
            .length,
        1000,
      );
    });
  });
}

FileMirrorStore _store(String ownerId, Directory rootDirectory) =>
    FileMirrorStore(ownerId: ownerId, rootDirectory: rootDirectory);

MirrorLedger _ledger(String ownerId, Iterable<MirrorEntry> entries) =>
    MirrorLedger(
      ownerId: ownerId,
      destinationFolderRkey: 'folder-1',
      entries: {for (final entry in entries) entry.assetId: entry},
    );

MirrorEntry _entry(
  String assetId, {
  MirrorState state = MirrorState.queued,
  String? sha256,
  String? localPath,
  String? rkey,
  String? backgroundTaskId,
  int attempts = 0,
  String? lastError,
  double progress = 0,
  DateTime? updatedAt,
}) {
  final modifiedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
  return MirrorEntry(
    assetId: assetId,
    modificationDate: modifiedAt,
    filename: '$assetId.jpg',
    mime: 'image/jpeg',
    size: 1234,
    takenAt: DateTime.utc(2025, 12, 31, 10),
    sha256: sha256,
    localPath: localPath,
    state: state,
    rkey: rkey,
    backgroundTaskId: backgroundTaskId,
    attempts: attempts,
    lastError: lastError,
    progress: progress,
    updatedAt: updatedAt ?? modifiedAt,
  );
}

String _ownerPath(Directory rootDirectory, String ownerId) =>
    '${rootDirectory.path}/taina_mirror/${base64Url.encode(utf8.encode(ownerId))}';

Directory _ownerDirectory(Directory rootDirectory, String ownerId) =>
    Directory(_ownerPath(rootDirectory, ownerId));

Directory _entriesDirectory(Directory rootDirectory, String ownerId) =>
    Directory('${_ownerPath(rootDirectory, ownerId)}/entries');

File _metadataFile(Directory rootDirectory, String ownerId) =>
    File('${_ownerPath(rootDirectory, ownerId)}/metadata.json');

String _entryFilename(String assetId) =>
    '${base64Url.encode(utf8.encode(assetId))}.json';

File _entryFile(Directory entriesDirectory, String assetId) =>
    File('${entriesDirectory.path}/${_entryFilename(assetId)}');
