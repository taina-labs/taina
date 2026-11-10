import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_core/okena_core.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: Scaffold(body: Center(child: child)),
  );
}

Widget _sized(Widget child) {
  return _app(SizedBox(width: 320, child: child));
}

Widget _reducedMotion(Widget child) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  group('buttons', () {
    testWidgets('primary renders its label, calls back and is full width', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _sized(TainaPrimaryButton(label: 'Entrar', onPressed: () => taps++)),
      );

      expect(find.text('Entrar'), findsOneWidget);
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(TainaSizes.controlMd),
      );

      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
    });

    testWidgets('primary while loading shows a spinner and ignores taps', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _sized(
          TainaPrimaryButton(
            label: 'Entrar',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      );

      expect(find.text('Entrar'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      expect(taps, 0);
    });

    testWidgets('secondary renders and calls back', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _sized(
          TainaSecondaryButton(label: 'Cancelar', onPressed: () => taps++),
        ),
      );

      expect(find.text('Cancelar'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
    });
  });

  group('surfaces', () {
    testWidgets('row card renders content and handles a tap', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _sized(
          TainaRowCard(
            onTap: () => taps++,
            child: const TainaText('Linha', style: TainaTypography.body),
          ),
        ),
      );

      expect(find.text('Linha'), findsOneWidget);
      await tester.tap(find.text('Linha'));
      expect(taps, 1);
    });

    testWidgets('zona badge says Casa with the ybira accent', (tester) async {
      await tester.pumpWidget(_app(const TainaZonaBadge.casa()));

      expect(find.text('Casa'), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      final Container container = tester.widget<Container>(
        find.descendant(
          of: find.byType(TainaZonaBadge),
          matching: find.byType(Container),
        ),
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, TainaPalette.serviceYbiraSoft);
    });

    testWidgets('zona badge says Praça with the jaci accent', (tester) async {
      await tester.pumpWidget(_app(const TainaZonaBadge.praca()));

      expect(find.text('Praça'), findsOneWidget);
      expect(find.byIcon(Icons.people_rounded), findsOneWidget);
      final Container container = tester.widget<Container>(
        find.descendant(
          of: find.byType(TainaZonaBadge),
          matching: find.byType(Container),
        ),
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, TainaPalette.serviceJaciSoft);
    });

    testWidgets('cleartext notice shows the full warning', (tester) async {
      await tester.pumpWidget(_sized(const TainaCleartextNotice()));

      expect(find.text(TainaCleartextNotice.message), findsOneWidget);
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
    });
  });

  group('text field', () {
    testWidgets('renders label, placeholder and help', (tester) async {
      await tester.pumpWidget(
        _sized(
          const TainaTextField(
            label: 'E-mail',
            placeholder: 'voce@casa.ts.net',
            help: 'O mesmo e-mail do convite.',
          ),
        ),
      );

      expect(find.text('E-mail'), findsOneWidget);
      expect(find.text('voce@casa.ts.net'), findsOneWidget);
      expect(find.text('O mesmo e-mail do convite.'), findsOneWidget);
    });

    testWidgets('errors replace the help text', (tester) async {
      await tester.pumpWidget(
        _sized(
          const TainaTextField(
            label: 'Senha',
            help: 'Ao menos 8 caracteres.',
            errorMessages: ['Senha curta.', 'Senha comum.'],
          ),
        ),
      );

      expect(find.text('Senha curta.'), findsOneWidget);
      expect(find.text('Senha comum.'), findsOneWidget);
      expect(find.text('Ao menos 8 caracteres.'), findsNothing);
    });

    testWidgets('secure fields obscure the text', (tester) async {
      await tester.pumpWidget(
        _sized(const TainaTextField(label: 'Senha', obscureText: true)),
      );

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
    });

    testWidgets('accepts typing through a controller', (tester) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _sized(TainaTextField(label: 'Nome', controller: controller)),
      );

      await tester.enterText(find.byType(TextField), 'Ana');
      expect(controller.text, 'Ana');
      expect(find.text('Ana'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('empty state shows the action when both are given', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _sized(
          TainaEmptyState(
            icon: Icons.inbox_rounded,
            title: 'Nada por aqui',
            message: 'Quando a comunidade enviar algo, aparece aqui.',
            actionLabel: 'Tentar de novo',
            onAction: () => taps++,
          ),
        ),
      );

      expect(find.text('Nada por aqui'), findsOneWidget);
      expect(
        find.text('Quando a comunidade enviar algo, aparece aqui.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tentar de novo'));
      expect(taps, 1);
    });

    testWidgets('empty state hides the action without a callback', (
      tester,
    ) async {
      await tester.pumpWidget(
        _sized(
          const TainaEmptyState(
            icon: Icons.inbox_rounded,
            title: 'Nada por aqui',
            message: 'Ainda não há nada.',
            actionLabel: 'Tentar de novo',
          ),
        ),
      );

      expect(find.text('Tentar de novo'), findsNothing);
    });

    testWidgets('error state shows the error message and retries', (
      tester,
    ) async {
      int retries = 0;
      await tester.pumpWidget(
        _sized(
          TainaErrorState(
            error: const NetworkError(),
            onRetry: () async => retries++,
          ),
        ),
      );

      expect(find.text(const NetworkError().message), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      await tester.tap(find.text('Tentar de novo'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('loading list shows four row skeletons', (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.pumpWidget(_reducedMotion(const TainaLoadingList()));

      expect(find.byType(TainaRowCard), findsNWidgets(4));
      expect(find.byType(TainaSkeleton), findsNWidgets(12));
      expect(find.bySemanticsLabel('Carregando'), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('skeleton holds still when motion is disabled', (tester) async {
      await tester.pumpWidget(_reducedMotion(const TainaSkeleton()));

      await tester.pump(const Duration(milliseconds: 800));

      final FadeTransition fade = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byType(TainaSkeleton),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, 1);
    });
  });

  group('text', () {
    testWidgets('applies the overline text case', (tester) async {
      await tester.pumpWidget(
        _app(
          const TainaText(
            'mural',
            style: TainaTypography.overline,
            uppercase: true,
          ),
        ),
      );

      expect(find.text('MURAL'), findsOneWidget);
    });
  });
}
