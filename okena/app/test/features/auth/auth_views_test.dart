import 'package:material_ui/material_ui.dart';
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
    testWidgets('an expired invitation shows the error and return path', (
      tester,
    ) async {
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

      expect(find.text('Este convite não é mais válido.'), findsOneWidget);
      expect(find.text('Voltar para entrar'), findsOneWidget);
      expect(find.text('Falar com quem cuida'), findsOneWidget);
    });

    testWidgets('a live invitation renders its copy and one password field', (
      tester,
    ) async {
      const pending = PendingAuth(kind: PendingAuthKind.invite, token: 'tk1');
      final composed = makeSession(
        host: testBox(),
        state: const SessionPendingAuth(pending),
      );

      await tester.pumpWidget(
        _app(
          InviteAcceptView(
            session: composed.model,
            pending: pending,
            tekoaName: 'Quilombo do Café',
            inviter: 'Ana',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Você recebeu um convite'), findsOneWidget);
      expect(
        find.text(
          'Ana convidou você para a comunidade Quilombo do Café. Crie sua '
          'conta para entrar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Seu nome de usuário'), findsOneWidget);
      expect(find.text('Nome de exibição (opcional)'), findsOneWidget);
      expect(find.text('Senha'), findsOneWidget);
      expect(find.text('Confirme a senha'), findsNothing);
      expect(find.text('Criar conta'), findsOneWidget);
    });

    testWidgets('creating an account needs one password', (tester) async {
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
      await tester.ensureVisible(find.text('Criar conta'));
      await tester.tap(find.text('Criar conta'));
      await tester.pumpAndSettle();

      expect(composed.model.state, isA<SessionReady>());
    });
  });

  group('reset password', () {
    testWidgets('an expired reset shows the error and return path', (
      tester,
    ) async {
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

      expect(find.text('Este link expirou.'), findsOneWidget);
      expect(find.text('Voltar para entrar'), findsOneWidget);
    });

    testWidgets('a live reset has one password field', (tester) async {
      const pending = PendingAuth(kind: PendingAuthKind.reset, token: 'tk1');
      final composed = makeSession(
        host: testBox(),
        state: const SessionPendingAuth(pending),
      );

      await tester.pumpWidget(
        _app(ResetPasswordView(session: composed.model, pending: pending)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Redefinir senha'), findsOneWidget);
      expect(find.text('Senha nova'), findsOneWidget);
      expect(find.text('Confirme a senha'), findsNothing);
      expect(find.text('Salvar nova senha'), findsOneWidget);
    });

    testWidgets('a valid reset signs in with the one password field', (
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

      await tester.enterText(find.byType(TextField).first, 'nova-senha');
      await tester.ensureVisible(find.text('Salvar nova senha'));
      await tester.tap(find.text('Salvar nova senha'));
      await tester.pumpAndSettle();

      expect(composed.model.state, isA<SessionReady>());
    });
  });
}
