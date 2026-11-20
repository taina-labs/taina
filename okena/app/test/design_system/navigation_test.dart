import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/components/identity.dart';
import 'package:okena_app/src/design_system/components/icons.dart';
import 'package:okena_app/src/design_system/components/navigation.dart';
import 'package:okena_app/src/design_system/components/text.dart';
import 'package:okena_app/src/design_system/theme.dart';
import 'package:okena_app/src/design_system/tokens.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: Scaffold(body: child),
  );
}

void main() {
  group('navigation mappings', () {
    test('maps back targets to pt-BR labels', () {
      expect(tainaBackLabel(TainaBackTarget.hub), 'Início');
      expect(tainaBackLabel(TainaBackTarget.documentos), 'Documentos');
      expect(tainaBackLabel(TainaBackTarget.galeria), 'Galeria');
      expect(tainaBackLabelForParent('Atas'), 'Atas');
      expect(tainaBackLabelForParent('Pasta muito longa'), 'Voltar');
      expect(tainaBackLabelForParent(null), 'Voltar');
    });

    test('maps document and gallery tabs', () {
      expect(TainaDocumentTab.values.map(tainaDocumentTabLabel), [
        'Praça',
        'Casa',
        'Lixeira',
      ]);
      expect(TainaGalleryTab.values.map(tainaGalleryTabLabel), [
        'Grade',
        'Linha do tempo',
      ]);
      expect(tainaDocumentTabIcon(TainaDocumentTab.casa), TainaIcon.casa);
      expect(tainaGalleryTabIcon(TainaGalleryTab.grade), TainaIcon.grid);
    });
  });

  group('headers', () {
    testWidgets('service header has back label, centered title and action', (
      tester,
    ) async {
      int backs = 0;
      await tester.pumpWidget(
        _app(
          ServiceHeader(
            title: 'Documentos',
            backLabel: 'Início',
            onBack: () => backs++,
            action: IconButton(
              tooltip: 'Adicionar',
              onPressed: () {},
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
      );

      expect(find.text('Início'), findsOneWidget);
      expect(find.text('Documentos'), findsOneWidget);
      await tester.tap(find.text('Início'));
      expect(backs, 1);
      expect(find.byTooltip('Adicionar'), findsOneWidget);
    });

    testWidgets('hub and page headers render their titles', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              HubHeader(greeting: 'Boa noite, Ana'),
              PageHeader(title: 'Arquivos'),
            ],
          ),
        ),
      );

      expect(find.text('Boa noite, Ana'), findsOneWidget);
      expect(find.text('Arquivos'), findsOneWidget);
      final TainaText greeting = tester.widget(
        find.widgetWithText(TainaText, 'Boa noite, Ana'),
      );
      expect(greeting.style, TainaTypography.h1);
    });

    testWidgets('hub header composes greeting, community and account action', (
      tester,
    ) async {
      int accountOpens = 0;
      await tester.pumpWidget(
        _app(
          HubHeader(
            greeting: 'Boa noite, Ana',
            communityName: 'Quilombo do Café',
            userName: 'Ana',
            onAccount: () => accountOpens++,
            careLine: const Text('Há um pedido aguardando resposta.'),
          ),
        ),
      );

      final TainaText greeting = tester.widget(
        find.widgetWithText(TainaText, 'Boa noite, Ana'),
      );
      final TainaText community = tester.widget(
        find.widgetWithText(TainaText, 'Quilombo do Café'),
      );
      expect(greeting.style, TainaTypography.bodySm);
      expect(community.style, TainaTypography.h1);
      expect(find.byType(TainaAvatar), findsOneWidget);
      expect(find.text('Há um pedido aguardando resposta.'), findsOneWidget);

      await tester.tap(find.byTooltip('Conta'));
      expect(accountOpens, 1);
    });

    testWidgets('sliver header can be composed in a CustomScrollView', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TainaTheme.data,
          home: CustomScrollView(
            slivers: [
              PageHeaderSliver(
                title: 'Fotos',
                backLabel: 'Início',
                onBack: _noop,
                action: IconButton(
                  tooltip: 'Ação',
                  onPressed: _noop,
                  icon: const Icon(Icons.more_horiz),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: 800, child: Text('Conteúdo')),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Fotos'), findsOneWidget);
      expect(find.text('Início'), findsOneWidget);
      expect(find.byTooltip('Ação'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(find.text('Fotos'), findsOneWidget);
      expect(find.text('Início'), findsOneWidget);
      expect(find.byTooltip('Ação'), findsOneWidget);
    });

    testWidgets('service sliver keeps its labeled back while collapsing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TainaTheme.data,
          home: CustomScrollView(
            slivers: [
              ServiceHeaderSliver(
                title: 'Documentos',
                backLabel: 'Início',
                onBack: _noop,
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: 800, child: Text('Conteúdo')),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Início'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(find.text('Documentos'), findsOneWidget);
      expect(find.text('Início'), findsOneWidget);
    });
  });

  group('service tabs', () {
    testWidgets('document tabs select and report each typed tab', (
      tester,
    ) async {
      TainaDocumentTab? selected;
      await tester.pumpWidget(
        _app(
          ServiceTabBar.documents(
            selected: TainaDocumentTab.praca,
            onSelected: (tab) => selected = tab,
          ),
        ),
      );

      expect(find.text('Praça'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Lixeira'), findsOneWidget);
      expect(tester.getSize(find.byType(ServiceTabBar)).height, 72);
      await tester.tap(find.text('Casa'));
      expect(selected, TainaDocumentTab.casa);
    });

    testWidgets('gallery tabs expose grade and line choices', (tester) async {
      TainaGalleryTab? selected;
      await tester.pumpWidget(
        _app(
          ServiceTabBar.gallery(
            selected: TainaGalleryTab.grade,
            onSelected: (tab) => selected = tab,
          ),
        ),
      );

      expect(find.text('Grade'), findsOneWidget);
      expect(find.text('Linha do tempo'), findsOneWidget);
      await tester.tap(find.text('Linha do tempo'));
      expect(selected, TainaGalleryTab.linha);
    });
  });
}

void _noop() {}
