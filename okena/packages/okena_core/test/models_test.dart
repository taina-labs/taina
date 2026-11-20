import 'dart:convert';

import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

TainaResult<T> decode<T>(String json, T Function(JsonReader reader) read) =>
    decodeJsonBody(utf8.encode(json), 'test', read);

void main() {
  group('JsonValue', () {
    test('keeps every JSON type whole', () {
      final value = JsonValue.fromJson({
        'name': 'quadra',
        'size': 1204331,
        'ratio': 1.5,
        'featured': true,
        'caption': null,
        'tags': ['festa', 'quadra'],
        'nested': {'a': 1},
      });
      expect(
        value,
        const JsonObject({
          'name': JsonString('quadra'),
          'size': JsonInt(1204331),
          'ratio': JsonDouble(1.5),
          'featured': JsonBool(true),
          'caption': JsonNull(),
          'tags': JsonArray([JsonString('festa'), JsonString('quadra')]),
          'nested': JsonObject({'a': JsonInt(1)}),
        }),
      );
      expect(value.toJson(), {
        'name': 'quadra',
        'size': 1204331,
        'ratio': 1.5,
        'featured': true,
        'caption': null,
        'tags': ['festa', 'quadra'],
        'nested': {'a': 1},
      });
    });
  });

  group('boundary decoding', () {
    test('storage decodes optional physical disk fields', () {
      final StorageStats withDisk = decode(
        storageJson,
        StorageStats.fromJson,
      ).value!;
      expect(withDisk.diskTotalBytes, 1073741824000);
      expect(withDisk.diskFreeBytes, 536870912000);

      final String withoutDiskFields = storageJson.replaceFirst(
        '"disk_total_bytes":1073741824000,"disk_free_bytes":536870912000,',
        '',
      );
      final StorageStats missing = decode(
        withoutDiskFields,
        StorageStats.fromJson,
      ).value!;
      expect(missing.diskTotalBytes, isNull);
      expect(missing.diskFreeBytes, isNull);

      final String nullDiskFields = storageJson.replaceFirst(
        '"disk_total_bytes":1073741824000,"disk_free_bytes":536870912000,',
        '"disk_total_bytes":null,"disk_free_bytes":null,',
      );
      final StorageStats nullValues = decode(
        nullDiskFields,
        StorageStats.fromJson,
      ).value!;
      expect(nullValues.diskTotalBytes, isNull);
      expect(nullValues.diskFreeBytes, isNull);
      expect(withDisk, isNot(missing));
    });

    test('storage decodes optional revamp fields and legacy fallbacks', () {
      final withRevampFields = storageJson.replaceFirst(
        '"used_bytes":',
        '"by_zone":{"casa":100,"praca":200,"lixeira":300},'
            '"disk_bytes":1073741824000,"videos":4,"used_bytes":',
      );
      final StorageStats current = decode(
        withRevampFields,
        StorageStats.fromJson,
      ).value!;
      expect(
        current.byZone,
        const StorageByZone(casa: 100, praca: 200, lixeira: 300),
      );
      expect(current.diskBytes, 1073741824000);
      expect(current.videos, 4);
      expect(
        decode(
          storageJson.replaceFirst(
            '"quota_bytes":268435456000',
            '"quota_bytes":null',
          ),
          StorageStats.fromJson,
        ).value!.quotaBytes,
        isNull,
      );

      final StorageStats legacy = decode(
        storageJson,
        StorageStats.fromJson,
      ).value!;
      expect(legacy.byZone, isNull);
      expect(legacy.diskBytes, legacy.diskTotalBytes);
      expect(legacy.videos, isNull);

      final withoutDisk = storageJson.replaceFirst(
        '"disk_total_bytes":1073741824000,"disk_free_bytes":536870912000,',
        '',
      );
      expect(
        decode(withoutDisk, StorageStats.fromJson).value!.diskBytes,
        isNull,
      );
    });

    test('saude optional summary and update decode when present or absent', () {
      final withRevampFields = saudeJson.replaceFirst(
        '"backup":',
        '"summary":{"state":"attention","line":"Disco quase cheio"},'
            '"update":{"status":"update_available","running":"0.6.0",'
            '"latest":"0.7.0"},"backup":',
      );
      final Saude current = decode(withRevampFields, Saude.fromJson).value!;
      expect(
        current.summary,
        const SaudeSummary(
          state: SaudeSummaryState.attention,
          line: 'Disco quase cheio',
        ),
      );
      expect(
        current.update,
        const SaudeUpdate(
          status: SaudeUpdateStatus.updateAvailable,
          running: '0.6.0',
          latest: '0.7.0',
        ),
      );

      final Saude legacy = decode(saudeJson, Saude.fromJson).value!;
      expect(legacy.summary, isNull);
      expect(legacy.update, isNull);
    });

    test('token status invite context remains optional', () {
      final legacy = decode(tokenStatusJson, TokenStatus.fromJson).value!;
      expect(legacy.valid, isTrue);
      expect(legacy.tekoaName, isNull);
      expect(legacy.inviter, isNull);

      final current = decode(
        '{"valid":true,"tekoa_name":"Quilombo do Café",'
        '"inviter":"Ana Souza"}',
        TokenStatus.fromJson,
      ).value!;
      expect(current.tekoaName, 'Quilombo do Café');
      expect(current.inviter, 'Ana Souza');
    });

    test('invite web URLs remain optional for older boxes', () {
      final oldInvite = decode(
        '{"ava":$anaJson,"token":"tk123","invite_url":"taina://convite/tk123"}',
        MemberInvite.fromJson,
      ).value!;
      expect(oldInvite.webUrl, isNull);

      final newInvite = decode(
        '{"ava":$anaJson,"token":"tk123","invite_url":"taina://convite/tk123",'
        '"web_url":"https://box/convite/tk123"}',
        MemberInvite.fromJson,
      ).value!;
      expect(newInvite.webUrl, 'https://box/convite/tk123');

      final oldReset = decode(
        '{"ava":$anaJson,"token":"tk123","reset_url":"taina://redefinir/tk123"}',
        ResetLink.fromJson,
      ).value!;
      expect(oldReset.webUrl, isNull);

      final newReset = decode(
        '{"ava":$anaJson,"token":"tk123","reset_url":"taina://redefinir/tk123",'
        '"web_url":"https://box/redefinir/tk123"}',
        ResetLink.fromJson,
      ).value!;
      expect(newReset.webUrl, 'https://box/redefinir/tk123');
    });

    test(
      'decodes each backup status and rejects an unknown or missing one',
      () {
        const statuses = {
          'ok': SaudeBackupStatus.ok,
          'none': SaudeBackupStatus.none,
          'never': SaudeBackupStatus.never,
          'failed': SaudeBackupStatus.failed,
          'disabled': SaudeBackupStatus.disabled,
          'not_configured': SaudeBackupStatus.notConfigured,
          'unreadable': SaudeBackupStatus.unreadable,
        };
        for (final MapEntry<String, SaudeBackupStatus> entry
            in statuses.entries) {
          final json = saudeJson.replaceFirst(
            '"status":"ok"',
            '"status":"${entry.key}"',
          );
          final saude = decode(json, Saude.fromJson).value!;
          expect(saude.backup.status, entry.value);
          expect(saude.backup.at, '2026-10-14T03:00:00Z');
          expect(saude.backup.bytes, 1829000000);
        }

        final unknown = saudeJson.replaceFirst(
          '"status":"ok"',
          '"status":"old"',
        );
        expect(
          decode(unknown, Saude.fromJson).error,
          isA<InvalidResponseError>(),
        );
        final missing = saudeJson.replaceFirst('"status":"ok",', '');
        expect(
          decode(missing, Saude.fromJson).error,
          isA<InvalidResponseError>(),
        );
      },
    );

    test('decodes an instance', () {
      final instance = decode(instanceJson, Instance.fromJson).value!;
      expect(instance.bootstrapped, isTrue);
      expect(instance.tekoa?.domain, 'taina.sapukai.ts.net');
    });

    test('a missing required field is an invalid response', () {
      final result = decode('{"version":"0.6.0"}', Instance.fromJson);
      expect(result.error, isA<InvalidResponseError>());
    });

    test('decodes present and suppressed mirror hash responses', () {
      final present = decode(
        '{"status":"present","file":$fileJson}',
        MirrorHashLookup.fromJson,
      ).value!;
      switch (present) {
        case MirrorHashPresent(:final file):
          expect(file.name, 'ata.pdf');
          expect(file.sha256, contains('aa11'));
        case MirrorHashSuppressed():
          fail('expected a present file');
      }

      final suppressed = decode(
        '{"status":"suppressed","file":null}',
        MirrorHashLookup.fromJson,
      ).value!;
      switch (suppressed) {
        case MirrorHashPresent():
          fail('expected a suppressed hash');
        case MirrorHashSuppressed():
          expect(suppressed, const MirrorHashSuppressed());
      }
    });

    test('an unknown mirror hash status is an invalid response', () {
      final result = decode(
        '{"status":"unknown","file":null}',
        MirrorHashLookup.fromJson,
      );
      expect(result.error, isA<InvalidResponseError>());
    });

    test('a wrong type is an invalid response', () {
      final result = decode(
        '{"bootstrapped":"yes","tekoa":null,"version":null}',
        Instance.fromJson,
      );
      expect(result.error, isA<InvalidResponseError>());
    });

    test('an unknown enum word is an invalid response', () {
      final broken = folderJson.replaceFirst(
        '"zona":"casa"',
        '"zona":"aldeia"',
      );
      expect(
        decode(broken, Folder.fromJson).error,
        isA<InvalidResponseError>(),
      );
    });

    test('a body that is not an object is an invalid response', () {
      expect(
        decodeJsonBody(utf8.encode('[]'), 'test', Folder.fromJson).error,
        isA<InvalidResponseError>(),
      );
      expect(
        decodeJsonBody(
          utf8.encode('nao e json'),
          'test',
          Folder.fromJson,
        ).error,
        isA<InvalidResponseError>(),
      );
    });

    test('absent and null optional fields both decode as null', () {
      final absent = decode(
        '{"public_id":"a","papel":"morador","created_at":"now"}',
        Ava.fromJson,
      ).value!;
      expect(absent.username, isNull);
      expect(absent.displayName, isNull);
      expect(absent.activatedAt, isNull);

      final explicit = decode(
        '{"public_id":"a","username":null,"display_name":null,'
        '"papel":"morador","activated_at":null,"deactivated_at":null,'
        '"created_at":"now"}',
        Ava.fromJson,
      ).value!;
      expect(explicit.username, isNull);
      expect(explicit.displayName, isNull);
    });

    test('a pedido page decodes the nested people', () {
      final page = decode(
        pedidosPageJson,
        (reader) => Page.fromJson(reader, Pedido.fromJson),
      ).value!;
      expect(page.items.single.status, PedidoStatus.pendente);
      expect(page.items.single.pedinte?.username, 'joana');
      expect(page.items.single.dono?.username, 'ana');
    });

    test('the error envelope keeps its details', () {
      final envelope = decode(
        '{"error":{"code":"validation_failed","message":"Confira.",'
        '"details":{"nome":["vazio"],"senha":["curta","simples"]}}}',
        (reader) {
          final error = reader.object('error');
          return (
            code: error.string('code'),
            details: error.stringListMapOrEmpty('details'),
          );
        },
      ).value!;
      expect(envelope.code, 'validation_failed');
      expect(envelope.details['senha'], ['curta', 'simples']);
    });

    test('an envelope without details answers an empty map', () {
      final envelope = decode(
        '{"error":{"code":"not_authenticated","message":"Entre."}}',
        (reader) {
          final error = reader.object('error');
          return error.stringListMapOrEmpty('details');
        },
      ).value!;
      expect(envelope, isEmpty);
    });
  });

  test('backup equality includes the status', () {
    const ok = SaudeBackup(status: SaudeBackupStatus.ok, at: null, bytes: null);
    const none = SaudeBackup(
      status: SaudeBackupStatus.none,
      at: null,
      bytes: null,
    );
    expect(ok, isNot(none));
    expect(
      ok.hashCode,
      Object.hash(SaudeBackup, SaudeBackupStatus.ok, null, null),
    );
    expect(
      none.hashCode,
      Object.hash(SaudeBackup, SaudeBackupStatus.none, null, null),
    );
  });

  group('session encoding', () {
    test('round trips through the persisted JSON', () {
      final session = fixturedSession();
      final roundTripped = Session.fromPersistedJson(
        jsonDecode(jsonEncode(session.toJson())) as Map<String, Object?>,
      );
      expect(roundTripped, session);
      expect(roundTripped.identity.ava, session.me);
    });

    test('the stored label falls back through display name and username', () {
      const ava = Ava(
        publicId: 'a',
        username: 'ana',
        displayName: 'Ana Souza',
        papel: Papel.zelador,
        activatedAt: null,
        deactivatedAt: null,
        createdAt: 'now',
      );
      expect(ava.label, 'Ana Souza');
      expect(
        const Ava(
          publicId: 'a',
          username: 'ana',
          displayName: null,
          papel: Papel.morador,
          activatedAt: null,
          deactivatedAt: null,
          createdAt: 'now',
        ).label,
        'ana',
      );
      expect(
        const Ava(
          publicId: 'a',
          username: null,
          displayName: null,
          papel: Papel.morador,
          activatedAt: null,
          deactivatedAt: null,
          createdAt: 'now',
        ).label,
        'Convite pendente',
      );
    });
  });

  group('Sort', () {
    test('the wire is key and direction', () {
      expect(const Sort(key: SortKey.date).wire, 'date_asc');
      expect(
        const Sort(key: SortKey.name, direction: SortDirection.desc).wire,
        'name_desc',
      );
    });
  });
}
