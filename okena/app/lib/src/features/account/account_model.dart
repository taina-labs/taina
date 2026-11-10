import 'package:flutter/foundation.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The account's state: who is acting, which devices and which community.
///
/// Signing out is owned by the session, never by this model: the screen calls
/// the orchestrator's callback so the session stays authoritative. The
/// password is self-service: the box keeps this device signed in and revokes
/// the others.
final class AccountModel extends ChangeNotifier {
  AccountModel({required this.gateway});

  final SessionGateway gateway;

  Me? _me;
  bool _loading = true;
  TainaError? _error;
  List<DeviceToken>? _devices;
  TainaError? _devicesError;
  TainaError? _actionError;
  String? _revokingDevice;
  String? _version;
  bool _changing = false;
  bool _changed = false;
  TainaError? _passwordFailure;
  String? _mismatch;
  bool _disposed = false;

  Me? get me => _me;
  bool get loading => _loading;
  TainaError? get error => _error;
  List<DeviceToken>? get devices => _devices;
  TainaError? get devicesError => _devicesError;
  TainaError? get actionError => _actionError;
  String? get revokingDevice => _revokingDevice;
  String? get version => _version;
  bool get changing => _changing;
  bool get changed => _changed;
  TainaError? get passwordFailure => _passwordFailure;
  String? get mismatch => _mismatch;

  List<String> get currentPasswordErrors =>
      _passwordFailure?.messagesFor(['current_password']) ?? const [];

  List<String> get newPasswordErrors =>
      _passwordFailure?.messagesFor(['new_password', 'password']) ?? const [];

  Future<void> load() async {
    _loading = true;
    _notify();
    await _loadIdentity();
    await loadDevices();
    _loading = false;
    _notify();
  }

  Future<void> loadDevices() async {
    final result = await gateway.screen(await gateway.api.devices());
    switch (result) {
      case Ok(:final value):
        _devices = value;
        _devicesError = null;
      case Err(:final error):
        // With a list already on screen, the failure is the alert, not a
        // replacement of the section.
        if (_devices == null) {
          _devicesError = error;
        } else {
          _actionError = error;
        }
    }
    _notify();
  }

  /// Revokes one device that is not this one. The list is read again, so the
  /// row says revoked with the date.
  Future<TainaResult<void>> revokeDevice(String id) async {
    _revokingDevice = id;
    _actionError = null;
    _notify();
    final result = await gateway.screen(await gateway.api.revokeDevice(id: id));
    switch (result) {
      case Ok():
        await loadDevices();
      case Err(:final error):
        _actionError = error;
    }
    _revokingDevice = null;
    _notify();
    return result;
  }

  /// The self-service password change. The local rule the wire does not carry
  /// is the confirmation match; the box's answer lands as field messages or
  /// the success line. Returns whether the change was accepted.
  Future<bool> changePassword({
    required String current,
    required String newPassword,
    required String confirmation,
  }) async {
    _passwordFailure = null;
    _mismatch = null;
    _changed = false;
    if (!confirmationMatches(
      password: newPassword,
      confirmation: confirmation,
    )) {
      _mismatch = 'As duas senhas não são iguais.';
      _notify();
      return false;
    }
    _changing = true;
    _notify();
    final result = await gateway.screen(
      await gateway.api.updatePassword(
        current: current,
        newPassword: newPassword,
      ),
    );
    switch (result) {
      case Ok():
        _changed = true;
        // The other devices were revoked on the box: the list says so.
        await loadDevices();
      case Err(:final error):
        _passwordFailure = error;
    }
    _changing = false;
    _notify();
    return result.isSuccess;
  }

  void clearActionError() {
    _actionError = null;
    _notify();
  }

  Future<void> _loadIdentity() async {
    final result = await gateway.screen(await gateway.api.me());
    switch (result) {
      case Ok(:final value):
        _me = value;
        _error = null;
      case Err(:final error):
        _error = error;
    }
    final instance = await gateway.screen(await gateway.api.instance());
    if (instance case Ok(:final value)) {
      _version = value.version;
    }
  }

  // Pure transitions.

  /// The local rule the wire does not carry: the two passwords must match.
  static bool confirmationMatches({
    required String password,
    required String confirmation,
  }) {
    return password == confirmation;
  }

  /// One line per device: revoked when it is, the last use otherwise.
  static String deviceLine(DeviceToken device) {
    final String? revoked = device.revokedAt;
    if (revoked != null) return 'Revogado em ${TainaFormat.date(revoked)}';
    final String? used = device.lastUsedAt;
    if (used != null) return 'Último uso em ${TainaFormat.date(used)}';
    return 'Nunca usado';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
