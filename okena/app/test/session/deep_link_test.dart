import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/session/deep_link.dart';

void main() {
  group('native links', () {
    test('parses an invite with its box address', () {
      final link = DeepLink.parse(
        Uri.parse('taina://convite/tk9x2m5qp7w4v8?host=taina.sapukai.ts.net'),
      );

      expect(link, isNotNull);
      expect(link!.kind, DeepLinkKind.invite);
      expect(link.token, 'tk9x2m5qp7w4v8');
      expect(link.box, 'taina.sapukai.ts.net');
    });

    test('parses a reset with a full address in the query', () {
      final link = DeepLink.parse(
        Uri.parse('taina://redefinir/tk1?host=https%3A%2F%2Fbox.local%3A8443'),
      );

      expect(link!.kind, DeepLinkKind.reset);
      expect(link.token, 'tk1');
      expect(link.box, 'https://box.local:8443');
    });

    test('a link without a host query leaves the box unknown', () {
      final link = DeepLink.parse(Uri.parse('taina://convite/tk1'));
      expect(link!.box, isNull);
    });

    test('an empty host query is the same as absent', () {
      final link = DeepLink.parse(Uri.parse('taina://convite/tk1?host=%20'));
      expect(link!.box, isNull);
    });

    test('decodes a percent-encoded token', () {
      final link = DeepLink.parse(Uri.parse('taina://convite/tk%201'));
      expect(link!.token, 'tk 1');
    });

    test('rejects another kind', () {
      expect(DeepLink.parse(Uri.parse('taina://outra/tk1')), isNull);
    });

    test('rejects a missing token', () {
      expect(DeepLink.parse(Uri.parse('taina://convite/')), isNull);
      expect(DeepLink.parse(Uri.parse('taina://convite')), isNull);
    });

    test('rejects a token with more than one path piece', () {
      expect(DeepLink.parse(Uri.parse('taina://convite/a/b')), isNull);
      expect(DeepLink.parse(Uri.parse('taina://convite/tk1/')), isNull);
    });
  });

  group('web links', () {
    test('parses an https invite and keeps the address whole', () {
      final link = DeepLink.parse(
        Uri.parse('https://box.local/convite/tk9x2m5qp7w4v8'),
      );

      expect(link!.kind, DeepLinkKind.invite);
      expect(link.token, 'tk9x2m5qp7w4v8');
      expect(link.box, 'https://box.local');
    });

    test('keeps the port and the cleartext scheme as typed', () {
      final link = DeepLink.parse(
        Uri.parse('http://box.local:8080/redefinir/tk1'),
      );

      expect(link!.kind, DeepLinkKind.reset);
      expect(link.token, 'tk1');
      expect(link.box, 'http://box.local:8080');
    });

    test('rejects the wrong number of path pieces', () {
      expect(DeepLink.parse(Uri.parse('https://box.local/convite')), isNull);
      expect(
        DeepLink.parse(Uri.parse('https://box.local/convite/a/b')),
        isNull,
      );
    });

    test('rejects another path kind', () {
      expect(DeepLink.parse(Uri.parse('https://box.local/outra/tk1')), isNull);
    });
  });

  group('pasted links', () {
    test('trims the whitespace a copy picks up', () {
      final link = DeepLink.parsePasted('  taina://convite/tk1  \n');
      expect(link!.token, 'tk1');
    });

    test('reads a pasted web link too', () {
      final link = DeepLink.parsePasted('https://box.local/redefinir/tk1');
      expect(link!.kind, DeepLinkKind.reset);
    });

    test('empty or foreign text is not a link', () {
      expect(DeepLink.parsePasted(''), isNull);
      expect(DeepLink.parsePasted('nada'), isNull);
      expect(DeepLink.parsePasted('https://example.com/'), isNull);
    });
  });

  test('rejects another scheme', () {
    expect(DeepLink.parse(Uri.parse('tel:+5511999999999')), isNull);
  });
}
