import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/account/account_screen.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

Widget _app({required DevicesApi api, Future<void> Function()? onSignOut}) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: AccountScreen(
      session: FakeSession(api, me: identity(ana)),
      onSignOut: onSignOut ?? () async {},
      hostDisplay: 'taina.sapukai.ts.net',
      cleartext: true,
    ),
  );
}

DevicesApi _devicesApi() {
  return DevicesApi(FakeTainaApi(delay: Duration.zero), const [
    currentDevice,
    otherDevice,
  ]);
}

void _large(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('the account reads identity, community and devices', (
    tester,
  ) async {
    _large(tester);
    await tester.pumpWidget(_app(api: _devicesApi()));
    await tester.pumpAndSettle();

    expect(find.text('Conta'), findsOneWidget);
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('@ana'), findsOneWidget);
    expect(find.text('Zelador'), findsOneWidget);
    expect(find.text('Tekoa Sapukai'), findsOneWidget);
    expect(find.text('taina.sapukai.ts.net'), findsOneWidget);
    expect(find.text('Versão da caixa: 0.6.0'), findsOneWidget);
    expect(find.text('iPhone da Ana'), findsOneWidget);
    expect(find.text('Este aparelho'), findsOneWidget);
    expect(find.text('Tablet da Ana'), findsOneWidget);
    expect(find.text('Identificação deste aparelho'), findsOneWidget);
    expect(find.textContaining('http'), findsOneWidget);
  });

  testWidgets('the other device revokes after a confirmation', (tester) async {
    _large(tester);
    final DevicesApi api = _devicesApi();
    await tester.pumpWidget(_app(api: api));
    await tester.pumpAndSettle();

    expect(find.text('Revogar'), findsOneWidget);
    await tester.tap(find.text('Revogar'));
    await tester.pumpAndSettle();

    expect(find.text('Revogar o acesso deste aparelho?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Revogar'));
    await tester.pumpAndSettle();

    expect(api.revoked, [otherDevice.publicId]);
    expect(find.textContaining('Revogado em'), findsOneWidget);
  });

  testWidgets('the password change says the mismatch on the spot', (
    tester,
  ) async {
    _large(tester);
    await tester.pumpWidget(_app(api: _devicesApi()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'novasenha');
    await tester.enterText(find.byType(TextField).at(2), 'outra');
    await tester.tap(find.text('Trocar minha senha'));
    await tester.pumpAndSettle();

    expect(find.text('As duas senhas não são iguais.'), findsOneWidget);
  });

  testWidgets('signing out goes through the orchestrator callback', (
    tester,
  ) async {
    _large(tester);
    bool signedOut = false;
    await tester.pumpWidget(
      _app(
        api: _devicesApi(),
        onSignOut: () async {
          signedOut = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sair da comunidade'));
    await tester.pumpAndSettle();

    expect(find.text('Sair da comunidade?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Sair'));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });
}
