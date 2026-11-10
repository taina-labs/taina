import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/session/local_network_gate.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import 'support/session_support.dart';

void main() {
  group('restore', () {
    test('without a box needs the instance and attaches the scene', () async {
      final composed = makeSession();

      await composed.model.restore();

      expect(composed.model.state, isA<SessionNeedsInstance>());
      expect(composed.model.host, isNull);
      expect(composed.lifecycle.attached, isTrue);
    });

    test('with a saved box but no session needs the login', () async {
      final composed = makeSession(host: testBox());

      await composed.model.restore();

      expect(composed.model.state, isA<SessionNeedsLogin>());
      expect(composed.model.host, testBox());
    });

    test('with a stored session becomes ready', () async {
      final composed = makeSession(
        host: testBox(),
        storage: InMemorySessionStorage(testSession()),
      );

      await composed.model.restore();

      final state = composed.model.state;
      expect(state, isA<SessionReady>());
      expect((state as SessionReady).me, testSession().identity);
    });

    test('a stored session without its box is discarded into setup', () async {
      final storage = InMemorySessionStorage(testSession());
      final composed = makeSession(storage: storage);

      await composed.model.restore();

      expect(composed.model.state, isA<SessionNeedsInstance>());
      expect(composed.model.host, isNull);
      expect(composed.store.current, isNull);
      expect((await storage.load()).value, isNull);
    });

    test('a session that cannot be read counts as absent', () async {
      final composed = makeSession(
        host: testBox(),
        storage: _BrokenSessionStorage(),
      );

      await composed.model.restore();

      expect(composed.model.state, isA<SessionNeedsLogin>());
    });
  });

  group('connect', () {
    test('falls back from https to http when nothing answers', () async {
      final schemes = <String>[];
      final composed = makeSession(
        probe: (address) async {
          schemes.add(address.url.scheme);
          if (address.url.scheme == 'https') {
            return const Err(NetworkError('down'));
          }
          return const Ok(
            Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
          );
        },
      );

      final result = await composed.model.connect('box.local');

      expect(result.value?.bootstrapped, isTrue);
      expect(schemes, ['https', 'http']);
      expect(composed.model.state, isA<SessionNeedsLogin>());
      expect(composed.model.host, testBox('http://box.local'));
      expect((await composed.hosts.address())!.isCleartext, isTrue);
    });

    test('keeps https when the first candidate answers', () async {
      final schemes = <String>[];
      final composed = makeSession(
        probe: (address) async {
          schemes.add(address.url.scheme);
          return const Ok(
            Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
          );
        },
      );

      await composed.model.connect('box.local');

      expect(schemes, ['https']);
      expect(await composed.hosts.address(), testBox());
    });

    test('an explicit scheme is not retried on the other one', () async {
      final schemes = <String>[];
      final composed = makeSession(
        probe: (address) async {
          schemes.add(address.url.scheme);
          return const Err(NetworkError('down'));
        },
      );

      final result = await composed.model.connect('http://box.local');

      expect(result.error, isA<NetworkError>());
      expect(schemes, ['http']);
      expect(await composed.hosts.address(), isNull);
    });

    test('a box without a community is not saved', () async {
      final composed = makeSession(
        state: const SessionNeedsInstance(),
        probe: (address) async =>
            const Ok(Instance(bootstrapped: false, tekoa: null, version: null)),
      );

      final result = await composed.model.connect('box.local');

      expect(result.value?.bootstrapped, isFalse);
      expect(composed.model.instance?.bootstrapped, isFalse);
      expect(composed.model.state, isA<SessionNeedsInstance>());
      expect(await composed.hosts.address(), isNull);
    });

    test('a malformed address never touches the network', () async {
      var probed = false;
      final composed = makeSession(
        probe: (address) async {
          probed = true;
          return const Ok(
            Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
          );
        },
      );

      final result = await composed.model.connect('   ');

      expect(result.error, isA<InvalidAddressError>());
      expect(probed, isFalse);
    });

    test('a declined local network permission reads as unreachable', () async {
      var probed = false;
      final composed = makeSession(
        localNetwork: const DenyLocalNetworkGate(),
        probe: (address) async {
          probed = true;
          return const Ok(
            Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
          );
        },
      );

      final result = await composed.model.connect('box.local');

      expect(result.error, isA<NetworkError>());
      expect(probed, isFalse);
    });
  });

  group('sign in', () {
    test('a login stores the session and becomes ready', () async {
      final composed = makeSession(
        host: testBox(),
        state: const SessionNeedsLogin(),
      );

      final result = await composed.model.login(
        username: 'ana',
        password: 'segredo',
        deviceName: 'Aparelho de teste',
      );

      expect(result.value, isNotNull);
      expect(composed.model.state, isA<SessionReady>());
      expect(composed.store.token, isNotNull);
      expect((await composed.store.storage.load()).value, isNotNull);
    });

    test('a rejected login stays on the login with its error', () async {
      final composed = makeSession(
        host: testBox(),
        state: const SessionNeedsLogin(),
      );

      final result = await composed.model.login(
        username: 'sem-acesso',
        password: 'segredo',
        deviceName: 'Aparelho de teste',
      );

      expect(result.error, isA<ApiError>());
      expect(composed.model.state, isA<SessionNeedsLogin>());
      expect(composed.store.token, isNull);
    });

    test('an accepted invite signs the new account in', () async {
      final composed = makeSession(
        host: testBox(),
        state: SessionPendingAuth(
          const PendingAuth(kind: PendingAuthKind.invite, token: 'tk1'),
        ),
      );

      final result = await composed.model.acceptInvite(
        token: 'tk1',
        username: 'novo',
        password: 'segredo',
        displayName: 'Pessoa Nova',
        deviceName: 'Aparelho de teste',
      );

      expect(result.value, isNotNull);
      expect(composed.model.state, isA<SessionReady>());
      expect(composed.store.current?.me.displayName, 'Pessoa Nova');
    });

    test('a reset defines the password and signs in', () async {
      final composed = makeSession(
        host: testBox(),
        state: SessionPendingAuth(
          const PendingAuth(kind: PendingAuthKind.reset, token: 'tk1'),
        ),
      );

      final result = await composed.model.resetPassword(
        token: 'tk1',
        password: 'nova-senha',
        deviceName: 'Aparelho de teste',
      );

      expect(result.value, isNotNull);
      expect(composed.model.state, isA<SessionReady>());
    });

    test('checkToken maps the light read to a yes or an error', () async {
      final composed = makeSession();

      final live = await composed.model.checkToken(
        const PendingAuth(kind: PendingAuthKind.invite, token: 'live'),
      );
      expect(live.value, isTrue);

      final dead = await composed.model.checkToken(
        const PendingAuth(kind: PendingAuthKind.invite, token: 'expirado'),
      );
      expect(dead.error, isA<ApiError>());
    });
  });

  group('leaving', () {
    test('signOut revokes and clears locally whatever the answer', () async {
      final composed = makeSession(
        host: testBox(),
        state: const SessionNeedsLogin(),
      );
      await composed.model.login(
        username: 'ana',
        password: 'segredo',
        deviceName: 'Aparelho de teste',
      );

      await composed.model.signOut();

      expect(composed.model.state, isA<SessionNeedsLogin>());
      expect(composed.store.current, isNull);
    });

    test('signing out without a box returns to setup', () async {
      final composed = makeSession(
        storage: InMemorySessionStorage(testSession()),
      );
      await composed.store.restore();

      await composed.model.signOut();

      expect(composed.model.state, isA<SessionNeedsInstance>());
      expect(composed.store.current, isNull);
    });

    test('a 401 signs out with the expired sentence', () async {
      final composed = makeSession(
        host: testBox(),
        state: const SessionNeedsLogin(),
      );
      await composed.model.login(
        username: 'ana',
        password: 'segredo',
        deviceName: 'Aparelho de teste',
      );
      // The box forgets the token, the way a revocation elsewhere would.
      await composed.model.api.revokeSession();

      final outcome = await composed.model.api.me();
      await composed.model.screen(outcome);

      expect(composed.model.state, isA<SessionNeedsLogin>());
      expect(composed.model.notice, contains('expirou'));
      expect(composed.store.current, isNull);
    });

    test('a deactivated account has its own sentence', () async {
      final api = ScriptedApi(
        meOutcome: const Err(
          ApiError(
            code: 'account_deactivated',
            status: 403,
            serverMessage: 'Esta conta foi desativada.',
          ),
        ),
      );
      final composed = makeSession(
        api: api,
        host: testBox(),
        storage: InMemorySessionStorage(testSession()),
        state: SessionReady(testMe()),
      );

      final outcome = await api.me();
      await composed.model.screen(outcome);

      expect(composed.model.state, isA<SessionNeedsLogin>());
      expect(composed.model.notice, contains('desativada'));
    });

    test('a successful result passes through untouched', () async {
      final composed = makeSession();
      const outcome = Ok<void>(null);
      expect(await composed.model.screen(outcome), same(outcome));
    });
  });

  group('refresh', () {
    test('the ready identity is refreshed and re-saved', () async {
      final renamed = Ava(
        publicId: testAva.publicId,
        username: testAva.username,
        displayName: 'Ana S.',
        papel: testAva.papel,
        activatedAt: testAva.activatedAt,
        deactivatedAt: testAva.deactivatedAt,
        createdAt: testAva.createdAt,
      );
      final api = ScriptedApi(
        meOutcome: Ok(Me(ava: renamed, tekoa: testTekoa, device: testDevice)),
      );
      final storage = InMemorySessionStorage(testSession());
      final composed = makeSession(
        api: api,
        host: testBox(),
        storage: storage,
        state: SessionReady(testMe()),
      );
      await composed.store.restore();

      await composed.model.refresh();

      final state = composed.model.state;
      expect(state, isA<SessionReady>());
      expect((state as SessionReady).me.ava.displayName, 'Ana S.');
      expect((await storage.load()).value?.me.displayName, 'Ana S.');
    });

    test('before the login it probes the saved box', () async {
      final composed = makeSession(host: testBox());
      await composed.model.restore();
      expect(composed.model.instance, isNull);

      await composed.model.refresh();

      expect(composed.model.instance?.tekoa?.name, 'Tekoa Sapukai');
    });
  });

  group('scene poll', () {
    test('activation starts one poll and deactivation stops it', () async {
      final composed = makeSession(host: testBox());
      await composed.model.restore();

      composed.lifecycle.activate();
      expect(composed.poller.starts, 1);
      expect(composed.poller.interval, const Duration(seconds: 30));

      // A second activation while active does not stack a timer.
      composed.lifecycle.activate();
      expect(composed.poller.starts, 1);

      composed.lifecycle.deactivate();
      expect(composed.poller.running, isFalse);

      composed.lifecycle.activate();
      expect(composed.poller.starts, 2);
    });

    test('a tick refreshes the saved box', () async {
      final composed = makeSession(host: testBox());
      await composed.model.restore();
      expect(composed.model.instance, isNull);

      composed.lifecycle.activate();
      composed.poller.tick();
      await Future<void>.delayed(Duration.zero);

      expect(composed.model.instance?.tekoa?.name, 'Tekoa Sapukai');
    });
  });

  group('deep links', () {
    test('a link that arrives during restore wins the screen', () async {
      final storage = DelayedSessionStorage();
      final composed = makeSession(storage: storage);

      final restoring = composed.model.restore();
      await composed.model.handleDeepLink(
        Uri.parse('taina://convite/tk1?host=https://link.example'),
      );

      storage.completer.complete(Ok<Session?>(testSession()));
      await restoring;

      final state = composed.model.state;
      expect(state, isA<SessionPendingAuth>());
      expect(
        (state as SessionPendingAuth).pending,
        const PendingAuth(kind: PendingAuthKind.invite, token: 'tk1'),
      );
      expect(composed.model.host, testBox('https://link.example'));
      expect(await composed.hosts.address(), testBox('https://link.example'));
    });

    test('a malformed link changes nothing', () async {
      final composed = makeSession();
      await composed.model.restore();
      final before = composed.model.state;

      await composed.model.handleDeepLink(Uri.parse('taina://outra/tk1'));

      expect(composed.model.state, same(before));
      expect(composed.model.host, isNull);
    });

    test(
      'a pasted link without a box and without a saved one is blocked',
      () async {
        final composed = makeSession();
        await composed.model.restore();

        final problem = await composed.model.openPastedInvite(
          'taina://convite/tk1',
        );

        expect(problem, contains('nenhuma foi conectada'));
        expect(composed.model.state, isA<SessionNeedsInstance>());
      },
    );

    test('a pasted link without a box uses the saved one', () async {
      final composed = makeSession(host: testBox());
      await composed.model.restore();

      final problem = await composed.model.openPastedInvite(
        'taina://convite/tk1',
      );

      expect(problem, isNull);
      expect(composed.model.state, isA<SessionPendingAuth>());
      expect(composed.model.host, testBox());
    });

    test(
      'a pasted malformed link is reported without changing anything',
      () async {
        final composed = makeSession();
        await composed.model.restore();
        final before = composed.model.state;

        final problem = await composed.model.openPastedInvite('nada');

        expect(problem, contains('não pôde ser lido'));
        expect(composed.model.state, same(before));
      },
    );

    test('leaving pending auth returns to the stored session', () async {
      final composed = makeSession(
        host: testBox(),
        storage: InMemorySessionStorage(testSession()),
        state: SessionPendingAuth(
          const PendingAuth(kind: PendingAuthKind.reset, token: 'tk1'),
        ),
      );
      await composed.store.restore();

      await composed.model.leavePendingAuth();

      expect(composed.model.state, isA<SessionReady>());
    });

    test('a link for another box clears the previous box session', () async {
      final composed = makeSession(
        host: testBox(),
        storage: InMemorySessionStorage(testSession()),
      );
      await composed.store.restore();

      await composed.model.handleDeepLink(
        Uri.parse('taina://convite/tk1?host=https://other.example'),
      );
      await composed.model.leavePendingAuth();

      expect(composed.store.current, isNull);
      expect(composed.model.host, testBox('https://other.example'));
      expect(composed.model.state, isA<SessionNeedsLogin>());
    });

    test('without a session it lands on the saved box login', () async {
      final composed = makeSession(
        host: testBox(),
        state: SessionPendingAuth(
          const PendingAuth(kind: PendingAuthKind.invite, token: 'tk1'),
        ),
      );

      await composed.model.leavePendingAuth();

      expect(composed.model.state, isA<SessionNeedsLogin>());
    });

    test('without a session or a box it lands on the setup', () async {
      final composed = makeSession(
        state: SessionPendingAuth(
          const PendingAuth(kind: PendingAuthKind.invite, token: 'tk1'),
        ),
      );

      await composed.model.leavePendingAuth();

      expect(composed.model.state, isA<SessionNeedsInstance>());
    });
  });
}

final class _BrokenSessionStorage implements SessionStorage {
  @override
  Future<TainaResult<Session?>> load() async =>
      const Err(InvalidResponseError('stored session'));

  @override
  Future<TainaResult<void>> save(Session session) async => const Ok<void>(null);

  @override
  Future<TainaResult<void>> clear() async => const Ok<void>(null);
}
