import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/saude/saude_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

const StorageStats _space = StorageStats(
  usedBytes: 50,
  quotaBytes: 100,
  byKind: StorageByKind(photos: 0, videos: 0, documents: 0, others: 0),
  files: 0,
  photos: 0,
  trash: StorageTrash(count: 0, bytes: 0),
);

Saude _saude({
  SaudeBackupStatus backup = SaudeBackupStatus.ok,
  SaudeSummary? summary,
  SaudeUpdate? update,
  StorageStats storage = _space,
}) => Saude(
  storage: storage,
  jobs: const {},
  backup: SaudeBackup(
    status: backup,
    at: backup == SaudeBackupStatus.ok ? '2026-10-14T03:00:00Z' : null,
    bytes: null,
  ),
  summary: summary,
  update: update,
);

void main() {
  test('load reads the panel and the zelador role', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final SaudeModel model = SaudeModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    await model.load();

    expect(model.saude, isNotNull);
    expect(model.isZelador, isTrue);
    expect(model.canTriggerBackup, isTrue);
    expect(model.panelState, SaudePanelState.zelador);
    expect(model.zeladorNames, ['Ana Souza']);
    expect(model.error, isNull);
    expect(model.loading, isFalse);
  });

  test('a morador sees the panel and cannot trigger a backup', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final SaudeModel model = SaudeModel(
      gateway: FakeSession(api, me: identity(joana)),
    );

    await model.load();

    expect(model.isZelador, isFalse);
    expect(model.canTriggerBackup, isFalse);
    expect(model.panelState, SaudePanelState.morador);
    expect(
      SaudeModel.footer(model.panelState, zeladorName: 'Ana Souza'),
      'Quem cuida da nuvem: Ana Souza. Cuida da máquina, não dos arquivos.',
    );
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

  test(
    'a zelador can start the first backup and retry a failed backup',
    () async {
      for (final SaudeBackupStatus status in [
        SaudeBackupStatus.never,
        SaudeBackupStatus.failed,
      ]) {
        final FakeTainaApi api = FakeTainaApi(
          delay: Duration.zero,
          backup: SaudeBackup(status: status, at: null, bytes: null),
        );
        final SaudeModel model = SaudeModel(
          gateway: FakeSession(api, me: identity(ana)),
        );

        await model.load();

        expect(model.canTriggerBackup, isTrue, reason: status.name);
        model.dispose();
      }
    },
  );

  group('pure status selection', () {
    test('always returns the four board rows in order', () {
      final List<SaudeStatus> rows = SaudeModel.statuses(_saude());
      expect(rows, hasLength(4));
      expect(rows.map((SaudeStatus row) => row.title), [
        'Espaço de sobra',
        'Backup em dia',
        'Atualizações',
        'Tudo no ar',
      ]);
      expect(rows.map((SaudeStatus row) => row.state), [
        TainaStatusState.ok,
        TainaStatusState.ok,
        TainaStatusState.unknown,
        TainaStatusState.ok,
      ]);
    });

    test('the disk summary and capacity select the attention status', () {
      final Saude attention = _saude(
        backup: SaudeBackupStatus.failed,
        summary: const SaudeSummary(
          state: SaudeSummaryState.attention,
          line: 'Disco quase cheio',
        ),
        storage: const StorageStats(
          usedBytes: 95,
          quotaBytes: 100,
          byKind: StorageByKind(photos: 0, videos: 0, documents: 0, others: 0),
          files: 0,
          photos: 0,
          trash: StorageTrash(count: 0, bytes: 0),
        ),
        update: const SaudeUpdate(
          status: SaudeUpdateStatus.upToDate,
          running: '1.0.0',
          latest: '1.0.0',
        ),
      );
      final List<SaudeStatus> rows = SaudeModel.statuses(attention);

      expect(rows.map((SaudeStatus row) => row.title), [
        'Disco quase cheio',
        'Último backup falhou',
        'Atualizações em dia',
        'Tudo no ar',
      ]);
      expect(rows.map((SaudeStatus row) => row.state), [
        TainaStatusState.attention,
        TainaStatusState.problem,
        TainaStatusState.ok,
        TainaStatusState.ok,
      ]);
      expect(
        SaudeModel.stateFor(attention, isZelador: false),
        SaudePanelState.atencao,
      );
      expect(
        SaudeModel.footer(SaudePanelState.atencao),
        'Vale falar com quem cuida da nuvem. Ninguém perdeu arquivo.',
      );
    });

    test('the fallback marks a first backup as attention', () {
      final SaudeStatus status = SaudeModel.backupStatus(
        const SaudeBackup(
          status: SaudeBackupStatus.never,
          at: null,
          bytes: null,
        ),
      );
      expect(status.title, 'Nenhum backup ainda');
      expect(status.state, TainaStatusState.attention);
      expect(
        SaudeModel.stateFor(
          _saude(backup: SaudeBackupStatus.never),
          isZelador: true,
        ),
        SaudePanelState.atencao,
      );
    });

    test('an absent update model is a present unknown row', () {
      expect(SaudeModel.updateStatus(null).title, 'Atualizações');
      expect(SaudeModel.updateStatus(null).state, TainaStatusState.unknown);
    });

    test('update statuses use the available optional model', () {
      expect(
        SaudeModel.updateStatus(
          const SaudeUpdate(
            status: SaudeUpdateStatus.updateAvailable,
            running: '1.0.0',
            latest: '1.1.0',
          ),
        ),
        const SaudeStatus(
          state: TainaStatusState.attention,
          title: 'Atualização disponível',
        ),
      );
      expect(
        SaudeModel.updateStatus(
          const SaudeUpdate(
            status: SaudeUpdateStatus.upToDate,
            running: '1.0.0',
            latest: '1.0.0',
          ),
        ).title,
        'Atualizações em dia',
      );
    });

    test('disk warning falls back to the physical disk values', () {
      const StorageStats stats = StorageStats(
        usedBytes: 91,
        quotaBytes: null,
        diskBytes: 100,
        byKind: StorageByKind(photos: 0, videos: 0, documents: 0, others: 0),
        files: 0,
        photos: 0,
        trash: StorageTrash(count: 0, bytes: 0),
      );
      expect(SaudeModel.isAlmostFull(stats), isTrue);
      expect(
        SaudeModel.statuses(_saude(storage: stats)).first.title,
        'Disco quase cheio',
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
            status == SaudeBackupStatus.never ||
            status == SaudeBackupStatus.failed ||
            status == SaudeBackupStatus.unreadable,
      );
      model.dispose();
    });
  }
}
