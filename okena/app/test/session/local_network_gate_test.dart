import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/session/local_network_gate.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PermissionLocalNetworkGate', () {
    test(
      'allows Android SDK versions before 37 without requesting permission',
      () async {
        var permissionRequested = false;

        final gate = PermissionLocalNetworkGate(
          isAndroid: () => true,
          androidSdkVersion: () async => 36,
          requestPermission: () async {
            permissionRequested = true;
            return PermissionStatus.denied;
          },
        );

        expect(await gate.ensure(), isTrue);
        expect(permissionRequested, isFalse);
      },
    );

    test('allows API 37 when local network permission is granted', () async {
      var permissionRequested = false;

      final gate = PermissionLocalNetworkGate(
        isAndroid: () => true,
        androidSdkVersion: () async => 37,
        requestPermission: () async {
          permissionRequested = true;
          return PermissionStatus.granted;
        },
      );

      expect(await gate.ensure(), isTrue);
      expect(permissionRequested, isTrue);
    });

    test('blocks API 37 when local network permission is denied', () async {
      var permissionRequested = false;

      final gate = PermissionLocalNetworkGate(
        isAndroid: () => true,
        androidSdkVersion: () async => 37,
        requestPermission: () async {
          permissionRequested = true;
          return PermissionStatus.denied;
        },
      );

      expect(await gate.ensure(), isFalse);
      expect(permissionRequested, isTrue);
    });

    test(
      'does not query native SDK or permission on non-Android platforms',
      () async {
        var sdkVersionRead = false;
        var permissionRequested = false;

        final gate = PermissionLocalNetworkGate(
          isAndroid: () => false,
          androidSdkVersion: () async {
            sdkVersionRead = true;
            return 37;
          },
          requestPermission: () async {
            permissionRequested = true;
            return PermissionStatus.denied;
          },
        );

        expect(await gate.ensure(), isTrue);
        expect(sdkVersionRead, isFalse);
        expect(permissionRequested, isFalse);
      },
    );

    test('decodes the SDK version from the Android method channel', () async {
      const channel = MethodChannel('io.taina.app/device');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'sdkInt');
            return 37;
          });

      var permissionRequested = false;
      final gate = PermissionLocalNetworkGate(
        isAndroid: () => true,
        requestPermission: () async {
          permissionRequested = true;
          return PermissionStatus.granted;
        },
      );

      expect(await gate.ensure(), isTrue);
      expect(permissionRequested, isTrue);
    });
  });
}
