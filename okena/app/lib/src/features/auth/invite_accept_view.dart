import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/device_name.dart';
import '../../session/session_model.dart';
import '../../session/session_state.dart';
import 'auth_community_header.dart';
import 'auth_gate.dart';
import 'invite_accept_view_model.dart';

/// The invite accept, the native mirror of the web's `InviteAcceptLive`.
///
/// The token is checked lightly on arrival, a dead link shows the dead end
/// instead of the form, and the real validation stays on the submit.
final class InviteAcceptView extends StatelessWidget {
  const InviteAcceptView({
    required this.session,
    required this.pending,
    super.key,
  });

  final SessionModel session;
  final PendingAuth pending;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InviteAcceptViewModel>(
      create: (_) => InviteAcceptViewModel(session: session),
      child: _InviteAcceptBody(session: session, pending: pending),
    );
  }
}

final class _InviteAcceptBody extends StatefulWidget {
  const _InviteAcceptBody({required this.session, required this.pending});

  final SessionModel session;
  final PendingAuth pending;

  @override
  State<_InviteAcceptBody> createState() => _InviteAcceptBodyState();
}

final class _InviteAcceptBodyState extends State<_InviteAcceptBody> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<InviteAcceptViewModel>().check(widget.pending);
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _create(InviteAcceptViewModel model) => model.createAccount(
    pending: widget.pending,
    username: _username.text,
    displayName: _displayName.text,
    password: _password.text,
    confirmation: _confirmation.text,
    deviceName: DeviceName.current,
  );

  @override
  Widget build(BuildContext context) {
    final model = context.watch<InviteAcceptViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Aceitar convite')),
      body: switch (model.gate) {
        AuthChecking() => const TainaLoadingList(itemCount: 4),
        AuthDead() => _deadEnd(context),
        AuthBroken(:final error) => TainaErrorState(
          error: error,
          onRetry: () => model.check(widget.pending),
        ),
        AuthOpen() => _form(model),
      },
    );
  }

  /// The dead end of a token spent or expired: an honest sentence and the way
  /// back to the login.
  Widget _deadEnd(BuildContext context) {
    return Center(
      child: TainaEmptyState(
        icon: Icons.schedule,
        title: 'Este convite expirou ou já foi usado',
        message:
            'Convites valem sete dias e só podem ser usados uma vez. Peça '
            'um novo link a quem cuida da sua comunidade.',
        actionLabel: 'Ir para o login',
        onAction: () {
          widget.session.leavePendingAuth();
        },
      ),
    );
  }

  Widget _form(InviteAcceptViewModel model) {
    final formMessage = model.formMessage;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(TainaSpacing.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: TainaSpacing.space5,
        children: [
          AuthCommunityHeader(instance: model.instance, host: model.host),
          const _InviteTitle(),
          TainaTextField(
            label: 'Seu nome de usuário',
            controller: _username,
            errorMessages: model.messagesFor(const ['username']),
            autofillHints: const [AutofillHints.username],
            placeholder: 'ex.: joao',
            help: 'Sem espaços. É com ele que você entra na comunidade.',
          ),
          TainaTextField(
            label: 'Nome de exibição (opcional)',
            controller: _displayName,
            errorMessages: model.messagesFor(const ['display_name']),
            textCapitalization: TextCapitalization.sentences,
            autofillHints: const [AutofillHints.name],
            placeholder: 'ex.: João Mendes',
          ),
          TainaTextField(
            label: 'Senha',
            controller: _password,
            obscureText: true,
            errorMessages: model.messagesFor(const ['password']),
            autofillHints: const [AutofillHints.newPassword],
            placeholder: 'mínimo 8 caracteres',
          ),
          TainaTextField(
            label: 'Confirme a senha',
            controller: _confirmation,
            obscureText: true,
            errorMessages: model.mismatch != null
                ? [model.mismatch!]
                : model.messagesFor(const ['password']),
            autofillHints: const [AutofillHints.newPassword],
            placeholder: 'a mesma senha',
          ),
          if (formMessage != null)
            TainaText(
              formMessage,
              style: TainaTypography.bodySm,
              color: TainaPalette.feedbackError,
            ),
          TainaPrimaryButton(
            label: 'Criar conta',
            loading: model.creating,
            onPressed: () => _create(model),
          ),
        ],
      ),
    );
  }
}

final class _InviteTitle extends StatelessWidget {
  const _InviteTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: TainaSpacing.space2,
      children: const [
        Icon(
          Icons.auto_awesome,
          size: TainaFontSizes.display,
          color: TainaPalette.brandPrimary,
        ),
        TainaText(
          'Você foi convidado!',
          style: TainaTypography.h1,
          color: TainaPalette.textPrimary,
          textAlign: TextAlign.center,
        ),
        TainaText(
          'Crie sua conta para entrar na nuvem da comunidade.',
          style: TainaTypography.body,
          color: TainaPalette.textSecondary,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
