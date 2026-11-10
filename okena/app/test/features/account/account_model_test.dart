import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/account/account_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

AccountModel _model() {
  final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
  final DevicesApi api = DevicesApi(inner, const [currentDevice, otherDevice]);
  return AccountModel(gateway: FakeSession(api, me: identity(ana)));
}

void main() {
  test('load reads the identity, the version and the devices', () async {
    final AccountModel model = _model();

    await model.load();

    expect(model.me, isNotNull);
    expect(model.me!.ava.label, 'Ana Souza');
    expect(model.version, '0.6.0');
    expect(model.devices, hasLength(2));
    expect(model.loading, isFalse);
    expect(model.error, isNull);
  });

  test('revokeDevice revokes and reads the list again', () async {
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    final DevicesApi api = DevicesApi(inner, const [
      currentDevice,
      otherDevice,
    ]);
    final AccountModel model = AccountModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();

    final result = await model.revokeDevice(otherDevice.publicId);

    expect(result.isSuccess, isTrue);
    expect(api.revoked, [otherDevice.publicId]);
    final DeviceToken other = model.devices!.firstWhere(
      (DeviceToken device) => device.publicId == otherDevice.publicId,
    );
    expect(other.revokedAt, isNotNull);
    expect(model.revokingDevice, isNull);
  });

  test('a mismatched confirmation never reaches the box', () async {
    final AccountModel model = _model();

    final bool accepted = await model.changePassword(
      current: 'atual',
      newPassword: 'novasenha',
      confirmation: 'outra',
    );

    expect(accepted, isFalse);
    expect(model.mismatch, 'As duas senhas não são iguais.');
    expect(model.passwordFailure, isNull);
  });

  test('a wrong current password lands on the current field', () async {
    final AccountModel model = _model();

    final bool accepted = await model.changePassword(
      current: 'errada',
      newPassword: 'novasenha',
      confirmation: 'novasenha',
    );

    expect(accepted, isFalse);
    expect(model.passwordFailure, isA<ApiError>());
    expect((model.passwordFailure! as ApiError).code, 'invalid_credentials');
  });

  test('a weak new password lands on the new field', () async {
    final AccountModel model = _model();

    final bool accepted = await model.changePassword(
      current: 'atual',
      newPassword: 'curta',
      confirmation: 'curta',
    );

    expect(accepted, isFalse);
    expect(model.newPasswordErrors, isNotEmpty);
  });

  test('a good change succeeds and says so', () async {
    final AccountModel model = _model();

    final bool accepted = await model.changePassword(
      current: 'atual',
      newPassword: 'novasenha',
      confirmation: 'novasenha',
    );

    expect(accepted, isTrue);
    expect(model.changed, isTrue);
    expect(model.passwordFailure, isNull);
    expect(model.mismatch, isNull);
    expect(model.changing, isFalse);
  });

  group('pure transitions', () {
    test('confirmationMatches is the local wire rule', () {
      expect(
        AccountModel.confirmationMatches(password: 'a', confirmation: 'a'),
        isTrue,
      );
      expect(
        AccountModel.confirmationMatches(password: 'a', confirmation: 'b'),
        isFalse,
      );
    });

    test('deviceLine reads revoked, last use and never used', () {
      expect(
        AccountModel.deviceLine(
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
        AccountModel.deviceLine(
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
        AccountModel.deviceLine(
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
  });
}
