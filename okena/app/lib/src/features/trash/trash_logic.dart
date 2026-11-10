import 'dart:math' as math;

import 'package:okena_core/okena_core.dart';

import '../../design_system/design_system.dart';

/// The shape of the glyph a discarded file shows. The trash row never shows
/// a thumbnail of a discarded file.
enum TrashGlyph { photo, film, audio, pdf, text, document }

/// The trash rules: retention, warning, meta line and count. Pure functions
/// the view never reimplements.
abstract final class TrashLogic {
  /// The same number the purge worker counts: 30 days, then the file is gone
  /// for good.
  static const int retentionDays = 30;

  /// At or below this many days left, the meta line turns to warning.
  static const int warningDays = 5;

  /// "%{count} item carregado(s)" while a page is still missing, the plain
  /// count at the end of the list.
  static String countLabel({required int count, required bool hasMore}) {
    final noun = count == 1 ? '1 item' : '$count itens';
    if (!hasMore) return noun;
    return noun + (count == 1 ? ' carregado' : ' carregados');
  }

  /// The glyph for a mime, like the web's `file_visual/1`.
  static TrashGlyph glyph(String mime) {
    if (mime.startsWith('image/')) return TrashGlyph.photo;
    if (mime.startsWith('video/')) return TrashGlyph.film;
    if (mime.startsWith('audio/')) return TrashGlyph.audio;
    if (mime == 'application/pdf') return TrashGlyph.pdf;
    if (mime.startsWith('text/')) return TrashGlyph.text;
    return TrashGlyph.document;
  }

  /// The row's meta line, like the web's `trash_meta/1`: deleted when, days
  /// left before the purge, and who reads the file. Inside the warning window
  /// the line says the purge is close.
  static String meta(FileRecord file, {DateTime? now}) {
    final zone = file.zona == Zona.praca ? 'Todos veem' : 'Só você';
    final deletedAt = file.deletedAt ?? '';
    final days = _deletedDaysAgo(deletedAt, now ?? DateTime.now());
    if (days == null) {
      return 'Apagado em ${TainaFormat.date(deletedAt)} / $zone';
    }
    final left = math.max(retentionDays - days, 0);
    if (left == 0) return 'Apaga hoje / $zone';
    if (left <= warningDays) {
      return left == 1
          ? 'Resta 1 dia, apaga em breve / $zone'
          : 'Restam $left dias, apaga em breve / $zone';
    }
    final deleted = switch (days) {
      0 => 'Apagado hoje',
      1 => 'Apagado ontem',
      _ => 'Apagado há $days dias',
    };
    final remaining = left == 1 ? ', resta 1 dia' : ', restam $left dias';
    return '$deleted$remaining / $zone';
  }

  /// True inside the warning window: few days left, the purge is close.
  static bool isWarning(FileRecord file, {DateTime? now}) {
    final days = _deletedDaysAgo(file.deletedAt ?? '', now ?? DateTime.now());
    if (days == null) return false;
    return math.max(retentionDays - days, 0) <= warningDays;
  }

  /// Whole days since the deletion, never negative: a clock ahead of the
  /// box's must not read "apagado há -1 dias".
  static int? _deletedDaysAgo(String deletedAt, DateTime now) {
    final deleted = DateTime.tryParse(deletedAt);
    if (deleted == null) return null;
    final localDeleted = deleted.toLocal();
    final localNow = now.toLocal();
    final days = DateTime.utc(localNow.year, localNow.month, localNow.day)
        .difference(
          DateTime.utc(localDeleted.year, localDeleted.month, localDeleted.day),
        )
        .inDays;
    return math.max(days, 0);
  }
}
