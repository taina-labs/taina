import 'package:okena_core/src/json/api_coding.dart';
import 'package:okena_core/src/models/wire.dart';

/// The owner of a casa resource, for whoever does not read it yet: the shape
/// `GET /files/{id}/access-target` answers with.
final class AccessTarget {
  const AccessTarget({
    required this.owner,
    required this.rkey,
    required this.name,
  });

  factory AccessTarget.fromJson(JsonReader reader) {
    return AccessTarget(
      owner: Ava.fromJson(reader.object('owner')),
      rkey: reader.string('rkey'),
      name: reader.string('name'),
    );
  }

  final Ava owner;
  final String rkey;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AccessTarget &&
      other.owner == owner &&
      other.rkey == rkey &&
      other.name == name;

  @override
  int get hashCode => Object.hash(AccessTarget, owner, rkey, name);
}

/// Where an access request stands. The word on the wire, in the model and on
/// the screen is the same.
enum PedidoStatus {
  pendente,
  aprovado,
  negado;

  static const Map<String, PedidoStatus> byWire = {
    'pendente': pendente,
    'aprovado': aprovado,
    'negado': negado,
  };
}

/// The access request. A mere intermediary: it grants nothing, it registers
/// the question, and the owner decides.
final class Pedido {
  const Pedido({
    required this.publicId,
    required this.tipo,
    required this.recurso,
    required this.motivo,
    required this.status,
    required this.decididoEm,
    required this.createdAt,
    required this.pedinte,
    required this.dono,
  });

  factory Pedido.fromJson(JsonReader reader) {
    final pedinte = reader.objectOrNull('pedinte');
    final dono = reader.objectOrNull('dono');
    return Pedido(
      publicId: reader.string('public_id'),
      tipo: reader.string('tipo'),
      recurso: reader.string('recurso'),
      motivo: reader.stringOrNull('motivo'),
      status: reader.enumValue('status', PedidoStatus.byWire),
      decididoEm: reader.stringOrNull('decidido_em'),
      createdAt: reader.string('created_at'),
      pedinte: pedinte == null ? null : Ava.fromJson(pedinte),
      dono: dono == null ? null : Ava.fromJson(dono),
    );
  }

  final String publicId;
  final String tipo;
  final String recurso;
  final String? motivo;
  final PedidoStatus status;
  final String? decididoEm;
  final String createdAt;
  final Ava? pedinte;
  final Ava? dono;

  @override
  bool operator ==(Object other) =>
      other is Pedido &&
      other.publicId == publicId &&
      other.tipo == tipo &&
      other.recurso == recurso &&
      other.motivo == motivo &&
      other.status == status &&
      other.decididoEm == decididoEm &&
      other.createdAt == createdAt &&
      other.pedinte == pedinte &&
      other.dono == dono;

  @override
  int get hashCode => Object.hash(
    Pedido,
    publicId,
    tipo,
    recurso,
    motivo,
    status,
    decididoEm,
    createdAt,
    pedinte,
    dono,
  );
}

/// The explicit read permission. Revoking does not erase the fact.
final class Concessao {
  const Concessao({
    required this.publicId,
    required this.tipo,
    required this.recurso,
    required this.concedidaEm,
    required this.revogadaEm,
    required this.createdAt,
    required this.leitor,
    required this.dono,
  });

  factory Concessao.fromJson(JsonReader reader) {
    final leitor = reader.objectOrNull('leitor');
    final dono = reader.objectOrNull('dono');
    return Concessao(
      publicId: reader.string('public_id'),
      tipo: reader.string('tipo'),
      recurso: reader.string('recurso'),
      concedidaEm: reader.stringOrNull('concedida_em'),
      revogadaEm: reader.stringOrNull('revogada_em'),
      createdAt: reader.string('created_at'),
      leitor: leitor == null ? null : Ava.fromJson(leitor),
      dono: dono == null ? null : Ava.fromJson(dono),
    );
  }

  final String publicId;
  final String tipo;
  final String recurso;
  final String? concedidaEm;
  final String? revogadaEm;
  final String createdAt;
  final Ava? leitor;
  final Ava? dono;

  @override
  bool operator ==(Object other) =>
      other is Concessao &&
      other.publicId == publicId &&
      other.tipo == tipo &&
      other.recurso == recurso &&
      other.concedidaEm == concedidaEm &&
      other.revogadaEm == revogadaEm &&
      other.createdAt == createdAt &&
      other.leitor == leitor &&
      other.dono == dono;

  @override
  int get hashCode => Object.hash(
    Concessao,
    publicId,
    tipo,
    recurso,
    concedidaEm,
    revogadaEm,
    createdAt,
    leitor,
    dono,
  );
}
