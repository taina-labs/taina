import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/trash/trash_screen.dart';
import 'package:okena_core/okena_core.dart';

import '../files/support/fakes.dart';

final class _ErrorTrashApi implements TainaApi {
  @override
  Future<TainaResult<Page<FileRecord>>> trash({
    int? limit,
    String? cursor,
  }) async {
    return const Err(NetworkError());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget home) {
  return MaterialApp(theme: TainaTheme.data, home: home);
}

void main() {
  testWidgets('trash lists the discarded file with the retention rule', (
    tester,
  ) async {
    final api = FakeTainaApi(delay: Duration.zero);
    await api.deleteFile(rkey: '3m7d1wyzr4c8u');

    await tester.pumpWidget(
      _app(TrashScreen(session: FakeSessionGateway(api: api))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lixeira'), findsOneWidget);
    expect(
      find.textContaining('Itens são apagados para sempre após 30 dias'),
      findsOneWidget,
    );
    expect(find.text('Foto da quadra.jpg'), findsOneWidget);
    expect(find.textContaining('Apagado hoje'), findsOneWidget);
    expect(find.byTooltip('Restaurar'), findsOneWidget);
  });

  testWidgets('restoring drops the row and empties the trash', (tester) async {
    final api = FakeTainaApi(delay: Duration.zero);
    await api.deleteFile(rkey: '3m7d1wyzr4c8u');

    await tester.pumpWidget(
      _app(TrashScreen(session: FakeSessionGateway(api: api))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Restaurar'));
    await tester.pumpAndSettle();

    expect(find.text('Foto da quadra.jpg'), findsNothing);
    expect(find.text('Lixeira vazia'), findsOneWidget);
  });

  testWidgets('an empty trash says nothing is waiting', (tester) async {
    final api = FakeTainaApi(delay: Duration.zero);

    await tester.pumpWidget(
      _app(TrashScreen(session: FakeSessionGateway(api: api))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lixeira vazia'), findsOneWidget);
    expect(find.text('Nada esperando para ser apagado.'), findsOneWidget);
  });

  testWidgets('a failed page shows the error and the retry', (tester) async {
    await tester.pumpWidget(
      _app(TrashScreen(session: FakeSessionGateway(api: _ErrorTrashApi()))),
    );
    await tester.pumpAndSettle();

    expect(find.text(const NetworkError().message), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
