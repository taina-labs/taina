import 'package:material_ui/material_ui.dart';
import 'package:okena_app/src/design_system/design_system.dart';

/// A short explanation of how files are shared in the community.
final class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({this.onBack, this.backLabel = 'Conta', super.key});

  final VoidCallback? onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            PageHeaderSliver(
              title: 'Privacidade',
              backLabel: backLabel,
              onBack: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                TainaSpacing.space4,
                TainaSpacing.space3,
                TainaSpacing.space4,
                TainaSpacing.space6,
              ),
              sliver: SliverList.list(
                children: const [
                  _PrivacyCard(
                    title: 'Sua casa é só sua',
                    body:
                        'Ninguém abre um arquivo da sua casa sem você deixar: '
                        'quem pede, você aprova ou recusa.',
                  ),
                  SizedBox(height: TainaSpacing.space6),
                  _PrivacyCard(
                    title: 'A praça é de todos',
                    body:
                        'O que você publica na praça, todo mundo lê. Publicar '
                        'é um gesto seu, e dá para voltar atrás.',
                    meta: 'Casa por padrão. Praça por escolha.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({required this.title, required this.body, this.meta});

  final String title;
  final String body;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return TainaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TainaTypography.h3.copyWith(color: TainaPalette.textPrimary),
          ),
          const SizedBox(height: TainaSpacing.space2),
          Text(
            body,
            style: TainaTypography.body.copyWith(
              color: TainaPalette.textSecondary,
            ),
          ),
          if (meta != null) ...[
            const SizedBox(height: TainaSpacing.space2),
            Text(
              meta!,
              style: TainaTypography.caption.copyWith(
                color: TainaPalette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
