import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/requests/requests_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

void main() {
  test(
    'load reads both pedido lists and resolves the resource names',
    () async {
      final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
      await api.createSession(
        username: 'ana',
        password: 'x',
        deviceName: 'test',
      );
      final RequestsModel model = RequestsModel(gateway: FakeSession(api));

      await model.load();

      expect(model.loading, isFalse);
      expect(model.sections.received, hasLength(1));
      expect(model.sections.sent, hasLength(2));
      expect(
        model.receivedNames['3m2a8twqpv5z2'],
        'Estatuto da associacao.pdf',
      );
      expect(model.sentNames['3q9p2xk5m8v1'], RequestsModel.deletedResource);
      expect(model.grantNames['3m5c9vxyq2b7t'], 'Lista de presenca.pdf');
      expect(
        model.grantNames['3q9p2xk5m8v1'],
        RequestsModel.unreadableResource,
      );
      expect(model.error, isNull);
    },
  );

  test('approve removes the pending pedido', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    final RequestsModel model = RequestsModel(gateway: FakeSession(api));
    await model.load();

    final result = await model.approve('ped3xk9mq2v7w4');

    expect(result.isSuccess, isTrue);
    expect(model.sections.received, isEmpty);
    expect(model.deciding, isNull);
  });

  test(
    'deny removes the pending pedido and keeps the fact on the box',
    () async {
      final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
      await api.createSession(
        username: 'ana',
        password: 'x',
        deviceName: 'test',
      );
      final RequestsModel model = RequestsModel(gateway: FakeSession(api));
      await model.load();

      final result = await model.deny('ped3xk9mq2v7w4');

      expect(result.isSuccess, isTrue);
      expect(model.sections.received, isEmpty);
    },
  );

  test('a second decision answers the box conflict', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    final RequestsModel model = RequestsModel(gateway: FakeSession(api));
    await model.load();
    await model.approve('ped3xk9mq2v7w4');

    final again = await model.approve('ped3xk9mq2v7w4');

    expect(again.isFailure, isTrue);
    expect((again.error! as ApiError).code, 'already_decided');
  });

  test('revoke reads the grants again and flips the row', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
    final RequestsModel model = RequestsModel(gateway: FakeSession(api));
    await model.load();

    final result = await model.revoke('con3qk9mq2v7w1');

    expect(result.isSuccess, isTrue);
    expect(RequestsModel.isRevoked(model.grants.given.first), isTrue);
    expect(model.revoking, isNull);
  });

  group('pure transitions', () {
    const Pedido pedido = Pedido(
      publicId: 'p1',
      tipo: 'leitura',
      recurso: 'missing',
      motivo: null,
      status: PedidoStatus.pendente,
      decididoEm: null,
      createdAt: '2026-10-14T10:00:00Z',
      pedinte: null,
      dono: null,
    );

    test('resource names fall back to the neutral labels', () {
      expect(
        RequestsModel.resourceNameForPedido(pedido, const {}),
        RequestsModel.deletedResource,
      );
      expect(
        RequestsModel.resourceNameForPedido(pedido, const {'missing': 'x.zip'}),
        'x.zip',
      );
    });

    test(
      'personLabel keeps a person of the community when the wire is empty',
      () {
        expect(RequestsModel.personLabel(null), 'Pessoa da comunidade');
        expect(RequestsModel.personLabel(joana), 'Joana Reis');
      },
    );

    test('resourceLine speaks from each side', () {
      expect(
        RequestsModel.resourceLine(received: true, name: 'x.zip'),
        'Pediu acesso a x.zip',
      );
      expect(
        RequestsModel.resourceLine(received: false, name: 'x.zip'),
        'Pedido para abrir x.zip',
      );
    });

    test('receivedHeader agrees in number', () {
      expect(
        RequestsModel.receivedHeader(1),
        '1 pedido esperando sua resposta',
      );
      expect(
        RequestsModel.receivedHeader(2),
        '2 pedidos esperando sua resposta',
      );
    });

    test('outcome messages name the file when the name is known', () {
      expect(
        RequestsModel.approvedMessage('x.zip'),
        'Acesso a x.zip liberado. A pessoa já pode ler.',
      );
      expect(
        RequestsModel.approvedMessage(null),
        'Acesso liberado. A pessoa já pode ler.',
      );
      expect(
        RequestsModel.revokedMessage('x.zip'),
        'Acesso a x.zip revogado. A pessoa já não pode ler.',
      );
    });

    test('removing drops the identity from both lists', () {
      final RequestSections sections = RequestSections(
        received: const [pedido],
        sent: const [pedido],
      );
      final RequestSections next = RequestsModel.removing('p1', sections);
      expect(next.received, isEmpty);
      expect(next.sent, isEmpty);
    });
  });
}
