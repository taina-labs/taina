import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/files/upload_screen.dart';
import 'package:okena_app/src/session/upload_center.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fakes.dart';

final class _UploadApi implements TainaApi {
  _UploadApi(this.handler);

  final Future<TainaResult<FileRecord>> Function(
    int attempt,
    UploadProgress? progress,
  )
  handler;
  int attempts = 0;
  final List<String?> folders = [];

  @override
  Future<TainaResult<FileRecord>> upload({
    required String filePath,
    required String name,
    required String mime,
    String? folderRkey,
    UploadProgress? progress,
  }) {
    attempts += 1;
    folders.add(folderRkey);
    return handler(attempts, progress);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FileRecord _record(UploadRequest request) {
  return FileRecord(
    rkey: 'uploaded-${request.name}',
    cid: 'cid-${request.name}',
    blobCid: 'blob-${request.name}',
    sha256: 'sha-${request.name}',
    name: request.name,
    mime: request.mime,
    size: 100,
    zona: Zona.casa,
    folder: request.folderRkey,
    takenAt: null,
    width: null,
    height: null,
    rendition: Rendition.none,
    deletedAt: null,
    createdAt: '2026-03-11T09:30:00Z',
    updatedAt: '2026-03-11T09:30:00Z',
  );
}

const _request = UploadRequest(
  path: '/private/arquivo.pdf',
  name: 'arquivo.pdf',
  mime: 'application/pdf',
  folderRkey: 'folder-1',
  folderName: 'Atas',
);

Widget _app(Widget home) => MaterialApp(theme: TainaTheme.data, home: home);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'shows real transport progress and leaving keeps the upload alive',
    (tester) async {
      _tall(tester);
      final completed = Completer<TainaResult<FileRecord>>();
      final api = _UploadApi((_, progress) {
        progress?.call(50, 100);
        return completed.future;
      });
      final center = UploadCenter(gateway: FakeSessionGateway(api: api));
      late BuildContext routeContext;

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (context) {
                        routeContext = context;
                        return EnviarScreen(
                          center: center,
                          request: _request,
                          onBack: () => Navigator.of(routeContext).pop(),
                        );
                      },
                    ),
                  );
                },
                child: const Text('Abrir envio'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir envio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('Enviando arquivo.pdf'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('Guardando na casa.'), findsOneWidget);
      expect(api.folders, ['folder-1']);
      expect(center.isUploading, isTrue);

      await tester.tap(find.text('Documentos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(center.isUploading, isTrue);

      completed.complete(Ok(_record(_request)));
      await tester.pump();
      await tester.pump();
      expect(center.state, isA<UploadSucceeded>());
      center.dispose();
    },
  );

  testWidgets('network failure can retry and reports completion', (
    tester,
  ) async {
    _tall(tester);
    final api = _UploadApi((attempt, _) async {
      if (attempt == 1) return const Err(NetworkError());
      return Ok(_record(_request));
    });
    final center = UploadCenter(gateway: FakeSessionGateway(api: api));
    var completed = false;

    await tester.pumpWidget(
      _app(
        EnviarScreen(
          center: center,
          request: _request,
          onCompleted: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Não deu para enviar'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(api.attempts, 2);
    expect(center.state, isA<UploadSucceeded>());
    expect(find.text('Arquivo guardado na sua casa.'), findsOneWidget);
    expect(completed, isTrue);
    center.dispose();
  });

  testWidgets('quota error offers the space route instead of retry', (
    tester,
  ) async {
    _tall(tester);
    const quota = ApiError(
      code: 'storage_quota_exceeded',
      status: 422,
      serverMessage: 'A cota acabou.',
    );
    final api = _UploadApi((_, _) async => const Err(quota));
    final center = UploadCenter(gateway: FakeSessionGateway(api: api));
    var openedSpace = false;

    await tester.pumpWidget(
      _app(
        EnviarScreen(
          center: center,
          request: _request,
          onViewSpace: () => openedSpace = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ver espaço'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsNothing);
    await tester.tap(find.text('Ver espaço'));
    expect(openedSpace, isTrue);
    center.dispose();
  });
}
