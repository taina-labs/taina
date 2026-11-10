import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/saude/saude_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

Widget _app(SessionGateway session) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: SaudeScreen(session: session),
  );
}

void main() {
  testWidgets('the panel reads the box facts and offers the backup to the '
      'zeladora', (tester) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(find.text('Saúde da comunidade'), findsOneWidget);
    expect(find.text('Disco'), findsOneWidget);
    expect(find.text('Último backup'), findsOneWidget);
    expect(find.text('Trabalhos da caixa'), findsNothing);
    expect(find.text('Fazer backup agora'), findsOneWidget);

    await tester.tap(find.text('Fazer backup agora'));
    await tester.pumpAndSettle();

    expect(find.text('Backup agendado'), findsOneWidget);
    expect(
      find.textContaining('A caixa faz o backup em seguida'),
      findsOneWidget,
    );
  });

  testWidgets('a morador reads the panel without the button', (tester) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    expect(find.text('Disco'), findsOneWidget);
    expect(find.text('Último backup'), findsOneWidget);
    expect(find.text('Fazer backup agora'), findsNothing);
  });
}
