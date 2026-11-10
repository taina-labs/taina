import 'dart:convert';
import 'dart:io';

import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

String text(List<int> bytes) => utf8.decode(bytes);

void main() {
  test('the body starts and ends with the boundary', () {
    final body = MultipartBody.encode(
      boundary: 'BOUNDARY',
      parts: const [
        MultipartPart(name: 'folder', content: MultipartText('3kx2n8pqrv5w2')),
      ],
    );
    final encoded = text(body);
    expect(encoded, startsWith('--BOUNDARY\r\n'));
    expect(encoded, endsWith('--BOUNDARY--\r\n'));
  });

  test('a text part carries the name without filename', () {
    final encoded = text(
      MultipartBody.prologue(
        boundary: 'BOUNDARY',
        parts: const [
          MultipartPart(
            name: 'folder',
            content: MultipartText('3kx2n8pqrv5w2'),
          ),
        ],
      ),
    );
    expect(
      encoded,
      contains('Content-Disposition: form-data; name="folder"\r\n'),
    );
    expect(encoded, isNot(contains('filename=')));
    expect(encoded, isNot(contains('Content-Type:')));
  });

  test('a file part carries filename and content type', () {
    final encoded = text(
      MultipartBody.prologue(
        boundary: 'BOUNDARY',
        parts: const [
          MultipartPart(
            name: 'folder',
            content: MultipartText('3kx2n8pqrv5w2'),
          ),
          MultipartPart(
            name: 'file',
            filename: 'ata.pdf',
            contentType: 'application/pdf',
            content: MultipartFile('/tmp/nao-existe'),
          ),
        ],
      ),
    );
    expect(encoded, contains('; filename="ata.pdf"\r\n'));
    expect(encoded, contains('Content-Type: application/pdf\r\n'));
  });

  test('the prologue ends ready for the file bytes', () {
    final encoded = text(
      MultipartBody.prologue(
        boundary: 'BOUNDARY',
        parts: const [
          MultipartPart(
            name: 'folder',
            content: MultipartText('3kx2n8pqrv5w2'),
          ),
          MultipartPart(
            name: 'file',
            filename: 'ata.pdf',
            contentType: 'application/pdf',
            content: MultipartFile('/tmp/nao-existe'),
          ),
        ],
      ),
    );
    const expected =
        '--BOUNDARY\r\n'
        'Content-Disposition: form-data; name="folder"\r\n'
        '\r\n'
        '3kx2n8pqrv5w2\r\n'
        '--BOUNDARY\r\n'
        'Content-Disposition: form-data; name="file"; filename="ata.pdf"\r\n'
        'Content-Type: application/pdf\r\n'
        '\r\n';
    expect(encoded, expected);
  });

  test('the epilogue closes the frame', () {
    expect(
      text(MultipartBody.epilogue(boundary: 'BOUNDARY')),
      '\r\n--BOUNDARY--\r\n',
    );
  });

  test('a hostile filename cannot inject a header', () {
    final prologue = text(
      MultipartBody.prologue(
        boundary: 'BOUNDARY',
        parts: const [
          MultipartPart(
            name: 'file',
            filename: 'ata.pdf"\r\nContent-Type: text/html\r\nX: ',
            contentType: 'application/pdf',
            content: MultipartText('bytes'),
          ),
        ],
      ),
    );
    expect(prologue, contains('filename="ata.pdfContent-Type: text/htmlX: "'));
    expect('Content-Disposition'.allMatches(prologue).length, 1);
  });

  test('encode carries the file bytes between prologue and epilogue', () async {
    final source = File(
      '${Directory.systemTemp.path}/multipart-${DateTime.now().microsecondsSinceEpoch}.bin',
    );
    await source.writeAsString('CONTEUDO-DO-ARQUIVO');
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });

    final encoded = text(
      MultipartBody.encode(
        boundary: 'BOUNDARY',
        parts: [
          const MultipartPart(
            name: 'folder',
            content: MultipartText('3kx2n8pqrv5w2'),
          ),
          MultipartPart(
            name: 'file',
            filename: 'ata.pdf',
            contentType: 'application/pdf',
            content: MultipartFile(source.path),
          ),
        ],
      ),
    );
    expect(encoded, contains('CONTEUDO-DO-ARQUIVO'));
    expect(encoded, endsWith('CONTEUDO-DO-ARQUIVO\r\n--BOUNDARY--\r\n'));
  });

  test('the boundary is 32 hex characters and differs between calls', () {
    final first = MultipartBody.boundary();
    final second = MultipartBody.boundary();
    expect(first.length, 32);
    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(first, isNot(second));
  });
}
