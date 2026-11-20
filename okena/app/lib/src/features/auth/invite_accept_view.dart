import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_model.dart';
import '../../session/session_state.dart';
import 'auth_gate.dart';
import 'device_name.dart';
import 'invite_accept_view_model.dart';

/// The invitation form and its token states.
final class InviteAcceptView extends StatelessWidget {
  const InviteAcceptView({
    required this.session,
    required this.pending,
    this.tekoaName,
    this.inviter,
    super.key,
  });

  final SessionModel session;
  final PendingAuth pending;
  final String? tekoaName;
  final String? inviter;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InviteAcceptViewModel>(
      create: (_) => InviteAcceptViewModel(session: session),
      child: _InviteAcceptBody(
        session: session,
        pending: pending,
        tekoaName: tekoaName,
        inviter: inviter,
      ),
    );
  }
}

final class _InviteAcceptBody extends StatefulWidget {
  const _InviteAcceptBody({
    required this.session,
    required this.pending,
    required this.tekoaName,
    required this.inviter,
  });

  final SessionModel session;
  final PendingAuth pending;
  final String? tekoaName;
  final String? inviter;

  @override
  State<_InviteAcceptBody> createState() => _InviteAcceptBodyState();
}

final class _InviteAcceptBodyState extends State<_InviteAcceptBody> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<InviteAcceptViewModel>().check(
        widget.pending,
        tekoaName: widget.tekoaName,
        inviter: widget.inviter,
      );
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create(InviteAcceptViewModel model) => model.createAccount(
    pending: widget.pending,
    username: _username.text,
    displayName: _displayName.text,
    password: _password.text,
    deviceName: authDeviceName(
      platform: defaultTargetPlatform,
      username: _username.text,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final model = context.watch<InviteAcceptViewModel>();
    return Scaffold(
      backgroundColor: TainaPalette.bgDeep,
      body: SafeArea(
        child: switch (model.gate) {
          AuthChecking() => const Center(child: TainaLoadingList(itemCount: 4)),
          AuthDead() => _deadEnd(context),
          AuthBroken(:final error) => _broken(model, error),
          AuthOpen() => _form(model),
        },
      ),
    );
  }

  Widget _deadEnd(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorCard(
              title: 'Este convite não é mais válido.',
              body: '',
              retryLabel: 'Voltar',
              retry: widget.session.leavePendingAuth,
              contact: () => _showContactSheet(context),
            ),
            const SizedBox(height: TainaSpacing.space3),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TainaButton(
                title: 'Voltar para entrar',
                kind: TainaButtonKind.ghost,
                size: TainaButtonSize.sm,
                action: widget.session.leavePendingAuth,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _broken(InviteAcceptViewModel model, TainaError error) {
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      child: Center(
        child: ErrorCard(
          title: 'Não conseguimos validar este convite.',
          body: error.message,
          retry: () => model.check(
            widget.pending,
            tekoaName: widget.tekoaName,
            inviter: widget.inviter,
          ),
        ),
      ),
    );
  }

  Widget _form(InviteAcceptViewModel model) {
    final formMessage = model.formMessage;
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TainaButton(
              title: 'Entrar',
              kind: TainaButtonKind.ghost,
              size: TainaButtonSize.sm,
              icon: TainaIcon.chevL,
              action: widget.session.leavePendingAuth,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: TainaSpacing.space4),
                  const TainaText(
                    'Você recebeu um convite',
                    style: TainaTypography.h1,
                    color: TainaPalette.textPrimary,
                  ),
                  const SizedBox(height: TainaSpacing.space5),
                  TainaText(
                    model.invitationMessage,
                    style: TainaTypography.body,
                    color: TainaPalette.textSecondary,
                  ),
                  const SizedBox(height: TainaSpacing.space5),
                  TainaField(
                    label: 'Seu nome de usuário',
                    controller: _username,
                    kind: TainaFieldKind.text,
                    placeholder: 'ex.: joao',
                    help: 'Sem espaços. É com ele que você entra.',
                    errorMessages: model.messagesFor(const ['username']),
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: TainaSpacing.space4),
                  TainaField(
                    label: 'Nome de exibição (opcional)',
                    controller: _displayName,
                    kind: TainaFieldKind.text,
                    placeholder: 'ex.: João Mendes',
                    help: 'Como seu nome aparece para a comunidade.',
                    errorMessages: model.messagesFor(const ['display_name']),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: TainaSpacing.space4),
                  TainaField(
                    label: 'Senha',
                    controller: _password,
                    kind: TainaFieldKind.password,
                    placeholder: 'mínimo 8 caracteres',
                    help: 'Use uma frase longa que só você lembra.',
                    errorMessages: model.messagesFor(const ['password']),
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _create(model),
                  ),
                  if (formMessage != null) ...[
                    const SizedBox(height: TainaSpacing.space3),
                    ErrorCard(title: formMessage, body: ''),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: TainaSpacing.space3),
          TainaButton(
            title: 'Criar conta',
            kind: TainaButtonKind.primary,
            size: TainaButtonSize.lg,
            loading: model.creating,
            action: () => _create(model),
          ),
        ],
      ),
    );
  }

  Future<void> _showContactSheet(BuildContext context) {
    return TainaSheet.show<void>(
      context: context,
      title: 'Falar com quem cuida',
      child: const Padding(
        padding: EdgeInsets.all(TainaSpacing.space4),
        child: TainaText(
          'Peça a quem cuida da sua comunidade para enviar um novo convite.',
          style: TainaTypography.body,
          color: TainaPalette.textSecondary,
        ),
      ),
    );
  }
}
