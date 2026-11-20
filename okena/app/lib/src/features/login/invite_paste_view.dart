import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_model.dart';
import 'invite_paste_view_model.dart';
import 'invite_qr_scanner.dart';

/// A standalone invite-entry screen that can also be placed on a route.
final class InvitePasteView extends StatelessWidget {
  const InvitePasteView({
    required this.session,
    this.scanner,
    this.onBack,
    super.key,
  });

  final SessionModel session;
  final InviteQrScanner? scanner;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InvitePasteViewModel>(
      create: (_) => InvitePasteViewModel(session: session),
      child: _InvitePasteBody(
        session: session,
        scanner: scanner ?? const MobileInviteQrScanner(),
        onBack: onBack,
      ),
    );
  }
}

final class _InvitePasteBody extends StatefulWidget {
  const _InvitePasteBody({
    required this.session,
    required this.scanner,
    required this.onBack,
  });

  final SessionModel session;
  final InviteQrScanner scanner;
  final VoidCallback? onBack;

  @override
  State<_InvitePasteBody> createState() => _InvitePasteBodyState();
}

final class _InvitePasteBodyState extends State<_InvitePasteBody> {
  final TextEditingController _link = TextEditingController();
  final TextEditingController _address = TextEditingController();
  late final Future<bool> _scannerAvailable;
  bool _scanHandled = false;

  @override
  void initState() {
    super.initState();
    _scannerAvailable = widget.scanner.isSupported
        ? widget.scanner.isAvailable()
        : Future<bool>.value(false);
  }

  @override
  void dispose() {
    _link.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<InvitePasteViewModel>();
    final needsAddress = widget.session.host == null;

    return Scaffold(
      backgroundColor: TainaPalette.bgDeep,
      body: SafeArea(
        child: Padding(
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
                  action:
                      widget.onBack ?? () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: TainaSpacing.space4),
                      const TainaText(
                        'Colar um convite',
                        style: TainaTypography.h1,
                        color: TainaPalette.textPrimary,
                      ),
                      const SizedBox(height: TainaSpacing.space2),
                      const TainaText(
                        'Cole o link ou o código que você recebeu.',
                        style: TainaTypography.body,
                        color: TainaPalette.textSecondary,
                      ),
                      const SizedBox(height: TainaSpacing.space5),
                      TainaField(
                        label: 'Link ou código do convite',
                        controller: _link,
                        kind: TainaFieldKind.text,
                        placeholder: 'ex.: taina.local/convite/abc123',
                        help: 'Cole o link inteiro ou só o código.',
                        errorMessages: [
                          if (model.problem != null) model.problem!,
                        ],
                        keyboardType: TextInputType.url,
                        autofillHints: const [AutofillHints.url],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _open(model),
                      ),
                      const SizedBox(height: TainaSpacing.space2),
                      FutureBuilder<bool>(
                        future: _scannerAvailable,
                        builder: (context, snapshot) {
                          if (snapshot.data != true) {
                            return const SizedBox.shrink();
                          }
                          return Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TainaButton(
                              title: 'Ler QR code',
                              kind: TainaButtonKind.ghost,
                              size: TainaButtonSize.sm,
                              icon: TainaIcon.qr,
                              action: () => _readQr(model),
                            ),
                          );
                        },
                      ),
                      if (needsAddress) ...[
                        const SizedBox(height: TainaSpacing.space3),
                        TainaField(
                          label: 'Endereço da comunidade',
                          kind: TainaFieldKind.address,
                          controller: _address,
                          placeholder: 'ex.: taina.local',
                          help: 'O código sozinho não diz qual é a comunidade.',
                          onChanged: (_) {
                            setState(() {});
                            model.clearProblem();
                          },
                        ),
                        if (_isCleartext(_address.text)) ...[
                          const SizedBox(height: TainaSpacing.space3),
                          const ConnectionNotice(),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: TainaSpacing.space3),
              TainaButton(
                title: 'Continuar',
                kind: TainaButtonKind.primary,
                size: TainaButtonSize.lg,
                loading: model.opening,
                action: () => _open(model),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isCleartext(String address) {
    final parsed = InstanceAddress.parse(address);
    return parsed.value?.isCleartext ?? false;
  }

  Future<void> _open(InvitePasteViewModel model) => model.open(
    _link.text,
    address: _address.text,
    confirmCommunitySwitch: _confirmCommunitySwitch,
  );

  Future<bool> _confirmCommunitySwitch(
    InstanceAddress nextAddress,
    String communityName,
  ) async {
    final destination = communityName == nextAddress.display
        ? communityName
        : '$communityName (${nextAddress.display})';
    final confirmed = await TainaDialog.confirm(
      context: context,
      title: 'Trocar comunidade?',
      message:
          'Este convite é da comunidade $destination. Quer trocar a '
          'comunidade conectada para continuar?',
      confirmLabel: 'Trocar',
    );
    return confirmed == true;
  }

  Future<void> _readQr(InvitePasteViewModel model) {
    _scanHandled = false;
    return TainaSheet.show<void>(
      context: context,
      title: 'Ler QR code',
      child: SizedBox(
        height: 320,
        child: widget.scanner.build(
          onCapture: (value) => _captured(value, model),
        ),
      ),
    );
  }

  void _captured(String value, InvitePasteViewModel model) {
    if (_scanHandled) return;
    _scanHandled = true;
    Navigator.of(context).maybePop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _link.text = value;
      _open(model);
    });
  }
}
