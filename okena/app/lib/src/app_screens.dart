import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/account/account_screen.dart';
import 'package:okena_app/src/features/account/devices_screen.dart';
import 'package:okena_app/src/features/privacy/privacy_screen.dart';
import 'package:okena_app/src/features/files/file_detail_screen.dart';
import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/features/files/files_screen.dart';
import 'package:okena_app/src/features/files/folder_screen.dart';
import 'package:okena_app/src/features/files/upload_screen.dart';
import 'package:okena_app/src/features/files/platform_file_actions.dart';
import 'package:okena_app/src/features/camera_roll/platform_media_picker.dart';
import 'package:okena_app/src/features/gallery/gallery_screen.dart';
import 'package:okena_app/src/features/gallery/gallery_model.dart';
import 'package:okena_app/src/features/gallery/gallery_viewer.dart';
import 'package:okena_app/src/features/home/home_screen.dart';
import 'package:okena_app/src/features/login/invite_paste_view.dart';
import 'package:okena_app/src/features/members/members_screen.dart';
import 'package:okena_app/src/features/members/invite_screen.dart';
import 'package:okena_app/src/features/mirror/mirror_screen.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_app/src/features/mural/mural_screen.dart';
import 'package:okena_app/src/features/requests/requests_screen.dart';
import 'package:okena_app/src/features/saude/saude_screen.dart';
import 'package:okena_app/src/features/storage/storage_screen.dart';
import 'package:okena_app/src/features/trash/trash_screen.dart';
import 'package:okena_app/src/routing/route_helpers.dart';
import 'package:okena_app/src/routing/shell_screens.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/upload_center.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

@immutable
final class FolderRouteTarget {
  const FolderRouteTarget({
    required this.folder,
    required this.parentLabel,
    required this.returnLocation,
  });

  final Folder folder;
  final String parentLabel;
  final String returnLocation;
}

@immutable
final class FileRouteTarget {
  const FileRouteTarget({
    required this.file,
    required this.backLabel,
    required this.returnLocation,
  });

  final FileRecord file;
  final String backLabel;
  final String returnLocation;
}

@immutable
final class UploadRouteTarget {
  const UploadRouteTarget({
    required this.backLabel,
    required this.returnLocation,
    this.request,
  });

  final UploadRequest? request;
  final String backLabel;
  final String returnLocation;
}

@immutable
final class RequestsRouteTarget {
  const RequestsRouteTarget({
    required this.backLabel,
    this.showSentState = false,
    this.sentTo,
  });

  final String backLabel;
  final bool showSentState;
  final String? sentTo;
}

/// Composes the existing feature implementations into the single route graph.
///
/// The historical function name stays for the app entry point; it no longer
/// creates or configures a tab shell.
ShellScreens buildShellScreens(
  SessionModel session, {
  MirrorRuntime? mirrorRuntime,
}) {
  const FileActions actions = PlatformFileActions();
  final PlatformMediaPicker mediaPicker = PlatformMediaPicker();

  return ShellScreens(
    home: (context, state) => HomeScreen(
      gateway: context.read<SessionGateway>(),
      onOpenFile: (file) => _openFile(
        context,
        file,
        backLabel: 'Início',
        returnLocation: AppRoutes.home,
      ),
      onOpenAccount: () => context.push(AppRoutes.account),
      onOpenDocuments: () => context.push(AppRoutes.documentsCasa),
      onOpenGallery: () => context.push(AppRoutes.galleryGrid),
      onOpenMural: () => context.push(AppRoutes.mural),
      onOpenHealth: () => context.push(AppRoutes.health),
      onOpenMembers: () => context.push(AppRoutes.members),
      onOpenStorage: () => context.push(AppRoutes.storage),
      onOpenRequests: () => context.push(
        AppRoutes.requests,
        extra: const RequestsRouteTarget(backLabel: 'Início'),
      ),
    ),
    documents: (context, state) => _filesScreen(
      context,
      state,
      actions: actions,
      mediaPicker: mediaPicker,
    ),
    trash: (context, state) => TrashScreen(
      session: context.read<SessionGateway>(),
      selectedTab: TainaDocumentTab.lixeira,
      onSelectTab: (tab) => context.pushReplacement(_documentsTabLocation(tab)),
      onBack: () => _routeBack(context, AppRoutes.home),
    ),
    folder: (context, state) {
      final FolderRouteTarget? target = state.extra is FolderRouteTarget
          ? state.extra! as FolderRouteTarget
          : null;
      return _FolderRoute(
        rkey: state.pathParameters['rkey']!,
        zone: _zone(state.uri.queryParameters['zona']),
        initialFolder: target?.folder,
        parentLabel: target?.parentLabel ?? 'Documentos',
        returnLocation:
            target?.returnLocation ??
            _zoneLocation(_zone(state.uri.queryParameters['zona'])),
        actions: actions,
        mediaPicker: mediaPicker,
      );
    },
    file: (context, state) {
      final FileRouteTarget? target = state.extra is FileRouteTarget
          ? state.extra! as FileRouteTarget
          : null;
      final FileRecord? legacyFile = state.extra is FileRecord
          ? state.extra! as FileRecord
          : null;
      return _FileRoute(
        rkey: state.pathParameters['rkey']!,
        initialFile: target?.file ?? legacyFile,
        backLabel: target?.backLabel ?? 'Documentos',
        returnLocation:
            target?.returnLocation ??
            _zoneLocation(legacyFile?.zona ?? Zona.casa),
        actions: actions,
      );
    },
    upload: (context, state) => _uploadRoute(context, state),
    gallery: (context, state) => GalleryScreen(
      gateway: context.read<SessionGateway>(),
      onShareFile: actions.share,
      initialTab: _galleryTab(state.uri.path),
      mediaPicker: mediaPicker,
      uploadCenter: context.read<UploadCenter>(),
      onNavigateTab: (tab) => context.pushReplacement(
        serviceTabLocation(
          tab == TainaGalleryTab.grade
              ? ServiceTab.galleryGrid
              : ServiceTab.galleryTimeline,
        ),
      ),
      onBack: () => _routeBack(context, AppRoutes.home),
      onOpenUpload: () => _openUpload(
        context,
        null,
        backLabel: 'Galeria',
        returnLocation: state.uri.path,
      ),
    ),
    galleryViewer: (context, state) {
      final String? rkey = state.pathParameters['rkey'];
      if (rkey == null) {
        return GalleryScreen(
          gateway: context.read<SessionGateway>(),
          onShareFile: actions.share,
        );
      }
      final TainaGalleryTab tab = _galleryTabFromViewer(state);
      return _GalleryViewerRoute(
        gateway: context.read<SessionGateway>(),
        rkey: rkey,
        tab: tab,
        onShareFile: actions.share,
        onClose: () => _routeBack(context, _galleryLocation(tab)),
      );
    },
    mural: (context, state) => MuralScreen(
      session: context.read<SessionGateway>(),
      onBack: () => _routeBack(context, AppRoutes.home),
    ),
    health: (context, state) => SaudeScreen(
      session: context.read<SessionGateway>(),
      onBack: () => _routeBack(context, AppRoutes.home),
    ),
    members: (context, state) => MembersScreen(
      session: context.read<SessionGateway>(),
      onInvite: () async {
        await context.push<void>(AppRoutes.inviteMember);
      },
    ),
    inviteMember: (context, state) =>
        MembersInviteScreen(session: context.read<SessionGateway>()),
    storage: (context, state) => StorageScreen(
      session: context.read<SessionGateway>(),
      onBack: () => _routeBack(context, AppRoutes.home),
    ),
    account: (context, state) => _accountScreen(context, session),
    requests: (context, state) {
      final RequestsRouteTarget target = state.extra is RequestsRouteTarget
          ? state.extra! as RequestsRouteTarget
          : const RequestsRouteTarget(backLabel: 'Conta');
      return RequestsScreen(
        session: context.read<SessionGateway>(),
        showSentState: target.showSentState,
        sentTo: target.sentTo,
        backLabel: target.backLabel,
        onBack: () => _routeBack(context, AppRoutes.account),
      );
    },
    privacy: (context, state) => PrivacyScreen(
      backLabel: 'Conta',
      onBack: () => _routeBack(context, AppRoutes.account),
    ),
    devices: (context, state) => DevicesScreen(
      session: context.read<SessionGateway>(),
      backLabel: 'Conta',
      onBack: () => _routeBack(context, AppRoutes.account),
    ),
    cameraRoll: mirrorRuntime == null
        ? null
        : (context, state) => MirrorScreen(
            runtime: mirrorRuntime,
            onOpenStorage: () => context.push(AppRoutes.storage),
          ),
    invitePaste: (context, state) => InvitePasteView(
      session: session,
      onBack: () => _routeBack(context, AppRoutes.login),
    ),
  );
}

Widget _accountScreen(BuildContext context, SessionModel session) {
  return AccountScreen(
    session: context.read<SessionGateway>(),
    onSignOut: session.signOut,
    hostDisplay: session.host?.display,
    cleartext: session.host?.isCleartext ?? false,
    onBack: () => _routeBack(context, AppRoutes.home),
    onOpenRequests: () => context.push(
      AppRoutes.requests,
      extra: const RequestsRouteTarget(backLabel: 'Conta'),
    ),
    onOpenPrivacy: () => context.push(AppRoutes.privacy),
    onOpenInvite: () => context.push(AppRoutes.inviteMember),
    onOpenDevices: () => context.push(AppRoutes.devices),
    onOpenCameraRoll: () => context.push(AppRoutes.cameraRoll),
  );
}

Widget _filesScreen(
  BuildContext context,
  GoRouterState state, {
  required FileActions actions,
  required PlatformMediaPicker mediaPicker,
}) {
  final TainaDocumentTab selected = _documentTab(state.uri.path);
  return FilesScreen(
    session: context.read<SessionGateway>(),
    actions: actions,
    mediaPicker: mediaPicker,
    title: 'Documentos',
    selectedTab: selected,
    onSelectTab: (tab) => context.pushReplacement(_documentsTabLocation(tab)),
    onBack: () => _routeBack(context, AppRoutes.home),
    onOpenFolder: (folder) => _openFolder(
      context,
      folder,
      parentLabel: 'Documentos',
      returnLocation: _documentsTabLocation(selected),
    ),
    onOpenFile: (file) => _openFile(
      context,
      file,
      backLabel: 'Documentos',
      returnLocation: _documentsTabLocation(selected),
    ),
    onOpenTrash: () => context.pushReplacement(AppRoutes.documentsTrash),
    uploadCenter: context.read<UploadCenter>(),
    onOpenUpload: (request) => _openUpload(
      context,
      request,
      backLabel: 'Documentos',
      returnLocation: state.uri.path,
    ),
  );
}

TainaDocumentTab _documentTab(String path) {
  if (path == AppRoutes.documentsCasa) return TainaDocumentTab.casa;
  if (path == AppRoutes.documentsTrash) return TainaDocumentTab.lixeira;
  return TainaDocumentTab.praca;
}

String _documentsTabLocation(TainaDocumentTab tab) =>
    serviceTabLocation(switch (tab) {
      TainaDocumentTab.praca => ServiceTab.documentsPraca,
      TainaDocumentTab.casa => ServiceTab.documentsCasa,
      TainaDocumentTab.lixeira => ServiceTab.documentsTrash,
    });

String _zoneLocation(Zona zone) =>
    zone == Zona.casa ? AppRoutes.documentsCasa : AppRoutes.documentsPraca;

TainaGalleryTab _galleryTab(String path) => path == AppRoutes.galleryTimeline
    ? TainaGalleryTab.linha
    : TainaGalleryTab.grade;

TainaGalleryTab _galleryTabFromViewer(GoRouterState state) =>
    state.uri.queryParameters['tab'] == 'linha'
    ? TainaGalleryTab.linha
    : TainaGalleryTab.grade;

String _galleryLocation(TainaGalleryTab tab) => tab == TainaGalleryTab.linha
    ? AppRoutes.galleryTimeline
    : AppRoutes.galleryGrid;

void _routeBack(BuildContext context, String fallbackLocation) {
  final GoRouter router = GoRouter.of(context);
  if (router.canPop()) {
    context.pop();
  } else {
    context.go(fallbackLocation);
  }
}

void _openUpload(
  BuildContext context,
  UploadRequest? request, {
  required String backLabel,
  required String returnLocation,
}) {
  context.push(
    AppRoutes.documentsUpload,
    extra: UploadRouteTarget(
      request: request,
      backLabel: backLabel,
      returnLocation: returnLocation,
    ),
  );
}

Widget _uploadRoute(BuildContext context, GoRouterState state) {
  final UploadCenter center = context.read<UploadCenter>();
  final UploadRouteTarget? target = state.extra is UploadRouteTarget
      ? state.extra! as UploadRouteTarget
      : null;
  final UploadRequest? request =
      target?.request ?? _activeUploadRequest(center);
  if (request == null) {
    return Scaffold(
      body: Center(
        child: EmptyStateView(
          icon: TainaIcon.upload,
          title: 'Nenhum envio em andamento',
          body: 'Escolha um arquivo em Documentos ou na Galeria para enviar.',
          actionLabel: 'Voltar para Documentos',
          onAction: () => context.go(AppRoutes.documentsCasa),
        ),
      ),
    );
  }
  return EnviarScreen(
    center: center,
    request: request,
    backLabel: target?.backLabel ?? 'Documentos',
    onBack: () =>
        _routeBack(context, target?.returnLocation ?? AppRoutes.documentsCasa),
    onViewSpace: () => context.push(AppRoutes.storage),
  );
}

UploadRequest? _activeUploadRequest(UploadCenter center) =>
    switch (center.state) {
      UploadUploading(:final request) ||
      UploadSucceeded(:final request) ||
      UploadFailed(:final request, error: _) => request,
      UploadIdle() => null,
    };

final class _GalleryViewerRoute extends StatefulWidget {
  const _GalleryViewerRoute({
    required this.gateway,
    required this.rkey,
    required this.tab,
    required this.onClose,
    this.onShareFile,
  });

  final SessionGateway gateway;
  final String rkey;
  final TainaGalleryTab tab;
  final GalleryShareFile? onShareFile;
  final VoidCallback onClose;

  @override
  State<_GalleryViewerRoute> createState() => _GalleryViewerRouteState();
}

final class _GalleryViewerRouteState extends State<_GalleryViewerRoute> {
  late final GalleryModel _model = GalleryModel(
    widget.gateway,
    initialTab: switch (widget.tab) {
      TainaGalleryTab.grade => GalleryTab.grid,
      TainaGalleryTab.linha => GalleryTab.timeline,
    },
  );
  bool _opening = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (mounted && !_opening) setState(() => _opening = true);
    if (_model.error != null) await _model.refresh();
    if (_model.alertMessage != null) _model.dismissAlert();
    final bool opened = await _model.openRkey(widget.rkey);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened && _model.alertMessage != null) {
      _model.dismissAlert();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_opening) {
      return const Scaffold(
        backgroundColor: TainaPalette.bgViewer,
        body: SafeArea(child: TainaLoadingList(itemCount: 1)),
      );
    }
    if (_model.viewer != null) {
      return GalleryViewerScreen(
        model: _model,
        gateway: widget.gateway,
        onShareFile: widget.onShareFile,
        onClose: widget.onClose,
      );
    }

    return Scaffold(
      backgroundColor: TainaPalette.bgViewer,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(TainaSpacing.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ErrorCard(
                  title: 'Não conseguimos abrir esta foto.',
                  body:
                      _model.error?.message ??
                      _model.alertMessage ??
                      'Esta foto não está na Galeria.',
                  retry: () => unawaited(_open()),
                ),
                const SizedBox(height: TainaSpacing.space3),
                TainaButton(
                  title: 'Voltar para a Galeria',
                  icon: TainaIcon.chevL,
                  kind: TainaButtonKind.ghost,
                  action: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _openFolder(
  BuildContext context,
  Folder folder, {
  required String parentLabel,
  required String returnLocation,
}) {
  context.push(
    AppRoutes.folder(folder.rkey, folder.zona),
    extra: FolderRouteTarget(
      folder: folder,
      parentLabel: parentAwareBackLabel(
        parentIsHub: false,
        parentName: parentLabel,
      ),
      returnLocation: returnLocation,
    ),
  );
}

void _openFile(
  BuildContext context,
  FileRecord file, {
  required String backLabel,
  required String returnLocation,
}) {
  context.push(
    AppRoutes.file(file.rkey),
    extra: FileRouteTarget(
      file: file,
      backLabel: parentAwareBackLabel(
        parentIsHub: false,
        parentName: backLabel,
      ),
      returnLocation: returnLocation,
    ),
  );
}

Zona _zone(String? zone) => zone == 'casa' ? Zona.casa : Zona.praca;

final class _FolderRoute extends StatefulWidget {
  const _FolderRoute({
    required this.rkey,
    required this.zone,
    required this.actions,
    required this.mediaPicker,
    required this.parentLabel,
    required this.returnLocation,
    this.initialFolder,
  });

  final String rkey;
  final Zona zone;
  final FileActions actions;
  final PlatformMediaPicker mediaPicker;
  final String parentLabel;
  final String returnLocation;
  final Folder? initialFolder;

  @override
  State<_FolderRoute> createState() => _FolderRouteState();
}

final class _FolderRouteState extends State<_FolderRoute> {
  late Future<TainaResult<Folder>> _folder = _load();

  Future<TainaResult<Folder>> _load() async {
    final Folder? initial = widget.initialFolder;
    if (initial != null && initial.rkey == widget.rkey) {
      return Ok<Folder>(initial);
    }
    final SessionGateway gateway = context.read<SessionGateway>();
    return gateway.screen(await gateway.api.folder(rkey: widget.rkey));
  }

  @override
  void didUpdateWidget(_FolderRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rkey != widget.rkey ||
        oldWidget.initialFolder != widget.initialFolder) {
      _folder = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.parentLabel.isNotEmpty);
    return FutureBuilder<TainaResult<Folder>>(
      future: _folder,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: TainaLoadingList());
        }
        return switch (snapshot.data!) {
          Ok<Folder>(:final value) => FolderScreen(
            session: context.read<SessionGateway>(),
            actions: widget.actions,
            folder: value,
            selectedTab: widget.zone == Zona.casa
                ? TainaDocumentTab.casa
                : TainaDocumentTab.praca,
            onSelectTab: (tab) =>
                context.pushReplacement(_documentsTabLocation(tab)),
            onBack: () => _routeBack(context, widget.returnLocation),
            onOpenFolder: (folder) => _openFolder(
              context,
              folder,
              parentLabel: value.name,
              returnLocation: AppRoutes.folder(value.rkey, value.zona),
            ),
            onOpenFile: (file) => _openFile(
              context,
              file,
              backLabel: value.name,
              returnLocation: AppRoutes.folder(value.rkey, value.zona),
            ),
            onOpenTrash: () =>
                context.pushReplacement(AppRoutes.documentsTrash),
            uploadCenter: context.read<UploadCenter>(),
            onOpenUpload: (request) => _openUpload(
              context,
              request,
              backLabel: value.name,
              returnLocation: AppRoutes.folder(value.rkey, value.zona),
            ),
            onDeleted: () =>
                context.pushReplacement(_zoneLocation(widget.zone)),
          ),
          Err<Folder>(:final error) => Scaffold(
            body: SafeArea(
              child: TainaErrorState(
                error: error,
                onRetry: () async {
                  setState(() => _folder = _load());
                  await _folder;
                },
              ),
            ),
          ),
        };
      },
    );
  }
}

final class _FileRoute extends StatefulWidget {
  const _FileRoute({
    required this.rkey,
    required this.actions,
    required this.backLabel,
    required this.returnLocation,
    this.initialFile,
  });

  final String rkey;
  final FileActions actions;
  final String backLabel;
  final String returnLocation;
  final FileRecord? initialFile;

  @override
  State<_FileRoute> createState() => _FileRouteState();
}

final class _FileRouteState extends State<_FileRoute> {
  late Future<TainaResult<FileRecord>> _file = _load();

  Future<TainaResult<FileRecord>> _load() async {
    final FileRecord? initial = widget.initialFile;
    if (initial != null && initial.rkey == widget.rkey) {
      return Ok<FileRecord>(initial);
    }
    final SessionGateway gateway = context.read<SessionGateway>();
    return gateway.screen(await gateway.api.file(rkey: widget.rkey));
  }

  @override
  void didUpdateWidget(_FileRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rkey != widget.rkey ||
        oldWidget.initialFile != widget.initialFile) {
      _file = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TainaResult<FileRecord>>(
      future: _file,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: TainaLoadingList());
        }
        return switch (snapshot.data!) {
          Ok<FileRecord>(:final value) => FileDetailScreen(
            session: context.read<SessionGateway>(),
            actions: widget.actions,
            file: value,
            backLabel: widget.backLabel,
            onBack: () => _routeBack(context, widget.returnLocation),
            onRequested: () => context.push(
              AppRoutes.requests,
              extra: RequestsRouteTarget(
                backLabel: parentAwareBackLabel(
                  parentIsHub: false,
                  parentName: value.name,
                ),
                showSentState: true,
              ),
            ),
          ),
          Err<FileRecord>(:final error) => Scaffold(
            body: SafeArea(
              child: TainaErrorState(
                error: error,
                onRetry: () async {
                  setState(() => _file = _load());
                  await _file;
                },
              ),
            ),
          ),
        };
      },
    );
  }
}
