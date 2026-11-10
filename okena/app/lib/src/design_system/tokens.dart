import 'package:flutter/material.dart';

/// Raw palette, mirroring the primitives of `design/tokens.css`.
///
/// Components never consume these values: they use [TainaPalette] and the
/// other semantic groups. The list stays one to one with the CSS so a drift
/// check against `tokens.css` is a name by name comparison.
abstract final class TainaPrimitives {
  static const Color night950 = Color(0xFF060A14); // --color-night-950
  static const Color night900 = Color(0xFF0A101F); // --color-night-900
  static const Color night800 = Color(0xFF0F1729); // --color-night-800
  static const Color night700 = Color(0xFF15203A); // --color-night-700
  static const Color night600 = Color(0xFF1D2C4E); // --color-night-600
  static const Color night500 = Color(0xFF28395F); // --color-night-500
  static const Color night400 = Color(0xFF3A4D7A); // --color-night-400
  static const Color night300 = Color(0xFF56689B); // --color-night-300
  static const Color night200 = Color(0xFF8C9AC0); // --color-night-200
  static const Color night100 = Color(0xFFBFC8DF); // --color-night-100
  static const Color night50 = Color(0xFFEEF1F8); // --color-night-50

  static const Color dawn300 = Color(0xFFFFD9A3); // --color-dawn-300
  static const Color dawn400 = Color(0xFFFCBE74); // --color-dawn-400
  static const Color dawn500 = Color(0xFFF2A65A); // --color-dawn-500
  static const Color dawn600 = Color(0xFFDD8A3E); // --color-dawn-600
  static const Color dawn700 = Color(0xFFB96D2C); // --color-dawn-700
  static const Color dawn800 = Color(0xFFA35C1E); // --color-dawn-800

  static const Color ember400 = Color(0xFFF08A6C); // --color-ember-400
  static const Color ember500 = Color(0xFFE2674A); // --color-ember-500
  static const Color ember600 = Color(0xFFC44E33); // --color-ember-600

  static const Color star50 = Color(0xFFFAF7F0); // --color-star-50
  static const Color star100 = Color(0xFFF1ECDF); // --color-star-100
  static const Color star200 = Color(0xFFE4DCC8); // --color-star-200

  static const Color forest300 = Color(0xFF82CBA4); // --color-forest-300
  static const Color forest400 = Color(0xFF5FB88A); // --color-forest-400
  static const Color forest500 = Color(0xFF3FA171); // --color-forest-500
  static const Color forest600 = Color(0xFF2F8159); // --color-forest-600
  static const Color forest700 = Color(0xFF246244); // --color-forest-700
  static const Color forest900 = Color(0xFF122E22); // --color-forest-900

  static const Color moon300 = Color(0xFFF4DFA6); // --color-moon-300
  static const Color moon400 = Color(0xFFECCD80); // --color-moon-400
  static const Color moon500 = Color(0xFFE3BC66); // --color-moon-500
  static const Color moon600 = Color(0xFFC49A48); // --color-moon-600
  static const Color moon700 = Color(0xFF9C7836); // --color-moon-700
  static const Color moon900 = Color(0xFF46350F); // --color-moon-900

  static const Color guara500 = Color(0xFFDE5B3F); // --color-guara-500
  static const Color guara600 = Color(0xFFBE4327); // --color-guara-600

  static const Color sky300 = Color(0xFF92C3F8); // --color-sky-300
  static const Color sky500 = Color(0xFF5BA3F5); // --color-sky-500
  static const Color sky600 = Color(0xFF3F84D6); // --color-sky-600
  static const Color sky700 = Color(0xFF2F66AC); // --color-sky-700

  static const Color red500 = Color(0xFFE5484D); // --color-red-500
  static const Color red600 = Color(0xFFC03538); // --color-red-600
  static const Color amber500 = Color(0xFFEFB54A); // --color-amber-500
  static const Color amber700 = Color(0xFF8A6114); // --color-amber-700

  /// The white of the light block of `tokens.css`. Kept so the primitives
  /// mirror the CSS one to one; the app ships the night theme only.
  static const Color paper0 = Color(0xFFFFFFFF); // --color-paper-0
}

/// The semantic colors. The only colors a component consumes.
///
/// The app ships one theme, the night one (dark-first). A token carries the
/// night value of its `tokens.css` entry; the light block of the CSS is not
/// consumed. Translucent tokens are written as explicit ARGB values so the
/// palette stays constant.
abstract final class TainaPalette {
  static const Color bgApp = TainaPrimitives.night900; // --bg-app
  static const Color bgDeep = TainaPrimitives.night950; // --bg-deep
  static const Color bgQr = TainaPrimitives.star50; // --bg-qr
  static const Color bgViewer = TainaPrimitives.night950; // --bg-viewer

  static const Color surfaceDefault =
      TainaPrimitives.night800; // --surface-default
  static const Color surfaceRaised =
      TainaPrimitives.night700; // --surface-raised
  static const Color surfaceHigh = TainaPrimitives.night600; // --surface-high
  static const Color surfaceOverlay = Color(0xE00A101F); // --surface-overlay
  static const Color surfaceDim = TainaPrimitives.night500; // --surface-dim
  static const Color surfaceScrim = Color(0xA3060A14); // --surface-scrim
  static const Color surfaceScrimStrong = Color(
    0x80060A14,
  ); // --surface-scrim-strong
  static const Color surfaceTintBrand = Color(
    0x14F2A65A,
  ); // --surface-tint-brand

  static const Color borderSubtle = TainaPrimitives.night700; // --border-subtle
  static const Color borderDefault =
      TainaPrimitives.night600; // --border-default
  static const Color borderStrong = TainaPrimitives.night500; // --border-strong

  static const Color textPrimary = TainaPrimitives.star50; // --text-primary
  static const Color textSecondary =
      TainaPrimitives.night100; // --text-secondary
  static const Color textMuted = TainaPrimitives.night200; // --text-muted
  static const Color textFaint = TainaPrimitives.night300; // --text-faint
  static const Color textOnBrand = TainaPrimitives.night950; // --text-on-brand

  static const Color brandPrimary = TainaPrimitives.dawn500; // --brand-primary
  static const Color brandPrimaryHover =
      TainaPrimitives.dawn400; // --brand-primary-hover
  static const Color brandPrimaryPressed =
      TainaPrimitives.dawn600; // --brand-primary-pressed
  static const Color brandEmber = TainaPrimitives.ember500; // --brand-ember

  static const Color serviceYbira =
      TainaPrimitives.forest500; // --service-ybira
  static const Color serviceYbiraSoft =
      TainaPrimitives.forest900; // --service-ybira-soft
  static const Color serviceYbiraHover =
      TainaPrimitives.forest400; // --service-ybira-hover
  static const Color serviceYbiraTint =
      TainaPrimitives.forest300; // --service-ybira-tint
  static const Color serviceJaci = TainaPrimitives.moon500; // --service-jaci
  static const Color serviceJaciSoft =
      TainaPrimitives.moon900; // --service-jaci-soft
  static const Color serviceJaciTint =
      TainaPrimitives.moon400; // --service-jaci-tint
  static const Color serviceNhaman = TainaPrimitives.sky500; // --service-nhaman
  static const Color serviceVideo = TainaPrimitives.sky300; // --service-video
  static const Color serviceGuara = TainaPrimitives.guara500; // --service-guara

  /// Maracá (identity, access: members, mural, requests) owns its accent
  /// instead of borrowing another service's.
  static const Color serviceMaraca =
      TainaPrimitives.ember500; // --service-maraca
  static const Color serviceMaracaSoft = Color(
    0x29E2674A,
  ); // --service-maraca-soft
  static const Color serviceMaracaTint =
      TainaPrimitives.ember400; // --service-maraca-tint

  static const Color feedbackSuccess =
      TainaPrimitives.forest400; // --feedback-success
  static const Color feedbackWarning =
      TainaPrimitives.amber500; // --feedback-warning
  static const Color feedbackError = TainaPrimitives.red500; // --feedback-error
  static const Color feedbackInfo = TainaPrimitives.sky500; // --feedback-info

  /// Translucent tints for the deterministic avatar colors (hash -> 0..3).
  static const Color avatarTint0 = Color(0x29F2A65A); // --avatar-tint-0
  static const Color avatarTint1 = Color(0x293FA171); // --avatar-tint-1
  static const Color avatarTint2 = Color(0x29E3BC66); // --avatar-tint-2
  static const Color avatarTint3 = Color(0x295BA3F5); // --avatar-tint-3

  static const Color fieldBg = Color(0x990F1729); // --field-bg
}

/// Spacing scale, in logical pixels.
abstract final class TainaSpacing {
  static const double space1 = 4; // --space-1
  static const double space2 = 8; // --space-2
  static const double space3 = 12; // --space-3
  static const double space4 = 16; // --space-4
  static const double space5 = 20; // --space-5
  static const double space6 = 24; // --space-6
  static const double space8 = 32; // --space-8
  static const double space10 = 40; // --space-10
  static const double space12 = 48; // --space-12
  static const double space16 = 64; // --space-16
}

/// Corner radii. The `*All` helpers are the matching [BorderRadius] values.
abstract final class TainaRadii {
  static const double sm = 8; // --radius-sm
  static const double md = 12; // --radius-md
  static const double lg = 16; // --radius-lg
  static const double xl = 24; // --radius-xl
  static const double pill = 999; // --radius-pill

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Control and layout sizes, plus the border widths.
///
/// The web-only `--measure-*` container widths are intentionally absent:
/// the app lays out with the system, not with fixed widths.
abstract final class TainaSizes {
  static const double touch = 44; // --size-touch
  static const double controlSm = 36; // --size-control-sm
  static const double controlMd = 48; // --size-control-md
  static const double controlLg = 56; // --size-control-lg
  static const double navMobile = 72; // --size-nav-mobile
  static const double appbar = 64; // --size-appbar
  static const double navDot = 6; // --size-nav-dot

  static const double hairline = 1; // --border-hairline
  static const double thick = 2; // --border-thick

  static const double sidebar = 248; // --size-sidebar
  static const double menuMin = 180; // --size-menu-min
  static const double qr = 200; // --size-qr
  static const double gapPhoto = 2; // --gap-photo
  static const double badge = 24; // --size-badge
  static const double progress = 6; // --size-progress
}

/// Opacity scale, used for disabled and pressed states and for scrims.
abstract final class TainaOpacity {
  static const double disabled = 0.4; // --opacity-disabled
  static const double muted = 0.72; // --opacity-muted
  static const double scrim = 0.64; // --opacity-scrim
}

/// Elevation, translated from the CSS box shadows.
///
/// Flutter's [BoxShadow.blurRadius] follows the CSS blur value, so the token
/// is written as the CSS says (16 and 32) even though the SwiftUI port
/// halves it for its own shadow radius.
abstract final class TainaElevation {
  // --elevation-soft: 0 4px 16px 0 rgb(6 10 20 / 0.5)
  static const List<BoxShadow> soft = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 16, color: Color(0x80060A14)),
  ];

  // --elevation-lifted: 0 12px 32px -4px rgb(6 10 20 / 0.65)
  static const List<BoxShadow> lifted = [
    BoxShadow(
      offset: Offset(0, 12),
      blurRadius: 32,
      spreadRadius: -4,
      color: Color(0xA6060A14),
    ),
  ];
}

/// The three families of the design, by name.
///
/// The files are the variable TTFs of the families the web self-hosts. The
/// orchestrator must copy them into the app and declare the same family
/// names under `flutter: fonts:` in `app/pubspec.yaml`.
abstract final class TainaFonts {
  static const String display = 'Bricolage Grotesque'; // --font-family-display
  static const String body = 'Schibsted Grotesk'; // --font-family-body
  static const String mono = 'JetBrains Mono'; // --font-family-mono
}

/// Font sizes, from the primitives of `tokens.css`.
abstract final class TainaFontSizes {
  static const double xs = 12; // --font-size-xs
  static const double sm = 14; // --font-size-sm
  static const double md = 16; // --font-size-md
  static const double lg = 18; // --font-size-lg
  static const double xl = 22; // --font-size-xl
  static const double xxl = 28; // --font-size-2xl
  static const double xxxl = 36; // --font-size-3xl
  static const double display = 44; // --font-size-display
  static const double monoSm = 13; // --font-size-mono-sm
}

/// Letter spacing primitives, in logical pixels.
abstract final class TainaTracking {
  static const double tight = -0.5; // --tracking-tight
  static const double normal = 0; // --tracking-normal
  static const double wide = 1.5; // --tracking-wide
}

/// The `type-*` styles, with weight, tracking and line height from the CSS.
///
/// Colors are not baked in: text inherits the theme's color. The overline is
/// the one style that carries a text case, so render it uppercase through
/// `TainaText(..., uppercase: true)`.
abstract final class TainaTypography {
  // type-display: bold, tight, line-height 1.05
  static const TextStyle display = TextStyle(
    fontFamily: TainaFonts.display,
    fontSize: TainaFontSizes.display,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    letterSpacing: TainaTracking.tight,
    height: 1.05,
  );

  // type-h1: bold, tight, line-height 1.1
  static const TextStyle h1 = TextStyle(
    fontFamily: TainaFonts.display,
    fontSize: TainaFontSizes.xxxl,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
    letterSpacing: TainaTracking.tight,
    height: 1.1,
  );

  // type-h2: semibold, line-height 1.15
  static const TextStyle h2 = TextStyle(
    fontFamily: TainaFonts.display,
    fontSize: TainaFontSizes.xxl,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    letterSpacing: TainaTracking.normal,
    height: 1.15,
  );

  // type-h3: semibold, line-height 1.25
  static const TextStyle h3 = TextStyle(
    fontFamily: TainaFonts.display,
    fontSize: TainaFontSizes.lg,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    letterSpacing: TainaTracking.normal,
    height: 1.25,
  );

  // type-body: regular, line-height 1.5
  static const TextStyle body = TextStyle(
    fontFamily: TainaFonts.body,
    fontSize: TainaFontSizes.md,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
    letterSpacing: TainaTracking.normal,
    height: 1.5,
  );

  // type-body-sm: regular, line-height 1.45
  static const TextStyle bodySm = TextStyle(
    fontFamily: TainaFonts.body,
    fontSize: TainaFontSizes.sm,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
    letterSpacing: TainaTracking.normal,
    height: 1.45,
  );

  // type-label: semibold, line-height 1.2
  static const TextStyle label = TextStyle(
    fontFamily: TainaFonts.body,
    fontSize: TainaFontSizes.sm,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    letterSpacing: TainaTracking.normal,
    height: 1.2,
  );

  // type-caption: medium, line-height 1.3
  static const TextStyle caption = TextStyle(
    fontFamily: TainaFonts.body,
    fontSize: TainaFontSizes.xs,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    letterSpacing: TainaTracking.normal,
    height: 1.3,
  );

  // type-overline: semibold, wide, uppercase, line-height 1.2
  static const TextStyle overline = TextStyle(
    fontFamily: TainaFonts.body,
    fontSize: TainaFontSizes.xs,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
    letterSpacing: TainaTracking.wide,
    height: 1.2,
  );

  // type-mono-sm: regular, line-height 1.4, tabular figures so quotas and
  // counts line up in a column.
  static const TextStyle monoSm = TextStyle(
    fontFamily: TainaFonts.mono,
    fontSize: TainaFontSizes.monoSm,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
    letterSpacing: TainaTracking.normal,
    height: 1.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// The same styles exposed as a Material [TextTheme], used by [TainaTheme].
  static const TextTheme textTheme = TextTheme(
    displayLarge: display,
    displayMedium: display,
    displaySmall: h1,
    headlineLarge: h2,
    headlineMedium: h2,
    headlineSmall: h3,
    titleLarge: h3,
    titleMedium: label,
    titleSmall: label,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: bodySm,
    labelLarge: label,
    labelMedium: caption,
    labelSmall: caption,
  );
}

/// The words the screens use for the two zones and the two roles. They are
/// the same words on the wire, in the model and on the screen.
abstract final class TainaWords {
  static const String casa = 'Casa';
  static const String praca = 'Praça';
  static const String zelador = 'Zelador';
  static const String morador = 'Morador';
}
