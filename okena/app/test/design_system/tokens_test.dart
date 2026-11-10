import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';

void main() {
  group('semantic palette', () {
    test('carries the night values of tokens.css', () {
      expect(TainaPalette.bgApp.toARGB32(), 0xFF0A101F);
      expect(TainaPalette.bgDeep.toARGB32(), 0xFF060A14);
      expect(TainaPalette.bgQr.toARGB32(), 0xFFFAF7F0);
      expect(TainaPalette.bgViewer.toARGB32(), 0xFF060A14);

      expect(TainaPalette.surfaceDefault.toARGB32(), 0xFF0F1729);
      expect(TainaPalette.surfaceRaised.toARGB32(), 0xFF15203A);
      expect(TainaPalette.surfaceHigh.toARGB32(), 0xFF1D2C4E);
      expect(TainaPalette.surfaceOverlay.toARGB32(), 0xE00A101F);
      expect(TainaPalette.surfaceDim.toARGB32(), 0xFF28395F);
      expect(TainaPalette.surfaceScrim.toARGB32(), 0xA3060A14);
      expect(TainaPalette.surfaceScrimStrong.toARGB32(), 0x80060A14);
      expect(TainaPalette.surfaceTintBrand.toARGB32(), 0x14F2A65A);

      expect(TainaPalette.borderSubtle.toARGB32(), 0xFF15203A);
      expect(TainaPalette.borderDefault.toARGB32(), 0xFF1D2C4E);
      expect(TainaPalette.borderStrong.toARGB32(), 0xFF28395F);

      expect(TainaPalette.textPrimary.toARGB32(), 0xFFFAF7F0);
      expect(TainaPalette.textSecondary.toARGB32(), 0xFFBFC8DF);
      expect(TainaPalette.textMuted.toARGB32(), 0xFF8C9AC0);
      expect(TainaPalette.textFaint.toARGB32(), 0xFF56689B);
      expect(TainaPalette.textOnBrand.toARGB32(), 0xFF060A14);

      expect(TainaPalette.brandPrimary.toARGB32(), 0xFFF2A65A);
      expect(TainaPalette.brandPrimaryHover.toARGB32(), 0xFFFCBE74);
      expect(TainaPalette.brandPrimaryPressed.toARGB32(), 0xFFDD8A3E);
      expect(TainaPalette.brandEmber.toARGB32(), 0xFFE2674A);

      expect(TainaPalette.fieldBg.toARGB32(), 0x990F1729);
    });

    test('keeps the service accent meanings', () {
      expect(TainaPalette.serviceYbira, TainaPrimitives.forest500);
      expect(TainaPalette.serviceYbiraSoft, TainaPrimitives.forest900);
      expect(TainaPalette.serviceYbiraHover, TainaPrimitives.forest400);
      expect(TainaPalette.serviceYbiraTint, TainaPrimitives.forest300);

      expect(TainaPalette.serviceJaci, TainaPrimitives.moon500);
      expect(TainaPalette.serviceJaciSoft, TainaPrimitives.moon900);
      expect(TainaPalette.serviceJaciTint, TainaPrimitives.moon400);

      expect(TainaPalette.serviceNhaman, TainaPrimitives.sky500);
      expect(TainaPalette.serviceVideo, TainaPrimitives.sky300);
      expect(TainaPalette.serviceGuara, TainaPrimitives.guara500);

      expect(TainaPalette.serviceMaraca, TainaPrimitives.ember500);
      expect(TainaPalette.serviceMaracaSoft.toARGB32(), 0x29E2674A);
      expect(TainaPalette.serviceMaracaTint, TainaPrimitives.ember400);

      expect(TainaPalette.feedbackSuccess, TainaPrimitives.forest400);
      expect(TainaPalette.feedbackWarning, TainaPrimitives.amber500);
      expect(TainaPalette.feedbackError, TainaPrimitives.red500);
      expect(TainaPalette.feedbackInfo, TainaPrimitives.sky500);

      expect(TainaPalette.avatarTint0.toARGB32(), 0x29F2A65A);
      expect(TainaPalette.avatarTint1.toARGB32(), 0x293FA171);
      expect(TainaPalette.avatarTint2.toARGB32(), 0x29E3BC66);
      expect(TainaPalette.avatarTint3.toARGB32(), 0x295BA3F5);
    });
  });

  group('scale', () {
    test('spacing follows the CSS scale', () {
      expect(
        [
          TainaSpacing.space1,
          TainaSpacing.space2,
          TainaSpacing.space3,
          TainaSpacing.space4,
          TainaSpacing.space5,
          TainaSpacing.space6,
          TainaSpacing.space8,
          TainaSpacing.space10,
          TainaSpacing.space12,
          TainaSpacing.space16,
        ],
        [4, 8, 12, 16, 20, 24, 32, 40, 48, 64],
      );
    });

    test('radii follow the CSS scale', () {
      expect(
        [TainaRadii.sm, TainaRadii.md, TainaRadii.lg, TainaRadii.xl],
        [8, 12, 16, 24],
      );
      expect(TainaRadii.pill, 999);
      expect(TainaRadii.mdAll.topLeft.x, TainaRadii.md);
    });

    test('control sizes and borders follow the CSS scale', () {
      expect(TainaSizes.touch, 44);
      expect(TainaSizes.controlSm, 36);
      expect(TainaSizes.controlMd, 48);
      expect(TainaSizes.controlLg, 56);
      expect(TainaSizes.navMobile, 72);
      expect(TainaSizes.appbar, 64);
      expect(TainaSizes.navDot, 6);
      expect(TainaSizes.hairline, 1);
      expect(TainaSizes.thick, 2);
      expect(TainaSizes.sidebar, 248);
      expect(TainaSizes.menuMin, 180);
      expect(TainaSizes.qr, 200);
      expect(TainaSizes.gapPhoto, 2);
      expect(TainaSizes.badge, 24);
      expect(TainaSizes.progress, 6);
    });

    test('opacity follows the CSS scale', () {
      expect(TainaOpacity.disabled, 0.4);
      expect(TainaOpacity.muted, 0.72);
      expect(TainaOpacity.scrim, 0.64);
    });

    test('elevation keeps the CSS shadows', () {
      expect(TainaElevation.soft, hasLength(1));
      expect(TainaElevation.soft.single.offset, const Offset(0, 4));
      expect(TainaElevation.soft.single.blurRadius, 16);
      expect(TainaElevation.soft.single.spreadRadius, 0);
      expect(TainaElevation.soft.single.color.toARGB32(), 0x80060A14);

      expect(TainaElevation.lifted, hasLength(1));
      expect(TainaElevation.lifted.single.offset, const Offset(0, 12));
      expect(TainaElevation.lifted.single.blurRadius, 32);
      expect(TainaElevation.lifted.single.spreadRadius, -4);
      expect(TainaElevation.lifted.single.color.toARGB32(), 0xA6060A14);
    });
  });

  group('typography', () {
    test('names the three shipped families', () {
      expect(TainaFonts.display, 'Bricolage Grotesque');
      expect(TainaFonts.body, 'Schibsted Grotesk');
      expect(TainaFonts.mono, 'JetBrains Mono');
    });

    test('display, headings and body carry size, weight and line height', () {
      expect(TainaTypography.display.fontFamily, TainaFonts.display);
      expect(TainaTypography.display.fontSize, 44);
      expect(TainaTypography.display.fontWeight, FontWeight.w700);
      expect(TainaTypography.display.letterSpacing, -0.5);
      expect(TainaTypography.display.height, 1.05);

      expect(TainaTypography.h1.fontSize, 36);
      expect(TainaTypography.h1.height, 1.1);
      expect(TainaTypography.h2.fontSize, 28);
      expect(TainaTypography.h2.fontWeight, FontWeight.w600);
      expect(TainaTypography.h2.height, 1.15);
      expect(TainaTypography.h3.fontSize, 18);
      expect(TainaTypography.h3.height, 1.25);

      expect(TainaTypography.body.fontFamily, TainaFonts.body);
      expect(TainaTypography.body.fontSize, 16);
      expect(TainaTypography.body.height, 1.5);
      expect(TainaTypography.bodySm.fontSize, 14);
      expect(TainaTypography.bodySm.height, 1.45);
    });

    test('label, caption and overline carry their weights and tracking', () {
      expect(TainaTypography.label.fontSize, 14);
      expect(TainaTypography.label.fontWeight, FontWeight.w600);
      expect(TainaTypography.label.height, 1.2);

      expect(TainaTypography.caption.fontSize, 12);
      expect(TainaTypography.caption.fontWeight, FontWeight.w500);
      expect(TainaTypography.caption.height, 1.3);

      expect(TainaTypography.overline.fontSize, 12);
      expect(TainaTypography.overline.fontWeight, FontWeight.w600);
      expect(TainaTypography.overline.letterSpacing, 1.5);
      expect(TainaTypography.overline.height, 1.2);
    });

    test('mono-sm uses tabular figures', () {
      expect(TainaTypography.monoSm.fontFamily, TainaFonts.mono);
      expect(TainaTypography.monoSm.fontSize, 13);
      expect(TainaTypography.monoSm.height, 1.4);
      expect(
        TainaTypography.monoSm.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test('words match the wire vocabulary', () {
      expect(TainaWords.casa, 'Casa');
      expect(TainaWords.praca, 'Praça');
      expect(TainaWords.zelador, 'Zelador');
      expect(TainaWords.morador, 'Morador');
    });
  });

  group('theme', () {
    test('is dark and maps the semantic tokens', () {
      final ThemeData theme = TainaTheme.data;

      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, TainaPalette.bgApp);
      expect(theme.canvasColor, TainaPalette.bgApp);
      expect(theme.colorScheme.primary, TainaPalette.brandPrimary);
      expect(theme.colorScheme.onPrimary, TainaPalette.textOnBrand);
      expect(theme.colorScheme.surface, TainaPalette.surfaceDefault);
      expect(theme.colorScheme.onSurface, TainaPalette.textPrimary);
      expect(theme.colorScheme.error, TainaPalette.feedbackError);
      expect(theme.colorScheme.outline, TainaPalette.borderDefault);
      expect(theme.colorScheme.surfaceTint, Colors.transparent);
    });

    test('text theme uses the design families and colors', () {
      final ThemeData theme = TainaTheme.data;

      expect(theme.textTheme.displayLarge?.fontFamily, TainaFonts.display);
      expect(theme.textTheme.bodyMedium?.fontFamily, TainaFonts.body);
      expect(theme.textTheme.bodyMedium?.color, TainaPalette.textPrimary);
      expect(
        theme.textTheme.labelSmall?.fontFamily,
        TainaTypography.caption.fontFamily,
      );
    });

    test('app bar and controls agree with the tokens', () {
      final ThemeData theme = TainaTheme.data;

      expect(theme.appBarTheme.backgroundColor, TainaPalette.bgApp);
      expect(theme.appBarTheme.toolbarHeight, TainaSizes.appbar);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.dialogTheme.backgroundColor, TainaPalette.surfaceDefault);
      expect(
        theme.bottomSheetTheme.backgroundColor,
        TainaPalette.surfaceDefault,
      );
      expect(theme.dividerTheme.color, TainaPalette.borderSubtle);
      expect(theme.progressIndicatorTheme.color, TainaPalette.brandPrimary);
    });
  });
}
