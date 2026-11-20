import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import 'home_model.dart';

typedef HomeOpenFile = void Function(FileRecord file);
typedef HomeOpenDestination = void Function();

/// The community hub. It reads live session and service data, and delegates
/// every transition to the route composition supplied by the app.
final class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.gateway,
    this.onOpenFile,
    this.onOpenAccount,
    this.onOpenDocuments,
    this.onOpenGallery,
    this.onOpenMural,
    this.onOpenHealth,
    this.onOpenMembers,
    this.onOpenStorage,
    this.onOpenRequests,
    this.clock = DateTime.now,
    super.key,
  });

  final SessionGateway gateway;
  final HomeOpenFile? onOpenFile;
  final HomeOpenDestination? onOpenAccount;
  final HomeOpenDestination? onOpenDocuments;
  final HomeOpenDestination? onOpenGallery;
  final HomeOpenDestination? onOpenMural;
  final HomeOpenDestination? onOpenHealth;
  final HomeOpenDestination? onOpenMembers;
  final HomeOpenDestination? onOpenStorage;
  final HomeOpenDestination? onOpenRequests;
  final DateTime Function() clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends State<HomeScreen> {
  late final HomeModel _model = HomeModel(widget.gateway);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_model.load());
    });
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HomeModel>.value(
      value: _model,
      child: Scaffold(
        backgroundColor: TainaPalette.bgApp,
        body: SafeArea(
          child: Consumer<HomeModel>(
            builder: (context, model, child) {
              final bool showAccount =
                  model.userName != null && widget.onOpenAccount != null;
              return RefreshIndicator(
                onRefresh: model.load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HubHeader(
                        greeting: HomeModel.greeting(
                          widget.clock().hour,
                          name: model.userName,
                        ),
                        communityName: model.communityName,
                        userName: showAccount ? model.userName : null,
                        onAccount: showAccount ? widget.onOpenAccount : null,
                        careLine: _careLine(model),
                      ),
                      if (model.requestsError != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: TainaSpacing.space4,
                          ),
                          child: _errorCard(
                            onRetry: model.load,
                            onContact: widget.onOpenMembers,
                          ),
                        ),
                        const SizedBox(height: TainaSpacing.space4),
                      ],
                      if (!model.loaded)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: TainaSpacing.space4,
                          ),
                          child: TainaLoadingList(itemCount: 3),
                        )
                      else ...[
                        _serviceSection(),
                        const SizedBox(height: TainaSpacing.space5),
                        _communitySection(model),
                        const SizedBox(height: TainaSpacing.space5),
                        _storageSection(model),
                        const SizedBox(height: TainaSpacing.space5),
                        _recentSection(model),
                        const SizedBox(height: TainaSpacing.space5),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget? _careLine(HomeModel model) {
    final String? text = HomeModel.careLine(
      count: model.pendingRequests,
      firstRequester: model.firstPendingName,
    );
    if (text == null) return null;
    return CareLine(
      text: text,
      actionLabel: 'Responder',
      action: widget.onOpenRequests ?? () {},
    );
  }

  Widget _serviceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Serviços'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ServiceCard(
                  service: ServiceCardService.ybira,
                  title: 'Documentos',
                  body: 'Arquivos da casa e da praça',
                  onTap: widget.onOpenDocuments,
                ),
              ),
              const SizedBox(width: TainaSpacing.space3),
              Expanded(
                child: ServiceCard(
                  service: ServiceCardService.jaci,
                  title: 'Galeria',
                  body: 'Fotos da casa e da praça',
                  onTap: widget.onOpenGallery,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _communitySection(HomeModel model) {
    final String muralMeta = model.muralError != null
        ? ''
        : model.mural.isEmpty
        ? 'Sem registros no mural'
        : HomeModel.muralMeta(model.mural.first);
    final String healthMeta = model.healthSummary ?? '';
    final String membersMeta = model.activeMembers == null
        ? ''
        : HomeModel.memberCountLabel(model.activeMembers!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Da comunidade'),
        if (model.muralError != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TainaSpacing.space4,
            ),
            child: _errorCard(
              onRetry: model.load,
              onContact: widget.onOpenMembers,
            ),
          )
        else
          TainaListRow(
            kind: TainaListRowKind.civic,
            title: 'Mural',
            meta: muralMeta,
            trailing: TainaListRowTrailing.chevron,
            leadingBuilder: (context) =>
                const ServiceSquare(mark: TainaServiceMark.mural),
            onTap: widget.onOpenMural,
          ),
        if (model.healthError != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TainaSpacing.space4,
            ),
            child: _errorCard(
              onRetry: model.load,
              onContact: widget.onOpenMembers,
            ),
          )
        else
          TainaListRow(
            kind: TainaListRowKind.civic,
            title: 'Saúde da comunidade',
            meta: healthMeta,
            trailing: TainaListRowTrailing.chevron,
            leadingBuilder: (context) =>
                const ServiceSquare(mark: TainaServiceMark.saude),
            onTap: widget.onOpenHealth,
          ),
        if (model.membersError != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TainaSpacing.space4,
            ),
            child: _errorCard(
              onRetry: model.load,
              onContact: widget.onOpenMembers,
            ),
          )
        else
          TainaListRow(
            kind: TainaListRowKind.civic,
            title: 'Moradores',
            meta: membersMeta,
            trailing: TainaListRowTrailing.chevron,
            leadingBuilder: (context) =>
                const ServiceSquare(mark: TainaServiceMark.moradores),
            onTap: widget.onOpenMembers,
            showDivider: false,
          ),
      ],
    );
  }

  Widget _storageSection(HomeModel model) {
    if (model.statsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
        child: _errorCard(
          onRetry: model.retryStorage,
          onContact: widget.onOpenMembers,
        ),
      );
    }
    final StorageStats? stats = model.stats;
    if (stats == null) return const SizedBox.shrink();
    final bool warning = HomeModel.storageLow(stats);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
      child: StorageCard(
        summary: HomeModel.storageSummary(stats),
        tone: warning ? TainaStorageTone.warning : TainaStorageTone.normal,
        onAction: widget.onOpenStorage,
      ),
    );
  }

  Widget _recentSection(HomeModel model) {
    final Widget content;
    if (model.recentError != null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
        child: _errorCard(onRetry: model.load, onContact: widget.onOpenMembers),
      );
    } else if (model.recent.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space4),
        child: EmptyStateView(
          icon: TainaIcon.folder,
          title: 'Nada recente',
          body: 'O que chegar de novo aparece aqui.',
          actionLabel: 'Enviar arquivos',
          onAction: widget.onOpenDocuments,
        ),
      );
    } else {
      content = Column(
        children: [
          for (int index = 0; index < model.recent.length; index++)
            TainaListRow(
              kind: TainaListRowKind.file,
              title: model.recent[index].name,
              meta: HomeModel.recentMeta(
                model.recent[index],
                now: widget.clock(),
              ),
              trailing: TainaListRowTrailing.chevron,
              onTap: widget.onOpenFile == null
                  ? null
                  : () => widget.onOpenFile!(model.recent[index]),
              showDivider: index != model.recent.length - 1,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_sectionTitle('Recentes'), content],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TainaSpacing.space4,
        0,
        TainaSpacing.space4,
        TainaSpacing.space3,
      ),
      child: TainaText(
        title,
        style: TainaTypography.overline,
        uppercase: true,
        color: TainaPalette.textMuted,
      ),
    );
  }

  Widget _errorCard({
    required Future<void> Function() onRetry,
    HomeOpenDestination? onContact,
  }) {
    return ErrorCard(
      title: 'Não conseguimos falar com a nuvem agora.',
      body: '',
      retry: () => unawaited(onRetry()),
      contact: onContact,
    );
  }
}
