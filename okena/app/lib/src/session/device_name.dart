import 'dart:io';

/// The default name of the device a session is created from.
///
/// The Swift app sends `UIDevice.current.name`; without a device-info plugin
/// the hostname is the closest platform value a mobile app can read. The
/// person can always replace it in the login form.
abstract final class DeviceName {
  static String get current {
    try {
      final name = Platform.localHostname.trim();
      return name.isEmpty ? 'Aparelho' : name;
    } on Object {
      return 'Aparelho';
    }
  }
}
