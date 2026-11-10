import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/home/home.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fake_gateway.dart';

Widget _app(Widget child) => MaterialApp(theme: TainaTheme.data, home: child);

Future<void> _pumpHome(
  WidgetTester tester, {
  required HomeTestGateway gateway,
  DateTime Function()? clock,
  HomeOpenFile? onOpenFile,
  HomeOpenDestination? onOpenMural,
  HomeOpenDestination? onOpenRequests,
}) async {
  await tester.pumpWidget(
    _app(
      HomeScreen(
        gateway: gateway,
        clock: clock ?? () => DateTime(2026, 11, 9, 10),
        onOpenFile: onOpenFile,
        onOpenMural: onOpenMural,
        onOpenRequests: onOpenRequests,
      ),
    ),
  );
}

void main() {
  testWidgets('the home greets, names the community and fills the sections', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway();
    await _pumpHome(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Bom dia,'), findsOneWidget);
    expect(find.text('Tekoa Sapukai'), findsOneWidget);
    expect(find.text('Espaço da comunidade'), findsOneWidget);
    expect(find.textContaining('livres'), findsOneWidget);
    expect(find.text('RECENTES'), findsOneWidget);
    expect(find.text('Apresentacao na escola.mp4'), findsOneWidget);
    expect(find.textContaining('na praça'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('MURAL'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MURAL'), findsOneWidget);
    expect(
      find.text('O sistema fez um ato registrado na comunidade.'),
      findsNWidgets(3),
    );

    await tester.scrollUntilVisible(
      find.text('Pedidos de acesso'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pedidos de acesso'), findsOneWidget);
    expect(find.text('1 pedido esperando'), findsOneWidget);
  });

  testWidgets('the afternoon greeting follows the injected clock', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway();
    await _pumpHome(
      tester,
      gateway: gateway,
      clock: () => DateTime(2026, 11, 9, 15),
    );
    await tester.pumpAndSettle();
    expect(find.text('Boa tarde,'), findsOneWidget);
  });

  testWidgets('the recent, mural and requests rows navigate by callback', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway();
    FileRecord? opened;
    int mural = 0;
    int requests = 0;
    await _pumpHome(
      tester,
      gateway: gateway,
      onOpenFile: (FileRecord file) => opened = file,
      onOpenMural: () => mural++,
      onOpenRequests: () => requests++,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apresentacao na escola.mp4'));
    expect(opened?.name, 'Apresentacao na escola.mp4');

    await tester.scrollUntilVisible(
      find.text('MURAL'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.text('O sistema fez um ato registrado na comunidade.').first,
    );
    expect(mural, 1);

    await tester.scrollUntilVisible(
      find.text('Pedidos de acesso'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pedidos de acesso'));
    expect(requests, 1);
  });

  testWidgets('a failed storage card retries only itself', (tester) async {
    final HomeTestGateway gateway = HomeTestGateway();
    gateway.failStats = true;
    await _pumpHome(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível consultar o espaço da comunidade agora.'),
      findsOneWidget,
    );
    final int recentCalls = gateway.recentCalls;

    gateway.failStats = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.text('Espaço da comunidade'), findsOneWidget);
    expect(gateway.storageCalls, 2);
    expect(gateway.recentCalls, recentCalls);
  });

  testWidgets('a failed recent list shows the error and the retry', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway();
    gateway.failRecent = true;
    await _pumpHome(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text(const NetworkError().message), findsOneWidget);

    gateway.failRecent = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Apresentacao na escola.mp4'), findsOneWidget);
  });

  testWidgets('the home waits behind the loading state', (tester) async {
    final HomeTestGateway gateway = HomeTestGateway(
      delay: const Duration(milliseconds: 120),
    );
    await _pumpHome(tester, gateway: gateway);
    await tester.pump();

    expect(find.byType(TainaLoadingList), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(TainaLoadingList), findsNothing);
    expect(find.text('RECENTES'), findsOneWidget);
  });
}
