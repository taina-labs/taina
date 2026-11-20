import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_model.dart';
import '../../session/session_state.dart';
import 'auth_gate.dart';

/// The invite accept, the native mirror of the web's `InviteAcceptLive`.
///
/// The token is checked lightly on arrival, a dead link shows the dead end
/// instead of the form, and the real validation stays on the submit.
final class InviteAcceptViewModel extends ChangeNotifier {
  InviteAcceptViewModel({required this.session}) {
    session.addListener(_changed);
  }

  final SessionModel session;

  AuthGate gate = const AuthChecking();
  bool creating = false;
  TainaError? failure;
  String? tekoaName;
  String? inviter;

  Instance? get instance => session.instance;
  InstanceAddress? get host => session.host;

  String? get formMessage => failure?.message;

  String? get communityName {
    final name = tekoaName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final fallback = instance?.tekoa?.name.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  String get invitationMessage {
    final name = inviter?.trim();
    final community = communityName;
    if (community == null) {
      if (name == null || name.isEmpty) {
        return 'Você foi convidado para a comunidade. Crie sua conta para '
            'entrar.';
      }
      return '$name convidou você para sua comunidade. Crie sua conta para '
          'entrar.';
    }
    if (name == null || name.isEmpty) {
      return 'Você foi convidado para a comunidade $community. Crie sua conta '
          'para entrar.';
    }
    return '$name convidou você para a comunidade $community. Crie sua '
        'conta para entrar.';
  }

  List<String> messagesFor(List<String> fields) =>
      failure?.messagesFor(fields) ?? const [];

  Future<void> check(
    PendingAuth pending, {
    String? tekoaName,
    String? inviter,
  }) async {
    gate = const AuthChecking();
    this.tekoaName = tekoaName;
    this.inviter = inviter;
    _notify();
    final result = await session.api.inviteStatus(token: pending.token);
    final status = result.value;
    if (status != null) {
      this.tekoaName ??= status.tekoaName;
      this.inviter ??= status.inviter;
      gate = status.valid ? const AuthOpen() : const AuthDead();
    } else {
      final error = result.error ?? const InvalidResponseError('token status');
      gate = error is ApiError && error.isUnauthorized
          ? const AuthDead()
          : AuthBroken(error);
    }
    _notify();
  }

  Future<void> createAccount({
    required PendingAuth pending,
    required String username,
    required String displayName,
    required String password,
    required String deviceName,
  }) async {
    failure = null;
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
