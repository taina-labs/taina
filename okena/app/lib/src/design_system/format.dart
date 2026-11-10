/// Pure pt-BR formatting: sizes and dates. No widgets, no IO.
///
/// Dates parse as ISO 8601 and print with a fixed pt-BR shape, so the device
/// locale never changes what a screen says. A date that cannot be parsed
/// comes back as sent, never empty and never "Invalid Date".
abstract final class TainaFormat {
  static const List<String> _months = [
    'jan.',
    'fev.',
    'mar.',
    'abr.',
    'mai.',
    'jun.',
    'jul.',
    'ago.',
    'set.',
    'out.',
    'nov.',
    'dez.',
  ];

  /// Bytes for a person: "834 B", "1,2 KB", "2,4 MB", "1,8 GB".
  ///
  /// Decimal comma, one decimal above KB, like the web.
  static String bytes(int count) {
    const double kilo = 1024;
    final double value = count.toDouble();
    if (value < kilo) return '$count B';
    if (value < kilo * kilo) return '${_decimal(value / kilo)} KB';
    if (value < kilo * kilo * kilo) {
      return '${_decimal(value / (kilo * kilo))} MB';
    }
    return '${_decimal(value / (kilo * kilo * kilo))} GB';
  }

  /// "10 de mar. de 2026 às 14:00".
  static String date(String iso) {
    final DateTime? parsed = _parse(iso);
    if (parsed == null) return iso;
    final DateTime local = parsed.toLocal();
    final String day = '${local.day}';
    final String month = _months[local.month - 1];
    final String time = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
    return '$day de $month de ${local.year} às $time';
  }

  /// "hoje", "ontem", "3 dias", then a short date. For list rows.
  ///
  /// [now] exists so pure tests can pin the clock; screens use the default.
  static String relative(String iso, {DateTime? now}) {
    final DateTime? parsed = _parse(iso);
    if (parsed == null) return iso;

    final DateTime local = parsed.toLocal();
    final DateTime today = now ?? DateTime.now();
    final int days = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;

    return switch (days) {
      0 => 'hoje',
      1 => 'ontem',
      >= 2 && < 7 => '$days dias',
      _ => _numericDate(local),
    };
  }

  /// The dot of `toStringAsFixed` is the comma a Brazilian reads.
  static String _decimal(double value) =>
      value.toStringAsFixed(1).replaceAll('.', ',');

  static String _numericDate(DateTime local) {
    final String day = _twoDigits(local.day);
    final String month = _twoDigits(local.month);
    return '$day/$month/${local.year}';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static DateTime? _parse(String iso) {
    if (iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }
}
