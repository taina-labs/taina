import 'package:flutter/foundation.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

enum RequestFeedKind { incoming, outgoing, grant }

/// One row in the combined requests feed.
final class RequestFeedItem {
  const RequestFeedItem({
    required this.id,
    required this.kind,
    required this.sortDate,
    required this.title,
    required this.meta,
    required this.resourceName,
    required this.state,
    this.stateSummary,
    this.pedido,
    this.grant,
    this.canDecide = false,
    this.canRevoke = false,
  });

  final String id;
  final RequestFeedKind kind;
  final String sortDate;
  final String title;
  final String meta;
  final String resourceName;
  final TainaPedidoState state;
  final String? stateSummary;
  final Pedido? pedido;
  final Concessao? grant;
  final bool canDecide;
  final bool canRevoke;
}

/// Loads and merges received requests, sent requests and accesses this person
/// has given. Decisions stay in the feed instead of disappearing.
final class RequestsModel extends ChangeNotifier {
  RequestsModel({required this.gateway});

  final SessionGateway gateway;

  List<Pedido> _received = const [];
  List<Pedido> _sent = const [];
  List<Concessao> _given = const [];
  final Map<String, Pedido> _localReceivedDecisions = {};
  final Set<String> _locallyRevokedGrants = {};
  Map<String, String> _receivedNames = const {};
  Map<String, String> _sentNames = const {};
  Map<String, String> _grantNames = const {};
  bool _loading = true;
  TainaError? _error;
  String? _deciding;
  String? _revoking;
  bool _disposed = false;

  bool get loading => _loading;
  TainaError? get error => _error;
  String? get deciding => _deciding;
  String? get revoking => _revoking;

  List<RequestFeedItem> get items => mergeFeed(
    received: _received,
    sent: _sent,
    given: _given,
    localReceivedDecisions: _localReceivedDecisions.values.toList(),
    receivedNames: _receivedNames,
    sentNames: _sentNames,
    grantNames: _grantNames,
    locallyRevokedGrantIds: _locallyRevokedGrants,
  );

  Future<void> load() async {
    _loading = true;
    _notify();

    Future<TainaResult<Page<Pedido>>> readReceived() async =>
        gateway.screen(await gateway.api.accessRequests());
    Future<TainaResult<Page<Pedido>>> readSent() async =>
        gateway.screen(await gateway.api.myRequests());
    Future<TainaResult<Page<Concessao>>> readGiven() async =>
        gateway.screen(await gateway.api.grants(role: GrantRole.owner));

    final Future<TainaResult<Page<Pedido>>> receivedFuture = readReceived();
    final Future<TainaResult<Page<Pedido>>> sentFuture = readSent();
    final Future<TainaResult<Page<Concessao>>> givenFuture = readGiven();

    final List<Object> results = await Future.wait<Object>([
      receivedFuture,
      sentFuture,
      givenFuture,
    ]);
    final TainaResult<Page<Pedido>> received =
        results[0] as TainaResult<Page<Pedido>>;
    final TainaResult<Page<Pedido>> sent =
        results[1] as TainaResult<Page<Pedido>>;
    final TainaResult<Page<Concessao>> given =
        results[2] as TainaResult<Page<Concessao>>;

    final List<Pedido> receivedItems = switch (received) {
      Ok(:final value) => value.items,
      Err() => _received,
    };
    final List<Pedido> sentItems = switch (sent) {
      Ok(:final value) => value.items,
      Err() => _sent,
    };
    final List<Concessao> givenItems = switch (given) {
      Ok(:final value) => value.items,
      Err() => _given,
    };

    _received = List<Pedido>.unmodifiable(receivedItems);
    _sent = List<Pedido>.unmodifiable(sentItems);
    _given = List<Concessao>.unmodifiable(givenItems);

    final List<Pedido> allReceived = [
      ..._received,
      ..._localReceivedDecisions.values,
    ];
    final List<Map<String, String>> names = await Future.wait([
      _namesFor(allReceived, asOwner: true),
      _namesFor(_sent, asOwner: false),
      _grantNamesFor(_given),
    ]);
    _receivedNames = names[0];
    _sentNames = names[1];
    _grantNames = names[2];

    _locallyRevokedGrants.removeWhere(
      (String id) => _given.any(
        (Concessao grant) => grant.publicId == id && grant.revogadaEm != null,
      ),
    );
    _error = _firstError(received, sent, given);
    _loading = false;
    _notify();
  }

  /// Grants the read. The box creates the grant, which remains visible as a
  /// resolved row in the same feed.
  Future<TainaResult<void>> approve(String id) async {
    _deciding = id;
    _notify();
    final TainaResult<Concessao> result = await gateway.screen(
      await gateway.api.approveRequest(id: id),
    );
    final TainaResult<void> settled = switch (result) {
      Ok(:final value) => _rememberApproval(value, id),
      Err(:final error) => Err<void>(error),
    };
    if (settled case Ok()) {
      _received = List<Pedido>.unmodifiable(
        _received.where((Pedido pedido) => pedido.publicId != id),
      );
      await load();
    }
    _deciding = null;
    _notify();
    return settled;
  }

  /// Refuses the read and keeps the returned decision in this screen's feed.
  Future<TainaResult<void>> deny(String id) async {
    _deciding = id;
    _notify();
    final TainaResult<Pedido> result = await gateway.screen(
      await gateway.api.denyRequest(id: id),
    );
    final TainaResult<void> settled = switch (result) {
      Ok(:final value) => _rememberDenied(value),
      Err(:final error) => Err<void>(error),
    };
    _deciding = null;
    _notify();
    return settled;
  }

  /// Takes back one access this person gave. The owner grant remains visible
  /// with its revoked state.
  Future<TainaResult<void>> revoke(String id) async {
    _revoking = id;
    _notify();
    final TainaResult<void> result = await gateway.screen(
      await gateway.api.revokeGrant(id: id),
    );
    if (result case Ok()) {
      _locallyRevokedGrants.add(id);
      await load();
    }
    _revoking = null;
    _notify();
    return result;
  }

  // Pure projections.

  static const String deletedResource = 'arquivo apagado';
  static const String unreadableResource = 'nome não disponível';

  static String resourceNameForPedido(
    Pedido pedido,
    Map<String, String> names,
  ) => names[pedido.recurso] ?? deletedResource;

  static String resourceNameForGrant(
    Concessao grant,
    Map<String, String> names,
  ) => names[grant.recurso] ?? unreadableResource;

  static String personLabel(Ava? ava) => ava?.label ?? 'Pessoa da comunidade';

  static bool isRevoked(Concessao grant) => grant.revogadaEm != null;

  static String approvedMessage(String? name) {
    if (name == null) return 'Acesso liberado. A pessoa já pode ler.';
    return 'Acesso a $name liberado. A pessoa já pode ler.';
  }

  static String revokedMessage(String? name) {
    if (name == null) return 'Acesso revogado. A pessoa já não pode ler.';
    return 'Acesso a $name revogado. A pessoa já não pode ler.';
  }

  static List<RequestFeedItem> mergeFeed({
    required List<Pedido> received,
    required List<Pedido> sent,
    required List<Concessao> given,
    required List<Pedido> localReceivedDecisions,
    required Map<String, String> receivedNames,
    required Map<String, String> sentNames,
    required Map<String, String> grantNames,
    Set<String> locallyRevokedGrantIds = const {},
  }) {
    final Map<String, Pedido> incomingById = {
      for (final Pedido pedido in received) pedido.publicId: pedido,
      for (final Pedido pedido in localReceivedDecisions)
        pedido.publicId: pedido,
    };
    final Set<String> approvedReads = {
      for (final Pedido pedido in incomingById.values)
        if (pedido.status == PedidoStatus.aprovado)
          _accessKey(pedido.recurso, pedido.pedinte?.publicId),
    };
    final List<RequestFeedItem> rows = [
      for (final Pedido pedido in incomingById.values)
        _pedidoItem(
          pedido,
          kind: RequestFeedKind.incoming,
          name: resourceNameForPedido(pedido, receivedNames),
        ),
      for (final Pedido pedido in sent)
        _pedidoItem(
          pedido,
          kind: RequestFeedKind.outgoing,
          name: resourceNameForPedido(pedido, sentNames),
        ),
      for (final Concessao grant in given)
        if (!approvedReads.contains(
          _accessKey(grant.recurso, grant.leitor?.publicId),
        ))
          _grantItem(
            grant,
            name: resourceNameForGrant(grant, grantNames),
            locallyRevoked: locallyRevokedGrantIds.contains(grant.publicId),
          ),
    ];
    rows.sort(_newestFirst);
    return List<RequestFeedItem>.unmodifiable(rows);
  }

  static String timestamp(String iso, {DateTime? now}) {
    final DateTime? parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return TainaFormat.relative(iso, now: now);
    final String relative = TainaFormat.relative(iso, now: now);
    return '$relative ${_twoDigits(parsed.hour)}:${_twoDigits(parsed.minute)}';
  }

  static String shortDate(String iso) {
    final DateTime? parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return TainaFormat.relative(iso);
    return '${parsed.day} ${_months[parsed.month - 1]}';
  }

  static RequestFeedItem _pedidoItem(
    Pedido pedido, {
    required RequestFeedKind kind,
    required String name,
  }) {
    final bool incoming = kind == RequestFeedKind.incoming;
    final String eventDate = pedido.decididoEm ?? pedido.createdAt;
    final TainaPedidoState state = switch (pedido.status) {
      PedidoStatus.pendente => TainaPedidoState.esperando,
      PedidoStatus.aprovado => TainaPedidoState.dado,
      PedidoStatus.negado => TainaPedidoState.recusado,
    };
    final String title = switch ((incoming, pedido.status)) {
      (true, PedidoStatus.pendente) =>
        '${personLabel(pedido.pedinte)} pediu acesso',
      (true, PedidoStatus.aprovado) =>
        '${personLabel(pedido.pedinte)} recebeu acesso',
      (true, PedidoStatus.negado) =>
        '${personLabel(pedido.pedinte)} teve o acesso recusado',
      (false, PedidoStatus.pendente) => 'Você pediu acesso a $name',
      (false, PedidoStatus.aprovado) => 'Você recebeu acesso a $name',
      (false, PedidoStatus.negado) => 'Seu pedido de acesso foi recusado',
    };
    final String meta = incoming
        ? '$name, ${timestamp(pedido.createdAt)}'
        : '${personLabel(pedido.dono)}, ${timestamp(pedido.createdAt)}';
    final String? stateSummary = switch (pedido.status) {
      PedidoStatus.pendente when incoming => null,
      PedidoStatus.pendente =>
        'Aguardando resposta de ${personLabel(pedido.dono)}',
      PedidoStatus.aprovado => 'Acesso dado em ${shortDate(eventDate)}',
      PedidoStatus.negado => 'Acesso recusado em ${shortDate(eventDate)}',
    };
    return RequestFeedItem(
      id: 'pedido:${pedido.publicId}',
      kind: kind,
      sortDate: eventDate,
      title: title,
      meta: meta,
      resourceName: name,
      state: state,
      stateSummary: stateSummary,
      pedido: pedido,
      canDecide: incoming && pedido.status == PedidoStatus.pendente,
    );
  }

  static RequestFeedItem _grantItem(
    Concessao grant, {
    required String name,
    required bool locallyRevoked,
  }) {
    final bool revoked = isRevoked(grant) || locallyRevoked;
    final String eventDate =
        grant.revogadaEm ?? grant.concedidaEm ?? grant.createdAt;
    final String person = personLabel(grant.leitor);
    return RequestFeedItem(
      id: 'grant:${grant.publicId}',
      kind: RequestFeedKind.grant,
      sortDate: eventDate,
      title: revoked ? 'Acesso retirado de $person' : '$person recebeu acesso',
      meta: '$name, ${timestamp(grant.createdAt)}',
      resourceName: name,
      state: revoked ? TainaPedidoState.recusado : TainaPedidoState.dado,
      stateSummary: revoked
          ? 'Acesso tirado em ${shortDate(eventDate)}'
          : 'Acesso dado em ${shortDate(eventDate)}',
      grant: grant,
      canRevoke: !revoked,
    );
  }

  static int _newestFirst(RequestFeedItem left, RequestFeedItem right) {
    final DateTime? leftDate = DateTime.tryParse(left.sortDate);
    final DateTime? rightDate = DateTime.tryParse(right.sortDate);
    if (leftDate != null && rightDate != null) {
      final int chronological = rightDate.compareTo(leftDate);
      if (chronological != 0) return chronological;
    }
    return right.sortDate.compareTo(left.sortDate);
  }

  static String _accessKey(String resource, String? readerId) =>
      '$resource:${readerId ?? ''}';

  TainaResult<void> _rememberDenied(Pedido pedido) {
    if (pedido.status != PedidoStatus.negado) {
      return const Err<void>(
        InvalidResponseError(
          'denial response did not contain a denied request',
        ),
      );
    }
    _localReceivedDecisions[pedido.publicId] = pedido;
    _received = List<Pedido>.unmodifiable(
      _received.where(
        (Pedido existing) => existing.publicId != pedido.publicId,
      ),
    );
    return const Ok<void>(null);
  }

  TainaResult<void> _rememberApproval(Concessao grant, String requestId) {
    _received = List<Pedido>.unmodifiable(
      _received.where((Pedido pedido) => pedido.publicId != requestId),
    );
    _given = List<Concessao>.unmodifiable([
      grant,
      ..._given.where(
        (Concessao existing) => existing.publicId != grant.publicId,
      ),
    ]);
    final String? name = _receivedNames[grant.recurso];
    if (name != null) {
      _grantNames = Map<String, String>.unmodifiable({
        ..._grantNames,
        grant.recurso: name,
      });
    }
    return const Ok<void>(null);
  }

  static TainaError? _firstError(
    TainaResult<Page<Pedido>> received,
    TainaResult<Page<Pedido>> sent,
    TainaResult<Page<Concessao>> given,
  ) {
    return switch ((received, sent, given)) {
      (Err(:final error), _, _) => error,
      (_, Err(:final error), _) => error,
      (_, _, Err(:final error)) => error,
      _ => null,
    };
  }

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

  Future<Map<String, String>> _grantNamesFor(List<Concessao> grants) async {
    final Map<String, String> names = {};
    for (final Concessao grant in grants) {
      if (names.containsKey(grant.recurso)) continue;
      final TainaResult<String> found = (await gateway.screen(
        await gateway.api.file(rkey: grant.recurso),
      )).map((FileRecord file) => file.name);
      names[grant.recurso] = found.value ?? unreadableResource;
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

  static const List<String> _months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
