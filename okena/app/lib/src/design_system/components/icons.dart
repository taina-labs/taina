import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../tokens.dart';

/// The icon glyphs mirrored by the Tainá web design system.
enum TainaIcon {
  home,
  folder,
  image,
  user,
  search,
  servidor,
  plus,
  upload,
  chevL,
  chevR,
  kebab,
  trash,
  grid,
  check,
  download,
  close,
  clock,
  qr,
  link,
  dots,
  info,
  shield,
  file,
  warning,
  restore,
  praca,
  casa,
  lixeira,
  mural,
  saude,
  moradores,
  pedidos,
  privacidade,
  senha,
  dispositivos,
  sair,
  x;

  String get assetName => name;
}

/// Renders one local design-system SVG. Icons are decorative unless a
/// [semanticsLabel] is supplied by the caller.
final class TainaIconView extends StatelessWidget {
  const TainaIconView({
    required this.icon,
    this.size = TainaSizes.iconMd,
    this.color = TainaPalette.textSecondary,
    this.semanticsLabel,
    super.key,
  });

  final TainaIcon icon;
  final double size;
  final Color color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final Widget image = SvgPicture.asset(
      'assets/icons/${icon.assetName}.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );

    if (semanticsLabel case final String label) {
      return Semantics(image: true, label: label, child: image);
    }

    return ExcludeSemantics(child: image);
  }
}
