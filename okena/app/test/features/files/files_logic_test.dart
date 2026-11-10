import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/files/files_logic.dart';
import 'package:okena_core/okena_core.dart';

Folder _folder(String rkey, {String? parent, Zona zona = Zona.casa}) {
  return Folder(
    rkey: rkey,
    cid: 'cid-$rkey',
    name: 'Pasta $rkey',
    zona: zona,
    folder: parent,
    deletedAt: null,
    createdAt: '2026-03-10T14:00:00Z',
    updatedAt: '2026-03-10T14:00:00Z',
  );
}

FileRecord _file(String rkey, {String? folder, Zona zona = Zona.casa}) {
  return FileRecord(
    rkey: rkey,
    cid: 'cid-$rkey',
    blobCid: 'blob-$rkey',
    sha256: 'sha-$rkey',
    name: 'arquivo $rkey',
    mime: 'text/plain',
    size: 10,
    zona: zona,
    folder: folder,
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
  group('entries transitions', () {
    test('from a folder answer keeps folders and files apart', () {
      final entries = FilesLogic.entriesFrom(
        FolderContents(
          folders: [_folder('a')],
          items: [_file('f1')],
          nextCursor: '1',
        ),
      );

      expect(entries.folders.map((folder) => folder.rkey), ['a']);
      expect(entries.files.map((file) => file.rkey), ['f1']);
      expect(entries.isEmpty, isFalse);
    });

    test('inserting a folder appends without touching the files', () {
      final entries = FilesLogic.insertingFolder(
        FilesEntries(files: [_file('f1')]),
        _folder('a'),
      );

      expect(entries.folders.map((folder) => folder.rkey), ['a']);
      expect(entries.files.map((file) => file.rkey), ['f1']);
    });

    test('inserting a file appends to the end', () {
      final entries = FilesLogic.insertingFile(
        FilesEntries(files: [_file('f1')]),
        _file('f2'),
      );

      expect(entries.files.map((file) => file.rkey), ['f1', 'f2']);
    });

    test('a later page joins only its files, folders stay put', () {
      final entries = FilesLogic.appending(
        FilesEntries(folders: [_folder('a')], files: [_file('f1')]),
        FolderContents(
          folders: [_folder('ignored')],
          items: [_file('f2')],
          nextCursor: null,
        ),
      );

      expect(entries.folders.map((folder) => folder.rkey), ['a']);
      expect(entries.files.map((file) => file.rkey), ['f1', 'f2']);
    });

    test('replacing keeps the file where it was and ignores a stranger', () {
      final entries = FilesEntries(files: [_file('f1'), _file('f2')]);
      final replaced = FilesLogic.replacingFile(
        entries,
        _file('f1', zona: Zona.praca),
      );

      expect(replaced.files.first.rkey, 'f1');
      expect(replaced.files.first.zona, Zona.praca);
      expect(replaced.files.last.rkey, 'f2');
      expect(FilesLogic.replacingFile(entries, _file('missing')), entries);
    });
  });

  group('publish action', () {
    test('shows only for an uploaded file still in the casa', () {
      final upload = _file('f1');
      final published = _file('f2', zona: Zona.praca);
      final uploaded = {'f1', 'f2'};

      expect(FilesLogic.showsPublishAction(upload, uploaded), isTrue);
      expect(FilesLogic.showsPublishAction(published, uploaded), isFalse);
      expect(FilesLogic.showsPublishAction(upload, {'other'}), isFalse);
    });
  });

  group('move destinations', () {
    test('a file may go anywhere except its own source', () {
      final folders = [_folder('a'), _folder('b')];

      final destinations = FilesLogic.moveDestinations(
        sourceRkey: 'file',
        isFolder: false,
        folders: folders,
      );

      expect(destinations.map((folder) => folder.rkey), ['a', 'b']);
    });

    test('a folder never moves into itself or its descendants', () {
      final folders = [
        _folder('a'),
        _folder('b', parent: 'a'),
        _folder('c', parent: 'b'),
        _folder('d'),
      ];

      final destinations = FilesLogic.moveDestinations(
        sourceRkey: 'a',
        isFolder: true,
        folders: folders,
      );

      expect(destinations.map((folder) => folder.rkey), ['d']);
    });

    test('a sibling subtree stays a valid destination', () {
      final folders = [_folder('a'), _folder('b', parent: 'a'), _folder('c')];

      final destinations = FilesLogic.moveDestinations(
        sourceRkey: 'c',
        isFolder: true,
        folders: folders,
      );

      expect(destinations.map((folder) => folder.rkey), ['a', 'b']);
    });

    test('a corrupted parent chain does not loop forever', () {
      final folders = [
        _folder('a', parent: 'b'),
        _folder('b', parent: 'a'),
        _folder('c'),
      ];

      final destinations = FilesLogic.moveDestinations(
        sourceRkey: 'x',
        isFolder: true,
        folders: folders,
      );

      expect(destinations.map((folder) => folder.rkey), ['a', 'b', 'c']);
    });
  });

  group('copy', () {
    test('count label says carregados while a page is missing', () {
      expect(
        FilesLogic.countLabel(count: 1, hasMore: true),
        '1 arquivo carregado',
      );
      expect(
        FilesLogic.countLabel(count: 4, hasMore: true),
        '4 arquivos carregados',
      );
      expect(FilesLogic.countLabel(count: 1, hasMore: false), '1 arquivo');
      expect(FilesLogic.countLabel(count: 4, hasMore: false), '4 arquivos');
    });

    test('zona copy always offers the opposite of where the item is', () {
      expect(FilesLogic.zonaActionLabel(Zona.casa), 'Publicar na praça');
      expect(FilesLogic.zonaActionLabel(Zona.praca), 'Tirar da praça');
      expect(
        FilesLogic.zonaConfirmTitle('Foto', Zona.casa),
        'Publicar "Foto" na praça?',
      );
      expect(
        FilesLogic.zonaConfirmTitle('Foto', Zona.praca),
        'Tirar "Foto" da praça?',
      );
      expect(FilesLogic.zonaConfirmPrimary(Zona.casa), 'Publicar');
      expect(FilesLogic.zonaConfirmPrimary(Zona.praca), 'Tirar da praça');
    });

    test('the folder confirm adds that only the folder changes zona', () {
      expect(
        FilesLogic.zonaFolderBody('Fotos', Zona.casa),
        contains('Só a pasta entra na praça.'),
      );
      expect(
        FilesLogic.zonaFolderBody('Fotos', Zona.praca),
        isNot(contains('Só a pasta entra na praça.')),
      );
    });

    test('upload destination names the zone and the way back', () {
      expect(
        FilesLogic.uploadDestinationMessage(Zona.casa),
        contains('só você vê'),
      );
      expect(
        FilesLogic.uploadDestinationMessage(Zona.praca),
        contains('todos os moradores vão ver'),
      );
    });

    test('delete titles quote the name', () {
      expect(
        FilesLogic.deleteFileTitle('Estatuto.pdf'),
        'Excluir "Estatuto.pdf"?',
      );
      expect(
        FilesLogic.deleteFolderTitle('Assembleia'),
        'Excluir a pasta "Assembleia"?',
      );
    });
  });

  group('upload message', () {
    test('quota has its own sentence about the trash window', () {
      const quota = ApiError(
        code: 'storage_quota_exceeded',
        status: 422,
        serverMessage: 'Sem espaço.',
      );

      expect(
        FilesLogic.uploadMessage(quota),
        contains('O que foi apagado segue ocupando espaço'),
      );
      expect(FilesLogic.uploadMessage(quota), isNot(contains('Sem espaço.')));
    });

    test('any other failure keeps the server or local sentence', () {
      const failure = ApiError(
        code: 'forbidden',
        status: 403,
        serverMessage: 'Esta pasta não é sua.',
      );

      expect(FilesLogic.uploadMessage(failure), 'Esta pasta não é sua.');
    });
  });

  group('mime and kind', () {
    test('reads the extension case-insensitively', () {
      expect(FilesLogic.mimeFor('Foto.JPG'), 'image/jpeg');
      expect(FilesLogic.mimeFor('documento.pdf'), 'application/pdf');
      expect(FilesLogic.mimeFor('video.MOV'), 'video/quicktime');
      expect(FilesLogic.mimeFor('sem-extensao'), 'application/octet-stream');
      expect(FilesLogic.mimeFor('ponto.'), 'application/octet-stream');
    });

    test('kind follows the wire mime, not the extension', () {
      expect(FilesLogic.fileKind('image/png'), 'Imagem');
      expect(FilesLogic.fileKind('video/mp4'), 'Vídeo');
      expect(FilesLogic.fileKind('audio/mpeg'), 'Áudio');
      expect(FilesLogic.fileKind('application/pdf'), 'PDF');
      expect(FilesLogic.fileKind('application/zip'), 'ZIP');
      expect(FilesLogic.fileKind('text/csv'), 'Texto');
      expect(FilesLogic.fileKind('application/octet-stream'), 'Arquivo');
    });
  });
}
