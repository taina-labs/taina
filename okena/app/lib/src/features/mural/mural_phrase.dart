import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_core/okena_core.dart';

/// The mural's words, in one place.
///
/// Each chain `tipo` becomes one plain pt-BR sentence, no ids and no jargon.
/// The table mirrors the web's `mural_live.sentence/2` and the Swift
/// `MuralPhrase`, so the Home teaser and the Mural screen never drift. The
/// mural is append-only: a type the screen does not know yet keeps its row on
/// the air with the generic sentence.
abstract final class MuralPhrase {
  /// The chain stores the actor's `public_id`; the screen is who translates it
  /// to people, from the community roster.
  static Map<String, String> actorNames(List<Ava> avas) {
    return {for (final ava in avas) ava.publicId: ava.label};
  }

  /// The sentence the entry becomes. Pure.
  static String sentence(MuralEntry entry, Map<String, String> names) {
    final String actor = actorLabel(entry, names);
    final String? role = _string('role', entry.payload);
    final String? member = _string('member', entry.payload);
    final bool folder = _string('collection', entry.payload) == 'ypy.folder.v0';

    switch (entry.tipo) {
      case 'invite_created':
        return role == 'zelador'
            ? '$actor convidou uma nova pessoa para cuidar da máquina.'
            : '$actor convidou uma nova pessoa para a comunidade.';
      case 'invite_accepted':
        return role == 'zelador'
            ? '$actor entrou na comunidade para cuidar da máquina.'
            : '$actor entrou na comunidade.';
      case 'invite_revoked':
        return role == 'zelador'
            ? '$actor revogou um convite para cuidar da máquina.'
            : '$actor revogou um convite.';
      case 'reset_link_created':
        return member != null
            ? '$actor gerou um link de nova senha para $member.'
            : '$actor gerou um link de nova senha para um membro da comunidade.';
      case 'member_deactivated':
        return member != null
            ? '$actor desativou a conta de $member.'
            : '$actor desativou uma conta.';
      case 'member_reactivated':
        return member != null
            ? '$actor reativou a conta de $member.'
            : '$actor reativou uma conta.';
      case 'quota_changed':
        final int? from = _int('from', entry.payload);
        final int? to = _int('to', entry.payload);
        if (from != null && to != null) {
          return '$actor mudou o limite de armazenamento de '
              '${TainaFormat.bytes(from)} para ${TainaFormat.bytes(to)}.';
        }
        if (to != null) {
          return '$actor mudou o limite de armazenamento para '
              '${TainaFormat.bytes(to)}.';
        }
        return '$actor mudou o limite de armazenamento.';
      case 'put':
        return folder
            ? '$actor criou uma pasta.'
            : '$actor guardou um arquivo na caixa.';
      case 'publicar':
        return folder
            ? '$actor publicou uma pasta na praça.'
            : '$actor publicou um arquivo na praça.';
      case 'tirar_da_praca':
        return folder
            ? '$actor tirou uma pasta da praça.'
            : '$actor tirou um arquivo da praça.';
      case 'apagar':
        return folder
            ? '$actor mandou uma pasta para a lixeira.'
            : '$actor mandou um arquivo para a lixeira.';
      case 'restaurar':
        return '$actor tirou um arquivo da lixeira.';
      case 'mover':
        return '$actor moveu um arquivo de pasta.';
      case 'renomear':
        return folder
            ? '$actor renomeou uma pasta.'
            : '$actor renomeou um arquivo.';
      case 'concessao':
        return '$actor abriu a sua casa para a leitura de um morador.';
      case 'revogar':
        return '$actor tirou a leitura que tinha aberto.';
      case 'mudar_papel':
        return role == 'zelador'
            ? '$actor deu a um morador o cuidado da máquina.'
            : '$actor tirou de um morador o cuidado da máquina.';
      default:
        return '$actor fez um ato registrado na comunidade.';
    }
  }

  /// The actor's label, resolved from the roster. Without an actor, or with one
  /// the roster no longer knows, "O sistema" speaks, like the web does.
  static String actorLabel(MuralEntry entry, Map<String, String> names) {
    final String? publicId = _string('actor', entry.payload);
    if (publicId == null) return 'O sistema';
    return names[publicId] ?? 'O sistema';
  }

  static String? _string(String key, Map<String, JsonValue> payload) {
    final JsonValue? raw = payload[key];
    return switch (raw) {
      JsonString(:final value) => value,
      _ => null,
    };
  }

  static int? _int(String key, Map<String, JsonValue> payload) {
    final JsonValue? raw = payload[key];
    return switch (raw) {
      JsonInt(:final value) => value,
      _ => null,
    };
  }
}
