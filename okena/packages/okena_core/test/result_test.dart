import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('maps successful values', () {
      const result = Ok<int>(2);

      final mapped = result.map((value) => value * 3);

      expect(mapped.value, 6);
      expect(mapped.error, isNull);
    });

    test('keeps failures unchanged', () {
      const error = ApiError(
        code: 'storage_quota_exceeded',
        status: 409,
        serverMessage: 'A comunidade encheu.',
      );
      const result = Err<int>(error);

      final mapped = result.map((value) => value * 3);

      expect(mapped.value, isNull);
      expect(mapped.error, same(error));
      expect(error.isQuotaExceeded, isTrue);
      expect(error.isConflict, isTrue);
    });
  });
}
