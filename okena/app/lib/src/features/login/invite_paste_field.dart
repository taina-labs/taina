import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_model.dart';
import 'invite_paste_view_model.dart';

/// The paste field of the invite link, on the two screens where the app can
/// still be pointed at a community.
///
/// The link arrives as text or as a QR shot, in either of the box's two
/// shapes, and goes through the same deep-link path a tapped link takes. What
/// cannot open comes back as a sentence under the field.
final class InvitePasteField extends StatelessWidget {
  const InvitePasteField({required this.session, super.key});

  final SessionModel session;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InvitePasteViewModel>(
      create: (_) => InvitePasteViewModel(session: session),
      child: const _InvitePasteForm(),
    );
  }
}

final class _InvitePasteForm extends StatefulWidget {
  const _InvitePasteForm();

  @override
  State<_InvitePasteForm> createState() => _InvitePasteFormState();
}

final class _InvitePasteFormState extends State<_InvitePasteForm> {
  final TextEditingController _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<InvitePasteViewModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: TainaSpacing.space2,
      children: [
        const TainaText(
          'Chegou por um convite?',
          style: TainaTypography.overline,
          uppercase: true,
          color: TainaPalette.textMuted,
        ),
        TainaTextField(
          label: 'Cole aqui o link do convite',
          controller: _link,
          errorMessages: model.problem == null ? const [] : [model.problem!],
          keyboardType: TextInputType.url,
          autofillHints: const [AutofillHints.url],
          placeholder: 'taina://convite/... ou https://.../convite/...',
          help: 'É o link que a comunidade mandou, por mensagem ou no QR code.',
        ),
        TainaSecondaryButton(
          label: 'Abrir o convite',
          onPressed: () {
            model.open(_link.text);
          },
        ),
      ],
    );
  }
}
