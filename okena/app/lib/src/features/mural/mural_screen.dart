import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/mural/mural_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The mural: the community's ledger, newest first, in plain words.
///
/// Read-only for every papel: the register of what happened, not a place to
/// act. The screen owns its loading and pull to refresh.
final class MuralScreen extends StatefulWidget {
  const MuralScreen({required this.session, super.key});

  final SessionGateway session;

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
      child: const _MuralView(),
    );
  }
}

final class _MuralView extends StatelessWidget {
  const _MuralView();

  @override
  Widget build(BuildContext context) {
    final MuralModel model = context.watch<MuralModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mural')),
      body: SafeArea(child: _body(context, model)),
    );
  }

  Widget _body(BuildContext context, MuralModel model) {
    if (model.entries.isEmpty) {
      if (model.loading) return const TainaLoadingList();
      if (model.error case final TainaError error) {
        return _refreshable(
          model,
          TainaErrorState(error: error, onRetry: model.load),
        );
      }
      return _refreshable(
        model,
        const TainaEmptyState(
          icon: Icons.menu_book_outlined,
          title: 'Nada aconteceu ainda',
          message:
              'Quando alguém convidar, publicar na praça ou pedir acesso, o '
              'registro aparece aqui. Ninguém edita e ninguém apaga: o mural é '
              'a memória do que aconteceu.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView.builder(
        padding: const EdgeInsets.all(TainaSpacing.space4),
        itemCount: model.entries.length + 2,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: TainaSpacing.space5),
              child: TainaText(
                'O que aconteceu na comunidade. Cada linha registra um ato: '
                'ninguém edita, ninguém apaga.',
                style: TainaTypography.bodySm,
                color: TainaPalette.textMuted,
              ),
            );
          }
          final int position = index - 1;
          if (position < model.entries.length) {
            final MuralEntry entry = model.entries[position];
            return Padding(
              padding: const EdgeInsets.only(bottom: TainaSpacing.space5),
              child: _MuralRow(
                sentence: model.sentenceFor(entry),
                ago: TainaFormat.relative(entry.createdAt),
              ),
            );
          }
          return _MuralSentinel(model: model);
        },
      ),
    );
  }

  Widget _refreshable(MuralModel model, Widget child) {
    return RefreshIndicator(
      onRefresh: model.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(TainaSpacing.space4),
        children: [child],
      ),
    );
  }
}

/// The next page: a spinner that loads on sight, or the retry when a page
/// failed. It only exists while the server still has rows.
final class _MuralSentinel extends StatelessWidget {
  const _MuralSentinel({required this.model});

  final MuralModel model;

  @override
  Widget build(BuildContext context) {
    if (model.nextCursor == null) return const SizedBox.shrink();
    if (model.moreError) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TainaText(
            'Não foi possível carregar mais do mural.',
            style: TainaTypography.caption,
            color: TainaPalette.textMuted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: TainaSpacing.space2),
          SizedBox(
            width: 200,
            child: TainaSecondaryButton(
              label: 'Tentar de novo',
              onPressed: () => unawaited(model.loadMore()),
            ),
          ),
        ],
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(model.loadMore());
    });
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: TainaSpacing.space4),
      child: Center(
        child: SizedBox(
          width: TainaSizes.controlSm / 2,
          height: TainaSizes.controlSm / 2,
          child: CircularProgressIndicator(
            strokeWidth: TainaSizes.thick,
            color: TainaPalette.textMuted,
            semanticsLabel: 'Carregando',
          ),
        ),
      ),
    );
  }
}

/// One entry: the act in words, and when. The sentence is the web's own,
/// from the shared table; the chain's ids never reach the screen.
final class _MuralRow extends StatelessWidget {
  const _MuralRow({required this.sentence, required this.ago});

  final String sentence;
  final String ago;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TainaText(
          sentence,
          style: TainaTypography.body,
          color: TainaPalette.textPrimary,
        ),
        const SizedBox(height: TainaSpacing.space1),
        TainaText(
          ago,
          style: TainaTypography.caption,
          color: TainaPalette.textFaint,
        ),
      ],
    );
  }
}
