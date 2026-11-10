import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/home/home_model.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fake_gateway.dart';

const StorageStats _half = StorageStats(
  usedBytes: 50,
  quotaBytes: 100,
  byKind: StorageByKind(photos: 50, videos: 0, documents: 0, others: 0),
  files: 1,
  photos: 1,
  trash: StorageTrash(count: 0, bytes: 0),
);

const StorageStats _nearlyFull = StorageStats(
  usedBytes: 95,
  quotaBytes: 100,
  byKind: StorageByKind(photos: 95, videos: 0, documents: 0, others: 0),
  files: 1,
  photos: 1,
  trash: StorageTrash(count: 0, bytes: 0),
);

const StorageStats _noQuota = StorageStats(
  usedBytes: 95,
  quotaBytes: null,
  byKind: StorageByKind(photos: 95, videos: 0, documents: 0, others: 0),
  files: 1,
  photos: 1,
  trash: StorageTrash(count: 0, bytes: 0),
);

MuralEntry _entry(
  String tipo,
  Map<String, JsonValue> payload, {
  String cid = 'cid-1',
  String createdAt = '2026-11-09T10:00:00Z',
}) {
  return MuralEntry(
    seq: 1,
    tipo: tipo,
    payload: payload,
    cid: cid,
    prev: null,
    createdAt: createdAt,
  );
}

void main() {
  group('pure helpers', () {
    test('the greeting follows the device clock', () {
      expect(HomeModel.greeting(5), 'Bom dia,');
      expect(HomeModel.greeting(11), 'Bom dia,');
      expect(HomeModel.greeting(12), 'Boa tarde,');
      expect(HomeModel.greeting(17), 'Boa tarde,');
      expect(HomeModel.greeting(18), 'Boa noite,');
      expect(HomeModel.greeting(4), 'Boa noite,');
    });

    test('storage reads quota, percent, warning and free space', () {
      expect(HomeModel.hasQuota(_half), isTrue);
      expect(HomeModel.hasQuota(_noQuota), isFalse);
      expect(HomeModel.storagePercent(_half), 50);
      expect(HomeModel.storagePercent(_nearlyFull), 95);
      expect(HomeModel.storagePercent(_noQuota), 0);
      expect(HomeModel.storageLow(_half), isFalse);
      expect(HomeModel.storageLow(_nearlyFull), isTrue);
      expect(HomeModel.storageLow(_noQuota), isFalse);
      expect(HomeModel.freeLabel(_half), '50 B livres');
      expect(HomeModel.freeLabel(_nearlyFull), 'quase cheia: 5 B livres');
      expect(HomeModel.freeLabel(_noQuota), isEmpty);
    });

    test('the recent meta ends in the zone in words', () {
      final FileRecord file = FileRecord(
        rkey: 'a',
        cid: 'cid',
        blobCid: 'blob',
        sha256: 'sha',
        name: 'Foto.jpg',
        mime: 'image/jpeg',
        size: 1204331,
        zona: Zona.praca,
        folder: null,
        takenAt: null,
        width: null,
        height: null,
        rendition: Rendition.ready,
        deletedAt: null,
        createdAt: '2026-11-08T10:00:00Z',
        updatedAt: '2026-11-08T10:00:00Z',
      );
      expect(
        HomeModel.recentMeta(file, now: DateTime(2026, 11, 9, 12)),
        'Imagem, 1,1 MB, ontem, na praça',
      );
    });

    test('the kind words and the pending label match the screen', () {
      expect(HomeModel.fileKind('application/pdf'), 'PDF');
      expect(HomeModel.fileKind('video/mp4'), 'Vídeo');
      expect(HomeModel.fileKind('text/plain'), 'Texto');
      expect(HomeModel.fileKind('application/octet-stream'), 'Arquivo');
      expect(HomeModel.zonaWord(Zona.casa), 'na casa');
      expect(HomeModel.zonaWord(Zona.praca), 'na praça');
      expect(HomeModel.pendingLabel(0), 'Nenhum pedido esperando');
      expect(HomeModel.pendingLabel(1), '1 pedido esperando');
      expect(HomeModel.pendingLabel(4), '4 pedidos esperando');
    });

    test('pending count ignores the decided pedidos', () async {
      final HomeTestGateway gateway = HomeTestGateway();
      final Page<Pedido> page = (await gateway.api.accessRequests()).value!;
      expect(HomeModel.pendingCount(page), 1);
    });
  });

  group('mural sentences', () {
    const Map<String, String> names = {'ava-ana': 'Ana'};

    test('an actor the roster knows speaks by name', () {
      expect(
        HomeModel.sentence(
          _entry('put', const {'actor': JsonString('ava-ana')}),
          names,
        ),
        'Ana guardou um arquivo na caixa.',
      );
      expect(
        HomeModel.sentence(
          _entry('put', const {
            'actor': JsonString('ava-ana'),
            'collection': JsonString('ypy.folder.v0'),
          }),
          names,
        ),
        'Ana criou uma pasta.',
      );
    });

    test('an unknown actor is the system', () {
      expect(
        HomeModel.sentence(
          _entry('publicar', const {'actor': JsonString('sumiu')}),
          names,
        ),
        'O sistema publicou um arquivo na praça.',
      );
      expect(
        HomeModel.sentence(_entry('desconhecido', const {}), names),
        'O sistema fez um ato registrado na comunidade.',
      );
    });

    test('the quota sentence formats both bounds', () {
      expect(
        HomeModel.sentence(
          _entry('quota_changed', const {
            'actor': JsonString('ava-ana'),
            'from': JsonInt(1024),
            'to': JsonInt(2048),
          }),
          names,
        ),
        'Ana mudou o limite de armazenamento de 1,0 KB para 2,0 KB.',
      );
    });

    test('the member sentences name the member when it is there', () {
      expect(
        HomeModel.sentence(
          _entry('member_deactivated', const {
            'actor': JsonString('ava-ana'),
            'member': JsonString('Joana'),
          }),
          names,
        ),
        'Ana desativou a conta de Joana.',
      );
      expect(
        HomeModel.sentence(
          _entry('member_reactivated', const {'actor': JsonString('ava-ana')}),
          names,
        ),
        'Ana reativou uma conta.',
      );
    });

    test('lines keep the cid, the sentence and the ago', () {
      final List<HomeMuralLine> lines = HomeModel.lines(
        [
          _entry('put', const {'actor': JsonString('ava-ana')}, cid: 'c1'),
        ],
        names,
        now: DateTime(2026, 11, 9, 12),
      );
      expect(lines.single.id, 'c1');
      expect(lines.single.sentence, 'Ana guardou um arquivo na caixa.');
      expect(lines.single.ago, 'hoje');
    });

    test('actor names come from the roster labels', () {
      final Map<String, String> names = HomeModel.actorNames(const [
        Ava(
          publicId: 'a',
          username: 'ana',
          displayName: 'Ana Souza',
          papel: Papel.zelador,
          activatedAt: null,
          deactivatedAt: null,
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ]);
      expect(names['a'], 'Ana Souza');
    });
  });

  group('loading', () {
    test('load fills every section and the community name', () async {
      final HomeTestGateway gateway = HomeTestGateway();
      final HomeModel model = HomeModel(gateway);
      addTearDown(model.dispose);

      await model.load();

      expect(model.loaded, isTrue);
      expect(model.communityName, 'Tekoa Sapukai');
      expect(model.recent, hasLength(4));
      expect(model.recentError, isNull);
      expect(model.stats, isNotNull);
      expect(model.statsError, isFalse);
      expect(model.mural, hasLength(3));
      expect(model.muralError, isFalse);
      expect(model.pendingRequests, 1);
      expect(model.requestsError, isFalse);
    });

    test('a section failure degrades only that section', () async {
      final HomeTestGateway gateway = HomeTestGateway();
      gateway.failStats = true;
      gateway.failMural = true;
      gateway.failRequests = true;
      final HomeModel model = HomeModel(gateway);
      addTearDown(model.dispose);

      await model.load();

      expect(model.statsError, isTrue);
      expect(model.stats, isNull);
      expect(model.muralError, isTrue);
      expect(model.mural, isEmpty);
      expect(model.requestsError, isTrue);
      expect(model.pendingRequests, isNull);
      expect(model.recent, hasLength(4));
      expect(model.recentError, isNull);
      expect(model.loaded, isTrue);
    });

    test('retryStorage reloads the stats and nothing else', () async {
      final HomeTestGateway gateway = HomeTestGateway();
      gateway.failStats = true;
      final HomeModel model = HomeModel(gateway);
      addTearDown(model.dispose);
      await model.load();
      final int recentCalls = gateway.recentCalls;

      gateway.failStats = false;
      await model.retryStorage();

      expect(model.stats, isNotNull);
      expect(model.statsError, isFalse);
      expect(gateway.recentCalls, recentCalls);
      expect(gateway.storageCalls, 2);
    });

    test('a response after dispose does not notify', () async {
      final HomeTestGateway gateway = HomeTestGateway(
        delay: const Duration(milliseconds: 10),
      );
      final HomeModel model = HomeModel(gateway);
      final Future<void> pending = model.load();
      model.dispose();
      await pending;
      expect(model.loaded, isFalse);
    });
  });
}
