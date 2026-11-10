import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import 'home_model.dart';

/// Opens the detail of a recent file.
typedef HomeOpenFile = void Function(FileRecord file);

/// Opens another screen of the app (the mural, the access requests). The
/// feature never touches the router; the app integration says where to go.
typedef HomeOpenDestination = void Function();

/// The home: the greeting and the community's name, the storage card, the
/// recent uploads and two teasers (the mural and the access requests).
///
/// The screen owns its [HomeModel]; the app integration provides the
/// [SessionGateway] and the navigation callbacks.
final class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.gateway,
    this.onOpenFile,
    this.onOpenMural,
    this.onOpenRequests,
    this.clock = DateTime.now,
    super.key,
  });

  final SessionGateway gateway;
  final HomeOpenFile? onOpenFile;
  final HomeOpenDestination? onOpenMural;
  final HomeOpenDestination? onOpenRequests;

  /// The clock the greeting reads; injectable so a test pins the hour.
  final DateTime Function() clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends State<HomeScreen> {
  late final HomeModel _model = HomeModel(widget.gateway);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_model.load());
    });
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HomeModel>.value(
      value: _model,
      child: Scaffold(
        backgroundColor: TainaPalette.bgApp,
        appBar: AppBar(title: const Text('Início')),
        body: SafeArea(
          top: false,
          child: Consumer<HomeModel>(
            builder: (context, model, child) {
              if (!model.loaded) return const TainaLoadingList();
              return RefreshIndicator(
                onRefresh: model.load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(TainaSpacing.space4),
                  children: [
                    _header(model),
                    const SizedBox(height: TainaSpacing.space6),
                    _storageSection(model),
                    if (model.stats != null || model.statsError)
                      const SizedBox(height: TainaSpacing.space6),
                    _recentSection(model),
                    const SizedBox(height: TainaSpacing.space6),
                    _muralSection(model),
                    if (model.muralError ||
                        (!model.muralError && model.mural.isNotEmpty))
                      const SizedBox(height: TainaSpacing.space6),
                    _requestsSection(model),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(HomeModel model) {
    final String greeting = HomeModel.greeting(widget.clock().hour);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TainaText(
          greeting,
          style: TainaTypography.body,
          color: TainaPalette.textSecondary,
        ),
        if (model.communityName != null)
          TainaText(
            model.communityName!,
            style: TainaTypography.h1,
            color: TainaPalette.textPrimary,
          ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TainaText(
          title,
          style: TainaTypography.overline,
          uppercase: true,
          color: TainaPalette.textMuted,
        ),
        const SizedBox(height: TainaSpacing.space3),
        child,
      ],
    );
  }

  Widget _storageSection(HomeModel model) {
    final StorageStats? stats = model.stats;
    if (stats != null) return _storageCard(stats);
    if (model.statsError) {
      return _degradedCard(
        'Não foi possível consultar o espaço da comunidade agora.',
        model.retryStorage,
      );
    }
    return const SizedBox.shrink();
  }

  /// The storage card: use against the quota, with the free space in words.
  /// Without a quota there is no "free" to measure, so the card shows only the
  /// use and hides the bar.
  Widget _storageCard(StorageStats stats) {
    final bool hasQuota = HomeModel.hasQuota(stats);
    final bool low = HomeModel.storageLow(stats);
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: TainaText(
                  'Espaço da comunidade',
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                ),
              ),
              if (hasQuota)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (low)
                      const Padding(
                        padding: EdgeInsets.only(right: TainaSpacing.space1),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: TainaFontSizes.sm,
                          color: TainaPalette.feedbackWarning,
                        ),
                      ),
                    TainaText(
                      HomeModel.freeLabel(stats),
                      style: TainaTypography.caption,
                      color: low
                          ? TainaPalette.feedbackWarning
                          : TainaPalette.feedbackSuccess,
                    ),
                  ],
                ),
            ],
          ),
          if (hasQuota) ...[
            const SizedBox(height: TainaSpacing.space3),
            ClipRRect(
              borderRadius: TainaRadii.pillAll,
              child: LinearProgressIndicator(
                value: HomeModel.storagePercent(stats) / 100,
                minHeight: TainaSizes.progress,
                color: TainaPalette.brandPrimary,
                backgroundColor: TainaPalette.surfaceRaised,
              ),
            ),
          ],
          const SizedBox(height: TainaSpacing.space3),
          TainaText(
            hasQuota
                ? '${TainaFormat.bytes(stats.usedBytes)} de '
                      '${TainaFormat.bytes(stats.quotaBytes!)} usados'
                : '${TainaFormat.bytes(stats.usedBytes)} em uso',
            style: TainaTypography.monoSm,
            color: TainaPalette.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _recentSection(HomeModel model) {
    final Widget body;
    final TainaError? error = model.recentError;
    if (error != null) {
      body = TainaErrorState(error: error, onRetry: model.load);
    } else if (model.recent.isEmpty) {
      body = const TainaEmptyState(
        icon: Icons.outbox_outlined,
        title: 'Nada por aqui ainda',
        message: 'Envie o primeiro arquivo da comunidade.',
      );
    } else {
      body = Column(
        children: [
          for (int index = 0; index < model.recent.length; index++) ...[
            if (index > 0) const SizedBox(height: TainaSpacing.space2),
            _RecentRow(
              file: model.recent[index],
              onTap: widget.onOpenFile == null
                  ? null
                  : () => widget.onOpenFile!(model.recent[index]),
            ),
          ],
        ],
      );
    }
    return _section('Recentes', body);
  }

  Widget _muralSection(HomeModel model) {
    if (model.muralError) {
      return _section(
        'Mural',
        _degradedCard('Não foi possível carregar o mural agora.', model.load),
      );
    }
    if (model.mural.isEmpty) return const SizedBox.shrink();
    return _section(
      'Mural',
      Column(
        children: [
          for (int index = 0; index < model.mural.length; index++) ...[
            if (index > 0) const SizedBox(height: TainaSpacing.space2),
            _MuralTeaserRow(
              line: model.mural[index],
              onTap: widget.onOpenMural,
            ),
          ],
        ],
      ),
    );
  }

  Widget _requestsSection(HomeModel model) {
    if (model.requestsError) {
      return _degradedCard(
        'Não foi possível consultar os pedidos de acesso agora.',
        model.load,
      );
    }
    final int? count = model.pendingRequests;
    if (count == null) return const SizedBox.shrink();
    return _requestsCard(count);
  }

  Widget _requestsCard(int count) {
    return TainaRowCard(
      onTap: widget.onOpenRequests,
      child: Row(
        children: [
          Container(
            width: TainaSpacing.space10,
            height: TainaSpacing.space10,
            decoration: const BoxDecoration(
              color: TainaPalette.surfaceRaised,
              borderRadius: TainaRadii.mdAll,
            ),
            child: const Icon(
              Icons.inbox_rounded,
              size: TainaFontSizes.lg,
              color: TainaPalette.serviceMaraca,
            ),
          ),
          const SizedBox(width: TainaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TainaText(
                  'Pedidos de acesso',
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                ),
                TainaText(
                  HomeModel.pendingLabel(count),
                  style: TainaTypography.caption,
                  color: TainaPalette.textMuted,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: TainaFontSizes.lg,
            color: TainaPalette.textFaint,
          ),
        ],
      ),
    );
  }

  /// The calm card that takes the place of a section the box did not answer:
  /// a sentence and a way back, never a card that vanishes.
  Widget _degradedCard(String message, Future<void> Function() retry) {
    return TainaRowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TainaText(
            message,
            style: TainaTypography.bodySm,
            color: TainaPalette.textMuted,
          ),
          const SizedBox(height: TainaSpacing.space3),
          TainaSecondaryButton(
            label: 'Tentar de novo',
            onPressed: () => unawaited(retry()),
          ),
        ],
      ),
    );
  }
}

/// The recent row: the kind glyph, the name, and the meta line that ends in
/// the zone in words, with the chevron that says it opens.
final class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.file, this.onTap});

  final FileRecord file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TainaRowCard(
      onTap: onTap,
      child: Row(
        children: [
          _FileGlyph(mime: file.mime),
          const SizedBox(width: TainaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TainaText(
                  file.name,
                  style: TainaTypography.label,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                TainaText(
                  HomeModel.recentMeta(file),
                  style: TainaTypography.caption,
                  color: TainaPalette.textMuted,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: TainaFontSizes.lg,
            color: TainaPalette.textFaint,
          ),
        ],
      ),
    );
  }
}

/// One mural teaser line: the sentence and when it happened, with the chevron
/// that says it opens (the mural itself).
final class _MuralTeaserRow extends StatelessWidget {
  const _MuralTeaserRow({required this.line, this.onTap});

  final HomeMuralLine line;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TainaRowCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TainaText(
                  line.sentence,
                  style: TainaTypography.bodySm,
                  color: TainaPalette.textPrimary,
                ),
                const SizedBox(height: TainaSpacing.space2),
                TainaText(
                  line.ago,
                  style: TainaTypography.caption,
                  color: TainaPalette.textMuted,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: TainaFontSizes.lg,
            color: TainaPalette.textFaint,
          ),
        ],
      ),
    );
  }
}

/// The glyph of a kind of file: color and shape together, never the color
/// alone.
final class _FileGlyph extends StatelessWidget {
  const _FileGlyph({required this.mime});

  final String mime;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: TainaSpacing.space10,
      height: TainaSpacing.space10,
      decoration: BoxDecoration(color: _fill, borderRadius: TainaRadii.mdAll),
      child: Icon(_symbol, size: TainaFontSizes.lg, color: _tint),
    );
  }

  IconData get _symbol {
    if (mime.startsWith('image/')) return Icons.photo_outlined;
    if (mime.startsWith('audio/')) return Icons.play_arrow_rounded;
    return Icons.description_outlined;
  }

  Color get _tint {
    if (mime.startsWith('image/')) return TainaPalette.serviceJaciTint;
    if (mime.startsWith('video/') || mime.startsWith('audio/')) {
      return TainaPalette.serviceVideo;
    }
    if (mime == 'application/pdf') return TainaPalette.brandEmber;
    if (mime.startsWith('text/')) return TainaPalette.serviceYbiraTint;
    return TainaPalette.textMuted;
  }

  Color get _fill {
    if (mime.startsWith('image/')) return TainaPalette.serviceJaciSoft;
    if (mime.startsWith('text/')) return TainaPalette.serviceYbiraSoft;
    return TainaPalette.surfaceRaised;
  }
}
