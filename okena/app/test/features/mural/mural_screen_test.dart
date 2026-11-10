import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/mural/mural_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

final class _EmptyMuralApi implements TainaApi {
  _EmptyMuralApi(this._inner);

  final TainaApi _inner;

  @override
  Future<TainaResult<Page<MuralEntry>>> mural({
    int? limit,
    String? cursor,
  }) async {
    return Ok(Page(items: const [], nextCursor: null));
  }

  @override
  Future<TainaResult<Page<Ava>>> members() => _inner.members();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(SessionGateway session) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: MuralScreen(session: session),
  );
}

void main() {
  testWidgets('renders one sentence per entry and the ledger header', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(find.text('Mural'), findsOneWidget);
    expect(
      find.textContaining('O que aconteceu na comunidade'),
      findsOneWidget,
    );
    expect(
      find.textContaining('fez um ato registrado na comunidade'),
      findsNWidgets(4),
    );
  });

  testWidgets('shows the honest empty state when nothing happened', (
    tester,
  ) async {
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(
      _app(FakeSession(_EmptyMuralApi(inner), me: identity(ana))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nada aconteceu ainda'), findsOneWidget);
    expect(
      find.textContaining('Ninguém edita e ninguém apaga'),
      findsOneWidget,
    );
  });
}
