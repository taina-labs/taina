import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

/// The local-network runtime permission Android 17 (API 37) asks for before
/// an app may talk to a box on the same network.
///
/// The gate is a boundary, not a screen concern: `connect` asks it once and
/// reports a network failure when the person declines. On earlier Android
/// versions, iOS and tests it is a no-op, so it never blocks a supported flow.
abstract class LocalNetworkGate {
  Future<bool> ensure();
}

/// The real gate, through `permission_handler`.
///
/// `Permission.accessLocalNetwork` maps to `ACCESS_LOCAL_NETWORK`. The
/// platform plugin returns "granted" before API 37 and on iOS, so no version
/// branch lives here.
final class PermissionLocalNetworkGate implements LocalNetworkGate {
  const PermissionLocalNetworkGate();

  @override
  Future<bool> ensure() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.accessLocalNetwork.request();
    return status.isGranted;
  }
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
