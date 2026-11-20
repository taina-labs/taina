import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_model.dart';
import '../../session/session_state.dart';
import 'auth_gate.dart';

/// The password reset, the native mirror of the web's `ResetPasswordLive`.
///
/// The link is checked lightly on arrival, a dead link shows the dead end
/// instead of the form, and the session is born on the submit.
final class ResetPasswordViewModel extends ChangeNotifier {
  ResetPasswordViewModel({required this.session}) {
    session.addListener(_changed);
  }

  final SessionModel session;

  AuthGate gate = const AuthChecking();
  bool saving = false;
  TainaError? failure;

  Instance? get instance => session.instance;
  InstanceAddress? get host => session.host;

  String? get formMessage => failure?.message;

  List<String> messagesFor(List<String> fields) =>
      failure?.messagesFor(fields) ?? const [];

  Future<void> check(PendingAuth pending) async {
    gate = const AuthChecking();
    _notify();
    final result = await session.api.resetStatus(token: pending.token);
    final status = result.value;
    if (status != null) {
      gate = status.valid ? const AuthOpen() : const AuthDead();
    } else {
      final error = result.error ?? const InvalidResponseError('token status');
      gate = error is ApiError && error.isUnauthorized
          ? const AuthDead()
          : AuthBroken(error);
    }
    _notify();
  }

  Future<void> save({
    required PendingAuth pending,
    required String password,
    required String deviceName,
  }) async {
    failure = null;
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
