import 'dart:convert';
import 'dart:io' as io;

import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  late io.HttpServer server;
  late IoTransport transport;
  late Future<void> Function(io.HttpRequest request) handler;

  setUp(() async {
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    handler = (request) async {
      request.response.statusCode = 200;
      await request.response.close();
    };
    server.listen((request) async {
      try {
        await handler(request);
      } on Object {
        await request.response.close();
      }
    });
    transport = IoTransport();
  });

  tearDown(() async {
    transport.close(force: true);
    await server.close(force: true);
  });

  Uri uri(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test('send carries the status and the body', () async {
    handler = (request) async {
      request.response.statusCode = 201;
      request.response.write('criado');
      await request.response.close();
    };

    final response = (await transport.send(
      HttpRequest(url: uri('/x'), method: 'GET'),
    )).value!;
    expect(response.status, 201);
    expect(response.isSuccess, isTrue);
    expect(response.body, 'criado');
    expect(response.filePath, isNull);
  });

  test('send carries the method, headers and JSON body', () async {
    String? method;
    String? contentType;
    var body = '';
    handler = (request) async {
      method = request.method;
      contentType = request.headers.value('content-type');
      body = await utf8.decodeStream(request);
      request.response.statusCode = 200;
      request.response.write('{}');
      await request.response.close();
    };

    await transport.send(
      HttpRequest(
        url: uri('/api/v1/session'),
        method: 'POST',
        headers: const {'Content-Type': 'application/json'},
        body: '{"a":1}'.codeUnits,
      ),
    );

    expect(method, 'POST');
    expect(contentType, 'application/json');
    expect(body, '{"a":1}');
  });

  test('upload streams the file and carries the status', () async {
    final file = io.File(
      '${io.Directory.systemTemp.path}/urlsession-transport-${DateTime.now().microsecondsSinceEpoch}',
    );
    final payload = List<int>.generate(2 * 1024 * 1024, (index) => index % 251);
    await file.writeAsBytes(payload);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });

    var received = <int>[];
    String? contentType;
    handler = (request) async {
      contentType = request.headers.value('content-type');
      received = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      request.response.statusCode = 200;
      request.response.write('ok');
      await request.response.close();
    };

    final response = (await transport.upload(
      HttpRequest(
        url: uri('/x'),
        method: 'POST',
        headers: const {
          'Content-Type': 'multipart/form-data; boundary=BOUNDARY',
        },
      ),
      fromFile: file.path,
    )).value!;

    expect(response.status, 200);
    expect(response.body, 'ok');
    expect(contentType, 'multipart/form-data; boundary=BOUNDARY');
    expect(received.length, payload.length);
  });

  test('download writes the body to a file and keeps the headers', () async {
    handler = (request) async {
      request.response.statusCode = 200;
      request.response.headers.set(
        'Content-Disposition',
        'attachment; filename="a.pdf"',
      );
      request.response.add('BYTES'.codeUnits);
      await request.response.close();
    };

    final response = (await transport.download(
      HttpRequest(url: uri('/x'), method: 'GET'),
    )).value!;
    final file = response.filePath!;
    addTearDown(() async {
      if (await io.File(file).exists()) await io.File(file).delete();
    });

    expect(response.status, 200);
    expect(response.data, isEmpty);
    // The header lookup is case-insensitive.
    expect(
      response.header('content-DISPOSITION'),
      'attachment; filename="a.pdf"',
    );
    expect(await io.File(file).readAsString(), 'BYTES');
  });

  test('download of an error keeps the response for the caller', () async {
    const envelope =
        '{"error":{"code":"not_authenticated",'
        '"message":"Entre na sua conta para continuar."}}';
    handler = (request) async {
      request.response.statusCode = 401;
      request.response.write(envelope);
      await request.response.close();
    };

    final response = (await transport.download(
      HttpRequest(url: uri('/x'), method: 'GET'),
    )).value!;
    final file = response.filePath!;
    addTearDown(() async {
      if (await io.File(file).exists()) await io.File(file).delete();
    });

    expect(response.status, 401);
    expect(response.isSuccess, isFalse);
    expect(await io.File(file).readAsString(), envelope);
  });

  test('a download error envelope becomes the typed error', () async {
    handler = (request) async {
      request.response.statusCode = 401;
      request.response.write(
        '{"error":{"code":"not_authenticated",'
        '"message":"Entre na sua conta para continuar."}}',
      );
      await request.response.close();
    };

    final store = SessionStore(storage: InMemorySessionStorage());
    await store.signIn(fixturedSession());
    final api = LiveTainaApi(
      transport: transport,
      host: InMemoryHostStore(
        InstanceAddress.parse('http://127.0.0.1:${server.port}').value!,
      ),
      session: store,
    );

    final error = (await api.download(rkey: '3m2a8twqpv5z2')).error;
    expect(error, isA<ApiError>());
    final apiError = error as ApiError;
    expect(apiError.isUnauthorized, isTrue);
    expect(apiError.code, 'not_authenticated');
  });
}
