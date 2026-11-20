import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/setup/setup_view.dart';
import 'package:okena_app/src/session/session_state.dart';

import '../../session/support/session_support.dart';

void main() {
  testWidgets('SetupView remains a compatibility wrapper for first access', (
    tester,
  ) async {
    final composed = makeSession(state: const SessionNeedsInstance());

    await tester.pumpWidget(
      MaterialApp(
        theme: TainaTheme.data,
        home: SetupView(session: composed.model),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tainá'), findsOneWidget);
    expect(find.text('Endereço da comunidade'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Conectar'), findsNothing);
    expect(find.text('Setup'), findsNothing);
  });
}
