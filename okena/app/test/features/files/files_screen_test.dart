import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/features/files/files_screen.dart';
import 'package:okena_app/src/session/upload_center.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fakes.dart';

final class _EmptyFolderApi implements TainaApi {
  @override
  Future<TainaResult<FolderContents>> folderContents({
    String? folderRkey,
    int? limit,
    String? cursor,
    Sort? sort,
    Zona? zona,
  }) async {
    return Ok(
      FolderContents(folders: const [], items: const [], nextCursor: null),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ErrorFolderApi implements TainaApi {
  @override
  Future<TainaResult<FolderContents>> folderContents({
    String? folderRkey,
    int? limit,
    String? cursor,
    Sort? sort,
    Zona? zona,
  }) async {
    return const Err(NetworkError());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _OwnerFilesApi implements TainaApi {
  _OwnerFilesApi({required this.api, required this.ownerPublicId});

  final FakeTainaApi api;
  final String ownerPublicId;

  @override
  Future<TainaResult<FolderContents>> folderContents({
    String? folderRkey,
    int? limit,
    String? cursor,
    Sort? sort,
    Zona? zona,
  }) async {
    final result = await api.folderContents(
      folderRkey: folderRkey,
      limit: limit,
      cursor: cursor,
      sort: sort,
      zona: zona,
    );
    final contents = result.value;
    if (contents == null) return Err(result.error!);
    return Ok(
      FolderContents(
        folders: [
          for (final folder in contents.folders)
            Folder(
              rkey: folder.rkey,
              cid: folder.cid,
              name: folder.name,
              zona: folder.zona,
              folder: folder.folder,
              deletedAt: folder.deletedAt,
              createdAt: folder.createdAt,
              updatedAt: folder.updatedAt,
              dono: ownerPublicId,
            ),
        ],
        items: [
          for (final file in contents.items)
            FileRecord(
              rkey: file.rkey,
              cid: file.cid,
              blobCid: file.blobCid,
              sha256: file.sha256,
              name: file.name,
              mime: file.mime,
              size: file.size,
              zona: file.zona,
              folder: file.folder,
              takenAt: file.takenAt,
              width: file.width,
              height: file.height,
              rendition: file.rendition,
              deletedAt: file.deletedAt,
              createdAt: file.createdAt,
              updatedAt: file.updatedAt,
              dono: ownerPublicId,
            ),
        ],
        nextCursor: contents.nextCursor,
      ),
    );
  }

  @override
  Future<TainaResult<Page<Ava>>> members() => api.members();

  @override
  Future<TainaResult<Uint8List>> thumbnail({
    required String rkey,
    required ThumbnailSize size,
  }) {
    return api.thumbnail(rkey: rkey, size: size);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget home) => MaterialApp(theme: TainaTheme.data, home: home);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('Praça and Casa are separate route tabs with filtered rows', (
    tester,
  ) async {
    _tall(tester);
    final api = FakeTainaApi(delay: Duration.zero);
    final actions = FakeFileActions();
    Folder? openedFolder;
    FileRecord? openedFile;
    final tabs = <TainaDocumentTab>[];

    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: FakeSessionGateway(api: api),
          actions: actions,
          onSelectTab: tabs.add,
          onOpenFolder: (folder) => openedFolder = folder,
          onOpenFile: (file) => openedFile = file,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Documentos'), findsWidgets);
    expect(find.text('Fotos da festa'), findsOneWidget);
    expect(find.text('Foto da quadra.jpg'), findsOneWidget);
    expect(find.text('Documentos da assembleia'), findsNothing);
    expect(find.text('Lista de presenca.pdf'), findsNothing);
    expect(find.text('Praça'), findsWidgets);
    expect(find.text('Casa'), findsWidgets);
    expect(find.text('Lixeira'), findsWidgets);

    await tester.tap(find.text('Fotos da festa'));
    expect(openedFolder?.name, 'Fotos da festa');
    await tester.tap(find.text('Foto da quadra.jpg'));
    expect(openedFile?.name, 'Foto da quadra.jpg');

    await tester.tap(find.text('Casa').last);
    await tester.pumpAndSettle();
    expect(tabs, [TainaDocumentTab.casa]);
    expect(find.text('Documentos da assembleia'), findsOneWidget);
    expect(find.text('Lista de presenca.pdf'), findsOneWidget);
    expect(find.text('Foto da quadra.jpg'), findsNothing);

    await tester.tap(find.text('Lixeira').last);
    await tester.pumpAndSettle();
    expect(tabs, [TainaDocumentTab.casa, TainaDocumentTab.lixeira]);
    expect(find.text('A lixeira está vazia'), findsOneWidget);
  });

  testWidgets('an empty zone offers the new folder action', (tester) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: FakeSessionGateway(api: _EmptyFolderApi()),
          actions: FakeFileActions(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A praça está vazia'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Nova pasta').first);
    await tester.pumpAndSettle();

    expect(find.text('Nova pasta'), findsWidgets);
    expect(find.text('Nome da pasta'), findsOneWidget);
    expect(find.text('Criar'), findsOneWidget);
  });

  testWidgets('an empty Casa offers the file picker action', (tester) async {
    _tall(tester);
    final actions = FakeFileActions()
      ..pickOutcome = const PickedFileCancelled();
    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: FakeSessionGateway(api: _EmptyFolderApi()),
          actions: actions,
          selectedTab: TainaDocumentTab.casa,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sua casa está vazia'), findsOneWidget);
    await tester.tap(find.text('Enviar um arquivo'));
    await tester.pumpAndSettle();
    expect(actions.pickCalls, 1);
  });

  testWidgets('a failed first page shows the error and retry', (tester) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: FakeSessionGateway(api: _ErrorFolderApi()),
          actions: FakeFileActions(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(const NetworkError().message), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('the file picker hands the route a streamed upload request', (
    tester,
  ) async {
    _tall(tester);
    final temp = Directory.systemTemp.createTempSync('okena-upload-widget');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = '${temp.path}/cartaz.txt';
    File(path).writeAsStringSync('cartaz');

    final api = FakeTainaApi(delay: Duration.zero);
    final actions = FakeFileActions()
      ..pickOutcome = PickedFileSelected(
        PickedFile(path: path, name: 'cartaz.txt', mime: 'text/plain'),
      );
    UploadRequest? requested;

    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: FakeSessionGateway(api: api),
          actions: actions,
          onOpenUpload: (request) => requested = request,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(requested?.path, path);
    expect(requested?.name, 'cartaz.txt');
    expect(requested?.mime, 'text/plain');
    expect(requested?.folderRkey, isNull);
    expect(requested?.folderName, isNull);
  });

  testWidgets(
    'row actions expose owner operations only when ownership is known',
    (tester) async {
      _tall(tester);
      final api = FakeTainaApi(delay: Duration.zero);

      await tester.pumpWidget(
        _app(
          FilesScreen(
            session: FakeSessionGateway(api: api),
            actions: FakeFileActions(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is TainaIconButton &&
                  widget.label == 'Ações do arquivo',
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Ações do arquivo'), findsOneWidget);
      expect(find.text('Abrir'), findsOneWidget);
      expect(find.text('Baixar'), findsOneWidget);
      expect(find.text('Mover'), findsNothing);
      expect(find.text('Remover'), findsNothing);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      const me = fakeMe;
      final ownerApi = _OwnerFilesApi(api: api, ownerPublicId: me.ava.publicId);
      await tester.pumpWidget(
        _app(
          FilesScreen(
            session: FakeSessionGateway(api: ownerApi, identity: me),
            actions: FakeFileActions(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is TainaIconButton &&
                  widget.label == 'Ações do arquivo',
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Mover'), findsOneWidget);
      expect(find.text('Renomear'), findsOneWidget);
      expect(find.text('Remover'), findsOneWidget);
    },
  );
}
