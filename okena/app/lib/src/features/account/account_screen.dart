import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/account/account_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The account: who is acting, which devices, which community, and the way
/// out.
///
/// Signing out is a session act, so it leaves through [onSignOut] and the
/// session owner stays authoritative. The password is self-service: the box
/// keeps this device signed in and revokes the others.
final class AccountScreen extends StatefulWidget {
  const AccountScreen({
    required this.session,
    required this.onSignOut,
    this.hostDisplay,
    this.cleartext = false,
    super.key,
  });

  final SessionGateway session;

  /// The session owner's sign-out, called only after the confirmation.
  final Future<void> Function() onSignOut;

  /// The community's address as the device stores it, when the orchestrator
  /// can provide it. Falls back to the community's domain.
  final String? hostDisplay;

  /// Whether the community's path has no TLS, so the notice shows.
  final bool cleartext;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

final class _AccountScreenState extends State<AccountScreen> {
  late final AccountModel _model;
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();

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
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AccountModel>.value(
      value: _model,
      child: _AccountView(
        onSignOut: widget.onSignOut,
        hostDisplay: widget.hostDisplay,
        cleartext: widget.cleartext,
        currentPassword: _currentPassword,
        newPassword: _newPassword,
        confirmation: _confirmation,
      ),
    );
  }
}

final class _AccountView extends StatefulWidget {
  const _AccountView({
    required this.onSignOut,
    required this.hostDisplay,
    required this.cleartext,
    required this.currentPassword,
    required this.newPassword,
    required this.confirmation,
  });

  final Future<void> Function() onSignOut;
  final String? hostDisplay;
  final bool cleartext;
  final TextEditingController currentPassword;
  final TextEditingController newPassword;
  final TextEditingController confirmation;

  @override
  State<_AccountView> createState() => _AccountViewState();
}

final class _AccountViewState extends State<_AccountView> {
  bool _leaving = false;

  @override
  Widget build(BuildContext context) {
    final AccountModel model = context.watch<AccountModel>();
    final Me? me = model.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Conta')),
      body: SafeArea(
        child: me == null
            ? _unloaded(context, model)
            : _content(context, model, me),
      ),
    );
  }

  Widget _unloaded(BuildContext context, AccountModel model) {
    if (model.loading) return const TainaLoadingList();
    if (model.error case final TainaError error) {
      return TainaErrorState(error: error, onRetry: model.load);
    }
    return const TainaLoadingList();
  }

  Widget _content(BuildContext context, AccountModel model, Me me) {
    final Tekoa tekoa = me.tekoa;
    final int? quota = tekoa.storageQuotaBytes;
    return RefreshIndicator(
      onRefresh: () => _refresh(context, model),
      child: ListView(
        padding: const EdgeInsets.all(TainaSpacing.space5),
        children: [
          _section(
            'Você',
            TainaRowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TainaText(
                    me.ava.label,
                    style: TainaTypography.h3,
                    color: TainaPalette.textPrimary,
                  ),
                  if (me.ava.username case final String username) ...[
                    const SizedBox(height: TainaSpacing.space1),
                    TainaText(
                      '@$username',
                      style: TainaTypography.monoSm,
                      color: TainaPalette.textMuted,
                    ),
                  ],
                  const SizedBox(height: TainaSpacing.space1),
                  TainaText(
                    me.ava.papel == Papel.zelador
                        ? TainaWords.zelador
                        : TainaWords.morador,
                    style: TainaTypography.bodySm,
                    color: TainaPalette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: TainaSpacing.space5),
          _section('Senha', _passwordForm(context, model)),
          const SizedBox(height: TainaSpacing.space5),
          _section('Aparelhos', _devicesSection(context, model, me.device)),
          const SizedBox(height: TainaSpacing.space5),
          _section(
            'Comunidade',
            TainaRowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TainaText(
                    tekoa.name,
                    style: TainaTypography.label,
                    color: TainaPalette.textPrimary,
                  ),
                  const SizedBox(height: TainaSpacing.space1),
                  TainaText(
                    widget.hostDisplay ?? tekoa.domain,
                    style: TainaTypography.monoSm,
                    color: TainaPalette.textMuted,
                  ),
                  if (widget.cleartext) ...[
                    const SizedBox(height: TainaSpacing.space2),
                    const TainaCleartextNotice(),
                  ],
                  if (model.version case final String version) ...[
                    const SizedBox(height: TainaSpacing.space2),
                    TainaText(
                      'Versão da caixa: $version',
                      style: TainaTypography.bodySm,
                      color: TainaPalette.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (quota != null) ...[
            const SizedBox(height: TainaSpacing.space5),
            _section(
              'Espaço',
              TainaRowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TainaText(
                      '${TainaFormat.bytes(tekoa.storageUsedBytes)} de '
                      '${TainaFormat.bytes(quota)}',
                      style: TainaTypography.monoSm,
                      color: TainaPalette.textPrimary,
                    ),
                    const SizedBox(height: TainaSpacing.space2),
                    ClipRRect(
                      borderRadius: TainaRadii.smAll,
                      child: LinearProgressIndicator(
                        value: quota <= 0
                            ? 0
                            : (tekoa.storageUsedBytes / quota)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                        color: TainaPalette.serviceYbira,
                        backgroundColor: TainaPalette.surfaceRaised,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: TainaSpacing.space5),
          TainaSecondaryButton(
            label: _leaving ? 'Saindo...' : 'Sair da comunidade',
            textColor: TainaPalette.feedbackError,
            onPressed: _leaving ? null : () => unawaited(_signOut(context)),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TainaText(
          title,
          style: TainaTypography.overline,
          uppercase: true,
          color: TainaPalette.textMuted,
        ),
        const SizedBox(height: TainaSpacing.space2),
        content,
      ],
    );
  }

  /// The self-service password change: the current one proves who is asking,
  /// the two new ones are the app's own check, and the box's answer lands as
  /// field messages or the success line.
  Widget _passwordForm(BuildContext context, AccountModel model) {
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TainaTextField(
            label: 'Senha atual',
            controller: widget.currentPassword,
            obscureText: true,
            errorMessages: model.currentPasswordErrors,
            autofillHints: const [AutofillHints.password],
          ),
          const SizedBox(height: TainaSpacing.space3),
          TainaTextField(
            label: 'Senha nova',
            controller: widget.newPassword,
            obscureText: true,
            errorMessages: model.newPasswordErrors,
            autofillHints: const [AutofillHints.newPassword],
            placeholder: 'mínimo 8 caracteres',
          ),
          const SizedBox(height: TainaSpacing.space3),
          TainaTextField(
            label: 'Confirme a senha nova',
            controller: widget.confirmation,
            obscureText: true,
            errorMessages: [if (model.mismatch case final String m) m],
            autofillHints: const [AutofillHints.newPassword],
            placeholder: 'a mesma senha',
          ),
          if (model.passwordFailure case final TainaError failure) ...[
            const SizedBox(height: TainaSpacing.space2),
            TainaText(
              failure.message,
              style: TainaTypography.bodySm,
              color: TainaPalette.feedbackError,
            ),
          ],
          if (model.changed) ...[
            const SizedBox(height: TainaSpacing.space2),
            TainaText(
              'Senha trocada. Nos outros aparelhos, é preciso entrar de novo '
              'com a senha nova.',
              style: TainaTypography.bodySm,
              color: TainaPalette.feedbackSuccess,
            ),
          ],
          const SizedBox(height: TainaSpacing.space3),
          TainaPrimaryButton(
            label: 'Trocar minha senha',
            loading: model.changing,
            onPressed: model.changing
                ? null
                : () => unawaited(_changePassword(model)),
          ),
        ],
      ),
    );
  }

  Widget _devicesSection(
    BuildContext context,
    AccountModel model,
    DeviceToken? current,
  ) {
    final TainaError? devicesError = model.devicesError;
    if (devicesError != null) {
      return TainaErrorState(error: devicesError, onRetry: model.loadDevices);
    }
    final List<DeviceToken>? devices = model.devices;
    if (devices == null) {
      return const TainaRowCard(
        child: Row(
          children: [
            SizedBox(
              width: TainaSizes.controlSm / 2,
              height: TainaSizes.controlSm / 2,
              child: CircularProgressIndicator(
                strokeWidth: TainaSizes.thick,
                color: TainaPalette.textMuted,
                semanticsLabel: 'Carregando',
              ),
            ),
            Spacer(),
          ],
        ),
      );
    }
    if (devices.isEmpty) {
      return const TainaEmptyState(
        icon: Icons.phone_iphone,
        title: 'Nenhum aparelho',
        message: 'Os aparelhos que entram na sua conta aparecem aqui.',
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final DeviceToken device in devices)
          Padding(
            padding: const EdgeInsets.only(bottom: TainaSpacing.space2),
            child: _deviceRow(context, model, device, current),
          ),
      ],
    );
  }

  Widget _deviceRow(
    BuildContext context,
    AccountModel model,
    DeviceToken device,
    DeviceToken? current,
  ) {
    final bool isCurrent = device.publicId == current?.publicId;
    final bool revoked = device.revokedAt != null;
    final bool working = model.revokingDevice == device.publicId;
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TainaText(
                  device.name,
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCurrent)
                TainaText(
                  'Este aparelho',
                  style: TainaTypography.caption,
                  color: TainaPalette.textSecondary,
                ),
            ],
          ),
          const SizedBox(height: TainaSpacing.space1),
          TainaText(
            AccountModel.deviceLine(device),
            style: TainaTypography.monoSm,
            color: revoked
                ? TainaPalette.textMuted
                : TainaPalette.textSecondary,
          ),
          if (isCurrent) ...[
            const SizedBox(height: TainaSpacing.space2),
            TainaText(
              'Identificação deste aparelho',
              style: TainaTypography.caption,
              color: TainaPalette.textMuted,
            ),
            SelectableText(
              device.publicId,
              maxLines: 1,
              style: TainaTypography.monoSm.copyWith(
                color: TainaPalette.textMuted,
              ),
            ),
            TainaText(
              'É assim que a comunidade distingue este aparelho dos outros.',
              style: TainaTypography.caption,
              color: TainaPalette.textMuted,
            ),
          ],
          if (!revoked && !isCurrent) ...[
            const SizedBox(height: TainaSpacing.space2),
            TainaSecondaryButton(
              label: 'Revogar',
              textColor: TainaPalette.feedbackError,
              onPressed: working
                  ? null
                  : () => unawaited(_revoke(context, model, device)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refresh(BuildContext context, AccountModel model) async {
    await model.load();
    final TainaError? error = model.actionError;
    if (error != null) {
      model.clearActionError();
      if (context.mounted) _showFailure(context, error);
    }
  }

  Future<void> _changePassword(AccountModel model) async {
    final bool accepted = await model.changePassword(
      current: widget.currentPassword.text,
      newPassword: widget.newPassword.text,
      confirmation: widget.confirmation.text,
    );
    if (accepted) {
      widget.currentPassword.clear();
      widget.newPassword.clear();
      widget.confirmation.clear();
    }
  }

  Future<void> _revoke(
    BuildContext context,
    AccountModel model,
    DeviceToken device,
  ) async {
    final bool confirmed = await _confirm(
      context,
      title: 'Revogar o acesso deste aparelho?',
      primary: 'Revogar',
      message:
          '"${device.name}" perde o acesso à comunidade. Para voltar, é '
          'preciso entrar de novo nele.',
    );
    if (!confirmed || !context.mounted) return;
    final result = await model.revokeDevice(device.publicId);
    if (result case Err(:final error)) {
      if (context.mounted) _showFailure(context, error);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final bool confirmed = await _confirm(
      context,
      title: 'Sair da comunidade?',
      primary: 'Sair',
      message:
          'Ao sair, este aparelho perde o acesso à comunidade. Para voltar, '
          'entre de novo com o seu usuário e senha.',
    );
    if (!confirmed || !mounted) return;
    setState(() => _leaving = true);
    await widget.onSignOut();
    if (mounted) setState(() => _leaving = false);
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
