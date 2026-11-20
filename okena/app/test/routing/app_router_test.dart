import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/login/login_view.dart';
import 'package:okena_app/src/routing/app_router.dart';
import 'package:okena_app/src/routing/route_helpers.dart';
import 'package:okena_app/src/routing/shell_screens.dart';
import 'package:okena_app/src/session/session_composition.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_app/src/session/upload_center.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../session/support/session_support.dart';

ShellScreens _screens() {
  AppRouteBuilder screen(String name) {
    return (context, state) => Scaffold(
      body: Center(
        child: Text(
          '$name:${state.uri.path}:'
          '${state.uri.queryParameters['zona'] ?? ''}:'
          '${state.pathParameters['rkey'] ?? ''}',
        ),
      ),
    );
  }

  return ShellScreens(
    home: screen('hub'),
    documents: screen('documentos'),
    trash: screen('lixeira'),
    folder: screen('pasta'),
    file: screen('arquivo'),
    upload: (context, state) => Text(
      'upload:${identical(context.read<UploadCenter>(), _testUploadCenter)}',
    ),
    gallery: screen('galeria'),
    galleryViewer: screen('visualizador'),
    mural: screen('mural'),
    health: screen('saude'),
    members: screen('moradores'),
    inviteMember: screen('convidar'),
    storage: screen('armazenamento'),
    account: screen('conta'),
    requests: screen('pedidos'),
    privacy: screen('privacidade'),
    devices: screen('dispositivos'),
    cameraRoll: screen('rolo'),
    invitePaste: screen('invite-paste'),
  );
}

UploadCenter? _testUploadCenter;

Widget _app(GoRouter router) {
  return MaterialApp.router(theme: TainaTheme.data, routerConfig: router);
}

Future<SessionModel> _readyModel() async {
  final FakeTainaApi fake = FakeTainaApi(delay: Duration.zero);
  return makeSession(
    api: fake,
    host: testBox(),
    storage: InMemorySessionStorage(testSession()),
    state: SessionReady(testMe()),
  ).model;
}

void main() {
  testWidgets('a ready session opens the Hub without global navigation', (
    tester,
  ) async {
    final SessionModel model = await _readyModel();
    final GoRouter router = createSessionRouter(
      session: model,
      screens: _screens(),
    );

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.text('hub:/::'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Mais'), findsNothing);
  });

  testWidgets('service places use one route and replace selected tabs', (
    tester,
  ) async {
    final SessionModel model = await _readyModel();
    final GoRouter router = createSessionRouter(
      session: model,
      screens: _screens(),
    );
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    router.push(AppRoutes.documentsPraca);
    await tester.pumpAndSettle();
    expect(find.text('documentos:/documentos/praca::'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    router.go(serviceTabLocation(ServiceTab.documentsCasa));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.documentsCasa,
    );
    expect(find.text('documentos:/documentos/casa::'), findsOneWidget);

    router.go(serviceTabLocation(ServiceTab.documentsTrash));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.documentsTrash,
    );
    expect(find.text('lixeira:/documentos/lixeira::'), findsOneWidget);
  });

  testWidgets('all Hub-and-spoke and incoming screen routes resolve', (
    tester,
  ) async {
    final SessionModel model = await _readyModel();
    final GoRouter router = createSessionRouter(
      session: model,
      screens: _screens(),
    );
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    final Map<String, String> routes = {
      AppRoutes.documentsPraca: 'documentos:/documentos/praca::',
      AppRoutes.documentsCasa: 'documentos:/documentos/casa::',
      AppRoutes.documentsTrash: 'lixeira:/documentos/lixeira::',
      '/documentos/pasta/folder-1?zona=casa':
          'pasta:/documentos/pasta/folder-1:casa:folder-1',
      '/documentos/arquivo/file-1':
          'arquivo:/documentos/arquivo/file-1::file-1',
      AppRoutes.documentsUpload: 'upload:true',
      AppRoutes.galleryGrid: 'galeria:/galeria/grade::',
      AppRoutes.galleryTimeline: 'galeria:/galeria/linha-do-tempo::',
      AppRoutes.galleryViewer: 'visualizador:/galeria/visualizador::',
      '/galeria/visualizador/photo-1':
          'visualizador:/galeria/visualizador/photo-1::photo-1',
      AppRoutes.mural: 'mural:/mural::',
      AppRoutes.health: 'saude:/saude::',
      AppRoutes.members: 'moradores:/moradores::',
      AppRoutes.inviteMember: 'convidar:/moradores/convidar::',
      AppRoutes.storage: 'armazenamento:/armazenamento::',
      AppRoutes.account: 'conta:/conta::',
      AppRoutes.requests: 'pedidos:/conta/pedidos::',
      AppRoutes.privacy: 'privacidade:/conta/privacidade::',
      AppRoutes.devices: 'dispositivos:/conta/dispositivos::',
      AppRoutes.cameraRoll: 'rolo:/conta/rolo-de-camera::',
      AppRoutes.invitePaste: 'invite-paste:/convite/colar::',
    };

    _testUploadCenter = model.uploadCenter;
    for (final MapEntry<String, String> entry in routes.entries) {
      router.go(entry.key);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
    }

    final UploadCenter center = model.uploadCenter;
    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(identical(center, model.uploadCenter), isTrue);
    _testUploadCenter = null;
  });

  testWidgets('mirror remains directly reachable on its own route', (
    tester,
  ) async {
    final SessionModel model = await _readyModel();
    final GoRouter router = createSessionRouter(
      session: model,
      screens: _screens(),
    );

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    router.go(AppRoutes.cameraRoll);
    await tester.pumpAndSettle();

    expect(find.text('rolo:/conta/rolo-de-camera::'), findsOneWidget);
  });

  testWidgets('a morador cannot enter the zelador-only invite route', (
    tester,
  ) async {
    const Ava morador = Ava(
      publicId: 'morador',
      username: 'joana',
      displayName: 'Joana',
      papel: Papel.morador,
      activatedAt: '2026-01-01T00:00:00Z',
      deactivatedAt: null,
      createdAt: '2026-01-01T00:00:00Z',
    );
    final SessionModel model = makeSession(
      host: testBox(),
      state: SessionReady(
        Me(ava: morador, tekoa: testTekoa, device: testDevice),
      ),
    ).model;
    final GoRouter router = createSessionRouter(
      session: model,
      screens: _screens(),
    );
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    router.go(AppRoutes.inviteMember);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, AppRoutes.members);
    expect(find.text('moradores:/moradores::'), findsOneWidget);
  });

  testWidgets('a login round trip preserves a deep link and its zone', (
    tester,
  ) async {
    final SessionModel model = SessionComposition.fake(host: testBox());
    await model.restore();
    final GoRouter router = createSessionRouter(
      session: model,
      screens: _screens(),
    );

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    router.go('/documentos/pasta/folder-1?zona=casa');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, AppRoutes.login);
    expect(
      router.routeInformationProvider.value.uri.queryParameters['from'],
      '/documentos/pasta/folder-1?zona=casa',
    );

    await model.login(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Aparelho de teste',
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/documentos/pasta/folder-1',
    );
    expect(
      find.text('pasta:/documentos/pasta/folder-1:casa:folder-1'),
      findsOneWidget,
    );
  });

  testWidgets(
    'atomic first access keeps failed login mounted and success opens Hub',
    (tester) async {
      final model = makeSession(
        state: const SessionNeedsInstance(),
        probe: (_) async => const Ok(
          Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
        ),
      ).model;
      final router = createSessionRouter(session: model, screens: _screens());

      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'box.local');
      await tester.enterText(find.byType(TextField).at(1), 'sem-acesso');
      await tester.enterText(find.byType(TextField).at(2), 'segredo');

      final failed = await model.connectAndLogin(
        address: 'box.local',
        username: 'sem-acesso',
        password: 'segredo',
        deviceName: 'Android de ana',
      );
      await tester.pumpAndSettle();

      expect(failed.error, isA<ApiError>());
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.login);
      expect(find.byType(LoginView), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'sem-acesso',
      );

      final succeeded = await model.connectAndLogin(
        address: 'box.local',
        username: 'ana',
        password: 'segredo',
        deviceName: 'Android de ana',
      );
      await tester.pumpAndSettle();

      expect(succeeded.value, isNotNull);
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.home);
      expect(find.text('hub:/::'), findsOneWidget);
    },
  );

  testWidgets('both no-box and saved-box sessions land on login', (
    tester,
  ) async {
    final model = makeSession(state: const SessionNeedsInstance()).model;
    final router = createSessionRouter(session: model, screens: _screens());
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    expect(find.text('Entrar'), findsOneWidget);

    final savedHost = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    ).model;
    final savedRouter = createSessionRouter(
      session: savedHost,
      screens: _screens(),
    );
    await tester.pumpWidget(_app(savedRouter));
    await tester.pumpAndSettle();
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('Login opens the route-composed invite paste screen', (
    tester,
  ) async {
    final SessionModel model = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    ).model;
    final GoRouter router = createSessionRouter(
      session: model,
      screens: _screens(),
    );
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Tenho um convite'));
    await tester.tap(find.text('Tenho um convite'));
    await tester.pumpAndSettle();

    expect(find.text('invite-paste:/convite/colar::'), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('checking and pending-auth routes remain session-owned', (
    tester,
  ) async {
    final checking = makeSession().model;
    final checkingRouter = createSessionRouter(
      session: checking,
      screens: _screens(),
    );
    await tester.pumpWidget(_app(checkingRouter));
    await tester.pump();
    expect(find.byType(TainaLoadingList), findsOneWidget);

    final invite = makeSession(
      host: testBox(),
      state: SessionPendingAuth(
        const PendingAuth(kind: PendingAuthKind.invite, token: 'tk1'),
      ),
    ).model;
    final inviteRouter = createSessionRouter(
      session: invite,
      screens: _screens(),
    );
    await tester.pumpWidget(_app(inviteRouter));
    await tester.pumpAndSettle();
    expect(find.text('Você recebeu um convite'), findsOneWidget);
  });

  testWidgets('sign out returns from the Hub to the existing login screen', (
    tester,
  ) async {
    final SessionModel model = await _readyModel();
    final GoRouter router = createSessionRouter(
      session: model,
      screens: _screens(),
    );
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    await model.signOut();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, AppRoutes.login);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
