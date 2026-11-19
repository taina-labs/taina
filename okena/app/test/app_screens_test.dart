import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/app_screens.dart';
import 'package:okena_app/src/mirror/mirror_composition.dart';
import 'package:okena_app/src/mirror/mirror_foreground.dart';
import 'package:okena_app/src/session/session_composition.dart';
import 'package:okena_core/okena_core.dart';

final class _Foreground implements MirrorForeground {
  @override
  bool get isForeground => false;

  @override
  void attach(void Function(bool isForeground) onChanged) {}

  @override
  void dispose() {}
}

void main() {
  test('authenticated shell wires every real feature', () {
    final session = SessionComposition.fake();
    addTearDown(session.dispose);

    final screens = buildShellScreens(session);

    expect(screens.home, isNotNull);
    expect(screens.files, isNotNull);
    expect(screens.gallery, isNotNull);
    expect(screens.mural, isNotNull);
    expect(screens.members, isNotNull);
    expect(screens.storage, isNotNull);
    expect(screens.mirror, isNull);
    expect(screens.saude, isNotNull);
    expect(screens.requests, isNotNull);
    expect(screens.account, isNotNull);
  });

  test('production shell builder wires an injected mirror runtime', () async {
    final session = SessionComposition.fake();
    final runtime = MirrorComposition.production(
      session,
      foreground: _Foreground(),
      ownerFactory: ({required ownerId, required identity}) async =>
          const Err(NotSignedInError()),
    );
    addTearDown(session.dispose);
    addTearDown(runtime.dispose);

    final screens = buildShellScreens(session, mirrorRuntime: runtime);

    expect(screens.mirror, isNotNull);
  });
}
