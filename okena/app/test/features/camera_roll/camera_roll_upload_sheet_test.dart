import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/camera_roll/media_picker.dart';
import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/features/files/files_screen.dart';
import 'package:okena_core/okena_core.dart';

import 'support/camera_roll_fakes.dart';

final class _FileActionsFake implements FileActions {
  @override
  Future<PickedFileOutcome> pick() async => const PickedFileCancelled();

  @override
  Future<String?> open(String path) async => null;

  @override
  Future<String?> share(String path, {String? subject}) async => null;
}

FileRecord _record(UploadCall call) {
  return FileRecord(
    rkey: 'uploaded-${call.name}',
    cid: 'cid-${call.name}',
    blobCid: 'blob-${call.name}',
    sha256: 'sha-${call.name}',
    name: call.name,
    mime: call.mime,
    size: 1,
    zona: Zona.casa,
    folder: call.folderRkey,
    takenAt: null,
    width: null,
    height: null,
    rendition: Rendition.none,
    deletedAt: null,
    createdAt: '2026-03-11T09:30:00Z',
    updatedAt: '2026-03-11T09:30:00Z',
  );
}

Widget _app(Widget home) => MaterialApp(theme: TainaTheme.data, home: home);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('root opens the media sheet, stops, retries and reloads files', (
    tester,
  ) async {
    _tall(tester);
    final activeUpload = Completer<TainaResult<FileRecord>>();
    late final CameraUploadApiFake api;
    api = CameraUploadApiFake(
      uploadHandler: (call) {
        if (call.name == 'um.jpg' && api.uploadCalls.length == 1) {
          return activeUpload.future;
        }
        return Future.value(Ok(_record(call)));
      },
    );
    final session = CameraSessionFake(api: api);
    final picker = CameraMediaPickerFake()
      ..photosOutcome = MediaPickerSelected([
        picked('um.jpg', 'image/jpeg'),
        picked('dois.mp4', 'video/mp4'),
      ]);

    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: session,
          actions: _FileActionsFake(),
          mediaPicker: picker,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Adicionar fotos e vídeos'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Adicionar fotos e vídeos'));
    await tester.pumpAndSettle();

    expect(find.text('Adicionar fotos e vídeos'), findsOneWidget);
    expect(find.text('Na sua casa. Nada vai para a praça.'), findsOneWidget);
    expect(find.text('Este envio pode usar dados móveis.'), findsOneWidget);
    expect(find.text('Escolher fotos e vídeos'), findsOneWidget);
    expect(find.text('Tirar foto'), findsOneWidget);
    expect(picker.lostDataCalls, 1);

    await tester.tap(find.text('Escolher fotos e vídeos'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Tentados: 1 de 2'), findsOneWidget);
    expect(find.text('Enviados: 0'), findsOneWidget);
    expect(find.text('um.jpg'), findsOneWidget);
    expect(find.text('Mantenha o Tainá aberto'), findsOneWidget);
    expect(find.text('Parar os próximos envios'), findsOneWidget);
    expect(
      find.text('O envio atual continua; os demais não começarão.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Parar os próximos envios'));
    await tester.pump();
    activeUpload.complete(Ok(_record(api.uploadCalls.first)));
    await tester.pump();
    await tester.pump();

    expect(find.text('Enviados: 1 de 2. Não começaram: 1.'), findsOneWidget);
    expect(find.text('Tentar os que faltam'), findsOneWidget);
    expect(api.uploadCalls, hasLength(1));

    await tester.tap(find.text('Tentar os que faltam'));
    await tester.pumpAndSettle();
    expect(find.text('2 de 2 arquivos foram enviados.'), findsOneWidget);
    expect(find.text('Ver arquivos'), findsOneWidget);

    await tester.tap(find.text('Ver arquivos'));
    await tester.pumpAndSettle();

    expect(api.uploadCalls.map((call) => call.name), ['um.jpg', 'dois.mp4']);
    expect(api.uploadCalls.every((call) => call.folderRkey == null), isTrue);
    expect(api.folderContentsCalls, 2);
  });

  testWidgets('camera action captures and uploads one photo', (tester) async {
    _tall(tester);
    final api = CameraUploadApiFake();
    final session = CameraSessionFake(api: api);
    final picker = CameraMediaPickerFake()
      ..cameraOutcome = MediaPickerSelected([
        picked('captura.jpg', 'image/jpeg'),
      ]);

    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: session,
          actions: _FileActionsFake(),
          mediaPicker: picker,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Adicionar fotos e vídeos'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tirar foto'));
    await tester.pumpAndSettle();

    expect(picker.cameraCalls, 1);
    expect(api.uploadCalls.map((call) => call.name), ['captura.jpg']);
    expect(find.text('1 de 1 arquivos foram enviados.'), findsOneWidget);
  });

  testWidgets('root action is absent when the picker is not provided', (
    tester,
  ) async {
    _tall(tester);
    final api = CameraUploadApiFake();

    await tester.pumpWidget(
      _app(
        FilesScreen(
          session: CameraSessionFake(api: api),
          actions: _FileActionsFake(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Adicionar fotos e vídeos'), findsNothing);
  });
}
