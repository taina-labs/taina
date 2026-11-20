import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/components/actions.dart';
import 'package:okena_app/src/design_system/components/forms.dart';
import 'package:okena_app/src/design_system/components/icons.dart';
import 'package:okena_app/src/design_system/components/identity.dart';
import 'package:okena_app/src/design_system/theme.dart';
import 'package:okena_app/src/design_system/tokens.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('TainaButton', () {
    testWidgets('renders the title, icon, and calls its action', (
      tester,
    ) async {
      int calls = 0;
      await tester.pumpWidget(
        _app(
          TainaButton(
            title: 'Continuar',
            icon: TainaIcon.plus,
            action: () => calls++,
          ),
        ),
      );

      expect(find.text('Continuar'), findsOneWidget);
      expect(find.byType(TainaIconView), findsOneWidget);
      expect(
        tester.getSize(find.byType(TainaButton)).height,
        greaterThanOrEqualTo(TainaSizes.touch),
      );

      await tester.tap(find.byType(TainaButton));
      expect(calls, 1);
    });

    testWidgets('loading keeps the title and freezes intrinsic width', (
      tester,
    ) async {
      int calls = 0;
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(TainaButton(title: 'Salvar', action: () => calls++)),
      );

      final Size idleSize = tester.getSize(find.byType(TainaButton));
      expect(find.text('Salvar'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          TainaButton(title: 'Salvar', loading: true, action: () => calls++),
        ),
      );

      expect(find.text('Salvar'), findsOneWidget);
      expect(tester.getSize(find.byType(TainaButton)), idleSize);
      expect(tester.getSemantics(find.byType(TainaButton)).label, 'Salvar');
      expect(tester.getSemantics(find.byType(TainaButton)).value, 'Carregando');

      await tester.tap(find.byType(TainaButton));
      expect(calls, 0);
      semantics.dispose();
    });

    testWidgets('small size keeps a touch-sized target', (tester) async {
      await tester.pumpWidget(
        _app(const TainaButton(title: 'Voltar', size: TainaButtonSize.sm)),
      );

      expect(
        tester.getSize(find.byType(TainaButton)).height,
        greaterThanOrEqualTo(TainaSizes.touch),
      );
    });
  });

  group('TainaIconButton and TainaFAB', () {
    testWidgets('icon button exposes the required accessible label', (
      tester,
    ) async {
      int calls = 0;
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          TainaIconButton(
            icon: TainaIcon.kebab,
            label: 'Mais opções',
            action: () => calls++,
          ),
        ),
      );

      expect(find.bySemanticsLabel('Mais opções'), findsOneWidget);
      expect(tester.getSize(find.byType(TainaIconButton)), const Size(44, 44));
      await tester.tap(find.byType(TainaIconButton));
      expect(calls, 1);
      semantics.dispose();
    });

    testWidgets('FAB remains labeled and disabled while uploading', (
      tester,
    ) async {
      int calls = 0;
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(TainaFAB(label: 'Enviar', uploading: true, action: () => calls++)),
      );

      expect(tester.getSemantics(find.byType(TainaFAB)).label, 'Enviar');
      expect(tester.getSemantics(find.byType(TainaFAB)).value, 'Enviando');
      await tester.tap(find.byType(TainaFAB));
      expect(calls, 0);
      semantics.dispose();
    });
  });

  group('TainaField', () {
    testWidgets('renders help until errors are present', (tester) async {
      await tester.pumpWidget(
        _app(
          const TainaField(
            label: 'Nome',
            help: 'Use o nome que recebeu no convite.',
            errorMessages: ['Confira o nome.'],
          ),
        ),
      );

      expect(find.text('Nome'), findsOneWidget);
      expect(find.text('Confira o nome.'), findsOneWidget);
      expect(find.text('Use o nome que recebeu no convite.'), findsNothing);
    });

    testWidgets('password can be shown with the labeled inline control', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const TainaField(label: 'Senha', kind: TainaFieldKind.password)),
      );

      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      expect(find.bySemanticsLabel('Mostrar senha'), findsOneWidget);
      await tester.tap(find.text('Mostrar'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
      expect(find.bySemanticsLabel('Ocultar senha'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('search and address fields use their Penpot leading icons', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TainaField(label: 'Buscar', kind: TainaFieldKind.search),
              TainaField(label: 'Endereço', kind: TainaFieldKind.address),
            ],
          ),
        ),
      );

      final List<TainaIcon> icons = tester
          .widgetList<TainaIconView>(find.byType(TainaIconView))
          .map((TainaIconView icon) => icon.icon)
          .toList();
      expect(icons, [TainaIcon.search, TainaIcon.servidor]);
      expect(
        tester.widgetList<TextField>(find.byType(TextField)).last.keyboardType,
        TextInputType.url,
      );
    });
  });

  group('TainaSegmented and TainaRadioCard', () {
    testWidgets('segmented selection uses the selected surface and not amber', (
      tester,
    ) async {
      String selection = 'name';
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => TainaSegmented<String>(
              label: 'Ordenar por',
              selection: selection,
              options: const [
                TainaSegmentOption(value: 'name', label: 'Nome'),
                TainaSegmentOption(value: 'date', label: 'Data'),
              ],
              onChanged: (value) => setState(() => selection = value),
            ),
          ),
        ),
      );

      expect(find.text('Nome'), findsOneWidget);
      await tester.tap(find.text('Data'));
      await tester.pump();
      expect(selection, 'date');
      final Ink ink = tester.widget<Ink>(
        find.ancestor(of: find.text('Data'), matching: find.byType(Ink)).first,
      );
      expect(
        (ink.decoration! as BoxDecoration).color,
        TainaPalette.surfaceRaised,
      );
    });

    testWidgets('radio card is selectable and carries radio semantics', (
      tester,
    ) async {
      bool selected = false;
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => TainaRadioCard(
              title: 'Usar o disco inteiro',
              description: 'A comunidade usa todo o espaço disponível.',
              selected: selected,
              action: () => setState(() => selected = !selected),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Usar o disco inteiro'));
      await tester.pump();
      expect(selected, isTrue);
      expect(
        tester
            .getSemantics(find.byType(TainaRadioCard))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      semantics.dispose();
    });
  });

  group('TainaBadge and TainaAvatar', () {
    testWidgets('badge kinds use their Penpot copy and semantic colors', (
      tester,
    ) async {
      const List<(TainaBadgeKind, String)> variants = [
        (TainaBadgeKind.praca, 'praça'),
        (TainaBadgeKind.casa, 'casa'),
        (TainaBadgeKind.zelador, 'zelador'),
        (TainaBadgeKind.morador, 'morador'),
        (TainaBadgeKind.active, 'Com acesso'),
        (TainaBadgeKind.inactive, 'Sem acesso'),
      ];

      for (final (TainaBadgeKind kind, String label) in variants) {
        await tester.pumpWidget(_app(TainaBadge(kind: kind)));
        expect(find.text(label), findsOneWidget);
        expect(find.byType(TainaIconView), findsOneWidget);
      }
    });

    testWidgets('avatar keeps the stable initial, size, and accessible name', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const TainaAvatar(name: 'Ana', size: TainaAvatarSize.lg)),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.bySemanticsLabel('Avatar de Ana'), findsOneWidget);
      expect(tester.getSize(find.byType(TainaAvatar)), const Size(56, 56));
      semantics.dispose();
    });
  });

  group('ServiceSquare and ConnectionNotice', () {
    testWidgets('service square resolves every typed mark to one SVG', (
      tester,
    ) async {
      for (final TainaServiceMark mark in TainaServiceMark.values) {
        await tester.pumpWidget(_app(ServiceSquare(mark: mark)));
        expect(find.byType(TainaIconView), findsOneWidget);
      }
    });

    testWidgets('connection notice uses the board copy and info icon', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(const ConnectionNotice()));

      expect(
        find.text(
          'Esta conexão só fica protegida quando você está na rede da '
          'comunidade. Se não tiver certeza, fale com quem cuida antes de entrar.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(ConnectionNotice)).label,
        ConnectionNotice().message,
      );
      expect(find.byType(TainaIconView), findsOneWidget);
      semantics.dispose();
    });
  });
}
