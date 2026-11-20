import 'package:flutter/foundation.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The members list's state and API transitions.
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

  /// The `public_id` of the person acting, when the identity is loaded.
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

  /// The role and the row's current state, in the wording used by the board.
  static String metaFor(Ava member) {
    final String role = roleLabel(member.papel);
    if (member.deactivatedAt != null) return '$role, conta desativada';
    if (isPendingInvite(member)) return '$role, convite pendente';

    final String? activatedAt = member.activatedAt;
    final int? joinedYear = activatedAt == null
        ? null
        : DateTime.tryParse(activatedAt)?.year;
    return joinedYear == null ? role : '$role, entrou em $joinedYear';
  }

  static String roleLabel(Papel papel) =>
      papel == Papel.zelador ? 'Zelador' : 'Morador';

  /// Locally filters by the display name, ignoring case and common accents.
  static List<Ava> filterByName(Iterable<Ava> members, String query) {
    final String needle = _searchKey(query.trim());
    if (needle.isEmpty) return List<Ava>.unmodifiable(members);

    return List<Ava>.unmodifiable(
      members.where((Ava member) => _searchKey(member.label).contains(needle)),
    );
  }

  static String _searchKey(String value) {
    final StringBuffer normalized = StringBuffer();
    for (final int rune in value.toLowerCase().runes) {
      if (rune >= 0x0300 && rune <= 0x036F) continue;
      normalized.write(_searchReplacements[rune] ?? String.fromCharCode(rune));
    }
    return normalized.toString();
  }

  static const Map<int, String> _searchReplacements = {
    0x00E0: 'a',
    0x00E1: 'a',
    0x00E2: 'a',
    0x00E3: 'a',
    0x00E4: 'a',
    0x00E5: 'a',
    0x00E7: 'c',
    0x00E8: 'e',
    0x00E9: 'e',
    0x00EA: 'e',
    0x00EB: 'e',
    0x00EC: 'i',
    0x00ED: 'i',
    0x00EE: 'i',
    0x00EF: 'i',
    0x00F1: 'n',
    0x00F2: 'o',
    0x00F3: 'o',
    0x00F4: 'o',
    0x00F5: 'o',
    0x00F6: 'o',
    0x00F9: 'u',
    0x00FA: 'u',
    0x00FB: 'u',
    0x00FC: 'u',
    0x00FD: 'y',
    0x00FF: 'y',
    0x0101: 'a',
    0x0103: 'a',
    0x0105: 'a',
    0x0107: 'c',
    0x010D: 'c',
    0x010F: 'd',
    0x0113: 'e',
    0x0117: 'e',
    0x0119: 'e',
    0x011B: 'e',
    0x011F: 'g',
    0x0121: 'g',
    0x012B: 'i',
    0x012F: 'i',
    0x013A: 'l',
    0x013C: 'l',
    0x013E: 'l',
    0x0142: 'l',
    0x0144: 'n',
    0x0148: 'n',
    0x014D: 'o',
    0x0151: 'o',
    0x0155: 'r',
    0x0159: 'r',
    0x015B: 's',
    0x015F: 's',
    0x0161: 's',
    0x0163: 't',
    0x0165: 't',
    0x016B: 'u',
    0x016F: 'u',
    0x0171: 'u',
    0x017A: 'z',
    0x017C: 'z',
    0x017E: 'z',
    0x00DF: 'ss',
    0x00E6: 'ae',
    0x0153: 'oe',
    0x00F8: 'o',
  };

  /// A pending invite: the account exists only as the invitation, with no
  /// username and no activation yet.
  static bool isPendingInvite(Ava member) =>
      member.username == null && member.activatedAt == null;

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
