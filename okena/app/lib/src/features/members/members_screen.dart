import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/members/invite_screen.dart';
import 'package:okena_app/src/features/members/members_clipboard.dart';
import 'package:okena_app/src/features/members/members_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The community's people, with zelador actions when the current person cares
/// for the box.
final class MembersScreen extends StatefulWidget {
  const MembersScreen({
    required this.session,
    this.onInvite,
    this.clipboard,
    super.key,
  });

  final SessionGateway session;
  final Future<void> Function()? onInvite;
  final MembersClipboard? clipboard;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

final class _MembersScreenState extends State<MembersScreen> {
  late final MembersModel _model = MembersModel(gateway: widget.session);
  late final MembersClipboard _clipboard =
      widget.clipboard ?? const PlatformMembersClipboard();

  @override
  void initState() {
    super.initState();
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (BuildContext context, Widget? child) {
        return _MembersView(
          model: _model,
          clipboard: _clipboard,
          onInvite: widget.onInvite,
        );
      },
    );
  }
}

final class _MembersView extends StatefulWidget {
  const _MembersView({
    required this.model,
    required this.clipboard,
    required this.onInvite,
  });

  final MembersModel model;
  final MembersClipboard clipboard;
  final Future<void> Function()? onInvite;

  @override
  State<_MembersView> createState() => _MembersViewState();
}

final class _MembersViewState extends State<_MembersView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MembersModel model = widget.model;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              title: 'Moradores',
              backLabel: 'Início',
              onBack: () => Navigator.of(context).maybePop(),
              action: model.isZelador
                  ? TainaButton(
                      title: 'Convidar',
                      size: TainaButtonSize.sm,
                      kind: TainaButtonKind.ghost,
                      action: () => unawaited(_openInvite()),
                    )
                  : null,
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final MembersModel model = widget.model;
    final TainaError? error = model.error;
    if (model.members.isEmpty && model.loading) {
      return const TainaLoadingList(itemCount: 5);
    }
    if (model.members.isEmpty && error != null) {
      return TainaErrorState(error: error, onRetry: model.load);
    }

    final List<Ava> filtered = MembersModel.filterByName(model.members, _query);
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          TainaSpacing.space4,
          TainaSpacing.space2,
          TainaSpacing.space4,
          TainaSpacing.space6,
        ),
        children: [
          TainaField(
            label: 'Buscar pessoa',
            kind: TainaFieldKind.search,
            help: 'Busque pelo nome.',
            controller: _searchController,
            onChanged: (String value) => setState(() => _query = value),
          ),
          if (model.error case final TainaError error) ...[
            const SizedBox(height: TainaSpacing.space3),
            TainaToast(kind: TainaToastKind.error, text: error.message),
          ],
          const SizedBox(height: TainaSpacing.space3),
          if (model.members.isEmpty)
            const TainaEmptyState(
              icon: TainaIcon.moradores,
              title: 'Ninguém por aqui',
              message: 'A comunidade ainda não tem moradores.',
            )
          else if (filtered.isEmpty)
            const TainaEmptyState(
              icon: TainaIcon.search,
              title: 'Ninguém com esse nome',
              message: 'Confira a escrita ou procure por outro nome.',
            )
          else
            for (final Ava member in filtered)
              TainaListRow(
                kind: TainaListRowKind.person,
                title: member.label,
                meta: MembersModel.metaFor(member),
                leadingBuilder: (BuildContext context) => TainaAvatar(
                  name: member.label,
                  off: member.deactivatedAt != null,
                ),
                trailing: _hasActions(model, member)
                    ? TainaListRowTrailing.kebab
                    : TainaListRowTrailing.none,
                trailingLabel: _hasActions(model, member)
                    ? 'Ações para ${member.label}'
                    : null,
                onTrailingPressed: _hasActions(model, member)
                    ? () => _showActions(context, model, member)
                    : null,
              ),
          if (model.isZelador) ...[
            const SizedBox(height: TainaSpacing.space5),
            const TainaBadge(kind: TainaBadgeKind.zelador),
            const SizedBox(height: TainaSpacing.space2),
            Text(
              'Quem cuida da nuvem só convida pessoas. Ninguém pode mexer '
              'nos arquivos de outra pessoa.',
              style: TainaTypography.caption.copyWith(
                color: TainaPalette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasActions(MembersModel model, Ava member) {
    return model.isZelador && member.publicId != model.mePublicId;
  }

  Future<void> _openInvite() async {
    final MembersModel model = widget.model;
    if (widget.onInvite != null) {
      await widget.onInvite!();
    } else {
      await Navigator.of(context).push<MemberInvite>(
        MaterialPageRoute<MemberInvite>(
          builder: (BuildContext context) => MembersInviteScreen(
            session: model.gateway,
            clipboard: widget.clipboard,
          ),
        ),
      );
    }
    if (mounted) await model.load();
  }

  void _showActions(BuildContext context, MembersModel model, Ava member) {
    final bool pending = MembersModel.isPendingInvite(member);
    ActionsMenu.show(
      context: context,
      title: member.label,
      actions: [
        if (pending)
          TainaMenuAction(
            label: 'Cancelar convite',
            icon: TainaIcon.trash,
            destructive: true,
            onSelected: () => unawaited(_cancelInvite(context, model, member)),
          )
        else
          TainaMenuAction(
            label: 'Gerar link de redefinição de senha',
            icon: TainaIcon.restore,
            onSelected: () =>
                unawaited(_generateResetLink(context, model, member)),
          ),
      ],
    );
  }

  Future<void> _generateResetLink(
    BuildContext context,
    MembersModel model,
    Ava member,
  ) async {
    final TainaResult<ResetLink> result = await model.resetLink(
      member.publicId,
    );
    if (!context.mounted) return;
    switch (result) {
      case Ok(:final value):
        await TainaSheet.show<void>(
          context: context,
          title: 'Link de redefinição de senha',
          isScrollControlled: true,
          child: _ResetLinkContent(
            resetLink: value,
            clipboard: widget.clipboard,
          ),
        );
      case Err(:final error):
        await _showFailure(context, error);
    }
  }

  Future<void> _cancelInvite(
    BuildContext context,
    MembersModel model,
    Ava member,
  ) async {
    final bool confirmed = await _confirmCancelInvite(context);
    if (!confirmed || !context.mounted) return;

    final TainaResult<void> result = await model.revokeInvite(member.publicId);
    if (!context.mounted) return;
    if (result case Err(:final error)) {
      await _showFailure(context, error);
    }
  }

  Future<bool> _confirmCancelInvite(BuildContext context) async {
    final bool? confirmed = await TainaSheet.show<bool>(
      context: context,
      title: 'Cancelar convite?',
      isScrollControlled: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'O link para de valer. A pessoa vai precisar de um novo convite.',
            style: TainaTypography.bodySm.copyWith(
              color: TainaPalette.textSecondary,
            ),
          ),
          const SizedBox(height: TainaSpacing.space4),
          TainaButton(
            title: 'Cancelar convite',
            kind: TainaButtonKind.danger,
            size: TainaButtonSize.md,
            action: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: TainaSpacing.space2),
          TainaButton(
            title: 'Voltar',
            kind: TainaButtonKind.secondary,
            size: TainaButtonSize.md,
            action: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _showFailure(BuildContext context, TainaError error) {
    return TainaSheet.show<void>(
      context: context,
      title: 'Não deu certo',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            error.message,
            style: TainaTypography.bodySm.copyWith(
              color: TainaPalette.textSecondary,
            ),
          ),
          const SizedBox(height: TainaSpacing.space4),
          TainaButton(
            title: 'Entendi',
            size: TainaButtonSize.md,
            action: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

final class _ResetLinkContent extends StatefulWidget {
  const _ResetLinkContent({required this.resetLink, required this.clipboard});

  final ResetLink resetLink;
  final MembersClipboard? clipboard;

  @override
  State<_ResetLinkContent> createState() => _ResetLinkContentState();
}

final class _ResetLinkContentState extends State<_ResetLinkContent> {
  late final MembersClipboard _clipboard =
      widget.clipboard ?? const PlatformMembersClipboard();
  bool _copied = false;
  bool _copyFailed = false;

  @override
  Widget build(BuildContext context) {
    final ResetLink link = widget.resetLink;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Envie este link para ${link.ava.label}. A pessoa escolhe uma senha '
          'nova e entra de novo. O link vale uma vez só.',
          style: TainaTypography.bodySm.copyWith(
            color: TainaPalette.textSecondary,
          ),
        ),
        const SizedBox(height: TainaSpacing.space3),
        TainaCard(
          child: SelectableText(
            link.webUrl?.trim().isNotEmpty == true
                ? link.webUrl!.trim()
                : link.resetUrl,
            style: TainaTypography.monoSm.copyWith(
              color: TainaPalette.textPrimary,
            ),
          ),
        ),
        if (_copyFailed) ...[
          const SizedBox(height: TainaSpacing.space3),
          const TainaToast(
            kind: TainaToastKind.error,
            text: 'Não foi possível copiar o link.',
          ),
        ],
        const SizedBox(height: TainaSpacing.space3),
        TainaButton(
          title: _copied ? 'Link copiado' : 'Copiar link',
          size: TainaButtonSize.md,
          action: () => unawaited(_copy()),
        ),
      ],
    );
  }

  Future<void> _copy() async {
    final ResetLink link = widget.resetLink;
    final String text = link.webUrl?.trim().isNotEmpty == true
        ? link.webUrl!.trim()
        : link.resetUrl;
    try {
      await _clipboard.writeText(text);
      if (!mounted) return;
      setState(() {
        _copied = true;
        _copyFailed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _copied = false;
        _copyFailed = true;
      });
    }
  }
}
