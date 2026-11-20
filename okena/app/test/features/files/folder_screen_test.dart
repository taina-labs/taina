import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/files/folder_screen.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fakes.dart';

Widget _app(Widget home) {
  return MaterialApp(theme: TainaTheme.data, home: home);
}

Folder _withOwner(Folder folder, String dono) {
  return Folder(
    rkey: folder.rkey,
    cid: folder.cid,
    name: folder.name,
    zona: folder.zona,
    folder: folder.folder,
    deletedAt: folder.deletedAt,
    createdAt: folder.createdAt,
    updatedAt: folder.updatedAt,
    dono: dono,
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('a folder browses its own contents and shows its menu', (
    tester,
  ) async {
    _tall(tester);
    final api = FakeTainaApi(delay: Duration.zero);
    const me = fakeMe;
    final folders = (await api.listFolders()).value!;
    final folder = _withOwner(folders.first, me.ava.publicId);

    await tester.pumpWidget(
      _app(
        FolderScreen(
          session: FakeSessionGateway(api: api, identity: me),
          actions: FakeFileActions(),
          folder: folder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(folder.name), findsOneWidget);
    expect(find.text('Estatuto da associacao.pdf'), findsOneWidget);
    expect(find.text('Lista de presenca.pdf'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Ações da pasta'));
    await tester.pumpAndSettle();

    expect(find.text('Publicar na praça'), findsOneWidget);
    expect(find.text('Renomear'), findsOneWidget);
    expect(find.text('Mover'), findsOneWidget);
    expect(find.text('Remover'), findsOneWidget);
  });

  testWidgets('uploads in a praca folder still start in casa', (tester) async {
    _tall(tester);
    final api = FakeTainaApi(delay: Duration.zero);
    final folder = (await api.listFolders()).value!.firstWhere(
      (folder) => folder.zona == Zona.praca,
    );

    await tester.pumpWidget(
      _app(
        FolderScreen(
          session: FakeSessionGateway(api: api),
          actions: FakeFileActions(),
          folder: folder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Todo envio começa na sua casa, onde só você vê.'),
      findsOneWidget,
    );
  });

  testWidgets('deleting the folder confirms and reports the deletion', (
    tester,
  ) async {
    _tall(tester);
    final api = FakeTainaApi(delay: Duration.zero);
    const me = fakeMe;
    final folders = (await api.listFolders()).value!;
    final folder = _withOwner(folders.first, me.ava.publicId);
    var deleted = false;

    await tester.pumpWidget(
      _app(
        FolderScreen(
          session: FakeSessionGateway(api: api, identity: me),
          actions: FakeFileActions(),
          folder: folder,
          onDeleted: () => deleted = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Ações da pasta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();

    expect(find.text('Remover a pasta ${folder.name}?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TainaButton, 'Remover'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });
}
