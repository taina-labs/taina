import 'package:flutter/foundation.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The invite form and its one-time link state.
final class MembersInviteModel extends ChangeNotifier {
  MembersInviteModel({required this.gateway});

  final SessionGateway gateway;

  Papel _papel = Papel.morador;
  bool _working = false;
  TainaError? _error;
  MemberInvite? _invite;
  bool _disposed = false;

  Papel get papel => _papel;
  bool get working => _working;
  TainaError? get error => _error;
  MemberInvite? get invite => _invite;

  String? get link => _invite == null ? null : linkFor(_invite!);

  void selectRole(Papel papel) {
    if (_working || _invite != null || papel == _papel) return;
    _papel = papel;
    _error = null;
    _notify();
  }

  Future<TainaResult<MemberInvite>> create() async {
    if (_working || _invite != null) {
      return const Err<MemberInvite>(CancelledError());
    }

    _working = true;
    _error = null;
    _notify();
    final TainaResult<MemberInvite> result = await gateway.screen(
      await gateway.api.inviteMember(papel: _papel),
    );
    switch (result) {
      case Ok(:final value):
        _invite = value;
      case Err(:final error):
        _error = error;
    }
    _working = false;
    _notify();
    return result;
  }

  static String linkFor(MemberInvite invite) {
    final String? webUrl = invite.webUrl?.trim();
    return webUrl == null || webUrl.isEmpty ? invite.inviteUrl : webUrl;
  }

  static String descriptionFor(Papel papel) {
    return switch (papel) {
      Papel.morador => 'Quem entrar vê a praça e ganha uma casa própria.',
      Papel.zelador =>
        'Quem entrar cuida da máquina: disco, backups e convites. '
            'Para abrir uma casa, pede como todo mundo.',
    };
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
