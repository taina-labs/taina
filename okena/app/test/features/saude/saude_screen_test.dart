import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/saude/saude_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

final class _SaudeApi implements TainaApi {
  _SaudeApi(this._inner, this.value);

  final TainaApi _inner;
  final Saude value;

  @override
  Future<TainaResult<Saude>> saude() async => Ok(value);

  @override
  Future<TainaResult<Me>> me() => _inner.me();

  @override
  Future<TainaResult<Page<Ava>>> members() => _inner.members();

  @override
  Future<TainaResult<void>> triggerBackup() => _inner.triggerBackup();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const StorageByKind _noKinds = StorageByKind(
  photos: 0,
  videos: 0,
  documents: 0,
  others: 0,
);

Widget _app(SessionGateway session) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: SaudeScreen(session: session),
  );
}

Saude _attention() => const Saude(
  storage: StorageStats(
    usedBytes: 95,
    quotaBytes: 100,
    byKind: _noKinds,
    files: 0,
    photos: 0,
    trash: StorageTrash(count: 0, bytes: 0),
  ),
  jobs: {},
  backup: SaudeBackup(status: SaudeBackupStatus.failed, at: null, bytes: null),
  summary: SaudeSummary(
    state: SaudeSummaryState.attention,
    line: 'Disco quase cheio',
  ),
  update: SaudeUpdate(
    status: SaudeUpdateStatus.upToDate,
    running: '1.0.0',
    latest: '1.0.0',
  ),
);

void main() {
  testWidgets('morador sees four status rows and the neutral caretaker copy', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    expect(find.text('ESTADO DA NUVEM'), findsOneWidget);
    expect(find.byType(StatusLine), findsNWidgets(4));
    expect(find.text('Backup em dia'), findsOneWidget);
    expect(find.text('Espaço de sobra'), findsOneWidget);
    expect(find.text('Atualizações'), findsOneWidget);
    expect(find.text('Tudo no ar'), findsOneWidget);
    expect(
      find.text(
        'Quem cuida da nuvem: Ana Souza. Cuida da máquina, não dos arquivos.',
      ),
      findsOneWidget,
    );
    expect(find.text('Fazer backup agora'), findsNothing);
  });

  testWidgets('zelador can queue the first backup and gets a toast', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(
      delay: Duration.zero,
      backup: const SaudeBackup(
        status: SaudeBackupStatus.ok,
        at: '2026-10-14T03:00:00Z',
        bytes: 1024,
      ),
    );
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(find.text('Fazer backup agora'), findsOneWidget);
    expect(
      find.text(
        'Você cuida da nuvem. O backup é a sua parte; os arquivos continuam '
        'de cada um.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Fazer backup agora'));
    await tester.pumpAndSettle();

    expect(find.text('Backup agendado.'), findsOneWidget);
  });

  testWidgets('attention state shows the board status and footer', (
    tester,
  ) async {
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    final _SaudeApi api = _SaudeApi(inner, _attention());
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    expect(find.byType(StatusLine), findsNWidgets(4));
    expect(find.text('Disco quase cheio'), findsOneWidget);
    expect(find.text('Último backup falhou'), findsOneWidget);
    expect(find.text('Atualizações em dia'), findsOneWidget);
    expect(
      find.text('Vale falar com quem cuida da nuvem. Ninguém perdeu arquivo.'),
      findsOneWidget,
    );
  });

  testWidgets('an unavailable update remains an unknown status row', (
    tester,
  ) async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    final StatusLine update = tester.widget<StatusLine>(
      find.ancestor(
        of: find.text('Atualizações'),
        matching: find.byType(StatusLine),
      ),
    );
    expect(update.state, TainaStatusState.unknown);
  });
}
