import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/mural/mural_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The mural: the community's ledger, newest first, in plain words.
final class MuralScreen extends StatefulWidget {
  const MuralScreen({required this.session, this.onBack, super.key});

  final SessionGateway session;
  final VoidCallback? onBack;

  @override
  State<MuralScreen> createState() => _MuralScreenState();
}

final class _MuralScreenState extends State<MuralScreen> {
  late final MuralModel _model;

  @override
  void initState() {
    super.initState();
    _model = MuralModel(gateway: widget.session);
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MuralModel>.value(
      value: _model,
      child: _MuralView(onBack: widget.onBack),
    );
  }
}

final class _MuralView extends StatelessWidget {
  const _MuralView({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final MuralModel model = context.watch<MuralModel>();
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: model.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              PageHeaderSliver(
                title: 'Mural',
                backLabel: 'Início',
                onBack: () => _handleBack(context),
              ),
              if (model.entries.isNotEmpty)
                _entries(model)
              else if (model.loading)
                const SliverPadding(
                  padding: EdgeInsets.all(TainaSpacing.space4),
                  sliver: SliverToBoxAdapter(
                    child: SkeletonView(
                      kind: TainaSkeletonKind.listRow,
                      count: 4,
                    ),
                  ),
                )
              else if (model.error != null)
                SliverPadding(
                  padding: const EdgeInsets.all(TainaSpacing.space4),
                  sliver: SliverToBoxAdapter(
                    child: ErrorCard(
                      title: 'Não conseguimos falar com a nuvem agora.',
                      body: '',
                      retry: () => unawaited(model.load()),
                      contact: () => _showCaretakers(context, model),
                    ),
                  ),
                )
              else
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyStateView(
                      icon: TainaIcon.folder,
                      title: 'Nada no mural ainda',
                      body:
                          'Ainda não aconteceu nada por aqui. Quando alguém '
                          'publicar na praça ou cuidar da máquina, aparece '
                          'neste mural.',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entries(MuralModel model) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index < model.entries.length) {
          final MuralEntry entry = model.entries[index];
          return TainaListRow(
            kind: TainaListRowKind.mural,
            title: model.sentenceFor(entry),
            meta: MuralModel.timeLabel(entry.createdAt),
          );
        }
        return _MuralSentinel(model: model);
      }, childCount: model.entries.length + 1),
    );
  }

  void _handleBack(BuildContext context) {
    final VoidCallback? callback = onBack;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _showCaretakers(BuildContext context, MuralModel model) {
    final List<String> names = model.caretakers;
    unawaited(
      TainaSheet.show<void>(
        context: context,
        title: 'Quem cuida da nuvem',
        child: Padding(
          padding: const EdgeInsets.all(TainaSpacing.space4),
          child: names.isEmpty
              ? const EmptyStateView(
                  icon: TainaIcon.user,
                  title: 'Não encontramos quem cuida',
                  body: 'Tente de novo quando a nuvem responder.',
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int index = 0; index < names.length; index++)
                      TainaListRow(
                        kind: TainaListRowKind.person,
                        title: names[index],
                        meta: 'Zelador',
                        showDivider: index < names.length - 1,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The next page loads on sight. Once the cursor is exhausted the board ends
/// with its fixed "Fim do mural." line.
final class _MuralSentinel extends StatelessWidget {
  const _MuralSentinel({required this.model});

  final MuralModel model;

  @override
  Widget build(BuildContext context) {
    if (model.nextCursor == null) {
      return Column(
        children: [
          const Divider(
            color: TainaPalette.borderSubtle,
            height: TainaSizes.hairline,
            thickness: TainaSizes.hairline,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: TainaSpacing.space4),
            child: Text(
              'Fim do mural.',
              textAlign: TextAlign.center,
              style: TainaTypography.caption.copyWith(
                color: TainaPalette.textMuted,
              ),
            ),
          ),
        ],
      );
    }
    if (model.moreError) {
      return Padding(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        child: TainaSecondaryButton(
          label: 'Tentar de novo',
          onPressed: () => unawaited(model.loadMore()),
        ),
      );
    }
    if (model.loadingMore) {
      return const SkeletonView(kind: TainaSkeletonKind.listRow, count: 1);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(model.loadMore());
    });
    return const SkeletonView(kind: TainaSkeletonKind.listRow, count: 1);
  }
}
