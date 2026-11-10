import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/members/members_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The community's people, as the box lists them: zeladoras first.
///
/// Every morador reads; the acts of the zeladora live on this screen too, one
/// menu per row, so she does her work from the phone. The server enforces the
/// role again.
final class MembersScreen extends StatefulWidget {
  const MembersScreen({required this.session, super.key});

  final SessionGateway session;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

final class _MembersScreenState extends State<MembersScreen> {
  late final MembersModel _model;

  @override
  void initState() {
    super.initState();
    _model = MembersModel(gateway: widget.session);
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MembersModel>.value(
      value: _model,
      child: const _MembersView(),
    );
  }
}

final class _MembersView extends StatelessWidget {
  const _MembersView();

  @override
  Widget build(BuildContext context) {
    final MembersModel model = context.watch<MembersModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moradores'),
        actions: [
          if (model.isZelador)
            IconButton(
              onPressed: () => _openInvite(context, model),
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'Convidar pessoa',
            ),
        ],
      ),
      body: SafeArea(child: _body(context, model)),
    );
  }

  Widget _body(BuildContext context, MembersModel model) {
    if (model.members.isEmpty) {
      if (model.loading) return const TainaLoadingList();
      if (model.error case final TainaError error) {
        return _refreshable(
          model,
          TainaErrorState(error: error, onRetry: model.load),
        );
      }
      return _refreshable(
        model,
        const TainaEmptyState(
          icon: Icons.people_outline,
          title: 'Ninguém por aqui',
          message: 'A comunidade ainda não tem moradores.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        children: [
          TainaText(
            MembersModel.countLine(model.members.length),
            style: TainaTypography.overline,
            uppercase: true,
            color: TainaPalette.textMuted,
          ),
          const SizedBox(height: TainaSpacing.space1),
          TainaText(
            _hint(model.isZelador),
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
          ),
          const SizedBox(height: TainaSpacing.space2),
          for (final Ava member in model.members)
            Padding(
              padding: const EdgeInsets.only(bottom: TainaSpacing.space2),
              child: _MemberRow(
                member: member,
                mePublicId: model.mePublicId,
                isZelador: model.isZelador,
                working: model.working == member.publicId,
                onChangeRole: (Papel papel) =>
                    _changeRole(context, model, member, papel),
                onResetLink: () => _resetLink(context, model, member),
                onDeactivate: () => _deactivate(context, model, member),
                onReactivate: () => _reactivate(context, model, member),
                onRevokeInvite: () => _revokeInvite(context, model, member),
              ),
            ),
        ],
      ),
    );
  }

  Widget _refreshable(MembersModel model, Widget child) {
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(TainaSpacing.space4),
        children: [child],
      ),
    );
  }

  /// Where the acts live, said out loud: the screen is theirs when the person
  /// is the zeladora, and a window when she is not.
  String _hint(bool isZelador) {
    return isZelador
        ? 'Você cuida da comunidade: convide pelo + no topo, mude papéis e '
              'mande o link de senha pelo menu de cada pessoa.'
        : 'Quem cuida da comunidade convida e muda papéis. Para pedir um '
              'convite ou uma senha nova, fale com a zeladora.';
  }

  Future<void> _changeRole(
    BuildContext context,
    MembersModel model,
    Ava member,
    Papel papel,
  ) async {
    final result = await model.changeRole(member.publicId, papel);
    if (context.mounted) _showOutcome(context, result);
  }

  Future<void> _resetLink(
    BuildContext context,
    MembersModel model,
    Ava member,
  ) async {
    final result = await model.resetLink(member.publicId);
    if (!context.mounted) return;
    switch (result) {
      case Ok(:final value):
        await _showLink(
          context,
          _LinkData(
            title: 'Link de senha',
            link: value.resetUrl,
            message:
                'Envie este link para ${value.ava.label}. Ela escolhe uma '
                'senha nova e entra de novo. O link vale uma vez só.',
          ),
        );
      case Err(:final error):
        _showFailure(context, error);
    }
  }

  Future<void> _reactivate(
    BuildContext context,
    MembersModel model,
    Ava member,
  ) async {
    final result = await model.reactivate(member.publicId);
    if (context.mounted) _showOutcome(context, result);
  }

  Future<void> _deactivate(
    BuildContext context,
    MembersModel model,
    Ava member,
  ) async {
    final bool confirmed = await _confirm(
      context,
      title: 'Desativar conta?',
      primary: 'Desativar',
      message:
          '${member.label} deixa de entrar na comunidade. O acesso volta '
          'quando a conta for reativada.',
    );
    if (!confirmed || !context.mounted) return;
    final result = await model.deactivate(member.publicId);
    if (context.mounted) _showOutcome(context, result);
  }

  Future<void> _revokeInvite(
    BuildContext context,
    MembersModel model,
    Ava member,
  ) async {
    final bool confirmed = await _confirm(
      context,
      title: 'Revogar este convite?',
      primary: 'Revogar',
      message:
          'O link de convite para de valer. Seria preciso convidar de novo.',
    );
    if (!confirmed || !context.mounted) return;
    final result = await model.revokeInvite(member.publicId);
    if (context.mounted) _showOutcome(context, result);
  }

  Future<void> _openInvite(BuildContext context, MembersModel model) async {
    final MemberInvite? created = await showModalBottomSheet<MemberInvite>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _InviteSheet(model: model),
    );
    if (created == null || !context.mounted) return;
    await _showLink(
      context,
      _LinkData(
        title: 'Convite criado',
        link: created.inviteUrl,
        message:
            'Envie este link para a pessoa. Ela abre no Tainá e escolhe o '
            'próprio nome de usuário. O link vale uma vez só.',
      ),
    );
  }

  Future<void> _showLink(BuildContext context, _LinkData data) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _LinkSheet(data: data),
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

  /// The one alert slot: the failure's own pt-BR sentence. Success is said by
  /// the list itself, which already shows the new state.
  void _showOutcome<T>(BuildContext context, TainaResult<T> result) {
    if (result case Err(:final error)) {
      _showFailure(context, error);
    }
  }

  void _showFailure(BuildContext context, TainaError error) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Não deu certo'),
        content: Text(error.message),
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

enum _MemberMenu { role, resetLink, deactivate, reactivate, revokeInvite }

/// One person: the mark, the name, the role, and the state when there is one
/// (deactivated, or the person holding the phone). The zeladora's acts sit in
/// the menu of the row.
final class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.mePublicId,
    required this.isZelador,
    required this.working,
    required this.onChangeRole,
    required this.onResetLink,
    required this.onDeactivate,
    required this.onReactivate,
    required this.onRevokeInvite,
  });

  final Ava member;
  final String? mePublicId;
  final bool isZelador;
  final bool working;
  final ValueChanged<Papel> onChangeRole;
  final VoidCallback onResetLink;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;
  final VoidCallback onRevokeInvite;

  bool get _isMe => member.publicId == mePublicId;

  @override
  Widget build(BuildContext context) {
    final String? meta = MembersModel.metaFor(member, mePublicId);
    return TainaRowCard(
      child: Row(
        children: [
          _MemberAvatar(
            name: member.label,
            inactive: member.deactivatedAt != null,
          ),
          const SizedBox(width: TainaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TainaText(
                  member.label,
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                TainaText(
                  _roleLabel(member.papel),
                  style: TainaTypography.bodySm,
                  color: TainaPalette.textSecondary,
                ),
                if (meta != null)
                  TainaText(
                    meta,
                    style: TainaTypography.caption,
                    color: TainaPalette.textMuted,
                  ),
              ],
            ),
          ),
          if (isZelador && !_isMe) _menu(),
        ],
      ),
    );
  }

  Widget _menu() {
    if (working) {
      return const SizedBox(
        width: TainaSizes.controlSm,
        height: TainaSizes.controlSm,
        child: Center(
          child: SizedBox(
            width: TainaSizes.controlSm / 2,
            height: TainaSizes.controlSm / 2,
            child: CircularProgressIndicator(
              strokeWidth: TainaSizes.thick,
              color: TainaPalette.textMuted,
              semanticsLabel: 'Carregando',
            ),
          ),
        ),
      );
    }
    final bool pending = MembersModel.isPendingInvite(member);
    final bool deactivated = member.deactivatedAt != null;
    return PopupMenuButton<_MemberMenu>(
      tooltip: 'Ações para ${member.label}',
      icon: const Icon(Icons.more_horiz, color: TainaPalette.textMuted),
      onSelected: (_MemberMenu value) {
        switch (value) {
          case _MemberMenu.role:
            onChangeRole(
              member.papel == Papel.zelador ? Papel.morador : Papel.zelador,
            );
          case _MemberMenu.resetLink:
            onResetLink();
          case _MemberMenu.deactivate:
            onDeactivate();
          case _MemberMenu.reactivate:
            onReactivate();
          case _MemberMenu.revokeInvite:
            onRevokeInvite();
        }
      },
      itemBuilder: (BuildContext context) {
        if (pending) {
          return const [
            PopupMenuItem<_MemberMenu>(
              value: _MemberMenu.revokeInvite,
              child: Text('Revogar convite'),
            ),
          ];
        }
        if (deactivated) {
          return const [
            PopupMenuItem<_MemberMenu>(
              value: _MemberMenu.reactivate,
              child: Text('Reativar conta'),
            ),
          ];
        }
        return [
          PopupMenuItem<_MemberMenu>(
            value: _MemberMenu.role,
            child: Text(
              member.papel == Papel.zelador
                  ? 'Voltar a morador'
                  : 'Tornar zelador(a)',
            ),
          ),
          const PopupMenuItem<_MemberMenu>(
            value: _MemberMenu.resetLink,
            child: Text('Link de senha'),
          ),
          const PopupMenuItem<_MemberMenu>(
            value: _MemberMenu.deactivate,
            child: Text('Desativar conta'),
          ),
        ];
      },
    );
  }
}

/// The person's mark: the first letter on a deterministic tint, dimmed when
/// the account is not active.
final class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, this.inactive = false});

  final String name;
  final bool inactive;

  @override
  Widget build(BuildContext context) {
    final String initial = name.isEmpty
        ? ' '
        : name.substring(0, 1).toUpperCase();
    return Container(
      width: TainaSizes.controlSm,
      height: TainaSizes.controlSm,
      decoration: BoxDecoration(color: _tint(name), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: TainaText(
        initial,
        style: TainaTypography.label,
        color: inactive ? TainaPalette.textMuted : TainaPalette.textPrimary,
      ),
    );
  }

  Color _tint(String value) {
    return switch (MembersModel.tintIndex(value)) {
      0 => TainaPalette.avatarTint0,
      1 => TainaPalette.avatarTint1,
      2 => TainaPalette.avatarTint2,
      _ => TainaPalette.avatarTint3,
    };
  }
}

/// The invite the zeladora mints: the role of the new person, then the link.
/// The default is morador, like the web's form.
final class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.model});

  final MembersModel model;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

final class _InviteSheetState extends State<_InviteSheet> {
  Papel _papel = Papel.morador;
  bool _working = false;
  String? _failure;

  Future<void> _invite() async {
    setState(() {
      _working = true;
      _failure = null;
    });
    final result = await widget.model.invite(_papel);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final error):
        setState(() {
          _working = false;
          _failure = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(TainaSpacing.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TainaText(
              'Convidar pessoa',
              style: TainaTypography.h3,
              color: TainaPalette.textPrimary,
            ),
            const SizedBox(height: TainaSpacing.space2),
            TainaText(
              'A pessoa entra pelo link do convite e escolhe o próprio nome de '
              'usuário.',
              style: TainaTypography.bodySm,
              color: TainaPalette.textSecondary,
            ),
            const SizedBox(height: TainaSpacing.space4),
            SegmentedButton<Papel>(
              segments: const [
                ButtonSegment<Papel>(
                  value: Papel.morador,
                  label: Text('Morador'),
                ),
                ButtonSegment<Papel>(
                  value: Papel.zelador,
                  label: Text('Zelador'),
                ),
              ],
              selected: {_papel},
              onSelectionChanged: (Set<Papel> selection) {
                setState(() => _papel = selection.first);
              },
            ),
            if (_failure case final String failure) ...[
              const SizedBox(height: TainaSpacing.space2),
              TainaText(
                failure,
                style: TainaTypography.caption,
                color: TainaPalette.feedbackError,
              ),
            ],
            const SizedBox(height: TainaSpacing.space4),
            TainaPrimaryButton(
              label: 'Criar convite',
              loading: _working,
              onPressed: _working ? null : () => unawaited(_invite()),
            ),
            const SizedBox(height: TainaSpacing.space2),
            TainaSecondaryButton(
              label: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

final class _LinkData {
  const _LinkData({
    required this.title,
    required this.link,
    required this.message,
  });

  final String title;
  final String link;
  final String message;
}

/// The sheet a minted link lands in: the link in full, the copy at one touch,
/// and the one-time rule said out loud.
final class _LinkSheet extends StatefulWidget {
  const _LinkSheet({required this.data});

  final _LinkData data;

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

final class _LinkSheetState extends State<_LinkSheet> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.data.link));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(TainaSpacing.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TainaText(
              widget.data.title,
              style: TainaTypography.h3,
              color: TainaPalette.textPrimary,
            ),
            const SizedBox(height: TainaSpacing.space2),
            TainaText(
              widget.data.message,
              style: TainaTypography.bodySm,
              color: TainaPalette.textSecondary,
            ),
            const SizedBox(height: TainaSpacing.space4),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                minHeight: TainaSizes.controlSm,
              ),
              padding: const EdgeInsets.all(TainaSpacing.space3),
              decoration: const BoxDecoration(
                color: TainaPalette.fieldBg,
                borderRadius: TainaRadii.mdAll,
              ),
              child: SelectableText(
                widget.data.link,
                maxLines: 3,
                style: TainaTypography.monoSm.copyWith(
                  color: TainaPalette.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: TainaSpacing.space4),
            TainaPrimaryButton(
              label: _copied ? 'Copiado' : 'Copiar link',
              onPressed: () => unawaited(_copy()),
            ),
            const SizedBox(height: TainaSpacing.space2),
            TainaSecondaryButton(
              label: 'Fechar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

String _roleLabel(Papel papel) =>
    papel == Papel.zelador ? TainaWords.zelador : TainaWords.morador;
