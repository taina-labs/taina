import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';

void main() {
  group('bytes', () {
    test('keeps whole bytes below one kilobyte', () {
      expect(TainaFormat.bytes(0), '0 B');
      expect(TainaFormat.bytes(834), '834 B');
      expect(TainaFormat.bytes(1023), '1023 B');
    });

    test('uses one decimal and a comma above the kilobyte', () {
      expect(TainaFormat.bytes(1024), '1,0 KB');
      expect(TainaFormat.bytes(1229), '1,2 KB');
      expect(TainaFormat.bytes(1536), '1,5 KB');
      expect(TainaFormat.bytes(1024 * 1024 - 1), '1024,0 KB');
    });

    test('walks to megabytes and gigabytes at 1024 steps', () {
      expect(TainaFormat.bytes(1024 * 1024), '1,0 MB');
      expect(TainaFormat.bytes((2.4 * 1024 * 1024).round()), '2,4 MB');
      expect(TainaFormat.bytes(1024 * 1024 * 1024), '1,0 GB');
      expect(TainaFormat.bytes((1.8 * 1024 * 1024 * 1024).round()), '1,8 GB');
    });
  });

  group('date', () {
    test('prints the abbreviated pt-BR date and the short time', () {
      expect(TainaFormat.date('2026-03-10'), '10 de mar. de 2026 às 00:00');
      expect(TainaFormat.date('2026-03-05'), '5 de mar. de 2026 às 00:00');
      expect(
        TainaFormat.date('2026-12-31T09:07:00'),
        '31 de dez. de 2026 às 09:07',
      );
    });

    test('parses ISO 8601 with an offset and fractional seconds', () {
      final String formatted = TainaFormat.date(
        '2026-03-10T17:00:00.123-03:00',
      );
      expect(formatted, contains(' de mar. de 2026 às '));
      expect(formatted, isNot(contains('-03:00')));
    });

    test('returns an unparsable date as sent', () {
      expect(TainaFormat.date('ontem'), 'ontem');
      expect(TainaFormat.date(''), '');
    });
  });

  group('relative', () {
    final DateTime now = DateTime(2026, 3, 10, 12);

    test('says hoje and ontem for the last two days', () {
      expect(TainaFormat.relative('2026-03-10', now: now), 'hoje');
      expect(TainaFormat.relative('2026-03-09', now: now), 'ontem');
    });

    test('counts days between two and six', () {
      expect(TainaFormat.relative('2026-03-08', now: now), '2 dias');
      expect(TainaFormat.relative('2026-03-04', now: now), '6 dias');
    });

    test('falls back to a short date from seven days on', () {
      expect(TainaFormat.relative('2026-03-03', now: now), '03/03/2026');
      expect(TainaFormat.relative('2025-12-24', now: now), '24/12/2025');
    });

    test('uses the short date for a future date', () {
      expect(TainaFormat.relative('2026-03-11', now: now), '11/03/2026');
    });

    test('returns an unparsable date as sent', () {
      expect(TainaFormat.relative('não é data', now: now), 'não é data');
      expect(TainaFormat.relative('', now: now), '');
    });
  });
}
