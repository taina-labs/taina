import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/auth/invite_accept_view.dart';
import 'package:okena_app/src/features/auth/reset_password_view.dart';
import 'package:okena_app/src/features/login/login_view.dart';
import 'package:okena_app/src/features/setup/setup_view.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_app/src/shared/widgets/bootstrap_screen.dart';
import 'package:okena_app/src/shell/more_view.dart';
import 'package:okena_app/src/shell/shell_view.dart';

import 'shell_screens.dart';

/// The app's router.
///
/// Without a [session] it keeps the launch-only router the bootstrap shipped.
/// The orchestrator mounts the real app by passing the composed session:
///
/// ```dart
/// final session = SessionComposition.production();
/// await session.restore();
/// runApp(OkenaApp(router: createAppRouter(session: session)));
/// ```
///
/// Restoring before `runApp` is what lets a cold-start deep link win the
/// restore race: the session source is attached before the router exists.
GoRouter createAppRouter({
  SessionModel? session,
  ShellScreens screens = const ShellScreens(),
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

/// The session-aware router: the explicit state decides the top-level route,
/// and each shell tab keeps its own navigation stack.
GoRouter createSessionRouter({
  required SessionModel session,
  ShellScreens screens = const ShellScreens(),
}) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) =>
        sessionRedirect(session.state, state.matchedLocation),
    routes: [
      GoRoute(
        path: '/checking',
        builder: (context, state) => const _CheckingView(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => SetupView(session: session),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginView(session: session),
      ),
      GoRoute(path: '/convite', builder: (context, state) => _invite(session)),
      GoRoute(path: '/redefinir', builder: (context, state) => _reset(session)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellView(navigationShell: navigationShell, session: session),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inicio',
                builder: (context, state) =>
                    _destination(context, screens.home, 'Início'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/arquivos',
                builder: (context, state) =>
                    _destination(context, screens.files, 'Arquivos'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/fotos',
                builder: (context, state) =>
                    _destination(context, screens.gallery, 'Fotos'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/mural',
                builder: (context, state) =>
                    _destination(context, screens.mural, 'Mural'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/mais',
                builder: (context, state) => const MoreView(),
                routes: [
                  GoRoute(
                    path: 'moradores',
                    builder: (context, state) =>
                        _destination(context, screens.members, 'Moradores'),
                  ),
                  GoRoute(
                    path: 'armazenamento',
                    builder: (context, state) =>
                        _destination(context, screens.storage, 'Armazenamento'),
                  ),
                  GoRoute(
                    path: 'saude',
                    builder: (context, state) =>
                        _destination(context, screens.saude, 'Saúde'),
                  ),
                  GoRoute(
                    path: 'pedidos',
                    builder: (context, state) => _destination(
                      context,
                      screens.requests,
                      'Pedidos de acesso',
                    ),
                  ),
                  GoRoute(
                    path: 'conta',
                    builder: (context, state) =>
                        _destination(context, screens.account, 'Conta'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// The pure switch from the session state to the route that must be on top.
///
/// It is synchronous on purpose: the session owns every decision, and the
/// router only reflects it. A change notifies [SessionModel], go_router
/// re-runs this redirect, and a deep link moves from whichever screen was up
/// to the invite or reset one.
String? sessionRedirect(SessionState state, String location) {
  final path = location.split('?').first;

  switch (state) {
    case SessionChecking():
      return path == '/checking' ? null : '/checking';
    case SessionNeedsInstance():
      return path == '/setup' ? null : '/setup';
    case SessionNeedsLogin():
      return path == '/login' ? null : '/login';
    case SessionPendingAuth(:final pending):
      final target = pending.kind == PendingAuthKind.invite
          ? '/convite'
          : '/redefinir';
      return path == target ? null : target;
    case SessionReady():
      const preAuth = {
        '/',
        '/checking',
        '/setup',
        '/login',
        '/convite',
        '/redefinir',
      };
      if (preAuth.contains(path)) return '/inicio';
      return null;
  }
}

Widget _destination(
  BuildContext context,
  WidgetBuilder? builder,
  String title,
) {
  return builder?.call(context) ?? ShellPlaceholder(title: title);
}

Widget _invite(SessionModel session) {
  final state = session.state;
  if (state is SessionPendingAuth) {
    return InviteAcceptView(session: session, pending: state.pending);
  }
  return const _CheckingView();
}

Widget _reset(SessionModel session) {
  final state = session.state;
  if (state is SessionPendingAuth) {
    return ResetPasswordView(session: session, pending: state.pending);
  }
  return const _CheckingView();
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
