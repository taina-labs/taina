/// The Tainá design system: tokens, theme, shared components and formatting.
///
/// Feature agents import this library and never need to know the Swift
/// implementation:
///
/// ```dart
/// import 'package:okena_app/src/design_system/design_system.dart';
/// ```
///
/// - Colors, type, spacing and sizes: [TainaPalette], [TainaTypography],
///   [TainaSpacing], [TainaRadii], [TainaSizes], [TainaOpacity],
///   [TainaElevation].
/// - Material defaults: [TainaTheme.data].
/// - Shared components: [TainaPrimaryButton], [TainaSecondaryButton],
///   [TainaTextField], [TainaRowCard], [TainaZonaBadge],
///   [TainaEmptyState], [TainaErrorState], [TainaSkeleton],
///   [TainaLoadingList], [TainaText].
/// - Pure formatting: [TainaFormat].
library;

export 'components/actions.dart';
export 'components/buttons.dart';
export 'components/content.dart';
export 'components/feedback.dart';
export 'components/field.dart';
export 'components/forms.dart';
export 'components/icons.dart';
export 'components/identity.dart';
export 'components/media.dart';
export 'components/navigation.dart';
export 'components/overlays.dart';
export 'components/states.dart';
export 'components/surfaces.dart';
export 'components/text.dart';
export 'format.dart';
export 'theme.dart';
export 'tokens.dart';
