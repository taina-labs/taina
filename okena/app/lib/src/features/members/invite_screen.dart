import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/members/invite_model.dart';
import 'package:okena_app/src/features/members/members_clipboard.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// Creates an invitation and shows its web link and QR code.
final class MembersInviteScreen extends StatefulWidget {
  const MembersInviteScreen({required this.session, this.clipboard, super.key});

  final SessionGateway session;
  final MembersClipboard? clipboard;

  @override
  State<MembersInviteScreen> createState() => _MembersInviteScreenState();
}

final class _MembersInviteScreenState extends State<MembersInviteScreen> {
  late final MembersInviteModel _model = MembersInviteModel(
    gateway: widget.session,
  );
  late final MembersClipboard _clipboard =
      widget.clipboard ?? const PlatformMembersClipboard();
  bool _copied = false;
  bool _copyFailed = false;

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              title: 'Convidar moradores',
              backLabel: 'Moradores',
              onBack: () => Navigator.of(context).pop(_model.invite),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: _model,
                builder: (BuildContext context, Widget? child) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      TainaSpacing.space4,
                      TainaSpacing.space3,
                      TainaSpacing.space4,
                      TainaSpacing.space6,
                    ),
                    child: _model.invite == null
                        ? _inviteForm()
                        : _inviteLink(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inviteForm() {
    final TainaError? error = _model.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PAPEL NO CONVITE',
          style: TainaTypography.overline.copyWith(
            color: TainaPalette.textMuted,
          ),
        ),
        const SizedBox(height: TainaSpacing.space3),
        TainaRadioCard(
          title: 'Morador',
          description: 'Vê a praça e ganha uma casa própria.',
          selected: _model.papel == Papel.morador,
          action: _model.working
              ? null
              : () => _model.selectRole(Papel.morador),
        ),
        const SizedBox(height: TainaSpacing.space2),
        TainaRadioCard(
          title: 'Zelador',
          description:
              'Cuida da máquina: disco, backups e convites. '
              'Para abrir uma casa, pede como todo mundo.',
          selected: _model.papel == Papel.zelador,
          action: _model.working
              ? null
              : () => _model.selectRole(Papel.zelador),
        ),
        if (error != null) ...[
          const SizedBox(height: TainaSpacing.space4),
          TainaToast(kind: TainaToastKind.error, text: error.message),
        ],
        const SizedBox(height: TainaSpacing.space5),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TainaButton(
            title: 'Criar convite',
            size: TainaButtonSize.md,
            loading: _model.working,
            action: _model.working ? null : () => unawaited(_createInvite()),
          ),
        ),
        const SizedBox(height: TainaSpacing.space3),
        Text(
          'Você cria convites só quando quiser. Dá para cancelar depois.',
          style: TainaTypography.caption.copyWith(
            color: TainaPalette.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _inviteLink() {
    final MemberInvite invite = _model.invite!;
    final String? link = _model.link;
    if (link == null) return const SizedBox.shrink();

    final String toastText = _copyFailed
        ? 'Não foi possível copiar o link. Selecione e copie o endereço.'
        : _copied
        ? 'Link copiado.'
        : 'Convite criado. Envie o link para a pessoa.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TainaToast(
          kind: _copyFailed ? TainaToastKind.error : TainaToastKind.info,
          text: toastText,
        ),
        const SizedBox(height: TainaSpacing.space4),
        QRCard(
          link: link,
          description:
              '${MembersInviteModel.descriptionFor(invite.ava.papel)} '
              'Você pode cancelar quando quiser.',
          copyLabel: _copied ? 'Link copiado' : 'Copiar link',
          onCopy: () => unawaited(_copy(link)),
        ),
        const SizedBox(height: TainaSpacing.space3),
        Text(
          'O convite vale por 7 dias.',
          style: TainaTypography.caption.copyWith(
            color: TainaPalette.textMuted,
          ),
        ),
      ],
    );
  }

  Future<void> _createInvite() async {
    await _model.create();
  }

  Future<void> _copy(String link) async {
    try {
      await _clipboard.writeText(link);
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
