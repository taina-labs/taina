import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/saude/saude_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

const StorageByKind noBytes = StorageByKind(
  photos: 0,
  videos: 0,
  documents: 0,
  others: 0,
);

const StorageStats stats = StorageStats(
  usedBytes: 90,
  quotaBytes: 100,
  byKind: noBytes,
  files: 1,
  photos: 0,
  trash: StorageTrash(count: 0, bytes: 0),
);

void main() {
  test('load reads the panel and the zeladora role', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final SaudeModel model = SaudeModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    await model.load();

    expect(model.saude, isNotNull);
    expect(model.isZelador, isTrue);
    expect(model.error, isNull);
    expect(SaudeModel.rows(model.saude!), hasLength(2));
  });

  test('a morador reads the panel but cannot trigger the backup', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final SaudeModel model = SaudeModel(
      gateway: FakeSession(api, me: identity(joana)),
    );

    await model.load();

    expect(model.isZelador, isFalse);
  });

  test('backupNow queues the backup and answers', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final SaudeModel model = SaudeModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    final result = await model.backupNow();

    expect(result.isSuccess, isTrue);
    expect(model.triggering, isFalse);
  });

  group('pure transitions', () {
    test('diskRow reads the used, the quota and the free room', () {
      final SaudeRow row = SaudeModel.diskRow(stats);
      expect(row.icon, SaudeRowIcon.disk);
      expect(row.lines.first, '90 B usados de 100 B. 10 B livres.');
      expect(
        row.warning,
        'O espaço está acabando. Quem cuida da máquina pode '
        'aumentar o limite.',
      );
    });

    test('diskRow without a quota says there is no limit', () {
      const StorageStats unlimited = StorageStats(
        usedBytes: 90,
        quotaBytes: null,
        byKind: noBytes,
        files: 1,
        photos: 0,
        trash: StorageTrash(count: 0, bytes: 0),
      );
      final SaudeRow row = SaudeModel.diskRow(unlimited);
      expect(row.lines.first, '90 B usados. Sem limite.');
      expect(row.warning, isNull);
    });

    test('trashLines is a fact only when the trash holds something', () {
      expect(
        SaudeModel.trashLines(const StorageTrash(count: 0, bytes: 0)),
        isEmpty,
      );
      expect(SaudeModel.trashLines(const StorageTrash(count: 1, bytes: 2048)), [
        '2,0 KB na lixeira esperando a limpeza (1 arquivo).',
      ]);
    });

    test('backupRow reads finished, finished with size, and never', () {
      expect(
        SaudeModel.backupRow(
          const SaudeBackup(at: '2026-10-14T03:00:00Z', bytes: 2048),
        ).lines.first,
        contains('guardados'),
      );
      expect(
        SaudeModel.backupRow(
          const SaudeBackup(at: '2026-10-14T03:00:00Z', bytes: null),
        ).lines.first,
        isNot(contains('guardados')),
      );
      expect(
        SaudeModel.backupRow(const SaudeBackup(at: null, bytes: null))
            .lines
            .first,
        'Nunca foi feito um backup.',
      );
    });

    test('jobsRow disappears when every queue is quiet', () {
      expect(SaudeModel.jobsRow(const {'renditions': 0, 'backups': 0}), isNull);
    });

    test('jobsRow orders queues and speaks each one', () {
      final SaudeRow? row = SaudeModel.jobsRow(const {
        'renditions': 1,
        'backups': 2,
        'trash_purge': 1,
      });
      expect(row, isNotNull);
      expect(row!.lines, [
        '2 backups em andamento',
        '1 miniatura ainda sendo gerada',
        '1 limpeza da lixeira em andamento',
      ]);
    });

    test('an unknown queue keeps its name', () {
      expect(
        SaudeModel.jobLine(queue: 'exports', count: 1),
        '1 trabalho na fila exports',
      );
      expect(
        SaudeModel.jobLine(queue: 'exports', count: 3),
        '3 trabalhos na fila exports',
      );
    });
  });
}
