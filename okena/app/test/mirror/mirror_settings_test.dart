import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/mirror_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PreferencesMirrorSettings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SharedPreferences.setPrefix('');
    });

    test('missing settings use safe defaults', () async {
      final settings = PreferencesMirrorSettings();

      final result = await settings.load('owner');

      expect(result.value, const MirrorPreferences());
      expect(result.value!.enabled, isFalse);
      expect(result.value!.wifiOnly, isTrue);
    });

    test('corrupt settings use safe defaults', () async {
      SharedPreferences.setMockInitialValues({
        _keyFor('owner'): '{not valid json',
      });
      final settings = PreferencesMirrorSettings();

      final result = await settings.load('owner');

      expect(result.value, const MirrorPreferences());
    });

    test('incomplete or invalid settings use safe defaults', () async {
      SharedPreferences.setMockInitialValues({
        _keyFor('owner'): '{"enabled":true}',
      });
      final settings = PreferencesMirrorSettings();

      final result = await settings.load('owner');

      expect(result.value, const MirrorPreferences());
    });

    test('saves and loads both preference values', () async {
      final settings = PreferencesMirrorSettings();
      const expected = MirrorPreferences(enabled: true, wifiOnly: false);

      final saved = await settings.save('owner', expected);
      final loaded = await settings.load('owner');

      expect(saved.isSuccess, isTrue);
      expect(loaded.value, expected);
    });

    test('isolates owners including community-qualified IDs', () async {
      final settings = PreferencesMirrorSettings();
      const first = 'tekoaId:avaId';
      const second = 'tekoaId:biaId';

      await settings.save(
        first,
        const MirrorPreferences(enabled: true, wifiOnly: false),
      );
      await settings.save(second, const MirrorPreferences(enabled: false));

      expect(
        (await settings.load(first)).value,
        const MirrorPreferences(enabled: true, wifiOnly: false),
      );
      expect((await settings.load(second)).value, const MirrorPreferences());
    });

    test('keys encode owner IDs without storing raw owner text', () async {
      const ownerId = 'tekoaId:avaId';
      final settings = PreferencesMirrorSettings();

      await settings.save(ownerId, const MirrorPreferences(enabled: true));

      final preferences = await SharedPreferences.getInstance();
      final keys = preferences.getKeys();
      expect(keys, {_keyFor(ownerId)});
      expect(keys.single, startsWith('taina.mirror.'));
      expect(keys.single, isNot(contains(ownerId)));
    });

    test('separate stores read the same persisted settings', () async {
      final firstStore = PreferencesMirrorSettings();
      const expected = MirrorPreferences(enabled: true, wifiOnly: false);
      final saved = await firstStore.save('owner', expected);

      final secondStore = PreferencesMirrorSettings();
      final loaded = await secondStore.load('owner');

      expect(saved.isSuccess, isTrue);
      expect(loaded.value, expected);
    });
  });
}

String _keyFor(String ownerId) {
  final encodedOwner = base64Url
      .encode(utf8.encode(ownerId))
      .replaceAll('=', '');
  return 'taina.mirror.$encodedOwner';
}
