import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/components/actions.dart';
import 'package:okena_app/src/design_system/components/icons.dart';
import 'package:okena_app/src/design_system/components/overlays.dart';
import 'package:okena_app/src/design_system/theme.dart';

void main() {
  group('TainaSheet', () {
    testWidgets('shows a visible close action and closes the sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TainaTheme.data,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => TainaSheet.show<void>(
                  context: context,
                  title: 'Opções',
                  child: const Text('Conteúdo'),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Fechar'), findsOneWidget);
      expect(find.text('Conteúdo'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Conteúdo'), findsNothing);
    });
  });

  group('ActionsMenu', () {
    testWidgets('shows menu actions in a sheet and forwards selection', (
      tester,
    ) async {
      int selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TainaTheme.data,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ActionsMenu.show(
                  context: context,
                  actions: [
                    TainaMenuAction(
                      label: 'Renomear',
                      icon: TainaIcon.file,
                      onSelected: () => selected++,
                    ),
                  ],
                ),
                child: const Text('Menu'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Fechar'), findsOneWidget);
      await tester.tap(find.text('Renomear'));
      await tester.pumpAndSettle();
      expect(selected, 1);
    });

    testWidgets('disabled actions do not invoke their callback', (
      tester,
    ) async {
      int selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TainaTheme.data,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ActionsMenu.show(
                  context: context,
                  actions: [
                    TainaMenuAction(
                      label: 'Remover',
                      icon: TainaIcon.trash,
                      onSelected: () => selected++,
                      enabled: false,
                    ),
                  ],
                ),
                child: const Text('Menu'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pump();
      expect(selected, 0);
      expect(find.text('Fechar'), findsOneWidget);
    });
  });

  group('TainaDialog', () {
    testWidgets('confirm dialog keeps both actions at equal width', (
      tester,
    ) async {
      int confirmations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TainaTheme.data,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => TainaDialog.confirm(
                  context: context,
                  title: 'Continuar?',
                  message: 'Confirme esta ação.',
                  onConfirm: () => confirmations++,
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final Finder buttons = find.descendant(
        of: find.byType(TainaDialog),
        matching: find.byType(TainaButton),
      );
      expect(buttons, findsNWidgets(2));
      expect(
        tester.getSize(buttons.first).width,
        tester.getSize(buttons.last).width,
      );
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(confirmations, 1);
    });

    testWidgets('destructive dialog exposes an explicit safe action', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TainaTheme.data,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => TainaDialog.destructive(
                  context: context,
                  title: 'Remover arquivo?',
                  message: 'O arquivo deixará de aparecer aqui.',
                  confirmLabel: 'Remover',
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Remover'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('haptics only on destructive confirmation', (tester) async {
      final List<MethodCall> platformCalls = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TainaTheme.data,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => TainaDialog.destructive(
                  context: context,
                  title: 'Remover arquivo?',
                  message: 'O arquivo vai para a lixeira.',
                  confirmLabel: 'Remover',
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(
        platformCalls.where((call) => call.method == 'HapticFeedback.vibrate'),
        isEmpty,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(
        platformCalls.where((call) => call.method == 'HapticFeedback.vibrate'),
        isEmpty,
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(
        platformCalls
            .where((call) => call.method == 'HapticFeedback.vibrate')
            .single
            .arguments,
        'HapticFeedbackType.lightImpact',
      );
    });
  });
}
