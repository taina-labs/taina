import 'package:flutter/material.dart';
import 'package:okena_app/src/features/account/account_screen.dart';
import 'package:okena_app/src/features/files/file_detail_screen.dart';
import 'package:okena_app/src/features/files/files_screen.dart';
import 'package:okena_app/src/features/files/folder_screen.dart';
import 'package:okena_app/src/features/files/platform_file_actions.dart';
import 'package:okena_app/src/features/gallery/gallery_screen.dart';
import 'package:okena_app/src/features/home/home_screen.dart';
import 'package:okena_app/src/features/members/members_screen.dart';
import 'package:okena_app/src/features/mural/mural_screen.dart';
import 'package:okena_app/src/features/requests/requests_screen.dart';
import 'package:okena_app/src/features/saude/saude_screen.dart';
import 'package:okena_app/src/features/storage/storage_screen.dart';
import 'package:okena_app/src/features/trash/trash_screen.dart';
import 'package:okena_app/src/routing/shell_screens.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/shell/shell_model.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// Wires every feature into the authenticated shell at the composition root.
ShellScreens buildShellScreens(SessionModel session) {
  const actions = PlatformFileActions();

  return ShellScreens(
    home: (context) => HomeScreen(
      gateway: context.read<SessionGateway>(),
      onOpenFile: (file) => _openFile(context, session, actions, file),
      onOpenMural: () => context.read<ShellModel>().open(ShellTab.mural),
      onOpenRequests: () =>
          context.read<ShellModel>().openMore(MoreRoute.pedidos),
    ),
    files: (context) => _filesScreen(context, session, actions),
    gallery: (context) => GalleryScreen(
      gateway: context.read<SessionGateway>(),
      onShareFile: actions.share,
      onImmersiveChanged: context.read<ShellModel>().setImmersive,
    ),
    mural: (context) => MuralScreen(session: context.read<SessionGateway>()),
    members: (context) =>
        MembersScreen(session: context.read<SessionGateway>()),
    storage: (context) =>
        StorageScreen(session: context.read<SessionGateway>()),
    saude: (context) => SaudeScreen(session: context.read<SessionGateway>()),
    requests: (context) =>
        RequestsScreen(session: context.read<SessionGateway>()),
    account: (context) => AccountScreen(
      session: context.read<SessionGateway>(),
      onSignOut: session.signOut,
      hostDisplay: session.host?.display,
      cleartext: session.host?.isCleartext ?? false,
    ),
  );
}

Widget _filesScreen(
  BuildContext context,
  SessionModel session,
  PlatformFileActions actions,
) {
  final gateway = context.read<SessionGateway>();
  return FilesScreen(
    session: gateway,
    actions: actions,
    onOpenFolder: (folder) => _openFolder(context, session, actions, folder),
    onOpenFile: (file) => _openFile(context, session, actions, file),
    onOpenTrash: () => _openTrash(context, session),
  );
}

void _openFolder(
  BuildContext context,
  SessionModel session,
  PlatformFileActions actions,
  Folder folder,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) {
        final gateway = context.read<SessionGateway>();
        return FolderScreen(
          session: gateway,
          actions: actions,
          folder: folder,
          onOpenFolder: (next) => _openFolder(context, session, actions, next),
          onOpenFile: (file) => _openFile(context, session, actions, file),
          onOpenTrash: () => _openTrash(context, session),
        );
      },
    ),
  );
}

void _openFile(
  BuildContext context,
  SessionModel session,
  PlatformFileActions actions,
  FileRecord file,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => FileDetailScreen(
        session: context.read<SessionGateway>(),
        actions: actions,
        file: file,
      ),
    ),
  );
}

void _openTrash(BuildContext context, SessionModel session) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          TrashScreen(session: context.read<SessionGateway>()),
    ),
  );
}
