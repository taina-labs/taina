import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_gateway.dart';
import 'trash_logic.dart';
import 'trash_view_model.dart';

/// The lixeira is a Documentos route tab, not a separate global screen.
final class TrashScreen extends StatelessWidget {
  const TrashScreen({
    required this.session,
    this.model,
    this.selectedTab = TainaDocumentTab.lixeira,
    this.onSelectTab,
    this.onBack,
    super.key,
  });

  final SessionGateway session;
  final TrashViewModel? model;
  final TainaDocumentTab selectedTab;
  final ValueChanged<TainaDocumentTab>? onSelectTab;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scaffold = _TrashScaffold(
      selectedTab: selectedTab,
      onSelectTab: onSelectTab,
      onBack: onBack,
    );
    final injected = model;
    if (injected != null) {
      return ChangeNotifierProvider<TrashViewModel>.value(
        value: injected,
        child: scaffold,
      );
    }
    return ChangeNotifierProvider<TrashViewModel>(
      create: (context) {
        final created = TrashViewModel(session: session);
        unawaited(created.load());
        return created;
      },
      child: scaffold,
    );
  }
}

final class _TrashScaffold extends StatelessWidget {
  const _TrashScaffold({
    required this.selectedTab,
    required this.onSelectTab,
    required this.onBack,
  });

  final TainaDocumentTab selectedTab;
  final ValueChanged<TainaDocumentTab>? onSelectTab;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<TrashViewModel>();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: model.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ServiceHeaderSliver(
              title: 'Documentos',
              backLabel: 'Início',
              onBack: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  TainaSpacing.space4,
                  TainaSpacing.space2,
                  TainaSpacing.space4,
                  TainaSpacing.space3,
                ),
                child: TainaText(
                  'Os itens ficam 30 dias na lixeira e depois são apagados de vez.',
                  style: TainaTypography.bodySm,
                  color: TainaPalette.textSecondary,
                ),
              ),
            ),
            _TrashContents(model: model),
          ],
        ),
      ),
      bottomNavigationBar: ServiceTabBar.documents(
        selected: selectedTab,
        onSelected: (tab) {
          if (onSelectTab != null) {
            onSelectTab!(tab);
          } else if (tab != TainaDocumentTab.lixeira) {
            Navigator.of(context).maybePop();
          }
        },
      ),
    );
  }
}

final class _TrashContents extends StatelessWidget {
  const _TrashContents({required this.model});

  final TrashViewModel model;

  @override
  Widget build(BuildContext context) {
    if (model.items.isEmpty) {
      if (model.loading) {
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: TainaLoadingList()),
        );
      }
      final error = model.error;
      if (error != null) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(TainaSpacing.space4),
              child: ErrorCard(
                title: 'Não conseguimos carregar a lixeira.',
                body: error.message,
                retry: () => unawaited(model.load()),
              ),
            ),
          ),
        );
      }
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: EmptyStateView(
            icon: TainaIcon.lixeira,
            title: 'A lixeira está vazia',
            body: 'Nada foi apagado. O que você apagar aparece aqui por 30 dias antes de sumir de vez.',
          ),
        ),
      );
    }

    final rows = <Widget>[
      SliverList.builder(
        itemCount: model.items.length,
        itemBuilder: (context, index) {
          final file = model.items[index];
          final restoring = model.restoringRkey == file.rkey;
          return TainaListRow(
            kind: TainaListRowKind.trash,
            title: file.name,
            meta: TrashLogic.meta(file),
            trailing: TainaListRowTrailing.action,
            trailingLabel: restoring ? 'Restaurando' : 'Restaurar',
            trailingBuilder: restoring
                ? (_) => Semantics(
                    label: 'Restaurando',
                    liveRegion: true,
                    child: SizedBox(
                      width: TainaSizes.touch,
                      height: TainaSizes.touch,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                : null,
            onTrailingPressed: restoring
                ? null
                : () => unawaited(_restore(context, file.rkey)),
          );
        },
      ),
      if (model.nextCursor != null)
        SliverToBoxAdapter(
          child: _TrashLoadMoreSentinel(
            model: model,
            key: ValueKey(model.nextCursor),
          ),
        ),
    ];
    return SliverMainAxisGroup(slivers: rows);
  }

  Future<void> _restore(BuildContext context, String rkey) async {
    final result = await model.restore(rkey: rkey);
    if (!context.mounted) return;
    final error = result.error;
    final text = error == null
        ? 'Arquivo restaurado.'
        : error.message.isEmpty
        ? 'Não foi possível restaurar o arquivo.'
        : error.message;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          content: TainaToast(
            kind: error == null ? TainaToastKind.info : TainaToastKind.error,
            text: text,
          ),
        ),
      );
  }
}

final class _TrashLoadMoreSentinel extends StatefulWidget {
  const _TrashLoadMoreSentinel({required this.model, super.key});

  final TrashViewModel model;

  @override
  State<_TrashLoadMoreSentinel> createState() => _TrashLoadMoreSentinelState();
}

final class _TrashLoadMoreSentinelState extends State<_TrashLoadMoreSentinel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.model.moreError) {
        unawaited(widget.model.loadMore());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.model.moreError) {
      return Padding(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        child: ErrorCard(
          title: 'Não foi possível carregar mais itens.',
          body: '',
          retry: () => unawaited(widget.model.loadMore()),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(TainaSpacing.space4),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
