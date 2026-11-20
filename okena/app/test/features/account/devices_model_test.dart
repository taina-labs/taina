import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/account/devices_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

void main() {
  test('loads the devices and identifies the current one', () async {
    final DevicesApi api = DevicesApi(
      FakeTainaApi(delay: Duration.zero),
      const [currentDevice, otherDevice],
    );
    final DevicesModel model = DevicesModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    await model.load();

    expect(model.devices, hasLength(2));
    expect(model.currentDevice, currentDevice);
    expect(model.error, isNull);
    expect(model.loading, isFalse);
  });

  test('revoking an other device reloads it as revoked', () async {
    final DevicesApi api = DevicesApi(
      FakeTainaApi(delay: Duration.zero),
      const [currentDevice, otherDevice],
    );
    final DevicesModel model = DevicesModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();

    final TainaResult<void> result = await model.revokeDevice(
      otherDevice.publicId,
    );

    expect(result.isSuccess, isTrue);
    expect(api.revoked, [otherDevice.publicId]);
    final DeviceToken other = model.devices!.firstWhere(
      (DeviceToken device) => device.publicId == otherDevice.publicId,
    );
    expect(other.revokedAt, isNotNull);
    expect(model.revokingDevice, isNull);
  });

  test('deviceLine reads revoked, last use and never used', () {
    expect(
      DevicesModel.deviceLine(
        const DeviceToken(
          publicId: 'd1',
          name: 'x',
          lastUsedAt: '2026-10-14T03:00:00Z',
          revokedAt: '2026-10-15T03:00:00Z',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
      startsWith('Revogado em '),
    );
    expect(
      DevicesModel.deviceLine(
        const DeviceToken(
          publicId: 'd1',
          name: 'x',
          lastUsedAt: '2026-10-14T03:00:00Z',
          revokedAt: null,
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
      startsWith('Último uso em '),
    );
    expect(
      DevicesModel.deviceLine(
        const DeviceToken(
          publicId: 'd1',
          name: 'x',
          lastUsedAt: null,
          revokedAt: null,
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
      'Nunca usado',
    );
  });
}
