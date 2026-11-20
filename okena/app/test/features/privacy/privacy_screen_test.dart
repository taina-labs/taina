import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/privacy/privacy_screen.dart';

void main() {
  testWidgets('shows only the board privacy copy, not its annotation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: TainaTheme.data, home: const PrivacyScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Privacidade'), findsOneWidget);
    expect(find.text('Sua casa é só sua'), findsOneWidget);
    expect(
      find.text(
        'Ninguém abre um arquivo da sua casa sem você deixar: quem pede, '
        'você aprova ou recusa.',
      ),
      findsOneWidget,
    );
    expect(find.text('A praça é de todos'), findsOneWidget);
    expect(
      find.text(
        'O que você publica na praça, todo mundo lê. Publicar é um gesto seu, '
        'e dá para voltar atrás.',
      ),
      findsOneWidget,
    );
    expect(find.text('Casa por padrão. Praça por escolha.'), findsOneWidget);
    expect(find.textContaining('promessa técnica'), findsNothing);
    expect(find.textContaining('Ybira'), findsNothing);
    expect(find.textContaining('Jaci'), findsNothing);
  });

  testWidgets('uses the provided back action', (tester) async {
    bool wentBack = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: TainaTheme.data,
        home: PrivacyScreen(onBack: () => wentBack = true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conta'));

    expect(wentBack, isTrue);
  });
}
