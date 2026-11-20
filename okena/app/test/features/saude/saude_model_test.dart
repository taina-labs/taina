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

StorageStats _stats({
  int usedBytes = 90,
  int? quotaBytes = 100,
  int? diskTotalBytes,
  int? diskFreeBytes,
}) => StorageStats(
  usedBytes: usedBytes,
  quotaBytes: quotaBytes,
  diskTotalBytes: diskTotalBytes,
  diskFreeBytes: diskFreeBytes,
  byKind: noBytes,
  files: 1,
  photos: 0,
  trash: const StorageTrash(count: 0, bytes: 0),
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
    expect(model.canTriggerBackup, isTrue);
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
    expect(model.canTriggerBackup, isFalse);
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
      expect(SaudeModel.isAlmostFull(unlimited), isFalse);
    });

    test('diskRow without a quota includes known physical free space', () {
      final SaudeRow row = SaudeModel.diskRow(
        _stats(quotaBytes: null, diskTotalBytes: 100, diskFreeBytes: 10),
      );
      expect(row.lines.first, '90 B usados. 10 B livres no disco.');
      expect(
        row.warning,
        'O espaço do disco está acabando. Quem cuida da máquina precisa '
        'liberar espaço no disco.',
      );
    });

    test('physical disk alert starts at ten percent free', () {
      expect(
        SaudeModel.isAlmostFull(
          _stats(quotaBytes: null, diskTotalBytes: 100, diskFreeBytes: 10),
        ),
        isTrue,
      );
    });

    test('physical disk alert stays off above ten percent free', () {
      expect(
        SaudeModel.isAlmostFull(
          _stats(quotaBytes: null, diskTotalBytes: 100, diskFreeBytes: 11),
        ),
        isFalse,
      );
    });

    test('physical disk alert applies below ten percent free', () {
      expect(
        SaudeModel.isAlmostFull(
          _stats(quotaBytes: null, diskTotalBytes: 100, diskFreeBytes: 9),
        ),
        isTrue,
      );
    });

    test('physical disk alert works without a quota', () {
      final SaudeRow row = SaudeModel.diskRow(
        _stats(quotaBytes: null, diskTotalBytes: 100, diskFreeBytes: 9),
      );
      expect(
        SaudeModel.isAlmostFull(
          _stats(quotaBytes: null, diskTotalBytes: 100, diskFreeBytes: 9),
        ),
        isTrue,
      );
      expect(row.warning, contains('O espaço do disco está acabando.'));
    });

    test('physical disk warning takes precedence over the quota warning', () {
      final SaudeRow row = SaudeModel.diskRow(
        _stats(
          usedBytes: 95,
          quotaBytes: 100,
          diskTotalBytes: 100,
          diskFreeBytes: 10,
        ),
      );
      expect(
        row.warning,
        'O espaço do disco está acabando. Quem cuida da máquina precisa '
        'liberar espaço no disco.',
      );
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

    test('backupRow reads a successful backup with and without its size', () {
      expect(
        SaudeModel.backupRow(
          const SaudeBackup(
            status: SaudeBackupStatus.ok,
            at: '2026-10-14T03:00:00Z',
            bytes: 2048,
          ),
        ).lines.first,
        contains('guardados'),
      );
      expect(
        SaudeModel.backupRow(
          const SaudeBackup(
            status: SaudeBackupStatus.ok,
            at: '2026-10-14T03:00:00Z',
            bytes: null,
          ),
        ).lines.first,
        isNot(contains('guardados')),
      );
      expect(
        SaudeModel.backupRow(
          const SaudeBackup(
            status: SaudeBackupStatus.none,
            at: null,
            bytes: null,
          ),
        ).lines.first,
        'Nunca foi feito um backup.',
      );
    });

    test('backupRow reports disabled, unconfigured and unreadable states', () {
      final SaudeRow disabled = SaudeModel.backupRow(
        const SaudeBackup(
          status: SaudeBackupStatus.disabled,
          at: null,
          bytes: null,
        ),
      );
      expect(disabled.lines, ['O backup está desativado.']);
      expect(
        disabled.warning,
        'Quem cuida da máquina precisa ativar o backup.',
      );

      final SaudeRow notConfigured = SaudeModel.backupRow(
        const SaudeBackup(
          status: SaudeBackupStatus.notConfigured,
          at: null,
          bytes: null,
        ),
      );
      expect(notConfigured.lines, ['O backup está sem destino.']);
      expect(
        notConfigured.warning,
        'Quem cuida da máquina precisa escolher onde guardar o backup.',
      );

      final SaudeRow unreadable = SaudeModel.backupRow(
        const SaudeBackup(
          status: SaudeBackupStatus.unreadable,
          at: null,
          bytes: null,
        ),
      );
      expect(unreadable.lines, ['Não foi possível ler o destino do backup.']);
      expect(
        unreadable.warning,
        'Quem cuida da máquina precisa verificar o destino.',
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

  for (final SaudeBackupStatus status in SaudeBackupStatus.values) {
    test('canTriggerBackup for ${status.name}', () async {
      final FakeTainaApi api = FakeTainaApi(
        delay: Duration.zero,
        backup: SaudeBackup(status: status, at: null, bytes: null),
      );
      final SaudeModel model = SaudeModel(
        gateway: FakeSession(api, me: identity(ana)),
      );

      await model.load();

      expect(
        model.canTriggerBackup,
        status == SaudeBackupStatus.ok ||
            status == SaudeBackupStatus.none ||
            status == SaudeBackupStatus.unreadable,
      );
      model.dispose();
    });
  }
}
