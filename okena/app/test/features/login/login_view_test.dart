import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/login/login_view.dart';
import 'package:okena_app/src/features/login/login_view_model.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/support/session_support.dart';

Widget _app(SessionModel model) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: LoginView(session: model),
  );
}

void main() {
  testWidgets('known community login shows its address and the designed form', (
    tester,
  ) async {
    final composed = makeSession(
      host: testBox('http://box.local'),
      state: const SessionNeedsLogin(),
    );
    await composed.model.restore();

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();

    expect(find.text('Tainá'), findsOneWidget);
    expect(
      find.text('Entre com seu nome na nuvem da sua comunidade.'),
      findsOneWidget,
    );
    expect(find.text('Tekoa Sapukai, box.local'), findsOneWidget);
    expect(find.text('Trocar'), findsOneWidget);
    expect(find.text('Endereço da comunidade'), findsNothing);
    expect(find.text('Seu nome de usuário'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.text('Nome deste aparelho'), findsNothing);
    expect(find.byType(ConnectionNotice), findsOneWidget);
    expect(find.text('Tenho um convite'), findsOneWidget);
  });

  testWidgets('Trocar clears the saved host and shows address entry', (
    tester,
  ) async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );
    await composed.model.restore();

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trocar'));
    await tester.pumpAndSettle();

    expect(find.text('Endereço da comunidade'), findsOneWidget);
    expect(composed.model.host, isNull);
    expect(composed.model.state, isA<SessionNeedsInstance>());
  });

  testWidgets('first access connects and signs in with one submit', (
    tester,
  ) async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (_) async => const Ok(
        Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
      ),
    );
    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();

    expect(find.text('Endereço da comunidade'), findsOneWidget);
    expect(find.text('Conectar'), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), 'http://box.local');
    await tester.pump();
    expect(find.byType(ConnectionNotice), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), 'ana');
    await tester.enterText(find.byType(TextField).at(2), 'segredo');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(composed.model.state, isA<SessionReady>());
    expect(composed.store.current?.device.name, endsWith('de ana'));
  });

  testWidgets('a box without a community keeps the setup card', (tester) async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (_) async =>
          const Ok(Instance(bootstrapped: false, tekoa: null, version: null)),
    );

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'box.local');
    await tester.enterText(find.byType(TextField).at(1), 'ana');
    await tester.enterText(find.byType(TextField).at(2), 'segredo');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('A comunidade ainda não foi criada'), findsOneWidget);
    expect(composed.model.state, isA<SessionNeedsInstance>());
  });

  testWidgets('unreachable address keeps the specific recovery sentence', (
    tester,
  ) async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (_) async => const Err(NetworkError('down')),
    );

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'box.local');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text(LoginViewModel.unreachableMessage), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('the password error and rate-limit sentence are visible', (
    tester,
  ) async {
    final api = ScriptedApi(
      sessionOutcome: const Err(
        ApiError(
          code: 'invalid_credentials',
          status: 401,
          serverMessage: 'Usuário ou senha incorretos.',
        ),
      ),
    );
    final composed = makeSession(
      api: api,
      host: testBox(),
      state: const SessionNeedsLogin(),
    );
    await composed.model.restore();

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'ana');
    await tester.enterText(find.byType(TextField).at(1), 'errada');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Não conseguimos entrar.'), findsOneWidget);
    expect(find.text('Confira a senha e tente de novo.'), findsOneWidget);
  });

  testWidgets('forgot password opens the resolved web sentence', (
    tester,
  ) async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );
    await composed.model.restore();

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esqueci minha senha'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'O Tainá não usa e-mail. Fale com quem cuida da sua comunidade: '
        'essa pessoa gera um link para você criar uma senha nova.',
      ),
      findsOneWidget,
    );
    expect(find.text('Fechar'), findsOneWidget);
  });
}
