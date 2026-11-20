import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/auth/auth_gate.dart';
import 'package:okena_app/src/features/auth/invite_accept_view_model.dart';
import 'package:okena_app/src/features/auth/reset_password_view_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/support/session_support.dart';

const _invite = PendingAuth(kind: PendingAuthKind.invite, token: 'tk1');
const _reset = PendingAuth(kind: PendingAuthKind.reset, token: 'tk1');

void main() {
  group('invite accept', () {
    test('a live token opens the form', () async {
      final composed = makeSession(host: testBox());
      final model = InviteAcceptViewModel(session: composed.model);

      await model.check(_invite);

      expect(model.gate, isA<AuthOpen>());
    });

    test('a spent token shows the dead end', () async {
      final composed = makeSession(host: testBox());
      final model = InviteAcceptViewModel(session: composed.model);

      await model.check(
        const PendingAuth(kind: PendingAuthKind.invite, token: 'expirado'),
      );

      expect(model.gate, isA<AuthDead>());
    });

    test('a valid form creates the account and signs in', () async {
      final composed = makeSession(host: testBox(), state: _pending(_invite));
      final model = InviteAcceptViewModel(session: composed.model);

      await model.createAccount(
        pending: _invite,
        username: 'novo',
        displayName: 'Pessoa Nova',
        password: 'segredo',
        deviceName: 'Aparelho de teste',
      );

      expect(model.failure, isNull);
      expect(composed.model.state, isA<SessionReady>());
      expect(composed.store.current?.me.displayName, 'Pessoa Nova');
    });

    test('invitation copy uses the optional name and inviter fields', () async {
      final api = ScriptedApi(
        inviteOutcome: const Ok(
          TokenStatus(
            valid: true,
            tekoaName: 'Quilombo do Café',
            inviter: 'Ana',
          ),
        ),
      );
      final composed = makeSession(host: testBox(), api: api);
      final model = InviteAcceptViewModel(session: composed.model);

      await model.check(_invite);

      expect(
        model.invitationMessage,
        'Ana convidou você para a comunidade Quilombo do Café. Crie sua '
        'conta para entrar.',
      );
    });

    test('invitation copy has a generic fallback', () async {
      final composed = makeSession(host: testBox());
      final model = InviteAcceptViewModel(session: composed.model);

      await model.check(_invite);

      expect(
        model.invitationMessage,
        'Você foi convidado para a comunidade. Crie sua conta para entrar.',
      );
    });
  });

  group('reset password', () {
    test('a live token opens the form', () async {
      final composed = makeSession(host: testBox());
      final model = ResetPasswordViewModel(session: composed.model);

      await model.check(_reset);

      expect(model.gate, isA<AuthOpen>());
    });

    test('a spent token shows the dead end', () async {
      final composed = makeSession(host: testBox());
      final model = ResetPasswordViewModel(session: composed.model);

      await model.check(
        const PendingAuth(kind: PendingAuthKind.reset, token: 'expirado'),
      );

      expect(model.gate, isA<AuthDead>());
    });

    test('a valid form defines the password and signs in', () async {
      final composed = makeSession(host: testBox(), state: _pending(_reset));
      final model = ResetPasswordViewModel(session: composed.model);

      await model.save(
        pending: _reset,
        password: 'nova-senha',
        deviceName: 'Aparelho de teste',
      );

      expect(model.failure, isNull);
      expect(composed.model.state, isA<SessionReady>());
    });
  });
}

SessionState _pending(PendingAuth pending) => SessionPendingAuth(pending);
