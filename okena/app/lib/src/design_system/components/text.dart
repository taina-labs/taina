import 'package:flutter/material.dart';

/// A [Text] that owns the two decisions a type style carries besides font
/// metrics: the color override and the uppercase text case of the overline.
///
/// ```dart
/// TainaText('Mural', style: TainaTypography.overline, uppercase: true)
/// ```
final class TainaText extends StatelessWidget {
  const TainaText(
    this.text, {
    required this.style,
    this.uppercase = false,
    this.color,
    this.textAlign,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final String text;
  final TextStyle style;

  /// The `type-overline` text case. Leave false for every other style.
  final bool uppercase;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      uppercase ? text.toUpperCase() : text,
      style: color == null ? style : style.copyWith(color: color),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
