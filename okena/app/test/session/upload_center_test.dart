import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_app/src/session/upload_center.dart';
import 'package:okena_core/okena_core.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'okena-upload-center-',
    );
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('reports progress, succeeds, and notifies listeners', () async {
    final filePath = '${temporaryDirectory.path}/document.pdf';
    await File(filePath)
        .writeAsBytes(List<int>.generate(2500, (index) => index % 256));

    final api = FakeTainaApi(delay: Duration.zero);
    final gateway = _TestGateway(api);
    final center = UploadCenter(gateway: gateway);
    final notifications = <UploadState>[];
    center.addListener(() => notifications.add(center.state));
    addTearDown(center.dispose);

    final request = UploadRequest(
      path: filePath,
      name: 'document.pdf',
      mime: 'application/pdf',
      folderRkey: '3kx2n8pqrv5w2',
      folderName: 'Atas',
    );

    final result = await center.start(request);

    expect(result, isA<UploadFinished>());
    final completed = (result as UploadFinished).result;
    expect(completed.value, isNotNull);
    expect(completed.value!.folder, request.folderRkey);
    expect(completed.value!.size, 2500);
    expect(gateway.screenCalls, 1);
    expect(center.state, isA<UploadSucceeded>());
    expect(center.isUploading, isFalse);

    final progress = notifications.whereType<UploadUploading>().toList();
    expect(progress, isNotEmpty);
    expect(progress.first.totalBytes, 0);
    expect(progress.last.sentBytes, 2500);
    expect(progress.last.totalBytes, 2500);
    expect(progress.last.progressFraction, 1);
    expect(progress.last.progressTitle, 'Enviando document.pdf');
    expect(progress.last.progressDetail, 'Guardando na casa. 2,4 KB de 2,4 KB');
    expect(
      progress.last.progressHelp,
      'Você pode continuar usando o app enquanto envia.',
    );
    expect(notifications.first, isA<UploadUploading>());
    expect(notifications.last, isA<UploadSucceeded>());
  });

  test('keeps failure retryable and retries the same request', () async {
    var calls = 0;
    final api = _UploadApi(
      onUpload:
          ({
            required filePath,
            required name,
            required mime,
            folderRkey,
            progress,
          }) async {
            if (calls++ == 0) return const Err(NetworkError('offline'));
            return FakeTainaApi(delay: Duration.zero).upload(
              filePath: filePath,
              name: name,
              mime: mime,
              folderRkey: folderRkey,
              progress: progress,
            );
          },
    );
    final gateway = _TestGateway(api);
    final center = UploadCenter(gateway: gateway);
    addTearDown(center.dispose);
    const request = UploadRequest(
      path: '/missing/document.pdf',
      name: 'document.pdf',
      mime: 'application/pdf',
      folderRkey: '3kx2n8pqrv5w2',
      folderName: 'Atas',
    );

    final first = await center.start(request);

    expect(first, isA<UploadFinished>());
    expect((first as UploadFinished).result.error, isA<NetworkError>());
    expect(center.state, isA<UploadFailed>());
    expect(center.canRetry, isTrue);
    expect((center.state as UploadFailed).request, request);

    final retry = await center.retry();

    expect(retry, isA<UploadFinished>());
    expect((retry as UploadFinished).result.value, isNotNull);
    expect(api.uploadCalls, 2);
    expect(gateway.screenCalls, 2);
    expect(center.state, isA<UploadSucceeded>());
    expect(center.canRetry, isFalse);

    center.clear();
    expect(center.state, isA<UploadIdle>());
    expect(
      await center.retry(),
      isA<UploadRejected>().having(
        (result) => result.reason,
        'reason',
        UploadRejection.noRetryableFailure,
      ),
    );
  });

  test(
    'rejects a concurrent start without interrupting the active upload',
    () async {
      final completion = Completer<TainaResult<FileRecord>>();
      final api = _UploadApi(
        onUpload:
            ({
              required filePath,
              required name,
              required mime,
              folderRkey,
              progress,
            }) {
              progress?.call(20, 100);
              return completion.future;
            },
      );
      final center = UploadCenter(gateway: _TestGateway(api));
      addTearDown(center.dispose);
      const firstRequest = UploadRequest(
        path: '/first',
        name: 'first.jpg',
        mime: 'image/jpeg',
      );
      const secondRequest = UploadRequest(
        path: '/second',
        name: 'second.jpg',
        mime: 'image/jpeg',
      );

      final active = center.start(firstRequest);
      expect(center.state, isA<UploadUploading>());
      expect(center.isUploading, isTrue);

      final rejected = await center.start(secondRequest);

      expect(rejected, isA<UploadRejected>());
      expect((rejected as UploadRejected).reason, UploadRejection.busy);
      expect((center.state as UploadUploading).request, firstRequest);
      center.clear();
      expect(center.state, isA<UploadUploading>());

      completion.complete(Ok(_uploadedFile));
      expect(await active, isA<UploadFinished>());
      expect(center.state, isA<UploadSucceeded>());
    },
  );

  test(
    'screens unauthorized and forbidden upload failures through the gateway',
    () async {
      final errors = <TainaError>[
        const ApiError(
          code: 'unauthorized',
          status: 401,
          serverMessage: 'Entre de novo.',
        ),
        const ApiError(
          code: 'forbidden',
          status: 403,
          serverMessage: 'Sem acesso.',
        ),
      ];
      var errorIndex = 0;
      final api = _UploadApi(
        onUpload: ({
          required filePath,
          required name,
          required mime,
          folderRkey,
          progress,
        }) async => Err<FileRecord>(errors[errorIndex++]),
      );
      final gateway = _TestGateway(api);
      final center = UploadCenter(gateway: gateway);
      addTearDown(center.dispose);

      for (final error in errors) {
        final result = await center.start(
          const UploadRequest(
            path: '/document.pdf',
            name: 'document.pdf',
            mime: 'application/pdf',
          ),
        );

        expect((result as UploadFinished).result.error, error);
        expect((center.state as UploadFailed).error, error);
      }

      expect(gateway.screenCalls, 2);
      expect(gateway.screenedErrors, errors);
    },
  );
}

final class _UploadApi implements TainaApi {
  _UploadApi({required this.onUpload});

  final _UploadHandler onUpload;
  var uploadCalls = 0;

  @override
  Future<TainaResult<FileRecord>> upload({
    required String filePath,
    required String name,
    required String mime,
    String? folderRkey,
    UploadProgress? progress,
  }) {
    uploadCalls += 1;
    return onUpload(
      filePath: filePath,
      name: name,
      mime: mime,
      folderRkey: folderRkey,
      progress: progress,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not used in this test',
  );
}

typedef _UploadHandler = Future<TainaResult<FileRecord>> Function({
  required String filePath,
  required String name,
  required String mime,
  String? folderRkey,
  UploadProgress? progress,
});

final class _TestGateway implements SessionGateway {
  _TestGateway(this.api) : thumbnails = ThumbnailStore(api: api);

  @override
  Me? get identity => null;

  @override
  final TainaApi api;

  @override
  final ThumbnailStore thumbnails;

  var screenCalls = 0;
  final screenedErrors = <TainaError?>[];

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async {
    screenCalls += 1;
    screenedErrors.add(outcome.error);
    return outcome;
  }
}

const _uploadedFile = FileRecord(
  rkey: 'file-1',
  cid: 'cid-1',
  blobCid: 'blob-1',
  sha256: 'hash-1',
  name: 'uploaded.pdf',
  mime: 'application/pdf',
  size: 20,
  zona: Zona.casa,
  folder: null,
  takenAt: null,
  width: null,
  height: null,
  rendition: Rendition.none,
  deletedAt: null,
  createdAt: '2026-11-20T00:00:00Z',
  updatedAt: '2026-11-20T00:00:00Z',
);
