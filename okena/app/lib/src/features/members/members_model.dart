import 'package:flutter/foundation.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The members list's state: one load, the transitions pure.
///
/// The zeladora's acts live here too: mint an invite and hand over its link,
/// change a role, switch an account off and on, take a pending invite back,
/// and mint a password link for one person.
final class MembersModel extends ChangeNotifier {
  MembersModel({required this.gateway});

  final SessionGateway gateway;

  List<Ava> _members = const [];
  bool _loading = true;
  TainaError? _error;
  String? _working;
  Ava? _me;
  bool _disposed = false;

  List<Ava> get members => _members;
  bool get loading => _loading;
  TainaError? get error => _error;

  /// The `public_id` of the person the box is acting on right now.
  String? get working => _working;

  /// The person acting, when the identity is loaded: their own row reads
  /// "Você", like the web's list.
  String? get mePublicId => _me?.publicId;

  /// The acts belong to whoever cares for the box; the server enforces it
  /// again anyway.
  bool get isZelador => _me?.papel == Papel.zelador;

  Future<void> load() async {
    _loading = true;
    _notify();
    await _loadMe();
    final result = await gateway.screen(await gateway.api.members());
    switch (result) {
      case Ok(:final value):
        _members = value.items;
        _error = null;
      case Err(:final error):
        _error = error;
    }
    _loading = false;
    _notify();
  }

  /// Mints the invite. The link travels by hand, so the screen shows it once
  /// for the copy; the new pending person joins the roster.
  Future<TainaResult<MemberInvite>> invite(Papel papel) async {
    final result = await gateway.screen(
      await gateway.api.inviteMember(papel: papel),
    );
    if (result case Ok(:final value)) {
      _members = inserting(value.ava, _members);
      _notify();
    }
    return result;
  }

  /// The role change, one person at a time. The row reads the answer.
  Future<TainaResult<Ava>> changeRole(String id, Papel papel) async {
    _working = id;
    _notify();
    final result = await gateway.screen(
      await gateway.api.updateMember(id: id, papel: papel),
    );
    switch (result) {
      case Ok(:final value):
        _members = replacing(id, value, _members);
      case Err():
        break;
    }
    _working = null;
    _notify();
    return result;
  }

  /// Deactivates: the account stops resolving, the fact stays listed. The
  /// answer is a 204 with no body, so the list is read again.
  Future<TainaResult<void>> deactivate(String id) async {
    _working = id;
    _notify();
    final result = await gateway.screen(
      await gateway.api.deactivateMember(id: id),
    );
    _working = null;
    switch (result) {
      case Ok():
        await load();
        return const Ok<void>(null);
      case Err(:final error):
        _notify();
        return Err<void>(error);
    }
  }

  /// Brings an account back; its old tokens count again.
  Future<TainaResult<Ava>> reactivate(String id) async {
    _working = id;
    _notify();
    final result = await gateway.screen(
      await gateway.api.reactivateMember(id: id),
    );
    switch (result) {
      case Ok(:final value):
        _members = replacing(id, value, _members);
      case Err():
        break;
    }
    _working = null;
    _notify();
    return result;
  }

  /// Takes a pending invite back: the person was never in, so the row leaves
  /// the list.
  Future<TainaResult<void>> revokeInvite(String id) async {
    _working = id;
    _notify();
    final result = await gateway.screen(await gateway.api.revokeInvite(id: id));
    if (result case Ok()) {
      _members = removing(id, _members);
    }
    _working = null;
    _notify();
    return result;
  }

  /// Mints the password link of one person, shown once for the copy.
  Future<TainaResult<ResetLink>> resetLink(String id) async {
    return gateway.screen(await gateway.api.memberResetLink(id: id));
  }

  Future<void> _loadMe() async {
    final result = await gateway.screen(await gateway.api.me());
    if (result case Ok(:final value)) {
      _me = value.ava;
    }
  }

  // Pure transitions.

  /// The count line above the list: "1 pessoa", "3 pessoas".
  static String countLine(int count) =>
      count == 1 ? '1 pessoa' : '$count pessoas';

  /// The state line of a row, when there is one: a deactivated account wins,
  /// then the person acting. The role is a line of its own.
  static String? metaFor(Ava member, String? mePublicId) {
    if (member.deactivatedAt != null) return 'Conta desativada';
    if (member.publicId == mePublicId) return 'Você';
    return null;
  }

  /// A pending invite: the account exists only as the invitation, with no
  /// username and no activation yet.
  static bool isPendingInvite(Ava member) =>
      member.username == null && member.activatedAt == null;

  /// The avatar tint: a stable sum of the name's scalars, 0 to 3, so the same
  /// person lands on the same color.
  static int tintIndex(String name) =>
      name.runes.fold(0, (int sum, int rune) => sum + rune) % 4;

  /// The pending person joins the roster, zeladoras first, like the box orders
  /// the list. Pure.
  static List<Ava> inserting(Ava member, List<Ava> members) {
    final List<Ava> next = [...members, member];
    next.sort((Ava lhs, Ava rhs) {
      if (lhs.papel != rhs.papel) return lhs.papel == Papel.zelador ? -1 : 1;
      return lhs.label.compareTo(rhs.label);
    });
    return List<Ava>.unmodifiable(next);
  }

  /// One row swapped for the answer. Pure.
  static List<Ava> replacing(String id, Ava updated, List<Ava> members) {
    return List<Ava>.unmodifiable([
      for (final Ava member in members)
        if (member.publicId == id) updated else member,
    ]);
  }

  /// One row gone. Pure.
  static List<Ava> removing(String id, List<Ava> members) {
    return List<Ava>.unmodifiable([
      for (final Ava member in members)
        if (member.publicId != id) member,
    ]);
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
