import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_model.dart';

/// The sign-in state: the header the session supplies and the last failure
/// the form shows.
final class LoginViewModel extends ChangeNotifier {
  LoginViewModel({required this.session}) {
    session.addListener(_changed);
  }

  final SessionModel session;

  bool signingIn = false;
  TainaError? failure;
  bool changingCommunity = false;

  String? get notice => session.notice;
  Instance? get instance => session.instance;
  InstanceAddress? get host => session.host;
  bool get showsAddress => host == null || changingCommunity;
  bool get communityNotCreated {
    final currentFailure = failure;
    return instance?.bootstrapped == false &&
        currentFailure is InvalidResponseError &&
        currentFailure.cause == 'community is not bootstrapped';
  }

  /// The sentence above the button: the rate limit explains itself; the rest
  /// is the error's own pt-BR description.
  String? get formMessage {
    final failure = this.failure;
    if (failure == null) return null;
    if (failure is InvalidAddressError) return null;
    if (communityNotCreated) return null;
    if (failure is ApiError && failure.isRateLimited) {
      return 'Muitas tentativas de entrada. Espere um pouco antes de tentar '
          'de novo.';
    }
    if (failure is NetworkError) return 'Não conseguimos chegar à comunidade.';
    if (failure is ApiError && failure.code == 'invalid_credentials') {
      return 'Não conseguimos entrar.';
    }
    return failure.message;
  }

  List<String> messagesFor(List<String> fields) {
    final failure = this.failure;
    if (failure is ApiError && failure.code == 'invalid_credentials') {
      if (fields.contains('password')) {
        return const ['Confira a senha e tente de novo.'];
      }
    }
    return failure?.messagesFor(fields) ?? const [];
  }

  String? get addressErrorMessage {
    final failure = this.failure;
    if (failure is InvalidAddressError) return failure.message;
    return null;
  }

  bool get isUnreachable => failure is NetworkError;

  static const String unreachableMessage =
      'Nada respondeu neste endereço. Confira se ele está certo, se a caixa '
      'está ligada e se este aparelho está na rede da comunidade.';

  bool isCleartextAddress(String address) {
    final parsed = InstanceAddress.parse(address);
    return parsed.value?.isCleartext ?? false;
  }

  String communityLine() {
    final community = instance?.tekoa?.name;
    final address = host?.display;
    if (community == null) return address ?? '';
    if (address == null) return community;
    return '$community, $address';
  }

  Future<void> probe() => session.probe();

  Future<void> changeCommunity() async {
    changingCommunity = true;
    failure = null;
    _notify();
    await session.clearHost();
  }

  void clearFailure() {
    if (failure == null) return;
    failure = null;
    _notify();
  }

  Future<void> enter({
    required String username,
    required String password,
    String address = '',
    required String deviceName,
  }) async {
    signingIn = true;
    failure = null;
    _notify();

    final result = showsAddress
        ? await session.connectAndLogin(
            address: address,
            username: username,
            password: password,
            deviceName: deviceName,
          )
        : await session.login(
            username: username.trim(),
            password: password,
            deviceName: deviceName,
          );
    if (showsAddress && session.host != null) changingCommunity = false;
    final error = result.error;
    if (error != null) failure = error;
    signingIn = false;
    _notify();
  }

  void _changed() => _notify();

  bool _disposed = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_changed);
    super.dispose();
  }
}
