import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/auth/device_name.dart';
import 'package:okena_app/src/features/login/login_view_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/support/session_support.dart';

void main() {
  test('the rate limit keeps its specific sentence', () {
    final composed = makeSession(state: const SessionNeedsLogin());
    final model = LoginViewModel(session: composed.model)
      ..failure = const ApiError(
        code: 'rate_limited',
        status: 429,
        serverMessage: 'Tente mais tarde.',
      );

    expect(model.formMessage, contains('Muitas tentativas'));
  });

  test('credential failures use board copy and the password help', () {
    final composed = makeSession(state: const SessionNeedsLogin());
    final model = LoginViewModel(session: composed.model)
      ..failure = const ApiError(
        code: 'invalid_credentials',
        status: 401,
        serverMessage: 'Usuário ou senha incorretos.',
      );

    expect(model.formMessage, 'Não conseguimos entrar.');
    expect(model.messagesFor(const ['password']), [
      'Confira a senha e tente de novo.',
    ]);
  });

  test('other failures keep the server sentence and field messages', () {
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

    expect(model.formMessage, 'Confira os campos.');
    expect(model.messagesFor(const ['username']), ['não pode ficar em branco']);
  });

  test('first access connects and logs in as one operation', () async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (_) async => const Ok(
        Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
      ),
    );
    final model = LoginViewModel(session: composed.model);

    await model.enter(
      username: '  ana  ',
      password: 'segredo',
      address: 'box.local',
      deviceName: 'Android de ana',
    );

    expect(model.failure, isNull);
    expect(model.signingIn, isFalse);
    expect(composed.model.state, isA<SessionReady>());
    expect(composed.model.host, testBox());
  });

  test('a failed first-access login remains on the same login state', () async {
    final composed = makeSession(
      api: ScriptedApi(
        sessionOutcome: const Err(
          ApiError(
            code: 'invalid_credentials',
            status: 401,
            serverMessage: 'Usuário ou senha incorretos.',
          ),
        ),
      ),
      state: const SessionNeedsInstance(),
      probe: (_) async => const Ok(
        Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
      ),
    );
    final model = LoginViewModel(session: composed.model);

    await model.enter(
      username: 'ana',
      password: 'errada',
      address: 'box.local',
      deviceName: 'Android de ana',
    );

    expect(model.failure, isA<ApiError>());
    expect(model.formMessage, 'Não conseguimos entrar.');
    expect(model.messagesFor(const ['password']), [
      'Confira a senha e tente de novo.',
    ]);
    expect(model.signingIn, isFalse);
    expect(composed.model.host, testBox());
    expect(composed.model.state, isA<SessionNeedsLogin>());
  });

  test('unreachable address retains its specific error state', () async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (_) async => const Err(NetworkError('down')),
    );
    final model = LoginViewModel(session: composed.model);

    await model.enter(
      username: 'ana',
      password: 'segredo',
      address: 'box.local',
      deviceName: 'Android de ana',
    );

    expect(model.failure, isA<NetworkError>());
    expect(model.isUnreachable, isTrue);
    expect(model.formMessage, 'Não conseguimos chegar à comunidade.');
    expect(model.signingIn, isFalse);
    expect(composed.model.state, isA<SessionNeedsInstance>());
  });

  test('an unbootstrapped box remains on first access', () async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (_) async =>
          const Ok(Instance(bootstrapped: false, tekoa: null, version: null)),
    );
    final model = LoginViewModel(session: composed.model);

    await model.enter(
      username: 'ana',
      password: 'segredo',
      address: 'box.local',
      deviceName: 'Android de ana',
    );

    expect(model.communityNotCreated, isTrue);
    expect(composed.model.state, isA<SessionNeedsInstance>());
  });

  test('a known host login does not probe another address', () async {
    var probes = 0;
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
      probe: (_) async {
        probes++;
        return const Ok(
          Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
        );
      },
    );
    await composed.model.restore();
    final model = LoginViewModel(session: composed.model);

    await model.enter(
      username: 'ana',
      password: 'segredo',
      address: '',
      deviceName: 'Android de ana',
    );

    expect(probes, 0);
    expect(composed.model.state, isA<SessionReady>());
  });

  test(
    'changing community clears the saved host before address entry',
    () async {
      final composed = makeSession(
        host: testBox(),
        state: const SessionNeedsLogin(),
      );
      await composed.model.restore();
      final model = LoginViewModel(session: composed.model);

      await model.changeCommunity();

      expect(model.showsAddress, isTrue);
      expect(model.changingCommunity, isTrue);
      expect(composed.model.host, isNull);
      expect(await composed.hosts.address(), isNull);
      expect(composed.model.state, isA<SessionNeedsInstance>());
    },
  );

  test('probe fills the community row for a saved host', () async {
    final composed = makeSession(host: testBox());
    await composed.model.restore();
    final model = LoginViewModel(session: composed.model);

    await model.probe();

    expect(model.instance?.tekoa?.name, 'Tekoa Sapukai');
    expect(model.communityLine(), 'Tekoa Sapukai, box.local');
    expect(model.host, testBox());
  });

  test('typed and saved cleartext addresses are visible', () async {
    final composed = makeSession(
      host: testBox('http://box.local'),
      state: const SessionNeedsLogin(),
    );
    await composed.model.restore();
    final model = LoginViewModel(session: composed.model);

    expect(model.host?.isCleartext, isTrue);
    expect(model.isCleartextAddress('http://other.local'), isTrue);
    expect(model.isCleartextAddress('other.local'), isFalse);
  });

  test('device labels are pure and platform-neutral', () {
    expect(
      authDeviceName(platform: TargetPlatform.iOS, username: ' Ana '),
      'iPhone de ana',
    );
    expect(
      authDeviceName(platform: TargetPlatform.android, username: 'ana'),
      'Android de ana',
    );
    expect(authDeviceName(platform: TargetPlatform.iOS), 'iPhone');
  });
}
