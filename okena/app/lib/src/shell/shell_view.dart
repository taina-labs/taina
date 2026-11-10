import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../design_system/design_system.dart';
import '../session/session_gateway.dart';
import '../session/session_model.dart';
import 'shell_model.dart';

/// The authenticated shell: a `NavigationBar` over the five tab stacks that
/// [StatefulShellRoute.indexedStack] keeps alive.
///
/// The session and the shell controller are provided to every tab, so a
/// screen can open another tab or a Mais row without reaching for the router
/// directly.
final class ShellView extends StatefulWidget {
  const ShellView({
    required this.navigationShell,
    required this.session,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final SessionModel session;

  @override
  State<ShellView> createState() => _ShellViewState();
}

final class _ShellViewState extends State<ShellView> {
  late final ShellModel _shell = ShellModel(
    onOpenTab: _openTab,
    onOpenMore: _openMore,
  );
  late final SessionGateway _gateway = _GatewayBinding(widget.session);
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _router ??= GoRouter.of(context);
  }

  void _openTab(ShellTab tab) {
    widget.navigationShell.goBranch(tab.index);
  }

  void _openMore(MoreRoute route) {
    widget.navigationShell.goBranch(ShellTab.mais.index);
    _router?.go('/mais/${route.segment}');
  }

  @override
  void dispose() {
    _shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _shell,
      builder: (context, _) {
        return Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<SessionModel>.value(value: widget.session),
              Provider<SessionGateway>.value(value: _gateway),
              ChangeNotifierProvider<ShellModel>.value(value: _shell),
            ],
            child: widget.navigationShell,
          ),
          bottomNavigationBar: _shell.immersive
              ? null
              : NavigationBar(
                  selectedIndex: widget.navigationShell.currentIndex,
                  onDestinationSelected: (index) {
                    widget.navigationShell.goBranch(
                      index,
                      initialLocation: false,
                    );
                  },
                  backgroundColor: TainaPalette.bgApp,
                  indicatorColor: TainaPalette.surfaceRaised,
                  surfaceTintColor: Colors.transparent,
                  destinations: [
                    for (final tab in ShellTab.values)
                      NavigationDestination(
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(
                          tab.selectedIcon,
                          color: TainaPalette.brandPrimary,
                        ),
                        label: tab.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// The read-only gateway a feature can hold.
///
/// `SessionGateway` is not a [Listenable], so it is provided through a plain
/// wrapper: screens that need to react to the session listen to the
/// `SessionModel` provider, and screens that only call the API use this.
final class _GatewayBinding implements SessionGateway {
  const _GatewayBinding(this._session);

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
