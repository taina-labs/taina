import 'dart:async';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:okena_core/src/result.dart';
import 'package:okena_core/src/taina_error.dart';
import 'package:okena_core/src/transport/transport.dart';

/// The production transport: `dart:io`'s [io.HttpClient], which streams both
/// ways. Uploads read the file handle chunk by chunk and downloads write the
/// response straight to a temp file, so a large video never sits in memory.
final class IoTransport implements Transport {
  IoTransport({
    io.HttpClient? client,
    Duration connectionTimeout = const Duration(seconds: 30),
  }) : _client = client ?? io.HttpClient() {
    _client.connectionTimeout = connectionTimeout;
  }

  final io.HttpClient _client;

  @override
  Future<TainaResult<HttpResponse>> send(HttpRequest request) async {
    try {
      final http = await _open(request);
      final body = request.body;
      if (body != null) {
        http.contentLength = body.length;
        http.add(body);
      }
      final response = await http.close();
      final bytes = await _drain(response);
      return Ok(_assembled(response, bytes));
    } on Exception catch (error) {
      return Err(NetworkError(error.toString()));
    }
  }

  @override
  Future<TainaResult<HttpResponse>> upload(
    HttpRequest request, {
    required String fromFile,
  }) async {
    final file = io.File(fromFile);
    try {
      final http = await _open(request);
      http.contentLength = await file.length();
      await http.addStream(file.openRead());
      final response = await http.close();
      final bytes = await _drain(response);
      return Ok(_assembled(response, bytes));
    } on io.FileSystemException catch (error) {
      return Err(
        NetworkError('could not read the upload body: ${error.message}'),
      );
    } on Exception catch (error) {
      return Err(NetworkError(error.toString()));
    }
  }

  @override
  Future<TainaResult<HttpResponse>> download(HttpRequest request) async {
    io.File? kept;
    try {
      final http = await _open(request);
      final response = await http.close();
      kept = io.File(_tempPath());
      final sink = kept.openWrite();
      try {
        await response.forEach(sink.add);
      } finally {
        await sink.close();
      }
      return Ok(
        HttpResponse(
          status: response.statusCode,
          headers: _headers(response.headers),
          filePath: kept.path,
        ),
      );
    } on io.FileSystemException catch (error) {
      if (kept != null) {
        try {
          await kept.delete();
        } on io.FileSystemException {
          // Best effort: the OS clears the temporary directory.
        }
      }
      return Err(
        NetworkError('could not keep the downloaded file: ${error.message}'),
      );
    } on Exception catch (error) {
      if (kept != null) {
        try {
          await kept.delete();
        } on io.FileSystemException {
          // Best effort.
        }
      }
      return Err(NetworkError(error.toString()));
    }
  }

  /// Releases the underlying connections. The app keeps one transport for its
  /// lifetime; tests call this so the process exits cleanly.
  void close({bool force = false}) => _client.close(force: force);

  Future<io.HttpClientRequest> _open(HttpRequest request) async {
    final http = await _client.openUrl(request.method, request.url);
    for (final entry in request.headers.entries) {
      http.headers.set(entry.key, entry.value);
    }
    return http;
  }

  static Future<Uint8List> _drain(io.HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static HttpResponse _assembled(
    io.HttpClientResponse response,
    Uint8List bytes,
  ) {
    return HttpResponse(
      status: response.statusCode,
      headers: _headers(response.headers),
      data: bytes,
    );
  }

  static Map<String, String> _headers(io.HttpHeaders headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      result[name] = values.join(', ');
    });
    return result;
  }

  static String _tempPath() {
    final random = Random.secure();
    final suffix = String.fromCharCodes([
      for (var index = 0; index < 32; index++)
        '0123456789abcdef'.codeUnitAt(random.nextInt(16)),
    ]);
    return '${io.Directory.systemTemp.path}/taina-transport-$suffix';
  }
}
