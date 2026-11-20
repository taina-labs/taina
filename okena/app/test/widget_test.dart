import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:okena_app/src/app.dart';
import 'package:okena_app/src/routing/app_router.dart';
import 'package:okena_app/src/routing/shell_screens.dart';

ShellScreens _screens() {
  Widget screen(BuildContext context, GoRouterState state) =>
      const SizedBox.shrink();

  return ShellScreens(
    home: screen,
    documents: screen,
    trash: screen,
    folder: screen,
    file: screen,
    upload: screen,
    gallery: screen,
    galleryViewer: screen,
    mural: screen,
    health: screen,
    members: screen,
    inviteMember: screen,
    storage: screen,
    account: screen,
    requests: screen,
    privacy: screen,
    devices: screen,
    invitePaste: screen,
  );
}

void main() {
  testWidgets('app boots into the initial route', (tester) async {
    await tester.pumpWidget(
      OkenaApp(router: createAppRouter(screens: _screens())),
    );

    expect(find.text('Tainá'), findsOneWidget);
    expect(find.text('Preparando o app.'), findsOneWidget);
  });
}
