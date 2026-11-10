import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/members/members_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

Widget _app(SessionGateway session) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: MembersScreen(session: session),
  );
}

void main() {
  testWidgets('the zeladora sees the roster, the count and the invite act', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(find.text('Moradores'), findsOneWidget);
    expect(find.byTooltip('Convidar pessoa'), findsOneWidget);
    expect(find.text('3 PESSOAS'), findsOneWidget);
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Você'), findsOneWidget);
    expect(find.text('Joana Reis'), findsOneWidget);
    expect(find.text('Rafael Nunes'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNWidgets(2));
  });

  testWidgets('a morador reads the list and gets no acts', (tester) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    expect(find.text('3 PESSOAS'), findsOneWidget);
    expect(find.byTooltip('Convidar pessoa'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(
      find.textContaining('Quem cuida da comunidade convida'),
      findsOneWidget,
    );
  });

  testWidgets('the invite link is shown once and copied', (tester) async {
    final List<MethodCall> platformCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Convidar pessoa'));
    await tester.pumpAndSettle();
    expect(find.text('Criar convite'), findsOneWidget);

    await tester.tap(find.text('Criar convite'));
    await tester.pumpAndSettle();

    expect(find.text('Convite criado'), findsOneWidget);
    expect(find.textContaining('taina://convite/'), findsOneWidget);
    expect(find.textContaining('O link vale uma vez só'), findsOneWidget);

    await tester.tap(find.text('Copiar link'));
    await tester.pumpAndSettle();

    expect(find.text('Copiado'), findsOneWidget);
    final MethodCall clipboard = platformCalls.firstWhere(
      (MethodCall call) => call.method == 'Clipboard.setData',
    );
    expect(
      (clipboard.arguments as Map<Object?, Object?>)['text'],
      startsWith('taina://convite/'),
    );
  });

  testWidgets('deactivating a person confirms first and then says so', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    final Finder row = find.ancestor(
      of: find.text('Rafael Nunes'),
      matching: find.byType(TainaRowCard),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.more_horiz)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Desativar conta'));
    await tester.pumpAndSettle();
    expect(find.text('Desativar conta?'), findsOneWidget);
    expect(
      find.textContaining('deixa de entrar na comunidade'),
      findsOneWidget,
    );

    await tester.tap(find.text('Desativar'));
    await tester.pumpAndSettle();

    expect(find.text('Conta desativada'), findsOneWidget);
  });
}
