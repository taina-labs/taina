import 'package:okena_core/src/result.dart';
import 'package:okena_core/src/session/session.dart';
import 'package:okena_core/src/session/session_storage.dart';
import 'package:okena_core/src/taina_error.dart';

/// One session, visible to every caller at once.
///
/// [LiveTainaApi] reads the token at call time, so a revoked token fails on
/// the next request. On the single-isolate Flutter runtime this does not need
/// a lock; the state transitions stay explicit.
final class SessionStore {
  SessionStore({required this.storage});

  final SessionStorage storage;
  Session? _session;

  /// Loads the stored session into memory. Idempotent.
  Future<TainaResult<Session?>> restore() async {
    final loaded = await storage.load();
    switch (loaded) {
      case Ok(:final value):
        _session = value;
      case Err():
        break;
    }
    return loaded;
  }

  Future<TainaResult<void>> signIn(Session session) async {
    final saved = await storage.save(session);
    if (saved.isSuccess) {
      _session = session;
    }
    return saved;
  }

  /// Clears storage and memory. Leaving is local: a stored token the server
  /// has already forgotten is worse than either.
  Future<TainaResult<void>> signOut() async {
    final cleared = await storage.clear();
    _session = null;
    return cleared;
  }

  Session? get current => _session;

  String? get token => _session?.token;

  /// Updates the identity and re-saves, so a role change or a renamed
  /// community survives a relaunch. The device record stays as stored.
  Future<TainaResult<void>> refreshIdentity(Me me) async {
    final current = _session;
    if (current == null) {
      return const Err(NotSignedInError());
    }
    final updated = Session(
      token: current.token,
      device: current.device,
      me: me.ava,
      tekoa: me.tekoa,
    );
    final saved = await storage.save(updated);
    if (saved.isSuccess) {
      _session = updated;
    }
    return saved;
  }
}
