import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/app_screens.dart';
import 'package:okena_app/src/session/session_composition.dart';

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
    expect(screens.saude, isNotNull);
    expect(screens.requests, isNotNull);
    expect(screens.account, isNotNull);
  });
}
