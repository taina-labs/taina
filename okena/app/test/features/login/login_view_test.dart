import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/login/login_view.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/support/session_support.dart';

Widget _app(SessionModel model) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: LoginView(session: model),
  );
}

void main() {
  testWidgets('shows the community, the address and the form', (tester) async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );
    await composed.model.restore();

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();

    expect(find.text('Tekoa Sapukai'), findsOneWidget);
    expect(find.text('box.local'), findsOneWidget);
    expect(find.text('Usuário'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.text('Nome deste aparelho'), findsOneWidget);
  });

  testWidgets('shows the forced sign out sentence', (tester) async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );
    await composed.model.screen(
      const Err(
        ApiError(
          code: 'not_authenticated',
          status: 401,
          serverMessage: 'Entre de novo.',
        ),
      ),
    );

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();

    expect(
      find.text('Sua entrada expirou. Entre de novo para continuar.'),
      findsOneWidget,
    );
  });

  testWidgets('an empty username shows the field error', (tester) async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );

    await tester.pumpWidget(_app(composed.model));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar'));
    await tester.pump();
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('não pode ficar em branco'), findsOneWidget);
  });

  testWidgets('a malformed pasted link is reported', (tester) async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );

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
