import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

Ava renamedAna(Ava ana) {
  return Ava(
    publicId: ana.publicId,
    username: 'ana',
    displayName: 'Ana S.',
    papel: Papel.morador,
    activatedAt: ana.activatedAt,
    deactivatedAt: null,
    createdAt: ana.createdAt,
  );
}

void main() {
  test('a session round trips through in-memory storage', () async {
    final session = fixturedSession();
    final storage = InMemorySessionStorage();
    final store = SessionStore(storage: storage);

    expect(store.token, isNull);

    expect((await store.signIn(session)).isSuccess, isTrue);
    expect(store.token, session.token);
    expect(store.current!.me.username, 'ana');

    // A fresh store over the same storage sees the same session.
    final restored = (await SessionStore(storage: storage).restore()).value!;
    expect(restored, session);
  });

  test('restore loads a stored session', () async {
    final session = fixturedSession();
    final store = SessionStore(storage: InMemorySessionStorage(session));

    final restored = (await store.restore()).value!;
    expect(restored, session);
    expect(store.token, session.token);
  });

  test('the token is null before sign in and after sign out', () async {
    final session = fixturedSession();
    final storage = InMemorySessionStorage();
    final store = SessionStore(storage: storage);

    expect(store.token, isNull);

    expect((await store.signIn(session)).isSuccess, isTrue);
    expect((await store.signOut()).isSuccess, isTrue);
    expect(store.token, isNull);
    expect(store.current, isNull);
    expect((await storage.load()).value, isNull);
  });

  test('refreshIdentity replaces me and re-saves', () async {
    final session = fixturedSession();
    final storage = InMemorySessionStorage();
    final store = SessionStore(storage: storage);
    expect((await store.signIn(session)).isSuccess, isTrue);

    final renamed = renamedAna(session.me);
    expect(
      (await store.refreshIdentity(
        Me(ava: renamed, tekoa: session.tekoa, device: session.device),
      )).isSuccess,
      isTrue,
    );

    final current = store.current!;
    expect(current.me.displayName, 'Ana S.');
    expect(current.me.papel, Papel.morador);
    expect(current.token, session.token);
    expect(current.device, session.device);

    // The change survives a relaunch: it is in storage too.
    final stored = (await storage.load()).value!;
    expect(stored.me.displayName, 'Ana S.');
  });

  test('refreshIdentity without a session is not signed in', () async {
    final store = SessionStore(storage: InMemorySessionStorage());
    final me = Me(
      ava: const Ava(
        publicId: 'avap2xw5m8q3',
        username: 'ana',
        displayName: null,
        papel: Papel.morador,
        activatedAt: null,
        deactivatedAt: null,
        createdAt: '2026-02-01T09:00:00Z',
      ),
      tekoa: const Tekoa(
        publicId: 'tekp2xw5m8q3',
        name: 'Tekoa Sapukai',
        domain: 'taina.sapukai.ts.net',
        storageQuotaBytes: null,
        storageUsedBytes: 0,
        createdAt: '2026-02-01T09:00:00Z',
      ),
      device: null,
    );
    expect((await store.refreshIdentity(me)).error, const NotSignedInError());
  });

  test('the persisted session JSON keeps the wire shape', () {
    final session = fixturedSession();
    final json = session.toJson();
    expect(json['token'], session.token);
    expect((json['device'] as Map)['name'], 'iPhone da Ana');
    expect(Session.fromPersistedJson(json), session);
  });

  test('the restored identity carries the same pieces without the token', () {
    final session = fixturedSession();
    final identity = session.identity;
    expect(identity.ava, session.me);
    expect(identity.tekoa, session.tekoa);
    expect(identity.device, session.device);
  });
}
