import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/auth/invite_accept_view.dart';
import 'package:okena_app/src/features/auth/reset_password_view.dart';
import 'package:okena_app/src/session/session_state.dart';

import '../../session/support/session_support.dart';

Widget _app(Widget child) {
  return MaterialApp(theme: TainaTheme.data, home: child);
}

void main() {
  group('invite accept', () {
    testWidgets('a spent token shows the dead end', (tester) async {
      const pending = PendingAuth(
        kind: PendingAuthKind.invite,
        token: 'expirado',
      );
      final composed = makeSession(
        host: testBox(),
        state: const SessionPendingAuth(pending),
      );

      await tester.pumpWidget(
        _app(InviteAcceptView(session: composed.model, pending: pending)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Este convite expirou ou já foi usado'), findsOneWidget);
      expect(find.text('Ir para o login'), findsOneWidget);
    });

    testWidgets('a live token opens the form with the invite copy', (
      tester,
    ) async {
      const pending = PendingAuth(kind: PendingAuthKind.invite, token: 'tk1');
      final composed = makeSession(
        host: testBox(),
        state: const SessionPendingAuth(pending),
      );

      await tester.pumpWidget(
        _app(InviteAcceptView(session: composed.model, pending: pending)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Você foi convidado!'), findsOneWidget);
      expect(find.text('Seu nome de usuário'), findsOneWidget);
      expect(find.text('Criar conta'), findsOneWidget);
    });

    testWidgets('mismatched passwords are the local check', (tester) async {
      const pending = PendingAuth(kind: PendingAuthKind.invite, token: 'tk1');
      final composed = makeSession(
        host: testBox(),
        state: const SessionPendingAuth(pending),
      );

      await tester.pumpWidget(
        _app(InviteAcceptView(session: composed.model, pending: pending)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'novo');
      await tester.enterText(find.byType(TextField).at(2), 'segredo');
      await tester.enterText(find.byType(TextField).at(3), 'outra');
      await tester.ensureVisible(find.text('Criar conta'));
      await tester.pump();
      await tester.tap(find.text('Criar conta'));
      await tester.pumpAndSettle();

      expect(find.text('As duas senhas não são iguais.'), findsOneWidget);
      expect(composed.model.state, isA<SessionPendingAuth>());
    });

    testWidgets('a valid form creates the account', (tester) async {
      const pending = PendingAuth(kind: PendingAuthKind.invite, token: 'tk1');
      final composed = makeSession(
        host: testBox(),
        state: const SessionPendingAuth(pending),
      );

      await tester.pumpWidget(
        _app(InviteAcceptView(session: composed.model, pending: pending)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'novo');
      await tester.enterText(find.byType(TextField).at(2), 'segredo');
      await tester.enterText(find.byType(TextField).at(3), 'segredo');
      await tester.ensureVisible(find.text('Criar conta'));
      await tester.pump();
      await tester.tap(find.text('Criar conta'));
      await tester.pumpAndSettle();

      expect(composed.model.state, isA<SessionReady>());
    });
  });

  group('reset password', () {
    testWidgets('a spent link shows the dead end', (tester) async {
      const pending = PendingAuth(
        kind: PendingAuthKind.reset,
        token: 'expirado',
      );
      final composed = makeSession(
        host: testBox(),
        state: const SessionPendingAuth(pending),
      );

      await tester.pumpWidget(
        _app(ResetPasswordView(session: composed.model, pending: pending)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Este link expirou ou já foi usado'), findsOneWidget);
    });

    testWidgets('a live link opens the form with the reset copy', (
      tester,
    ) async {
      const pending = PendingAuth(kind: PendingAuthKind.reset, token: 'tk1');
      final composed = makeSession(
        host: testBox(),
        state: const SessionPendingAuth(pending),
      );

      await tester.pumpWidget(
        _app(ResetPasswordView(session: composed.model, pending: pending)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Redefinir senha'), findsWidgets);
      expect(find.text('Senha nova'), findsOneWidget);
      expect(find.text('Salvar nova senha'), findsOneWidget);
    });

    testWidgets('a valid reset signs in', (tester) async {
      const pending = PendingAuth(kind: PendingAuthKind.reset, token: 'tk1');
      final composed = makeSession(
        host: testBox(),
        state: const SessionPendingAuth(pending),
      );

      await tester.pumpWidget(
        _app(ResetPasswordView(session: composed.model, pending: pending)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'nova-senha');
      await tester.enterText(find.byType(TextField).at(1), 'nova-senha');
      await tester.ensureVisible(find.text('Salvar nova senha'));
      await tester.pump();
      await tester.tap(find.text('Salvar nova senha'));
      await tester.pumpAndSettle();

      expect(composed.model.state, isA<SessionReady>());
    });
  });
}
