import 'package:material_ui/material_ui.dart';

import '../tokens.dart';
import 'identity.dart';
import 'icons.dart';
import 'text.dart';

enum TainaBackTarget { hub, documentos, galeria }

enum TainaDocumentTab { praca, casa, lixeira }

enum TainaGalleryTab { grade, linha }

String tainaBackLabel(TainaBackTarget target) => switch (target) {
  TainaBackTarget.hub => 'Início',
  TainaBackTarget.documentos => 'Documentos',
  TainaBackTarget.galeria => 'Galeria',
};

String tainaBackLabelForParent(String? parentName) {
  final String parent = parentName?.trim() ?? '';
  if (parent.isEmpty || parent.length > 12) return 'Voltar';
  return parent;
}

String tainaDocumentTabLabel(TainaDocumentTab tab) => switch (tab) {
  TainaDocumentTab.praca => 'Praça',
  TainaDocumentTab.casa => 'Casa',
  TainaDocumentTab.lixeira => 'Lixeira',
};

TainaIcon tainaDocumentTabIcon(TainaDocumentTab tab) => switch (tab) {
  TainaDocumentTab.praca => TainaIcon.praca,
  TainaDocumentTab.casa => TainaIcon.casa,
  TainaDocumentTab.lixeira => TainaIcon.lixeira,
};

String tainaGalleryTabLabel(TainaGalleryTab tab) => switch (tab) {
  TainaGalleryTab.grade => 'Grade',
  TainaGalleryTab.linha => 'Linha do tempo',
};

TainaIcon tainaGalleryTabIcon(TainaGalleryTab tab) => switch (tab) {
  TainaGalleryTab.grade => TainaIcon.grid,
  TainaGalleryTab.linha => TainaIcon.clock,
};

/// A labeled back control for headers that need to expose their destination.
final class TainaBackButton extends StatelessWidget {
  const TainaBackButton({
    required this.onPressed,
    this.label = 'Voltar',
    super.key,
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const TainaIconView(
        icon: TainaIcon.chevL,
        size: TainaSizes.iconMd,
        color: TainaPalette.textSecondary,
      ),
      label: TainaText(
        label,
        style: TainaTypography.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: TextButton.styleFrom(
        foregroundColor: TainaPalette.textSecondary,
        minimumSize: const Size(TainaSizes.touch, TainaSizes.touch),
        padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space2),
        shape: const RoundedRectangleBorder(borderRadius: TainaRadii.mdAll),
      ),
    );
  }
}

/// The hub greeting and optional care line.
final class HubHeader extends StatelessWidget {
  const HubHeader({
    required this.greeting,
    this.communityName,
    this.userName,
    this.onAccount,
    this.careLine,
    super.key,
  }) : assert((userName == null) == (onAccount == null));

  final String greeting;
  final String? communityName;
  final String? userName;
  final VoidCallback? onAccount;
  final Widget? careLine;

  @override
  Widget build(BuildContext context) {
    final bool hasCommunity = communityName != null;
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TainaText(
          greeting,
          style: hasCommunity ? TainaTypography.bodySm : TainaTypography.h1,
          color: hasCommunity
              ? TainaPalette.textSecondary
              : TainaPalette.textPrimary,
        ),
        if (communityName case final String name) ...[
          const SizedBox(height: TainaSpacing.space1),
          TainaText(
            name,
            style: TainaTypography.h1,
            color: TainaPalette.textPrimary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TainaSpacing.space4,
        TainaSpacing.space6,
        TainaSpacing.space4,
        TainaSpacing.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (userName case final String name)
            Row(
              children: [
                Expanded(child: heading),
                IconButton(
                  tooltip: 'Conta',
                  onPressed: onAccount,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: TainaSizes.touch,
                    height: TainaSizes.touch,
                  ),
                  icon: TainaAvatar(name: name),
                ),
              ],
            )
          else
            heading,
          if (careLine != null) ...[
            const SizedBox(height: TainaSpacing.space3),
            careLine!,
          ],
        ],
      ),
    );
  }
}

/// A compact centered page title, optionally paired with back and action slots.
final class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.backLabel,
    this.onBack,
    this.action,
    super.key,
  }) : assert((backLabel == null) == (onBack == null));

  final String title;
  final String? backLabel;
  final VoidCallback? onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _HeaderRow(
      title: title,
      leading: onBack == null
          ? null
          : TainaBackButton(label: backLabel ?? 'Voltar', onPressed: onBack!),
      action: action,
    );
  }
}

/// A service title with a labeled back control and at most one trailing action.
final class ServiceHeader extends StatelessWidget {
  const ServiceHeader({
    required this.title,
    required this.backLabel,
    required this.onBack,
    this.action,
    super.key,
  });

  final String title;
  final String backLabel;
  final VoidCallback onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _HeaderRow(
      title: title,
      leading: TainaBackButton(label: backLabel, onPressed: onBack),
      action: action,
    );
  }
}

/// A [CustomScrollView] header that transitions from a large to compact title.
///
/// Use it directly in a sliver list:
/// `CustomScrollView(slivers: [PageHeaderSliver(...), ...])`.
final class PageHeaderSliver extends StatelessWidget {
  const PageHeaderSliver({
    required this.title,
    this.backLabel,
    this.onBack,
    this.action,
    this.expandedHeight,
    super.key,
  }) : assert((backLabel == null) == (onBack == null));

  final String title;
  final String? backLabel;
  final VoidCallback? onBack;
  final Widget? action;
  final double? expandedHeight;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PageHeaderSliverDelegate(
        title: title,
        leading: onBack == null
            ? null
            : TainaBackButton(label: backLabel ?? 'Voltar', onPressed: onBack!),
        action: action,
        expandedHeight:
            expandedHeight ??
            TainaSizes.appbar +
                TainaFontSizes.xxxl * TainaTypography.h1.height! +
                TainaSpacing.space6,
      ),
    );
  }
}

/// The service-header sliver variant, with the same collapse behavior as pages.
final class ServiceHeaderSliver extends StatelessWidget {
  const ServiceHeaderSliver({
    required this.title,
    required this.backLabel,
    required this.onBack,
    this.action,
    this.expandedHeight,
    super.key,
  });

  final String title;
  final String backLabel;
  final VoidCallback onBack;
  final Widget? action;
  final double? expandedHeight;

  @override
  Widget build(BuildContext context) {
    return PageHeaderSliver(
      title: title,
      backLabel: backLabel,
      onBack: onBack,
      action: action,
      expandedHeight: expandedHeight,
    );
  }
}

/// The bottom navigation used by Documentos and Galeria.
final class ServiceTabBar extends StatelessWidget {
  const ServiceTabBar.documents({
    required TainaDocumentTab selected,
    required ValueChanged<TainaDocumentTab> onSelected,
    super.key,
  }) : _documentSelected = selected,
       _onDocumentSelected = onSelected,
       _gallerySelected = null,
       _onGallerySelected = null;

  const ServiceTabBar.gallery({
    required TainaGalleryTab selected,
    required ValueChanged<TainaGalleryTab> onSelected,
    super.key,
  }) : _documentSelected = null,
       _onDocumentSelected = null,
       _gallerySelected = selected,
       _onGallerySelected = onSelected;

  final TainaDocumentTab? _documentSelected;
  final ValueChanged<TainaDocumentTab>? _onDocumentSelected;
  final TainaGalleryTab? _gallerySelected;
  final ValueChanged<TainaGalleryTab>? _onGallerySelected;

  @override
  Widget build(BuildContext context) {
    final bool isDocuments = _documentSelected != null;
    final List<_ServiceTabData> tabs = isDocuments
        ? TainaDocumentTab.values
              .map(
                (tab) => _ServiceTabData(
                  label: tainaDocumentTabLabel(tab),
                  icon: tainaDocumentTabIcon(tab),
                  selected: tab == _documentSelected,
                  onSelected: () => _onDocumentSelected!(tab),
                ),
              )
              .toList()
        : TainaGalleryTab.values
              .map(
                (tab) => _ServiceTabData(
                  label: tainaGalleryTabLabel(tab),
                  icon: tainaGalleryTabIcon(tab),
                  selected: tab == _gallerySelected,
                  onSelected: () => _onGallerySelected!(tab),
                ),
              )
              .toList();

    return Material(
      color: TainaPalette.surfaceDefault,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: TainaSizes.navMobile,
          child: Column(
            children: [
              const SizedBox(
                height: TainaSizes.hairline,
                child: ColoredBox(color: TainaPalette.borderSubtle),
              ),
              Expanded(
                child: Row(
                  children: [
                    for (final _ServiceTabData tab in tabs)
                      Expanded(child: _ServiceTabButton(data: tab)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.title,
    this.leading,
    this.action,
    this.titleOpacity = 1,
  });

  final String title;
  final Widget? leading;
  final Widget? action;
  final double titleOpacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TainaSizes.appbar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space2),
        child: Row(
          children: [
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: leading),
            ),
            Expanded(
              flex: 2,
              child: Visibility(
                visible: titleOpacity > 0,
                maintainState: true,
                child: Opacity(
                  opacity: titleOpacity,
                  child: TainaText(
                    title,
                    style: TainaTypography.h3,
                    color: TainaPalette.textPrimary,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: action == null
                    ? null
                    : ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: TainaSizes.touch,
                          minHeight: TainaSizes.touch,
                        ),
                        child: action,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PageHeaderSliverDelegate extends SliverPersistentHeaderDelegate {
  const _PageHeaderSliverDelegate({
    required this.title,
    required this.expandedHeight,
    this.leading,
    this.action,
  });

  final String title;
  final double expandedHeight;
  final Widget? leading;
  final Widget? action;

  @override
  double get minExtent => TainaSizes.appbar;

  @override
  double get maxExtent =>
      expandedHeight < minExtent ? minExtent : expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double range = maxExtent - minExtent;
    final double collapse = range == 0
        ? 1
        : (shrinkOffset / range).clamp(0.0, 1.0);
    return Material(
      color: TainaPalette.bgApp,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _HeaderRow(
              title: title,
              leading: leading,
              action: action,
              titleOpacity: collapse,
            ),
          ),
          Positioned(
            left: TainaSpacing.space4,
            right: TainaSpacing.space4,
            bottom: TainaSpacing.space4,
            child: Visibility(
              visible: collapse < 1,
              maintainState: true,
              child: Opacity(
                opacity: 1 - collapse,
                child: TainaText(
                  title,
                  style: TainaTypography.h1,
                  color: TainaPalette.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PageHeaderSliverDelegate oldDelegate) {
    return title != oldDelegate.title ||
        expandedHeight != oldDelegate.expandedHeight ||
        leading != oldDelegate.leading ||
        action != oldDelegate.action;
  }
}

final class _ServiceTabData {
  const _ServiceTabData({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final TainaIcon icon;
  final bool selected;
  final VoidCallback onSelected;
}

final class _ServiceTabButton extends StatelessWidget {
  const _ServiceTabButton({required this.data});

  final _ServiceTabData data;

  @override
  Widget build(BuildContext context) {
    final Color foreground = data.selected
        ? TainaPalette.navSelected
        : TainaPalette.navIdle;
    return Semantics(
      button: true,
      selected: data.selected,
      label: data.label,
      child: Material(
        color: TainaPalette.surfaceDefault,
        child: InkWell(
          onTap: data.onSelected,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TainaIconView(
                  icon: data.icon,
                  size: TainaSizes.iconMd,
                  color: foreground,
                ),
                const SizedBox(height: TainaSpacing.space1),
                TainaText(
                  data.label,
                  style: TainaTypography.label,
                  color: foreground,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
