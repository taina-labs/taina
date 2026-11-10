import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/setup/setup_view.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/support/session_support.dart';

Widget _app(SessionModel model) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: SetupView(session: model),
  );
}

void main() {
  testWidgets('renders the community copy and the paste field', (tester) async {
    final composed = makeSession(state: const SessionNeedsInstance());

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();

    expect(find.text('Sua comunidade'), findsOneWidget);
    expect(find.text('Conectar'), findsOneWidget);
    expect(find.text('CHEGOU POR UM CONVITE?'), findsOneWidget);
    expect(find.text('Abrir o convite'), findsOneWidget);
  });

  testWidgets('an empty address shows the field sentence', (tester) async {
    final composed = makeSession(state: const SessionNeedsInstance());

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Conectar'));
    await tester.pump();
    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Informe o endereço da comunidade, por exemplo '
        'taina.minhacasa.ts.net.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a cleartext address warns while typing', (tester) async {
    final composed = makeSession(state: const SessionNeedsInstance());

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'http://box.local');
    await tester.pump();

    expect(find.text(TainaCleartextNotice.message), findsOneWidget);
  });

  testWidgets('a box without a community shows the setup card', (tester) async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (address) async =>
          const Ok(Instance(bootstrapped: false, tekoa: null, version: null)),
    );

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'box.local');
    await tester.ensureVisible(find.text('Conectar'));
    await tester.pump();
    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();

    expect(find.text('A comunidade ainda não foi criada'), findsOneWidget);
  });

  testWidgets('an unreachable box shows the actionable card', (tester) async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (address) async => const Err(NetworkError('down')),
    );

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'box.local');
    await tester.ensureVisible(find.text('Conectar'));
    await tester.pump();
    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();

    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(
      find.text(
        'Nada respondeu neste endereço. Confira se ele está certo, se a '
        'caixa está ligada e se este aparelho está na rede da comunidade.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a pasted malformed link is reported under the field', (
    tester,
  ) async {
    final composed = makeSession(state: const SessionNeedsInstance());

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'nada');
    await tester.ensureVisible(find.text('Abrir o convite'));
    await tester.pump();
    await tester.tap(find.text('Abrir o convite'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Este link não pôde ser lido'), findsOneWidget);
  });
}
