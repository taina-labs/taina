import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/requests/requests_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The pedidos screen: what the community asked of this person and what this
/// person asked of others, one segmented screen.
///
/// The dono decides; a decided pedido leaves the pending list and the outcome
/// is said out loud, never silent.
final class RequestsScreen extends StatefulWidget {
  const RequestsScreen({required this.session, super.key});

  final SessionGateway session;

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
      child: const _RequestsView(),
    );
  }
}

enum _RequestTab { received, sent, granted }

final class _RequestsView extends StatefulWidget {
  const _RequestsView();

  @override
  State<_RequestsView> createState() => _RequestsViewState();
}

final class _RequestsViewState extends State<_RequestsView> {
  _RequestTab _tab = _RequestTab.received;

  @override
  Widget build(BuildContext context) {
    final RequestsModel model = context.watch<RequestsModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TainaSpacing.space4,
                vertical: TainaSpacing.space3,
              ),
              child: SegmentedButton<_RequestTab>(
                segments: const [
                  ButtonSegment<_RequestTab>(
                    value: _RequestTab.received,
                    label: Text('Recebidos'),
                  ),
                  ButtonSegment<_RequestTab>(
                    value: _RequestTab.sent,
                    label: Text('Enviados'),
                  ),
                  ButtonSegment<_RequestTab>(
                    value: _RequestTab.granted,
                    label: Text('Acessos'),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (Set<_RequestTab> selection) {
                  setState(() => _tab = selection.first);
                },
              ),
            ),
            Expanded(
              child: switch (_tab) {
                _RequestTab.received => _pedidoSection(
                  context,
                  model,
                  received: true,
                ),
                _RequestTab.sent => _pedidoSection(
                  context,
                  model,
                  received: false,
                ),
                _RequestTab.granted => _grantsSection(context, model),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _pedidoSection(
    BuildContext context,
    RequestsModel model, {
    required bool received,
  }) {
    final List<Pedido> pedidos = received
        ? model.sections.received
        : model.sections.sent;
    if (pedidos.isEmpty) {
      if (model.loading) return const TainaLoadingList();
      if (model.error case final TainaError error) {
        return _refreshable(
          model,
          TainaErrorState(error: error, onRetry: model.load),
        );
      }
      return _refreshable(model, received ? _receivedEmpty : _sentEmpty);
    }
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        children: [
          if (received)
            Padding(
              padding: const EdgeInsets.only(bottom: TainaSpacing.space2),
              child: TainaText(
                RequestsModel.receivedHeader(pedidos.length),
                style: TainaTypography.overline,
                uppercase: true,
                color: TainaPalette.textMuted,
              ),
            ),
          for (final Pedido pedido in pedidos)
            Padding(
              padding: const EdgeInsets.only(bottom: TainaSpacing.space2),
              child: _PedidoRow(
                person: RequestsModel.personLabel(
                  received ? pedido.pedinte : pedido.dono,
                ),
                status: pedido.status,
                resource: RequestsModel.resourceLine(
                  received: received,
                  name: RequestsModel.resourceNameForPedido(
                    pedido,
                    received ? model.receivedNames : model.sentNames,
                  ),
                ),
                motivo: pedido.motivo,
                date: TainaFormat.relative(
                  pedido.decididoEm ?? pedido.createdAt,
                ),
                deciding: model.deciding == pedido.publicId,
                onApprove: received
                    ? () => unawaited(_approve(context, model, pedido))
                    : null,
                onDeny: received
                    ? () => unawaited(_deny(context, model, pedido))
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _grantsSection(BuildContext context, RequestsModel model) {
    final bool empty =
        model.grants.given.isEmpty && model.grants.received.isEmpty;
    if (empty) {
      if (model.loading) return const TainaLoadingList();
      if (model.error case final TainaError error) {
        return _refreshable(
          model,
          TainaErrorState(error: error, onRetry: model.load),
        );
      }
      return _refreshable(model, _grantedEmpty);
    }
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        children: [
          _overline('Você liberou'),
          for (final Concessao concessao in model.grants.given)
            Padding(
              padding: const EdgeInsets.only(bottom: TainaSpacing.space2),
              child: _GrantRow(
                person: RequestsModel.personLabel(concessao.leitor),
                resource: RequestsModel.resourceNameForConcessao(
                  concessao,
                  model.grantNames,
                ),
                revoked: RequestsModel.isRevoked(concessao),
                date: TainaFormat.relative(
                  concessao.revogadaEm ??
                      concessao.concedidaEm ??
                      concessao.createdAt,
                ),
                revoking: model.revoking == concessao.publicId,
                onRevoke: RequestsModel.isRevoked(concessao)
                    ? null
                    : () => unawaited(_revoke(context, model, concessao)),
              ),
            ),
          if (model.grants.given.isEmpty)
            _inlineEmpty(
              'Nenhum acesso liberado por enquanto. Quando você aprovar um '
              'pedido, ele vira um acesso aqui.',
            ),
          _overline('Liberados para você'),
          for (final Concessao concessao in model.grants.received)
            Padding(
              padding: const EdgeInsets.only(bottom: TainaSpacing.space2),
              child: _GrantRow(
                person: RequestsModel.personLabel(concessao.dono),
                resource: RequestsModel.resourceNameForConcessao(
                  concessao,
                  model.grantNames,
                ),
                revoked: RequestsModel.isRevoked(concessao),
                date: TainaFormat.relative(
                  concessao.revogadaEm ??
                      concessao.concedidaEm ??
                      concessao.createdAt,
                ),
              ),
            ),
          if (model.grants.received.isEmpty)
            _inlineEmpty(
              'Nenhum ainda. Quando alguém te deixar ler um arquivo, o acesso '
              'aparece aqui.',
            ),
        ],
      ),
    );
  }

  Widget _refreshable(RequestsModel model, Widget child) {
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(TainaSpacing.space4),
        children: [child],
      ),
    );
  }

  Widget _overline(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TainaSpacing.space2),
      child: TainaText(
        title,
        style: TainaTypography.overline,
        uppercase: true,
        color: TainaPalette.textMuted,
      ),
    );
  }

  Widget _inlineEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: TainaSpacing.space4,
        top: TainaSpacing.space1,
      ),
      child: TainaText(
        message,
        style: TainaTypography.bodySm,
        color: TainaPalette.textMuted,
      ),
    );
  }

  static const TainaEmptyState _receivedEmpty = TainaEmptyState(
    icon: Icons.shield_outlined,
    title: 'Nenhum pedido por enquanto',
    message:
        'Ninguém acessa seus arquivos sem você deixar. Quando alguém pedir, '
        'aparece aqui.',
  );

  static const TainaEmptyState _sentEmpty = TainaEmptyState(
    icon: Icons.send_outlined,
    title: 'Você não pediu acesso a nada',
    message:
        'Quando você pedir para abrir um arquivo de outra pessoa, o pedido '
        'aparece aqui até ela decidir.',
  );

  static const TainaEmptyState _grantedEmpty = TainaEmptyState(
    icon: Icons.key_outlined,
    title: 'Nenhum acesso por enquanto',
    message:
        'Quando você aprovar um pedido, ele vira um acesso aqui, e você pode '
        'revogar depois. Os que você recebeu também aparecem.',
  );

  Future<void> _approve(
    BuildContext context,
    RequestsModel model,
    Pedido pedido,
  ) async {
    final String? name = model.receivedNames[pedido.recurso];
    final result = await model.approve(pedido.publicId);
    if (!context.mounted) return;
    _showOutcome(
      context,
      'Pedido aprovado',
      result,
      RequestsModel.approvedMessage(name),
    );
  }

  Future<void> _deny(
    BuildContext context,
    RequestsModel model,
    Pedido pedido,
  ) async {
    final bool confirmed = await _confirm(
      context,
      title: 'Negar este pedido?',
      primary: 'Negar',
      message:
          'A pessoa não vai poder abrir o arquivo. Ela pode pedir de novo '
          'depois.',
    );
    if (!confirmed || !context.mounted) return;
    final result = await model.deny(pedido.publicId);
    if (!context.mounted) return;
    _showOutcome(
      context,
      'Pedido negado',
      result,
      'A pessoa pode pedir de novo quando quiser.',
    );
  }

  Future<void> _revoke(
    BuildContext context,
    RequestsModel model,
    Concessao concessao,
  ) async {
    final String person = RequestsModel.personLabel(concessao.leitor);
    final String resource = RequestsModel.resourceNameForConcessao(
      concessao,
      model.grantNames,
    );
    final bool confirmed = await _confirm(
      context,
      title: 'Revogar este acesso?',
      primary: 'Revogar',
      message:
          '$person deixa de poder abrir $resource. A pessoa pode pedir de novo '
          'depois.',
    );
    if (!confirmed || !context.mounted) return;
    final result = await model.revoke(concessao.publicId);
    if (!context.mounted) return;
    _showOutcome(
      context,
      'Acesso revogado',
      result,
      RequestsModel.revokedMessage(model.grantNames[concessao.recurso]),
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String primary,
    required String message,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              primary,
              style: const TextStyle(color: TainaPalette.feedbackError),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// The one alert slot: a decision said out loud, or the failure's own pt-BR
  /// sentence.
  void _showOutcome(
    BuildContext context,
    String title,
    TainaResult<void> result,
    String success,
  ) {
    switch (result) {
      case Ok():
        _showFlash(context, title, success);
      case Err(:final error):
        _showFlash(context, 'Não deu certo', error.message);
    }
  }

  void _showFlash(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(PedidoStatus status) {
  return switch (status) {
    PedidoStatus.pendente => 'Pendente',
    PedidoStatus.aprovado => 'Aprovado',
    PedidoStatus.negado => 'Negado',
  };
}

Color _statusColor(PedidoStatus status) {
  return switch (status) {
    PedidoStatus.pendente => TainaPalette.feedbackWarning,
    PedidoStatus.aprovado => TainaPalette.feedbackSuccess,
    PedidoStatus.negado => TainaPalette.feedbackError,
  };
}

/// One pedido: the person it is about, the resource, the motivo in full
/// (deciding without the why is deciding blind), the status and the date. The
/// received, still-pending rows also carry the decision.
final class _PedidoRow extends StatelessWidget {
  const _PedidoRow({
    required this.person,
    required this.status,
    required this.resource,
    required this.motivo,
    required this.date,
    required this.deciding,
    this.onApprove,
    this.onDeny,
  });

  final String person;
  final PedidoStatus status;
  final String resource;
  final String? motivo;
  final String date;
  final bool deciding;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    final bool decides = onApprove != null || onDeny != null;
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TainaText(
                  person,
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TainaText(
                _statusLabel(status),
                style: TainaTypography.caption,
                color: _statusColor(status),
              ),
            ],
          ),
          const SizedBox(height: TainaSpacing.space2),
          TainaText(
            resource,
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
          ),
          if (motivo case final String why) ...[
            const SizedBox(height: TainaSpacing.space1),
            TainaText(
              'Motivo: $why',
              style: TainaTypography.bodySm,
              color: TainaPalette.textMuted,
            ),
          ],
          const SizedBox(height: TainaSpacing.space1),
          TainaText(
            date,
            style: TainaTypography.caption,
            color: TainaPalette.textFaint,
          ),
          if (decides) ...[
            const SizedBox(height: TainaSpacing.space2),
            Row(
              children: [
                Expanded(
                  child: TainaSecondaryButton(
                    label: 'Negar',
                    onPressed: deciding ? null : onDeny,
                  ),
                ),
                const SizedBox(width: TainaSpacing.space2),
                Expanded(
                  child: TainaPrimaryButton(
                    label: 'Aprovar',
                    loading: deciding,
                    onPressed: deciding ? null : onApprove,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One granted access: who reads what, standing or revoked, with the revoke on
/// the standing ones the caller gave. Revoking is destructive and says what
/// the person loses; the fact itself stays on the list.
final class _GrantRow extends StatelessWidget {
  const _GrantRow({
    required this.person,
    required this.resource,
    required this.revoked,
    required this.date,
    this.revoking = false,
    this.onRevoke,
  });

  final String person;
  final String resource;
  final bool revoked;
  final String date;
  final bool revoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TainaText(
                  person,
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TainaText(
                revoked ? 'Revogado' : 'Ativo',
                style: TainaTypography.caption,
                color: revoked
                    ? TainaPalette.textMuted
                    : TainaPalette.feedbackSuccess,
              ),
            ],
          ),
          const SizedBox(height: TainaSpacing.space2),
          TainaText(
            resource,
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
          ),
          const SizedBox(height: TainaSpacing.space1),
          TainaText(
            date,
            style: TainaTypography.caption,
            color: TainaPalette.textFaint,
          ),
          if (onRevoke != null) ...[
            const SizedBox(height: TainaSpacing.space2),
            TainaSecondaryButton(
              label: revoking ? 'Revogando...' : 'Revogar',
              onPressed: revoking ? null : onRevoke,
            ),
          ],
        ],
      ),
    );
  }
}
