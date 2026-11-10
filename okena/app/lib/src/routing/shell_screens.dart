import 'package:flutter/material.dart';

import '../design_system/design_system.dart';

/// The builders of the authenticated destinations.
///
/// The session agent owns the shell, not the screens inside it. The
/// orchestrator wires the real feature screens here once the other wave-2
/// agents land; until then the router falls back to [ShellPlaceholder], which
/// is deliberately explicit about not being final parity.
final class ShellScreens {
  const ShellScreens({
    this.home,
    this.files,
    this.gallery,
    this.mural,
    this.members,
    this.storage,
    this.saude,
    this.requests,
    this.account,
  });

  final WidgetBuilder? home;
  final WidgetBuilder? files;
  final WidgetBuilder? gallery;
  final WidgetBuilder? mural;
  final WidgetBuilder? members;
  final WidgetBuilder? storage;
  final WidgetBuilder? saude;
  final WidgetBuilder? requests;
  final WidgetBuilder? account;
}

/// The not-yet-integrated destination of a shell branch or a Mais row.
///
/// It exists so the router can be exercised in isolation without reaching
/// into another agent's feature. It is not a finished screen and must not
/// ship: the orchestrator replaces it through [ShellScreens].
final class ShellPlaceholder extends StatelessWidget {
  const ShellPlaceholder({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: TainaEmptyState(
          icon: Icons.construction_outlined,
          title: 'Tela em integração',
          message:
              'Esta tela pertence a outra frente da migração e ainda não foi '
              'conectada a este fluxo.',
        ),
      ),
    );
  }
}
