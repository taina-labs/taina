import 'package:material_ui/material_ui.dart';

import '../tokens.dart';
import 'icons.dart';

enum TainaBadgeKind { praca, casa, zelador, morador, active, inactive }

/// A compact label for a zone, community role or state.
final class TainaBadge extends StatelessWidget {
  const TainaBadge({required this.kind, this.label, super.key});

  final TainaBadgeKind kind;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final String text = label ?? _label;
    final Color color = _color;
    final TainaIcon icon = _icon;

    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Container(
          height: TainaSizes.badge,
          padding: const EdgeInsets.symmetric(horizontal: TainaSpacing.space2),
          decoration: BoxDecoration(
            color: TainaPalette.surfaceRaised,
            border: Border.all(color: color, width: TainaSizes.hairline),
            borderRadius: TainaRadii.pillAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TainaIconView(icon: icon, size: TainaFontSizes.sm, color: color),
              const SizedBox(width: TainaSpacing.space1),
              Text(
                text,
                style: TainaTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _label => switch (kind) {
    TainaBadgeKind.praca => 'praça',
    TainaBadgeKind.casa => 'casa',
    TainaBadgeKind.zelador => 'zelador',
    TainaBadgeKind.morador => 'morador',
    TainaBadgeKind.active => 'Com acesso',
    TainaBadgeKind.inactive => 'Sem acesso',
  };

  Color get _color => switch (kind) {
    TainaBadgeKind.praca => TainaPalette.badgeZonePraca,
    TainaBadgeKind.casa => TainaPalette.badgeZoneCasa,
    TainaBadgeKind.zelador => TainaPalette.badgeRoleZelador,
    TainaBadgeKind.morador => TainaPalette.badgeRoleMorador,
    TainaBadgeKind.active => TainaPalette.badgeStateActive,
    TainaBadgeKind.inactive => TainaPalette.badgeStateInactive,
  };

  TainaIcon get _icon => switch (kind) {
    TainaBadgeKind.praca => TainaIcon.praca,
    TainaBadgeKind.casa => TainaIcon.home,
    TainaBadgeKind.zelador => TainaIcon.shield,
    TainaBadgeKind.morador => TainaIcon.user,
    TainaBadgeKind.active => TainaIcon.check,
    TainaBadgeKind.inactive => TainaIcon.x,
  };
}

enum TainaAvatarSize { sm, md, lg }

/// An avatar whose tint follows the app's stable name-to-color mapping.
final class TainaAvatar extends StatelessWidget {
  const TainaAvatar({
    required this.name,
    this.size = TainaAvatarSize.md,
    this.off = false,
    super.key,
  });

  final String name;
  final TainaAvatarSize size;
  final bool off;

  @override
  Widget build(BuildContext context) {
    final int tint = _tintIndex(name);
    final double diameter = switch (size) {
      TainaAvatarSize.sm => TainaSizes.controlSm,
      TainaAvatarSize.md => TainaSizes.controlMd,
      TainaAvatarSize.lg => TainaSizes.controlLg,
    };
    final Color background = off ? TainaPalette.surfaceRaised : _tint(tint);
    final Color foreground = off
        ? TainaPalette.textSecondary
        : TainaPalette.textPrimary;

    return Semantics(
      image: true,
      label: name.isEmpty ? 'Avatar sem nome' : 'Avatar de $name',
      child: ExcludeSemantics(
        child: Container(
          width: diameter,
          height: diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: off
                ? Border.all(
                    color: TainaPalette.borderDefault,
                    width: TainaSizes.hairline,
                  )
                : null,
          ),
          child: Text(
            _initial(name),
            style: _textStyle.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }

  String _initial(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  int _tintIndex(String value) =>
      value.runes.fold(0, (int sum, int rune) => sum + rune) % 4;

  Color _tint(int index) => switch (index) {
    0 => TainaPalette.avatarTint0,
    1 => TainaPalette.avatarTint1,
    2 => TainaPalette.avatarTint2,
    _ => TainaPalette.avatarTint3,
  };

  TextStyle get _textStyle => switch (size) {
    TainaAvatarSize.sm => TainaTypography.caption,
    TainaAvatarSize.md => TainaTypography.label,
    TainaAvatarSize.lg => TainaTypography.h3,
  };
}

enum TainaServiceMark {
  ybira,
  jaci,
  maraca,
  nhaman,
  doc,
  video,
  neutral,
  casa,
  praca,
  lixeira,
  mural,
  saude,
  moradores,
  pedidos,
  privacidade,
  senha,
  dispositivos,
  sair,
}

enum TainaServiceSquareTone { service, neutral }

enum TainaServiceSquareSize { md, lg }

/// A square icon mark for a service or a neutral action.
final class ServiceSquare extends StatelessWidget {
  const ServiceSquare({
    required this.mark,
    this.tone = TainaServiceSquareTone.neutral,
    this.size = TainaServiceSquareSize.md,
    super.key,
  });

  final TainaServiceMark mark;
  final TainaServiceSquareTone tone;
  final TainaServiceSquareSize size;

  @override
  Widget build(BuildContext context) {
    final bool large = size == TainaServiceSquareSize.lg;

    return Semantics(
      image: true,
      label: _markLabel,
      child: ExcludeSemantics(
        child: Container(
          width: large ? TainaSizes.controlLg : TainaSizes.touch,
          height: large ? TainaSizes.controlLg : TainaSizes.touch,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _backgroundColor,
            borderRadius: large ? TainaRadii.xlAll : TainaRadii.lgAll,
          ),
          child: TainaIconView(
            icon: _icon,
            size: large ? TainaSizes.iconLg : TainaSizes.iconMd,
            color: _foregroundColor,
          ),
        ),
      ),
    );
  }

  String get _markLabel => switch (mark) {
    TainaServiceMark.ybira => 'Documentos',
    TainaServiceMark.jaci => 'Galeria',
    TainaServiceMark.maraca => 'Moradores',
    TainaServiceMark.nhaman => 'Armazenamento',
    TainaServiceMark.doc => 'Documento',
    TainaServiceMark.video => 'Vídeo',
    TainaServiceMark.neutral => 'Informação',
    TainaServiceMark.casa => TainaWords.casa,
    TainaServiceMark.praca => TainaWords.praca,
    TainaServiceMark.lixeira => 'Lixeira',
    TainaServiceMark.mural => 'Mural',
    TainaServiceMark.saude => 'Saúde da comunidade',
    TainaServiceMark.moradores => TainaWords.morador,
    TainaServiceMark.pedidos => 'Pedidos',
    TainaServiceMark.privacidade => 'Privacidade',
    TainaServiceMark.dispositivos => 'Dispositivos',
    TainaServiceMark.senha => 'Senha',
    TainaServiceMark.sair => 'Sair',
  };

  TainaIcon get _icon => switch (mark) {
    TainaServiceMark.ybira => TainaIcon.folder,
    TainaServiceMark.jaci => TainaIcon.image,
    TainaServiceMark.maraca => TainaIcon.moradores,
    TainaServiceMark.nhaman => TainaIcon.saude,
    TainaServiceMark.doc => TainaIcon.file,
    TainaServiceMark.video => TainaIcon.image,
    TainaServiceMark.neutral => TainaIcon.dots,
    TainaServiceMark.casa => TainaIcon.casa,
    TainaServiceMark.praca => TainaIcon.praca,
    TainaServiceMark.lixeira => TainaIcon.lixeira,
    TainaServiceMark.mural => TainaIcon.mural,
    TainaServiceMark.saude => TainaIcon.saude,
    TainaServiceMark.moradores => TainaIcon.moradores,
    TainaServiceMark.pedidos => TainaIcon.pedidos,
    TainaServiceMark.privacidade => TainaIcon.privacidade,
    TainaServiceMark.senha => TainaIcon.senha,
    TainaServiceMark.dispositivos => TainaIcon.dispositivos,
    TainaServiceMark.sair => TainaIcon.sair,
  };

  Color get _backgroundColor => switch (mark) {
    TainaServiceMark.ybira => TainaPalette.serviceYbiraSoft,
    TainaServiceMark.jaci => TainaPalette.serviceJaciSoft,
    TainaServiceMark.maraca => TainaPalette.serviceMaracaSoft,
    TainaServiceMark.nhaman => TainaPalette.serviceNhamanSoft,
    _ => TainaPalette.surfaceRaised,
  };

  Color get _foregroundColor => switch (mark) {
    TainaServiceMark.ybira => TainaPalette.serviceYbiraTint,
    TainaServiceMark.jaci => TainaPalette.serviceJaciTint,
    TainaServiceMark.maraca => TainaPalette.serviceMaracaTint,
    TainaServiceMark.nhaman => TainaPalette.serviceNhaman,
    TainaServiceMark.doc => TainaPalette.brandEmber,
    TainaServiceMark.video => TainaPalette.serviceVideo,
    _ =>
      tone == TainaServiceSquareTone.service
          ? TainaPalette.textSecondary
          : TainaPalette.textMuted,
  };
}

/// The connection caveat shown on authentication screens.
final class ConnectionNotice extends StatelessWidget {
  const ConnectionNotice({
    this.message =
        'Esta conexão só fica protegida quando você está na rede da comunidade. '
        'Se não tiver certeza, fale com quem cuida antes de entrar.',
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(TainaSpacing.space4),
          decoration: BoxDecoration(
            color: TainaPalette.surfaceDefault,
            border: Border.all(
              color: TainaPalette.borderSubtle,
              width: TainaSizes.hairline,
            ),
            borderRadius: TainaRadii.lgAll,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TainaIconView(
                icon: TainaIcon.info,
                size: TainaSizes.iconMd,
                color: TainaPalette.textSecondary,
              ),
              const SizedBox(width: TainaSpacing.space3),
              Expanded(
                child: Text(
                  message,
                  style: TainaTypography.bodySm.copyWith(
                    color: TainaPalette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
