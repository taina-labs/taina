import 'package:okena_core/src/result.dart';
import 'package:okena_core/src/session/session.dart';

/// Persists the session between launches. There is no expiry and no refresh:
/// the revocation is the lifecycle. Nothing here schedules anything.
///
/// The pure core ships the in-memory implementation only. A Keychain/Keystore
/// backed implementation belongs to the app, behind this same contract.
abstract class SessionStorage {
  Future<TainaResult<void>> save(Session session);

  Future<TainaResult<Session?>> load();

  Future<TainaResult<void>> clear();
}

/// In-memory storage for tests and previews. Seeding it starts from a session
/// instead of a login.
final class InMemorySessionStorage implements SessionStorage {
  InMemorySessionStorage([this._stored]);

  Session? _stored;

  @override
  Future<TainaResult<void>> save(Session session) async {
    _stored = session;
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<Session?>> load() async => Ok(_stored);

  @override
  Future<TainaResult<void>> clear() async {
    _stored = null;
    return const Ok<void>(null);
  }
}
