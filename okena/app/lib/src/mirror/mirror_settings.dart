// The public named parameter cannot be an initializing formal because the
// field it assigns is private.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:okena_core/okena_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-owner settings for the one-way camera-roll mirror.
final class MirrorPreferences {
  const MirrorPreferences({this.enabled = false, this.wifiOnly = true});

  final bool enabled;
  final bool wifiOnly;

  MirrorPreferences copyWith({bool? enabled, bool? wifiOnly}) {
    return MirrorPreferences(
      enabled: enabled ?? this.enabled,
      wifiOnly: wifiOnly ?? this.wifiOnly,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MirrorPreferences &&
      other.enabled == enabled &&
      other.wifiOnly == wifiOnly;

  @override
  int get hashCode => Object.hash(enabled, wifiOnly);
}

/// Loads and stores mirror preferences for a single owner.
abstract interface class MirrorSettings {
  Future<TainaResult<MirrorPreferences>> load(String ownerId);

  Future<TainaResult<void>> save(String ownerId, MirrorPreferences preferences);
}

/// Stores each owner's two settings together as one preferences value.
final class PreferencesMirrorSettings implements MirrorSettings {
  static bool _prefixConfigured = false;

  PreferencesMirrorSettings({SharedPreferences? preferences})
    : _preferences = preferences;

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
    final existing = _preferences;
    if (existing != null) return existing;
    if (!_prefixConfigured) {
      SharedPreferences.setPrefix('');
      _prefixConfigured = true;
    }
    return _preferences = await SharedPreferences.getInstance();
  }

  @override
  Future<TainaResult<MirrorPreferences>> load(String ownerId) async {
    try {
      final stored = (await _prefs).getString(_key(ownerId));
      return Ok(stored == null ? const MirrorPreferences() : _decode(stored));
    } on Exception {
      return const Err(
        InvalidResponseError('mirror preferences could not be loaded'),
      );
    }
  }

  @override
  Future<TainaResult<void>> save(
    String ownerId,
    MirrorPreferences preferences,
  ) async {
    try {
      final saved = await (await _prefs).setString(
        _key(ownerId),
        jsonEncode({
          'enabled': preferences.enabled,
          'wifiOnly': preferences.wifiOnly,
        }),
      );
      if (!saved) {
        return const Err(
          InvalidResponseError('mirror preferences could not be stored'),
        );
      }
      return const Ok<void>(null);
    } on Exception {
      return const Err(
        InvalidResponseError('mirror preferences could not be stored'),
      );
    }
  }

  static String _key(String ownerId) {
    final encodedOwner = base64Url
        .encode(utf8.encode(ownerId))
        .replaceAll('=', '');
    return 'taina.mirror.$encodedOwner';
  }

  static MirrorPreferences _decode(String stored) {
    Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } on FormatException {
      return const MirrorPreferences();
    }
    if (decoded is! Map<String, dynamic>) {
      return const MirrorPreferences();
    }
    final enabled = decoded['enabled'];
    final wifiOnly = decoded['wifiOnly'];
    if (enabled is! bool || wifiOnly is! bool) {
      return const MirrorPreferences();
    }
    return MirrorPreferences(enabled: enabled, wifiOnly: wifiOnly);
  }
}
