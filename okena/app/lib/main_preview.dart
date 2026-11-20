import 'package:flutter/widgets.dart';
import 'package:okena_app/src/app.dart';
import 'package:okena_app/src/app_screens.dart';
import 'package:okena_app/src/routing/app_router.dart';
import 'package:okena_app/src/session/session_composition.dart';
import 'package:okena_core/okena_core.dart';

/// Runs the app over the seeded fake API for local visual verification.
///
/// Select a route with `--dart-define=TAINA_ROUTE=documentos/casa`, using the
/// same route names as `debugRouteLocation`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = FakeTainaApi(delay: Duration.zero);
  final created = await api.createSession(
    username: 'ana',
    password: 'segredo',
    deviceName: 'Aparelho de teste',
  );
  final sessionToken = created.value!;
  final host = InstanceAddress.parse('https://box.local').value!;
  final session = SessionComposition.fake(
    api: api,
    host: host,
    storage: InMemorySessionStorage(sessionToken),
  );
  await session.restore();
  final router = createAppRouter(
    session: session,
    screens: buildShellScreens(session),
  );
  runApp(OkenaApp(router: router));
}
