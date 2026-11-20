import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/account/account_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

Future<AccountModel> _model() async {
  final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
  await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
  return AccountModel(gateway: FakeSession(api, me: identity(ana)));
}

void main() {
  test('load reads the identity and the incoming-request summary', () async {
    final AccountModel model = await _model();

    await model.load();

    expect(model.me, isNotNull);
    expect(model.me!.ava.label, 'Ana Souza');
    expect(model.isZelador, isTrue);
    expect(model.pendingRequestsLabel, '1 pedido esperando sua resposta');
    expect(model.loading, isFalse);
    expect(model.error, isNull);
  });

  test('a wrong current password lands on the current field', () async {
    final AccountModel model = await _model();

    final bool accepted = await model.changePassword(
      current: 'errada',
      newPassword: 'novasenha',
    );

    expect(accepted, isFalse);
    expect(model.passwordFailure, isA<ApiError>());
    expect((model.passwordFailure! as ApiError).code, 'invalid_credentials');
  });

  test('a weak new password lands on the new field', () async {
    final AccountModel model = await _model();

    final bool accepted = await model.changePassword(
      current: 'atual',
      newPassword: 'curta',
    );

    expect(accepted, isFalse);
    expect(model.newPasswordErrors, isNotEmpty);
  });

  test('a good change succeeds and says so', () async {
    final AccountModel model = await _model();

    final bool accepted = await model.changePassword(
      current: 'atual',
      newPassword: 'novasenha',
    );

    expect(accepted, isTrue);
    expect(model.changed, isTrue);
    expect(model.passwordFailure, isNull);
    expect(model.changing, isFalse);
  });
}
