import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/mural/mural_phrase.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

MuralEntry entry(String tipo, Map<String, JsonValue> payload) {
  return MuralEntry(
    seq: 1,
    tipo: tipo,
    payload: payload,
    cid: 'bafy',
    prev: null,
    createdAt: '2026-10-14T10:00:00Z',
  );
}

void main() {
  const Map<String, String> names = {'avap2xw5m8q3': 'Ana Souza'};

  group('actor', () {
    test('resolves the public_id through the roster', () {
      expect(
        MuralPhrase.sentence(
          entry('put', const {'actor': JsonString('avap2xw5m8q3')}),
          names,
        ),
        'Ana Souza guardou um arquivo na caixa.',
      );
    });

    test('falls back to O sistema without an actor', () {
      expect(
        MuralPhrase.sentence(entry('put', const {}), names),
        startsWith('O sistema'),
      );
    });

    test('falls back to O sistema when the roster does not know the actor', () {
      expect(
        MuralPhrase.sentence(
          entry('put', const {'actor': JsonString('sumiu')}),
          names,
        ),
        startsWith('O sistema'),
      );
    });

    test('builds the roster by public_id', () {
      expect(MuralPhrase.actorNames(const [ana, joana]), {
        'avap2xw5m8q3': 'Ana Souza',
        'avaq7r2m5xk9p1': 'Joana Reis',
      });
    });
  });

  group('invites and membership', () {
    test('invite_created distinguishes the machine role', () {
      expect(
        MuralPhrase.sentence(
          entry('invite_created', const {
            'actor': JsonString('avap2xw5m8q3'),
            'role': JsonString('zelador'),
          }),
          names,
        ),
        'Ana Souza convidou uma nova pessoa para cuidar da máquina.',
      );
      expect(
        MuralPhrase.sentence(
          entry('invite_created', const {
            'actor': JsonString('avap2xw5m8q3'),
            'role': JsonString('morador'),
          }),
          names,
        ),
        'Ana Souza convidou uma nova pessoa para a comunidade.',
      );
    });

    test('invite_accepted distinguishes the machine role', () {
      expect(
        MuralPhrase.sentence(
          entry('invite_accepted', const {
            'actor': JsonString('avap2xw5m8q3'),
            'role': JsonString('zelador'),
          }),
          names,
        ),
        'Ana Souza entrou na comunidade para cuidar da máquina.',
      );
      expect(
        MuralPhrase.sentence(
          entry('invite_accepted', const {
            'actor': JsonString('avap2xw5m8q3'),
            'role': JsonString('morador'),
          }),
          names,
        ),
        'Ana Souza entrou na comunidade.',
      );
    });

    test('invite_revoked distinguishes the machine role', () {
      expect(
        MuralPhrase.sentence(
          entry('invite_revoked', const {
            'actor': JsonString('avap2xw5m8q3'),
            'role': JsonString('zelador'),
          }),
          names,
        ),
        'Ana Souza revogou um convite para cuidar da máquina.',
      );
      expect(
        MuralPhrase.sentence(
          entry('invite_revoked', const {'actor': JsonString('avap2xw5m8q3')}),
          names,
        ),
        'Ana Souza revogou um convite.',
      );
    });

    test('reset_link_created names the member when present', () {
      expect(
        MuralPhrase.sentence(
          entry('reset_link_created', const {
            'actor': JsonString('avap2xw5m8q3'),
            'member': JsonString('Joana Reis'),
          }),
          names,
        ),
        'Ana Souza gerou um link de nova senha para Joana Reis.',
      );
      expect(
        MuralPhrase.sentence(
          entry('reset_link_created', const {
            'actor': JsonString('avap2xw5m8q3'),
          }),
          names,
        ),
        'Ana Souza gerou um link de nova senha para um membro da comunidade.',
      );
    });

    test('member_deactivated names the member when present', () {
      expect(
        MuralPhrase.sentence(
          entry('member_deactivated', const {
            'actor': JsonString('avap2xw5m8q3'),
            'member': JsonString('Joana Reis'),
          }),
          names,
        ),
        'Ana Souza desativou a conta de Joana Reis.',
      );
      expect(
        MuralPhrase.sentence(
          entry('member_deactivated', const {
            'actor': JsonString('avap2xw5m8q3'),
          }),
          names,
        ),
        'Ana Souza desativou uma conta.',
      );
    });

    test('member_reactivated names the member when present', () {
      expect(
        MuralPhrase.sentence(
          entry('member_reactivated', const {
            'actor': JsonString('avap2xw5m8q3'),
            'member': JsonString('Joana Reis'),
          }),
          names,
        ),
        'Ana Souza reativou a conta de Joana Reis.',
      );
      expect(
        MuralPhrase.sentence(
          entry('member_reactivated', const {
            'actor': JsonString('avap2xw5m8q3'),
          }),
          names,
        ),
        'Ana Souza reativou uma conta.',
      );
    });

    test('mudar_papel distinguishes granting and taking the machine', () {
      expect(
        MuralPhrase.sentence(
          entry('mudar_papel', const {
            'actor': JsonString('avap2xw5m8q3'),
            'role': JsonString('zelador'),
          }),
          names,
        ),
        'Ana Souza deu a um morador o cuidado da máquina.',
      );
      expect(
        MuralPhrase.sentence(
          entry('mudar_papel', const {
            'actor': JsonString('avap2xw5m8q3'),
            'role': JsonString('morador'),
          }),
          names,
        ),
        'Ana Souza tirou de um morador o cuidado da máquina.',
      );
    });
  });

  group('quota', () {
    test('reads the limit change with both ends', () {
      expect(
        MuralPhrase.sentence(
          entry('quota_changed', const {
            'actor': JsonString('avap2xw5m8q3'),
            'from': JsonInt(1073741824),
            'to': JsonInt(2147483648),
          }),
          names,
        ),
        'Ana Souza mudou o limite de armazenamento de 1,0 GB para 2,0 GB.',
      );
    });

    test('reads the limit change with only the destination', () {
      expect(
        MuralPhrase.sentence(
          entry('quota_changed', const {
            'actor': JsonString('avap2xw5m8q3'),
            'to': JsonInt(2147483648),
          }),
          names,
        ),
        'Ana Souza mudou o limite de armazenamento para 2,0 GB.',
      );
    });

    test('reads the limit change without numbers', () {
      expect(
        MuralPhrase.sentence(
          entry('quota_changed', const {'actor': JsonString('avap2xw5m8q3')}),
          names,
        ),
        'Ana Souza mudou o limite de armazenamento.',
      );
    });
  });

  group('files and folders', () {
    const Map<String, JsonValue> actor = {'actor': JsonString('avap2xw5m8q3')};
    const JsonValue folder = JsonString('ypy.folder.v0');

    test('put distinguishes folder and file', () {
      expect(
        MuralPhrase.sentence(
          entry('put', {
            'actor': const JsonString('avap2xw5m8q3'),
            'collection': folder,
          }),
          names,
        ),
        'Ana Souza criou uma pasta.',
      );
      expect(
        MuralPhrase.sentence(entry('put', actor), names),
        'Ana Souza guardou um arquivo na caixa.',
      );
    });

    test('publicar distinguishes folder and file', () {
      expect(
        MuralPhrase.sentence(
          entry('publicar', {
            'actor': const JsonString('avap2xw5m8q3'),
            'collection': folder,
          }),
          names,
        ),
        'Ana Souza publicou uma pasta na praça.',
      );
      expect(
        MuralPhrase.sentence(entry('publicar', actor), names),
        'Ana Souza publicou um arquivo na praça.',
      );
    });

    test('tirar_da_praca distinguishes folder and file', () {
      expect(
        MuralPhrase.sentence(
          entry('tirar_da_praca', {
            'actor': const JsonString('avap2xw5m8q3'),
            'collection': folder,
          }),
          names,
        ),
        'Ana Souza tirou uma pasta da praça.',
      );
      expect(
        MuralPhrase.sentence(entry('tirar_da_praca', actor), names),
        'Ana Souza tirou um arquivo da praça.',
      );
    });

    test('apagar distinguishes folder and file', () {
      expect(
        MuralPhrase.sentence(
          entry('apagar', {
            'actor': const JsonString('avap2xw5m8q3'),
            'collection': folder,
          }),
          names,
        ),
        'Ana Souza mandou uma pasta para a lixeira.',
      );
      expect(
        MuralPhrase.sentence(entry('apagar', actor), names),
        'Ana Souza mandou um arquivo para a lixeira.',
      );
    });

    test('restaurar, mover and renomear read their own acts', () {
      expect(
        MuralPhrase.sentence(entry('restaurar', actor), names),
        'Ana Souza tirou um arquivo da lixeira.',
      );
      expect(
        MuralPhrase.sentence(entry('mover', actor), names),
        'Ana Souza moveu um arquivo de pasta.',
      );
      expect(
        MuralPhrase.sentence(
          entry('renomear', {
            'actor': const JsonString('avap2xw5m8q3'),
            'collection': folder,
          }),
          names,
        ),
        'Ana Souza renomeou uma pasta.',
      );
      expect(
        MuralPhrase.sentence(entry('renomear', actor), names),
        'Ana Souza renomeou um arquivo.',
      );
    });

    test('concessao and revogar read the access acts', () {
      expect(
        MuralPhrase.sentence(entry('concessao', actor), names),
        'Ana Souza abriu a sua casa para a leitura de um morador.',
      );
      expect(
        MuralPhrase.sentence(entry('revogar', actor), names),
        'Ana Souza tirou a leitura que tinha aberto.',
      );
    });

    test('an unknown type keeps the generic sentence', () {
      expect(
        MuralPhrase.sentence(entry('arquivo.publicado', actor), names),
        'Ana Souza fez um ato registrado na comunidade.',
      );
    });
  });
}
