import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_model.dart';
import '../auth/device_name.dart';
import 'invite_paste_view.dart';
import 'login_view_model.dart';

/// The sign in and first-community address entry.
final class LoginView extends StatelessWidget {
  const LoginView({required this.session, this.onOpenInvite, super.key});

  final SessionModel session;
  final VoidCallback? onOpenInvite;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LoginViewModel>(
      create: (_) => LoginViewModel(session: session),
      child: _LoginForm(session: session, onOpenInvite: onOpenInvite),
    );
  }
}

final class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.session, required this.onOpenInvite});

  final SessionModel session;
  final VoidCallback? onOpenInvite;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

final class _LoginFormState extends State<_LoginForm> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _address = TextEditingController();

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
    _address.dispose();
    super.dispose();
  }

  Future<void> _enter(LoginViewModel model) => model.enter(
    username: _username.text,
    password: _password.text,
    address: _address.text,
    deviceName: authDeviceName(
      platform: defaultTargetPlatform,
      username: _username.text,
    ),
  );

  Future<void> _openInvite() {
    final onOpenInvite = widget.onOpenInvite;
    if (onOpenInvite != null) {
      onOpenInvite();
      return Future<void>.value();
    }
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InvitePasteView(session: widget.session),
      ),
    );
  }

  Future<void> _forgotPassword() {
    return TainaSheet.show<void>(
      context: context,
      title: 'Esqueci minha senha',
      child: const Padding(
        padding: EdgeInsets.all(TainaSpacing.space4),
        child: TainaText(
          'O Tainá não usa e-mail. Fale com quem cuida da sua comunidade: '
          'essa pessoa gera um link para você criar uma senha nova.',
          style: TainaTypography.body,
          color: TainaPalette.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<LoginViewModel>();
    final formMessage = model.formMessage;

    return Scaffold(
      backgroundColor: TainaPalette.bgDeep,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TainaSpacing.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: TainaSpacing.space5,
            children: [
              const _Header(),
              if (model.showsAddress)
                TainaField(
                  label: 'Endereço da comunidade',
                  kind: TainaFieldKind.address,
                  controller: _address,
                  placeholder: 'ex.: taina.local',
                  errorMessages: [
                    if (model.addressErrorMessage != null)
                      model.addressErrorMessage!,
                  ],
                  onChanged: (_) {
                    setState(() {});
                    model.clearFailure();
                  },
                  textInputAction: TextInputAction.next,
                )
              else
                _CommunityRow(
                  title: model.communityLine(),
                  onChange: () async {
                    _address.clear();
                    await model.changeCommunity();
                  },
                ),
              if (model.showsAddress && model.isCleartextAddress(_address.text))
                const ConnectionNotice(),
              if (model.host?.isCleartext == true && !model.showsAddress)
                const ConnectionNotice(),
              if (model.communityNotCreated) const _UnbootstrappedCard(),
              if (formMessage != null)
                ErrorCard(
                  title: formMessage,
                  body: model.isUnreachable
                      ? LoginViewModel.unreachableMessage
                      : '',
                  retry: model.isUnreachable ? () => _enter(model) : null,
                ),
              if (model.notice != null)
                ErrorCard(title: model.notice!, body: ''),
              TainaField(
                label: 'Seu nome de usuário',
                kind: TainaFieldKind.text,
                controller: _username,
                errorMessages: model.messagesFor(const ['username']),
                autofillHints: const [AutofillHints.username],
                textCapitalization: TextCapitalization.none,
                placeholder: 'ex.: ana',
                help: 'É com ele que você entra.',
                textInputAction: TextInputAction.next,
              ),
              TainaField(
                label: 'Senha',
                kind: TainaFieldKind.password,
                controller: _password,
                errorMessages: model.messagesFor(const ['password']),
                autofillHints: const [AutofillHints.password],
                placeholder: 'sua senha',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _enter(model),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TainaButton(
                  title: 'Esqueci minha senha',
                  kind: TainaButtonKind.ghost,
                  size: TainaButtonSize.sm,
                  action: _forgotPassword,
                ),
              ),
              TainaButton(
                title: 'Entrar',
                kind: TainaButtonKind.primary,
                size: TainaButtonSize.lg,
                loading: model.signingIn,
                action: () => _enter(model),
              ),
              const TainaText(
                'ou',
                style: TainaTypography.caption,
                color: TainaPalette.textMuted,
                textAlign: TextAlign.center,
              ),
              TainaButton(
                title: 'Tenho um convite',
                kind: TainaButtonKind.secondary,
                size: TainaButtonSize.lg,
                action: _openInvite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: TainaSpacing.space2,
      children: [
        const TainaText(
          'Tainá',
          style: TainaTypography.display,
          color: TainaPalette.textPrimary,
          textAlign: TextAlign.center,
        ),
        const TainaText(
          'Entre com seu nome na nuvem da sua comunidade.',
          style: TainaTypography.body,
          color: TainaPalette.textSecondary,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

final class _CommunityRow extends StatelessWidget {
  const _CommunityRow({required this.title, required this.onChange});

  final String title;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TainaText(
            title,
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TainaButton(
          title: 'Trocar',
          kind: TainaButtonKind.ghost,
          size: TainaButtonSize.sm,
          action: onChange,
        ),
      ],
    );
  }
}

final class _UnbootstrappedCard extends StatelessWidget {
  const _UnbootstrappedCard();

  @override
  Widget build(BuildContext context) {
    return TainaCard(
      kind: TainaCardKind.raised,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TainaText(
            'A comunidade ainda não foi criada',
            style: TainaTypography.label,
            color: TainaPalette.feedbackWarning,
          ),
          SizedBox(height: TainaSpacing.space2),
          TainaText(
            'Este endereço respondeu, mas ninguém criou a comunidade nele '
            'ainda. Confira o endereço com quem instalou a caixa.',
            style: TainaTypography.bodySm,
            color: TainaPalette.textSecondary,
          ),
        ],
      ),
    );
  }
}
