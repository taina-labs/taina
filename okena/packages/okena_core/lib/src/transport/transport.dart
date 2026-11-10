import 'dart:convert';
import 'dart:typed_data';

import 'package:okena_core/src/result.dart';

/// One HTTP round trip.
///
/// For [Transport.send] the body is [data]; for [Transport.download] the body
/// is on disk at [filePath] and [data] is empty, so a video is never held in
/// memory.
final class HttpResponse {
  HttpResponse({
    required this.status,
    Map<String, String> headers = const {},
    List<int> data = const [],
    this.filePath,
  }) : data = Uint8List.fromList(data),
       headers = Map.unmodifiable({
         for (final entry in headers.entries)
           entry.key.toLowerCase(): entry.value,
       });

  final Uint8List data;
  final int status;

  /// The caller already owns the file at [filePath].
  final String? filePath;

  /// Header names are case-insensitive.
  final Map<String, String> headers;

  String get body => utf8.decode(data, allowMalformed: true);

  bool get isSuccess => status >= 200 && status < 300;

  /// The header, case-insensitively, or null.
  String? header(String name) => headers[name.toLowerCase()];
}

/// One request description, independent of any HTTP library.
final class HttpRequest {
  const HttpRequest({
    required this.url,
    required this.method,
    this.headers = const {},
    this.body,
  });

  final Uri url;
  final String method;
  final Map<String, String> headers;

  /// JSON or form body for [Transport.send]; null for uploads and downloads.
  final List<int>? body;

  HttpRequest withHeader(String name, String value) {
    return HttpRequest(
      url: url,
      method: method,
      headers: {...headers, name: value},
      body: body,
    );
  }
}

/// The only seam that touches the network. Everything above it takes a
/// [Transport], so the whole client is testable with a stub and no sockets.
abstract class Transport {
  /// Everything that carries JSON in and out.
  Future<TainaResult<HttpResponse>> send(HttpRequest request);

  /// A request body that already lives in a file: the transport streams it
  /// from disk, so a 2 GiB upload is never held in memory.
  Future<TainaResult<HttpResponse>> upload(
    HttpRequest request, {
    required String fromFile,
  });

  /// The response written to a file, with its status and headers, so the
  /// caller can name it and move it where it wants.
  Future<TainaResult<HttpResponse>> download(HttpRequest request);
}
