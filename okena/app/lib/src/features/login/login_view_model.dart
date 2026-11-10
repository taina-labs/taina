import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/device_name.dart';
import '../../session/session_model.dart';

/// The sign-in state: the header the session supplies and the last failure
/// the form shows.
final class LoginViewModel extends ChangeNotifier {
  LoginViewModel({required this.session}) {
    session.addListener(_changed);
  }

  final SessionModel session;

  bool signingIn = false;
  TainaError? failure;

  String? get notice => session.notice;
  Instance? get instance => session.instance;
  InstanceAddress? get host => session.host;

  /// The sentence above the button: the rate limit explains itself; the rest
  /// is the error's own pt-BR description.
  String? get formMessage {
    final failure = this.failure;
    if (failure == null) return null;
    if (failure is ApiError && failure.isRateLimited) {
      return 'Muitas tentativas de entrada. Espere um pouco antes de tentar '
          'de novo.';
    }
    return failure.message;
  }

  List<String> messagesFor(List<String> fields) =>
      failure?.messagesFor(fields) ?? const [];

  Future<void> probe() => session.probe();

  Future<void> enter({
    required String username,
    required String password,
    required String deviceName,
  }) async {
    signingIn = true;
    failure = null;
    _notify();
    final typedName = deviceName.trim();
    final result = await session.login(
      username: username.trim(),
      password: password,
      deviceName: typedName.isEmpty ? DeviceName.current : typedName,
    );
    final error = result.error;
    if (error != null) failure = error;
    signingIn = false;
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
