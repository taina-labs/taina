import 'package:material_ui/material_ui.dart';

import '../../session/session_model.dart';
import '../login/login_view.dart';

/// Compatibility entry point. First access is part of the sign-in screen.
final class SetupView extends StatelessWidget {
  const SetupView({required this.session, super.key});

  final SessionModel session;

  @override
  Widget build(BuildContext context) => LoginView(session: session);
}
