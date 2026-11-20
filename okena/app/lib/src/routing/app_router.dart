import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/auth/invite_accept_view.dart';
import 'package:okena_app/src/features/auth/reset_password_view.dart';
import 'package:okena_app/src/features/login/login_view.dart';
import 'package:okena_app/src/routing/route_helpers.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_app/src/session/upload_center.dart';
import 'package:okena_app/src/shared/widgets/bootstrap_screen.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import 'shell_screens.dart';

/// Builds the router before or after the session composition is available.
GoRouter createAppRouter({
  SessionModel? session,
  required ShellScreens screens,
}) {
  if (session == null) {
    return GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const BootstrapScreen(),
        ),
      ],
    );
  }
  return createSessionRouter(session: session, screens: screens);
}

/// The authenticated route set is one go_router stack. Service tabs use
/// `go`, so selecting a place replaces the service URL instead of keeping a
/// parallel tab history.
GoRouter createSessionRouter({
  required SessionModel session,
  required ShellScreens screens,
}) {
  final AppRouteBuilder? cameraRoll = screens.cameraRoll;
  return GoRouter(
    initialLocation:
        debugRouteLocation(const String.fromEnvironment('TAINA_ROUTE')) ??
        AppRoutes.home,
    refreshListenable: session,
    redirect: (context, state) =>
        sessionRedirect(session.state, state.uri.toString()),
    routes: [
      GoRoute(
        path: AppRoutes.checking,
        builder: (context, state) => const _CheckingView(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => LoginView(
          session: session,
          onOpenInvite: () => context.push(AppRoutes.invitePaste),
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => LoginView(
          session: session,
          onOpenInvite: () => context.push(AppRoutes.invitePaste),
        ),
      ),
      GoRoute(
        path: AppRoutes.inviteAuth,
        builder: (context, state) => _invite(session),
      ),
      GoRoute(
        path: AppRoutes.invitePaste,
        builder: (context, state) => screens.invitePaste(context, state),
      ),
      GoRoute(
        path: AppRoutes.resetAuth,
        builder: (context, state) => _reset(session),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _AuthenticatedRoutes(session: session, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => screens.home(context, state),
          ),
          GoRoute(
            path: AppRoutes.documentsPraca,
            builder: (context, state) => screens.documents(context, state),
          ),
          GoRoute(
            path: AppRoutes.documentsCasa,
            builder: (context, state) => screens.documents(context, state),
          ),
          GoRoute(
            path: AppRoutes.documentsTrash,
            builder: (context, state) => screens.trash(context, state),
          ),
          GoRoute(
            path: '/documentos/pasta/:rkey',
            builder: (context, state) => screens.folder(context, state),
          ),
          GoRoute(
            path: '/documentos/arquivo/:rkey',
            builder: (context, state) => screens.file(context, state),
          ),
          GoRoute(
            path: AppRoutes.documentsUpload,
            builder: (context, state) => screens.upload(context, state),
          ),
          GoRoute(
            path: AppRoutes.galleryGrid,
            builder: (context, state) => screens.gallery(context, state),
          ),
          GoRoute(
            path: AppRoutes.galleryTimeline,
            builder: (context, state) => screens.gallery(context, state),
          ),
          GoRoute(
            path: AppRoutes.galleryViewer,
            redirect: (context, state) => AppRoutes.galleryGrid,
          ),
          GoRoute(
            path: '/galeria/visualizador/:rkey',
            builder: (context, state) => screens.galleryViewer(context, state),
          ),
          GoRoute(
            path: AppRoutes.mural,
            builder: (context, state) => screens.mural(context, state),
          ),
          GoRoute(
            path: AppRoutes.health,
            builder: (context, state) => screens.health(context, state),
          ),
          GoRoute(
            path: AppRoutes.members,
            builder: (context, state) => screens.members(context, state),
            routes: [
              GoRoute(
                path: 'convidar',
                redirect: (context, state) =>
                    inviteRouteAllowed(session.identity?.ava.papel)
                    ? null
                    : AppRoutes.members,
                builder: (context, state) =>
                    screens.inviteMember(context, state),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.storage,
            builder: (context, state) => screens.storage(context, state),
          ),
          GoRoute(
            path: AppRoutes.account,
            builder: (context, state) => screens.account(context, state),
            routes: [
              GoRoute(
                path: 'pedidos',
                builder: (context, state) => screens.requests(context, state),
              ),
              GoRoute(
                path: 'privacidade',
                builder: (context, state) => screens.privacy(context, state),
              ),
              GoRoute(
                path: 'dispositivos',
                builder: (context, state) => screens.devices(context, state),
              ),
              if (cameraRoll != null)
                GoRoute(
                  path: 'rolo-de-camera',
                  builder: (context, state) => cameraRoll(context, state),
                ),
            ],
          ),
        ],
      ),
    ],
  );
}

Widget _invite(SessionModel session) {
  final SessionState state = session.state;
  if (state is SessionPendingAuth) {
    return InviteAcceptView(session: session, pending: state.pending);
  }
  return const _CheckingView();
}

Widget _reset(SessionModel session) {
  final SessionState state = session.state;
  if (state is SessionPendingAuth) {
    return ResetPasswordView(session: session, pending: state.pending);
  }
  return const _CheckingView();
}

final class _AuthenticatedRoutes extends StatelessWidget {
  const _AuthenticatedRoutes({required this.session, required this.child});

  final SessionModel session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionModel>.value(value: session),
        Provider<SessionGateway>.value(value: _SessionGatewayBinding(session)),
        ChangeNotifierProvider<UploadCenter>.value(value: session.uploadCenter),
      ],
      child: child,
    );
  }
}

final class _SessionGatewayBinding implements SessionGateway {
  const _SessionGatewayBinding(this._session);

  final SessionModel _session;

  @override
  TainaApi get api => _session.api;

  @override
  ThumbnailStore get thumbnails => _session.thumbnails;

  @override
  Me? get identity => _session.identity;

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) =>
      _session.screen(outcome);
}

final class _CheckingView extends StatelessWidget {
  const _CheckingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: TainaLoadingList(itemCount: 4)),
    );
  }
}
