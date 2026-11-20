import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/requests/requests_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// One newest-first feed of incoming requests, sent requests and access this
/// person has given.
final class RequestsScreen extends StatefulWidget {
  const RequestsScreen({
    required this.session,
    this.onBack,
    this.backLabel = 'Início',
    this.showSentState = false,
    this.sentTo,
    super.key,
  });

  final SessionGateway session;
  final VoidCallback? onBack;
  final String backLabel;

  /// Set when the screen is opened immediately after an access request was
  /// sent from a file the person cannot read.
  final bool showSentState;
  final String? sentTo;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

final class _RequestsScreenState extends State<RequestsScreen> {
  late final RequestsModel _model;

  @override
  void initState() {
    super.initState();
    _model = RequestsModel(gateway: widget.session);
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RequestsModel>.value(
      value: _model,
      child: _RequestsView(
        onBack: widget.onBack,
        backLabel: widget.backLabel,
        showSentState: widget.showSentState,
        sentTo: widget.sentTo,
      ),
    );
  }
}

final class _RequestsView extends StatelessWidget {
  const _RequestsView({
    required this.onBack,
    required this.backLabel,
    required this.showSentState,
    required this.sentTo,
  });

  final VoidCallback? onBack;
  final String backLabel;
  final bool showSentState;
  final String? sentTo;

  @override
  Widget build(BuildContext context) {
    final RequestsModel model = context.watch<RequestsModel>();
    final List<RequestFeedItem> items = model.items;
    final bool initialLoading = model.loading && items.isEmpty;
    final TainaError? error = model.error;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: model.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              PageHeaderSliver(
                title: 'Pedidos',
                backLabel: backLabel,
                onBack: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              if (showSentState)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    TainaSpacing.space4,
                    TainaSpacing.space2,
                    TainaSpacing.space4,
                    TainaSpacing.space3,
                  ),
                  sliver: SliverToBoxAdapter(child: _sentCard(sentTo)),
                ),
              if (error != null && items.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    TainaSpacing.space4,
                    TainaSpacing.space2,
                    TainaSpacing.space4,
                    TainaSpacing.space3,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: ErrorCard(
                      title: 'Não conseguimos atualizar os pedidos.',
                      body: error.message,
                      retry: model.load,
                    ),
                  ),
                ),
              if (initialLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.all(TainaSpacing.space4),
                    child: SkeletonView(
                      kind: TainaSkeletonKind.listRow,
                      count: 3,
                    ),
                  ),
                )
              else if (error != null && items.isEmpty && !showSentState)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(TainaSpacing.space4),
                    child: ErrorCard(
                      title: 'Não conseguimos carregar os pedidos.',
                      body: error.message,
                      retry: model.load,
                    ),
                  ),
                )
              else if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: error != null
                        ? ErrorCard(
                            title: 'Não conseguimos carregar os pedidos.',
                            body: error.message,
                            retry: model.load,
                          )
                        : const EmptyStateView(
                            icon: TainaIcon.folder,
                            title: 'Nenhum pedido ainda',
                            body:
                                'Quando alguém pedir para abrir um arquivo da '
                                'sua casa, aparece aqui.',
                          ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(top: TainaSpacing.space1),
                  sliver: SliverList.builder(
                    itemCount: items.length + 1,
                    itemBuilder: (BuildContext context, int index) {
                      if (index == items.length) return _footer();
                      final RequestFeedItem item = items[index];
                      return _requestRow(context, model, item);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sentCard(String? owner) {
    final String decisionMaker = owner ?? 'Quem guarda o arquivo';
    return TainaCard(
      kind: TainaCardKind.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pedido enviado',
            style: TainaTypography.h3.copyWith(color: TainaPalette.textPrimary),
          ),
          const SizedBox(height: TainaSpacing.space2),
          Text(
            '$decisionMaker vai decidir. Você vê a resposta aqui em Pedidos.',
            style: TainaTypography.bodySm.copyWith(
              color: TainaPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestRow(
    BuildContext context,
    RequestsModel model,
    RequestFeedItem item,
  ) {
    final bool deciding =
        item.pedido != null && model.deciding == item.pedido!.publicId;
    final bool revoking =
        item.grant != null && model.revoking == item.grant!.publicId;

    return TainaListRow(
      kind: TainaListRowKind.pedido,
      title: item.title,
      meta: item.meta,
      state: item.state,
      stateSummary: item.stateSummary,
      trailing: item.canRevoke
          ? TainaListRowTrailing.kebab
          : TainaListRowTrailing.none,
      trailingLabel: 'Mais ações',
      onTrailingPressed: item.canRevoke && !revoking
          ? () => unawaited(_openGrantActions(context, model, item))
          : null,
      actionsBuilder: item.canDecide
          ? (BuildContext rowContext) =>
                _decisionActions(context, model, item, deciding: deciding)
          : item.state == TainaPedidoState.esperando
          ? (_) => StatusLine(
              state: TainaStatusState.attention,
              title: item.stateSummary ?? 'Aguardando resposta',
            )
          : null,
    );
  }

  Widget _decisionActions(
    BuildContext context,
    RequestsModel model,
    RequestFeedItem item, {
    required bool deciding,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TainaButton(
          title: 'Recusar',
          kind: TainaButtonKind.secondary,
          size: TainaButtonSize.sm,
          action: deciding
              ? null
              : () => unawaited(_deny(context, model, item)),
        ),
        const SizedBox(width: TainaSpacing.space2),
        TainaButton(
          title: 'Dar acesso',
          kind: TainaButtonKind.primary,
          size: TainaButtonSize.sm,
          loading: deciding,
          action: deciding
              ? null
              : () => unawaited(_approve(context, model, item)),
        ),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TainaSpacing.space4,
        TainaSpacing.space4,
        TainaSpacing.space4,
        TainaSpacing.space6,
      ),
      child: Text(
        'Os pedidos resolvidos ficam visíveis. Você pode mudar de ideia '
        'quando quiser.',
        style: TainaTypography.caption.copyWith(color: TainaPalette.textMuted),
      ),
    );
  }

  Future<void> _approve(
    BuildContext context,
    RequestsModel model,
    RequestFeedItem item,
  ) async {
    final String name = item.resourceName;
    final TainaResult<void> result = await model.approve(item.pedido!.publicId);
    if (!context.mounted) return;
    _showResult(
      context,
      result,
      success: name == RequestsModel.deletedResource
          ? 'A pessoa já pode abrir o arquivo.'
          : RequestsModel.approvedMessage(name),
    );
  }

  Future<void> _deny(
    BuildContext context,
    RequestsModel model,
    RequestFeedItem item,
  ) async {
    final TainaResult<void> result = await model.deny(item.pedido!.publicId);
    if (!context.mounted) return;
    _showResult(
      context,
      result,
      success: 'A pessoa pode pedir de novo quando quiser.',
    );
  }

  Future<void> _openGrantActions(
    BuildContext context,
    RequestsModel model,
    RequestFeedItem item,
  ) async {
    await ActionsMenu.show(
      context: context,
      title: 'Ações do pedido',
      actions: [
        TainaMenuAction(
          label: 'Tirar acesso',
          icon: TainaIcon.trash,
          destructive: true,
          onSelected: () => unawaited(_confirmRevoke(context, model, item)),
        ),
      ],
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    RequestsModel model,
    RequestFeedItem item,
  ) async {
    final Concessao grant = item.grant!;
    final String person = RequestsModel.personLabel(grant.leitor);
    final String resource = item.resourceName;
    final bool? confirmed = await TainaDialog.destructive(
      context: context,
      title: 'Tirar este acesso?',
      message:
          '$person deixa de poder abrir $resource. A pessoa pode pedir de novo '
          'depois.',
      confirmLabel: 'Tirar acesso',
      useRootNavigator: false,
    );
    if (confirmed != true || !context.mounted) return;
    final TainaResult<void> result = await model.revoke(grant.publicId);
    if (!context.mounted) return;
    _showResult(
      context,
      result,
      success: RequestsModel.revokedMessage(resource),
    );
  }

  void _showResult(
    BuildContext context,
    TainaResult<void> result, {
    required String success,
  }) {
    final (TainaToastKind kind, String message) = switch (result) {
      Ok() => (TainaToastKind.info, success),
      Err(:final error) => (TainaToastKind.error, error.message),
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          content: TainaToast(kind: kind, text: message),
        ),
      );
  }
}
