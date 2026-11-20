import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/mural/mural_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

final class _MuralApi implements TainaApi {
  _MuralApi(this._inner, this.result);

  final TainaApi _inner;
  final TainaResult<Page<MuralEntry>> result;

  @override
  Future<TainaResult<Page<MuralEntry>>> mural({
    int? limit,
    String? cursor,
  }) async => result;

  @override
  Future<TainaResult<Page<Ava>>> members() => _inner.members();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MuralEntry _entry(int seq, String tipo, Map<String, JsonValue> payload) {
  return MuralEntry(
    seq: seq,
    tipo: tipo,
    payload: payload,
    cid: 'cid$seq',
    prev: seq == 1 ? null : 'cid${seq - 1}',
    createdAt: '2026-10-14T09:12:00Z',
  );
}

Widget _app(SessionGateway session) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: MuralScreen(session: session),
  );
}

void main() {
  testWidgets('renders the board sentences newest first and ends the mural', (
    tester,
  ) async {
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    final _MuralApi api = _MuralApi(
      inner,
      Ok(
        Page(
          items: [
            _entry(3, 'publicar', const {
              'actor': JsonString('avap2xw5m8q3'),
              'name': JsonString('Estatuto.pdf'),
            }),
            _entry(2, 'invite_accepted', const {
              'actor': JsonString('avaq7r2m5xk9p1'),
            }),
            _entry(1, 'backup_succeeded', const {
              'actor': JsonString('avap2xw5m8q3'),
            }),
          ],
          nextCursor: null,
        ),
      ),
    );
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(find.byType(TainaListRow), findsNWidgets(3));
    expect(
      find.text('Ana Souza publicou Estatuto.pdf na praça'),
      findsOneWidget,
    );
    expect(find.text('Joana Reis entrou na comunidade'), findsOneWidget);
    expect(find.text('Ana Souza fez o backup da nuvem'), findsOneWidget);
    expect(find.text('Fim do mural.'), findsOneWidget);
  });

  testWidgets('shows the designed empty state', (tester) async {
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    final _MuralApi api = _MuralApi(
      inner,
      Ok(Page(items: const [], nextCursor: null)),
    );
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(find.text('Nada no mural ainda'), findsOneWidget);
    expect(
      find.textContaining(
        'Ainda não aconteceu nada por aqui. Quando alguém publicar na praça',
      ),
      findsOneWidget,
    );
    expect(find.text('Fim do mural.'), findsNothing);
  });

  testWidgets('shows the degraded board and caretaker sheet on error', (
    tester,
  ) async {
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    final _MuralApi api = _MuralApi(inner, const Err(offline));
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(
      find.text('Não conseguimos falar com a nuvem agora.'),
      findsOneWidget,
    );
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(find.text('Falar com quem cuida'), findsOneWidget);

    await tester.tap(find.text('Falar com quem cuida'));
    await tester.pumpAndSettle();

    expect(find.text('Quem cuida da nuvem'), findsOneWidget);
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Fechar'), findsOneWidget);
  });
}
