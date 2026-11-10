import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';

import '../../design_system/design_system.dart';

/// The community the link belongs to, always visible at the top of the auth
/// screens, with the cleartext caveat where it applies.
final class AuthCommunityHeader extends StatelessWidget {
  const AuthCommunityHeader({
    required this.instance,
    required this.host,
    super.key,
  });

  final Instance? instance;
  final InstanceAddress? host;

  @override
  Widget build(BuildContext context) {
    final name = instance?.tekoa?.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: TainaSpacing.space2,
      children: [
        if (name != null)
          TainaText(
            name,
            style: TainaTypography.h2,
            color: TainaPalette.textPrimary,
          ),
        if (host != null) ...[
          TainaText(
            host!.display,
            style: TainaTypography.monoSm,
            color: TainaPalette.textMuted,
          ),
          if (host!.isCleartext) const TainaCleartextNotice(),
        ],
      ],
    );
  }
}
