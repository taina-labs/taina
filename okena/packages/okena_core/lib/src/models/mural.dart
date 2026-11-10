import 'package:okena_core/src/internal/equality.dart';
import 'package:okena_core/src/json/api_coding.dart';
import 'package:okena_core/src/json/json_value.dart';

/// One entry of the mural, the readable projection of the single chain.
final class MuralEntry {
  MuralEntry({
    required this.seq,
    required this.tipo,
    required Map<String, JsonValue> payload,
    required this.cid,
    required this.prev,
    required this.createdAt,
  }) : payload = Map.unmodifiable(payload);

  factory MuralEntry.fromJson(JsonReader reader) {
    final raw = reader.object('payload');
    return MuralEntry(
      seq: reader.integer('seq'),
      tipo: reader.string('tipo'),
      payload: {
        for (final entry in raw.json.entries)
          entry.key: JsonValue.fromJson(entry.value),
      },
      cid: reader.string('cid'),
      prev: reader.stringOrNull('prev'),
      createdAt: reader.string('created_at'),
    );
  }

  final int seq;

  /// The entry type on the chain, the domain's own word.
  final String tipo;

  /// The payload exactly as the chain keeps it.
  final Map<String, JsonValue> payload;
  final String cid;

  /// The cid of the complete entry before this one; null on the first.
  final String? prev;
  final String createdAt;

  @override
  bool operator ==(Object other) =>
      other is MuralEntry &&
      other.seq == seq &&
      other.tipo == tipo &&
      mapEquals(other.payload, payload) &&
      other.cid == cid &&
      other.prev == prev &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    MuralEntry,
    seq,
    tipo,
    Object.hashAllUnordered([
      for (final entry in payload.entries) Object.hash(entry.key, entry.value),
    ]),
    cid,
    prev,
    createdAt,
  );
}
