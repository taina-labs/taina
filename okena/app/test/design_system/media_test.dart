import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/components/actions.dart';
import 'package:okena_app/src/design_system/components/media.dart';
import 'package:okena_app/src/design_system/theme.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  );
}

void main() {
  group('upload progress mapping', () {
    test('clamps finite values and treats invalid values as indeterminate', () {
      expect(normalizeUploadProgress(-0.2), 0);
      expect(normalizeUploadProgress(0.7), 0.7);
      expect(normalizeUploadProgress(1.4), 1);
      expect(normalizeUploadProgress(double.nan), isNull);
      expect(normalizeUploadProgress(double.infinity), isNull);
      expect(normalizeUploadProgress(null), isNull);
    });

    test('maps statuses to pt-BR labels', () {
      expect(UploadRowStatus.values.map(uploadRowStatusLabel), [
        'Enviando',
        'Não deu para enviar',
        'Não deu para enviar',
      ]);
    });
  });

  group('UploadRow', () {
    testWidgets('shows determinate progress with the file name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const UploadRow(
            fileName: 'foto.jpg',
            status: UploadRowStatus.uploading,
            progress: 0.45,
          ),
        ),
      );

      expect(find.text('Enviando foto.jpg'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      final LinearProgressIndicator progress = tester.widget(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, 0.45);
    });

    testWidgets('shows quota and network error states', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UploadRow(
                fileName: 'video.mp4',
                status: UploadRowStatus.quotaExceeded,
                onViewSpace: _noop,
              ),
              UploadRow(
                fileName: 'documento.pdf',
                status: UploadRowStatus.networkError,
                onRetry: _noop,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Não deu para enviar'), findsNWidgets(2));
      expect(
        find.text(
          'O espaço da comunidade acabou. Peça a quem cuida da nuvem para liberar.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'A conexão caiu no meio do envio. O arquivo não saiu da sua casa.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ver espaço'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('offers retry for a network error', (tester) async {
      int retries = 0;
      await tester.pumpWidget(
        _app(
          UploadRow(
            fileName: 'arquivo.pdf',
            status: UploadRowStatus.networkError,
            onRetry: () => retries++,
          ),
        ),
      );

      expect(find.text('Tentar de novo'), findsOneWidget);
      await tester.tap(find.text('Tentar de novo'));
      expect(retries, 1);
    });
  });

  testWidgets('viewer chrome forwards close and can hide controls', (
    tester,
  ) async {
    int closed = 0;
    int previous = 0;
    int next = 0;
    await tester.pumpWidget(
      _app(
        ViewerChrome(
          counter: '3 de 24',
          caption: 'Trilha da praia, 4 de outubro, na praça',
          onClose: () => closed++,
          onPrevious: () => previous++,
          onNext: () => next++,
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    );

    expect(find.text('3 de 24'), findsOneWidget);
    expect(
      find.text('Trilha da praia, 4 de outubro, na praça'),
      findsOneWidget,
    );
    final Finder iconButtons = find.byType(TainaIconButton);
    expect(iconButtons, findsNWidgets(3));
    await tester.tap(iconButtons.at(0));
    expect(closed, 1);
    await tester.tap(iconButtons.at(1));
    await tester.tap(iconButtons.at(2));
    expect(previous, 1);
    expect(next, 1);

    await tester.pumpWidget(
      _app(
        ViewerChrome(
          counter: '3 de 24',
          caption: 'Trilha da praia, 4 de outubro, na praça',
          onClose: () => closed++,
          controlsVisible: false,
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    expect(find.byType(TainaIconButton), findsNothing);
  });
}

void _noop() {}
