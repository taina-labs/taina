import 'dart:async';

import 'package:flutter/services.dart';
import 'package:okena_app/src/session/local_network_gate.dart';
import 'package:okena_app/src/session/secure_session_storage.dart';
import 'package:okena_app/src/session/session_lifecycle.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/session_poller.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

const testAva = Ava(
  publicId: 'avap2xw5m8q3',
  username: 'ana',
  displayName: 'Ana Souza',
  papel: Papel.zelador,
  activatedAt: '2026-02-01T09:00:00Z',
  deactivatedAt: null,
  createdAt: '2026-02-01T09:00:00Z',
);

const testTekoa = Tekoa(
  publicId: 'tekp2xw5m8q3',
  name: 'Tekoa Sapukai',
  domain: 'taina.sapukai.ts.net',
  storageQuotaBytes: 268435456000,
  storageUsedBytes: 1832110000,
  createdAt: '2026-02-01T09:00:00Z',
);

const testDevice = DeviceToken(
  publicId: 'devp2xw5m8q3',
  name: 'iPhone da Ana',
  lastUsedAt: null,
  revokedAt: null,
  createdAt: '2026-10-14T08:00:00Z',
);

Session testSession() => const Session(
  token: 'tnd_abcdef0123456789abcdef0123456789',
  device: testDevice,
  me: testAva,
  tekoa: testTekoa,
);

Me testMe() => const Me(ava: testAva, tekoa: testTekoa, device: testDevice);

InstanceAddress testBox([String input = 'https://box.local']) {
  final parsed = InstanceAddress.parse(input);
  return parsed.value!;
}

/// A lifecycle the test drives: activation is a method call, never a scene.
final class ManualSessionLifecycle implements SessionLifecycle {
  VoidCallback? _activated;
  VoidCallback? _deactivated;

  bool attached = false;

  @override
  void attach({
    required VoidCallback onActivated,
    required VoidCallback onDeactivated,
  }) {
    _activated = onActivated;
    _deactivated = onDeactivated;
    attached = true;
  }

  @override
  void detach() {
    attached = false;
    _activated = null;
    _deactivated = null;
  }

  void activate() => _activated?.call();

  void deactivate() => _deactivated?.call();
}

/// A poller the test ticks by hand, with the interval it was given.
final class ManualSessionPoller implements SessionPoller {
  Duration? interval;
  VoidCallback? _onTick;
  int starts = 0;
  int stops = 0;

  bool get running => _onTick != null;

  @override
  void start(Duration interval, VoidCallback onTick) {
    this.interval = interval;
    _onTick = onTick;
    starts += 1;
  }

  @override
  void stop() {
    _onTick = null;
    stops += 1;
  }

  void tick() => _onTick?.call();
}

/// An in-memory keystore: the JSON round trip without a platform channel.
final class MemorySecureKeyValueStore implements SecureKeyValueStore {
  MemorySecureKeyValueStore([Map<String, String>? values])
    : values = values ?? {};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// A keystore that fails the way a locked device or a missing plugin does.
final class ThrowingSecureKeyValueStore implements SecureKeyValueStore {
  const ThrowingSecureKeyValueStore();

  Never _fail() => throw PlatformException(code: 'locked', message: 'locked');

  @override
  Future<String?> read(String key) async => _fail();

  @override
  Future<void> write(String key, String value) async => _fail();

  @override
  Future<void> delete(String key) async => _fail();
}

/// A storage whose load the test completes by hand: the cold-start race.
final class DelayedSessionStorage implements SessionStorage {
  final Completer<TainaResult<Session?>> completer = Completer();

  @override
  Future<TainaResult<Session?>> load() => completer.future;

  @override
  Future<TainaResult<void>> save(Session session) async => const Ok<void>(null);

  @override
  Future<TainaResult<void>> clear() async => const Ok<void>(null);
}

/// A scripted [TainaApi] for the outcomes the fake does not produce, like a
/// deactivated account. Every member the test does not override is a bug.
final class ScriptedApi implements TainaApi {
  ScriptedApi({
    this.meOutcome,
    this.inviteOutcome,
    this.resetOutcome,
    this.sessionOutcome,
  });

  TainaResult<Me>? meOutcome;
  TainaResult<TokenStatus>? inviteOutcome;
  TainaResult<TokenStatus>? resetOutcome;
  TainaResult<Session>? sessionOutcome;

  @override
  Future<TainaResult<Me>> me() async => meOutcome ?? Ok(testMe());

  @override
  Future<TainaResult<TokenStatus>> inviteStatus({
    required String token,
  }) async => inviteOutcome ?? const Ok(TokenStatus(valid: true));

  @override
  Future<TainaResult<TokenStatus>> resetStatus({required String token}) async =>
      resetOutcome ?? const Ok(TokenStatus(valid: true));

  @override
  Future<TainaResult<Instance>> instance() async => const Ok(
    Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
  );

  @override
  Future<TainaResult<Session>> createSession({
    required String username,
    required String password,
    required String deviceName,
  }) async => sessionOutcome ?? Ok(testSession());

  @override
  Future<TainaResult<void>> revokeSession() async => const Ok<void>(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ScriptedApi.${invocation.memberName}');
}

/// One composed session for a test: the model plus the collaborators the
/// assertions read.
final class TestSession {
  const TestSession({
    required this.model,
    required this.store,
    required this.hosts,
    required this.lifecycle,
    required this.poller,
  });

  final SessionModel model;
  final SessionStore store;
  final InMemoryHostStore hosts;
  final ManualSessionLifecycle lifecycle;
  final ManualSessionPoller poller;
}

TestSession makeSession({
  TainaApi? api,
  InstanceAddress? host,
  SessionStorage? storage,
  SessionState state = const SessionChecking(),
  InstanceProbe? probe,
  LocalNetworkGate? localNetwork,
  Duration pollInterval = const Duration(seconds: 30),
}) {
  final wire = api ?? FakeTainaApi(delay: Duration.zero);
  final lifecycle = ManualSessionLifecycle();
  final poller = ManualSessionPoller();
  final sessions = SessionStore(storage: storage ?? InMemorySessionStorage());
  final hosts = InMemoryHostStore(host);
  final model = SessionModel.seeded(
    api: wire,
    store: sessions,
    hostStore: hosts,
    state: state,
    probe: probe ?? (address) => wire.instance(),
    lifecycle: lifecycle,
    poller: poller,
    localNetwork: localNetwork,
    pollInterval: pollInterval,
  );
  return TestSession(
    model: model,
    store: sessions,
    hosts: hosts,
    lifecycle: lifecycle,
    poller: poller,
  );
}
