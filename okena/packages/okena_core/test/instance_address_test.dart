import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

InstanceAddress address(String input) => InstanceAddress.parse(input).value!;

TainaError failure(String input) => InstanceAddress.parse(input).error!;

void main() {
  group('InstanceAddress.parse', () {
    test('a bare host gets https', () {
      expect(
        address('taina.minhacasa.ts.net').url.toString(),
        'https://taina.minhacasa.ts.net',
      );
    });

    test('a trailing slash is dropped', () {
      expect(
        address('https://taina.local/').url.toString(),
        'https://taina.local',
      );
      expect(address('taina.local/').url.toString(), 'https://taina.local');
    });

    test('whitespace is trimmed', () {
      expect(address('  taina.local \n').url.toString(), 'https://taina.local');
    });

    test('the port is kept', () {
      expect(
        address('http://10.0.0.5:4000').url.toString(),
        'http://10.0.0.5:4000',
      );
    });

    test('lan and dot local names over http are accepted', () {
      expect(address('http://taina').url.toString(), 'http://taina');
      expect(
        address('http://taina.local').url.toString(),
        'http://taina.local',
      );
    });

    test('private ipv4 over http is accepted', () {
      for (final host in [
        '192.168.1.10',
        '10.0.0.5',
        '127.0.0.1',
        '169.254.10.2',
        '172.16.0.1',
        '172.31.255.255',
      ]) {
        expect(address('http://$host').url.host, host, reason: host);
      }
    });

    test('cleartext is accepted on any host', () {
      final tailnet = address('http://taina.yby');
      expect(tailnet.url.toString(), 'http://taina.yby');
      expect(tailnet.isCleartext, isTrue);

      expect(address('http://exemplo.com').isCleartext, isTrue);
      expect(InstanceAddress.parse('http://172.32.0.1').value, isNotNull);
      expect(InstanceAddress.parse('http://11.0.0.5').value, isNotNull);
    });

    test('https is not cleartext', () {
      expect(address('https://exemplo.com').isCleartext, isFalse);
      expect(address('exemplo.com').isCleartext, isFalse);
    });

    test('cleartext keeps the port and displays the host', () {
      final parsed = address('http://taina.yby:4000');
      expect(parsed.url.toString(), 'http://taina.yby:4000');
      expect(parsed.display, 'taina.yby');
    });

    test('https is always accepted', () {
      expect(
        address('https://exemplo.com').url.toString(),
        'https://exemplo.com',
      );
    });

    test('another scheme is unsupported', () {
      expect(
        failure('ftp://taina.local'),
        const InvalidAddressError(AddressProblem.unsupportedScheme),
      );
    });

    test('empty input is empty', () {
      expect(failure(''), const InvalidAddressError(AddressProblem.empty));
      expect(
        failure('   \n\t'),
        const InvalidAddressError(AddressProblem.empty),
      );
    });

    test('a missing host is malformed', () {
      expect(
        failure('https://'),
        const InvalidAddressError(AddressProblem.malformed),
      );
    });

    test('embedded credentials are malformed', () {
      expect(
        failure('https://user:pass@exemplo.com'),
        const InvalidAddressError(AddressProblem.malformed),
      );
    });

    test('path, query and fragment are dropped', () {
      expect(
        address('https://exemplo.com/painel?x=1#topo').url.toString(),
        'https://exemplo.com',
      );
    });

    test('local ipv6 over http is accepted', () {
      expect(InstanceAddress.parse('http://[::1]:4000').value, isNotNull);
      expect(InstanceAddress.parse('http://[fe80::1]').value, isNotNull);
      expect(InstanceAddress.parse('http://[fd7a:4c2d::1]').value, isNotNull);
    });

    test('display is the bare host', () {
      expect(
        address('https://taina.minhacasa.ts.net:8443').display,
        'taina.minhacasa.ts.net',
      );
    });

    test('a persisted canonical address round trips through fromStored', () {
      final parsed = address('http://taina.yby:4000');
      final restored = InstanceAddress.fromStored(parsed.url.toString()).value!;
      expect(restored, parsed);
      expect(
        InstanceAddress.fromStored('ftp://x').error,
        const InvalidAddressError(AddressProblem.unsupportedScheme),
      );
    });
  });

  group('InstanceAddress.candidates', () {
    test('a bare host offers an http fallback', () {
      final candidates = InstanceAddress.candidates('taina.yby').value!;
      expect(candidates.primary.url.toString(), 'https://taina.yby');
      expect(candidates.fallback!.url.toString(), 'http://taina.yby');
    });

    test('an explicit scheme has no fallback', () {
      final https = InstanceAddress.candidates('https://taina.yby').value!;
      expect(https.fallback, isNull);

      final http = InstanceAddress.candidates('http://taina.yby').value!;
      expect(http.primary.url.toString(), 'http://taina.yby');
      expect(http.fallback, isNull);
    });

    test('the fallback keeps the port', () {
      final candidates = InstanceAddress.candidates('taina.yby:4000').value!;
      expect(candidates.primary.url.toString(), 'https://taina.yby:4000');
      expect(candidates.fallback!.url.toString(), 'http://taina.yby:4000');
    });

    test('candidates carry the parse error', () {
      expect(
        InstanceAddress.candidates('').error,
        const InvalidAddressError(AddressProblem.empty),
      );
      expect(
        InstanceAddress.candidates('ftp://x').error,
        const InvalidAddressError(AddressProblem.unsupportedScheme),
      );
    });
  });
}
