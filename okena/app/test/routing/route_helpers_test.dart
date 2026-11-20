import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/routing/route_helpers.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../session/support/session_support.dart';

void main() {
  group('parentAwareBackLabel', () {
    test('names the hub and short parents, then falls back to Voltar', () {
      expect(parentAwareBackLabel(parentIsHub: true), 'Início');
      expect(
        parentAwareBackLabel(parentIsHub: false, parentName: 'Documentos'),
        'Documentos',
      );
      expect(
        parentAwareBackLabel(parentIsHub: false, parentName: 'Pasta'),
        'Pasta',
      );
      expect(
        parentAwareBackLabel(parentIsHub: false, parentName: '123456789012'),
        '123456789012',
      );
      expect(
        parentAwareBackLabel(parentIsHub: false, parentName: '1234567890123'),
        'Voltar',
      );
      expect(parentAwareBackLabel(parentIsHub: false), 'Voltar');
    });
  });

  group('service route helpers', () {
    test('service tabs resolve to replacement locations', () {
      expect(
        serviceTabLocation(ServiceTab.documentsCasa),
        AppRoutes.documentsCasa,
      );
      expect(
        serviceTabLocation(ServiceTab.galleryTimeline),
        AppRoutes.galleryTimeline,
      );
      expect(
        AppRoutes.folder('abc', Zona.casa),
        '/documentos/pasta/abc?zona=casa',
      );
    });

    test('the tab bar is visible only on service places', () {
      for (final String route in [
        AppRoutes.documentsPraca,
        AppRoutes.documentsCasa,
        AppRoutes.documentsTrash,
        '/documentos/pasta/abc?zona=casa',
        AppRoutes.galleryGrid,
        AppRoutes.galleryTimeline,
      ]) {
        expect(serviceTabBarVisible(route), isTrue, reason: route);
      }
      for (final String route in [
        AppRoutes.documentsUpload,
        AppRoutes.file('abc'),
        AppRoutes.galleryPhoto('abc'),
        AppRoutes.mural,
        AppRoutes.account,
      ]) {
        expect(serviceTabBarVisible(route), isFalse, reason: route);
      }
    });
  });

  test('debug launch routes parse into canonical locations', () {
    expect(debugRouteLocation('documentos/casa'), AppRoutes.documentsCasa);
    expect(
      debugRouteLocation('pasta/abc?zona=casa'),
      '/documentos/pasta/abc?zona=casa',
    );
    expect(debugRouteLocation('pasta/abc'), '/documentos/pasta/abc?zona=praca');
    expect(debugRouteLocation('arquivo/a-file'), '/documentos/arquivo/a-file');
    expect(
      debugRouteLocation('galeria/visualizador/photo-1'),
      '/galeria/visualizador/photo-1',
    );
    expect(debugRouteLocation('/galeria/grade'), AppRoutes.galleryGrid);
    expect(debugRouteLocation('unknown'), isNull);
  });

  test('only zeladores can open the invitation route', () {
    expect(inviteRouteAllowed(Papel.zelador), isTrue);
    expect(inviteRouteAllowed(Papel.morador), isFalse);
    expect(inviteRouteAllowed(null), isFalse);
  });

  group('sessionRedirect', () {
    test('both unauthenticated states use the existing login flow', () {
      expect(
        sessionRedirect(const SessionNeedsInstance(), '/'),
        AppRoutes.login,
      );
      expect(sessionRedirect(const SessionNeedsLogin(), '/'), AppRoutes.login);
      expect(sessionRedirect(const SessionNeedsInstance(), '/login'), isNull);
      expect(
        sessionRedirect(const SessionNeedsLogin(), AppRoutes.invitePaste),
        isNull,
      );
    });

    test('restoring preserves a local deep link through login', () {
      final String checking = sessionRedirect(
        const SessionChecking(),
        '/documentos/pasta/abc?zona=casa',
      )!;
      expect(checking, startsWith('/checking?from='));
      final String login = sessionRedirect(
        const SessionNeedsLogin(),
        checking,
      )!;
      expect(login, startsWith('/login?from='));
      expect(
        sessionRedirect(SessionReady(testMe()), login),
        '/documentos/pasta/abc?zona=casa',
      );
    });

    test('restoring permits the route-composed invite paste screen', () {
      final String checking = sessionRedirect(
        const SessionChecking(),
        AppRoutes.invitePaste,
      )!;
      expect(
        sessionRedirect(const SessionNeedsInstance(), checking),
        AppRoutes.invitePaste,
      );
      expect(
        sessionRedirect(const SessionNeedsLogin(), AppRoutes.invitePaste),
        isNull,
      );
    });

    test(
      'a ready session leaves auth routes for the hub or saved destination',
      () {
        final SessionReady ready = SessionReady(testMe());
        expect(sessionRedirect(ready, '/login'), AppRoutes.home);
        expect(
          sessionRedirect(ready, '/login?from=%2Fsaude'),
          AppRoutes.health,
        );
        expect(sessionRedirect(ready, AppRoutes.members), isNull);
      },
    );

    test('pending authentication routes stay authoritative', () {
      expect(
        sessionRedirect(
          SessionPendingAuth(
            const PendingAuth(kind: PendingAuthKind.invite, token: 'token'),
          ),
          '/login',
        ),
        AppRoutes.inviteAuth,
      );
      expect(
        sessionRedirect(
          SessionPendingAuth(
            const PendingAuth(kind: PendingAuthKind.reset, token: 'token'),
          ),
          '/login',
        ),
        AppRoutes.resetAuth,
      );
    });

    test('return targets cannot redirect outside the app', () {
      expect(
        sessionRedirect(const SessionNeedsLogin(), '/login?from=https://evil'),
        isNull,
      );
      expect(
        sessionRedirect(
          SessionReady(testMe()),
          '/login?from=https%3A%2F%2Fevil',
        ),
        AppRoutes.home,
      );
    });
  });
}
