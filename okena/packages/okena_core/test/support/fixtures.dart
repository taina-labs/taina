import 'dart:convert';

import 'package:okena_core/okena_core.dart';

const instanceJson =
    '{"bootstrapped":true,"tekoa":{"public_id":"tekp2xw5m8q3",'
    '"name":"Tekoa Sapukai","domain":"taina.sapukai.ts.net",'
    '"storage_quota_bytes":268435456000,"storage_used_bytes":1832110000,'
    '"created_at":"2026-02-01T09:00:00Z"},"version":"0.6.0"}';

const sessionJson =
    '{"token":"tnd_abcdef0123456789abcdef0123456789","device":'
    '{"public_id":"devp2xw5m8q3","name":"iPhone da Ana","last_used_at":null,'
    '"revoked_at":null,"created_at":"2026-10-14T08:00:00Z"},"me":'
    '{"public_id":"avap2xw5m8q3","username":"ana","display_name":"Ana Souza",'
    '"papel":"zelador","activated_at":"2026-02-01T09:00:00Z",'
    '"deactivated_at":null,"created_at":"2026-02-01T09:00:00Z"},"tekoa":'
    '{"public_id":"tekp2xw5m8q3","name":"Tekoa Sapukai",'
    '"domain":"taina.sapukai.ts.net","storage_quota_bytes":268435456000,'
    '"storage_used_bytes":1832110000,"created_at":"2026-02-01T09:00:00Z"}}';

const contentsJson =
    '{"folders":[{"rkey":"3kx2n8pqrv5w2",'
    '"cid":"bmq2a5xw7k3p9r2t8v4z6c1d5f7h9j2x",'
    '"name":"Documentos da assembleia","zona":"casa","folder":null,'
    '"deleted_at":null,"created_at":"2026-03-10T14:00:00Z",'
    '"updated_at":"2026-03-10T14:00:00Z"}],"items":[],"next_cursor":null}';

const fileJson =
    '{"rkey":"3n4b9uxrw6a3",'
    '"cid":"bp3q4r5s6t7u8v9w0x1y2z3a4b5c6d7e8",'
    '"blob_cid":"bq4r5s6t7u8v9w0x1y2z3a4b5c6d7e8f9",'
    '"sha256":"aa11bb22cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66",'
    '"name":"ata.pdf","mime":"application/pdf","size":19,"zona":"casa",'
    '"folder":"3kx2n8pqrv5w2","taken_at":null,"width":null,"height":null,'
    '"rendition":"none","deleted_at":null,'
    '"created_at":"2026-10-14T08:00:00Z",'
    '"updated_at":"2026-10-14T08:00:00Z"}';

const folderJson =
    '{"rkey":"3kx2n8pqrv5w2",'
    '"cid":"bmq2a5xw7k3p9r2t8v4z6c1d5f7h9j2x",'
    '"name":"Documentos da assembleia","zona":"casa","folder":null,'
    '"deleted_at":null,"created_at":"2026-03-10T14:00:00Z",'
    '"updated_at":"2026-03-10T14:00:00Z"}';

const updatedFolderJson =
    '{"rkey":"3kx2n8pqrv5w2",'
    '"cid":"bmq2a5xw7k3p9r2t8v4z6c1d5f7h9j2x",'
    '"name":"Atas publicadas","zona":"praca","folder":null,'
    '"deleted_at":null,"created_at":"2026-03-10T14:00:00Z",'
    '"updated_at":"2026-10-14T09:00:00Z"}';

const fotoJson =
    '{"rkey":"3m7d1wyzr4c8u",'
    '"cid":"bt6u7v8w9x0y1z2a3b4c5d6e7f8g9h0i1",'
    '"blob_cid":"bu7v8w9x0y1z2a3b4c5d6e7f8g9h0i1j2",'
    '"sha256":"cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66aa11bb22",'
    '"name":"Foto da quadra.jpg","mime":"image/jpeg","size":1204331,'
    '"zona":"praca","folder":null,"taken_at":"2026-06-21T21:12:00Z",'
    '"width":4032,"height":3024,"rendition":"ready","deleted_at":null,'
    '"created_at":"2026-06-21T21:12:00Z",'
    '"updated_at":"2026-06-21T21:12:00Z"}';

const pendingFotoJson =
    '{"rkey":"3m8e2xz0s5d9v",'
    '"cid":"bv8w9x0y1z2a3b4c5d6e7f8g9h0i1j2k3",'
    '"blob_cid":"bw9x0y1z2a3b4c5d6e7f8g9h0i1j2k3l4",'
    '"sha256":"dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66aa11bb22cc33",'
    '"name":"Cartaz da festa.jpg","mime":"image/jpeg","size":934221,'
    '"zona":"praca","folder":null,"taken_at":null,"width":null,'
    '"height":null,"rendition":"pending","deleted_at":null,'
    '"created_at":"2026-06-21T20:30:00Z",'
    '"updated_at":"2026-06-21T20:30:00Z"}';

const filePageJson = '{"items":[$fileJson],"next_cursor":"12"}';

const anaJson =
    '{"public_id":"avap2xw5m8q3","username":"ana",'
    '"display_name":"Ana Souza","papel":"zelador",'
    '"activated_at":"2026-02-01T09:00:00Z","deactivated_at":null,'
    '"created_at":"2026-02-01T09:00:00Z"}';

const joanaJson =
    '{"public_id":"avaq7r2m5xk9p1","username":"joana",'
    '"display_name":"Joana Reis","papel":"morador",'
    '"activated_at":"2026-02-02T09:00:00Z","deactivated_at":null,'
    '"created_at":"2026-02-02T09:00:00Z"}';

const devicesPageJson =
    '{"items":[{"public_id":"devp2xw5m8q3","name":"iPhone da Ana",'
    '"last_used_at":"2026-10-14T08:00:00Z","revoked_at":null,'
    '"created_at":"2026-10-14T08:00:00Z"}],"next_cursor":null}';

const accessTargetJson =
    '{"owner":$joanaJson,"rkey":"3n4b9uxrw6a3","name":"ata.pdf"}';

const pedidoJson =
    '{"public_id":"ped3xk9mq2v7w4","tipo":"leitura",'
    '"recurso":"3n4b9uxrw6a3",'
    '"motivo":"Preciso do estatuto para a reuniao de domingo.",'
    '"status":"pendente","decidido_em":null,'
    '"created_at":"2026-10-12T10:00:00Z","pedinte":$joanaJson,'
    '"dono":$anaJson}';

const deniedPedidoJson =
    '{"public_id":"ped3xk9mq2v7w4","tipo":"leitura",'
    '"recurso":"3n4b9uxrw6a3",'
    '"motivo":"Preciso do estatuto para a reuniao de domingo.",'
    '"status":"negado","decidido_em":"2026-10-14T12:00:00Z",'
    '"created_at":"2026-10-12T10:00:00Z","pedinte":$joanaJson,'
    '"dono":$anaJson}';

const concessaoJson =
    '{"public_id":"con4kx9mq2v7w5","tipo":"leitura",'
    '"recurso":"3n4b9uxrw6a3","concedida_em":"2026-10-14T12:00:00Z",'
    '"revogada_em":null,"created_at":"2026-10-14T12:00:00Z",'
    '"leitor":$joanaJson,"dono":$anaJson}';

const pedidosPageJson = '{"items":[$pedidoJson],"next_cursor":null}';

const storageJson =
    '{"used_bytes":1832110000,"quota_bytes":268435456000,'
    '"by_kind":{"photos":1100000000,"videos":600000000,'
    '"documents":132110000,"others":0},"files":42,"photos":30,'
    '"trash":{"count":3,"bytes":1000000}}';

const saudeJson =
    '{"storage":$storageJson,"jobs":{"renditions":0,"backups":1},'
    '"backup":{"at":"2026-10-14T03:00:00Z","bytes":1829000000}}';

const muralPageJson =
    '{"items":[{"seq":2,"tipo":"arquivo.publicado","payload":'
    '{"name":"Foto da quadra.jpg","zona":"praca","size":1204331,'
    '"featured":true,"caption":null,"tags":["festa","quadra"]},'
    '"cid":"bz8x6k4m2q9v1p3r5t7w2y4a6c8e0g2",'
    '"prev":"by7w5j3l1p8u0o2q4s6v1x3z5a7d9f1",'
    '"created_at":"2026-06-21T21:12:00Z"},{"seq":1,"tipo":"pasta.criada",'
    '"payload":{"name":"Fotos da festa"},'
    '"cid":"by7w5j3l1p8u0o2q4s6v1x3z5a7d9f1","prev":null,'
    '"created_at":"2026-06-21T20:00:00Z"}],"next_cursor":null}';

const timelinePageJson =
    '{"items":[{"date":"2026-06-21","photos":[$fotoJson]}],'
    '"next_cursor":null}';

const membersPageJson = '{"items":[$anaJson,$joanaJson],"next_cursor":null}';

const tokenStatusJson = '{"valid":true}';

const inviteToken = 'tk9x2m5qp7w4v8';

Session fixturedSession() {
  final result = decodeJsonBody(
    utf8.encode(sessionJson),
    'session fixture',
    Session.fromJson,
  );
  return result.value!;
}

InstanceAddress boxAddress() => InstanceAddress.parse('https://box').value!;
