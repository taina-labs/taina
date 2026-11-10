import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/requests/requests_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

final class _FailingPedidosApi implements TainaApi {
  @override
  Future<TainaResult<Page<Pedido>>> accessRequests() async =>
      const Err(offline);

  @override
  Future<TainaResult<Page<Pedido>>> myRequests() async => const Err(offline);

  @override
  Future<TainaResult<Page<Concessao>>> grants({required GrantRole role}) async {
    return const Err(offline);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(SessionGateway session) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: RequestsScreen(session: session),
  );
}

void main() {
  testWidgets('the received list carries the decision', (tester) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    await tester.pumpWidget(_app(FakeSession(api)));
    await tester.pumpAndSettle();

    expect(find.text('Pedidos'), findsOneWidget);
    expect(find.text('1 PEDIDO ESPERANDO SUA RESPOSTA'), findsOneWidget);
    expect(find.text('Pendente'), findsOneWidget);
    expect(
      find.text('Pediu acesso a Estatuto da associacao.pdf'),
      findsOneWidget,
    );
    expect(find.text('Aprovar'), findsOneWidget);
    expect(find.text('Negar'), findsOneWidget);
  });

  testWidgets('a failed load shows the error with a way out', (tester) async {
    await tester.pumpWidget(_app(FakeSession(_FailingPedidosApi())));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível falar com a comunidade.'),
      findsOneWidget,
    );
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('approving says the outcome and empties the pending list', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    await tester.pumpWidget(_app(FakeSession(api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aprovar'));
    await tester.pumpAndSettle();

    expect(find.text('Pedido aprovado'), findsOneWidget);
    expect(
      find.text(
        'Acesso a Estatuto da associacao.pdf liberado. A pessoa já pode ler.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum pedido por enquanto'), findsOneWidget);
  });

  testWidgets('denying confirms first and says the person may ask again', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    await tester.pumpWidget(_app(FakeSession(api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Negar'));
    await tester.pumpAndSettle();
    expect(find.text('Negar este pedido?'), findsOneWidget);
    expect(find.textContaining('pode pedir de novo'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Negar'));
    await tester.pumpAndSettle();

    expect(find.text('Pedido negado'), findsOneWidget);
    expect(
      find.text('A pessoa pode pedir de novo quando quiser.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'the accesses tab shows both sides and revokes a standing grant',
    (tester) async {
      final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
      await api.createSession(
        username: 'ana',
        password: 'x',
        deviceName: 'test',
      );
      await tester.pumpWidget(_app(FakeSession(api)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Acessos'));
      await tester.pumpAndSettle();

      expect(find.text('VOCÊ LIBEROU'), findsOneWidget);
      expect(find.text('LIBERADOS PARA VOCÊ'), findsOneWidget);
      expect(find.text('Ativo'), findsOneWidget);
      expect(find.text('Revogado'), findsOneWidget);

      await tester.tap(find.text('Revogar'));
      await tester.pumpAndSettle();
      expect(find.text('Revogar este acesso?'), findsOneWidget);
      expect(find.textContaining('deixa de poder abrir'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Revogar'));
      await tester.pumpAndSettle();

      expect(find.text('Acesso revogado'), findsOneWidget);
      expect(find.textContaining('A pessoa já não pode ler.'), findsOneWidget);
    },
  );
}
