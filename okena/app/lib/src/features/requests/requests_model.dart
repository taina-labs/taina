import 'package:flutter/foundation.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The two lists of pedidos, received and sent.
final class RequestSections {
  const RequestSections({this.received = const [], this.sent = const []});

  final List<Pedido> received;
  final List<Pedido> sent;
}

/// The accesses of both sides: the ones this person gave (she is the dono) and
/// the ones she received (she is the leitor), the revoked included, because
/// granting must stay visible to be reversible.
final class RequestGrants {
  const RequestGrants({this.given = const [], this.received = const []});

  final List<Concessao> given;
  final List<Concessao> received;
}

/// The pedidos screen's state: what the community asked of this person and
/// what this person asked of others, the decisions on the received ones, and
/// the accesses granted in both directions.
///
/// Both wire lists hold the pending ones only, so deciding is removing; the
/// loading logic lives here once and the transitions are pure functions the
/// views never reimplement.
final class RequestsModel extends ChangeNotifier {
  RequestsModel({required this.gateway});

  final SessionGateway gateway;

  RequestSections _sections = const RequestSections();
  RequestGrants _grants = const RequestGrants();

  /// Resource rkey to display name, one map per list: the owner resolves the
  /// name on their own file record, the pedinte reads the access target, which
  /// carries the name without the file itself.
  Map<String, String> _receivedNames = const {};
  Map<String, String> _sentNames = const {};
  Map<String, String> _grantNames = const {};
  bool _loading = true;
  TainaError? _error;
  String? _deciding;
  String? _revoking;
  bool _disposed = false;

  RequestSections get sections => _sections;
  RequestGrants get grants => _grants;
  Map<String, String> get receivedNames => _receivedNames;
  Map<String, String> get sentNames => _sentNames;
  Map<String, String> get grantNames => _grantNames;
  bool get loading => _loading;
  TainaError? get error => _error;

  /// The `public_id` of the pedido the box is deciding right now.
  String? get deciding => _deciding;

  /// The `public_id` of the concessao the box is revoking right now.
  String? get revoking => _revoking;

  Future<void> load() async {
    _loading = true;
    _notify();
    final received = await gateway.screen(await gateway.api.accessRequests());
    final sent = await gateway.screen(await gateway.api.myRequests());
    await _apply(received: received, sent: sent);
    await _loadGrants();
    _loading = false;
    _notify();
  }

  /// Grants the read: the concessao is born on the box and the pedido leaves
  /// the pending list. The screen says what the outcome was.
  Future<TainaResult<void>> approve(String id) async {
    _deciding = id;
    _notify();
    final result = await gateway.screen(
      await gateway.api.approveRequest(id: id),
    );
    final settled = _settle(result.map((_) {}), id);
    _deciding = null;
    _notify();
    return settled;
  }

  /// Denies the read: nothing opens, and the person may ask again later.
  Future<TainaResult<void>> deny(String id) async {
    _deciding = id;
    _notify();
    final result = await gateway.screen(await gateway.api.denyRequest(id: id));
    final settled = _settle(result.map((_) {}), id);
    _deciding = null;
    _notify();
    return settled;
  }

  /// Takes an access back, the dono's act, one way only: the person deixa de
  /// poder abrir o arquivo e pode pedir de novo depois.
  ///
  /// The lists are read again, so the row flips to revoked with the date.
  Future<TainaResult<void>> revoke(String id) async {
    _revoking = id;
    _notify();
    final result = await gateway.screen(await gateway.api.revokeGrant(id: id));
    if (result case Ok()) {
      await _loadGrants();
    }
    _revoking = null;
    _notify();
    return result;
  }

  // Pure transitions.

  /// The neutral label for a resource the box no longer knows. Never an error
  /// screen: the pedido, and the decision about it, still stand.
  static const String deletedResource = 'arquivo apagado';

  /// The neutral label for a file the caller cannot read anymore: a revoked
  /// grant keeps the fact but takes the name with it.
  static const String unreadableResource = 'nome não disponível';

  static String resourceNameForPedido(
    Pedido pedido,
    Map<String, String> names,
  ) {
    return names[pedido.recurso] ?? deletedResource;
  }

  static String resourceNameForConcessao(
    Concessao concessao,
    Map<String, String> names,
  ) {
    return names[concessao.recurso] ?? unreadableResource;
  }

  /// The row's title: the person the row is about, the pedinte on the received
  /// list and the dono on the sent one. The wire preloads both ends; a missing
  /// end still names a person of the community.
  static String personLabel(Ava? ava) => ava?.label ?? 'Pessoa da comunidade';

  /// The resource line, in the sentence the row speaks: the owner reads who
  /// asked, the pedinte reads who decides.
  static String resourceLine({required bool received, required String name}) {
    return received ? 'Pediu acesso a $name' : 'Pedido para abrir $name';
  }

  /// Whether a grant still stands: the date of the revoke is the end of it,
  /// and the row says so.
  static bool isRevoked(Concessao concessao) => concessao.revogadaEm != null;

  /// The overline of the received list: every row there waits on this person.
  static String receivedHeader(int count) {
    return count == 1
        ? '1 pedido esperando sua resposta'
        : '$count pedidos esperando sua resposta';
  }

  /// The outcome named on the file, like the web's flash: a decision is about
  /// that file, not about "a pedido".
  static String approvedMessage(String? name) {
    if (name == null) return 'Acesso liberado. A pessoa já pode ler.';
    return 'Acesso a $name liberado. A pessoa já pode ler.';
  }

  /// The outcome of a revoke, said about the file it took back.
  static String revokedMessage(String? name) {
    if (name == null) return 'Acesso revogado. A pessoa já não pode ler.';
    return 'Acesso a $name revogado. A pessoa já não pode ler.';
  }

  /// Removing the decided pedido from both pending lists, by identity.
  static RequestSections removing(String id, RequestSections sections) {
    return RequestSections(
      received: List<Pedido>.unmodifiable(
        sections.received.where((Pedido pedido) => pedido.publicId != id),
      ),
      sent: List<Pedido>.unmodifiable(
        sections.sent.where((Pedido pedido) => pedido.publicId != id),
      ),
    );
  }

  Future<void> _apply({
    required TainaResult<Page<Pedido>> received,
    required TainaResult<Page<Pedido>> sent,
  }) async {
    switch ((received, sent)) {
      case (Ok(:final value), Ok(value: final sentPage)):
        _sections = RequestSections(
          received: value.items,
          sent: sentPage.items,
        );
        _receivedNames = await _namesFor(value.items, asOwner: true);
        _sentNames = await _namesFor(sentPage.items, asOwner: false);
        _error = null;
      case (Err(:final error), _):
        _error = error;
      case (_, Err(:final error)):
        _error = error;
    }
  }

  Future<void> _loadGrants() async {
    final given = await gateway.screen(
      await gateway.api.grants(role: GrantRole.owner),
    );
    final received = await gateway.screen(
      await gateway.api.grants(role: GrantRole.reader),
    );
    switch ((given, received)) {
      case (Ok(:final value), Ok(value: final receivedPage)):
        _grants = RequestGrants(
          given: value.items,
          received: receivedPage.items,
        );
        _grantNames = await _grantNamesFor([
          ...value.items,
          ...receivedPage.items,
        ]);
        _error = null;
      case (Err(:final error), _):
        _error = error;
      case (_, Err(:final error)):
        _error = error;
    }
  }

  TainaResult<void> _settle(TainaResult<void> result, String id) {
    switch (result) {
      case Ok():
        _sections = removing(id, _sections);
        return const Ok<void>(null);
      case Err(:final error):
        return Err<void>(error);
    }
  }

  /// One name per unique resource. A resource that is gone answers the neutral
  /// label, like the web; the pedido line stays legible.
  Future<Map<String, String>> _namesFor(
    List<Pedido> pedidos, {
    required bool asOwner,
  }) async {
    final Map<String, String> names = {};
    for (final Pedido pedido in pedidos) {
      if (names.containsKey(pedido.recurso)) continue;
      final TainaResult<String> found = asOwner
          ? (await gateway.screen(await gateway.api.file(rkey: pedido.recurso)))
                .map((FileRecord file) => file.name)
          : (await gateway.screen(
              await gateway.api.accessTarget(fileRkey: pedido.recurso),
            )).map((AccessTarget target) => target.name);
      names[pedido.recurso] = found.value ?? deletedResource;
    }
    return Map<String, String>.unmodifiable(names);
  }

  /// One name per unique resource across both grant lists, read through the
  /// grant itself: who holds a standing grant can read the file, and who lost
  /// it reads the neutral label.
  Future<Map<String, String>> _grantNamesFor(List<Concessao> concessoes) async {
    final Map<String, String> names = {};
    for (final Concessao concessao in concessoes) {
      if (names.containsKey(concessao.recurso)) continue;
      final TainaResult<String> found = (await gateway.screen(
        await gateway.api.file(rkey: concessao.recurso),
      )).map((FileRecord file) => file.name);
      names[concessao.recurso] = found.value ?? unreadableResource;
    }
    return Map<String, String>.unmodifiable(names);
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
