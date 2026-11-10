import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/storage/storage_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

const StorageStats small = StorageStats(
  usedBytes: 95,
  quotaBytes: 100,
  byKind: StorageByKind(photos: 40, videos: 30, documents: 20, others: 5),
  files: 4,
  photos: 1,
  trash: StorageTrash(count: 2, bytes: 2400000),
);

void main() {
  test('load reads the portrait and the zeladora role', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final StorageModel model = StorageModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    await model.load();

    expect(model.stats, isNotNull);
    expect(model.isZelador, isTrue);
    expect(model.error, isNull);
    expect(model.loading, isFalse);
    expect(StorageModel.byKindTotal(model.stats!), model.stats!.usedBytes);
  });

  test('a morador reads the portrait but not the quota act', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final StorageModel model = StorageModel(
      gateway: FakeSession(api, me: identity(joana)),
    );

    await model.load();

    expect(model.isZelador, isFalse);
  });

  test('setQuota saves and reads the portrait again', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final StorageModel model = StorageModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();

    final result = await model.setQuota(StorageModel.bytesFromGigabytes(500));

    expect(result.isSuccess, isTrue);
    expect(model.stats!.quotaBytes, StorageModel.bytesFromGigabytes(500));
    expect(model.saving, isFalse);
  });

  group('pure transitions', () {
    test('kinds are widest first', () {
      final List<StorageKindLine> lines = StorageModel.kinds(small);
      expect(lines.map((StorageKindLine line) => line.kind), [
        StorageKind.photos,
        StorageKind.videos,
        StorageKind.documents,
        StorageKind.others,
      ]);
    });

    test('segments drop the empty kinds and sum to the used bytes', () {
      final List<StorageSegment> segments = StorageModel.segments(small);
      expect(segments, hasLength(4));
      expect(segments.first.kind, StorageKind.photos);
      expect(
        segments.fold<double>(
          0,
          (double sum, StorageSegment segment) => sum + segment.fraction,
        ),
        closeTo(1, 0.0001),
      );

      final StorageStats empty = StorageStats(
        usedBytes: 0,
        quotaBytes: null,
        byKind: const StorageByKind(
          photos: 0,
          videos: 0,
          documents: 0,
          others: 0,
        ),
        files: 0,
        photos: 0,
        trash: const StorageTrash(count: 0, bytes: 0),
      );
      expect(StorageModel.segments(empty), isEmpty);
    });

    test('low free is at most a tenth of the quota', () {
      expect(StorageModel.isLowFree(small), isTrue);
      expect(
        StorageModel.isLowFree(
          const StorageStats(
            usedBytes: 50,
            quotaBytes: 100,
            byKind: StorageByKind(
              photos: 0,
              videos: 0,
              documents: 0,
              others: 0,
            ),
            files: 0,
            photos: 0,
            trash: StorageTrash(count: 0, bytes: 0),
          ),
        ),
        isFalse,
      );
      expect(
        StorageModel.isLowFree(
          const StorageStats(
            usedBytes: 10,
            quotaBytes: null,
            byKind: StorageByKind(
              photos: 0,
              videos: 0,
              documents: 0,
              others: 0,
            ),
            files: 0,
            photos: 0,
            trash: StorageTrash(count: 0, bytes: 0),
          ),
        ),
        isFalse,
      );
    });

    test('over quota is a limit below the use', () {
      expect(StorageModel.isOverQuota(small), isFalse);
      expect(
        StorageModel.isOverQuota(
          const StorageStats(
            usedBytes: 110,
            quotaBytes: 100,
            byKind: StorageByKind(
              photos: 0,
              videos: 0,
              documents: 0,
              others: 0,
            ),
            files: 0,
            photos: 0,
            trash: StorageTrash(count: 0, bytes: 0),
          ),
        ),
        isTrue,
      );
      expect(
        StorageModel.isOverQuota(
          const StorageStats(
            usedBytes: 110,
            quotaBytes: null,
            byKind: StorageByKind(
              photos: 0,
              videos: 0,
              documents: 0,
              others: 0,
            ),
            files: 0,
            photos: 0,
            trash: StorageTrash(count: 0, bytes: 0),
          ),
        ),
        isFalse,
      );
    });

    test('gigabytes rounds up and defaults to the web value', () {
      expect(StorageModel.gigabytes(null), 250);
      expect(StorageModel.gigabytes(0), 250);
      expect(StorageModel.gigabytes(1073741824), 1);
      expect(StorageModel.gigabytes(1073741825), 2);
    });

    test('bytesFromGigabytes speaks the wire unit', () {
      expect(StorageModel.bytesFromGigabytes(2), 2147483648);
    });

    test('trashSummary agrees in number and size', () {
      expect(
        StorageModel.trashSummary(const StorageTrash(count: 1, bytes: 2400000)),
        '1 arquivo, ${TainaFormat.bytes(2400000)}',
      );
      expect(
        StorageModel.trashSummary(const StorageTrash(count: 2, bytes: 2400000)),
        '2 arquivos, ${TainaFormat.bytes(2400000)}',
      );
    });
  });
}
