import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_model.dart';
import '../../session/session_state.dart';
import 'auth_gate.dart';
import 'device_name.dart';
import 'reset_password_view_model.dart';

/// The one-field password reset and its token states.
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
    super.dispose();
  }

  Future<void> _save(ResetPasswordViewModel model) => model.save(
    pending: widget.pending,
    password: _password.text,
    deviceName: authDeviceName(platform: defaultTargetPlatform),
  );

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ResetPasswordViewModel>();
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
              title: 'Este link expirou.',
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

  Widget _broken(ResetPasswordViewModel model, TainaError error) {
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      child: Center(
        child: ErrorCard(
          title: 'Não conseguimos validar este link.',
          body: error.message,
          retry: () => model.check(widget.pending),
        ),
      ),
    );
  }

  Widget _form(ResetPasswordViewModel model) {
    final formMessage = model.formMessage;
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: TainaSpacing.space5),
                  const TainaText(
                    'Redefinir senha',
                    style: TainaTypography.h1,
                    color: TainaPalette.textPrimary,
                  ),
                  const SizedBox(height: TainaSpacing.space2),
                  const TainaText(
                    'Crie uma senha nova para voltar a entrar.',
                    style: TainaTypography.body,
                    color: TainaPalette.textSecondary,
                  ),
                  const SizedBox(height: TainaSpacing.space6),
                  TainaField(
                    label: 'Senha nova',
                    controller: _password,
                    kind: TainaFieldKind.password,
                    placeholder: 'mínimo 8 caracteres',
                    help: 'Use uma frase longa que só você lembra.',
                    errorMessages: model.messagesFor(const ['password']),
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(model),
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
            title: 'Salvar nova senha',
            kind: TainaButtonKind.primary,
            size: TainaButtonSize.lg,
            loading: model.saving,
            action: () => _save(model),
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
          'Peça a quem cuida da sua comunidade para enviar um novo link.',
          style: TainaTypography.body,
          color: TainaPalette.textSecondary,
        ),
      ),
    );
  }
}
