import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// The local-network runtime permission Android 17 (API 37) asks for before
/// an app may talk to a box on the same network.
///
/// The gate is a boundary, not a screen concern: `connect` asks it once and
/// reports a network failure when the person declines. On earlier Android
/// versions it allows the connection without requesting a permission. Other
/// platforms are a no-op.
abstract class LocalNetworkGate {
  Future<bool> ensure();
}

/// The real gate, through `permission_handler`.
///
/// `Permission.accessLocalNetwork` maps to `ACCESS_LOCAL_NETWORK`. Android
/// versions before API 37 do not expose that permission, so they are allowed
/// through without consulting `permission_handler`.
final class PermissionLocalNetworkGate implements LocalNetworkGate {
  const PermissionLocalNetworkGate({
    bool Function()? isAndroid,
    Future<int> Function()? androidSdkVersion,
    Future<PermissionStatus> Function()? requestPermission,
  }) : _isAndroid = isAndroid ?? _isAndroidPlatform,
       _androidSdkVersion = androidSdkVersion ?? _readAndroidSdkVersion,
       _requestPermission = requestPermission ?? _requestLocalNetworkPermission;

  static const _androidDeviceChannel = MethodChannel('io.taina.app/device');

  final bool Function() _isAndroid;
  final Future<int> Function() _androidSdkVersion;
  final Future<PermissionStatus> Function() _requestPermission;

  @override
  Future<bool> ensure() async {
    if (!_isAndroid()) return true;
    if (await _androidSdkVersion() < 37) return true;
    final status = await _requestPermission();
    return status.isGranted;
  }

  static bool _isAndroidPlatform() => Platform.isAndroid;

  static Future<int> _readAndroidSdkVersion() async {
    final sdkVersion = await _androidDeviceChannel.invokeMethod<int>('sdkInt');
    if (sdkVersion == null) {
      throw StateError('Android SDK version channel returned no value');
    }
    return sdkVersion;
  }

  static Future<PermissionStatus> _requestLocalNetworkPermission() =>
      Permission.accessLocalNetwork.request();
}

/// Allows every connect: the fake composition and the widget tests.
final class AllowLocalNetworkGate implements LocalNetworkGate {
  const AllowLocalNetworkGate();

  @override
  Future<bool> ensure() async => true;
}

/// Refuses every connect: the permission-denied path.
final class DenyLocalNetworkGate implements LocalNetworkGate {
  const DenyLocalNetworkGate();

  @override
  Future<bool> ensure() async => false;
}
