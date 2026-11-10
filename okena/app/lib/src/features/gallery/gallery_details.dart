import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_core/okena_core.dart';

import 'gallery_model.dart';

/// Opens the details sheet, the web's photo-details modal.
Future<void> showGalleryDetails(BuildContext context, FileRecord file) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => GalleryDetailsSheet(file: file),
  );
}

/// The zone first (the product's promise, legible where the content lives),
/// then the facts.
final class GalleryDetailsSheet extends StatelessWidget {
  const GalleryDetailsSheet({required this.file, super.key});

  final FileRecord file;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        TainaSpacing.space5,
        0,
        TainaSpacing.space5,
        TainaSpacing.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const TainaText(
            'Detalhes',
            style: TainaTypography.h3,
            color: TainaPalette.textPrimary,
          ),
          const SizedBox(height: TainaSpacing.space4),
          _zone,
          const SizedBox(height: TainaSpacing.space4),
          _row('Nome original', file.name),
          const SizedBox(height: TainaSpacing.space4),
          _row('Tipo', GalleryModel.humanType(file.mime)),
          const SizedBox(height: TainaSpacing.space4),
          _row('Tamanho', TainaFormat.bytes(file.size)),
          const SizedBox(height: TainaSpacing.space4),
          _row('Enviado em', TainaFormat.date(file.createdAt)),
          const SizedBox(height: TainaSpacing.space4),
          _signature,
        ],
      ),
    );
  }

  Widget get _zone {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TainaText(
          'Zona',
          style: TainaTypography.overline,
          uppercase: true,
          color: TainaPalette.textMuted,
        ),
        const SizedBox(height: TainaSpacing.space1),
        _badge(file.zona),
        const SizedBox(height: TainaSpacing.space1),
        TainaText(
          GalleryModel.zoneSentence(file.zona),
          style: TainaTypography.caption,
          color: TainaPalette.textMuted,
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TainaText(
          label,
          style: TainaTypography.overline,
          uppercase: true,
          color: TainaPalette.textMuted,
        ),
        const SizedBox(height: TainaSpacing.space1),
        SelectableText(
          value,
          style: TainaTypography.body.copyWith(color: TainaPalette.textPrimary),
        ),
      ],
    );
  }

  Widget get _signature {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TainaText(
          'Assinatura do arquivo',
          style: TainaTypography.overline,
          uppercase: true,
          color: TainaPalette.textMuted,
        ),
        const SizedBox(height: TainaSpacing.space1),
        SelectableText(
          file.sha256,
          maxLines: 2,
          style: TainaTypography.monoSm.copyWith(
            color: TainaPalette.textPrimary,
          ),
        ),
        const SizedBox(height: TainaSpacing.space1),
        const TainaText(
          'É como o Tainá confere que o arquivo está intacto.',
          style: TainaTypography.caption,
          color: TainaPalette.textMuted,
        ),
      ],
    );
  }
}

Widget _badge(Zona zona) => zona == Zona.casa
    ? const TainaZonaBadge.casa()
    : const TainaZonaBadge.praca();
