import 'dart:convert';
import 'dart:io';

import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/stub_transport.dart';

Future<(LiveTainaApi, StubTransport)> signedInApi(
  Future<TainaResult<HttpResponse>> Function(TransportCall call) answer,
) async {
  final stub = StubTransport(answer);
  final store = SessionStore(storage: InMemorySessionStorage());
  await store.signIn(fixturedSession());
  final api = LiveTainaApi(
    transport: stub,
    host: InMemoryHostStore(boxAddress()),
    session: store,
  );
  return (api, stub);
}

ApiError apiErrorOf(TainaResult<Object?> result) {
  final error = result.error;
  expect(error, isA<ApiError>());
  return error as ApiError;
}

void main() {
  group('request building', () {
    test('build appends to the base path', () {
      final request = LiveTainaApi.build(
        base: Uri.parse('https://box/painel/'),
        path: 'instance',
      ).value!;
      expect(request.url.toString(), 'https://box/painel/api/v1/instance');
    });

    test('without a saved address the caller goes back to setup', () async {
      final api = LiveTainaApi(
        transport: StubTransport(
          (_) async => Ok(httpResponse(status: 200, body: instanceJson)),
        ),
        host: InMemoryHostStore(),
        session: SessionStore(storage: InMemorySessionStorage()),
      );
      expect(
        (await api.instance()).error,
        const InvalidAddressError(AddressProblem.empty),
      );
    });

    test('an authenticated call without a session is not signed in', () async {
      var requests = 0;
      final api = LiveTainaApi(
        transport: StubTransport((_) async {
          requests += 1;
          return Ok(httpResponse(status: 200, body: '{}'));
        }),
        host: InMemoryHostStore(boxAddress()),
        session: SessionStore(storage: InMemorySessionStorage()),
      );
      expect((await api.me()).error, const NotSignedInError());
      expect(requests, 0);
    });

    test('build produces the path, accept and no token', () {
      final request = LiveTainaApi.build(
        base: Uri.parse('https://box'),
        path: 'instance',
      ).value!;
      expect(request.url.toString(), 'https://box/api/v1/instance');
      expect(request.headers['Authorization'], isNull);
      expect(request.headers['Accept'], 'application/json');
    });

    test('build encodes only the given query keys', () {
      final full = LiveTainaApi.build(
        base: Uri.parse('https://box'),
        path: 'contents',
        query: const {
          'folder': '3kx2n8pqrv5w2',
          'limit': '100',
          'cursor': 'abc',
          'sort': 'date_desc',
        },
      ).value!;
      expect(
        full.url.query,
        'cursor=abc&folder=3kx2n8pqrv5w2&limit=100&sort=date_desc',
      );

      final bare = LiveTainaApi.build(
        base: Uri.parse('https://box'),
        path: 'contents',
        query: const {
          'folder': null,
          'limit': null,
          'cursor': null,
          'sort': null,
        },
      ).value!;
      expect(bare.url.toString(), 'https://box/api/v1/contents');
      expect(bare.url.query, isEmpty);
    });

    test('the conditional cache key carries the session', () {
      final trash = Uri.parse('https://box/api/v1/trash');
      expect(
        LiveTainaApi.cacheKey(trash, 'tnd_a'),
        isNot(LiveTainaApi.cacheKey(trash, 'tnd_b')),
      );
      expect(
        LiveTainaApi.cacheKey(trash, 'tnd_a'),
        LiveTainaApi.cacheKey(trash, 'tnd_a'),
      );
      expect(
        LiveTainaApi.cacheKey(trash, 'tnd_a'),
        isNot(
          LiveTainaApi.cacheKey(
            Uri.parse('https://box/api/v1/photos'),
            'tnd_a',
          ),
        ),
      );
    });
  });

  group('instance and session', () {
    test('instance builds the URL, sends no token and decodes', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: instanceJson)),
      );

      final instance = (await api.instance()).value!;
      expect(instance.bootstrapped, isTrue);
      expect(instance.tekoa?.name, 'Tekoa Sapukai');
      expect(instance.version, '0.6.0');

      final request = stub.requests.single;
      expect(request.url.toString(), 'https://box/api/v1/instance');
      expect(request.headers['Authorization'], isNull);
    });

    test('createSession posts the JSON and returns the raw token', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 201, body: sessionJson)),
      );

      final session = (await api.createSession(
        username: 'ana',
        password: 'segredo',
        deviceName: 'iPhone da Ana',
      )).value!;
      expect(session.token, 'tnd_abcdef0123456789abcdef0123456789');
      expect(session.me.username, 'ana');
      expect(session.tekoa.name, 'Tekoa Sapukai');

      final request = stub.requests.single;
      expect(request.method, 'POST');
      expect(request.headers['Content-Type'], 'application/json');
      final body = bodyOf(request);
      expect(body, contains('"username":"ana"'));
      expect(body, contains('"password":"segredo"'));
      expect(body, contains('"device_name":"iPhone da Ana"'));
    });

    test('invite status probes the path without the bearer', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: tokenStatusJson)),
      );

      final status = (await api.inviteStatus(token: inviteToken)).value!;
      expect(status.valid, isTrue);

      final request = stub.requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://box/api/v1/invites/$inviteToken');
      expect(request.headers['Authorization'], isNull);
    });

    test('accept invite posts the JSON and no bearer', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 201, body: sessionJson)),
      );

      await api.acceptInvite(
        token: inviteToken,
        username: 'joao',
        password: 'segredo',
        displayName: 'João Mendes',
        deviceName: 'iPhone do João',
      );

      final request = stub.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://box/api/v1/invites/$inviteToken/accept',
      );
      expect(request.headers['Authorization'], isNull);
      final body = bodyOf(request);
      expect(body, contains('"username":"joao"'));
      expect(body, contains('"display_name":"João Mendes"'));
      expect(body, isNot(contains('confirmation')));
    });

    test('accept invite omits the display name when there is none', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 201, body: sessionJson)),
      );
      await api.acceptInvite(
        token: inviteToken,
        username: 'joao',
        password: 'segredo',
        deviceName: 'iPhone do João',
      );
      final body = bodyOf(stub.requests.single);
      expect(body, contains('"username":"joao"'));
      expect(body, isNot(contains('display_name')));
    });

    test('reset status and reset password use the public path', () async {
      final (api, stub) = await signedInApi((call) async {
        if (call.request.method == 'POST') {
          return Ok(httpResponse(status: 201, body: sessionJson));
        }
        return Ok(httpResponse(status: 200, body: tokenStatusJson));
      });

      expect((await api.resetStatus(token: inviteToken)).value!.valid, isTrue);
      await api.resetPassword(
        token: inviteToken,
        password: 'segredo',
        deviceName: 'iPhone da Joana',
      );

      final (statusRequest, resetRequest) = (
        stub.requests[0],
        stub.requests[1],
      );
      expect(
        statusRequest.url.toString(),
        'https://box/api/v1/password-resets/$inviteToken',
      );
      expect(resetRequest.method, 'POST');
      expect(resetRequest.headers['Authorization'], isNull);
      final body = bodyOf(resetRequest);
      expect(body, contains('"password":"segredo"'));
      expect(body, contains('"device_name":"iPhone da Joana"'));
      expect(body, isNot(contains('username')));
      expect(body, isNot(contains('confirmation')));
    });

    test('the 204 of revoke session is success', () async {
      final (api, _) = await signedInApi(
        (_) async => Ok(httpResponse(status: 204)),
      );
      expect((await api.revokeSession()).isSuccess, isTrue);
    });

    test('an authenticated call carries the bearer token', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: '{}')),
      );
      await api.me();
      expect(
        stub.requests.single.headers['Authorization'],
        'Bearer tnd_abcdef0123456789abcdef0123456789',
      );
    });

    test('devices decode the page and return the list', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: devicesPageJson)),
      );
      final devices = (await api.devices()).value!;
      expect(devices.map((device) => device.name), ['iPhone da Ana']);
      expect(devices.first.revokedAt, isNull);
      expect(stub.requests.single.url.toString(), 'https://box/api/v1/devices');
    });

    test('revoke device sends delete to the device path', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 204)),
      );
      expect((await api.revokeDevice(id: 'devp2xw5m8q3')).isSuccess, isTrue);
      final request = stub.requests.single;
      expect(request.method, 'DELETE');
      expect(request.url.toString(), 'https://box/api/v1/devices/devp2xw5m8q3');
    });
  });

  group('folders and files', () {
    test('folder contents queries only what is given', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: contentsJson)),
      );

      await api.folderContents(
        folderRkey: '3kx2n8pqrv5w2',
        limit: 100,
        cursor: 'abc',
        sort: const Sort(key: SortKey.date, direction: SortDirection.desc),
      );
      await api.folderContents();

      expect(
        stub.requests[0].url.query,
        'cursor=abc&folder=3kx2n8pqrv5w2&limit=100&sort=date_desc',
      );
      expect(stub.requests[1].url.toString(), 'https://box/api/v1/contents');
    });

    test('folder fetch, update and move hit their contracts', () async {
      final (api, stub) = await signedInApi((call) async {
        if (call.request.method == 'PATCH') {
          return Ok(httpResponse(status: 200, body: updatedFolderJson));
        }
        return Ok(httpResponse(status: 200, body: folderJson));
      });

      final folder = (await api.folder(rkey: '3kx2n8pqrv5w2')).value!;
      expect(folder.name, 'Documentos da assembleia');

      final updated = (await api.updateFolder(
        rkey: '3kx2n8pqrv5w2',
        name: 'Atas publicadas',
        zona: Zona.praca,
      )).value!;
      expect(updated.name, 'Atas publicadas');
      expect(updated.zona, Zona.praca);

      await api.moveFolder(rkey: '3kx2n8pqrv5w2', parentRkey: '3kz9t4mqc1h7d');
      await api.moveFolder(rkey: '3kx2n8pqrv5w2');

      expect(stub.requests[0].method, 'GET');
      final patch = stub.requests[1];
      expect(patch.method, 'PATCH');
      expect(bodyOf(patch), contains('"name":"Atas publicadas"'));
      expect(bodyOf(patch), contains('"zona":"praca"'));
      final move = stub.requests[2];
      expect(move.method, 'POST');
      expect(
        move.url.toString(),
        'https://box/api/v1/folders/3kx2n8pqrv5w2/move',
      );
      expect(bodyOf(move), contains('"parent_rkey":"3kz9t4mqc1h7d"'));
      expect(bodyOf(stub.requests[3]), '{}');
    });

    test('createFolder posts the name and parent', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: folderJson)),
      );
      await api.createFolder(name: 'Atas', parentRkey: '3kx2n8pqrv5w2');
      expect(stub.requests.single.url.toString(), 'https://box/api/v1/folders');
      expect(bodyOf(stub.requests.single), contains('"parent_rkey"'));
    });

    test('updateFile omits the fields it was not given', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: fileJson)),
      );
      await api.updateFile(rkey: '3n4b9uxrw6a3', name: 'ata renomeada.pdf');
      final request = stub.requests.single;
      expect(request.method, 'PATCH');
      expect(bodyOf(request), contains('"name":"ata renomeada.pdf"'));
      expect(bodyOf(request), isNot(contains('zona')));
    });

    test('moveFile uses the folder wire key', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: fileJson)),
      );
      await api.moveFile(rkey: '3n4b9uxrw6a3', folderRkey: '3kx2n8pqrv5w2');
      final request = stub.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://box/api/v1/files/3n4b9uxrw6a3/move',
      );
      expect(bodyOf(request), contains('"folder":"3kx2n8pqrv5w2"'));
      expect(bodyOf(request), isNot(contains('folder_rkey')));
    });

    test('the deletes send DELETE and read the 204', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 204)),
      );
      expect((await api.deleteFolder(rkey: '3kx2n8pqrv5w2')).isSuccess, isTrue);
      expect((await api.deleteFile(rkey: '3n4b9uxrw6a3')).isSuccess, isTrue);
      expect(
        stub.requests.every((request) => request.method == 'DELETE'),
        isTrue,
      );
      expect(
        stub.requests[0].url.toString(),
        'https://box/api/v1/folders/3kx2n8pqrv5w2',
      );
      expect(
        stub.requests[1].url.toString(),
        'https://box/api/v1/files/3n4b9uxrw6a3',
      );
    });

    test('recent queries only the limit', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: filePageJson)),
      );
      await api.recent(limit: 5);
      await api.recent();
      expect(stub.requests[0].url.query, 'limit=5');
      expect(stub.requests[1].url.query, isEmpty);
    });

    test('trash decodes the paginated envelope', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: filePageJson)),
      );
      final page = (await api.trash(limit: 10, cursor: '12')).value!;
      expect(page.items.map((file) => file.name), ['ata.pdf']);
      expect(page.nextCursor, '12');
      expect(stub.requests.single.url.query, 'cursor=12&limit=10');
    });

    test('photos query limit and cursor', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: filePageJson)),
      );
      await api.photos(limit: 50, cursor: 'abc');
      final request = stub.requests.single;
      expect(request.url.path, '/api/v1/photos');
      expect(request.url.query, 'cursor=abc&limit=50');
    });

    test('the timeline decodes days and queries the page', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: timelinePageJson)),
      );
      final page = (await api.photoTimeline(limit: 20)).value!;
      expect(page.items.map((group) => group.date), ['2026-06-21']);
      expect(page.items.first.photos.map((file) => file.name), [
        'Foto da quadra.jpg',
      ]);
      final request = stub.requests.single;
      expect(request.url.path, '/api/v1/photos/timeline');
      expect(request.url.query, 'limit=20');
    });

    test('restore posts to the trash path and decodes the file', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: fileJson)),
      );
      final file = (await api.restoreFile(rkey: '3n4b9uxrw6a3')).value!;
      expect(file.name, 'ata.pdf');
      final request = stub.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://box/api/v1/trash/3n4b9uxrw6a3/restore',
      );
    });

    test('the file decodes the photo fields', () async {
      final (api, _) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 200,
            body: '{"items":[$fotoJson,$pendingFotoJson],"next_cursor":null}',
          ),
        ),
      );
      final page = (await api.photos()).value!;
      final ready = page.items.first;
      expect(ready.takenAt, '2026-06-21T21:12:00Z');
      expect(ready.width, 4032);
      expect(ready.height, 3024);
      expect(ready.rendition, Rendition.ready);
      expect(page.items.last.rendition, Rendition.pending);
      expect(page.items.last.takenAt, isNull);
    });

    test('manifest walks by the rkey and queries the page', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 200,
            body: '{"items":[$fileJson],"next_cursor":null}',
          ),
        ),
      );
      final page = (await api.manifest(
        after: '3m2a8twqpv5z2',
        limit: 200,
      )).value!;
      expect(page.items.map((file) => file.sha256), [
        'aa11bb22cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66',
      ]);
      final request = stub.requests.single;
      expect(request.url.path, '/api/v1/files/manifest');
      expect(request.url.query, 'after=3m2a8twqpv5z2&limit=200');
    });

    test('members decode the page and the pending invite label', () async {
      const pending =
          '{"public_id":"avatk9x2m5qp7w","username":null,"display_name":null,'
          '"papel":"morador","activated_at":null,"deactivated_at":null,'
          '"created_at":"2026-10-13T09:00:00Z"}';
      final (api, stub) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 200,
            body: '{"items":[$anaJson,$pending],"next_cursor":null}',
          ),
        ),
      );
      final page = (await api.members()).value!;
      expect(page.items.map((ava) => ava.username), ['ana', null]);
      expect(page.items.first.papel, Papel.zelador);
      expect(page.items.last.label, 'Convite pendente');
      expect(stub.requests.single.url.toString(), 'https://box/api/v1/members');
    });
  });

  group('uploads and downloads', () {
    test('upload streams the body and cleans the temp file', () async {
      final source = File(
        '${Directory.systemTemp.path}/upload-source-${DateTime.now().microsecondsSinceEpoch}.bin',
      );
      await source.writeAsString('CONTEUDO-DO-ARQUIVO');
      addTearDown(() async {
        if (await source.exists()) await source.delete();
      });

      String? bodyFile;
      String? contentType;
      String? bodyText;
      final (api, _) = await signedInApi((call) async {
        expect(call.kind, CallKind.upload);
        bodyFile = call.filePath;
        contentType = call.request.headers['Content-Type'];
        bodyText = utf8.decode(File(call.filePath!).readAsBytesSync());
        return Ok(httpResponse(status: 201, body: fileJson));
      });

      final uploaded = (await api.upload(
        filePath: source.path,
        name: 'ata.pdf',
        mime: 'application/pdf',
        folderRkey: '3kx2n8pqrv5w2',
      )).value!;
      expect(uploaded.name, 'ata.pdf');

      expect(contentType, startsWith('multipart/form-data; boundary='));
      final boundary = contentType!.substring(
        'multipart/form-data; boundary='.length,
      );
      expect(bodyText, startsWith('--$boundary\r\n'));
      expect(
        bodyText,
        contains(
          'Content-Disposition: form-data; name="folder"\r\n\r\n'
          '3kx2n8pqrv5w2\r\n',
        ),
      );
      expect(bodyText, contains('; filename="ata.pdf"\r\n'));
      expect(bodyText, contains('Content-Type: application/pdf\r\n'));
      expect(bodyText, endsWith('CONTEUDO-DO-ARQUIVO\r\n--$boundary--\r\n'));

      expect(File(bodyFile!).existsSync(), isFalse);
    });

    test('upload still cleans the temp file when the server fails', () async {
      final source = File(
        '${Directory.systemTemp.path}/upload-source-${DateTime.now().microsecondsSinceEpoch}.bin',
      );
      await source.writeAsString('BYTES');
      addTearDown(() async {
        if (await source.exists()) await source.delete();
      });

      String? bodyFile;
      final (api, _) = await signedInApi((call) async {
        bodyFile = call.filePath;
        // The temp body file exists while the request is in flight.
        File(call.filePath!).deleteSync();
        return Ok(
          httpResponse(
            status: 409,
            body:
                '{"error":{"code":"storage_quota_exceeded",'
                '"message":"O cofre da comunidade encheu."}}',
          ),
        );
      });

      final error = apiErrorOf(
        await api.upload(
          filePath: source.path,
          name: 'ata.pdf',
          mime: 'application/pdf',
        ),
      );
      expect(error.isQuotaExceeded, isTrue);
      expect(bodyFile, isNotNull);
      expect(File(bodyFile!).existsSync(), isFalse);
    });

    test('download names the file from content disposition', () async {
      final stubFile = File(
        '${Directory.systemTemp.path}/stub-download-${DateTime.now().microsecondsSinceEpoch}',
      );
      await stubFile.writeAsString('BYTES-DO-RELATORIO');

      final (api, _) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 200,
            headers: const {
              'Content-Disposition':
                  'attachment; filename="relatorio anual.pdf"',
            },
            filePath: stubFile.path,
          ),
        ),
      );

      final path = (await api.download(rkey: '3m2a8twqpv5z2')).value!;
      expect(path.split('/').last, 'relatorio anual.pdf');
      expect(File(path).existsSync(), isTrue);
      expect(await File(path).readAsString(), 'BYTES-DO-RELATORIO');
      expect(stubFile.existsSync(), isFalse);
      addTearDown(() async {
        if (await File(path).exists()) await File(path).delete();
      });
    });

    test('download falls back to the rkey without a header', () async {
      final stubFile = File(
        '${Directory.systemTemp.path}/stub-download-${DateTime.now().microsecondsSinceEpoch}',
      );
      await stubFile.writeAsString('BYTES');

      final (api, _) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, filePath: stubFile.path)),
      );

      final path = (await api.download(rkey: '3m2a8twqpv5z2')).value!;
      expect(path.split('/').last, '3m2a8twqpv5z2');
      addTearDown(() async {
        if (await File(path).exists()) await File(path).delete();
      });
    });

    test('download strips path separators from the server name', () async {
      final stubFile = File(
        '${Directory.systemTemp.path}/stub-download-${DateTime.now().microsecondsSinceEpoch}',
      );
      await stubFile.writeAsString('BYTES');

      final (api, _) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 200,
            headers: const {
              'Content-Disposition': 'attachment; filename="../../../etc/motd"',
            },
            filePath: stubFile.path,
          ),
        ),
      );

      final path = (await api.download(rkey: '3m2a8twqpv5z2')).value!;
      expect(path, isNot(contains('/etc/')));
      expect(path.split('/').last, '......etcmotd');
      addTearDown(() async {
        if (await File(path).exists()) await File(path).delete();
      });
    });

    test('download keeps the accented name', () async {
      final stubFile = File(
        '${Directory.systemTemp.path}/stub-download-${DateTime.now().microsecondsSinceEpoch}',
      );
      await stubFile.writeAsString('BYTES');

      final (api, _) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 200,
            headers: const {
              'Content-Disposition':
                  'attachment; filename="ata da reuniao.pdf"; '
                  "filename*=UTF-8''ata%20da%20reuni%C3%A3o.pdf",
            },
            filePath: stubFile.path,
          ),
        ),
      );

      final path = (await api.download(rkey: '3m2a8twqpv5z2')).value!;
      expect(path.split('/').last, 'ata da reunião.pdf');
      addTearDown(() async {
        if (await File(path).exists()) await File(path).delete();
      });
    });

    test('the extended form wins over the plain parameter', () {
      final both = httpResponse(
        status: 200,
        headers: const {
          'Content-Disposition':
              'attachment; filename="Fotografia da praca.jpg"; '
              "filename*=UTF-8''Fotografia%20da%20pra%C3%A7a.jpg",
        },
      );
      expect(LiveTainaApi.attachmentFilename(both), 'Fotografia da praça.jpg');

      final extended = httpResponse(
        status: 200,
        headers: const {
          'Content-Disposition':
              "attachment; filename*=UTF-8''Reuni%C3%A3o%20de%20domingo.pdf",
        },
      );
      expect(
        LiveTainaApi.attachmentFilename(extended),
        'Reunião de domingo.pdf',
      );
    });

    test('the plain name answers when the extended form does not parse', () {
      final charset = httpResponse(
        status: 200,
        headers: const {
          'Content-Disposition':
              'attachment; filename="relatorio.pdf"; '
              "filename*=iso-8859-1''relat%F3rio.pdf",
        },
      );
      expect(LiveTainaApi.attachmentFilename(charset), 'relatorio.pdf');

      final broken = httpResponse(
        status: 200,
        headers: const {
          'Content-Disposition':
              'attachment; filename="relatorio.pdf"; filename*=UTF-8\'\'',
        },
      );
      expect(LiveTainaApi.attachmentFilename(broken), 'relatorio.pdf');

      final plain = httpResponse(
        status: 200,
        headers: const {
          'Content-Disposition': 'attachment; filename="relatorio anual.pdf"',
        },
      );
      expect(LiveTainaApi.attachmentFilename(plain), 'relatorio anual.pdf');

      expect(
        LiveTainaApi.attachmentFilename(httpResponse(status: 200)),
        isNull,
      );
    });

    test(
      'the thumbnail does not ask for a type the pipeline cannot negotiate',
      () async {
        final (api, stub) = await signedInApi(
          (_) async => Ok(httpResponse(status: 200)),
        );
        await api.thumbnail(rkey: '3n4b9uxrw6a3', size: ThumbnailSize.sm);
        final request = stub.requests.single;
        expect(request.headers['Accept'], '*/*');
        expect(
          request.url.toString(),
          'https://box/api/v1/files/3n4b9uxrw6a3/thumbnail/sm',
        );
      },
    );

    test(
      'a thumbnail without a rendition is an API error with the status',
      () async {
        final (api, _) = await signedInApi(
          (_) async => Ok(httpResponse(status: 404)),
        );
        final error = apiErrorOf(
          await api.thumbnail(rkey: '3n4b9uxrw6a3', size: ThumbnailSize.sm),
        );
        expect(error.status, 404);
      },
    );
  });

  group('error envelopes', () {
    test('the unauthorized envelope becomes the typed error', () async {
      final (api, _) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 401,
            body:
                '{"error":{"code":"not_authenticated",'
                '"message":"Entre na sua conta para continuar."}}',
          ),
        ),
      );
      final error = apiErrorOf(await api.me());
      expect(error.code, 'not_authenticated');
      expect(error.isUnauthorized, isTrue);
      expect(error.serverMessage, 'Entre na sua conta para continuar.');
      expect(error.details, isEmpty);
    });

    test('the validation envelope keeps the field details', () async {
      final (api, _) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 422,
            body:
                '{"error":{"code":"validation_failed",'
                '"message":"Não foi possível criar a pasta.",'
                '"details":{"nome":["não pode ficar em branco"]}}}',
          ),
        ),
      );
      final error = apiErrorOf(await api.createFolder(name: ''));
      expect(error.isValidationFailed, isTrue);
      expect(error.details['nome'], ['não pode ficar em branco']);
      expect(error.fieldMessages, ['não pode ficar em branco']);
    });

    test(
      'a non-JSON error body becomes internal_error without leaking',
      () async {
        final (api, _) = await signedInApi(
          (_) async => Ok(
            httpResponse(status: 500, body: '<html>boom tnd_secret</html>'),
          ),
        );
        final error = apiErrorOf(await api.me());
        expect(error.code, 'internal_error');
        expect(error.status, 500);
        expect(error.message, isNot(contains('boom')));
        expect(error.message, isNot(contains('tnd_secret')));
      },
    );

    test('a transport failure is network', () async {
      final (api, _) = await signedInApi(
        (_) async => const Err(NetworkError('offline')),
      );
      expect((await api.me()).error, const NetworkError('offline'));
    });
  });

  group('access, grants and people', () {
    test('mural keeps the payload whole', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: muralPageJson)),
      );
      final page = (await api.mural()).value!;
      expect(page.items.length, 2);
      final payload = page.items.first.payload;
      expect(payload['name'], const JsonString('Foto da quadra.jpg'));
      expect(payload['zona'], const JsonString('praca'));
      expect(payload['size'], const JsonInt(1204331));
      expect(payload['featured'], const JsonBool(true));
      expect(payload['caption'], const JsonNull());
      expect(
        payload['tags'],
        const JsonArray([JsonString('festa'), JsonString('quadra')]),
      );
      expect(page.items.last.prev, isNull);
      expect(stub.requests.single.url.query, isEmpty);
    });

    test('accessTarget decodes the owner', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: accessTargetJson)),
      );
      final target = (await api.accessTarget(fileRkey: '3n4b9uxrw6a3')).value!;
      expect(target.owner.username, 'joana');
      expect(target.rkey, '3n4b9uxrw6a3');
      expect(
        stub.requests.single.url.toString(),
        'https://box/api/v1/files/3n4b9uxrw6a3/access-target',
      );
    });

    test('requestAccess posts motivo and decodes the pedido', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 201, body: pedidoJson)),
      );
      final pedido = (await api.requestAccess(
        fileRkey: '3n4b9uxrw6a3',
        motivo: 'Para a reuniao.',
      )).value!;
      expect(pedido.status, PedidoStatus.pendente);
      expect(pedido.pedinte?.username, 'joana');
      final request = stub.requests.single;
      expect(request.method, 'POST');
      expect(bodyOf(request), contains('"motivo":"Para a reuniao."'));
    });

    test('access requests and my requests decode pedido pages', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: pedidosPageJson)),
      );
      final received = (await api.accessRequests()).value!;
      expect(received.items.first.publicId, 'ped3xk9mq2v7w4');
      final sent = (await api.myRequests()).value!;
      expect(sent.nextCursor, isNull);
      expect(
        stub.requests[0].url.toString(),
        'https://box/api/v1/access-requests',
      );
      expect(stub.requests[1].url.toString(), 'https://box/api/v1/my-requests');
    });

    test('approve decodes the concessao and deny the decided pedido', () async {
      final (api, stub) = await signedInApi((call) async {
        if (call.request.url.path.endsWith('/deny')) {
          return Ok(httpResponse(status: 200, body: deniedPedidoJson));
        }
        return Ok(httpResponse(status: 200, body: concessaoJson));
      });

      final concessao = (await api.approveRequest(id: 'ped3xk9mq2v7w4')).value!;
      expect(concessao.leitor?.username, 'joana');
      expect(concessao.recurso, '3n4b9uxrw6a3');

      final denied = (await api.denyRequest(id: 'ped3xk9mq2v7w4')).value!;
      expect(denied.status, PedidoStatus.negado);
      expect(denied.decididoEm, '2026-10-14T12:00:00Z');

      expect(stub.requests[0].method, 'POST');
      expect(
        stub.requests[0].url.toString(),
        'https://box/api/v1/access-requests/ped3xk9mq2v7w4/approve',
      );
      expect(
        stub.requests[1].url.toString(),
        'https://box/api/v1/access-requests/ped3xk9mq2v7w4/deny',
      );
    });

    test('grants query the role and decode the page', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 200,
            body: '{"items":[$concessaoJson],"next_cursor":null}',
          ),
        ),
      );
      final given = (await api.grants(role: GrantRole.owner)).value!;
      expect(given.items.first.leitor?.username, 'joana');
      expect(given.items.first.revogadaEm, isNull);
      await api.grants(role: GrantRole.reader);
      expect(stub.requests[0].url.query, 'role=owner');
      expect(stub.requests[1].url.query, 'role=reader');
    });

    test('revokeGrant sends delete and reads the conflict', () async {
      var calls = 0;
      final (api, stub) = await signedInApi((call) async {
        calls += 1;
        if (calls == 1) {
          return Ok(httpResponse(status: 204));
        }
        return Ok(
          httpResponse(
            status: 409,
            body:
                '{"error":{"code":"invalid_status",'
                '"message":"Este acesso já foi revogado."}}',
          ),
        );
      });

      expect((await api.revokeGrant(id: 'con4kx9mq2v7w5')).isSuccess, isTrue);
      expect(
        stub.requests[0].url.toString(),
        'https://box/api/v1/grants/con4kx9mq2v7w5',
      );

      // The same call against a conflict envelope keeps the code and status.
      final error = apiErrorOf(await api.revokeGrant(id: 'con4kx9mq2v7w5'));
      expect(error.isConflict, isTrue);
      expect(error.code, 'invalid_status');
    });

    test(
      'updatePassword posts both passwords and reads the wrong current',
      () async {
        final (api, stub) = await signedInApi((call) async {
          if (bodyOf(call.request).contains('"current_password":"segredo"')) {
            return Ok(httpResponse(status: 200, body: '{"ok":true}'));
          }
          return Ok(
            httpResponse(
              status: 403,
              body:
                  '{"error":{"code":"invalid_credentials",'
                  '"message":"A senha atual não confere."}}',
            ),
          );
        });

        expect(
          (await api.updatePassword(
            current: 'segredo',
            newPassword: 'novo-segredo',
          )).isSuccess,
          isTrue,
        );
        final request = stub.requests.first;
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://box/api/v1/session/password');
        expect(
          request.headers['Authorization'],
          'Bearer tnd_abcdef0123456789abcdef0123456789',
        );
        expect(bodyOf(request), contains('"current_password":"segredo"'));
        expect(bodyOf(request), contains('"new_password":"novo-segredo"'));

        final error = apiErrorOf(
          await api.updatePassword(
            current: 'errada',
            newPassword: 'novo-segredo',
          ),
        );
        expect(error.code, 'invalid_credentials');
        expect(error.status, 403);
        expect(error.isUnauthorized, isFalse);
      },
    );

    test('inviteMember posts the papel and reads the once link', () async {
      final inviteJson =
          '{"ava":{"public_id":"avatk9x2m5qp7w","username":null,'
          '"display_name":null,"papel":"morador","activated_at":null,'
          '"deactivated_at":null,"created_at":"2026-10-14T08:00:00Z"},'
          '"token":"tk9x2m5qp7w4v8",'
          '"invite_url":"taina://convite/tk9x2m5qp7w4v8?host=taina.sapukai.ts.net"}';
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 201, body: inviteJson)),
      );
      final invite = (await api.inviteMember(papel: Papel.morador)).value!;
      expect(invite.token, 'tk9x2m5qp7w4v8');
      expect(invite.inviteUrl, startsWith('taina://convite/'));
      expect(invite.ava.username, isNull);
      final request = stub.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://box/api/v1/members');
      expect(bodyOf(request), contains('"papel":"morador"'));
    });

    test('updateMember patches the papel', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: anaJson)),
      );
      final updated = (await api.updateMember(
        id: 'avaq7r2m5xk9p1',
        papel: Papel.zelador,
      )).value!;
      expect(updated.papel, Papel.zelador);
      final request = stub.requests.single;
      expect(request.method, 'PATCH');
      expect(bodyOf(request), contains('"papel":"zelador"'));
    });

    test('deactivate, reactivate, revoke invite and reset link hit their paths', () async {
      const resetLinkJson =
          '{"ava":$joanaJson,"token":"tk9x2m5qp7w4v8",'
          '"reset_url":"taina://redefinir/tk9x2m5qp7w4v8?host=taina.sapukai.ts.net"}';
      final stub = StubTransport((call) async {
        final path = call.request.url.path;
        if (path.endsWith('/reset-link')) {
          return Ok(httpResponse(status: 201, body: resetLinkJson));
        }
        if (path.endsWith('/reactivate')) {
          return Ok(httpResponse(status: 200, body: joanaJson));
        }
        return Ok(httpResponse(status: 204));
      });
      final store = SessionStore(storage: InMemorySessionStorage());
      await store.signIn(fixturedSession());
      final api = LiveTainaApi(
        transport: stub,
        host: InMemoryHostStore(boxAddress()),
        session: store,
      );

      expect(
        (await api.deactivateMember(id: 'avaq7r2m5xk9p1')).isSuccess,
        isTrue,
      );
      expect(
        (await api.reactivateMember(id: 'avaq7r2m5xk9p1')).isSuccess,
        isTrue,
      );
      expect((await api.revokeInvite(id: 'avatk9x2m5qp7w')).isSuccess, isTrue);
      final link = (await api.memberResetLink(id: 'avaq7r2m5xk9p1')).value!;
      expect(link.resetUrl, startsWith('taina://redefinir/'));

      expect(stub.requests[0].method, 'DELETE');
      expect(stub.requests[0].url.path, '/api/v1/members/avaq7r2m5xk9p1');
      expect(
        stub.requests[1].url.path,
        '/api/v1/members/avaq7r2m5xk9p1/reactivate',
      );
      expect(
        stub.requests[2].url.path,
        '/api/v1/members/avatk9x2m5qp7w/invite',
      );
      expect(
        stub.requests[3].url.path,
        '/api/v1/members/avaq7r2m5xk9p1/reset-link',
      );
      expect(stub.requests[3].method, 'POST');
    });

    test('setQuota patches the bytes and triggerBackup posts to saude', () async {
      const tekoaJson =
          '{"public_id":"tekp2xw5m8q3","name":"Tekoa Sapukai",'
          '"domain":"taina.sapukai.ts.net","storage_quota_bytes":536870912000,'
          '"storage_used_bytes":1832110000,'
          '"created_at":"2026-02-01T09:00:00Z"}';
      final (api, stub) = await signedInApi((call) async {
        if (call.request.method == 'PATCH') {
          return Ok(httpResponse(status: 200, body: tekoaJson));
        }
        return Ok(httpResponse(status: 202, body: '{"scheduled":true}'));
      });

      final tekoa = (await api.setQuota(bytes: 536870912000)).value!;
      expect(tekoa.storageQuotaBytes, 536870912000);
      expect((await api.triggerBackup()).isSuccess, isTrue);

      final quota = stub.requests[0];
      expect(quota.method, 'PATCH');
      expect(quota.url.toString(), 'https://box/api/v1/storage/quota');
      expect(bodyOf(quota), contains('"quota_bytes":536870912000'));
      expect(
        stub.requests[1].url.toString(),
        'https://box/api/v1/saude/backup',
      );
    });

    test('storage and saude decode their panels', () async {
      final (api, stub) = await signedInApi((call) async {
        if (call.request.url.path.endsWith('/saude')) {
          return Ok(httpResponse(status: 200, body: saudeJson));
        }
        return Ok(httpResponse(status: 200, body: storageJson));
      });

      final stats = (await api.storage()).value!;
      expect(stats.usedBytes, 1832110000);
      expect(stats.quotaBytes, 268435456000);
      expect(stats.byKind.photos, 1100000000);
      expect(stats.byKind.documents, 132110000);
      expect(stats.files, 42);
      expect(stats.trash.count, 3);

      final saude = (await api.saude()).value!;
      expect(saude.jobs['backups'], 1);
      expect(saude.backup.at, '2026-10-14T03:00:00Z');
      expect(saude.storage.files, 42);
      expect(stub.requests[1].url.toString(), 'https://box/api/v1/saude');
    });

    test('the batch posts the op and reads the partial failure', () async {
      final body =
          '{"results":['
          '{"rkey":"3m2a8twqpv5z2","ok":true,"file":$fileJson},'
          '{"rkey":"3m5c9vxyq2b7t","ok":false,"error":"not_owner"}'
          ']}';
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: body)),
      );

      final outcomes = (await api.batch(
        op: BatchOp.trash,
        ids: const ['3m2a8twqpv5z2', '3m5c9vxyq2b7t'],
      )).value!;
      expect(outcomes.length, 2);
      expect(outcomes[0].ok, isTrue);
      expect(outcomes[0].file?.name, 'ata.pdf');
      expect(outcomes[1].ok, isFalse);
      expect(outcomes[1].error, 'not_owner');

      final request = stub.requests.single;
      expect(request.method, 'POST');
      expect(bodyOf(request), contains('"op":"trash"'));
      expect(
        bodyOf(request),
        contains('"ids":["3m2a8twqpv5z2","3m5c9vxyq2b7t"]'),
      );
    });

    test('batch move carries the folder and omits it at the root', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(httpResponse(status: 200, body: '{"results":[]}')),
      );
      await api.batch(
        op: BatchOp.move,
        ids: const ['3m2a8twqpv5z2'],
        folderRkey: '3kx2n8pqrv5w2',
      );
      await api.batch(op: BatchOp.move, ids: const ['3m2a8twqpv5z2']);
      expect(bodyOf(stub.requests[0]), contains('"folder":"3kx2n8pqrv5w2"'));
      expect(bodyOf(stub.requests[1]), isNot(contains('folder')));
    });
  });

  group('conditional reads', () {
    test('a conditional read sends the tag it kept', () async {
      final (api, stub) = await signedInApi(
        (_) async => Ok(
          httpResponse(
            status: 200,
            body: filePageJson,
            headers: const {'ETag': 'W/"5-1760000000"'},
          ),
        ),
      );

      await api.trash();
      await api.trash();

      expect(stub.requests.length, 2);
      expect(stub.requests[0].headers['If-None-Match'], isNull);
      expect(stub.requests[1].headers['If-None-Match'], 'W/"5-1760000000"');
    });

    test('a 304 answers the page it kept', () async {
      final (api, _) = await signedInApi((call) async {
        if (call.request.headers['If-None-Match'] != null) {
          return Ok(httpResponse(status: 304));
        }
        return Ok(
          httpResponse(
            status: 200,
            body: filePageJson,
            headers: const {'ETag': 'W/"5-1760000000"'},
          ),
        );
      });

      final first = (await api.trash()).value!;
      final second = (await api.trash()).value!;
      expect(
        second.items.map((file) => file.rkey),
        first.items.map((file) => file.rkey),
      );
      expect(second.nextCursor, first.nextCursor);
    });

    test('a new tag replaces the kept one', () async {
      var counter = 0;
      final (api, stub) = await signedInApi((_) async {
        counter += 1;
        final tag = counter == 1 ? 'W/"5-1"' : 'W/"7-2"';
        return Ok(
          httpResponse(status: 200, body: filePageJson, headers: {'ETag': tag}),
        );
      });

      await api.trash();
      await api.trash();
      await api.trash();

      expect(stub.requests.length, 3);
      expect(stub.requests[1].headers['If-None-Match'], 'W/"5-1"');
      expect(stub.requests[2].headers['If-None-Match'], 'W/"7-2"');
    });

    test('a 200 without a tag drops the kept entry', () async {
      final (api, stub) = await signedInApi((call) async {
        if (call.request.headers['If-None-Match'] != null) {
          return Ok(httpResponse(status: 200, body: filePageJson));
        }
        return Ok(
          httpResponse(
            status: 200,
            body: filePageJson,
            headers: const {'ETag': 'W/"5-1760000000"'},
          ),
        );
      });

      await api.trash();
      await api.trash();
      await api.trash();

      expect(stub.requests[1].headers['If-None-Match'], 'W/"5-1760000000"');
      expect(stub.requests[2].headers['If-None-Match'], isNull);
    });

    test('a 304 without a kept body is an invalid response', () async {
      final (api, _) = await signedInApi(
        (_) async => Ok(httpResponse(status: 304)),
      );
      expect((await api.trash()).error, isA<InvalidResponseError>());
    });
  });
}
