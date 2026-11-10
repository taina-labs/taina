// The public named parameter cannot be an initializing formal because the
// field it assigns is private.
// ignore_for_file: prefer_initializing_formals

import 'package:okena_core/okena_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the box address lives between launches.
///
/// The address is not a secret: it goes to `shared_preferences`, like the
/// Swift `UserDefaultsHostStore`. The token continues in platform secure
/// storage. The value was written by `InstanceAddress.parse`, so reading it
/// only re-validates it.
final class PreferencesHostStore implements HostStore {
  PreferencesHostStore({
    this.key = 'taina.host',
    SharedPreferences? preferences,
  }) : _preferences = preferences;

  final String key;
  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
    final existing = _preferences;
    if (existing != null) return existing;
    // Swift wrote the raw UserDefaults key. Flutter's default prefix would
    // otherwise hide it behind `flutter.taina.host` during an in-place upgrade.
    SharedPreferences.setPrefix('');
    return _preferences = await SharedPreferences.getInstance();
  }

  @override
  Future<InstanceAddress?> address() async {
    final stored = (await _prefs).getString(key);
    if (stored == null) return null;
    // The value was written by save, so it carries a scheme and no spaces.
    // Anything else is a corrupted item, which reads as absence.
    if (!stored.contains('://') || stored.contains(RegExp(r'\s'))) {
      return null;
    }
    final parsed = InstanceAddress.fromStored(stored).value;
    if (parsed == null) return null;
    return parsed;
  }

  @override
  Future<TainaResult<void>> save(InstanceAddress address) async {
    final saved = await (await _prefs).setString(key, address.url.toString());
    if (!saved) {
      return const Err(InvalidResponseError('host could not be stored'));
    }
    return const Ok<void>(null);
  }

  @override
  Future<void> clear() async {
    await (await _prefs).remove(key);
  }
}
