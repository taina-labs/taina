import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

const envelope = ApiError(
  code: 'validation_failed',
  status: 422,
  serverMessage: 'Confira os campos e tente de novo.',
  details: {
    'username': ['não pode ficar em branco'],
    'password': ['curta demais'],
  },
);

void main() {
  test('field messages come from the first field with any', () {
    expect(envelope.messagesFor(['username']), ['não pode ficar em branco']);
    expect(envelope.messagesFor(['display_name', 'password']), [
      'curta demais',
    ]);
    expect(envelope.messagesFor(['missing']), isEmpty);
  });

  test('a local error carries no field messages', () {
    expect(const NotSignedInError().messagesFor(['username']), isEmpty);
    expect(const NetworkError('offline').messagesFor(['password']), isEmpty);
  });

  test('the typed helpers read the status and the code', () {
    expect(envelope.isValidationFailed, isTrue);
    expect(envelope.isConflict, isFalse);
    expect(envelope.fieldMessages, [
      'não pode ficar em branco',
      'curta demais',
    ]);
  });

  test('errors are values with equality', () {
    expect(const NetworkError('offline'), const NetworkError('offline'));
    expect(const NetworkError('offline'), isNot(const NetworkError('timeout')));
    expect(
      const InvalidAddressError(AddressProblem.empty),
      const InvalidAddressError(AddressProblem.empty),
    );
    expect(
      const ApiError(code: 'x', status: 409, serverMessage: 'y'),
      const ApiError(code: 'x', status: 409, serverMessage: 'y'),
    );
  });
}
