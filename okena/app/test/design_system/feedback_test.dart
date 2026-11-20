import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/components/actions.dart';
import 'package:okena_app/src/design_system/components/feedback.dart';
import 'package:okena_app/src/design_system/components/icons.dart';
import 'package:okena_app/src/design_system/theme.dart';
import 'package:okena_app/src/design_system/tokens.dart';
import 'package:qr_flutter/qr_flutter.dart';

Widget _app(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: DefaultAssetBundle(
      bundle: _IconAssetBundle(),
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(width: 360, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('EmptyStateView', () {
    testWidgets('renders copy and invokes its optional action', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _app(
          EmptyStateView(
            icon: TainaIcon.folder,
            title: 'Sua casa está vazia',
            body: 'Envie um arquivo para começar.',
            actionLabel: 'Enviar um arquivo',
            onAction: () => taps++,
          ),
        ),
      );

      expect(find.text('Sua casa está vazia'), findsOneWidget);
      expect(find.text('Envie um arquivo para começar.'), findsOneWidget);
      expect(find.byType(TainaButton), findsOneWidget);

      await tester.tap(find.text('Enviar um arquivo'));
      expect(taps, 1);
    });

    testWidgets('allows callers to provide a composed action', (tester) async {
      await tester.pumpWidget(
        _app(
          EmptyStateView(
            icon: TainaIcon.folder,
            title: 'Nada no mural ainda',
            body: 'Quando alguém publicar, aparece aqui.',
            actionBuilder: (_) => const Text('Ação composta'),
          ),
        ),
      );

      expect(find.text('Ação composta'), findsOneWidget);
    });
  });

  group('ErrorCard', () {
    testWidgets('offers retry and optional contact actions', (tester) async {
      int retries = 0;
      int contacts = 0;
      await tester.pumpWidget(
        _app(
          ErrorCard(
            title: 'Não conseguimos falar com a nuvem agora.',
            body: 'Tente de novo em instantes.',
            retry: () => retries++,
            contact: () => contacts++,
          ),
        ),
      );

      expect(
        find.text('Não conseguimos falar com a nuvem agora.'),
        findsOneWidget,
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.text('Falar com quem cuida'), findsOneWidget);

      await tester.tap(find.text('Tentar de novo'));
      await tester.tap(find.text('Falar com quem cuida'));
      expect(retries, 1);
      expect(contacts, 1);
    });

    testWidgets('does not render controls without callbacks', (tester) async {
      await tester.pumpWidget(
        _app(
          const ErrorCard(
            title: 'Falha ao carregar.',
            body: 'Tente mais tarde.',
          ),
        ),
      );

      expect(find.byType(TainaButton), findsNothing);
    });
  });

  group('SkeletonView', () {
    testWidgets('renders each skeleton shape and count', (tester) async {
      await tester.pumpWidget(
        _app(const SkeletonView(kind: TainaSkeletonKind.listRow, count: 3)),
      );
      expect(find.bySemanticsLabel('Carregando'), findsOneWidget);
      expect(find.byType(SkeletonView), findsOneWidget);

      await tester.pumpWidget(
        _app(const SkeletonView(kind: TainaSkeletonKind.photoGrid, count: 6)),
      );
      final GridView grid = tester.widget<GridView>(find.byType(GridView));
      expect(grid.childrenDelegate.estimatedChildCount, 6);

      await tester.pumpWidget(
        _app(const SkeletonView(kind: TainaSkeletonKind.card, count: 2)),
      );
      expect(find.byType(DecoratedBox), findsNWidgets(6));
    });

    testWidgets('does not animate when reduced motion is enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SkeletonView(kind: TainaSkeletonKind.listRow),
          reduceMotion: true,
        ),
      );

      await tester.pump(const Duration(milliseconds: 800));

      final FadeTransition fade = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byType(SkeletonView),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, 1);
    });
  });

  group('TainaToast', () {
    testWidgets('renders info and error feedback as live regions', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      for (final TainaToastKind kind in TainaToastKind.values) {
        await tester.pumpWidget(
          _app(TainaToast(kind: kind, text: 'Convite criado.')),
        );

        expect(find.text('Convite criado.'), findsOneWidget);
        expect(find.byType(TainaIconView), findsOneWidget);
        expect(
          tester
              .getSemantics(find.byType(TainaToast))
              .getSemanticsData()
              .flagsCollection,
          isA<SemanticsFlags>().having(
            (flags) => flags.isLiveRegion,
            'isLiveRegion',
            isTrue,
          ),
        );
      }
      semantics.dispose();
    });
  });

  group('QRCard', () {
    testWidgets('renders a token-colored QR and invokes copy', (tester) async {
      int copies = 0;
      await tester.pumpWidget(
        _app(
          QRCard(
            link: 'https://taina.local/convite/abc123',
            description: 'Quem entrar vê a praça e ganha uma casa própria.',
            onCopy: () => copies++,
          ),
        ),
      );

      expect(find.text('LINK DO CONVITE'), findsOneWidget);
      expect(find.text('Copiar link'), findsOneWidget);
      final QrImageView qr = tester.widget<QrImageView>(
        find.byType(QrImageView),
      );
      expect(qr.size, TainaSizes.qr);
      expect(qr.backgroundColor, TainaPalette.bgQr);
      expect(qr.eyeStyle.color, TainaPalette.textOnBrand);
      expect(qr.dataModuleStyle.color, TainaPalette.textOnBrand);

      await tester.tap(find.text('Copiar link'));
      expect(copies, 1);
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
