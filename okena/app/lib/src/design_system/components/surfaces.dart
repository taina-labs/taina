import 'package:flutter/material.dart';

import '../tokens.dart';
import 'text.dart';

/// A list row surface: `surface-default` fill, `border-subtle` stroke,
/// `radius-lg`, `space-4` padding. Pass [onTap] when the whole row acts.
final class TainaRowCard extends StatelessWidget {
  const TainaRowCard({
    required this.child,
    this.padding = const EdgeInsets.all(TainaSpacing.space4),
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: TainaPalette.surfaceDefault,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: TainaRadii.lgAll,
          side: BorderSide(
            color: TainaPalette.borderSubtle,
            width: TainaSizes.hairline,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: TainaRadii.lgAll,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// The casa / praça mark, wherever a file or folder appears: the product's
/// core promise, in `service-ybira` for Casa and `service-jaci` for Praça.
///
/// No padlock on Casa: its privacy is a software promise, not a cryptographic
/// one, so the glyph says home. Feature agents map the wire zone to one of the
/// two named constructors.
final class TainaZonaBadge extends StatelessWidget {
  const TainaZonaBadge.casa({super.key}) : _casa = true;

  const TainaZonaBadge.praca({super.key}) : _casa = false;

  final bool _casa;

  @override
  Widget build(BuildContext context) {
    final Color color = _casa
        ? TainaPalette.serviceYbira
        : TainaPalette.serviceJaci;
    final Color soft = _casa
        ? TainaPalette.serviceYbiraSoft
        : TainaPalette.serviceJaciSoft;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TainaSpacing.space2,
        vertical: TainaSpacing.space1,
      ),
      decoration: BoxDecoration(color: soft, borderRadius: TainaRadii.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _casa ? Icons.home_rounded : Icons.people_rounded,
            size: TainaFontSizes.sm,
            color: color,
          ),
          const SizedBox(width: TainaSpacing.space1),
          TainaText(
            _casa ? TainaWords.casa : TainaWords.praca,
            style: TainaTypography.caption,
            color: color,
          ),
        ],
      ),
    );
  }
}

/// The path to the box has no TLS. Not a blocker, and never silent: a private
/// network (a tailnet, a VPN) already encrypts the path under the app's feet,
/// and outside one it does not. Shown where the address is typed, and on the
/// account screen, where it still matters later.
final class TainaCleartextNotice extends StatelessWidget {
  const TainaCleartextNotice({super.key});

  static const String message =
      'Esta comunidade responde sem criptografia (http). Numa rede privada, '
      'como uma VPN, o caminho já vai protegido; fora dela, não.';

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.lock_open,
          size: TainaFontSizes.sm,
          color: TainaPalette.feedbackWarning,
        ),
        const SizedBox(width: TainaSpacing.space2),
        Expanded(
          child: TainaText(
            message,
            style: TainaTypography.caption,
            color: TainaPalette.feedbackWarning,
          ),
        ),
      ],
    );
  }
}
