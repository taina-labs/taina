import 'package:okena_core/okena_core.dart';

/// The two links a box hands out: the invite that creates an account and the
/// reset that defines a new password.
enum PendingAuthKind { invite, reset }

/// A deep link in flight: the token of an invite or a reset, with the screens
/// of `features/auth` on top of the app.
final class PendingAuth {
  const PendingAuth({required this.kind, required this.token});

  final PendingAuthKind kind;
  final String token;

  @override
  bool operator ==(Object other) =>
      other is PendingAuth && other.kind == kind && other.token == token;

  @override
  int get hashCode => Object.hash(PendingAuth, kind, token);
}

/// The explicit session states the root switch renders.
///
/// The state is the whole decision of which screen is on top: restoring,
/// setting up, signing in, deciding a deep link, or the authenticated shell.
sealed class SessionState {
  const SessionState();
}

/// Restoring the saved address and session from the device.
final class SessionChecking extends SessionState {
  const SessionChecking();
}

/// No box address yet.
final class SessionNeedsInstance extends SessionState {
  const SessionNeedsInstance();
}

/// A box answers, nobody is signed in.
final class SessionNeedsLogin extends SessionState {
  const SessionNeedsLogin();
}

/// Signed in: the shell takes over.
final class SessionReady extends SessionState {
  const SessionReady(this.me);

  final Me me;
}

/// A deep link is being decided: the invite or reset screen is on top.
final class SessionPendingAuth extends SessionState {
  const SessionPendingAuth(this.pending);

  final PendingAuth pending;
}
