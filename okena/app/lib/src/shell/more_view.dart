import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design_system/design_system.dart';
import 'shell_model.dart';

/// The long tail of the web sidebar: everything that does not earn a tab of
/// its own. Each row is a [TainaRowCard], so the shell reads like the screens
/// it opens instead of a system list.
final class MoreView extends StatelessWidget {
  const MoreView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mais')),
      body: ListView.separated(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        itemCount: MoreRoute.values.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: TainaSpacing.space3),
        itemBuilder: (context, index) {
          final route = MoreRoute.values[index];
          return TainaRowCard(
            onTap: () => context.read<ShellModel>().openMore(route),
            child: Row(
              children: [
                Icon(
                  route.icon,
                  size: TainaFontSizes.lg,
                  color: TainaPalette.textMuted,
                ),
                const SizedBox(width: TainaSpacing.space3),
                Expanded(
                  child: TainaText(
                    route.label,
                    style: TainaTypography.body,
                    color: TainaPalette.textPrimary,
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: TainaFontSizes.lg,
                  color: TainaPalette.textFaint,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
