import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/files/file_detail_view_model.dart';
import 'package:okena_app/src/features/files/files_logic.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fakes.dart';

const _ana = Ava(
  publicId: 'ava-ana',
  username: 'ana',
  displayName: 'Ana Souza',
  papel: Papel.zelador,
  activatedAt: '2026-02-01T09:00:00Z',
  deactivatedAt: null,
  createdAt: '2026-02-01T09:00:00Z',
);

const _target = AccessTarget(owner: _ana, rkey: 'f1', name: 'Foto.jpg');

const _pedido = Pedido(
  publicId: 'ped-1',
  tipo: 'leitura',
  recurso: 'f1',
  motivo: 'Pedido de acesso pela tela do arquivo',
  status: PedidoStatus.pendente,
  decididoEm: null,
  createdAt: '2026-03-10T12:00:00Z',
  pedinte: _ana,
  dono: _ana,
);

FileRecord _file({String rkey = 'f1', Zona zona = Zona.casa, String? folder}) {
  return FileRecord(
    rkey: rkey,
    cid: 'cid',
    blobCid: 'blob',
    sha256: 'sha',
    name: 'Foto.jpg',
    mime: 'image/jpeg',
    size: 1200,
    zona: zona,
    folder: folder,
    takenAt: null,
    width: 10,
    height: 10,
    rendition: Rendition.ready,
    deletedAt: null,
    createdAt: '2026-03-10T12:00:00Z',
    updatedAt: '2026-03-10T12:00:00Z',
  );
}

final class _DeniedDownloadApi implements TainaApi {
  int downloads = 0;
  int requests = 0;
  String? lastMotivo;
  TainaResult<Pedido> requestOutcome = const Ok(_pedido);

  @override
  Future<TainaResult<String>> download({required String rkey}) async {
    downloads += 1;
    return const Err(
      ApiError(
        code: 'forbidden',
        status: 403,
        serverMessage: 'Esta casa é particular.',
      ),
    );
  }

  @override
  Future<TainaResult<AccessTarget>> accessTarget({
    required String fileRkey,
  }) async {
    return const Ok(_target);
  }

  @override
  Future<TainaResult<Pedido>> requestAccess({
    required String fileRkey,
    String? motivo,
  }) async {
    requests += 1;
    lastMotivo = motivo;
    return requestOutcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FailingDownloadApi implements TainaApi {
  @override
  Future<TainaResult<String>> download({required String rkey}) async {
    return const Err(NetworkError());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('access denied', () {
    test('a 403 download resolves who owns the file', () async {
      final api = _DeniedDownloadApi();
      final viewModel = FileDetailViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
        file: _file(),
      );

      final ok = await viewModel.download();

      expect(ok, isTrue);
      expect(api.downloads, 1);
      expect(viewModel.denied, _target);
      expect(viewModel.failure, isNull);
      expect(viewModel.resolving, isFalse);
      expect(viewModel.downloadedPath, isNull);
    });

    test('a non-403 download keeps the failure for the alert', () async {
      final viewModel = FileDetailViewModel(
        session: FakeSessionGateway(api: _FailingDownloadApi()),
        actions: FakeFileActions(),
        file: _file(),
      );

      final ok = await viewModel.download();

      expect(ok, isFalse);
      expect(viewModel.denied, isNull);
      expect(viewModel.failure, isA<NetworkError>());
      expect(viewModel.errorMessage, isNotNull);
    });

    test(
      'requesting access sends the screen motivo and flags the request',
      () async {
        final api = _DeniedDownloadApi();
        final viewModel = FileDetailViewModel(
          session: FakeSessionGateway(api: api),
          actions: FakeFileActions(),
          file: _file(),
        );
        await viewModel.download();

        final sent = await viewModel.requestAccess();

        expect(sent, isTrue);
        expect(api.requests, 1);
        expect(api.lastMotivo, FilesLogic.accessMotivo);
        expect(viewModel.requested, isTrue);
      },
    );

    test('a failed request keeps the failure and does not flag it', () async {
      final api = _DeniedDownloadApi()
        ..requestOutcome = const Err(
          ApiError(
            code: 'forbidden',
            status: 403,
            serverMessage: 'Você já pediu.',
          ),
        );
      final viewModel = FileDetailViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
        file: _file(),
      );
      await viewModel.download();

      final sent = await viewModel.requestAccess();

      expect(sent, isFalse);
      expect(viewModel.requested, isFalse);
      expect(viewModel.errorMessage, 'Você já pediu.');
    });
  });

  group('download, share and preview', () {
    test('download keeps the path and share hands it to the sheet', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final file = (await api.file(rkey: '3m7d1wyzr4c8u')).value!;
      final actions = FakeFileActions();
      final viewModel = FileDetailViewModel(
        session: FakeSessionGateway(api: api),
        actions: actions,
        file: file,
      );

      expect(await viewModel.download(), isTrue);
      final path = viewModel.downloadedPath;
      expect(path, isNotNull);
      expect(await viewModel.share(), isTrue);
      expect(actions.sharedPaths, [path]);
      expect(actions.shareSubjects, [file.name]);
      expect(await viewModel.preview(), isTrue);
      expect(actions.openedPaths, [path]);
    });

    test('preview downloads first when nothing is here yet', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final file = (await api.file(rkey: '3m7d1wyzr4c8u')).value!;
      final actions = FakeFileActions();
      final viewModel = FileDetailViewModel(
        session: FakeSessionGateway(api: api),
        actions: actions,
        file: file,
      );

      final ok = await viewModel.preview();

      expect(ok, isTrue);
      expect(viewModel.downloadedPath, isNotNull);
      expect(actions.openedPaths, [viewModel.downloadedPath]);
    });

    test('a share failure is surfaced as the alert sentence', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final file = (await api.file(rkey: '3m7d1wyzr4c8u')).value!;
      final actions = FakeFileActions()..shareFailure = 'Sem compartilhamento.';
      final viewModel = FileDetailViewModel(
        session: FakeSessionGateway(api: api),
        actions: actions,
        file: file,
      );
      await viewModel.download();

      final ok = await viewModel.share();

      expect(ok, isFalse);
      expect(viewModel.errorMessage, 'Sem compartilhamento.');
      viewModel.dismissError();
      expect(viewModel.errorMessage, isNull);
    });
  });

  group('file acts', () {
    test('rename swaps the record', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final file = (await api.file(rkey: '3m7d1wyzr4c8u')).value!;
      final viewModel = FileDetailViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
        file: file,
      );

      final ok = await viewModel.rename('Quadra nova.jpg');

      expect(ok, isTrue);
      expect(viewModel.file.name, 'Quadra nova.jpg');
      expect(viewModel.working, isFalse);
    });

    test('publishing takes the file to the praca and back', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final file = (await api.file(rkey: '3m5c9vxyq2b7t')).value!;
      final viewModel = FileDetailViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
        file: file,
      );

      expect(await viewModel.changeZona(), isTrue);
      expect(viewModel.file.zona, Zona.praca);
      expect(await viewModel.changeZona(), isTrue);
      expect(viewModel.file.zona, Zona.casa);
    });

    test('moving updates the folder and delete succeeds', () async {
      final api = FakeTainaApi(delay: Duration.zero);
      final file = (await api.file(rkey: '3m7d1wyzr4c8u')).value!;
      final folders = (await api.listFolders()).value!;
      final viewModel = FileDetailViewModel(
        session: FakeSessionGateway(api: api),
        actions: FakeFileActions(),
        file: file,
      );

      expect(await viewModel.move(folders.first), isTrue);
      expect(viewModel.file.folder, folders.first.rkey);

      expect(await viewModel.delete(), isTrue);
      final after = await api.file(rkey: file.rkey);
      expect(after.value?.deletedAt, isNotNull);
    });
  });
}
