import 'package:flutter/widgets.dart';
import 'package:okena_app/src/app.dart';
import 'package:okena_app/src/app_screens.dart';
import 'package:okena_app/src/routing/app_router.dart';
import 'package:okena_app/src/session/session_composition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionComposition.production();
  await session.restore();
  final router = createAppRouter(
    session: session,
    screens: buildShellScreens(session),
  );
  runApp(OkenaApp(router: router));
}
