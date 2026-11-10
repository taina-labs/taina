import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/trash/trash_view_model.dart';
import 'package:okena_core/okena_core.dart';

import '../files/support/fakes.dart';

FileRecord _file(String rkey) {
  return FileRecord(
    rkey: rkey,
    cid: 'cid-$rkey',
    blobCid: 'blob-$rkey',
    sha256: 'sha-$rkey',
    name: 'arquivo $rkey.txt',
    mime: 'text/plain',
    size: 10,
    zona: Zona.casa,
    folder: null,
    takenAt: null,
    width: null,
    height: null,
    rendition: Rendition.none,
    deletedAt: '2026-03-10T12:00:00Z',
    createdAt: '2026-03-01T12:00:00Z',
    updatedAt: '2026-03-10T12:00:00Z',
  );
}

final class _FailingTrashApi implements TainaApi {
  @override
  Future<TainaResult<Page<FileRecord>>> trash({
    int? limit,
    String? cursor,
  }) async {
    return const Err(NetworkError());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A trash API that answers the pages the test hands it and can fail the
/// restore call on purpose.
final class _PagedTrashApi implements TainaApi {
  _PagedTrashApi(this.pages);

  final List<TainaResult<Page<FileRecord>>> pages;
  TainaResult<FileRecord> restoreOutcome = const Ok(
    FileRecord(
      rkey: 'f1',
      cid: 'cid',
      blobCid: 'blob',
      sha256: 'sha',
      name: 'arquivo.txt',
      mime: 'text/plain',
      size: 10,
      zona: Zona.casa,
      folder: null,
      takenAt: null,
      width: null,
      height: null,
      rendition: Rendition.none,
      deletedAt: null,
      createdAt: '2026-03-01T12:00:00Z',
      updatedAt: '2026-03-10T12:00:00Z',
    ),
  );

  @override
  Future<TainaResult<Page<FileRecord>>> trash({
    int? limit,
    String? cursor,
  }) async {
    final index = cursor == null ? 0 : int.parse(cursor);
    return pages[index];
  }

  @override
  Future<TainaResult<FileRecord>> restoreFile({required String rkey}) async {
    return restoreOutcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('pagination', () {
    test('walks the cursor and appends the items', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      for (final rkey in const [
        '3m2a8twqpv5z2',
        '3m5c9vxyq2b7t',
        '3m7d1wyzr4c8u',
        '3m8e2xz0s5d9v',
        '3m9f4xk1q7v2n',
      ]) {
        await api.deleteFile(rkey: rkey);
      }
      final viewModel = TrashViewModel(
        session: FakeSessionGateway(api: api),
        pageSize: 2,
      );

      await viewModel.load();
      expect(viewModel.items, hasLength(2));
      expect(viewModel.nextCursor, '2');

      await viewModel.loadMore();
      expect(viewModel.items, hasLength(4));
      expect(viewModel.nextCursor, '4');

      await viewModel.loadMore();
      expect(viewModel.items, hasLength(5));
      expect(viewModel.nextCursor, isNull);

      await viewModel.loadMore();
      expect(viewModel.items, hasLength(5));
      expect(viewModel.moreError, isFalse);
    });

    test('a failed page keeps the items and the cursor for retry', () async {
      final api = _PagedTrashApi([
        Ok(Page(items: [_file('f1')], nextCursor: '1')),
        const Err(NetworkError()),
        Ok(Page(items: [_file('f2')], nextCursor: null)),
      ]);
      final viewModel = TrashViewModel(
        session: FakeSessionGateway(api: api),
        pageSize: 1,
      );

      await viewModel.load();
      await viewModel.loadMore();

      expect(viewModel.items.map((file) => file.rkey), ['f1']);
      expect(viewModel.nextCursor, '1');
      expect(viewModel.moreError, isTrue);

      api.pages[1] = Ok(Page(items: [_file('f2')], nextCursor: null));
      await viewModel.loadMore();
      expect(viewModel.items.map((file) => file.rkey), ['f1', 'f2']);
      expect(viewModel.moreError, isFalse);
      expect(viewModel.nextCursor, isNull);
    });
  });

  group('states', () {
    test('an empty trash reports no error', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final viewModel = TrashViewModel(session: FakeSessionGateway(api: api));

      await viewModel.load();

      expect(viewModel.items, isEmpty);
      expect(viewModel.error, isNull);
      expect(viewModel.loading, isFalse);
    });

    test('a failed first page keeps the error for the retry state', () async {
      final viewModel = TrashViewModel(
        session: FakeSessionGateway(api: _FailingTrashApi()),
      );

      await viewModel.load();

      expect(viewModel.items, isEmpty);
      expect(viewModel.error, isA<NetworkError>());
      expect(viewModel.loading, isFalse);
    });
  });

  group('restore', () {
    test('drops the row and brings the file back', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      await api.deleteFile(rkey: '3m7d1wyzr4c8u');
      final viewModel = TrashViewModel(session: FakeSessionGateway(api: api));
      await viewModel.load();
      expect(viewModel.items, hasLength(1));

      final result = await viewModel.restore(rkey: viewModel.items.first.rkey);

      expect(result.isSuccess, isTrue);
      expect(viewModel.items, isEmpty);
      expect(viewModel.restoringRkey, isNull);
      final restored = await api.file(rkey: '3m7d1wyzr4c8u');
      expect(restored.value?.deletedAt, isNull);
    });

    test('a failed restore keeps the row and the failure', () async {
      final api =
          _PagedTrashApi([
              Ok(Page(items: [_file('f1')], nextCursor: null)),
            ])
            ..restoreOutcome = const Err(
              ApiError(
                code: 'forbidden',
                status: 403,
                serverMessage: 'Esta casa é particular.',
              ),
            );
      final viewModel = TrashViewModel(session: FakeSessionGateway(api: api));
      await viewModel.load();

      final result = await viewModel.restore(rkey: 'f1');

      expect(result.isSuccess, isFalse);
      expect(viewModel.items, hasLength(1));
      expect(viewModel.restoringRkey, isNull);
      expect(result.error?.message, 'Esta casa é particular.');
    });
  });
}
