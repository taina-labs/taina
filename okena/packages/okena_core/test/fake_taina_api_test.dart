import 'dart:io';

import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

FakeTainaApi fake() => FakeTainaApi(delay: Duration.zero);

const assembleiaRkey = '3kx2n8pqrv5w2';
const estatutoRkey = '3m2a8twqpv5z2';

Future<File> tempUpload(String contents) async {
  final file = File(
    '${Directory.systemTemp.path}/fake-upload-${DateTime.now().microsecondsSinceEpoch}-'
    '${contents.hashCode}.pdf',
  );
  await file.writeAsString(contents);
  return file;
}

ApiError apiErrorOf(TainaResult<Object?> result) {
  final error = result.error;
  expect(error, isA<ApiError>());
  return error as ApiError;
}

void main() {
  test('login then contents returns the seeded folders', () async {
    final api = fake();

    final session = (await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'iPhone da Ana',
    )).value!;
    expect(session.token, startsWith('tnd_'));
    expect(session.token.length, 'tnd_'.length + 32);
    expect(session.me.username, 'ana');
    expect(session.tekoa.name, 'Tekoa Sapukai');

    final contents = (await api.folderContents()).value!;
    expect(contents.folders.map((folder) => folder.name), [
      'Documentos da assembleia',
      'Fotos da festa',
    ]);
    expect(contents.items.length, 2);

    expect((await api.me()).value!.ava.username, 'ana');
  });

  test(
    'sem-acesso answers 401 and the empty username a validation failure',
    () async {
      final unauthorized = apiErrorOf(
        await fake().createSession(
          username: 'sem-acesso',
          password: 'x',
          deviceName: 'Teste',
        ),
      );
      expect(unauthorized.isUnauthorized, isTrue);
      expect(unauthorized.code, 'invalid_credentials');
      expect(unauthorized.message, isNotEmpty);

      final validation = apiErrorOf(
        await fake().createSession(
          username: '',
          password: 'x',
          deviceName: 'Teste',
        ),
      );
      expect(validation.isValidationFailed, isTrue);
    },
  );

  test('upload grows the folder', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );

    final before = (await api.folderContents(folderRkey: assembleiaRkey))
        .value!;
    expect(before.items.length, 1);

    final source = await tempUpload('%PDF-1.4\nregimento\n');
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });

    final uploaded = (await api.upload(
      filePath: source.path,
      name: 'regimento.pdf',
      mime: 'application/pdf',
      folderRkey: assembleiaRkey,
    )).value!;
    expect(uploaded.name, 'regimento.pdf');
    expect(uploaded.zona, Zona.casa);
    expect(uploaded.folder, assembleiaRkey);
    expect(uploaded.sha256.length, 64);
    expect(uploaded.rkey.length, 13);

    final after = (await api.folderContents(folderRkey: assembleiaRkey)).value!;
    expect(after.items.length, 2);
    expect(after.items.last.name, 'regimento.pdf');
  });

  test('uploading to an unknown folder answers not found', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );
    final source = await tempUpload('BYTES');
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });

    final error = apiErrorOf(
      await api.upload(
        filePath: source.path,
        name: 'x.pdf',
        mime: 'application/pdf',
        folderRkey: '3aaaa2aaaaaaa',
      ),
    );
    expect(error.isNotFound, isTrue);
  });

  test('a thumbnail for a non-image answers not found', () async {
    final error = apiErrorOf(
      await fake().thumbnail(rkey: estatutoRkey, size: ThumbnailSize.sm),
    );
    expect(error.isNotFound, isTrue);
  });

  test('download writes the seeded bytes to a temp file', () async {
    final path = (await fake().download(rkey: estatutoRkey)).value!;
    final file = File(path);
    expect(await file.exists(), isTrue);
    expect((await file.readAsString()), startsWith('%PDF-1.4'));
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
  });

  test('create folder accepts then lists', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );
    final folder = (await api.createFolder(name: 'Prestação de contas')).value!;
    expect(folder.zona, Zona.casa);
    final listed = (await api.listFolders()).value!;
    expect(listed.last.name, 'Prestação de contas');
  });

  test('revoke session then me answers unauthorized', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );
    expect((await api.revokeSession()).isSuccess, isTrue);
    expect(apiErrorOf(await api.me()).isUnauthorized, isTrue);
  });

  test('Page.slice clamps the limit and reads the offset cursor', () {
    const values = [1, 2, 3];

    final first = Page.slice(values, limit: 2);
    expect(first.items, [1, 2]);
    expect(first.nextCursor, '2');

    final last = Page.slice(values, limit: 2, cursor: '2');
    expect(last.items, [3]);
    expect(last.nextCursor, isNull);

    final beyond = Page.slice(values, limit: 2, cursor: '9');
    expect(beyond.items, isEmpty);
    expect(beyond.nextCursor, isNull);

    final clamped = Page.slice(values, limit: 0);
    expect(clamped.items, [1]);
  });

  test(
    'deleting a file moves it to the trash and restore brings it back',
    () async {
      final api = fake();

      expect((await api.deleteFile(rkey: estatutoRkey)).isSuccess, isTrue);

      final contents = (await api.folderContents(folderRkey: assembleiaRkey))
          .value!;
      expect(contents.items.any((file) => file.rkey == estatutoRkey), isFalse);

      final trash = (await api.trash()).value!;
      expect(trash.items.map((file) => file.rkey), [estatutoRkey]);

      final restored = (await api.restoreFile(rkey: estatutoRkey)).value!;
      expect(restored.deletedAt, isNull);

      expect((await api.trash()).value!.items, isEmpty);
    },
  );

  test('update folder renames and publishes', () async {
    final api = fake();

    final published = (await api.updateFolder(
      rkey: assembleiaRkey,
      zona: Zona.praca,
    )).value!;
    expect(published.name, 'Documentos da assembleia');
    expect(published.zona, Zona.praca);

    final renamed = (await api.updateFolder(
      rkey: assembleiaRkey,
      name: 'Atas',
    )).value!;
    expect(renamed.name, 'Atas');
    expect(renamed.zona, Zona.praca);
  });

  test('moving a folder into its own subtree conflicts', () async {
    final api = fake();
    final inner = (await api.createFolder(
      name: 'Pasta de dentro',
      parentRkey: assembleiaRkey,
    )).value!;

    final error = apiErrorOf(
      await api.moveFolder(rkey: assembleiaRkey, parentRkey: inner.rkey),
    );
    expect(error.isConflict, isTrue);

    expect((await api.moveFolder(rkey: inner.rkey)).isSuccess, isTrue);
  });

  test('deleting a folder deletes the whole subtree', () async {
    final api = fake();
    final inner = (await api.createFolder(
      name: 'Pasta de dentro',
      parentRkey: assembleiaRkey,
    )).value!;

    expect((await api.deleteFolder(rkey: assembleiaRkey)).isSuccess, isTrue);

    final listed = (await api.listFolders()).value!;
    expect(
      listed.any(
        (folder) => folder.rkey == assembleiaRkey || folder.rkey == inner.rkey,
      ),
      isFalse,
    );

    final trash = (await api.trash()).value!;
    expect(trash.items.any((file) => file.rkey == estatutoRkey), isTrue);
  });

  test('photos paginate by cursor', () async {
    final api = fake();

    final first = (await api.photos(limit: 1)).value!;
    expect(first.items.length, 1);
    expect(first.nextCursor, '1');

    final second = (await api.photos(
      limit: 1,
      cursor: first.nextCursor,
    )).value!;
    expect(second.items.length, 1);
    expect(second.items.first.rkey, isNot(first.items.first.rkey));

    final third = (await api.photos(
      limit: 1,
      cursor: second.nextCursor,
    )).value!;
    expect(third.items.length, 1);
    expect(third.nextCursor, isNull);
  });

  test('the timeline groups the visual files by day', () async {
    final api = fake();
    final page = (await api.photoTimeline()).value!;
    expect(page.items.map((group) => group.date), ['2026-06-21']);
    expect(page.items.first.photos.length, 3);
    expect(page.nextCursor, isNull);
  });

  test('the access flow runs from request to decision', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );

    final pedido = (await api.requestAccess(
      fileRkey: estatutoRkey,
      motivo: 'Para a reuniao.',
    )).value!;
    expect(pedido.status, PedidoStatus.pendente);
    expect(pedido.motivo, 'Para a reuniao.');
    expect(pedido.pedinte?.username, 'ana');

    final mine = (await api.myRequests()).value!;
    expect(mine.items.first.publicId, pedido.publicId);

    final concessao = (await api.approveRequest(id: 'ped3xk9mq2v7w4')).value!;
    expect(concessao.leitor?.username, 'joana');
    expect(concessao.recurso, estatutoRkey);

    final received = (await api.accessRequests()).value!;
    expect(received.items.first.status, PedidoStatus.aprovado);

    final conflict = apiErrorOf(await api.approveRequest(id: 'ped3xk9mq2v7w4'));
    expect(conflict.isConflict, isTrue);
  });

  test('deny closes the pedido without access', () async {
    final api = fake();
    final pedido = (await api.denyRequest(id: 'ped3xk9mq2v7w4')).value!;
    expect(pedido.status, PedidoStatus.negado);
    expect(pedido.decididoEm, isNotNull);
  });

  test('storage counts the trash as it is', () async {
    final api = fake();

    final before = (await api.storage()).value!;
    expect(before.trash.count, 0);
    expect(before.quotaBytes, 268435456000);

    expect((await api.deleteFile(rkey: estatutoRkey)).isSuccess, isTrue);

    final after = (await api.storage()).value!;
    expect(after.trash.count, 1);
    expect(after.trash.bytes, 48213);
  });

  test('members list the zeladoras first', () async {
    final api = fake();
    final page = (await api.members()).value!;
    expect(page.items.first.papel, Papel.zelador);
    expect(page.items.map((ava) => ava.username), ['ana', 'joana', 'rafael']);
  });

  test(
    'devices list the newest first and revocation marks the clock',
    () async {
      final api = fake();
      await api.createSession(
        username: 'ana',
        password: 'segredo',
        deviceName: 'iPhone da Ana',
      );

      final devices = (await api.devices()).value!;
      expect(devices.length, 2);
      expect(devices.first.name, 'iPhone da Ana');
      expect(devices.first.revokedAt, isNull);

      final id = devices.first.publicId;
      expect((await api.revokeDevice(id: id)).isSuccess, isTrue);
      final after = (await api.devices()).value!;
      expect(
        after.firstWhere((device) => device.publicId == id).revokedAt,
        isNotNull,
      );

      expect(
        apiErrorOf(await api.revokeDevice(id: 'dev-nao-existe')).isNotFound,
        isTrue,
      );
    },
  );

  test('the mural lists the seeded chain newest first', () async {
    final api = fake();

    final page = (await api.mural(limit: 2)).value!;
    expect(page.items.map((entry) => entry.seq), [4, 3]);
    expect(page.nextCursor, '2');

    final rest = (await api.mural(cursor: page.nextCursor)).value!;
    expect(rest.items.map((entry) => entry.seq), [2, 1]);
    expect(rest.items.last.prev, isNull);
    expect(rest.nextCursor, isNull);
  });

  test('saude carries the last backup', () async {
    final api = fake();
    final saude = (await api.saude()).value!;
    expect(saude.backup.at, isNotNull);
    expect(saude.jobs['backups'], 0);
    expect(saude.storage.files, 5);
  });

  test('the invite flow runs from probe to account', () async {
    final api = fake();

    final status = (await api.inviteStatus(token: 'tk9x2m5qp7w4v8')).value!;
    expect(status.valid, isTrue);

    final session = (await api.acceptInvite(
      token: 'tk9x2m5qp7w4v8',
      username: 'joao',
      password: 'segredo',
      displayName: 'João Mendes',
      deviceName: 'iPhone do João',
    )).value!;
    expect(session.token, startsWith('tnd_'));
    expect(session.me.username, 'joao');
    expect(session.me.displayName, 'João Mendes');
    expect(session.me.papel, Papel.morador);

    expect((await api.me()).value!.ava.username, 'joao');
    expect((await api.devices()).value!.first.name, 'iPhone do João');
  });

  test('an empty username on the invite answers validation failed', () async {
    final error = apiErrorOf(
      await fake().acceptInvite(
        token: 'tk9x2m5qp7w4v8',
        username: '',
        password: 'segredo',
        deviceName: 'Teste',
      ),
    );
    expect(error.isValidationFailed, isTrue);
    expect(error.details['username'], isNotEmpty);
  });

  test('the reset flow signs the moradora in', () async {
    final api = fake();
    final status = (await api.resetStatus(token: 'tk9x2m5qp7w4v8')).value!;
    expect(status.valid, isTrue);

    final session = (await api.resetPassword(
      token: 'tk9x2m5qp7w4v8',
      password: 'nova-senha',
      deviceName: 'iPhone da Joana',
    )).value!;
    expect(session.me.username, 'joana');
    expect((await api.me()).value!.ava.username, 'joana');
  });

  test('the expired token closes every door', () async {
    final api = fake();
    final results = [
      await api.inviteStatus(token: 'expirado'),
      await api.resetStatus(token: 'expirado'),
      await api.acceptInvite(
        token: 'expirado',
        username: 'joao',
        password: 'segredo',
        deviceName: 'Teste',
      ),
      await api.resetPassword(
        token: 'expirado',
        password: 'segredo',
        deviceName: 'Teste',
      ),
    ];
    for (final result in results) {
      final error = apiErrorOf(result);
      expect(error.isUnauthorized, isTrue);
      expect(error.code, 'invalid_token');
    }
  });

  test(
    'the manifest lists every living file ordered by rkey and walks it',
    () async {
      final api = fake();

      final first = (await api.manifest(limit: 2)).value!;
      expect(first.items.map((file) => file.rkey), [
        '3m2a8twqpv5z2',
        '3m5c9vxyq2b7t',
      ]);
      expect(first.nextCursor, '3m5c9vxyq2b7t');

      final second = (await api.manifest(
        after: first.nextCursor,
        limit: 2,
      )).value!;
      expect(second.items.map((file) => file.rkey), [
        '3m7d1wyzr4c8u',
        '3m8e2xz0s5d9v',
      ]);
      expect(second.nextCursor, '3m8e2xz0s5d9v');

      final end = (await api.manifest(
        after: second.nextCursor,
        limit: 2,
      )).value!;
      expect(end.items.map((file) => file.rkey), ['3m9f4xk1q7v2n']);
      expect(end.nextCursor, isNull);

      expect((await api.deleteFile(rkey: estatutoRkey)).isSuccess, isTrue);
      final afterTrash = (await api.manifest()).value!;
      expect(
        afterTrash.items.any((file) => file.rkey == estatutoRkey),
        isFalse,
      );
    },
  );

  test('the batch applies every item and says what became of each', () async {
    final api = fake();

    final outcomes = (await api.batch(
      op: BatchOp.trash,
      ids: const [estatutoRkey, '3zzzzzzzzzzzz'],
    )).value!;
    expect(outcomes.first.ok, isTrue);
    expect(outcomes.first.file?.deletedAt, isNotNull);
    expect(outcomes.last.ok, isFalse);
    expect(outcomes.last.error, 'not_found');

    final restored = (await api.batch(
      op: BatchOp.restore,
      ids: const [estatutoRkey],
    )).value!;
    expect(restored.first.file?.deletedAt, isNull);

    final published = (await api.batch(
      op: BatchOp.publish,
      ids: const [estatutoRkey],
    )).value!;
    expect(published.first.file?.zona, Zona.praca);

    final unpublished = (await api.batch(
      op: BatchOp.unpublish,
      ids: const [estatutoRkey],
    )).value!;
    expect(unpublished.first.file?.zona, Zona.casa);

    final moved = (await api.batch(
      op: BatchOp.move,
      ids: const [estatutoRkey],
      folderRkey: assembleiaRkey,
    )).value!;
    expect(moved.first.file?.folder, assembleiaRkey);
  });

  test('the batch refuses more than two hundred ids', () async {
    final ids = [
      for (var index = 0; index <= 200; index++) '3m2a8twqpv5z$index',
    ];
    final error = apiErrorOf(await fake().batch(op: BatchOp.trash, ids: ids));
    expect(error.isValidationFailed, isTrue);
  });

  test('the grants list both sides of the caller', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );

    final given = (await api.grants(role: GrantRole.owner)).value!;
    expect(given.items.map((item) => item.publicId), ['con3qk9mq2v7w1']);
    expect(given.items.first.dono?.username, 'ana');

    final received = (await api.grants(role: GrantRole.reader)).value!;
    expect(received.items.map((item) => item.publicId), ['con5rk2mq8v3w7']);
    expect(received.items.first.revogadaEm, isNotNull);
  });

  test('revoking marks the clock once and conflicts the second time', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );

    expect((await api.revokeGrant(id: 'con3qk9mq2v7w1')).isSuccess, isTrue);
    final given = (await api.grants(role: GrantRole.owner)).value!;
    expect(given.items.first.revogadaEm, isNotNull);

    final conflict = apiErrorOf(await api.revokeGrant(id: 'con3qk9mq2v7w1'));
    expect(conflict.isConflict, isTrue);
    expect(conflict.code, 'invalid_status');

    expect(
      apiErrorOf(await api.revokeGrant(id: 'con-nao-existe')).isNotFound,
      isTrue,
    );
  });

  test('the password change says what the box would say', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );

    expect(
      (await api.updatePassword(
        current: 'qualquer',
        newPassword: 'nova-senha',
      )).isSuccess,
      isTrue,
    );

    final wrong = apiErrorOf(
      await api.updatePassword(current: 'errada', newPassword: 'nova-senha'),
    );
    expect(wrong.code, 'invalid_credentials');
    expect(wrong.status, 403);

    final weak = apiErrorOf(
      await api.updatePassword(current: 'qualquer', newPassword: 'curta'),
    );
    expect(weak.isValidationFailed, isTrue);
  });

  test('the zeladora runs the whole roster', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );

    final invite = (await api.inviteMember(papel: Papel.morador)).value!;
    expect(invite.ava.username, isNull);
    expect(
      invite.inviteUrl,
      startsWith('taina://convite/${invite.token}?host='),
    );

    expect((await api.revokeInvite(id: invite.ava.publicId)).isSuccess, isTrue);
    final roster = (await api.members()).value!;
    expect(
      roster.items.any((ava) => ava.publicId == invite.ava.publicId),
      isFalse,
    );

    const joana = 'avaq7r2m5xk9p1';
    final promoted = (await api.updateMember(
      id: joana,
      papel: Papel.zelador,
    )).value!;
    expect(promoted.papel, Papel.zelador);

    final link = (await api.memberResetLink(id: joana)).value!;
    expect(link.resetUrl, startsWith('taina://redefinir/${link.token}?host='));
    expect(link.ava.username, 'joana');

    expect((await api.deactivateMember(id: joana)).isSuccess, isTrue);
    final off = (await api.members()).value!;
    expect(
      off.items.firstWhere((ava) => ava.publicId == joana).deactivatedAt,
      isNotNull,
    );
    final back = (await api.reactivateMember(id: joana)).value!;
    expect(back.deactivatedAt, isNull);
  });

  test('the last zeladora cannot step down', () async {
    final api = fake();
    await api.createSession(
      username: 'ana',
      password: 'segredo',
      deviceName: 'Teste',
    );

    final error = apiErrorOf(
      await api.updateMember(id: 'avap2xw5m8q3', papel: Papel.morador),
    );
    expect(error.isConflict, isTrue);
    expect(error.code, 'last_zelador');
  });

  test('the quota changes and refuses zero', () async {
    final api = fake();

    final tekoa = (await api.setQuota(bytes: 536870912000)).value!;
    expect(tekoa.storageQuotaBytes, 536870912000);
    expect((await api.storage()).value!.quotaBytes, 536870912000);

    expect(apiErrorOf(await api.setQuota(bytes: 0)).isValidationFailed, isTrue);
  });

  test('the backup trigger is the queue not the backup', () async {
    expect((await fake().triggerBackup()).isSuccess, isTrue);
  });

  test('the instance reports the seeded community', () async {
    final instance = (await fake().instance()).value!;
    expect(instance.bootstrapped, isTrue);
    expect(instance.tekoa?.name, 'Tekoa Sapukai');
    expect(instance.version, '0.6.0');
  });
}
