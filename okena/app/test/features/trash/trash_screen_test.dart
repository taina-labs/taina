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
      find.textContaining('Os itens ficam 30 dias na lixeira'),
      findsOneWidget,
    );
    expect(find.text('Foto da quadra.jpg'), findsOneWidget);
    expect(find.textContaining('resta'), findsOneWidget);
    expect(find.text('Restaurar'), findsOneWidget);
  });

  testWidgets('restoring drops the row and empties the trash', (tester) async {
    final api = FakeTainaApi(delay: Duration.zero);
    await api.deleteFile(rkey: '3m7d1wyzr4c8u');

    await tester.pumpWidget(
      _app(TrashScreen(session: FakeSessionGateway(api: api))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restaurar'));
    await tester.pumpAndSettle();

    expect(find.text('Foto da quadra.jpg'), findsNothing);
    expect(find.text('A lixeira está vazia'), findsOneWidget);
  });

  testWidgets('an empty trash says nothing is waiting', (tester) async {
    final api = FakeTainaApi(delay: Duration.zero);
    TainaDocumentTab? selectedTab;

    await tester.pumpWidget(
      _app(
        TrashScreen(
          session: FakeSessionGateway(api: api),
          onSelectTab: (tab) => selectedTab = tab,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A lixeira está vazia'), findsOneWidget);
    expect(find.textContaining('Nada foi apagado.'), findsOneWidget);
    await tester.tap(find.text('Casa').last);
    expect(selectedTab, TainaDocumentTab.casa);
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
