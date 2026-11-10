import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:okena_core/src/api/sort.dart';
import 'package:okena_core/src/api/taina_api.dart';
import 'package:okena_core/src/json/json_value.dart';
import 'package:okena_core/src/models/access.dart';
import 'package:okena_core/src/models/mural.dart';
import 'package:okena_core/src/models/page.dart';
import 'package:okena_core/src/models/storage.dart';
import 'package:okena_core/src/models/timeline.dart';
import 'package:okena_core/src/models/token_status.dart';
import 'package:okena_core/src/models/wire.dart';
import 'package:okena_core/src/result.dart';
import 'package:okena_core/src/session/session.dart';
import 'package:okena_core/src/taina_error.dart';

/// A [TainaApi] over an in-memory world: the preview double and the UI test
/// double, and the reason a screen can be built and looked at without a box.
///
/// It never touches [Transport], [HostStore] or [SessionStore]. [delay] is
/// 300ms by default so previews show their loading states; tests pass
/// [Duration.zero].
final class FakeTainaApi implements TainaApi {
  FakeTainaApi({this.delay = const Duration(milliseconds: 300)}) {
    _seed();
  }

  final Duration delay;
  var _counter = 0;

  late Tekoa _tekoa;
  late List<Ava> _avas;
  late Ava _neighbor;
  late List<DeviceToken> _devices;
  late List<Folder> _folders;
  late List<FileRecord> _files;
  late List<Pedido> _receivedPedidos;
  late List<Pedido> _sentPedidos;
  late List<Concessao> _concessoes;
  late List<MuralEntry> _muralEntries;
  late Map<String, Uint8List> _bytes;
  Session? _session;

  void _seed() {
    _tekoa = const Tekoa(
      publicId: 'tekp2xw5m8q3',
      name: 'Tekoa Sapukai',
      domain: 'taina.sapukai.ts.net',
      storageQuotaBytes: 268435456000,
      storageUsedBytes: 1832110000,
      createdAt: '2026-02-01T09:00:00Z',
    );

    const ana = Ava(
      publicId: 'avap2xw5m8q3',
      username: 'ana',
      displayName: 'Ana Souza',
      papel: Papel.zelador,
      activatedAt: '2026-02-01T09:00:00Z',
      deactivatedAt: null,
      createdAt: '2026-02-01T09:00:00Z',
    );
    const joana = Ava(
      publicId: 'avaq7r2m5xk9p1',
      username: 'joana',
      displayName: 'Joana Reis',
      papel: Papel.morador,
      activatedAt: '2026-02-02T09:00:00Z',
      deactivatedAt: null,
      createdAt: '2026-02-02T09:00:00Z',
    );
    const rafael = Ava(
      publicId: 'avam4t8y2w6q0s3',
      username: 'rafael',
      displayName: 'Rafael Nunes',
      papel: Papel.morador,
      activatedAt: '2026-02-03T09:00:00Z',
      deactivatedAt: null,
      createdAt: '2026-02-03T09:00:00Z',
    );
    _avas = [ana, joana, rafael];
    // The seeded neighbor the pedido screens ask about: in the fake every
    // listed file is the person's own, so the access flow pretends she owns
    // each one.
    _neighbor = joana;

    _devices = [
      DeviceToken(
        publicId: 'devc9x2m5kq8',
        name: 'iPad da Ana',
        lastUsedAt: '2026-09-30T18:20:00Z',
        revokedAt: '2026-10-01T08:00:00Z',
        createdAt: '2026-05-12T11:00:00Z',
      ),
    ];

    const assembleia = '3kx2n8pqrv5w2';
    const festa = '3kz9t4mqc1h7d';
    _folders = [
      Folder(
        rkey: assembleia,
        cid: 'bmq2a5xw7k3p9r2t8v4z6c1d5f7h9j2x',
        name: 'Documentos da assembleia',
        zona: Zona.casa,
        folder: null,
        deletedAt: null,
        createdAt: '2026-03-10T14:00:00Z',
        updatedAt: '2026-03-10T14:00:00Z',
      ),
      Folder(
        rkey: festa,
        cid: 'bnu8b6y9l4q1s3u0w6y8d3e6g9k2m5o1p',
        name: 'Fotos da festa',
        zona: Zona.praca,
        folder: null,
        deletedAt: null,
        createdAt: '2026-06-21T20:00:00Z',
        updatedAt: '2026-06-21T20:00:00Z',
      ),
    ];

    _files = [
      FileRecord(
        rkey: '3m2a8twqpv5z2',
        cid: 'bp3q4r5s6t7u8v9w0x1y2z3a4b5c6d7e8',
        blobCid: 'bq4r5s6t7u8v9w0x1y2z3a4b5c6d7e8f9',
        sha256:
            'aa11bb22cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66',
        name: 'Estatuto da associacao.pdf',
        mime: 'application/pdf',
        size: 48213,
        zona: Zona.casa,
        folder: assembleia,
        takenAt: null,
        width: null,
        height: null,
        rendition: Rendition.none,
        deletedAt: null,
        createdAt: '2026-03-11T09:30:00Z',
        updatedAt: '2026-03-11T09:30:00Z',
      ),
      FileRecord(
        rkey: '3m5c9vxyq2b7t',
        cid: 'br4s5t6u7v8w9x0y1z2a3b4c5d6e7f8g9',
        blobCid: 'bs5t6u7v8w9x0y1z2a3b4c5d6e7f8g9h0',
        sha256:
            'bb22cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66aa11',
        name: 'Lista de presenca.pdf',
        mime: 'application/pdf',
        size: 12874,
        zona: Zona.casa,
        folder: null,
        takenAt: null,
        width: null,
        height: null,
        rendition: Rendition.none,
        deletedAt: null,
        createdAt: '2026-04-02T16:45:00Z',
        updatedAt: '2026-04-02T16:45:00Z',
      ),
      FileRecord(
        rkey: '3m7d1wyzr4c8u',
        cid: 'bt6u7v8w9x0y1z2a3b4c5d6e7f8g9h0i1',
        blobCid: 'bu7v8w9x0y1z2a3b4c5d6e7f8g9h0i1j2',
        sha256:
            'cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66aa11bb22',
        name: 'Foto da quadra.jpg',
        mime: 'image/jpeg',
        size: 1204331,
        zona: Zona.praca,
        folder: null,
        takenAt: '2026-06-21T21:12:00Z',
        width: 4032,
        height: 3024,
        rendition: Rendition.ready,
        deletedAt: null,
        createdAt: '2026-06-21T21:12:00Z',
        updatedAt: '2026-06-21T21:12:00Z',
      ),
      FileRecord(
        rkey: '3m8e2xz0s5d9v',
        cid: 'bv8w9x0y1z2a3b4c5d6e7f8g9h0i1j2k3',
        blobCid: 'bw9x0y1z2a3b4c5d6e7f8g9h0i1j2k3l4',
        sha256:
            'dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66aa11bb22cc33',
        name: 'Cartaz da festa.jpg',
        mime: 'image/jpeg',
        size: 934221,
        zona: Zona.praca,
        folder: festa,
        takenAt: null,
        width: null,
        height: null,
        rendition: Rendition.pending,
        deletedAt: null,
        createdAt: '2026-06-21T20:30:00Z',
        updatedAt: '2026-06-21T20:30:00Z',
      ),
      FileRecord(
        rkey: '3m9f4xk1q7v2n',
        cid: 'bx0y1z2a3b4c5d6e7f8g9h0i1j2k3l4m5',
        blobCid: 'by1z2a3b4c5d6e7f8g9h0i1j2k3l4m5n6',
        sha256:
            'ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66aa11bb22cc33dd44',
        name: 'Apresentacao na escola.mp4',
        mime: 'video/mp4',
        size: 52428800,
        zona: Zona.praca,
        folder: festa,
        takenAt: null,
        width: null,
        height: null,
        rendition: Rendition.none,
        deletedAt: null,
        createdAt: '2026-06-21T22:05:00Z',
        updatedAt: '2026-06-21T22:05:00Z',
      ),
    ];

    _bytes = {
      '3m2a8twqpv5z2': Uint8List.fromList(
        utf8.encode('%PDF-1.4\narquivo de teste do Tainá\n'),
      ),
      '3m5c9vxyq2b7t': Uint8List.fromList(
        utf8.encode('%PDF-1.4\narquivo de teste do Tainá\n'),
      ),
      '3m7d1wyzr4c8u': _tinyPng,
      '3m8e2xz0s5d9v': _tinyPng,
      '3m9f4xk1q7v2n': Uint8List.fromList(
        utf8.encode('vídeo de teste do Tainá'),
      ),
    };

    _receivedPedidos = [
      Pedido(
        publicId: 'ped3xk9mq2v7w4',
        tipo: 'leitura',
        recurso: '3m2a8twqpv5z2',
        motivo: 'Preciso do estatuto para a reuniao de domingo.',
        status: PedidoStatus.pendente,
        decididoEm: null,
        createdAt: '2026-10-12T10:00:00Z',
        pedinte: joana,
        dono: ana,
      ),
    ];
    _sentPedidos = [
      Pedido(
        publicId: 'ped7qm2xk4v9n1',
        tipo: 'leitura',
        recurso: '3q9p2xk5m8v1',
        motivo: 'A foto do crachá para o mural da quadra.',
        status: PedidoStatus.pendente,
        decididoEm: null,
        createdAt: '2026-10-13T15:30:00Z',
        pedinte: ana,
        dono: rafael,
      ),
      Pedido(
        publicId: 'ped9v2xk7m4q1n',
        tipo: 'leitura',
        recurso: '3r2v5xk9m8q1',
        motivo: null,
        status: PedidoStatus.aprovado,
        decididoEm: '2026-10-11T09:00:00Z',
        createdAt: '2026-10-10T09:00:00Z',
        pedinte: ana,
        dono: joana,
      ),
    ];

    // One access given (ana is the dono) and one received (ana is the leitor,
    // already revoked), so both sides of the grants tab preview with their
    // states.
    _concessoes = [
      Concessao(
        publicId: 'con3qk9mq2v7w1',
        tipo: 'leitura',
        recurso: '3m5c9vxyq2b7t',
        concedidaEm: '2026-10-10T09:00:00Z',
        revogadaEm: null,
        createdAt: '2026-10-10T09:00:00Z',
        leitor: joana,
        dono: ana,
      ),
      Concessao(
        publicId: 'con5rk2mq8v3w7',
        tipo: 'leitura',
        recurso: '3q9p2xk5m8v1',
        concedidaEm: '2026-10-11T09:00:00Z',
        revogadaEm: '2026-10-12T09:00:00Z',
        createdAt: '2026-10-11T09:00:00Z',
        leitor: ana,
        dono: rafael,
      ),
    ];

    _muralEntries = [
      MuralEntry(
        seq: 4,
        tipo: 'arquivo.publicado',
        payload: const {
          'name': JsonString('Foto da quadra.jpg'),
          'zona': JsonString('praca'),
          'size': JsonInt(1204331),
        },
        cid: 'bz8x6k4m2q9v1p3r5t7w2y4a6c8e0g2',
        prev: 'by7w5j3l1p8u0o2q4s6v1x3z5a7d9f1',
        createdAt: '2026-06-21T21:12:00Z',
      ),
      MuralEntry(
        seq: 3,
        tipo: 'pedido.aprovado',
        payload: const {
          'file': JsonString('Lista de presenca.pdf'),
          'reader': JsonString('rafael'),
          'motivo': JsonNull(),
        },
        cid: 'by7w5j3l1p8u0o2q4s6v1x3z5a7d9f1',
        prev: 'bx6v4i2k0p7t9n1p3r5u0w2y4z6c8e0g2',
        createdAt: '2026-06-21T20:45:00Z',
      ),
      MuralEntry(
        seq: 2,
        tipo: 'arquivo.criado',
        payload: const {
          'name': JsonString('Estatuto da associacao.pdf'),
          'zona': JsonString('casa'),
          'tags': JsonArray([JsonString('assembleia'), JsonString('estatuto')]),
        },
        cid: 'bx6v4i2k0p7t9n1p3r5u0w2y4z6c8e0g2',
        prev: 'bw5u3h1j9o6s8m0o2q4t9v1x3y5a7d9f1',
        createdAt: '2026-03-11T09:30:00Z',
      ),
      MuralEntry(
        seq: 1,
        tipo: 'pasta.criada',
        payload: const {
          'name': JsonString('Documentos da assembleia'),
          'zona': JsonString('casa'),
        },
        cid: 'bw5u3h1j9o6s8m0o2q4t9v1x3y5a7d9f1',
        prev: null,
        createdAt: '2026-03-10T14:00:00Z',
      ),
    ];
    _session = null;
  }

  @override
  Future<TainaResult<Instance>> instance() async {
    await _pause();
    return Ok(Instance(bootstrapped: true, tekoa: _tekoa, version: '0.6.0'));
  }

  /// Accepts any non-empty username except the literal `sem-acesso`, which
  /// answers 401 `invalid_credentials`, so the error path is previewable.
  @override
  Future<TainaResult<Session>> createSession({
    required String username,
    required String password,
    required String deviceName,
  }) async {
    await _pause();
    if (username.isEmpty) {
      return const Err(
        ApiError(
          code: 'validation_failed',
          status: 422,
          serverMessage: 'Informe seu nome de usuário.',
          details: {
            'username': ['não pode ficar em branco'],
          },
        ),
      );
    }
    if (username == 'sem-acesso') {
      return const Err(
        ApiError(
          code: 'invalid_credentials',
          status: 401,
          serverMessage: 'Usuário ou senha incorretos.',
        ),
      );
    }

    final ava = Ava(
      publicId: 'avap2xw5m8q3',
      username: username,
      displayName: null,
      papel: Papel.morador,
      activatedAt: _clock(),
      deactivatedAt: null,
      createdAt: _clock(),
    );
    return Ok(_handOut(ava, deviceName: deviceName));
  }

  /// The light read the invite screen opens with. Everything counts except
  /// the literal `expirado`, which answers 401 `invalid_token`, so the dead
  /// end previews; a real token is single use and the box still re-checks it
  /// on the submit.
  @override
  Future<TainaResult<TokenStatus>> inviteStatus({required String token}) async {
    await _pause();
    if (!_counts(token)) {
      return const Err(_invalidToken);
    }
    return const Ok(TokenStatus(valid: true));
  }

  /// Accepts like the box: the token first (401 for a dead link), the
  /// username required (422 for an empty one), and the account is born with
  /// the session in the same hand the login gets.
  @override
  Future<TainaResult<Session>> acceptInvite({
    required String token,
    required String username,
    required String password,
    String? displayName,
    required String deviceName,
  }) async {
    await _pause();
    if (!_counts(token)) {
      return const Err(_invalidToken);
    }
    if (username.isEmpty) {
      return const Err(
        ApiError(
          code: 'validation_failed',
          status: 422,
          serverMessage: 'Informe seu nome de usuário.',
          details: {
            'username': ['não pode ficar em branco'],
          },
        ),
      );
    }
    final ava = Ava(
      publicId: 'avap2xw5m8q3',
      username: username,
      displayName: displayName,
      papel: Papel.morador,
      activatedAt: _clock(),
      deactivatedAt: null,
      createdAt: _clock(),
    );
    return Ok(_handOut(ava, deviceName: deviceName));
  }

  /// The same light read, for the reset link.
  @override
  Future<TainaResult<TokenStatus>> resetStatus({required String token}) async {
    await _pause();
    if (!_counts(token)) {
      return const Err(_invalidToken);
    }
    return const Ok(TokenStatus(valid: true));
  }

  /// The reset signs the moradora the link belongs to in; the fake keeps no
  /// passwords, so any live token opens her session.
  @override
  Future<TainaResult<Session>> resetPassword({
    required String token,
    required String password,
    required String deviceName,
  }) async {
    await _pause();
    if (!_counts(token)) {
      return const Err(_invalidToken);
    }
    return Ok(_handOut(_neighbor, deviceName: deviceName));
  }

  @override
  Future<TainaResult<void>> revokeSession() async {
    await _pause();
    if (_session == null) {
      return const Err(_unauthorized);
    }
    _session = null;
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<Me>> me() async {
    await _pause();
    final current = _session;
    if (current == null) {
      return const Err(_unauthorized);
    }
    return Ok(
      Me(ava: current.me, tekoa: current.tekoa, device: current.device),
    );
  }

  /// The person's own devices, most recent first.
  @override
  Future<TainaResult<List<DeviceToken>>> devices() async {
    await _pause();
    return Ok(List.unmodifiable(_devices));
  }

  /// Revoking is idempotent: a device already revoked stays as is.
  @override
  Future<TainaResult<void>> revokeDevice({required String id}) async {
    await _pause();
    final index = _devices.indexWhere((device) => device.publicId == id);
    if (index < 0) {
      return const Err(
        ApiError(
          code: 'not_found',
          status: 404,
          serverMessage: 'Não encontramos este aparelho.',
        ),
      );
    }
    if (_devices[index].revokedAt == null) {
      final device = _devices[index];
      _devices[index] = DeviceToken(
        publicId: device.publicId,
        name: device.name,
        lastUsedAt: device.lastUsedAt,
        revokedAt: _clock(),
        createdAt: device.createdAt,
      );
    }
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<List<Folder>>> listFolders() async {
    await _pause();
    return Ok(
      List.unmodifiable(_folders.where((folder) => folder.deletedAt == null)),
    );
  }

  @override
  Future<TainaResult<Folder>> folder({required String rkey}) async {
    await _pause();
    final folder = _folders.where((folder) => folder.rkey == rkey).firstOrNull;
    if (folder == null) {
      return const Err(_notFoundFolder);
    }
    return Ok(folder);
  }

  /// Renames, publishes to the praca or brings back to the casa; each act is
  /// its own call, like on the box.
  @override
  Future<TainaResult<Folder>> updateFolder({
    required String rkey,
    String? name,
    Zona? zona,
  }) async {
    await _pause();
    final index = _folders.indexWhere((folder) => folder.rkey == rkey);
    if (index < 0) {
      return const Err(_notFoundFolder);
    }
    final current = _folders[index];
    final updated = Folder(
      rkey: current.rkey,
      cid: current.cid,
      name: name ?? current.name,
      zona: zona ?? current.zona,
      folder: current.folder,
      deletedAt: current.deletedAt,
      createdAt: current.createdAt,
      updatedAt: _clock(),
    );
    _folders[index] = updated;
    return Ok(updated);
  }

  @override
  Future<TainaResult<Folder>> moveFolder({
    required String rkey,
    String? parentRkey,
  }) async {
    await _pause();
    final index = _folders.indexWhere((folder) => folder.rkey == rkey);
    if (index < 0) {
      return const Err(_notFoundFolder);
    }
    if (parentRkey != null &&
        !_folders.any((folder) => folder.rkey == parentRkey)) {
      return const Err(_notFoundFolder);
    }
    if (cycles(rkey: rkey, into: parentRkey, folders: _folders)) {
      return const Err(
        ApiError(
          code: 'cycle',
          status: 409,
          serverMessage: 'A pasta não pode ficar dentro dela mesma.',
        ),
      );
    }
    final current = _folders[index];
    final moved = Folder(
      rkey: current.rkey,
      cid: current.cid,
      name: current.name,
      zona: current.zona,
      folder: parentRkey,
      deletedAt: current.deletedAt,
      createdAt: current.createdAt,
      updatedAt: _clock(),
    );
    _folders[index] = moved;
    return Ok(moved);
  }

  /// Soft deletes the whole subtree: the folder, the folders inside it and
  /// every file they hold.
  @override
  Future<TainaResult<void>> deleteFolder({required String rkey}) async {
    await _pause();
    if (!_folders.any((folder) => folder.rkey == rkey)) {
      return const Err(_notFoundFolder);
    }
    final subtree = subtreeRkeys(of: rkey, inFolders: _folders);
    final now = _clock();
    _folders = [
      for (final folder in _folders)
        if (!subtree.contains(folder.rkey))
          folder
        else
          Folder(
            rkey: folder.rkey,
            cid: folder.cid,
            name: folder.name,
            zona: folder.zona,
            folder: folder.folder,
            deletedAt: now,
            createdAt: folder.createdAt,
            updatedAt: now,
          ),
    ];
    _files = [
      for (final file in _files)
        if (file.folder != null && subtree.contains(file.folder))
          _stamping(file, deletedAt: now, updatedAt: now)
        else
          file,
    ];
    return const Ok<void>(null);
  }

  /// Folders are born in the casa; publishing to the praca is a separate act,
  /// so the fake never creates a praca folder here.
  @override
  Future<TainaResult<Folder>> createFolder({
    required String name,
    String? parentRkey,
  }) async {
    await _pause();
    if (name.isEmpty) {
      return const Err(
        ApiError(
          code: 'validation_failed',
          status: 422,
          serverMessage: 'Informe o nome da pasta.',
          details: {
            'name': ['não pode ficar em branco'],
          },
        ),
      );
    }
    final now = _clock();
    final folder = Folder(
      rkey: _nextRkey(),
      cid: _nextCid(),
      name: name,
      zona: Zona.casa,
      folder: parentRkey,
      deletedAt: null,
      createdAt: now,
      updatedAt: now,
    );
    _folders.add(folder);
    return Ok(folder);
  }

  @override
  Future<TainaResult<FolderContents>> folderContents({
    String? folderRkey,
    int? limit,
    String? cursor,
    Sort? sort,
  }) async {
    await _pause();
    final inside = _folders
        .where(
          (folder) => folder.folder == folderRkey && folder.deletedAt == null,
        )
        .toList();
    final items = _files
        .where((file) => file.folder == folderRkey && file.deletedAt == null)
        .toList();
    return Ok(FolderContents(folders: inside, items: items, nextCursor: null));
  }

  @override
  Future<TainaResult<FileRecord>> upload({
    required String filePath,
    required String name,
    required String mime,
    String? folderRkey,
  }) async {
    await _pause();
    var zona = Zona.casa;
    if (folderRkey != null) {
      final folder = _folders
          .where((folder) => folder.rkey == folderRkey)
          .firstOrNull;
      if (folder == null) {
        return const Err(
          ApiError(
            code: 'not_found',
            status: 404,
            serverMessage: 'Não encontramos esta pasta.',
          ),
        );
      }
      zona = folder.zona;
    }

    final file = io.File(filePath);
    final size = file.existsSync() ? file.lengthSync() : 0;
    final now = _clock();
    final record = FileRecord(
      rkey: _nextRkey(),
      cid: _nextCid(),
      blobCid: _nextCid(),
      sha256: _randomHex(64),
      name: name,
      mime: mime,
      size: size,
      zona: zona,
      folder: folderRkey,
      takenAt: null,
      width: null,
      height: null,
      // A fresh upload has no rendition row yet: pending is the honest state
      // for an image, none for the rest.
      rendition: mime.startsWith('image/') ? Rendition.pending : Rendition.none,
      deletedAt: null,
      createdAt: now,
      updatedAt: now,
    );
    _files.add(record);
    try {
      _bytes[record.rkey] = file.readAsBytesSync();
    } on io.FileSystemException {
      _bytes[record.rkey] = Uint8List(0);
    }
    return Ok(record);
  }

  @override
  Future<TainaResult<FileRecord>> file({required String rkey}) async {
    await _pause();
    final file = _files.where((file) => file.rkey == rkey).firstOrNull;
    if (file == null) {
      return const Err(_notFoundFile);
    }
    return Ok(file);
  }

  @override
  Future<TainaResult<FileRecord>> updateFile({
    required String rkey,
    String? name,
    Zona? zona,
  }) async {
    await _pause();
    final index = _files.indexWhere((file) => file.rkey == rkey);
    if (index < 0) {
      return const Err(_notFoundFile);
    }
    final current = _files[index];
    final updated = FileRecord(
      rkey: current.rkey,
      cid: current.cid,
      blobCid: current.blobCid,
      sha256: current.sha256,
      name: name ?? current.name,
      mime: current.mime,
      size: current.size,
      zona: zona ?? current.zona,
      folder: current.folder,
      takenAt: current.takenAt,
      width: current.width,
      height: current.height,
      rendition: current.rendition,
      deletedAt: current.deletedAt,
      createdAt: current.createdAt,
      updatedAt: _clock(),
    );
    _files[index] = updated;
    return Ok(updated);
  }

  @override
  Future<TainaResult<FileRecord>> moveFile({
    required String rkey,
    String? folderRkey,
  }) async {
    await _pause();
    return _perform(op: BatchOp.move, rkey: rkey, folderRkey: folderRkey);
  }

  /// The file goes to the trash, from where only its owner restores it.
  @override
  Future<TainaResult<void>> deleteFile({required String rkey}) async {
    await _pause();
    return _perform(
      op: BatchOp.trash,
      rkey: rkey,
      folderRkey: null,
    ).map((_) {});
  }

  @override
  Future<TainaResult<Page<FileRecord>>> recent({int? limit}) async {
    await _pause();
    final readable = _files.where((file) => file.deletedAt == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Ok(Page.slice(readable, limit: limit));
  }

  @override
  Future<TainaResult<String>> download({required String rkey}) async {
    await _pause();
    final file = _files.where((file) => file.rkey == rkey).firstOrNull;
    if (file == null) {
      return const Err(
        ApiError(
          code: 'not_found',
          status: 404,
          serverMessage: 'Não encontramos este arquivo.',
        ),
      );
    }
    final target =
        '${io.Directory.systemTemp.path}/${_randomHex(32)}-${file.name}';
    try {
      await io.File(target).writeAsBytes(_bytes[file.rkey] ?? Uint8List(0));
      return Ok(target);
    } on io.FileSystemException catch (error) {
      return Err(
        NetworkError('could not write the downloaded file: ${error.message}'),
      );
    }
  }

  /// A tiny PNG for the images the fake knows, and a 404 for everything else,
  /// so the missing-thumbnail path is exercised in previews.
  @override
  Future<TainaResult<Uint8List>> thumbnail({
    required String rkey,
    required ThumbnailSize size,
  }) async {
    await _pause();
    final file = _files.where((file) => file.rkey == rkey).firstOrNull;
    final payload = _bytes[rkey];
    if (file == null || !file.mime.startsWith('image/') || payload == null) {
      return const Err(
        ApiError(
          code: 'not_found',
          status: 404,
          serverMessage: 'Este arquivo não tem miniatura.',
        ),
      );
    }
    return Ok(payload);
  }

  @override
  Future<TainaResult<Page<FileRecord>>> trash({
    int? limit,
    String? cursor,
  }) async {
    await _pause();
    final discarded = _files.where((file) => file.deletedAt != null).toList()
      ..sort((a, b) => (b.deletedAt ?? '').compareTo(a.deletedAt ?? ''));
    return Ok(Page.slice(discarded, limit: limit, cursor: cursor));
  }

  @override
  Future<TainaResult<FileRecord>> restoreFile({required String rkey}) async {
    await _pause();
    return _perform(op: BatchOp.restore, rkey: rkey, folderRkey: null);
  }

  @override
  Future<TainaResult<Page<FileRecord>>> manifest({
    String? after,
    int? limit,
  }) async {
    await _pause();
    final readable = _files.where((file) => file.deletedAt == null).toList()
      ..sort((a, b) => a.rkey.compareTo(b.rkey));
    final rest = after == null
        ? readable
        : readable.where((file) => file.rkey.compareTo(after) > 0).toList();
    // The manifest's own bounds: 200 by default, never past 1000, walking by
    // the rkey itself and not by an offset.
    final size = min(max(limit ?? 200, 1), 1000);
    final page = rest.take(size).toList();
    final next = page.length < rest.length ? page.last.rkey : null;
    return Ok(Page(items: page, nextCursor: next));
  }

  /// The batch answers 200 even when items fail: each id runs through the
  /// same context call the single-item endpoint uses, and the outcome list
  /// says what became of each one.
  @override
  Future<TainaResult<List<BatchOutcome>>> batch({
    required BatchOp op,
    required List<String> ids,
    String? folderRkey,
  }) async {
    await _pause();
    if (ids.length > 200) {
      return const Err(
        ApiError(
          code: 'validation_failed',
          status: 422,
          serverMessage: 'A lista tem arquivos demais.',
          details: {
            'ids': ['no máximo 200 por vez'],
          },
        ),
      );
    }
    return Ok([
      for (final rkey in ids)
        switch (_perform(op: op, rkey: rkey, folderRkey: folderRkey)) {
          Ok(:final value) => BatchOutcome(
            rkey: rkey,
            ok: true,
            file: value,
            error: null,
          ),
          Err(:final error) => BatchOutcome(
            rkey: rkey,
            ok: false,
            file: null,
            error: codeOf(error),
          ),
        },
    ]);
  }

  @override
  Future<TainaResult<Page<FileRecord>>> photos({
    int? limit,
    String? cursor,
  }) async {
    await _pause();
    return Ok(Page.slice(_visual(_files), limit: limit, cursor: cursor));
  }

  @override
  Future<TainaResult<Page<TimelineGroup>>> photoTimeline({
    int? limit,
    String? cursor,
  }) async {
    await _pause();
    final days = timelineGroups(_visual(_files));
    return Ok(Page.slice(days, limit: limit, cursor: cursor));
  }

  @override
  Future<TainaResult<AccessTarget>> accessTarget({
    required String fileRkey,
  }) async {
    await _pause();
    final file = _files.where((file) => file.rkey == fileRkey).firstOrNull;
    if (file == null) {
      return const Err(_notFoundFile);
    }
    return Ok(AccessTarget(owner: _neighbor, rkey: file.rkey, name: file.name));
  }

  /// The pedido registers the question; it grants nothing.
  @override
  Future<TainaResult<Pedido>> requestAccess({
    required String fileRkey,
    String? motivo,
  }) async {
    await _pause();
    final file = _files.where((file) => file.rkey == fileRkey).firstOrNull;
    if (file == null) {
      return const Err(_notFoundFile);
    }
    final now = _clock();
    final pedido = Pedido(
      publicId: 'ped${_randomHex(9)}',
      tipo: 'leitura',
      recurso: file.rkey,
      motivo: motivo,
      status: PedidoStatus.pendente,
      decididoEm: null,
      createdAt: now,
      pedinte: _session?.me ?? _avas[0],
      dono: _neighbor,
    );
    _sentPedidos.insert(0, pedido);
    return Ok(pedido);
  }

  @override
  Future<TainaResult<Page<Pedido>>> accessRequests() async {
    await _pause();
    return Ok(Page(items: _receivedPedidos, nextCursor: null));
  }

  @override
  Future<TainaResult<Page<Pedido>>> myRequests() async {
    await _pause();
    return Ok(Page(items: _sentPedidos, nextCursor: null));
  }

  /// Approving grants the read: the concessao is born and the pedido closes.
  /// A pedido decided once cannot be decided again.
  @override
  Future<TainaResult<Concessao>> approveRequest({required String id}) async {
    await _pause();
    return switch (_decide(id: id, status: PedidoStatus.aprovado)) {
      Ok(:final value) => Ok(
        Concessao(
          publicId: 'con${_randomHex(9)}',
          tipo: value.tipo,
          recurso: value.recurso,
          concedidaEm: value.decididoEm,
          revogadaEm: null,
          createdAt: _clock(),
          leitor: value.pedinte,
          dono: value.dono,
        ),
      ),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<TainaResult<Pedido>> denyRequest({required String id}) async {
    await _pause();
    return _decide(id: id, status: PedidoStatus.negado);
  }

  @override
  Future<TainaResult<Page<MuralEntry>>> mural({
    int? limit,
    String? cursor,
  }) async {
    await _pause();
    return Ok(Page.slice(_muralEntries, limit: limit, cursor: cursor));
  }

  @override
  Future<TainaResult<StorageStats>> storage() async {
    await _pause();
    return Ok(stats(_files, quotaBytes: _tekoa.storageQuotaBytes));
  }

  @override
  Future<TainaResult<Saude>> saude() async {
    await _pause();
    return Ok(
      Saude(
        storage: stats(_files, quotaBytes: _tekoa.storageQuotaBytes),
        jobs: const {'renditions': 0, 'backups': 0},
        backup: const SaudeBackup(
          at: '2026-10-14T03:00:00Z',
          bytes: 1829000000,
        ),
      ),
    );
  }

  @override
  Future<TainaResult<Page<Ava>>> members() async {
    await _pause();
    // The box lists the zeladoras first.
    final ordered = [..._avas]
      ..sort((lhs, rhs) {
        if (lhs.papel != rhs.papel) {
          return lhs.papel == Papel.zelador ? -1 : 1;
        }
        return lhs.label.compareTo(rhs.label);
      });
    return Ok(Page(items: ordered, nextCursor: null));
  }

  @override
  Future<TainaResult<Page<Concessao>>> grants({required GrantRole role}) async {
    await _pause();
    return Ok(
      Page(
        items: grantsFor(_concessoes, _session?.me.publicId, role),
        nextCursor: null,
      ),
    );
  }

  /// Revoking is the dono's act, once: a second revoke is a conflict, like
  /// the box answers.
  @override
  Future<TainaResult<void>> revokeGrant({required String id}) async {
    await _pause();
    final index = _concessoes.indexWhere(
      (concessao) => concessao.publicId == id,
    );
    if (index < 0) {
      return const Err(_notFoundGrant);
    }
    if (_concessoes[index].revogadaEm != null) {
      return const Err(
        ApiError(
          code: 'invalid_status',
          status: 409,
          serverMessage: 'Este acesso já foi revogado.',
        ),
      );
    }
    final current = _concessoes[index];
    _concessoes[index] = Concessao(
      publicId: current.publicId,
      tipo: current.tipo,
      recurso: current.recurso,
      concedidaEm: current.concedidaEm,
      revogadaEm: _clock(),
      createdAt: current.createdAt,
      leitor: current.leitor,
      dono: current.dono,
    );
    return const Ok<void>(null);
  }

  /// Mints the invite and keeps the pending person on the roster: the
  /// username arrives when the invite is accepted.
  @override
  Future<TainaResult<MemberInvite>> inviteMember({required Papel papel}) async {
    await _pause();
    final token = 'tk${_randomHex(14)}';
    final invited = Ava(
      publicId: 'ava${_randomHex(9)}',
      username: null,
      displayName: null,
      papel: papel,
      activatedAt: null,
      deactivatedAt: null,
      createdAt: _clock(),
    );
    _avas.add(invited);
    return Ok(
      MemberInvite(
        ava: invited,
        token: token,
        inviteUrl: 'taina://convite/$token?host=${_tekoa.domain}',
      ),
    );
  }

  /// The role change, with the one conflict the box enforces: the last
  /// zeladora cannot step down.
  @override
  Future<TainaResult<Ava>> updateMember({
    required String id,
    required Papel papel,
  }) async {
    await _pause();
    final index = _avas.indexWhere((ava) => ava.publicId == id);
    if (index < 0) {
      return const Err(_notFoundMember);
    }
    if (papel == Papel.morador &&
        _avas[index].papel == Papel.zelador &&
        !_avas.any(
          (ava) =>
              ava.publicId != id &&
              ava.papel == Papel.zelador &&
              ava.deactivatedAt == null,
        )) {
      return const Err(
        ApiError(
          code: 'last_zelador',
          status: 409,
          serverMessage:
              'Não dá para deixar a comunidade sem ninguém para cuidar dela.',
        ),
      );
    }
    _avas[index] = _rewriting(
      _avas[index],
      papel: papel,
      deactivatedAt: _avas[index].deactivatedAt,
    );
    return Ok(_avas[index]);
  }

  @override
  Future<TainaResult<void>> deactivateMember({required String id}) async {
    await _pause();
    final index = _avas.indexWhere((ava) => ava.publicId == id);
    if (index < 0) {
      return const Err(_notFoundMember);
    }
    if (_avas[index].deactivatedAt != null) {
      return const Err(
        ApiError(
          code: 'invalid_status',
          status: 409,
          serverMessage: 'Esta conta já está desativada.',
        ),
      );
    }
    _avas[index] = _rewriting(_avas[index], deactivatedAt: _clock());
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<Ava>> reactivateMember({required String id}) async {
    await _pause();
    final index = _avas.indexWhere((ava) => ava.publicId == id);
    if (index < 0) {
      return const Err(_notFoundMember);
    }
    if (_avas[index].deactivatedAt == null) {
      return const Err(
        ApiError(
          code: 'invalid_status',
          status: 409,
          serverMessage: 'Esta conta já está ativa.',
        ),
      );
    }
    _avas[index] = _rewriting(_avas[index], deactivatedAt: null);
    return Ok(_avas[index]);
  }

  /// Takes a pending invite back: an accepted account is a member, not an
  /// invite, and answers conflict here.
  @override
  Future<TainaResult<void>> revokeInvite({required String id}) async {
    await _pause();
    final index = _avas.indexWhere((ava) => ava.publicId == id);
    if (index < 0) {
      return const Err(_notFoundMember);
    }
    if (_avas[index].username != null || _avas[index].activatedAt != null) {
      return const Err(
        ApiError(
          code: 'not_pending',
          status: 409,
          serverMessage: 'Este convite já foi aceito.',
        ),
      );
    }
    _avas.removeAt(index);
    return const Ok<void>(null);
  }

  /// The reset link of one morador. The token is shown once; the delivery is
  /// human, so the screen copies the deep link and hands it over.
  @override
  Future<TainaResult<ResetLink>> memberResetLink({required String id}) async {
    await _pause();
    final member = _avas.where((ava) => ava.publicId == id).firstOrNull;
    if (member == null) {
      return const Err(_notFoundMember);
    }
    final token = 'tk${_randomHex(14)}';
    return Ok(
      ResetLink(
        ava: member,
        token: token,
        resetUrl: 'taina://redefinir/$token?host=${_tekoa.domain}',
      ),
    );
  }

  @override
  Future<TainaResult<Tekoa>> setQuota({required int bytes}) async {
    await _pause();
    if (bytes < 1) {
      return const Err(
        ApiError(
          code: 'validation_failed',
          status: 422,
          serverMessage: 'O limite precisa ser maior que zero.',
          details: {
            'quota_bytes': ['tem que ser maior que zero'],
          },
        ),
      );
    }
    _tekoa = Tekoa(
      publicId: _tekoa.publicId,
      name: _tekoa.name,
      domain: _tekoa.domain,
      storageQuotaBytes: bytes,
      storageUsedBytes: _tekoa.storageUsedBytes,
      createdAt: _tekoa.createdAt,
    );
    return Ok(_tekoa);
  }

  /// The box answers 202: the backup is queued, not done.
  @override
  Future<TainaResult<void>> triggerBackup() async {
    await _pause();
    return const Ok<void>(null);
  }

  /// The fake keeps no passwords, so the current one is never checked except
  /// by the literals the previews rely on: `errada` answers the 403 of a
  /// wrong current, `curta` answers the 422 of a weak new.
  @override
  Future<TainaResult<void>> updatePassword({
    required String current,
    required String newPassword,
  }) async {
    await _pause();
    if (current == 'errada') {
      return const Err(
        ApiError(
          code: 'invalid_credentials',
          status: 403,
          serverMessage: 'A senha atual não confere.',
        ),
      );
    }
    if (newPassword == 'curta') {
      return const Err(
        ApiError(
          code: 'validation_failed',
          status: 422,
          serverMessage: 'A senha nova precisa de mais caracteres.',
          details: {
            'new_password': ['é muito curta'],
          },
        ),
      );
    }
    return const Ok<void>(null);
  }

  // MARK: internals

  /// The one context call a batch item shares with the single-item endpoint,
  /// without the pause: trash, restore, move, publish and unpublish, each
  /// mutating only this record.
  TainaResult<FileRecord> _perform({
    required BatchOp op,
    required String rkey,
    String? folderRkey,
  }) {
    final index = _files.indexWhere((file) => file.rkey == rkey);
    if (index < 0) {
      return const Err(_notFoundFile);
    }
    if (op == BatchOp.move &&
        folderRkey != null &&
        !_folders.any((folder) => folder.rkey == folderRkey)) {
      return const Err(_notFoundFolder);
    }
    final current = _files[index];
    final now = _clock();
    final changed = FileRecord(
      rkey: current.rkey,
      cid: current.cid,
      blobCid: current.blobCid,
      sha256: current.sha256,
      name: current.name,
      mime: current.mime,
      size: current.size,
      zona: switch (op) {
        BatchOp.publish => Zona.praca,
        BatchOp.unpublish => Zona.casa,
        _ => current.zona,
      },
      folder: op == BatchOp.move ? folderRkey : current.folder,
      takenAt: current.takenAt,
      width: current.width,
      height: current.height,
      rendition: current.rendition,
      deletedAt: switch (op) {
        BatchOp.trash => now,
        BatchOp.restore => null,
        _ => current.deletedAt,
      },
      createdAt: current.createdAt,
      updatedAt: now,
    );
    _files[index] = changed;
    return Ok(changed);
  }

  static const ApiError _unauthorized = ApiError(
    code: 'not_authenticated',
    status: 401,
    serverMessage: 'Entre na sua conta para continuar.',
  );

  static const ApiError _invalidToken = ApiError(
    code: 'invalid_token',
    status: 401,
    serverMessage:
        'Este link não vale mais. Peça um novo a quem cuida da comunidade.',
  );

  /// The fake's token rule: only the literal `expirado` is a dead link and
  /// nothing counts without a token.
  bool _counts(String token) => token.isNotEmpty && token != 'expirado';

  /// The session the fake hands out, the way login, invite and reset all
  /// create one: a fresh device, a raw token shown once, stored here.
  Session _handOut(Ava ava, {required String deviceName}) {
    final now = _clock();
    final device = DeviceToken(
      publicId: 'devp2xw5m8q3',
      name: deviceName.isEmpty ? 'Dispositivo' : deviceName,
      lastUsedAt: now,
      revokedAt: null,
      createdAt: now,
    );
    final created = Session(
      token: 'tnd_${_randomHex(32)}',
      device: device,
      me: ava,
      tekoa: _tekoa,
    );
    _devices.insert(0, device);
    _session = created;
    return created;
  }

  static const ApiError _notFoundFolder = ApiError(
    code: 'not_found',
    status: 404,
    serverMessage: 'Não encontramos esta pasta.',
  );

  static const ApiError _notFoundFile = ApiError(
    code: 'not_found',
    status: 404,
    serverMessage: 'Não encontramos este arquivo.',
  );

  static const ApiError _notFoundMember = ApiError(
    code: 'not_found',
    status: 404,
    serverMessage: 'Não encontramos esta pessoa.',
  );

  static const ApiError _notFoundGrant = ApiError(
    code: 'not_found',
    status: 404,
    serverMessage: 'Não encontramos este acesso.',
  );

  /// The grants of one role: the caller as dono for the ones she gave, as
  /// leitor for the ones she received. Pure.
  static List<Concessao> grantsFor(
    List<Concessao> all,
    String? publicId,
    GrantRole role,
  ) {
    if (publicId == null) return const [];
    return [
      for (final concessao in all)
        if (switch (role) {
          GrantRole.owner => concessao.dono?.publicId == publicId,
          GrantRole.reader => concessao.leitor?.publicId == publicId,
        })
          concessao,
    ];
  }

  /// The record with the fields a person's act changes. Pure.
  static Ava _rewriting(Ava ava, {Papel? papel, String? deactivatedAt}) {
    return Ava(
      publicId: ava.publicId,
      username: ava.username,
      displayName: ava.displayName,
      papel: papel ?? ava.papel,
      activatedAt: ava.activatedAt,
      deactivatedAt: deactivatedAt,
      createdAt: ava.createdAt,
    );
  }

  /// The wire code of a failure, for the batch's per-item answers. Pure.
  static String codeOf(TainaError error) => switch (error) {
    ApiError(:final code) => code,
    _ => 'internal_error',
  };

  /// Decides a received pedido, once: a second decision is a conflict, like
  /// the box answers.
  TainaResult<Pedido> _decide({
    required String id,
    required PedidoStatus status,
  }) {
    final index = _receivedPedidos.indexWhere(
      (pedido) => pedido.publicId == id,
    );
    if (index < 0) {
      return const Err(
        ApiError(
          code: 'not_found',
          status: 404,
          serverMessage: 'Não encontramos este pedido.',
        ),
      );
    }
    if (_receivedPedidos[index].status != PedidoStatus.pendente) {
      return const Err(
        ApiError(
          code: 'already_decided',
          status: 409,
          serverMessage: 'Este pedido já foi decidido.',
        ),
      );
    }
    final pedido = _receivedPedidos[index];
    final decided = Pedido(
      publicId: pedido.publicId,
      tipo: pedido.tipo,
      recurso: pedido.recurso,
      motivo: pedido.motivo,
      status: status,
      decididoEm: _clock(),
      createdAt: pedido.createdAt,
      pedinte: pedido.pedinte,
      dono: pedido.dono,
    );
    _receivedPedidos[index] = decided;
    return Ok(decided);
  }

  /// The record with its trash state and clock restamped. Pure.
  static FileRecord _stamping(
    FileRecord file, {
    required String? deletedAt,
    required String updatedAt,
  }) {
    return FileRecord(
      rkey: file.rkey,
      cid: file.cid,
      blobCid: file.blobCid,
      sha256: file.sha256,
      name: file.name,
      mime: file.mime,
      size: file.size,
      zona: file.zona,
      folder: file.folder,
      takenAt: file.takenAt,
      width: file.width,
      height: file.height,
      rendition: file.rendition,
      deletedAt: deletedAt,
      createdAt: file.createdAt,
      updatedAt: updatedAt,
    );
  }

  /// The photos and videos still among the living, newest first. Pure.
  static List<FileRecord> _visual(List<FileRecord> files) {
    return files
        .where(
          (file) =>
              file.deletedAt == null &&
              (file.mime.startsWith('image/') ||
                  file.mime.startsWith('video/')),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Groups the files into days, newest first: the day is the date prefix of
  /// the wire clock, like the box reads the effective date. Pure.
  static List<TimelineGroup> timelineGroups(List<FileRecord> files) {
    final days = <String>[];
    final byDay = <String, List<FileRecord>>{};
    final sorted = [...files]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final file in sorted) {
      final day = file.createdAt.substring(0, min(10, file.createdAt.length));
      if (!byDay.containsKey(day)) {
        days.add(day);
      }
      (byDay[day] ??= []).add(file);
    }
    return [
      for (final day in days) TimelineGroup(date: day, photos: byDay[day]!),
    ];
  }

  /// True when moving [rkey] into [parentRkey] would close a cycle: the new
  /// parent is the folder itself or one of the folders above it. Pure.
  static bool cycles({
    required String rkey,
    required String? into,
    required List<Folder> folders,
  }) {
    var current = into;
    while (current != null) {
      if (current == rkey) return true;
      current = folders
          .where((folder) => folder.rkey == current)
          .firstOrNull
          ?.folder;
    }
    return false;
  }

  /// The folder and every folder below it, however deep. Pure.
  static Set<String> subtreeRkeys({
    required String of,
    required List<Folder> inFolders,
  }) {
    final subtree = <String>{of};
    var growing = true;
    while (growing) {
      growing = false;
      for (final folder in inFolders) {
        final parent = folder.folder;
        if (parent != null &&
            subtree.contains(parent) &&
            !subtree.contains(folder.rkey)) {
          subtree.add(folder.rkey);
          growing = true;
        }
      }
    }
    return subtree;
  }

  /// The storage portrait read straight from the records: bytes by kind,
  /// counts, and what the trash holds right now. Pure.
  static StorageStats stats(List<FileRecord> files, {int? quotaBytes}) {
    final alive = files.where((file) => file.deletedAt == null);
    final discarded = files.where((file) => file.deletedAt != null).toList();

    var photoBytes = 0;
    var videoBytes = 0;
    var documentBytes = 0;
    var otherBytes = 0;
    for (final file in alive) {
      if (file.mime.startsWith('image/')) {
        photoBytes += file.size;
      } else if (file.mime.startsWith('video/')) {
        videoBytes += file.size;
      } else if (file.mime.startsWith('application/')) {
        documentBytes += file.size;
      } else {
        otherBytes += file.size;
      }
    }

    return StorageStats(
      usedBytes: photoBytes + videoBytes + documentBytes + otherBytes,
      quotaBytes: quotaBytes,
      byKind: StorageByKind(
        photos: photoBytes,
        videos: videoBytes,
        documents: documentBytes,
        others: otherBytes,
      ),
      files: alive.length,
      photos: alive.where((file) => file.mime.startsWith('image/')).length,
      trash: StorageTrash(
        count: discarded.length,
        bytes: discarded.fold(0, (sum, file) => sum + file.size),
      ),
    );
  }

  static final Uint8List _tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  Future<void> _pause() async {
    if (delay.inMicroseconds > 0) {
      await Future<void>.delayed(delay);
    }
  }

  /// The wire clock: ISO 8601 with a UTC offset, like the server sends.
  String _clock() {
    return DateTime.now().toUtc().toIso8601String().replaceFirst(
      RegExp(r'\.\d+'),
      '',
    );
  }

  String _nextRkey() {
    _counter += 1;
    var value = _counter;
    final chars = <String>[];
    while (chars.length < 13) {
      chars.add('234567abcdefghijklmnopqrstuvwxyz'[value % 32]);
      value ~/= 32;
    }
    return chars.join();
  }

  String _nextCid() => 'b${_randomHex(32)}';

  final Random _random = Random();

  String _randomHex(int count) {
    const digits = '0123456789abcdef';
    return String.fromCharCodes([
      for (var index = 0; index < count; index++)
        digits.codeUnitAt(_random.nextInt(16)),
    ]);
  }
}
