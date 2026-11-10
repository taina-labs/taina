import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/gallery/gallery.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fake_gateway.dart';

Widget _app(Widget child) => MaterialApp(theme: TainaTheme.data, home: child);

Future<void> _pumpGallery(
  WidgetTester tester, {
  required GalleryTestGateway gateway,
  GalleryShareFile? onShare,
  GalleryImmersiveChanged? onImmersive,
  FakeVideoPlayerFactory? players,
}) async {
  await tester.pumpWidget(
    _app(
      GalleryScreen(
        gateway: gateway,
        onShareFile: onShare,
        onImmersiveChanged: onImmersive,
        playerFactory: players?.call ?? defaultGalleryVideoPlayer,
      ),
    ),
  );
}

Future<void> _openViewer(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey<String>('gallery-tile-$name')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('grid and filter render the readable set', (tester) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text('Fotos'), findsOneWidget);
    expect(find.text('Grade'), findsOneWidget);
    expect(find.text('Linha do tempo'), findsOneWidget);
    expect(find.text('Tudo'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Praça'), findsOneWidget);
    expect(find.byType(TainaZonaBadge), findsNWidgets(3));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('the casa filter narrows to the zone empty state', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Casa').first);
    await tester.pumpAndSettle();

    expect(find.text('Nada na sua casa ainda'), findsOneWidget);
    expect(find.byType(TainaZonaBadge), findsNothing);

    await tester.tap(find.text('Tudo'));
    await tester.pumpAndSettle();
    expect(find.byType(TainaZonaBadge), findsNWidgets(3));
  });

  testWidgets('the timeline groups the photos in days', (tester) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Linha do tempo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 fotos'), findsOneWidget);
    expect(find.byType(TainaZonaBadge), findsNWidgets(3));
  });

  testWidgets('the loading state is a grid of skeletons', (tester) async {
    final GalleryTestGateway gateway = GalleryTestGateway(
      delay: const Duration(milliseconds: 120),
    );
    await _pumpGallery(tester, gateway: gateway);
    await tester.pump();

    expect(find.byType(TainaSkeleton), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.byType(TainaSkeleton), findsNothing);
  });

  testWidgets('a failure shows the error and the retry recovers', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    gateway.failNextScreen = true;
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text(const NetworkError().message), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.byType(TainaZonaBadge), findsNWidgets(3));
  });

  testWidgets('the thumbnail store answers a second pass from the cache', (
    tester,
  ) async {
    final FastGalleryApi api = FastGalleryApi();
    final GalleryTestGateway gateway = GalleryTestGateway(api: api);
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    // Only the two images ask for a thumbnail; the video already has a play
    // placeholder.
    expect(api.thumbnailCalls, 2);

    await tester.tap(find.text('Casa').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tudo'));
    await tester.pumpAndSettle();

    expect(api.thumbnailCalls, 2);
  });

  testWidgets('the viewer opens at the tapped photo and navigates', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    await _openViewer(tester, 'Foto da quadra.jpg');

    expect(find.text('2 de 3'), findsOneWidget);
    expect(find.text('Compartilhar'), findsOneWidget);
    expect(find.text('Detalhes'), findsOneWidget);
    expect(find.text('Tirar da praça'), findsOneWidget);
    expect(find.text('Excluir'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('3 de 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('Fechar'), findsNothing);
    expect(find.text('Fotos'), findsOneWidget);
  });

  testWidgets('the details sheet shows the file facts', (tester) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');

    await tester.tap(find.text('Detalhes'));
    await tester.pumpAndSettle();

    expect(find.text('NOME ORIGINAL'), findsOneWidget);
    expect(find.text('Foto da quadra.jpg'), findsWidgets);
    expect(find.text('ASSINATURA DO ARQUIVO'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('NOME ORIGINAL'), findsNothing);
  });

  testWidgets('share downloads once and hands the path to the integration', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    String? shared;
    await _pumpGallery(
      tester,
      gateway: gateway,
      onShare: (String path) async {
        shared = path;
        return null;
      },
    );
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();

    expect(shared, isNotNull);
    expect(shared, isNotEmpty);
  });

  testWidgets('deleting closes the viewer and removes the tile', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');

    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir "Foto da quadra.jpg"?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Excluir'));
    await tester.pumpAndSettle();

    expect(find.text('Fechar'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('gallery-tile-Foto da quadra.jpg')),
      findsNothing,
    );
    expect(find.byType(TainaZonaBadge), findsNWidgets(2));
  });

  testWidgets('the viewer reports immersive mode until it closes', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    final immersive = <bool>[];
    await _pumpGallery(tester, gateway: gateway, onImmersive: immersive.add);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');

    expect(immersive, [true]);

    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(immersive, [true, false]);
  });

  testWidgets('the video page downloads, plays and disposes with the viewer', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    final FakeVideoPlayerFactory players = FakeVideoPlayerFactory();
    await _pumpGallery(tester, gateway: gateway, players: players);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Apresentacao na escola.mp4');

    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('Toque para assistir'), findsOneWidget);

    await tester.tap(find.text('Toque para assistir'));
    await tester.pumpAndSettle();

    expect(players.made, hasLength(1));
    expect(players.made.single.initialized, isTrue);
    expect(players.made.single.playing, isTrue);

    await tester.tap(find.bySemanticsLabel('Pausar vídeo'));
    await tester.pumpAndSettle();
    expect(players.made.single.paused, isTrue);

    await tester.tap(find.bySemanticsLabel('Reproduzir vídeo'));
    await tester.pumpAndSettle();
    expect(players.made.single.playing, isTrue);

    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(players.made.single.disposed, isTrue);
  });

  testWidgets('a video download failure offers the retry', (tester) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    final FakeVideoPlayerFactory players = FakeVideoPlayerFactory();
    await _pumpGallery(tester, gateway: gateway, players: players);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Apresentacao na escola.mp4');

    gateway.failNextScreen = true;
    await tester.tap(find.text('Toque para assistir'));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível abrir o vídeo.'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(players.made, hasLength(1));
    expect(players.made.single.playing, isTrue);
  });

  testWidgets('a player initialization failure keeps the retry surface', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    final FakeVideoPlayerFactory players = FakeVideoPlayerFactory(
      failInitialize: true,
    );
    await _pumpGallery(tester, gateway: gateway, players: players);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Apresentacao na escola.mp4');

    await tester.tap(find.text('Toque para assistir'));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível abrir o vídeo.'), findsOneWidget);
    expect(players.made, hasLength(1));

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(players.made, hasLength(2));
  });
}
