import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/components/actions.dart';
import 'package:okena_app/src/design_system/components/content.dart';
import 'package:okena_app/src/design_system/components/icons.dart';
import 'package:okena_app/src/design_system/components/identity.dart';
import 'package:okena_app/src/design_system/theme.dart';
import 'package:okena_app/src/design_system/tokens.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: DefaultAssetBundle(
      bundle: _IconAssetBundle(),
      child: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 360, child: child)),
      ),
    ),
  );
}

void main() {
  group('TainaCard', () {
    testWidgets('renders the child with standard and raised surfaces', (
      tester,
    ) async {
      for (final TainaCardKind kind in TainaCardKind.values) {
        await tester.pumpWidget(
          _app(TainaCard(kind: kind, child: Text(kind.name))),
        );

        expect(find.text(kind.name), findsOneWidget);
        final Material material = tester.widget<Material>(
          find.descendant(
            of: find.byType(TainaCard),
            matching: find.byType(Material),
          ),
        );
        expect(
          material.color,
          kind == TainaCardKind.raised
              ? TainaPalette.surfaceRaised
              : TainaPalette.surfaceDefault,
        );
      }
    });
  });

  group('TainaListRow', () {
    testWidgets('renders each typed kind and exposes its row semantics', (
      tester,
    ) async {
      for (final TainaListRowKind kind in TainaListRowKind.values) {
        await tester.pumpWidget(
          _app(
            TainaListRow(
              kind: kind,
              title: 'Item ${kind.name}',
              meta: 'Metadado',
              onTap: () {},
              showDivider: false,
            ),
          ),
        );

        expect(find.text('Item ${kind.name}'), findsOneWidget);
        expect(find.text('Metadado'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is Semantics &&
                widget.properties.label == 'Item ${kind.name}, Metadado',
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('renders all trailing variants with a 44-pixel kebab target', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              for (final TainaListRowTrailing trailing
                  in TainaListRowTrailing.values)
                TainaListRow(
                  kind: TainaListRowKind.file,
                  title: trailing.name,
                  trailing: trailing,
                  trailingLabel: trailing == TainaListRowTrailing.action
                      ? 'Abrir'
                      : 'Mais ações',
                  onTrailingPressed: () => taps++,
                  showDivider: false,
                ),
            ],
          ),
        ),
      );

      expect(find.text('Abrir'), findsOneWidget);
      expect(find.byType(TainaIconButton), findsOneWidget);
      expect(
        tester.getSize(find.byType(TainaIconButton)).height,
        greaterThanOrEqualTo(TainaSizes.touch),
      );

      await tester.tap(find.byType(TainaIconButton));
      expect(taps, 1);
    });

    testWidgets('renders waiting and resolved pedido states', (tester) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              TainaListRow(
                kind: TainaListRowKind.pedido,
                title: 'Carla pediu acesso',
                state: TainaPedidoState.esperando,
                actionsBuilder: (context) => const Row(
                  children: [
                    Expanded(child: Text('Recusar')),
                    Expanded(child: Text('Dar acesso')),
                  ],
                ),
                showDivider: false,
              ),
              for (final TainaPedidoState state in [
                TainaPedidoState.dado,
                TainaPedidoState.recusado,
              ])
                TainaListRow(
                  kind: TainaListRowKind.pedido,
                  title: 'Pedido resolvido',
                  state: state,
                  stateSummary: state.name,
                  showDivider: false,
                ),
            ],
          ),
        ),
      );

      expect(find.text('Recusar'), findsOneWidget);
      expect(find.text('Dar acesso'), findsOneWidget);
      expect(find.text('dado'), findsOneWidget);
      expect(find.text('recusado'), findsOneWidget);
      expect(find.byType(StatusLine), findsNWidgets(2));
    });
  });

  group('service and community content', () {
    testWidgets('ServiceCard renders both service variants and opens', (
      tester,
    ) async {
      int taps = 0;
      for (final ServiceCardService service in ServiceCardService.values) {
        await tester.pumpWidget(
          _app(
            ServiceCard(
              service: service,
              title: service.name,
              body: 'Arquivos da casa e da praça',
              onTap: () => taps++,
            ),
          ),
        );

        expect(find.text(service.name), findsOneWidget);
        expect(find.byType(ServiceSquare), findsOneWidget);
        await tester.tap(find.text(service.name));
        expect(taps, service.index + 1);
      }
    });

    testWidgets('CareLine calls its response action', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _app(
          CareLine(
            text: 'Carla pediu para abrir um arquivo da sua casa',
            actionLabel: 'Responder',
            action: () => taps++,
          ),
        ),
      );

      await tester.tap(find.text('Responder'));
      expect(taps, 1);
    });

    testWidgets('StorageCard renders compact and full details', (tester) async {
      const StorageSummary summary = StorageSummary(
        usedLabel: '236 GB',
        caption: '236 GB de 256 GB usados',
        progress: 0.92,
        freeLabel: '20 GB livres',
      );

      await tester.pumpWidget(_app(const StorageCard(summary: summary)));
      expect(find.text('Espaço da comunidade'), findsOneWidget);
      expect(find.text('Ver detalhes'), findsOneWidget);
      expect(find.byType(TainaProgress), findsOneWidget);

      await tester.pumpWidget(
        _app(
          const StorageCard(
            summary: summary,
            detail: TainaStorageDetail.full,
            tone: TainaStorageTone.warning,
          ),
        ),
      );
      expect(find.text('236 GB'), findsOneWidget);
      expect(find.text('Espaço da comunidade'), findsOneWidget);
      expect(find.text('20 GB livres'), findsOneWidget);
      expect(find.text('Ver detalhes'), findsNothing);
    });

    testWidgets('TainaProgress announces a clamped percentage', (tester) async {
      await tester.pumpWidget(
        _app(
          const TainaProgress(
            value: 1.4,
            tone: TainaProgressTone.warning,
            semanticLabel: 'Espaço usado',
          ),
        ),
      );

      final SemanticsData semantics = tester
          .getSemantics(find.byType(TainaProgress))
          .getSemanticsData();
      expect(semantics.label, 'Espaço usado');
      expect(semantics.value, '100%');
    });

    testWidgets('StatusLine has a readable title for every state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              for (final TainaStatusState state in TainaStatusState.values)
                StatusLine(state: state, title: 'Estado ${state.name}'),
            ],
          ),
        ),
      );

      for (final TainaStatusState state in TainaStatusState.values) {
        expect(find.text('Estado ${state.name}'), findsOneWidget);
      }
      expect(find.byType(TainaIconView), findsNWidgets(4));
    });
  });
}

final class _IconAssetBundle extends CachingAssetBundle {
  static final Uint8List _svgBytes = Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<path d="M2 2h20v20H2z" fill="#000"/>'
      '</svg>',
    ),
  );

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(_svgBytes);
}
