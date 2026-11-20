import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/requests/requests_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

Future<RequestsModel> _loadedModel() async {
  final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
  await api.createSession(username: 'ana', password: 'x', deviceName: 'test');
  final RequestsModel model = RequestsModel(gateway: FakeSession(api));
  await model.load();
  return model;
}

void main() {
  test(
    'load merges incoming, sent and owner-granted access newest first',
    () async {
      final RequestsModel model = await _loadedModel();

      expect(model.loading, isFalse);
      expect(model.items, hasLength(4));
      expect(model.items.first.kind, RequestFeedKind.outgoing);
      expect(
        model.items.map((RequestFeedItem item) => item.title),
        contains('Joana Reis pediu acesso'),
      );
      expect(
        model.items.map((RequestFeedItem item) => item.title),
        contains('Você recebeu acesso a arquivo apagado'),
      );
      expect(
        model.items.map((RequestFeedItem item) => item.title),
        contains('Joana Reis recebeu acesso'),
      );
      expect(
        model.items.map((RequestFeedItem item) => item.state),
        containsAll([TainaPedidoState.esperando, TainaPedidoState.dado]),
      );
      expect(model.error, isNull);
    },
  );

  test('approval remains visible as an owner grant', () async {
    final RequestsModel model = await _loadedModel();

    final TainaResult<void> result = await model.approve('ped3xk9mq2v7w4');

    expect(result.isSuccess, isTrue);
    expect(model.deciding, isNull);
    expect(
      model.items.map((RequestFeedItem item) => item.title),
      contains('Joana Reis recebeu acesso'),
    );
    expect(
      model.items
          .where(
            (RequestFeedItem item) => item.pedido?.publicId == 'ped3xk9mq2v7w4',
          )
          .length,
      1,
    );
  });

  test(
    'denial remains visible after a reload in the same screen model',
    () async {
      final RequestsModel model = await _loadedModel();

      final TainaResult<void> result = await model.deny('ped3xk9mq2v7w4');

      expect(result.isSuccess, isTrue);
      expect(
        model.items.map((RequestFeedItem item) => item.title),
        contains('Joana Reis teve o acesso recusado'),
      );
      expect(
        model.items
            .firstWhere(
              (RequestFeedItem item) =>
                  item.pedido?.publicId == 'ped3xk9mq2v7w4',
            )
            .state,
        TainaPedidoState.recusado,
      );

      await model.load();

      expect(
        model.items.map((RequestFeedItem item) => item.title),
        contains('Joana Reis teve o acesso recusado'),
      );
      expect(
        model.items
            .where(
              (RequestFeedItem item) =>
                  item.pedido?.publicId == 'ped3xk9mq2v7w4',
            )
            .length,
        1,
      );
    },
  );

  test('a second decision answers the box conflict', () async {
    final RequestsModel model = await _loadedModel();
    await model.approve('ped3xk9mq2v7w4');

    final TainaResult<void> again = await model.approve('ped3xk9mq2v7w4');

    expect(again.isFailure, isTrue);
    expect((again.error! as ApiError).code, 'already_decided');
  });

  test('revoke keeps the grant visible with its revoked state', () async {
    final RequestsModel model = await _loadedModel();

    final TainaResult<void> result = await model.revoke('con3qk9mq2v7w1');

    expect(result.isSuccess, isTrue);
    expect(model.revoking, isNull);
    final RequestFeedItem row = model.items.firstWhere(
      (RequestFeedItem item) => item.grant?.publicId == 'con3qk9mq2v7w1',
    );
    expect(row.state, TainaPedidoState.recusado);
    expect(row.canRevoke, isFalse);
    expect(row.title, 'Acesso retirado de Joana Reis');
  });

  group('pure formatting', () {
    test('timestamps include the relative day and local time', () {
      expect(
        RequestsModel.timestamp(
          '2026-10-13T15:30:00Z',
          now: DateTime.utc(2026, 10, 13, 18),
        ),
        matches(RegExp(r'^hoje \d{2}:\d{2}$')),
      );
    });

    test('short dates use the board month abbreviation', () {
      expect(RequestsModel.shortDate('2026-10-23T09:00:00Z'), '23 out');
    });
  });
}
