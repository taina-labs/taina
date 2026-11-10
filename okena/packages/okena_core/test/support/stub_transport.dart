import 'dart:convert';

import 'package:okena_core/okena_core.dart';

enum CallKind { send, upload, download }

/// One call a transport saw.
final class TransportCall {
  const TransportCall.send(this.request)
    : kind = CallKind.send,
      filePath = null;

  const TransportCall.upload(this.request, this.filePath)
    : kind = CallKind.upload;

  const TransportCall.download(this.request)
    : kind = CallKind.download,
      filePath = null;

  final CallKind kind;
  final HttpRequest request;

  /// The body file for [CallKind.upload].
  final String? filePath;
}

/// A transport that answers from a closure and records every call.
final class StubTransport implements Transport {
  StubTransport(this.handler);

  final Future<TainaResult<HttpResponse>> Function(TransportCall call) handler;
  final List<TransportCall> calls = [];

  List<HttpRequest> get requests => [for (final call in calls) call.request];

  @override
  Future<TainaResult<HttpResponse>> send(HttpRequest request) async {
    final call = TransportCall.send(request);
    calls.add(call);
    return handler(call);
  }

  @override
  Future<TainaResult<HttpResponse>> upload(
    HttpRequest request, {
    required String fromFile,
  }) async {
    final call = TransportCall.upload(request, fromFile);
    calls.add(call);
    return handler(call);
  }

  @override
  Future<TainaResult<HttpResponse>> download(HttpRequest request) async {
    final call = TransportCall.download(request);
    calls.add(call);
    return handler(call);
  }
}

HttpResponse httpResponse({
  required int status,
  String body = '',
  Map<String, String> headers = const {},
  String? filePath,
}) {
  return HttpResponse(
    status: status,
    headers: headers,
    data: utf8.encode(body),
    filePath: filePath,
  );
}

String bodyOf(HttpRequest request) => utf8.decode(request.body ?? const []);
