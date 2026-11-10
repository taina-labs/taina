import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_model.dart';

/// The setup screen's state: the address being probed and the outcome of the
/// last attempt.
///
/// The text field lives in the widget; this model owns only what the screen
/// renders after the person presses Conectar.
final class SetupViewModel extends ChangeNotifier {
  SetupViewModel({required this.session}) {
    session.addListener(_changed);
  }

  final SessionModel session;

  bool probing = false;
  TainaError? failure;

  Instance? get instance => session.instance;

  /// Says so while the person types, not after a failed attempt.
  bool typedCleartext(String input) {
    final parsed = InstanceAddress.parse(input);
    return parsed.value?.isCleartext ?? false;
  }

  /// Nothing answered at this address, on either scheme: the one failure
  /// where the person can act.
  static bool unreachable(TainaError error) => error is NetworkError;

  static const String unreachableMessage =
      'Nada respondeu neste endereço. Confira se ele está certo, se a caixa '
      'está ligada e se este aparelho está na rede da comunidade.';

  Future<void> connect(String input) async {
    probing = true;
    failure = null;
    _notify();
    final result = await session.connect(input);
    switch (result) {
      case Ok(:final value):
        // A bootstrapped community already moved the app to the login; a box
        // without a community stays here, with the card above.
        if (value.bootstrapped) return;
        probing = false;
      case Err(:final error):
        failure = error;
        probing = false;
    }
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
