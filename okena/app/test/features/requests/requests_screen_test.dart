import 'package:material_ui/material_ui.dart' hide Page;
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

final class _EmptyPedidosApi implements TainaApi {
  @override
  Future<TainaResult<Page<Pedido>>> accessRequests() async =>
      Ok(Page(items: const [], nextCursor: null));

  @override
  Future<TainaResult<Page<Pedido>>> myRequests() async =>
      Ok(Page(items: const [], nextCursor: null));

  @override
  Future<TainaResult<Page<Concessao>>> grants({
    required GrantRole role,
  }) async => Ok(Page(items: const [], nextCursor: null));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(SessionGateway session, {bool showSentState = false}) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: RequestsScreen(
      session: session,
      showSentState: showSentState,
      sentTo: 'Ana',
    ),
  );
}

void main() {
  testWidgets('renders one combined feed with the pending decision', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    await tester.pumpWidget(_app(FakeSession(api)));
    await tester.pumpAndSettle();

    expect(find.text('Pedidos'), findsOneWidget);
    expect(find.text('Joana Reis pediu acesso'), findsOneWidget);
    expect(find.text('Recusar'), findsOneWidget);
    expect(find.text('Dar acesso'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Os pedidos resolvidos ficam visíveis. Você pode mudar de ideia '
        'quando quiser.',
      ),
      findsOneWidget,
    );
    expect(find.text('Recebidos'), findsNothing);
    expect(find.text('Enviados'), findsNothing);
    expect(find.text('Acessos'), findsNothing);
  });

  testWidgets('shows the empty state when the combined feed is empty', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FakeSession(_EmptyPedidosApi())));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum pedido ainda'), findsOneWidget);
    expect(
      find.text(
        'Quando alguém pedir para abrir um arquivo da sua casa, aparece aqui.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed load shows an error with a retry action', (
    tester,
  ) async {
    await tester.pumpWidget(_app(FakeSession(_FailingPedidosApi())));
    await tester.pumpAndSettle();

    expect(find.text('Não conseguimos carregar os pedidos.'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('approving keeps the granted access visible', (tester) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    await tester.pumpWidget(_app(FakeSession(api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dar acesso'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Acesso a Estatuto da associacao.pdf liberado. '
        'A pessoa já pode ler.',
      ),
      findsOneWidget,
    );
    expect(find.text('Joana Reis recebeu acesso'), findsWidgets);
  });

  testWidgets('refusing keeps the resolved request visible', (tester) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    await tester.pumpWidget(_app(FakeSession(api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();

    expect(
      find.text('A pessoa pode pedir de novo quando quiser.'),
      findsOneWidget,
    );
    expect(find.text('Joana Reis teve o acesso recusado'), findsOneWidget);
    expect(find.textContaining('Acesso recusado em'), findsOneWidget);
  });

  testWidgets('sent state appears above the combined feed', (tester) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    await tester.pumpWidget(_app(FakeSession(api), showSentState: true));
    await tester.pumpAndSettle();

    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(
      find.text('Ana vai decidir. Você vê a resposta aqui em Pedidos.'),
      findsOneWidget,
    );
  });

  testWidgets('the grant kebab offers taking access back', (tester) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    await tester.pumpWidget(_app(FakeSession(api)));
    await tester.pumpAndSettle();

    final Finder kebab = find.byType(TainaIconButton);
    expect(kebab, findsOneWidget);
    await tester.ensureVisible(kebab);
    await tester.tap(kebab);
    await tester.pumpAndSettle();
    expect(find.text('Ações do pedido'), findsOneWidget);
    expect(find.text('Tirar acesso'), findsOneWidget);

    await tester.tap(find.text('Tirar acesso'));
    await tester.pumpAndSettle();
    expect(find.text('Tirar este acesso?'), findsOneWidget);

    await tester.tap(find.text('Tirar acesso').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Acesso a Lista de presenca.pdf revogado'),
      findsOneWidget,
    );
    expect(find.text('Acesso retirado de Joana Reis'), findsOneWidget);
  });
}
