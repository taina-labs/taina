import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/account/account_screen.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

Widget _app({
  required TainaApi api,
  Me? me,
  Future<void> Function()? onSignOut,
}) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: AccountScreen(
      session: FakeSession(api, me: me ?? identity(ana)),
      onSignOut: onSignOut ?? () async {},
      hostDisplay: 'taina.sapukai.ts.net',
      cleartext: true,
    ),
  );
}

Future<FakeTainaApi> _api() async {
  final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
  await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
  return api;
}

void _large(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('the account shows identity and the available destinations', (
    tester,
  ) async {
    _large(tester);
    await tester.pumpWidget(_app(api: await _api()));
    await tester.pumpAndSettle();

    expect(find.text('Conta'), findsOneWidget);
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Zelador, Tekoa Sapukai'), findsOneWidget);
    expect(find.text('Pedidos'), findsOneWidget);
    expect(find.text('1 pedido esperando sua resposta'), findsOneWidget);
    expect(find.text('Privacidade'), findsOneWidget);
    expect(find.text('Convidar'), findsOneWidget);
    expect(find.text('Trocar senha'), findsOneWidget);
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('Rolo de câmera'), findsOneWidget);
    expect(find.text('taina.sapukai.ts.net'), findsNothing);
    expect(find.text('Versão da caixa: 0.6.0'), findsNothing);
    expect(find.text('Espaço'), findsNothing);
  });

  testWidgets('a morador does not see the invite row', (tester) async {
    _large(tester);
    await tester.pumpWidget(_app(api: await _api(), me: identity(joana)));
    await tester.pumpAndSettle();

    expect(find.text('Morador, Tekoa Sapukai'), findsOneWidget);
    expect(find.text('Convidar'), findsNothing);
  });

  testWidgets('the password sheet has only the current and new fields', (
    tester,
  ) async {
    _large(tester);
    await tester.pumpWidget(_app(api: await _api()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trocar senha'));
    await tester.pumpAndSettle();

    expect(find.text('Senha atual'), findsOneWidget);
    expect(find.text('Senha nova'), findsOneWidget);
    expect(find.text('Confirme a senha nova'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).at(0), 'atual');
    await tester.enterText(find.byType(TextField).at(1), 'curta');
    await tester.tap(find.text('Trocar minha senha'));
    await tester.pumpAndSettle();

    expect(find.textContaining('8 caracteres'), findsOneWidget);
  });

  testWidgets('account navigation opens the separate devices page', (
    tester,
  ) async {
    _large(tester);
    await tester.pumpWidget(_app(api: await _api()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dispositivos'));
    await tester.pumpAndSettle();

    expect(find.text('Dispositivos'), findsOneWidget);
  });

  testWidgets('signing out goes through the orchestrator after confirmation', (
    tester,
  ) async {
    _large(tester);
    bool signedOut = false;
    await tester.pumpWidget(
      _app(
        api: await _api(),
        onSignOut: () async {
          signedOut = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sair').first);
    await tester.pumpAndSettle();

    expect(find.text('Sair da comunidade?'), findsOneWidget);
    await tester.tap(find.text('Sair').last);
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });
}
