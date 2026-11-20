import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/members/invite_model.dart';
import 'package:okena_app/src/features/members/members_clipboard.dart';
import 'package:okena_app/src/features/members/members_model.dart';
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

final class _Clipboard implements MembersClipboard {
  final List<String> copied = [];

  @override
  Future<void> writeText(String text) async {
    copied.add(text);
  }
}

void main() {
  testWidgets('a zelador sees the roster, invite action and footer', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(find.text('Moradores'), findsOneWidget);
    expect(find.text('Convidar'), findsOneWidget);
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Joana Reis'), findsOneWidget);
    expect(find.text('Rafael Nunes'), findsOneWidget);
    expect(find.text('Zelador, entrou em 2026'), findsOneWidget);
    expect(find.text('Morador, entrou em 2026'), findsNWidgets(2));
    expect(find.bySemanticsLabel('Ações para Ana Souza'), findsNothing);
    expect(find.bySemanticsLabel('Ações para Joana Reis'), findsOneWidget);
    expect(find.bySemanticsLabel('Ações para Rafael Nunes'), findsOneWidget);
    expect(
      find.text(
        'Quem cuida da nuvem só convida pessoas. Ninguém pode mexer nos '
        'arquivos de outra pessoa.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a morador sees the roster and no zelador actions', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    expect(find.text('Convidar'), findsNothing);
    expect(find.bySemanticsLabel('Ações para Ana Souza'), findsNothing);
    expect(find.bySemanticsLabel('Ações para Rafael Nunes'), findsNothing);
    expect(find.text('Quem cuida da nuvem só convida pessoas.'), findsNothing);
    expect(find.text('Joana Reis'), findsOneWidget);
  });

  testWidgets('the optional invite callback can hand navigation to the app', (
    tester,
  ) async {
    bool opened = false;
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(
      MaterialApp(
        theme: TainaTheme.data,
        home: MembersScreen(
          session: FakeSession(api, me: identity(ana)),
          onInvite: () async {
            opened = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Convidar'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(find.text('Convidar moradores'), findsNothing);
  });

  testWidgets('search filters names and shows the empty search state', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'RAFA');
    await tester.pumpAndSettle();
    expect(find.text('Rafael Nunes'), findsOneWidget);
    expect(find.text('Ana Souza'), findsNothing);
    expect(find.text('Joana Reis'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Julia');
    await tester.pumpAndSettle();
    expect(find.text('Ninguém com esse nome'), findsOneWidget);
    expect(
      find.text('Confira a escrita ou procure por outro nome.'),
      findsOneWidget,
    );
  });

  testWidgets('an active person has only the reset-link action', (
    tester,
  ) async {
    final _Clipboard clipboard = _Clipboard();
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(
      MaterialApp(
        theme: TainaTheme.data,
        home: MembersScreen(
          session: FakeSession(api, me: identity(ana)),
          clipboard: clipboard,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder activeRow = find.ancestor(
      of: find.text('Joana Reis'),
      matching: find.byType(TainaListRow),
    );
    await tester.tap(
      find.descendant(of: activeRow, matching: find.byType(TainaIconButton)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gerar link de redefinição de senha'), findsOneWidget);
    expect(find.text('Cancelar convite'), findsNothing);
    expect(find.text('Tornar zelador(a)'), findsNothing);
    expect(find.text('Desativar conta'), findsNothing);
    expect(find.text('Reativar conta'), findsNothing);

    await tester.tap(find.text('Gerar link de redefinição de senha'));
    await tester.pumpAndSettle();
    expect(find.text('Link de redefinição de senha'), findsOneWidget);
    expect(find.textContaining('taina://redefinir/'), findsOneWidget);
    await tester.tap(find.text('Copiar link'));
    await tester.pumpAndSettle();
    expect(find.text('Link copiado'), findsOneWidget);
    expect(clipboard.copied.single, startsWith('taina://redefinir/'));
  });

  testWidgets('a pending invite has only cancel and can be cancelled', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.inviteMember(papel: Papel.morador);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    final Finder pendingRow = find.ancestor(
      of: find.text('Convite pendente'),
      matching: find.byType(TainaListRow),
    );
    await tester.tap(
      find.descendant(of: pendingRow, matching: find.byType(TainaIconButton)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cancelar convite'), findsOneWidget);
    expect(find.text('Gerar link de redefinição de senha'), findsNothing);
    expect(find.text('Tornar zelador(a)'), findsNothing);
    expect(find.text('Desativar conta'), findsNothing);
    expect(find.text('Reativar conta'), findsNothing);

    await tester.tap(find.text('Cancelar convite'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar convite?'), findsOneWidget);
    expect(find.textContaining('O link para de valer'), findsOneWidget);
    await tester.tap(find.text('Cancelar convite'));
    await tester.pumpAndSettle();
    expect(find.text('Convite pendente'), findsNothing);
  });

  testWidgets('inviting a zelador shows the link, QR and copy toast', (
    tester,
  ) async {
    final _Clipboard clipboard = _Clipboard();
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(
      MaterialApp(
        theme: TainaTheme.data,
        home: MembersScreen(
          session: FakeSession(api, me: identity(ana)),
          clipboard: clipboard,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Convidar'));
    await tester.pumpAndSettle();
    expect(find.text('Convidar moradores'), findsOneWidget);
    expect(find.text('Vê a praça e ganha uma casa própria.'), findsOneWidget);
    expect(
      find.textContaining('Cuida da máquina: disco, backups e convites.'),
      findsOneWidget,
    );

    final Finder zeladorCard = find.byWidgetPredicate(
      (Widget widget) => widget is TainaRadioCard && widget.title == 'Zelador',
    );
    await tester.tap(zeladorCard);
    await tester.pumpAndSettle();
    expect((tester.widget<TainaRadioCard>(zeladorCard)).selected, isTrue);

    await tester.tap(find.text('Criar convite'));
    await tester.pumpAndSettle();
    expect(
      find.text('Convite criado. Envie o link para a pessoa.'),
      findsOneWidget,
    );
    expect(find.text('O convite vale por 7 dias.'), findsOneWidget);
    expect(find.byType(QRCard), findsOneWidget);
    final Finder inviteUrl = find.textContaining('taina://convite/');
    expect(inviteUrl, findsOneWidget);

    await tester.ensureVisible(find.text('Copiar link'));
    await tester.tap(find.text('Copiar link'));
    await tester.pumpAndSettle();
    expect(find.text('Link copiado.'), findsOneWidget);
    expect(clipboard.copied.single, startsWith('taina://convite/'));

    final List<Ava> members = (await api.members()).value!.items;
    final Ava createdInvite = members.singleWhere(MembersModel.isPendingInvite);
    expect(createdInvite.papel, Papel.zelador);
    expect(
      MembersInviteModel.linkFor(
        MemberInvite(
          ava: createdInvite,
          token: 'web-token',
          inviteUrl: 'taina://convite/fallback',
          webUrl: 'https://taina.local/c/web-token',
        ),
      ),
      'https://taina.local/c/web-token',
    );
  });
}
