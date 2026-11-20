import 'package:flutter/material.dart';

import '../tokens.dart';
import 'icons.dart';
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
/// Feature agents map the wire zone to one of the two named constructors.
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
          TainaIconView(
            icon: _casa ? TainaIcon.casa : TainaIcon.praca,
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
