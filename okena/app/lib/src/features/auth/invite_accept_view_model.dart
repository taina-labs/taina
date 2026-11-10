import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_model.dart';
import '../../session/session_state.dart';
import 'auth_gate.dart';

/// The invite accept, the native mirror of the web's `InviteAcceptLive`.
///
/// The token is checked lightly on arrival, a dead link shows the dead end
/// instead of the form, and the real validation stays on the submit. The two
/// password fields are the app's own check; the wire carries one.
final class InviteAcceptViewModel extends ChangeNotifier {
  InviteAcceptViewModel({required this.session}) {
    session.addListener(_changed);
  }

  final SessionModel session;

  AuthGate gate = const AuthChecking();
  bool creating = false;
  TainaError? failure;
  String? mismatch;

  Instance? get instance => session.instance;
  InstanceAddress? get host => session.host;

  String? get formMessage => failure?.message;

  List<String> messagesFor(List<String> fields) =>
      failure?.messagesFor(fields) ?? const [];

  Future<void> check(PendingAuth pending) async {
    gate = const AuthChecking();
    _notify();
    final result = await session.checkToken(pending);
    gate = switch (result) {
      Ok(value: true) => const AuthOpen(),
      Ok() => const AuthDead(),
      Err(:final error) when error is ApiError && error.isUnauthorized =>
        const AuthDead(),
      Err(:final error) => AuthBroken(error),
    };
    _notify();
  }

  Future<void> createAccount({
    required PendingAuth pending,
    required String username,
    required String displayName,
    required String password,
    required String confirmation,
    required String deviceName,
  }) async {
    failure = null;
    if (!confirmationMatches(password, confirmation)) {
      mismatch = 'As duas senhas não são iguais.';
      _notify();
      return;
    }
    mismatch = null;
    creating = true;
    _notify();

    final result = await session.acceptInvite(
      token: pending.token,
      username: username.trim(),
      password: password,
      displayName: displayName.trim().isEmpty ? null : displayName.trim(),
      deviceName: deviceName,
    );
    final error = result.error;
    if (error != null) failure = error;
    creating = false;
    _notify();
  }

  /// The local rule the wire does not carry: the two passwords must match.
  /// Pure, so both screens say it the same way.
  static bool confirmationMatches(String password, String confirmation) =>
      password == confirmation;

  void _changed() => _notify();

  bool _disposed = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_changed);
    super.dispose();
  }
}
