import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/app_screens.dart';
import 'package:okena_app/src/features/account/account_screen.dart';
import 'package:okena_app/src/mirror/mirror_composition.dart';
import 'package:okena_app/src/mirror/mirror_foreground.dart';
import 'package:okena_app/src/features/account/devices_screen.dart';
import 'package:okena_app/src/features/files/upload_screen.dart';
import 'package:okena_app/src/features/gallery/gallery_model.dart';
import 'package:okena_app/src/features/gallery/gallery_screen.dart';
import 'package:okena_app/src/features/gallery/gallery_viewer.dart';
import 'package:okena_app/src/features/home/home_screen.dart';
import 'package:okena_app/src/features/mirror/mirror_screen.dart';
import 'package:okena_app/src/features/privacy/privacy_screen.dart';
import 'package:okena_app/src/routing/app_router.dart';
import 'package:okena_app/src/routing/route_helpers.dart';
import 'package:okena_app/src/session/session_composition.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_app/src/session/upload_center.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import 'session/support/session_support.dart';

final class _Foreground implements MirrorForeground {
  @override
  bool get isForeground => false;

  @override
  void attach(void Function(bool isForeground) onChanged) {}

  @override
  void dispose() {}
}

void main() {
  Future<SessionModel> readySession() async {
    final api = FakeTainaApi(delay: Duration.zero);
    final created = await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Aparelho de teste',
    );
    final session = created.value!;
    return makeSession(
      api: api,
      host: testBox(),
      storage: InMemorySessionStorage(session),
      state: SessionReady(session.identity),
    ).model;
  }

  test('the route composition mounts existing feature implementations', () {
    final session = SessionComposition.fake();
    addTearDown(session.dispose);

    final screens = buildShellScreens(session);

    expect(screens.home, isNotNull);
    expect(screens.documents, isNotNull);
    expect(screens.trash, isNotNull);
    expect(screens.folder, isNotNull);
    expect(screens.file, isNotNull);
    expect(screens.upload, isNotNull);
    expect(screens.gallery, isNotNull);
    expect(screens.galleryViewer, isNotNull);
    expect(screens.mural, isNotNull);
    expect(screens.health, isNotNull);
    expect(screens.members, isNotNull);
    expect(screens.inviteMember, isNotNull);
    expect(screens.storage, isNotNull);
    expect(screens.account, isNotNull);
    expect(screens.requests, isNotNull);
    expect(screens.privacy, isNotNull);
    expect(screens.devices, isNotNull);
    expect(screens.cameraRoll, isNull);
    expect(session.uploadCenter, isNotNull);
  });

  test('the camera-roll route mounts an injected mirror runtime', () {
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

    expect(screens.cameraRoll, isNotNull);
  });

  testWidgets('Conta opens the camera-roll route through app routing', (
    tester,
  ) async {
    final SessionModel session = await readySession();
    final runtime = MirrorComposition.production(
      session,
      foreground: _Foreground(),
      ownerFactory: ({required ownerId, required identity}) async =>
          const Err(NotSignedInError()),
    );
    addTearDown(session.dispose);
    addTearDown(runtime.dispose);

    final GoRouter router = createSessionRouter(
      session: session,
      screens: buildShellScreens(session, mirrorRuntime: runtime),
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: TainaTheme.data, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conta'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Rolo de câmera'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Rolo de câmera'));
    await tester.pump();

    expect(find.byType(MirrorScreen), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('Conta hides camera-roll when no mirror runtime is composed', (
    tester,
  ) async {
    final SessionModel session = await readySession();
    addTearDown(session.dispose);
    final GoRouter router = createSessionRouter(
      session: session,
      screens: buildShellScreens(session),
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: TainaTheme.data, routerConfig: router),
    );
    await tester.pumpAndSettle();

    router.go(AppRoutes.account);
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.text('Rolo de câmera'), findsNothing);
    router.go(AppRoutes.cameraRoll);
    await tester.pumpAndSettle();
    expect(find.byType(MirrorScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Conta rows open privacy, devices and sent Pedidos destinations',
    (tester) async {
      final SessionModel session = await readySession();
      addTearDown(session.dispose);
      final GoRouter router = createSessionRouter(
        session: session,
        screens: buildShellScreens(session),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: TainaTheme.data, routerConfig: router),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.account);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.account);
      await tester.ensureVisible(find.text('Privacidade'));
      await tester.tap(find.text('Privacidade'));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen), findsOneWidget);
      expect(find.text('Sua casa é só sua'), findsOneWidget);

      await tester.tap(find.text('Conta'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dispositivos'));
      await tester.tap(find.text('Dispositivos'));
      await tester.pumpAndSettle();
      expect(find.byType(DevicesScreen), findsOneWidget);

      router.go(
        AppRoutes.requests,
        extra: const RequestsRouteTarget(
          backLabel: 'Conta',
          showSentState: true,
          sentTo: 'Joana',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pedido enviado'), findsOneWidget);
      expect(
        find.text('Joana vai decidir. Você vê a resposta aqui em Pedidos.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Galeria replaces its tab route and hands Enviar to the session center',
    (tester) async {
      final SessionModel session = await readySession();
      addTearDown(session.dispose);
      final GoRouter router = createSessionRouter(
        session: session,
        screens: buildShellScreens(session),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: TainaTheme.data, routerConfig: router),
      );
      await tester.pumpAndSettle();

      router.push(AppRoutes.galleryGrid);
      await tester.pumpAndSettle();
      expect(find.byType(GalleryScreen), findsOneWidget);
      await tester.tap(find.text('Linha do tempo'));
      await tester.pumpAndSettle();
      final BuildContext galleryContext = tester.element(
        find.text('Linha do tempo').first,
      );
      expect(
        Provider.of<GalleryModel>(galleryContext, listen: false).tab,
        GalleryTab.timeline,
      );

      final UploadCenter center = session.uploadCenter;
      router.push(
        AppRoutes.documentsUpload,
        extra: UploadRouteTarget(
          request: const UploadRequest(
            path: 'missing-upload-test-file',
            name: 'Arquivo de teste.txt',
            mime: 'text/plain',
          ),
          backLabel: 'Galeria',
          returnLocation: AppRoutes.galleryTimeline,
        ),
      );
      await tester.pumpAndSettle();

      expect(identical(center, session.uploadCenter), isTrue);
      expect(find.byType(EnviarScreen), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(GalleryScreen), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'viewer deep link opens the requested timeline photo and returns to its tab',
    (tester) async {
      final SessionModel session = await readySession();
      addTearDown(session.dispose);
      final timeline = (await session.api.photoTimeline(
        limit: null,
        cursor: null,
      )).value!;
      final FileRecord target = timeline.items.first.photos.first;
      final GoRouter router = createSessionRouter(
        session: session,
        screens: buildShellScreens(session),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: TainaTheme.data, routerConfig: router),
      );
      await tester.pumpAndSettle();

      router.go(
        AppRoutes.galleryPhoto(target.rkey, tab: GalleryRouteTab.timeline),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GalleryViewerScreen), findsOneWidget);
      final GalleryViewerScreen viewer = tester.widget(
        find.byType(GalleryViewerScreen),
      );
      expect(viewer.model.tab, GalleryTab.timeline);
      expect(viewer.model.viewer?.file?.rkey, target.rkey);

      await tester.tap(find.bySemanticsLabel('Fechar visualização'));
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.galleryTimeline,
      );
      expect(find.byType(GalleryScreen), findsOneWidget);
    },
  );
}
