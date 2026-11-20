import 'package:okena_core/src/json/api_coding.dart';

/// The answer of the light token reads (`GET /invites/:token`,
/// `GET /password-resets/:token`): the screen opens with it and shows the
/// form, while the real validation stays on the POST.
final class TokenStatus {
  const TokenStatus({required this.valid, this.tekoaName, this.inviter});

  factory TokenStatus.fromJson(JsonReader reader) {
    return TokenStatus(
      valid: reader.boolean('valid'),
      tekoaName: reader.stringOrNull('tekoa_name'),
      inviter: reader.stringOrNull('inviter'),
    );
  }

  final bool valid;
  final String? tekoaName;
  final String? inviter;

  @override
  bool operator ==(Object other) =>
      other is TokenStatus &&
      other.valid == valid &&
      other.tekoaName == tekoaName &&
      other.inviter == inviter;

  @override
  int get hashCode => Object.hash(TokenStatus, valid, tekoaName, inviter);
}
