import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/storage/storage_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

const StorageByKind _noKinds = StorageByKind(
  photos: 0,
  videos: 0,
  documents: 0,
  others: 0,
);

const StorageStats _partitioned = StorageStats(
  usedBytes: 95,
  quotaBytes: 100,
  byZone: StorageByZone(casa: 70, praca: 20, lixeira: 5),
  byKind: _noKinds,
  files: 4,
  photos: 1,
  trash: StorageTrash(count: 1, bytes: 5),
);

void main() {
  test('load reads the portrait and caretaker role', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final StorageModel model = StorageModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    await model.load();

    expect(model.stats, isNotNull);
    expect(model.isZelador, isTrue);
    expect(model.zeladorNames, ['Ana Souza']);
    expect(model.error, isNull);
    expect(model.loading, isFalse);
  });

  test('a morador reads the portrait without a quota action', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final StorageModel model = StorageModel(
      gateway: FakeSession(api, me: identity(joana)),
    );

    await model.load();

    expect(model.isZelador, isFalse);
  });

  test('setQuota saves a limit and reloads the portrait', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final StorageModel model = StorageModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();

    final int quota = StorageModel.bytesFromGigabytes(500);
    final TainaResult<void> result = await model.setQuota(quota);

    expect(result.isSuccess, isTrue);
    expect(model.stats!.quotaBytes, quota);
    expect(model.saving, isFalse);
  });

  test('setQuota accepts null for the whole disk', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final StorageModel model = StorageModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();

    final TainaResult<void> result = await model.setQuota(null);

    expect(result.isSuccess, isTrue);
    expect(model.stats!.quotaBytes, isNull);
    expect(
      StorageModel.summary(model.stats!).usedLabel,
      startsWith('Usando o disco inteiro: '),
    );
  });

  group('pure storage summaries', () {
    test('only shows zone rows when they sum to the total', () {
      final List<StorageZoneLine>? rows = StorageModel.zones(_partitioned);
      expect(rows, isNotNull);
      expect(rows!.map((StorageZoneLine row) => row.title), [
        'Casas (de cada morador)',
        'Praça',
        'Lixeira',
      ]);
      expect(rows.map((StorageZoneLine row) => row.bytes), [70, 20, 5]);
    });

    test('hides a missing, negative, or incomplete zone breakdown', () {
      expect(StorageModel.zones(_withoutZones()), isNull);
      expect(
        StorageModel.zones(
          _withZones(const StorageByZone(casa: 70, praca: 20, lixeira: 4)),
        ),
        isNull,
      );
      expect(
        StorageModel.zones(
          _withZones(const StorageByZone(casa: 100, praca: -10, lixeira: 5)),
        ),
        isNull,
      );
    });

    test('formats a limited community summary', () {
      final StorageSummary summary = StorageModel.summary(_partitioned);
      expect(summary.usedLabel, '95 B de 100 B');
      expect(summary.caption, '5 B livres');
      expect(summary.progress, 0.95);
    });

    test(
      'uses the current disk size, then legacy size, then unknown fallback',
      () {
        const StorageStats current = StorageStats(
          usedBytes: 80,
          quotaBytes: null,
          diskBytes: 100,
          diskFreeBytes: 20,
          byKind: _noKinds,
          files: 0,
          photos: 0,
          trash: StorageTrash(count: 0, bytes: 0),
        );
        final StorageSummary currentSummary = StorageModel.summary(current);
        expect(StorageModel.diskBytes(current), 100);
        expect(
          currentSummary.usedLabel,
          'Usando o disco inteiro: 80 B de 100 B',
        );
        expect(currentSummary.caption, '20 B livres');
        expect(currentSummary.progress, 0.8);

        const StorageStats legacy = StorageStats(
          usedBytes: 80,
          quotaBytes: null,
          diskTotalBytes: 200,
          diskFreeBytes: 50,
          byKind: _noKinds,
          files: 0,
          photos: 0,
          trash: StorageTrash(count: 0, bytes: 0),
        );
        expect(StorageModel.diskBytes(legacy), 200);
        expect(StorageModel.summary(legacy).caption, '50 B livres');

        const StorageStats unknown = StorageStats(
          usedBytes: 80,
          quotaBytes: null,
          byKind: _noKinds,
          files: 0,
          photos: 0,
          trash: StorageTrash(count: 0, bytes: 0),
        );
        final StorageSummary unknownSummary = StorageModel.summary(unknown);
        expect(unknownSummary.usedLabel, 'Usando o disco inteiro: 80 B em uso');
        expect(unknownSummary.caption, 'Espaço livre não informado.');
        expect(unknownSummary.progress, 0);
      },
    );

    test('derives physical free space when the box only reports disk size', () {
      const StorageStats stats = StorageStats(
        usedBytes: 75,
        quotaBytes: null,
        diskBytes: 100,
        byKind: _noKinds,
        files: 0,
        photos: 0,
        trash: StorageTrash(count: 0, bytes: 0),
      );
      expect(StorageModel.diskFreeBytes(stats), 25);
      expect(StorageModel.summary(stats).caption, '25 B livres');
    });

    test('does not report a negative free space above quota', () {
      const StorageStats over = StorageStats(
        usedBytes: 110,
        quotaBytes: 100,
        byKind: _noKinds,
        files: 0,
        photos: 0,
        trash: StorageTrash(count: 0, bytes: 0),
      );
      expect(StorageModel.isOverQuota(over), isTrue);
      expect(
        StorageModel.summary(over).caption,
        'O limite está abaixo do espaço usado.',
      );
    });
  });

  test('gigabytes round up and bytes use the wire unit', () {
    expect(StorageModel.gigabytes(null), 250);
    expect(StorageModel.gigabytes(1073741824), 1);
    expect(StorageModel.gigabytes(1073741825), 2);
    expect(StorageModel.bytesFromGigabytes(2), 2147483648);
  });
}

StorageStats _withoutZones() => const StorageStats(
  usedBytes: 95,
  quotaBytes: 100,
  byKind: _noKinds,
  files: 0,
  photos: 0,
  trash: StorageTrash(count: 0, bytes: 0),
);

StorageStats _withZones(StorageByZone zones) => StorageStats(
  usedBytes: 95,
  quotaBytes: 100,
  byZone: zones,
  byKind: _noKinds,
  files: 0,
  photos: 0,
  trash: const StorageTrash(count: 0, bytes: 0),
);
