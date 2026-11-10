import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/files/move_view_model.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fakes.dart';

final class _FailingFoldersApi implements TainaApi {
  @override
  Future<TainaResult<List<Folder>>> listFolders() async {
    return const Err(NetworkError());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('move destinations', () {
    test('a folder never offers itself or its descendants', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final root = (await api.createFolder(name: 'Raiz')).value!;
      final child = (await api.createFolder(
        name: 'Filha',
        parentRkey: root.rkey,
      )).value!;
      final grandchild = (await api.createFolder(
        name: 'Neta',
        parentRkey: child.rkey,
      )).value!;
      final viewModel = MoveViewModel(
        session: FakeSessionGateway(api: api),
        sourceRkey: root.rkey,
        isFolder: true,
      );

      await viewModel.load();

      final rkeys = viewModel.destinations.map((folder) => folder.rkey);
      expect(rkeys, isNot(contains(root.rkey)));
      expect(rkeys, isNot(contains(child.rkey)));
      expect(rkeys, isNot(contains(grandchild.rkey)));
      expect(viewModel.loading, isFalse);
      expect(viewModel.error, isNull);
    });

    test('a file source offers every folder', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final root = (await api.createFolder(name: 'Raiz')).value!;
      final viewModel = MoveViewModel(
        session: FakeSessionGateway(api: api),
        sourceRkey: 'file-rkey',
        isFolder: false,
      );

      await viewModel.load();

      expect(
        viewModel.destinations.map((folder) => folder.rkey),
        contains(root.rkey),
      );
      expect(viewModel.destinations, hasLength(3));
    });

    test('a failed listing keeps the error for the retry state', () async {
      final viewModel = MoveViewModel(
        session: FakeSessionGateway(api: _FailingFoldersApi()),
        sourceRkey: 'f1',
        isFolder: false,
      );

      await viewModel.load();

      expect(viewModel.error, isA<NetworkError>());
      expect(viewModel.destinations, isEmpty);
      expect(viewModel.loading, isFalse);
    });
  });
}
