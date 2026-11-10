import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/login/login_view_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/support/session_support.dart';

void main() {
  test('the rate limit has its own sentence', () {
    final composed = makeSession(state: const SessionNeedsLogin());
    final model = LoginViewModel(session: composed.model)
      ..failure = const ApiError(
        code: 'rate_limited',
        status: 429,
        serverMessage: 'Tente mais tarde.',
      );

    expect(model.formMessage, contains('Muitas tentativas'));
  });

  test('other failures show the server sentence', () {
    final composed = makeSession(state: const SessionNeedsLogin());
    final model = LoginViewModel(session: composed.model)
      ..failure = const ApiError(
        code: 'invalid_credentials',
        status: 401,
        serverMessage: 'Usuário ou senha incorretos.',
      );

    expect(model.formMessage, 'Usuário ou senha incorretos.');
    expect(model.messagesFor(const ['username']), isEmpty);
  });

  test('field messages come from the error envelope', () {
    final composed = makeSession(state: const SessionNeedsLogin());
    final model = LoginViewModel(session: composed.model)
      ..failure = const ApiError(
        code: 'validation_failed',
        status: 422,
        serverMessage: 'Confira os campos.',
        details: {
          'username': ['não pode ficar em branco'],
        },
      );

    expect(model.messagesFor(const ['username']), ['não pode ficar em branco']);
  });

  test('a login becomes ready and the notice clears', () async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );
    final model = LoginViewModel(session: composed.model);
    await composed.model.screen(
      const Err(
        ApiError(
          code: 'not_authenticated',
          status: 401,
          serverMessage: 'Entre de novo.',
        ),
      ),
    );
    expect(model.notice, contains('expirou'));

    await model.enter(
      username: '  ana  ',
      password: 'segredo',
      deviceName: 'Aparelho de teste',
    );

    expect(model.failure, isNull);
    expect(model.signingIn, isFalse);
    expect(composed.model.state, isA<SessionReady>());
    expect(composed.model.notice, isNull);
  });

  test('the login failure stays in the form', () async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );
    final model = LoginViewModel(session: composed.model);

    await model.enter(
      username: 'sem-acesso',
      password: 'segredo',
      deviceName: 'Aparelho de teste',
    );

    expect(model.failure, isA<ApiError>());
    expect(model.signingIn, isFalse);
    expect(composed.model.state, isA<SessionNeedsLogin>());
  });

  test('probe fills the community on the header', () async {
    final composed = makeSession(host: testBox());
    await composed.model.restore();
    final model = LoginViewModel(session: composed.model);

    await model.probe();

    expect(model.instance?.tekoa?.name, 'Tekoa Sapukai');
    expect(model.host, testBox());
  });
}
