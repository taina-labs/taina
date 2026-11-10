import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/session/preferences_host_store.dart';
import 'package:okena_app/src/session/secure_session_storage.dart';
import 'package:okena_core/okena_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureSessionStorage', () {
    test('round trips the whole session as JSON under one key', () async {
      final keyvalues = MemorySecureKeyValueStore();
      final storage = SecureSessionStorage(store: keyvalues);
      final session = testSession();

      expect((await storage.save(session)).isSuccess, isTrue);
      expect(keyvalues.values.keys, ['session']);

      final stored = jsonDecode(keyvalues.values['session']!);
      expect((stored as Map)['token'], session.token);

      expect((await storage.load()).value, session);
    });

    test('absence is a success with no session', () async {
      final storage = SecureSessionStorage(store: MemorySecureKeyValueStore());
      final loaded = await storage.load();
      expect(loaded.isSuccess, isTrue);
      expect(loaded.value, isNull);
    });

    test('clear removes the item and is idempotent', () async {
      final keyvalues = MemorySecureKeyValueStore();
      final storage = SecureSessionStorage(store: keyvalues);
      await storage.save(testSession());

      expect((await storage.clear()).isSuccess, isTrue);
      expect(keyvalues.values, isEmpty);
      expect((await storage.clear()).isSuccess, isTrue);
      expect((await storage.load()).value, isNull);
    });

    test('an unreadable body is an invalid response, not a crash', () async {
      final storage = SecureSessionStorage(
        store: MemorySecureKeyValueStore({'session': 'not json'}),
      );

      final loaded = await storage.load();
      expect(loaded.error, const InvalidResponseError('stored session'));
    });

    test('a platform failure becomes a secure storage error', () async {
      final storage = SecureSessionStorage(
        store: const ThrowingSecureKeyValueStore(),
      );

      expect((await storage.save(testSession())).isFailure, isTrue);
      expect((await storage.load()).error, isA<SecureStorageError>());
      expect((await storage.clear()).error, isA<SecureStorageError>());
    });
  });

  group('PreferencesHostStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves, reads back through a second instance and clears', () async {
      final address = testBox('http://box.local:8080');
      final store = PreferencesHostStore();

      expect((await store.save(address)).isSuccess, isTrue);
      expect(await store.address(), address);

      final reopened = PreferencesHostStore(
        preferences: await SharedPreferences.getInstance(),
      );
      expect(await reopened.address(), address);

      await reopened.clear();
      expect(await reopened.address(), isNull);
    });

    test('an unreadable saved address reads as absent', () async {
      SharedPreferences.setMockInitialValues({'taina.host': 'not a url'});
      final store = PreferencesHostStore();
      expect(await store.address(), isNull);
    });
  });
}
