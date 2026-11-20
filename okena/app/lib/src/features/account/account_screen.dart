import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/account/account_model.dart';
import 'package:okena_app/src/features/account/devices_screen.dart';
import 'package:okena_app/src/features/privacy/privacy_screen.dart';
import 'package:okena_app/src/features/requests/requests_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The current person's account and access settings.
final class AccountScreen extends StatefulWidget {
  const AccountScreen({
    required this.session,
    required this.onSignOut,
    this.hostDisplay,
    this.cleartext = false,
    this.onBack,
    this.onOpenRequests,
    this.onOpenPrivacy,
    this.onOpenInvite,
    this.onOpenDevices,
    this.onOpenCameraRoll,
    super.key,
  });

  final SessionGateway session;

  /// The session owner's sign-out, called only after confirmation.
  final Future<void> Function() onSignOut;

  /// Retained for callers that still pass the sign-in host details. The
  /// account screen does not display either value.
  final String? hostDisplay;
  final bool cleartext;

  final VoidCallback? onBack;
  final VoidCallback? onOpenRequests;
  final VoidCallback? onOpenPrivacy;
  final VoidCallback? onOpenInvite;
  final VoidCallback? onOpenDevices;
  final VoidCallback? onOpenCameraRoll;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

final class _AccountScreenState extends State<AccountScreen> {
  late final AccountModel _model;
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();

  @override
  void initState() {
    super.initState();
    _model = AccountModel(gateway: widget.session);
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AccountModel>.value(
      value: _model,
      child: _AccountView(
        onSignOut: widget.onSignOut,
        onBack: widget.onBack,
        onOpenRequests: widget.onOpenRequests,
        onOpenPrivacy: widget.onOpenPrivacy,
        onOpenInvite: widget.onOpenInvite,
        onOpenDevices: widget.onOpenDevices,
        onOpenCameraRoll: widget.onOpenCameraRoll,
        currentPassword: _currentPassword,
        newPassword: _newPassword,
        session: widget.session,
      ),
    );
  }
}

final class _AccountView extends StatefulWidget {
  const _AccountView({
    required this.onSignOut,
    required this.onBack,
    required this.onOpenRequests,
    required this.onOpenPrivacy,
    required this.onOpenInvite,
    required this.onOpenDevices,
    required this.onOpenCameraRoll,
    required this.currentPassword,
    required this.newPassword,
    required this.session,
  });

  final Future<void> Function() onSignOut;
  final VoidCallback? onBack;
  final VoidCallback? onOpenRequests;
  final VoidCallback? onOpenPrivacy;
  final VoidCallback? onOpenInvite;
  final VoidCallback? onOpenDevices;
  final VoidCallback? onOpenCameraRoll;
  final TextEditingController currentPassword;
  final TextEditingController newPassword;
  final SessionGateway session;

  @override
  State<_AccountView> createState() => _AccountViewState();
}

final class _AccountViewState extends State<_AccountView> {
  bool _leaving = false;

  @override
  Widget build(BuildContext context) {
    final AccountModel model = context.watch<AccountModel>();
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: model.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              PageHeaderSliver(
                title: 'Conta',
                backLabel: 'Início',
                onBack: widget.onBack ?? () => Navigator.of(context).maybePop(),
              ),
              if (model.me case final Me me)
                _accountContent(context, model, me)
              else if (model.loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.all(TainaSpacing.space4),
                    child: SkeletonView(
                      kind: TainaSkeletonKind.listRow,
                      count: 4,
                    ),
                  ),
                )
              else if (model.error case final TainaError error)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(TainaSpacing.space4),
                    child: ErrorCard(
                      title: 'Não conseguimos abrir sua conta.',
                      body: error.message,
                      retry: model.load,
                    ),
                  ),
                )
              else
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountContent(BuildContext context, AccountModel model, Me me) {
    final String role = me.ava.papel == Papel.zelador
        ? TainaWords.zelador
        : TainaWords.morador;
    final List<Widget> rows = [
      _accountRow(
        title: 'Pedidos',
        meta: model.pendingRequestsLabel,
        mark: TainaServiceMark.pedidos,
        onTap: () => _openRequests(context),
      ),
      _accountRow(
        title: 'Privacidade',
        meta: 'Como funciona o acesso',
        mark: TainaServiceMark.privacidade,
        onTap: () => _openPrivacy(context),
      ),
      if (me.ava.papel == Papel.zelador)
        _accountRow(
          title: 'Convidar',
          meta: 'Criar um convite',
          mark: TainaServiceMark.moradores,
          onTap: widget.onOpenInvite,
        ),
      _accountRow(
        title: 'Trocar senha',
        meta: 'Atualize a sua senha',
        mark: TainaServiceMark.senha,
        onTap: () => _openPassword(context, model),
      ),
      _accountRow(
        title: 'Dispositivos',
        meta: 'Aparelhos com acesso',
        mark: TainaServiceMark.dispositivos,
        onTap: () => _openDevices(context),
      ),
      if (widget.onOpenCameraRoll != null)
        _accountRow(
          title: 'Rolo de câmera',
          meta: 'Fotos e vídeos deste aparelho',
          mark: TainaServiceMark.jaci,
          onTap: widget.onOpenCameraRoll,
        ),
    ];
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        TainaSpacing.space4,
        TainaSpacing.space2,
        TainaSpacing.space4,
        TainaSpacing.space6,
      ),
      sliver: SliverList.list(
        children: [
          TainaCard(
            child: Row(
              children: [
                TainaAvatar(name: me.ava.label, size: TainaAvatarSize.lg),
                const SizedBox(width: TainaSpacing.space4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        me.ava.label,
                        style: TainaTypography.h3.copyWith(
                          color: TainaPalette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: TainaSpacing.space1),
                      Text(
                        '$role, ${me.tekoa.name}',
                        style: TainaTypography.bodySm.copyWith(
                          color: TainaPalette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TainaSpacing.space3),
          ...rows,
          const Divider(
            color: TainaPalette.borderSubtle,
            thickness: TainaSizes.hairline,
            height: TainaSizes.hairline,
          ),
          const SizedBox(height: TainaSpacing.space4),
          SizedBox(
            width: double.infinity,
            child: TainaButton(
              title: _leaving ? 'Saindo...' : 'Sair',
              icon: TainaIcon.sair,
              kind: TainaButtonKind.secondary,
              action: _leaving ? null : () => unawaited(_signOut(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountRow({
    required String title,
    required String meta,
    required TainaServiceMark mark,
    required VoidCallback? onTap,
  }) {
    return TainaListRow(
      kind: TainaListRowKind.civic,
      title: title,
      meta: meta,
      leadingBuilder: (_) => ServiceSquare(mark: mark),
      trailing: TainaListRowTrailing.chevron,
      onTap: onTap,
    );
  }

  void _openRequests(BuildContext context) {
    final VoidCallback? callback = widget.onOpenRequests;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => RequestsScreen(
          session: widget.session,
          backLabel: 'Conta',
          onBack: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    );
  }

  void _openPrivacy(BuildContext context) {
    final VoidCallback? callback = widget.onOpenPrivacy;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => PrivacyScreen(
          backLabel: 'Conta',
          onBack: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    );
  }

  void _openDevices(BuildContext context) {
    final VoidCallback? callback = widget.onOpenDevices;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => DevicesScreen(
          session: widget.session,
          backLabel: 'Conta',
          onBack: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    );
  }

  void _openPassword(BuildContext context, AccountModel model) {
    unawaited(
      TainaSheet.show<void>(
        context: context,
        title: 'Trocar senha',
        isScrollControlled: true,
        child: _PasswordForm(
          model: model,
          currentPassword: widget.currentPassword,
          newPassword: widget.newPassword,
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final bool? confirmed = await TainaDialog.confirm(
      context: context,
      title: 'Sair da comunidade?',
      confirmLabel: 'Sair',
      message:
          'Ao sair, este aparelho perde o acesso à comunidade. Para voltar, '
          'entre de novo com o seu usuário e senha.',
      useRootNavigator: false,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _leaving = true);
    await widget.onSignOut();
    if (mounted) setState(() => _leaving = false);
  }
}

final class _PasswordForm extends StatelessWidget {
  const _PasswordForm({
    required this.model,
    required this.currentPassword,
    required this.newPassword,
  });

  final AccountModel model;
  final TextEditingController currentPassword;
  final TextEditingController newPassword;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? child) {
        return Padding(
          padding: const EdgeInsets.all(TainaSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TainaField(
                label: 'Senha atual',
                kind: TainaFieldKind.password,
                controller: currentPassword,
                errorMessages: model.currentPasswordErrors,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: TainaSpacing.space3),
              TainaField(
                label: 'Senha nova',
                kind: TainaFieldKind.password,
                controller: newPassword,
                errorMessages: model.newPasswordErrors,
                autofillHints: const [AutofillHints.newPassword],
                placeholder: 'mínimo 8 caracteres',
                textInputAction: TextInputAction.done,
              ),
              if (model.passwordFailure case final TainaError failure) ...[
                const SizedBox(height: TainaSpacing.space2),
                Text(
                  failure.message,
                  style: TainaTypography.bodySm.copyWith(
                    color: TainaPalette.feedbackError,
                  ),
                ),
              ],
              if (model.changed) ...[
                const SizedBox(height: TainaSpacing.space2),
                const Text(
                  'Senha trocada. Nos outros aparelhos, é preciso entrar de '
                  'novo com a senha nova.',
                  style: TainaTypography.bodySm,
                ),
              ],
              const SizedBox(height: TainaSpacing.space3),
              TainaButton(
                title: 'Trocar minha senha',
                loading: model.changing,
                action: model.changing
                    ? null
                    : () => unawaited(_changePassword(model)),
                kind: TainaButtonKind.primary,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _changePassword(AccountModel model) async {
    final bool accepted = await model.changePassword(
      current: currentPassword.text,
      newPassword: newPassword.text,
    );
    if (accepted) {
      currentPassword.clear();
      newPassword.clear();
    }
  }
}
