import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/features/files/files_logic.dart';
import 'package:okena_app/src/features/files/files_view_model.dart';
import 'package:okena_app/src/features/files/folder_actions_view_model.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fakes.dart';

/// A files API that answers the pages the test hands it, in order. Every
/// other call is out of scope and fails loudly.
final class _PagedFolderApi implements TainaApi {
  _PagedFolderApi(this.pages);

  final List<TainaResult<FolderContents>> pages;
  final List<String?> cursors = [];

  @override
  Future<TainaResult<FolderContents>> folderContents({
    String? folderRkey,
    int? limit,
    String? cursor,
    Sort? sort,
  }) async {
    cursors.add(cursor);
    final index = cursor == null ? 0 : int.parse(cursor);
    return pages[index];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Folder _folder(String rkey, {String? parent}) {
  return Folder(
    rkey: rkey,
    cid: 'cid-$rkey',
    name: 'Pasta $rkey',
    zona: Zona.casa,
    folder: parent,
    deletedAt: null,
    createdAt: '2026-03-10T14:00:00Z',
    updatedAt: '2026-03-10T14:00:00Z',
  );
}

FileRecord _file(String rkey) {
  return FileRecord(
    rkey: rkey,
    cid: 'cid-$rkey',
    blobCid: 'blob-$rkey',
    sha256: 'sha-$rkey',
    name: 'arquivo $rkey',
    mime: 'text/plain',
    size: 10,
    zona: Zona.casa,
    folder: null,
    takenAt: null,
    width: null,
    height: null,
    rendition: Rendition.none,
    deletedAt: null,
    createdAt: '2026-03-11T09:30:00Z',
    updatedAt: '2026-03-11T09:30:00Z',
  );
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('okena-files-test');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  group('load', () {
    test('fills folders and files from the root answer', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
      );

      await viewModel.load();

      expect(viewModel.loading, isFalse);
      expect(viewModel.error, isNull);
      expect(viewModel.entries.folders, hasLength(2));
      expect(viewModel.entries.files, hasLength(2));
      expect(viewModel.nextCursor, isNull);
      expect(viewModel.isEmpty, isFalse);
    });

    test('an empty folder reports the empty state', () async {
      final api = _PagedFolderApi([
        Ok(
          FolderContents(folders: const [], items: const [], nextCursor: null),
        ),
      ]);
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
        folderRkey: 'empty',
      );

      await viewModel.load();

      expect(viewModel.isEmpty, isTrue);
      expect(viewModel.error, isNull);
    });
  });

  group('pagination', () {
    test('walks the cursor and appends the files in order', () async {
      final api = _PagedFolderApi([
        Ok(
          FolderContents(
            folders: [_folder('a')],
            items: [_file('f1'), _file('f2')],
            nextCursor: '1',
          ),
        ),
        Ok(
          FolderContents(
            folders: const [],
            items: [_file('f3')],
            nextCursor: null,
          ),
        ),
      ]);
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
      );

      await viewModel.load();
      expect(viewModel.entries.files.map((file) => file.rkey), ['f1', 'f2']);
      expect(viewModel.nextCursor, '1');

      await viewModel.loadMore();
      expect(viewModel.entries.files.map((file) => file.rkey), [
        'f1',
        'f2',
        'f3',
      ]);
      expect(viewModel.entries.folders.map((folder) => folder.rkey), ['a']);
      expect(viewModel.nextCursor, isNull);
      expect(api.cursors, [null, '1']);
    });

    test('a failed page keeps the list and the cursor for retry', () async {
      final api = _PagedFolderApi([
        Ok(
          FolderContents(
            folders: const [],
            items: [_file('f1')],
            nextCursor: '1',
          ),
        ),
        const Err(NetworkError()),
        Ok(
          FolderContents(
            folders: const [],
            items: [_file('f2')],
            nextCursor: null,
          ),
        ),
      ]);
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
      );

      await viewModel.load();
      await viewModel.loadMore();

      expect(viewModel.entries.files.map((file) => file.rkey), ['f1']);
      expect(viewModel.nextCursor, '1');
      expect(viewModel.moreError, isTrue);

      api.pages[1] = Ok(
        FolderContents(
          folders: const [],
          items: [_file('f2')],
          nextCursor: null,
        ),
      );
      await viewModel.loadMore();
      expect(viewModel.entries.files.map((file) => file.rkey), ['f1', 'f2']);
      expect(viewModel.moreError, isFalse);
      expect(viewModel.nextCursor, isNull);
    });

    test('never walks past the last page', () async {
      final api = _PagedFolderApi([
        Ok(
          FolderContents(
            folders: const [],
            items: [_file('f1')],
            nextCursor: null,
          ),
        ),
      ]);
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
      );

      await viewModel.load();
      await viewModel.loadMore();
      await viewModel.loadMore();

      expect(api.cursors, [null]);
      expect(viewModel.entries.files, hasLength(1));
    });
  });

  group('upload and publish', () {
    test('uploads the picked path and keeps the one-tap publish', () async {
      final path = '${temp.path}/nota.txt';
      File(path).writeAsStringSync('oi');
      final api = FakeTainaApi(delay: Duration.zero);
      final actions = FakeFileActions()
        ..pickOutcome = PickedFileSelected(
          PickedFile(
            path: path,
            name: 'nota.txt',
            mime: FilesLogic.mimeFor('nota.txt'),
          ),
        );
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: actions,
      );
      await viewModel.load();

      final message = await viewModel.pickAndUpload();

      expect(message, isNull);
      expect(viewModel.uploading, isFalse);
      expect(viewModel.entries.files, hasLength(3));
      final uploaded = viewModel.entries.files.last;
      expect(uploaded.name, 'nota.txt');
      expect(uploaded.mime, 'text/plain');
      expect(uploaded.size, 2);
      expect(viewModel.uploadedRkeys, contains(uploaded.rkey));
      expect(viewModel.showsPublishAction(uploaded), isTrue);
    });

    test('a cancelled picker changes nothing', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final actions = FakeFileActions()
        ..pickOutcome = const PickedFileCancelled();
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: actions,
      );
      await viewModel.load();

      final message = await viewModel.pickAndUpload();

      expect(message, isNull);
      expect(viewModel.entries.files, hasLength(2));
      expect(viewModel.uploading, isFalse);
    });

    test('a picker failure surfaces its own sentence', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final actions = FakeFileActions()
        ..pickOutcome = const PickedFileFailed(
          'Não deu para abrir o seletor de arquivos.',
        );
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: actions,
      );

      final message = await viewModel.pickAndUpload();

      expect(message, 'Não deu para abrir o seletor de arquivos.');
    });

    test('publishing swaps the row and ends the reminder', () async {
      final path = '${temp.path}/nota.txt';
      File(path).writeAsStringSync('oi');
      final api = FakeTainaApi(delay: Duration.zero);
      final actions = FakeFileActions()
        ..pickOutcome = PickedFileSelected(
          PickedFile(path: path, name: 'nota.txt', mime: 'text/plain'),
        );
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: actions,
      );
      await viewModel.load();
      await viewModel.pickAndUpload();
      final uploaded = viewModel.entries.files.last;

      final result = await viewModel.publish(uploaded);

      expect(result.isSuccess, isTrue);
      final published = viewModel.entries.files.last;
      expect(published.rkey, uploaded.rkey);
      expect(published.zona, Zona.praca);
      expect(viewModel.uploadedRkeys, isEmpty);
      expect(viewModel.publishingRkey, isNull);
      expect(viewModel.showsPublishAction(published), isFalse);
    });
  });

  group('folder acts', () {
    test('creates a folder at the end of the list', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final viewModel = FilesViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
      );
      await viewModel.load();

      final result = await viewModel.createFolder('Nova');

      expect(result.isSuccess, isTrue);
      expect(viewModel.entries.folders, hasLength(3));
      expect(viewModel.entries.folders.last.name, 'Nova');
    });

    test('renames, moves, changes zona and deletes a folder', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final session = FakeSessionGateway(api: api);
      final actions = FolderActionsViewModel(session: session);
      final folders = (await api.listFolders()).value!;
      final folder = folders.first;

      final renamed = await actions.rename(folder, 'Assembleia nova');
      expect(renamed.value?.name, 'Assembleia nova');
      expect(actions.working, isFalse);

      final moved = await actions.move(renamed.value!, folders.last);
      expect(moved.value?.folder, folders.last.rkey);

      final published = await actions.setZona(moved.value!, Zona.praca);
      expect(published.value?.zona, Zona.praca);

      final deleted = await actions.delete(published.value!);
      expect(deleted.isSuccess, isTrue);
      expect(actions.working, isFalse);
      final remaining = (await api.listFolders()).value!;
      expect(
        remaining.map((item) => item.rkey),
        isNot(contains(published.value!.rkey)),
      );
    });
  });
}
