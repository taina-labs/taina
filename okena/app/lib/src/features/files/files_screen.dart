import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../session/session_gateway.dart';
import 'browser_scaffold.dart';
import 'file_actions.dart';
import 'files_view_model.dart';

/// The browser's root: the community's own folder.
final class FilesScreen extends StatelessWidget {
  const FilesScreen({
    required this.session,
    required this.actions,
    this.model,
    this.title = 'Arquivos',
    this.onOpenFolder,
    this.onOpenFile,
    this.onOpenTrash,
    super.key,
  });

  final SessionGateway session;
  final FileActions actions;

  /// An already built model, for tests and previews. When null the screen
  /// builds its own and starts the load.
  final FilesViewModel? model;
  final String title;
  final ValueChanged<Folder>? onOpenFolder;
  final ValueChanged<FileRecord>? onOpenFile;
  final VoidCallback? onOpenTrash;

  @override
  Widget build(BuildContext context) {
    final scaffold = BrowserScaffold(
      title: title,
      destinationZona: Zona.casa,
      onOpenFolder: onOpenFolder,
      onOpenFile: onOpenFile,
      onOpenTrash: onOpenTrash,
    );
    final injected = model;
    if (injected != null) {
      return ChangeNotifierProvider<FilesViewModel>.value(
        value: injected,
        child: scaffold,
      );
    }
    return ChangeNotifierProvider<FilesViewModel>(
      create: (context) {
        final created = FilesViewModel(session: session, actions: actions);
        unawaited(created.load());
        return created;
      },
      child: scaffold,
    );
  }
}
