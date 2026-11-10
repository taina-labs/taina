import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_model.dart';
import '../login/invite_paste_field.dart';
import 'setup_view_model.dart';

/// The first screen: the address of the community's box, and the invite link
/// for the person who arrived with one.
///
/// One address field, one button, one paste field, and an honest answer for
/// every outcome.
final class SetupView extends StatelessWidget {
  const SetupView({required this.session, super.key});

  final SessionModel session;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SetupViewModel>(
      create: (_) => SetupViewModel(session: session),
      child: _SetupForm(session: session),
    );
  }
}

final class _SetupForm extends StatefulWidget {
  const _SetupForm({required this.session});

  final SessionModel session;

  @override
  State<_SetupForm> createState() => _SetupFormState();
}

final class _SetupFormState extends State<_SetupForm> {
  final TextEditingController _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _connect(SetupViewModel model) => model.connect(_address.text);

  @override
  Widget build(BuildContext context) {
    final model = context.watch<SetupViewModel>();
    final failure = model.failure;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TainaSpacing.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: TainaSpacing.space5,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: TainaSpacing.space2,
                children: [
                  const TainaText(
                    'Sua comunidade',
                    style: TainaTypography.h1,
                    color: TainaPalette.textPrimary,
                  ),
                  const TainaText(
                    'Tainá guarda os arquivos da sua comunidade numa caixa só '
                    'dela. Digite o endereço dessa caixa: quem instalou passou '
                    'um endereço parecido com taina.minhacasa.ts.net.',
                    style: TainaTypography.body,
                    color: TainaPalette.textSecondary,
                  ),
                ],
              ),
              TainaTextField(
                label: 'Endereço da comunidade',
                controller: _address,
                keyboardType: TextInputType.url,
                autofillHints: const [AutofillHints.url],
                onChanged: (_) => setState(() {}),
              ),
              TainaPrimaryButton(
                label: 'Conectar',
                loading: model.probing,
                onPressed: () => _connect(model),
              ),
              if (model.typedCleartext(_address.text))
                const TainaCleartextNotice(),
              if (model.instance != null && !model.instance!.bootstrapped)
                const _UnbootstrappedCard(),
              if (failure != null)
                if (SetupViewModel.unreachable(failure))
                  _UnreachableCard(onRetry: () => _connect(model))
                else
                  TainaErrorState(
                    error: failure,
                    onRetry: () => _connect(model),
                  ),
              InvitePasteField(session: widget.session),
            ],
          ),
        ),
      ),
    );
  }
}

/// The box answered but no community was created there yet: the address is
/// not kept, and Setup explains it.
final class _UnbootstrappedCard extends StatelessWidget {
  const _UnbootstrappedCard();

  @override
  Widget build(BuildContext context) {
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: TainaSpacing.space2,
        children: const [
          TainaText(
            'A comunidade ainda não foi criada',
            style: TainaTypography.label,
            color: TainaPalette.feedbackWarning,
          ),
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

/// Nothing answered at this address, on either scheme: the one failure where
/// the person can act, so it names what to check instead of the generic
/// "verifique a conexão".
final class _UnreachableCard extends StatelessWidget {
  const _UnreachableCard({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TainaSpacing.space5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: TainaFontSizes.xxl,
            color: TainaPalette.feedbackWarning,
          ),
          const SizedBox(height: TainaSpacing.space4),
          const TainaText(
            SetupViewModel.unreachableMessage,
            style: TainaTypography.body,
            color: TainaPalette.textSecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: TainaSpacing.space4),
          TainaSecondaryButton(
            label: 'Tentar de novo',
            onPressed: () {
              onRetry();
            },
          ),
        ],
      ),
    );
  }
}
