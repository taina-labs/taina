import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_model.dart';
import '../../session/session_state.dart';
import 'auth_gate.dart';
import 'invite_accept_view_model.dart';

/// The password reset, the native mirror of the web's `ResetPasswordLive`.
///
/// The link is checked lightly on arrival, a dead link shows the dead end
/// instead of the form, and the session is born on the submit. The two
/// password fields are the app's own check; the wire carries one.
final class ResetPasswordViewModel extends ChangeNotifier {
  ResetPasswordViewModel({required this.session}) {
    session.addListener(_changed);
  }

  final SessionModel session;

  AuthGate gate = const AuthChecking();
  bool saving = false;
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

  Future<void> save({
    required PendingAuth pending,
    required String password,
    required String confirmation,
    required String deviceName,
  }) async {
    failure = null;
    if (!InviteAcceptViewModel.confirmationMatches(password, confirmation)) {
      mismatch = 'As duas senhas não são iguais.';
      _notify();
      return;
    }
    mismatch = null;
    saving = true;
    _notify();

    final result = await session.resetPassword(
      token: pending.token,
      password: password,
      deviceName: deviceName,
    );
    final error = result.error;
    if (error != null) failure = error;
    saving = false;
    _notify();
  }

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
