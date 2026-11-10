import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/features/files/files_screen.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fakes.dart';

final class _EmptyFolderApi implements TainaApi {
  @override
  Future<TainaResult<FolderContents>> folderContents({
    String? folderRkey,
    int? limit,
    String? cursor,
    Sort? sort,
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
  }) async {
    return const Err(NetworkError());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget home) {
  return MaterialApp(theme: TainaTheme.data, home: home);
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('root shows folders, files and the upload destination', (
    tester,
  ) async {
    _tall(tester);
    final api = FakeTainaApi(delay: Duration.zero);
    final actions = FakeFileActions();
    Folder? openedFolder;
    FileRecord? openedFile;
    var openedTrash = false;

    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: FakeSessionGateway(api: api),
          actions: actions,
          onOpenFolder: (folder) => openedFolder = folder,
          onOpenFile: (file) => openedFile = file,
          onOpenTrash: () => openedTrash = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Arquivos'), findsOneWidget);
    expect(find.text('Documentos da assembleia'), findsOneWidget);
    expect(find.text('Fotos da festa'), findsOneWidget);
    expect(find.text('Lista de presenca.pdf'), findsOneWidget);
    expect(find.text('Foto da quadra.jpg'), findsOneWidget);
    expect(find.textContaining('Vai para a sua casa'), findsOneWidget);
    expect(find.text('2 ARQUIVOS'), findsOneWidget);

    await tester.tap(find.text('Documentos da assembleia'));
    expect(openedFolder?.name, 'Documentos da assembleia');

    await tester.tap(find.text('Lista de presenca.pdf'));
    expect(openedFile?.name, 'Lista de presenca.pdf');

    await tester.tap(find.byTooltip('Lixeira'));
    expect(openedTrash, isTrue);
  });

  testWidgets('loading shows the skeleton before the first page', (
    tester,
  ) async {
    _tall(tester);
    final api = FakeTainaApi(delay: const Duration(milliseconds: 50));

    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: FakeSessionGateway(api: api),
          actions: FakeFileActions(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TainaLoadingList), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byType(TainaLoadingList), findsNothing);
    expect(find.text('Documentos da assembleia'), findsOneWidget);
  });

  testWidgets('an empty folder offers the new folder action', (tester) async {
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

    expect(find.text('Esta pasta está vazia'), findsOneWidget);
    expect(find.textContaining('Vai para a sua casa'), findsOneWidget);

    await tester.tap(find.widgetWithText(TainaSecondaryButton, 'Nova pasta'));
    await tester.pumpAndSettle();

    expect(find.text('Nome da pasta'), findsOneWidget);
    expect(find.text('Criar'), findsOneWidget);
  });

  testWidgets('a failed first page shows the error and the retry', (
    tester,
  ) async {
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

  testWidgets('upload adds the row and the one-tap publish sends it', (
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

    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: FakeSessionGateway(api: api),
          actions: actions,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Enviar arquivo'));
    await tester.pumpAndSettle();

    expect(find.text('cartaz.txt'), findsOneWidget);
    expect(find.text('Publicar na praça'), findsOneWidget);

    await tester.tap(find.text('Publicar na praça'));
    await tester.pumpAndSettle();

    expect(find.text('Publicar na praça'), findsNothing);
  });
}
