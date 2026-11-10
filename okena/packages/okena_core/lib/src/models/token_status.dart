import 'package:okena_core/src/json/api_coding.dart';

/// The answer of the light token reads (`GET /invites/:token`,
/// `GET /password-resets/:token`): the screen opens with it and shows the
/// form, while the real validation stays on the POST.
final class TokenStatus {
  const TokenStatus({required this.valid});

  factory TokenStatus.fromJson(JsonReader reader) {
    return TokenStatus(valid: reader.boolean('valid'));
  }

  final bool valid;

  @override
  bool operator ==(Object other) =>
      other is TokenStatus && other.valid == valid;

  @override
  int get hashCode => Object.hash(TokenStatus, valid);
}
