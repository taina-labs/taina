import 'package:okena_core/src/internal/equality.dart';

/// Every way a call can fail, as a value.
sealed class TainaError {
  const TainaError();

  String get message;

  /// The envelope's messages for the first of [fields] that has any.
  /// A local error (no envelope) carries none.
  List<String> messagesFor(List<String> fields) => const [];
}

final class NetworkError extends TainaError {
  const NetworkError([this.cause = '']);

  final String cause;

  @override
  String get message =>
      'Não foi possível falar com a comunidade. Verifique a conexão e tente de novo.';

  @override
  bool operator ==(Object other) =>
      other is NetworkError && other.cause == cause;

  @override
  int get hashCode => Object.hash(NetworkError, cause);
}

final class InvalidUrlError extends TainaError {
  const InvalidUrlError();

  @override
  String get message =>
      'O endereço da comunidade não pôde ser usado. Confira o que está salvo no aparelho.';

  @override
  bool operator ==(Object other) => other is InvalidUrlError;

  @override
  int get hashCode => (InvalidUrlError).hashCode;
}

final class InvalidResponseError extends TainaError {
  const InvalidResponseError([this.cause = '']);

  final String cause;

  @override
  String get message =>
      'A comunidade respondeu algo inesperado. Tente de novo; se continuar, atualize o Tainá na caixa.';

  @override
  bool operator ==(Object other) =>
      other is InvalidResponseError && other.cause == cause;

  @override
  int get hashCode => Object.hash(InvalidResponseError, cause);
}

/// The decoded error envelope, and the client's contract with it.
///
/// `code` stays a [String] on purpose: it is the wire vocabulary and the
/// server owns it, so a new atom must not break an old client. A 403
/// `account_deactivated` must stay distinguishable from a 403 `forbidden`:
/// the client must not re-prompt for credentials in the first case.
final class ApiError extends TainaError {
  const ApiError({
    required this.code,
    required this.status,
    required this.serverMessage,
    this.details = const {},
  });

  final String code;
  final int status;

  /// pt-BR, from the server, shown as-is.
  final String serverMessage;

  /// Field to messages, empty when absent.
  final Map<String, List<String>> details;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;
  bool get isConflict => status == 409;
  bool get isValidationFailed => code == 'validation_failed';
  bool get isRateLimited => code == 'rate_limited';
  bool get isQuotaExceeded => code == 'storage_quota_exceeded';
  bool get isDeactivated => code == 'account_deactivated';

  /// Every field message, for a form that shows them as a list.
  List<String> get fieldMessages => [
    for (final messages in details.values) ...messages,
  ];

  @override
  List<String> messagesFor(List<String> fields) {
    for (final field in fields) {
      final messages = details[field];
      if (messages != null && messages.isNotEmpty) return messages;
    }
    return const [];
  }

  @override
  String get message => serverMessage;

  @override
  bool operator ==(Object other) =>
      other is ApiError &&
      other.code == code &&
      other.status == status &&
      other.serverMessage == serverMessage &&
      _detailsEqual(other.details, details);

  @override
  int get hashCode => Object.hash(
    ApiError,
    code,
    status,
    serverMessage,
    Object.hashAllUnordered([
      for (final entry in details.entries)
        Object.hash(entry.key, Object.hashAll(entry.value)),
    ]),
  );
}

bool _detailsEqual(Map<String, List<String>> a, Map<String, List<String>> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !listEquals(other, entry.value)) return false;
  }
  return true;
}

enum AddressProblem {
  empty,
  malformed,
  unsupportedScheme;

  String get message => switch (this) {
    AddressProblem.empty =>
      'Informe o endereço da comunidade, por exemplo taina.minhacasa.ts.net.',
    AddressProblem.malformed =>
      'Este endereço não pôde ser lido. Use algo como taina.minhacasa.ts.net.',
    AddressProblem.unsupportedScheme =>
      'Use o endereço da comunidade, por exemplo taina.minhacasa.ts.net.',
  };
}

final class InvalidAddressError extends TainaError {
  const InvalidAddressError(this.problem);

  final AddressProblem problem;

  @override
  String get message => problem.message;

  @override
  bool operator ==(Object other) =>
      other is InvalidAddressError && other.problem == problem;

  @override
  int get hashCode => Object.hash(InvalidAddressError, problem);
}

/// The device secret could not be stored by the platform layer.
///
/// The pure core never touches a Keychain or Keystore; this is the value the
/// app's platform-backed [SessionStorage] reports.
final class SecureStorageError extends TainaError {
  const SecureStorageError([this.cause = '']);

  final String cause;

  @override
  String get message => 'Não foi possível guardar a sessão neste aparelho.';

  @override
  bool operator ==(Object other) =>
      other is SecureStorageError && other.cause == cause;

  @override
  int get hashCode => Object.hash(SecureStorageError, cause);
}

final class NotSignedInError extends TainaError {
  const NotSignedInError();

  @override
  String get message => 'Entre na sua conta para continuar.';

  @override
  bool operator ==(Object other) => other is NotSignedInError;

  @override
  int get hashCode => (NotSignedInError).hashCode;
}

final class CancelledError extends TainaError {
  const CancelledError();

  @override
  String get message => 'A operação foi cancelada.';

  @override
  bool operator ==(Object other) => other is CancelledError;

  @override
  int get hashCode => (CancelledError).hashCode;
}
