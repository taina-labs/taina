import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/files/file_detail_screen.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fakes.dart';

/// Answers the download with a path and no real file IO, so the widget test
/// never waits on a disk write the fake clock cannot advance.
final class _DownloadApi implements TainaApi {
  _DownloadApi(this.path);

  final String path;

  @override
  Future<TainaResult<String>> download({required String rkey}) async {
    return Ok(path);
  }

  @override
  Future<TainaResult<Uint8List>> thumbnail({
    required String rkey,
    required ThumbnailSize size,
  }) async {
    return const Err(
      ApiError(
        code: 'not_found',
        status: 404,
        serverMessage: 'Este arquivo não tem miniatura.',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _ana = Ava(
  publicId: 'ava-ana',
  username: 'ana',
  displayName: 'Ana Souza',
  papel: Papel.zelador,
  activatedAt: '2026-02-01T09:00:00Z',
  deactivatedAt: null,
  createdAt: '2026-02-01T09:00:00Z',
);

const _target = AccessTarget(owner: _ana, rkey: 'f1', name: 'Foto.jpg');

const _pedido = Pedido(
  publicId: 'ped-1',
  tipo: 'leitura',
  recurso: 'f1',
  motivo: 'Pedido de acesso pela tela do arquivo',
  status: PedidoStatus.pendente,
  decididoEm: null,
  createdAt: '2026-03-10T12:00:00Z',
  pedinte: _ana,
  dono: _ana,
);

final class _DeniedApi implements TainaApi {
  int requests = 0;

  @override
  Future<TainaResult<String>> download({required String rkey}) async {
    return const Err(
      ApiError(
        code: 'forbidden',
        status: 403,
        serverMessage: 'Esta casa é particular.',
      ),
    );
  }

  @override
  Future<TainaResult<AccessTarget>> accessTarget({
    required String fileRkey,
  }) async {
    return const Ok(_target);
  }

  @override
  Future<TainaResult<Pedido>> requestAccess({
    required String fileRkey,
    String? motivo,
  }) async {
    requests += 1;
    return const Ok(_pedido);
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
  testWidgets('the file screen downloads, shares and previews one path', (
    tester,
  ) async {
    _tall(tester);
    const payload = '/tmp/taina-arquivo.jpg';
    final actions = FakeFileActions();
    final file = FileRecord(
      rkey: 'f1',
      cid: 'cid',
      blobCid: 'blob',
      sha256: 'sha',
      name: 'Foto da quadra.jpg',
      mime: 'image/jpeg',
      size: 1200,
      zona: Zona.praca,
      folder: null,
      takenAt: null,
      width: 10,
      height: 10,
      rendition: Rendition.ready,
      deletedAt: null,
      createdAt: '2026-06-21T21:12:00Z',
      updatedAt: '2026-06-21T21:12:00Z',
    );

    await tester.pumpWidget(
      _app(
        FileDetailScreen(
          session: FakeSessionGateway(api: _DownloadApi(payload)),
          actions: actions,
          file: file,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(file.name), findsOneWidget);
    expect(find.text('Baixar'), findsOneWidget);
    expect(find.text('Pré-visualizar'), findsOneWidget);
    expect(find.text('ASSINATURA DO ARQUIVO'), findsOneWidget);

    await tester.tap(find.text('Baixar'));
    await tester.pumpAndSettle();

    expect(find.text('Compartilhar'), findsOneWidget);

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
    expect(actions.sharedPaths, [payload]);

    await tester.tap(find.text('Pré-visualizar'));
    await tester.pumpAndSettle();
    expect(actions.openedPaths, [payload]);
  });

  testWidgets('rename updates the name through the owner menu', (tester) async {
    _tall(tester);
    final api = FakeTainaApi(delay: Duration.zero);
    final file = (await api.file(rkey: '3m7d1wyzr4c8u')).value!;

    await tester.pumpWidget(
      _app(
        FileDetailScreen(
          session: FakeSessionGateway(api: api),
          actions: FakeFileActions(),
          file: file,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Quadra nova.jpg');
    await tester.tap(find.widgetWithText(TextButton, 'Renomear'));
    await tester.pumpAndSettle();

    expect(find.text('Quadra nova.jpg'), findsOneWidget);
  });

  testWidgets('delete confirms and reports the deletion', (tester) async {
    _tall(tester);
    final api = FakeTainaApi(delay: Duration.zero);
    final file = (await api.file(rkey: '3m7d1wyzr4c8u')).value!;
    var deleted = false;

    await tester.pumpWidget(
      _app(
        FileDetailScreen(
          session: FakeSessionGateway(api: api),
          actions: FakeFileActions(),
          file: file,
          onDeleted: () => deleted = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();

    expect(find.text('Excluir "${file.name}"?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Excluir'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });

  testWidgets('a forbidden download turns the screen into the access request', (
    tester,
  ) async {
    _tall(tester);
    final thumbApi = FakeTainaApi(delay: Duration.zero);
    final denied = _DeniedApi();
    final file = (await thumbApi.file(rkey: '3m7d1wyzr4c8u')).value!;
    var requested = false;

    await tester.pumpWidget(
      _app(
        FileDetailScreen(
          session: FakeSessionGateway(
            api: denied,
            thumbnails: ThumbnailStore(api: thumbApi),
          ),
          actions: FakeFileActions(),
          file: file,
          onRequested: () => requested = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Baixar'));
    await tester.pumpAndSettle();

    expect(find.text('Esta casa é particular'), findsOneWidget);
    expect(find.text('Baixar'), findsNothing);

    await tester.tap(find.widgetWithText(TainaSecondaryButton, 'Pedir acesso'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Pedir acesso'));
    await tester.pumpAndSettle();

    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(denied.requests, 1);

    await tester.tap(find.widgetWithText(TextButton, 'Entendi'));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
  });
}
