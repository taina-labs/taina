import 'package:okena_core/okena_core.dart';

/// What the light token read decided for an invite or reset screen.
///
/// The screens open on [AuthChecking], show the dead end on [AuthDead], the
/// retry state on [AuthBroken], and the form only on [AuthOpen].
sealed class AuthGate {
  const AuthGate();
}

final class AuthChecking extends AuthGate {
  const AuthChecking();
}

final class AuthOpen extends AuthGate {
  const AuthOpen();
}

final class AuthDead extends AuthGate {
  const AuthDead();
}

final class AuthBroken extends AuthGate {
  const AuthBroken(this.error);

  final TainaError error;
}
