import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/device_name.dart';
import '../../session/session_model.dart';
import '../../session/session_state.dart';
import 'auth_community_header.dart';
import 'auth_gate.dart';
import 'reset_password_view_model.dart';

/// The password reset, the native mirror of the web's `ResetPasswordLive`.
///
/// The link is checked lightly on arrival, a dead link shows the dead end
/// instead of the form, and the session is born on the submit.
final class ResetPasswordView extends StatelessWidget {
  const ResetPasswordView({
    required this.session,
    required this.pending,
    super.key,
  });

  final SessionModel session;
  final PendingAuth pending;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ResetPasswordViewModel>(
      create: (_) => ResetPasswordViewModel(session: session),
      child: _ResetPasswordBody(session: session, pending: pending),
    );
  }
}

final class _ResetPasswordBody extends StatefulWidget {
  const _ResetPasswordBody({required this.session, required this.pending});

  final SessionModel session;
  final PendingAuth pending;

  @override
  State<_ResetPasswordBody> createState() => _ResetPasswordBodyState();
}

final class _ResetPasswordBodyState extends State<_ResetPasswordBody> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ResetPasswordViewModel>().check(widget.pending);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save(ResetPasswordViewModel model) => model.save(
    pending: widget.pending,
    password: _password.text,
    confirmation: _confirmation.text,
    deviceName: DeviceName.current,
  );

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ResetPasswordViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Redefinir senha')),
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

  /// The dead end of a link spent or expired: an honest sentence and the way
  /// back to the login.
  Widget _deadEnd(BuildContext context) {
    return Center(
      child: TainaEmptyState(
        icon: Icons.schedule,
        title: 'Este link expirou ou já foi usado',
        message:
            'O link de redefinição vale uma hora e só pode ser usado uma vez. '
            'Peça um novo a quem cuida da sua comunidade.',
        actionLabel: 'Ir para o login',
        onAction: () {
          widget.session.leavePendingAuth();
        },
      ),
    );
  }

  Widget _form(ResetPasswordViewModel model) {
    final formMessage = model.formMessage;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(TainaSpacing.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: TainaSpacing.space5,
        children: [
          AuthCommunityHeader(instance: model.instance, host: model.host),
          const _ResetTitle(),
          TainaTextField(
            label: 'Senha nova',
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
            label: 'Salvar nova senha',
            loading: model.saving,
            onPressed: () => _save(model),
          ),
        ],
      ),
    );
  }
}

final class _ResetTitle extends StatelessWidget {
  const _ResetTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: TainaSpacing.space2,
      children: const [
        Icon(
          Icons.shield_outlined,
          size: TainaFontSizes.display,
          color: TainaPalette.brandPrimary,
        ),
        TainaText(
          'Redefinir senha',
          style: TainaTypography.h1,
          color: TainaPalette.textPrimary,
          textAlign: TextAlign.center,
        ),
        TainaText(
          'Crie uma senha nova para voltar a entrar.',
          style: TainaTypography.body,
          color: TainaPalette.textSecondary,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
