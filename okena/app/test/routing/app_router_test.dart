import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/routing/app_router.dart';
import 'package:okena_app/src/routing/shell_screens.dart';
import 'package:okena_app/src/session/session_composition.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../session/support/session_support.dart';

ShellScreens _screens() {
  return ShellScreens(
    home: (context) => const Scaffold(body: Text('início custom')),
    files: (context) => const Scaffold(body: Text('arquivos custom')),
    gallery: (context) => const Scaffold(body: Text('fotos custom')),
    mural: (context) => const Scaffold(body: Text('mural custom')),
    members: (context) => const Scaffold(body: Text('moradores custom')),
    storage: (context) => const Scaffold(body: Text('armazenamento custom')),
    saude: (context) => const Scaffold(body: Text('saúde custom')),
    requests: (context) => const Scaffold(body: Text('pedidos custom')),
    account: (context) => const Scaffold(body: Text('conta custom')),
  );
}

Widget _app(SessionModel session) {
  return MaterialApp.router(
    theme: TainaTheme.data,
    routerConfig: createSessionRouter(session: session, screens: _screens()),
  );
}

Future<SessionModel> _readyModel() async {
  final fake = FakeTainaApi(delay: Duration.zero);
  final created = await fake.createSession(
    username: 'ana',
    password: 'segredo',
    deviceName: 'Aparelho de teste',
  );
  final session = created.value!;
  return makeSession(
    api: fake,
    host: testBox(),
    storage: InMemorySessionStorage(session),
    state: SessionReady(session.identity),
  ).model;
}

void main() {
  testWidgets('a ready session opens Início with the five tabs', (
    tester,
  ) async {
    final model = await _readyModel();

    await tester.pumpWidget(_app(model));
    await tester.pumpAndSettle();

    expect(find.text('início custom'), findsOneWidget);
    for (final tab in ['Início', 'Arquivos', 'Fotos', 'Mural', 'Mais']) {
      expect(find.text(tab), findsOneWidget);
    }
  });

  testWidgets('tapping a tab switches its stack', (tester) async {
    final model = await _readyModel();

    await tester.pumpWidget(_app(model));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arquivos'));
    await tester.pumpAndSettle();

    expect(find.text('arquivos custom'), findsOneWidget);
  });

  testWidgets('a Mais row and its stack survive a tab round trip', (
    tester,
  ) async {
    final model = await _readyModel();

    await tester.pumpWidget(_app(model));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mais'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moradores'));
    await tester.pumpAndSettle();
    expect(find.text('moradores custom'), findsOneWidget);

    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();
    expect(find.text('início custom'), findsOneWidget);

    await tester.tap(find.text('Mais'));
    await tester.pumpAndSettle();
    expect(find.text('moradores custom'), findsOneWidget);
  });

  testWidgets('checking shows the loading skeleton', (tester) async {
    final composed = makeSession();

    await tester.pumpWidget(_app(composed.model));
    await tester.pump();

    expect(find.byType(TainaLoadingList), findsOneWidget);
  });

  testWidgets('no box opens the setup', (tester) async {
    final composed = makeSession(state: const SessionNeedsInstance());

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();

    expect(find.text('Sua comunidade'), findsOneWidget);
  });

  testWidgets('a saved box without a session opens the login', (tester) async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();

    expect(find.text('Usuário'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('a pending invite opens the invite screen', (tester) async {
    final composed = makeSession(
      host: testBox(),
      state: SessionPendingAuth(
        const PendingAuth(kind: PendingAuthKind.invite, token: 'tk1'),
      ),
    );

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();

    expect(find.text('Aceitar convite'), findsOneWidget);
    expect(find.text('Você foi convidado!'), findsOneWidget);
  });

  testWidgets('a warm deep link moves the ready app to the invite', (
    tester,
  ) async {
    final model = await _readyModel();

    await tester.pumpWidget(_app(model));
    await tester.pumpAndSettle();
    expect(find.text('início custom'), findsOneWidget);

    await model.handleDeepLink(
      Uri.parse('taina://convite/expirado?host=https://other.box'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Este convite expirou ou já foi usado'), findsOneWidget);
  });

  testWidgets('a successful login leaves the login for the shell', (
    tester,
  ) async {
    final model = SessionComposition.fake(host: testBox());
    await model.restore();

    await tester.pumpWidget(_app(model));
    await tester.pumpAndSettle();
    expect(find.text('Entrar'), findsOneWidget);

    await model.login(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Aparelho de teste',
    );
    await tester.pumpAndSettle();

    expect(find.text('início custom'), findsOneWidget);
  });

  testWidgets('leaving the invite returns to the login', (tester) async {
    final composed = makeSession(
      host: testBox(),
      state: SessionPendingAuth(
        const PendingAuth(kind: PendingAuthKind.invite, token: 'expirado'),
      ),
    );

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    expect(find.text('Este convite expirou ou já foi usado'), findsOneWidget);

    await composed.model.leavePendingAuth();
    await tester.pumpAndSettle();

    expect(find.text('Entrar'), findsOneWidget);
  });

  test('the redirect maps every state to its screen', () {
    expect(sessionRedirect(const SessionChecking(), '/'), '/checking');
    expect(sessionRedirect(const SessionNeedsInstance(), '/login'), '/setup');
    expect(sessionRedirect(const SessionNeedsLogin(), '/setup'), '/login');
    expect(
      sessionRedirect(
        SessionPendingAuth(
          const PendingAuth(kind: PendingAuthKind.reset, token: 'tk1'),
        ),
        '/login',
      ),
      '/redefinir',
    );
    expect(sessionRedirect(SessionReady(testMe()), '/login'), '/inicio');
    expect(sessionRedirect(SessionReady(testMe()), '/inicio'), isNull);
    expect(sessionRedirect(SessionReady(testMe()), '/mais/moradores'), isNull);
  });
}
