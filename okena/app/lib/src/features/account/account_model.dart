import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_gateway.dart';

/// The account identity, incoming-request summary and self-service password
/// change.
final class AccountModel extends ChangeNotifier {
  AccountModel({required this.gateway});

  final SessionGateway gateway;

  Me? _me;
  bool _loading = true;
  TainaError? _error;
  TainaError? _requestsError;
  int? _pendingRequests;
  bool _changing = false;
  bool _changed = false;
  TainaError? _passwordFailure;
  bool _disposed = false;

  Me? get me => _me;
  bool get loading => _loading;
  TainaError? get error => _error;
  bool get changing => _changing;
  bool get changed => _changed;
  TainaError? get passwordFailure => _passwordFailure;
  bool get isZelador => _me?.ava.papel == Papel.zelador;

  List<String> get currentPasswordErrors =>
      _passwordFailure?.messagesFor(['current_password']) ?? const [];

  List<String> get newPasswordErrors =>
      _passwordFailure?.messagesFor(['new_password', 'password']) ?? const [];

  String get pendingRequestsLabel {
    if (_requestsError != null) return 'Não foi possível verificar agora';
    final int count = _pendingRequests ?? 0;
    return switch (count) {
      0 => 'Nada pendente',
      1 => '1 pedido esperando sua resposta',
      _ => '$count pedidos esperando sua resposta',
    };
  }

  Future<void> load() async {
    _loading = true;
    _notify();

    Future<TainaResult<Me>> readMe() async =>
        gateway.screen(await gateway.api.me());
    Future<TainaResult<Page<Pedido>>> readRequests() async =>
        gateway.screen(await gateway.api.accessRequests());

    final List<Object> results = await Future.wait<Object>([
      readMe(),
      readRequests(),
    ]);
    final TainaResult<Me> meResult = results[0] as TainaResult<Me>;
    final TainaResult<Page<Pedido>> requestsResult =
        results[1] as TainaResult<Page<Pedido>>;

    switch (meResult) {
      case Ok(:final value):
        _me = value;
        _error = null;
      case Err(:final error):
        _error = error;
    }
    switch (requestsResult) {
      case Ok(:final value):
        _pendingRequests = value.items
            .where((Pedido pedido) => pedido.status == PedidoStatus.pendente)
            .length;
        _requestsError = null;
      case Err(:final error):
        _requestsError = error;
    }

    _loading = false;
    _notify();
  }

  /// Changes the password using the two fields on the board. The box validates
  /// the new password; the screen does not ask for a confirmation field.
  Future<bool> changePassword({
    required String current,
    required String newPassword,
  }) async {
    _passwordFailure = null;
    _changed = false;
    _changing = true;
    _notify();
    final TainaResult<void> result = await gateway.screen(
      await gateway.api.updatePassword(
        current: current,
        newPassword: newPassword,
      ),
    );
    switch (result) {
      case Ok():
        _changed = true;
      case Err(:final error):
        _passwordFailure = error;
    }
    _changing = false;
    _notify();
    return result.isSuccess;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
