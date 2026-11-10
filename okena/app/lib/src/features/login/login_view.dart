import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/device_name.dart';
import '../../session/session_model.dart';
import 'invite_paste_field.dart';
import 'login_view_model.dart';

/// The sign in: username, password, device name, and the community the person
/// is entering, always visible at the top.
///
/// The invite link pasted at the bottom goes through the deep-link path, for
/// the person whose way in is a link, not a password.
final class LoginView extends StatelessWidget {
  const LoginView({required this.session, super.key});

  final SessionModel session;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LoginViewModel>(
      create: (_) => LoginViewModel(session: session),
      child: _LoginForm(session: session),
    );
  }
}

final class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.session});

  final SessionModel session;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

final class _LoginFormState extends State<_LoginForm> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  late final TextEditingController _deviceName = TextEditingController(
    text: DeviceName.current,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LoginViewModel>().probe();
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _deviceName.dispose();
    super.dispose();
  }

  Future<void> _enter(LoginViewModel model) => model.enter(
    username: _username.text,
    password: _password.text,
    deviceName: _deviceName.text,
  );

  @override
  Widget build(BuildContext context) {
    final model = context.watch<LoginViewModel>();
    final formMessage = model.formMessage;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TainaSpacing.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: TainaSpacing.space5,
            children: [
              _Header(model: model),
              TainaTextField(
                label: 'Usuário',
                controller: _username,
                errorMessages: model.messagesFor(const ['username']),
                autofillHints: const [AutofillHints.username],
                textCapitalization: TextCapitalization.none,
                placeholder: 'seu nome de usuário',
              ),
              TainaTextField(
                label: 'Senha',
                controller: _password,
                obscureText: true,
                errorMessages: model.messagesFor(const ['password']),
                autofillHints: const [AutofillHints.password],
                placeholder: 'sua senha',
              ),
              TainaTextField(
                label: 'Nome deste aparelho',
                controller: _deviceName,
                errorMessages: model.messagesFor(const [
                  'device_name',
                  'deviceName',
                ]),
                textCapitalization: TextCapitalization.sentences,
              ),
              if (formMessage != null)
                TainaText(
                  formMessage,
                  style: TainaTypography.bodySm,
                  color: TainaPalette.feedbackError,
                ),
              TainaPrimaryButton(
                label: 'Entrar',
                loading: model.signingIn,
                onPressed: () => _enter(model),
              ),
              InvitePasteField(session: widget.session),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Header extends StatelessWidget {
  const _Header({required this.model});

  final LoginViewModel model;

  @override
  Widget build(BuildContext context) {
    final notice = model.notice;
    final host = model.host;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: TainaSpacing.space2,
      children: [
        if (notice != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(TainaSpacing.space3),
            decoration: const BoxDecoration(
              color: TainaPalette.surfaceRaised,
              borderRadius: TainaRadii.mdAll,
            ),
            child: TainaText(
              notice,
              style: TainaTypography.bodySm,
              color: TainaPalette.feedbackWarning,
            ),
          ),
        if (model.instance?.tekoa?.name != null)
          TainaText(
            model.instance!.tekoa!.name,
            style: TainaTypography.h2,
            color: TainaPalette.textPrimary,
          ),
        if (host != null) ...[
          TainaText(
            host.display,
            style: TainaTypography.monoSm,
            color: TainaPalette.textMuted,
          ),
          if (host.isCleartext) const TainaCleartextNotice(),
        ],
        const TainaText(
          'Entre com o seu usuário e senha da comunidade.',
          style: TainaTypography.body,
          color: TainaPalette.textSecondary,
        ),
      ],
    );
  }
}
