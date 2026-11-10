import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/storage/storage_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

Widget _app(SessionGateway session) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: StorageScreen(session: session),
  );
}

void _large(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('the panel reads the portrait and the by-kind rows', (
    tester,
  ) async {
    _large(tester);
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(find.text('Armazenamento'), findsOneWidget);
    expect(find.text('ESPAÇO DA COMUNIDADE'), findsOneWidget);
    expect(find.textContaining('Uso por tipo'), findsOneWidget);
    expect(find.text('Fotos'), findsNWidgets(2));
    expect(find.text('Vídeos'), findsOneWidget);
    expect(find.text('Documentos'), findsOneWidget);
    expect(find.text('Outros'), findsOneWidget);
    expect(find.text('Arquivos'), findsOneWidget);
    expect(find.text('Lixeira'), findsOneWidget);
    expect(find.text('Mudar o limite'), findsOneWidget);
  });

  testWidgets('a morador gets no quota card', (tester) async {
    _large(tester);
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    expect(find.text('ESPAÇO DA COMUNIDADE'), findsOneWidget);
    expect(find.text('Mudar o limite'), findsNothing);
    expect(find.text('LIMITE DA COMUNIDADE'), findsNothing);
  });

  testWidgets('the zeladora changes the quota and the panel follows', (
    tester,
  ) async {
    _large(tester);
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mudar o limite'));
    await tester.pumpAndSettle();

    expect(find.text('Gigabytes'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '500');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('500,0 GB por mês'), findsOneWidget);
  });
}
