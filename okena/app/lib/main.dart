import 'package:flutter/widgets.dart';
import 'package:okena_app/src/app.dart';
import 'package:okena_app/src/app_screens.dart';
import 'package:okena_app/src/mirror/mirror_composition.dart';
import 'package:okena_app/src/routing/app_router.dart';
import 'package:okena_app/src/session/session_composition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionComposition.production();
  final mirror = MirrorComposition.production(session);
  await session.restore();
  mirror.attach();
  final router = createAppRouter(
    session: session,
    screens: buildShellScreens(session, mirrorRuntime: mirror),
  );
  runApp(OkenaApp(router: router));
}
