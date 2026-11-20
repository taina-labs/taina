import 'package:flutter/foundation.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// Loads and revokes the devices with access to this community.
final class DevicesModel extends ChangeNotifier {
  DevicesModel({required this.gateway})
    : _currentDevice = gateway.identity?.device;

  final SessionGateway gateway;

  DeviceToken? _currentDevice;
  List<DeviceToken>? _devices;
  bool _loading = true;
  TainaError? _error;
  TainaError? _actionError;
  String? _revokingDevice;
  bool _disposed = false;

  DeviceToken? get currentDevice => _currentDevice;
  List<DeviceToken>? get devices => _devices;
  bool get loading => _loading;
  TainaError? get error => _error;
  TainaError? get actionError => _actionError;
  String? get revokingDevice => _revokingDevice;

  Future<void> load() async {
    _loading = true;
    _notify();
    await _loadCurrentDevice();
    await loadDevices();
    _loading = false;
    _notify();
  }

  Future<void> loadDevices() async {
    final TainaResult<List<DeviceToken>> result = await gateway.screen(
      await gateway.api.devices(),
    );
    switch (result) {
      case Ok(:final value):
        _devices = List<DeviceToken>.unmodifiable(value);
        _error = null;
        _actionError = null;
      case Err(:final error):
        if (_devices == null) {
          _error = error;
        } else {
          _actionError = error;
        }
    }
    _notify();
  }

  Future<TainaResult<void>> revokeDevice(String id) async {
    _revokingDevice = id;
    _actionError = null;
    _notify();
    final TainaResult<void> result = await gateway.screen(
      await gateway.api.revokeDevice(id: id),
    );
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

  static String deviceLine(DeviceToken device) {
    final String? revoked = device.revokedAt;
    if (revoked != null) return 'Revogado em ${TainaFormat.date(revoked)}';
    final String? used = device.lastUsedAt;
    if (used != null) return 'Último uso em ${TainaFormat.date(used)}';
    return 'Nunca usado';
  }

  Future<void> _loadCurrentDevice() async {
    final TainaResult<Me> result = await gateway.screen(await gateway.api.me());
    if (result case Ok(:final value)) {
      _currentDevice = value.device;
    }
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
