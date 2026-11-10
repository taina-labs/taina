import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:okena_core/okena_core.dart';

/// The tiny key/value seam over the platform keystore.
///
/// Keeping it this small is what makes the session JSON round trip testable
/// without a real Keychain or Keystore.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The real store, through `flutter_secure_storage`.
///
/// The item is readable only while the device is unlocked and never migrates
/// to another device, like the Swift `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
final class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accountName: 'io.taina.app',
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The platform-backed session storage: the whole session, as the wire JSON,
/// under one Keychain/Keystore item.
///
/// The token is a credential and never leaves this boundary; nothing here
/// prints it.
final class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({SecureKeyValueStore? store, this.key = 'session'})
    : _store = store ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _store;
  final String key;

  @override
  Future<TainaResult<void>> save(Session session) async {
    try {
      await _store.write(key, jsonEncode(session.toJson()));
      return const Ok<void>(null);
    } on PlatformException catch (error) {
      return Err(SecureStorageError(error.message ?? error.code));
    } on MissingPluginException catch (error) {
      return Err(SecureStorageError(error.message ?? 'secure storage missing'));
    }
  }

  @override
  Future<TainaResult<Session?>> load() async {
    final String? raw;
    try {
      raw = await _store.read(key);
    } on PlatformException catch (error) {
      return Err(SecureStorageError(error.message ?? error.code));
    } on MissingPluginException catch (error) {
      return Err(SecureStorageError(error.message ?? 'secure storage missing'));
    }
    if (raw == null) return const Ok<Session?>(null);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const Err(InvalidResponseError('stored session'));
      }
      return Ok<Session?>(
        Session.fromPersistedJson(decoded.cast<String, Object?>()),
      );
    } on FormatException {
      return const Err(InvalidResponseError('stored session'));
    } on TypeError {
      return const Err(InvalidResponseError('stored session'));
    }
  }

  @override
  Future<TainaResult<void>> clear() async {
    try {
      await _store.delete(key);
      return const Ok<void>(null);
    } on PlatformException catch (error) {
      return Err(SecureStorageError(error.message ?? error.code));
    } on MissingPluginException catch (error) {
      return Err(SecureStorageError(error.message ?? 'secure storage missing'));
    }
  }
}
