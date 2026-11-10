import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:okena_core/src/api/conditional_store.dart';
import 'package:okena_core/src/api/multipart_body.dart';
import 'package:okena_core/src/api/sort.dart';
import 'package:okena_core/src/api/taina_api.dart';
import 'package:okena_core/src/json/api_coding.dart';
import 'package:okena_core/src/models/access.dart';
import 'package:okena_core/src/models/mural.dart';
import 'package:okena_core/src/models/page.dart';
import 'package:okena_core/src/models/storage.dart';
import 'package:okena_core/src/models/timeline.dart';
import 'package:okena_core/src/models/token_status.dart';
import 'package:okena_core/src/models/wire.dart';
import 'package:okena_core/src/result.dart';
import 'package:okena_core/src/session/host_store.dart';
import 'package:okena_core/src/session/session.dart';
import 'package:okena_core/src/session/session_store.dart';
import 'package:okena_core/src/taina_error.dart';
import 'package:okena_core/src/transport/io_transport.dart';
import 'package:okena_core/src/transport/transport.dart';

/// The real caller: a [Transport], the box address from [HostStore] and the
/// device token from [SessionStore], both read at call time. A revoked token
/// must fail on the next request, so reading late is the point.
final class LiveTainaApi implements TainaApi {
  LiveTainaApi({
    Transport? transport,
    required this.host,
    required this.session,
  }) : transport = transport ?? IoTransport();

  final Transport transport;
  final HostStore host;
  final SessionStore session;
  final ConditionalStore _conditional = ConditionalStore();

  @override
  Future<TainaResult<Instance>> instance() {
    return _sendJson(
      path: 'instance',
      authenticated: false,
      label: 'instance',
      decode: Instance.fromJson,
    );
  }

  @override
  Future<TainaResult<Session>> createSession({
    required String username,
    required String password,
    required String deviceName,
  }) {
    return _sendJson(
      path: 'session',
      method: 'POST',
      body: _jsonBody({
        'username': username,
        'password': password,
        'device_name': deviceName,
      }),
      contentType: _jsonContentType,
      authenticated: false,
      label: 'session',
      decode: Session.fromJson,
    );
  }

  @override
  Future<TainaResult<TokenStatus>> inviteStatus({required String token}) {
    return _sendJson(
      path: 'invites/$token',
      authenticated: false,
      label: 'invite status',
      decode: TokenStatus.fromJson,
    );
  }

  /// One password on the wire, on purpose: the two password fields are the
  /// app's own check, so a typo cannot arrive looking like a dead token (the
  /// 401 the box would answer otherwise).
  @override
  Future<TainaResult<Session>> acceptInvite({
    required String token,
    required String username,
    required String password,
    String? displayName,
    required String deviceName,
  }) {
    return _sendJson(
      path: 'invites/$token/accept',
      method: 'POST',
      body: _jsonBody({
        'username': username,
        'password': password,
        'display_name': ?displayName,
        'device_name': deviceName,
      }),
      contentType: _jsonContentType,
      authenticated: false,
      label: 'accepted invite',
      decode: Session.fromJson,
    );
  }

  @override
  Future<TainaResult<TokenStatus>> resetStatus({required String token}) {
    return _sendJson(
      path: 'password-resets/$token',
      authenticated: false,
      label: 'reset status',
      decode: TokenStatus.fromJson,
    );
  }

  @override
  Future<TainaResult<Session>> resetPassword({
    required String token,
    required String password,
    required String deviceName,
  }) {
    return _sendJson(
      path: 'password-resets/$token',
      method: 'POST',
      body: _jsonBody({'password': password, 'device_name': deviceName}),
      contentType: _jsonContentType,
      authenticated: false,
      label: 'password reset',
      decode: Session.fromJson,
    );
  }

  @override
  Future<TainaResult<void>> revokeSession() {
    return _sendEmpty(path: 'session', method: 'DELETE', authenticated: true);
  }

  @override
  Future<TainaResult<Me>> me() {
    return _sendJson(
      path: 'me',
      authenticated: true,
      label: 'me',
      decode: Me.fromJson,
    );
  }

  @override
  Future<TainaResult<List<DeviceToken>>> devices() async {
    final page = await _sendJson(
      path: 'devices',
      authenticated: true,
      label: 'devices',
      decode: (reader) => Page.fromJson(reader, DeviceToken.fromJson),
    );
    return page.map((value) => value.items);
  }

  @override
  Future<TainaResult<void>> revokeDevice({required String id}) {
    return _sendEmpty(
      path: 'devices/$id',
      method: 'DELETE',
      authenticated: true,
    );
  }

  @override
  Future<TainaResult<List<Folder>>> listFolders() async {
    final page = await _sendJson(
      path: 'folders',
      authenticated: true,
      label: 'folders',
      decode: (reader) => Page.fromJson(reader, Folder.fromJson),
    );
    return page.map((value) => value.items);
  }

  @override
  Future<TainaResult<Folder>> folder({required String rkey}) {
    return _sendJson(
      path: 'folders/$rkey',
      authenticated: true,
      label: 'folder',
      decode: Folder.fromJson,
    );
  }

  @override
  Future<TainaResult<Folder>> updateFolder({
    required String rkey,
    String? name,
    Zona? zona,
  }) {
    return _sendJson(
      path: 'folders/$rkey',
      method: 'PATCH',
      body: _jsonBody({'name': ?name, 'zona': ?zona?.name}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'folder',
      decode: Folder.fromJson,
    );
  }

  @override
  Future<TainaResult<Folder>> moveFolder({
    required String rkey,
    String? parentRkey,
  }) {
    return _sendJson(
      path: 'folders/$rkey/move',
      method: 'POST',
      body: _jsonBody({'parent_rkey': ?parentRkey}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'folder',
      decode: Folder.fromJson,
    );
  }

  @override
  Future<TainaResult<void>> deleteFolder({required String rkey}) {
    return _sendEmpty(
      path: 'folders/$rkey',
      method: 'DELETE',
      authenticated: true,
    );
  }

  @override
  Future<TainaResult<Folder>> createFolder({
    required String name,
    String? parentRkey,
  }) {
    return _sendJson(
      path: 'folders',
      method: 'POST',
      body: _jsonBody({'name': name, 'parent_rkey': ?parentRkey}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'folder',
      decode: Folder.fromJson,
    );
  }

  @override
  Future<TainaResult<FolderContents>> folderContents({
    String? folderRkey,
    int? limit,
    String? cursor,
    Sort? sort,
  }) {
    return _conditionalGet(
      path: 'contents',
      query: {
        'folder': folderRkey,
        'limit': limit?.toString(),
        'cursor': cursor,
        'sort': sort?.wire,
      },
      label: 'contents',
      decode: FolderContents.fromJson,
    );
  }

  @override
  Future<TainaResult<FileRecord>> upload({
    required String filePath,
    required String name,
    required String mime,
    String? folderRkey,
  }) async {
    final boundary = MultipartBody.boundary();
    final parts = [
      if (folderRkey != null)
        MultipartPart(name: 'folder', content: MultipartText(folderRkey)),
      MultipartPart(
        name: 'file',
        filename: name,
        contentType: mime,
        content: MultipartFile(filePath),
      ),
    ];

    final request = await _prepared(
      path: 'files',
      method: 'POST',
      contentType: 'multipart/form-data; boundary=$boundary',
      authenticated: true,
    );
    switch (request) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final assembled = await _assemble(
          boundary: boundary,
          parts: parts,
          source: filePath,
        );
        switch (assembled) {
          case Err(:final error):
            return Err(error);
          case Ok(value: final bodyFile):
            final outcome = await transport.upload(value, fromFile: bodyFile);
            // Cleanup is best effort; the OS clears the temp directory.
            try {
              await io.File(bodyFile).delete();
            } on io.FileSystemException {
              // Best effort.
            }
            switch (outcome) {
              case Err(:final error):
                return Err(error);
              case Ok(value: final http):
                return _respond(http, 'uploaded file', FileRecord.fromJson);
            }
        }
    }
  }

  @override
  Future<TainaResult<FileRecord>> file({required String rkey}) {
    return _sendJson(
      path: 'files/$rkey',
      authenticated: true,
      label: 'file',
      decode: FileRecord.fromJson,
    );
  }

  @override
  Future<TainaResult<FileRecord>> updateFile({
    required String rkey,
    String? name,
    Zona? zona,
  }) {
    return _sendJson(
      path: 'files/$rkey',
      method: 'PATCH',
      body: _jsonBody({'name': ?name, 'zona': ?zona?.name}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'file',
      decode: FileRecord.fromJson,
    );
  }

  @override
  Future<TainaResult<FileRecord>> moveFile({
    required String rkey,
    String? folderRkey,
  }) {
    // The wire key is `folder`, so the JSON key carries the name itself;
    // `folder_rkey` would not be the contract.
    return _sendJson(
      path: 'files/$rkey/move',
      method: 'POST',
      body: _jsonBody({'folder': ?folderRkey}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'file',
      decode: FileRecord.fromJson,
    );
  }

  @override
  Future<TainaResult<void>> deleteFile({required String rkey}) {
    return _sendEmpty(
      path: 'files/$rkey',
      method: 'DELETE',
      authenticated: true,
    );
  }

  @override
  Future<TainaResult<Page<FileRecord>>> recent({int? limit}) {
    return _conditionalGet(
      path: 'recent',
      query: {'limit': limit?.toString()},
      label: 'recent',
      decode: (reader) => Page.fromJson(reader, FileRecord.fromJson),
    );
  }

  @override
  Future<TainaResult<String>> download({required String rkey}) async {
    final request = await _prepared(
      path: 'files/$rkey/download',
      authenticated: true,
      accept: null,
    );
    switch (request) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final outcome = await transport.download(value);
        switch (outcome) {
          case Err(:final error):
            return Err(error);
          case Ok(value: final http):
            return _settle(http, fallbackName: rkey);
        }
    }
  }

  @override
  Future<TainaResult<Uint8List>> thumbnail({
    required String rkey,
    required ThumbnailSize size,
  }) async {
    // No image type asked for, on purpose: the API pipeline negotiates JSON
    // only, so a request that says `Accept: image/webp` is answered 406
    // before the controller runs. The endpoint's type is fixed, so the client
    // asks for anything.
    final request = await _prepared(
      path: 'files/$rkey/thumbnail/${size.wire}',
      authenticated: true,
      accept: '*/*',
    );
    switch (request) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final outcome = await transport.send(value);
        switch (outcome) {
          case Err(:final error):
            return Err(error);
          case Ok(value: final http):
            if (!http.isSuccess) return Err(apiFailure(http));
            return Ok(http.data);
        }
    }
  }

  @override
  Future<TainaResult<Page<FileRecord>>> trash({int? limit, String? cursor}) {
    return _conditionalGet(
      path: 'trash',
      query: {'limit': limit?.toString(), 'cursor': cursor},
      label: 'trash',
      decode: (reader) => Page.fromJson(reader, FileRecord.fromJson),
    );
  }

  @override
  Future<TainaResult<FileRecord>> restoreFile({required String rkey}) {
    return _sendJson(
      path: 'trash/$rkey/restore',
      method: 'POST',
      authenticated: true,
      label: 'restored file',
      decode: FileRecord.fromJson,
    );
  }

  @override
  Future<TainaResult<Page<FileRecord>>> photos({int? limit, String? cursor}) {
    return _conditionalGet(
      path: 'photos',
      query: {'limit': limit?.toString(), 'cursor': cursor},
      label: 'photos',
      decode: (reader) => Page.fromJson(reader, FileRecord.fromJson),
    );
  }

  @override
  Future<TainaResult<Page<TimelineGroup>>> photoTimeline({
    int? limit,
    String? cursor,
  }) {
    return _conditionalGet(
      path: 'photos/timeline',
      query: {'limit': limit?.toString(), 'cursor': cursor},
      label: 'timeline',
      decode: (reader) => Page.fromJson(reader, TimelineGroup.fromJson),
    );
  }

  @override
  Future<TainaResult<Page<FileRecord>>> manifest({String? after, int? limit}) {
    return _conditionalGet(
      path: 'files/manifest',
      query: {'after': after, 'limit': limit?.toString()},
      label: 'manifest',
      decode: (reader) => Page.fromJson(reader, FileRecord.fromJson),
    );
  }

  @override
  Future<TainaResult<List<BatchOutcome>>> batch({
    required BatchOp op,
    required List<String> ids,
    String? folderRkey,
  }) {
    return _sendJson(
      path: 'files/batch',
      method: 'POST',
      body: _jsonBody({'op': op.name, 'ids': ids, 'folder': ?folderRkey}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'batch',
      decode: (reader) => reader.list('results', BatchOutcome.fromJson),
    );
  }

  @override
  Future<TainaResult<AccessTarget>> accessTarget({required String fileRkey}) {
    return _sendJson(
      path: 'files/$fileRkey/access-target',
      authenticated: true,
      label: 'access target',
      decode: AccessTarget.fromJson,
    );
  }

  @override
  Future<TainaResult<Pedido>> requestAccess({
    required String fileRkey,
    String? motivo,
  }) {
    return _sendJson(
      path: 'files/$fileRkey/access-request',
      method: 'POST',
      body: _jsonBody({'motivo': ?motivo}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'access request',
      decode: Pedido.fromJson,
    );
  }

  @override
  Future<TainaResult<Page<Pedido>>> accessRequests() {
    return _sendJson(
      path: 'access-requests',
      authenticated: true,
      label: 'access requests',
      decode: (reader) => Page.fromJson(reader, Pedido.fromJson),
    );
  }

  @override
  Future<TainaResult<Page<Pedido>>> myRequests() {
    return _sendJson(
      path: 'my-requests',
      authenticated: true,
      label: 'my requests',
      decode: (reader) => Page.fromJson(reader, Pedido.fromJson),
    );
  }

  @override
  Future<TainaResult<Concessao>> approveRequest({required String id}) {
    return _sendJson(
      path: 'access-requests/$id/approve',
      method: 'POST',
      authenticated: true,
      label: 'concessao',
      decode: Concessao.fromJson,
    );
  }

  @override
  Future<TainaResult<Pedido>> denyRequest({required String id}) {
    return _sendJson(
      path: 'access-requests/$id/deny',
      method: 'POST',
      authenticated: true,
      label: 'pedido',
      decode: Pedido.fromJson,
    );
  }

  @override
  Future<TainaResult<Page<Concessao>>> grants({required GrantRole role}) {
    return _conditionalGet(
      path: 'grants',
      query: {'role': role.name},
      label: 'grants',
      decode: (reader) => Page.fromJson(reader, Concessao.fromJson),
    );
  }

  @override
  Future<TainaResult<void>> revokeGrant({required String id}) {
    return _sendEmpty(
      path: 'grants/$id',
      method: 'DELETE',
      authenticated: true,
    );
  }

  @override
  Future<TainaResult<MemberInvite>> inviteMember({required Papel papel}) {
    return _sendJson(
      path: 'members',
      method: 'POST',
      body: _jsonBody({'papel': papel.name}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'member invite',
      decode: MemberInvite.fromJson,
    );
  }

  @override
  Future<TainaResult<Ava>> updateMember({
    required String id,
    required Papel papel,
  }) {
    return _sendJson(
      path: 'members/$id',
      method: 'PATCH',
      body: _jsonBody({'papel': papel.name}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'member',
      decode: Ava.fromJson,
    );
  }

  @override
  Future<TainaResult<void>> deactivateMember({required String id}) {
    return _sendEmpty(
      path: 'members/$id',
      method: 'DELETE',
      authenticated: true,
    );
  }

  @override
  Future<TainaResult<Ava>> reactivateMember({required String id}) {
    return _sendJson(
      path: 'members/$id/reactivate',
      method: 'POST',
      authenticated: true,
      label: 'member',
      decode: Ava.fromJson,
    );
  }

  @override
  Future<TainaResult<void>> revokeInvite({required String id}) {
    return _sendEmpty(
      path: 'members/$id/invite',
      method: 'DELETE',
      authenticated: true,
    );
  }

  @override
  Future<TainaResult<ResetLink>> memberResetLink({required String id}) {
    return _sendJson(
      path: 'members/$id/reset-link',
      method: 'POST',
      authenticated: true,
      label: 'reset link',
      decode: ResetLink.fromJson,
    );
  }

  @override
  Future<TainaResult<Tekoa>> setQuota({required int bytes}) {
    return _sendJson(
      path: 'storage/quota',
      method: 'PATCH',
      body: _jsonBody({'quota_bytes': bytes}),
      contentType: _jsonContentType,
      authenticated: true,
      label: 'quota',
      decode: Tekoa.fromJson,
    );
  }

  @override
  Future<TainaResult<void>> triggerBackup() {
    return _sendEmpty(
      path: 'saude/backup',
      method: 'POST',
      authenticated: true,
    );
  }

  /// The self-service change, while signed in: the box checks the current
  /// password, keeps the calling device's session and revokes every other
  /// one. A wrong current answers 403 `invalid_credentials`, not the 401 of
  /// a dead session.
  @override
  Future<TainaResult<void>> updatePassword({
    required String current,
    required String newPassword,
  }) {
    return _sendEmpty(
      path: 'session/password',
      method: 'POST',
      body: _jsonBody({
        'current_password': current,
        'new_password': newPassword,
      }),
      contentType: _jsonContentType,
      authenticated: true,
    );
  }

  @override
  Future<TainaResult<Page<MuralEntry>>> mural({int? limit, String? cursor}) {
    return _sendJson(
      path: 'mural',
      query: {'limit': limit?.toString(), 'cursor': cursor},
      authenticated: true,
      label: 'mural',
      decode: (reader) => Page.fromJson(reader, MuralEntry.fromJson),
    );
  }

  @override
  Future<TainaResult<StorageStats>> storage() {
    return _sendJson(
      path: 'storage',
      authenticated: true,
      label: 'storage',
      decode: StorageStats.fromJson,
    );
  }

  @override
  Future<TainaResult<Saude>> saude() {
    return _sendJson(
      path: 'saude',
      authenticated: true,
      label: 'saude',
      decode: Saude.fromJson,
    );
  }

  @override
  Future<TainaResult<Page<Ava>>> members() {
    return _sendJson(
      path: 'members',
      authenticated: true,
      label: 'members',
      decode: (reader) => Page.fromJson(reader, Ava.fromJson),
    );
  }

  // MARK: internals

  static const String _jsonContentType = 'application/json';

  static List<int> _jsonBody(Map<String, Object?> body) =>
      utf8.encode(jsonEncode(body));

  /// Reads the box address and, when authenticated, the token at call time.
  /// Without a saved address the caller is sent back to Setup.
  Future<TainaResult<HttpRequest>> _prepared({
    required String path,
    String method = 'GET',
    Map<String, String?> query = const {},
    List<int>? body,
    String? contentType,
    required bool authenticated,
    String? accept = 'application/json',
  }) async {
    final address = await host.address();
    if (address == null) {
      return const Err(InvalidAddressError(AddressProblem.empty));
    }
    String? token;
    if (authenticated) {
      token = session.token;
      if (token == null) {
        return const Err(NotSignedInError());
      }
    }
    return build(
      base: address.url,
      path: path,
      method: method,
      query: query,
      body: body,
      contentType: contentType,
      authenticated: authenticated,
      token: token,
      accept: accept,
    );
  }

  /// Builds one request against the box. Pure, so the URL, the query encoding
  /// and the `Authorization: Bearer` header are proven by tests.
  /// `Authorization` is only added when [authenticated].
  static TainaResult<HttpRequest> build({
    required Uri base,
    required String path,
    String method = 'GET',
    Map<String, String?> query = const {},
    List<int>? body,
    String? contentType,
    bool authenticated = false,
    String? token,
    String? accept = 'application/json',
  }) {
    if (base.scheme.isEmpty || base.host.isEmpty) {
      return Err(InvalidUrlError());
    }
    var prefix = base.path;
    if (prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    var uri = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '$prefix/api/v1/$path',
    );

    final given =
        query.entries
            .where((entry) => entry.value != null)
            .map((entry) => MapEntry(entry.key, entry.value!))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    if (given.isNotEmpty) {
      final raw = given
          .map(
            (entry) =>
                '${Uri.encodeComponent(entry.key)}='
                '${Uri.encodeComponent(entry.value)}',
          )
          .join('&');
      uri = Uri.parse('$uri?$raw');
    }

    final authorization = authenticated && token != null
        ? 'Bearer $token'
        : null;
    final headers = <String, String>{
      'Accept': ?accept,
      'Authorization': ?authorization,
      'Content-Type': ?contentType,
    };
    return Ok(
      HttpRequest(url: uri, method: method, headers: headers, body: body),
    );
  }

  Future<TainaResult<T>> _sendJson<T>({
    required String path,
    String method = 'GET',
    Map<String, String?> query = const {},
    List<int>? body,
    String? contentType,
    required bool authenticated,
    String? accept = 'application/json',
    required String label,
    required T Function(JsonReader reader) decode,
  }) async {
    final request = await _prepared(
      path: path,
      method: method,
      query: query,
      body: body,
      contentType: contentType,
      authenticated: authenticated,
      accept: accept,
    );
    switch (request) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final sent = await transport.send(value);
        switch (sent) {
          case Err(:final error):
            return Err(error);
          case Ok(value: final http):
            return _respond(http, label, decode);
        }
    }
  }

  Future<TainaResult<void>> _sendEmpty({
    required String path,
    String method = 'GET',
    Map<String, String?> query = const {},
    List<int>? body,
    String? contentType,
    required bool authenticated,
    String? accept = 'application/json',
  }) async {
    final request = await _prepared(
      path: path,
      method: method,
      query: query,
      body: body,
      contentType: contentType,
      authenticated: authenticated,
      accept: accept,
    );
    switch (request) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final sent = await transport.send(value);
        switch (sent) {
          case Err(:final error):
            return Err(error);
          case Ok(value: final http):
            return _respondEmpty(http);
        }
    }
  }

  /// The one place a status becomes a value: 2xx decodes, anything else
  /// becomes the error envelope. 402, 429 and 5xx are not special cased; the
  /// envelope carries `code` and the typed helpers on [ApiError] are how a
  /// caller branches.
  TainaResult<T> _respond<T>(
    HttpResponse http,
    String label,
    T Function(JsonReader reader) decode,
  ) {
    if (!http.isSuccess) {
      return Err(apiFailure(http));
    }
    return decodeJsonBody(http.data, label, decode);
  }

  TainaResult<void> _respondEmpty(HttpResponse http) {
    if (!http.isSuccess) {
      return Err(apiFailure(http));
    }
    return const Ok<void>(null);
  }

  /// The collection reads (manifest, contents, photos, timeline, recent,
  /// trash, grants): sends the stored `If-None-Match` when the box tagged the
  /// last answer, and keeps every new tag with its body. A 304 carries no
  /// body, so the one kept before is decoded again.
  Future<TainaResult<T>> _conditionalGet<T>({
    required String path,
    required Map<String, String?> query,
    required String label,
    required T Function(JsonReader reader) decode,
  }) async {
    final request = await _prepared(
      path: path,
      query: query,
      authenticated: true,
    );
    switch (request) {
      case Err(:final error):
        return Err(error);
      case Ok(value: final built):
        final key = cacheKey(built.url, session.token);
        final tag = _conditional.tag(key);
        final conditioned = tag == null
            ? built
            : built.withHeader('If-None-Match', tag);
        final sent = await transport.send(conditioned);
        switch (sent) {
          case Err(:final error):
            return Err(error);
          case Ok(value: final http):
            if (http.status == 304) {
              final cached = _conditional.body(key);
              if (cached == null) {
                return Err(InvalidResponseError(label));
              }
              return decodeJsonBody(cached, label, decode);
            }
            if (!http.isSuccess) {
              return Err(apiFailure(http));
            }
            _conditional.keep(
              tag: http.header('ETag'),
              body: http.data,
              key: key,
            );
            return decodeJsonBody(http.data, label, decode);
        }
    }
  }

  /// The cache key of a conditional read: the request, with its query, plus
  /// the session the etag belongs to.
  static String cacheKey(Uri? url, String? token) =>
      '${url ?? ''}|${token ?? ''}';

  /// Decodes the error envelope; when the body is not the envelope (an HTML
  /// error page, an empty body), the fallback is `internal_error` and the body
  /// never reaches the message.
  static TainaError apiFailure(HttpResponse http) {
    var data = http.data;
    final filePath = http.filePath;
    if (data.isEmpty && filePath != null) {
      try {
        data = io.File(filePath).readAsBytesSync();
      } on io.FileSystemException {
        data = Uint8List(0);
      }
    }

    final envelope = decodeJsonBody(data, 'error envelope', (reader) {
      final error = reader.object('error');
      return (
        code: error.string('code'),
        message: error.string('message'),
        details: error.stringListMapOrEmpty('details'),
      );
    });
    switch (envelope) {
      case Ok(:final value):
        return ApiError(
          code: value.code,
          status: http.status,
          serverMessage: value.message,
          details: value.details,
        );
      case Err():
        return ApiError(
          code: 'internal_error',
          status: http.status,
          serverMessage:
              'Algo deu errado na comunidade. Tente de novo em instantes.',
        );
    }
  }

  /// Writes the multipart body to a temp file, streaming the source file
  /// through it, so a 2 GiB video is never held in memory.
  Future<TainaResult<String>> _assemble({
    required String boundary,
    required List<MultipartPart> parts,
    required String source,
  }) async {
    final bodyFile = _tempPath('taina-upload');
    final output = io.File(bodyFile).openWrite();
    try {
      output.add(MultipartBody.prologue(boundary: boundary, parts: parts));
      // One stream of chunks: the source may be a 2 GiB video.
      await for (final chunk in io.File(source).openRead()) {
        output.add(chunk);
      }
      output.add(MultipartBody.epilogue(boundary: boundary));
      await output.flush();
      await output.close();
      return Ok(bodyFile);
    } on io.FileSystemException catch (error) {
      await _closeQuietly(output);
      await _deleteQuietly(bodyFile);
      return Err(
        NetworkError('could not assemble the upload body: ${error.message}'),
      );
    }
  }

  /// Moves the downloaded file under a unique directory: the server's
  /// content-disposition filename when it carries one, the rkey otherwise.
  TainaResult<String> _settle(
    HttpResponse http, {
    required String fallbackName,
  }) {
    final filePath = http.filePath;
    if (!http.isSuccess || filePath == null) {
      // The failure reads the envelope from the file, so the file goes away
      // only after the failure is built.
      final failure = apiFailure(http);
      if (filePath != null) {
        _deleteQuietlySync(filePath);
      }
      return Err(failure);
    }

    final name = attachmentFilename(http) ?? fallbackName;
    // The uniqueness goes in the directory, not in the filename: the person
    // reads this name in the share sheet and in Files.
    final directory = _tempPath('taina-download');
    try {
      io.Directory(directory).createSync(recursive: true);
      final target = '$directory/${sanitize(name)}';
      io.File(filePath).renameSync(target);
      return Ok(target);
    } on io.FileSystemException catch (error) {
      _deleteQuietlySync(filePath);
      return Err(
        NetworkError('could not keep the downloaded file: ${error.message}'),
      );
    }
  }

  /// The `filename` of a Content-Disposition header. The extended
  /// `filename*=` form (RFC 5987) wins when it parses: the plain parameter
  /// cannot carry an accent without corrupting the name, and the box sends
  /// both forms on purpose.
  static String? attachmentFilename(HttpResponse http) {
    final disposition = http.header('Content-Disposition');
    if (disposition == null) return null;
    String? plain;
    for (final piece in disposition.split(';')) {
      final trimmed = piece.trim();
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('filename*=')) {
        final extended = extendedValue(trimmed.substring('filename*='.length));
        if (extended != null) return extended;
      } else if (lower.startsWith('filename=') && plain == null) {
        final value = trimmed
            .substring('filename='.length)
            .replaceAll(RegExp(r'^"+|"+$'), '');
        if (value.isNotEmpty) plain = value;
      }
    }
    return plain;
  }

  /// Decodes an RFC 5987 ext-value: `charset'language'percent-encoded`,
  /// usually `UTF-8''Fotografia%20da%20pra%C3%A7a.jpg`. Only UTF-8 is spoken
  /// here; another charset returns null, so the plain parameter answers.
  static String? extendedValue(String raw) {
    final parts = raw.split("'");
    if (parts.length < 3) return null;
    final charset = parts[0].toLowerCase();
    if (charset != 'utf-8' && charset != 'utf8') return null;
    final encoded = parts.sublist(2).join("'");
    try {
      final decoded = Uri.decodeComponent(encoded);
      return decoded.isEmpty ? null : decoded;
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Path separators are the ones that make a filename walk the tree.
  static String sanitize(String name) {
    final clean = name.replaceAll('/', '').replaceAll('\\', '');
    return clean.isEmpty ? 'arquivo' : clean;
  }

  static String _tempPath(String prefix) {
    final random = Random.secure();
    final suffix = String.fromCharCodes([
      for (var index = 0; index < 32; index++)
        '0123456789abcdef'.codeUnitAt(random.nextInt(16)),
    ]);
    return '${io.Directory.systemTemp.path}/$prefix-$suffix';
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await io.File(path).delete();
    } on io.FileSystemException {
      // Best effort.
    }
  }

  static void _deleteQuietlySync(String path) {
    try {
      io.File(path).deleteSync();
    } on io.FileSystemException {
      // Best effort.
    }
  }

  static Future<void> _closeQuietly(io.IOSink sink) async {
    try {
      await sink.close();
    } on Object {
      // Best effort.
    }
  }
}
