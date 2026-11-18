import 'dart:async';
import 'dart:typed_data';

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

  testWidgets('an empty filtered first page loads the next page', (
    tester,
  ) async {
    final _FilteredPaginationApi api = _FilteredPaginationApi();
    await _pumpGallery(tester, gateway: GalleryTestGateway(api: api));
    await tester.pump();

    await tester.tap(find.text('Casa').first);
    await tester.pump();

    api.firstPage.complete(
      Ok(
        Page(
          items: [sampleFile(rkey: 'praca', zona: Zona.praca)],
          nextCursor: 'next',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.photoCalls, 2);
    expect(
      find.byKey(const ValueKey<String>('gallery-tile-casa.jpg')),
      findsOneWidget,
    );
    expect(find.text('Nada na sua casa ainda'), findsNothing);
  });

  testWidgets('a failed empty-filter page does not retry by itself', (
    tester,
  ) async {
    final _FilteredPaginationApi api = _FilteredPaginationApi(
      failNextPage: true,
    );
    await _pumpGallery(tester, gateway: GalleryTestGateway(api: api));
    await tester.pump();

    await tester.tap(find.text('Casa').first);
    await tester.pump();

    api.firstPage.complete(
      Ok(
        Page(
          items: [sampleFile(rkey: 'praca', zona: Zona.praca)],
          nextCursor: 'next',
        ),
      ),
    );
    for (int frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(api.photoCalls, 2);
    expect(find.text('Nada na sua casa ainda'), findsNothing);
    for (int frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(api.photoCalls, 2);
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

final class _FilteredPaginationApi implements TainaApi {
  _FilteredPaginationApi({this.failNextPage = false});

  final Completer<TainaResult<Page<FileRecord>>> firstPage = Completer();
  final FakeTainaApi _assets = FakeTainaApi(delay: Duration.zero);
  final bool failNextPage;
  int photoCalls = 0;

  @override
  Future<TainaResult<Page<FileRecord>>> photos({int? limit, String? cursor}) {
    photoCalls += 1;
    if (cursor == null) return firstPage.future;
    if (failNextPage) return Future.value(const Err(NetworkError()));
    return Future.value(
      Ok(
        Page(
          items: [sampleFile(rkey: 'casa', name: 'casa.jpg')],
          nextCursor: null,
        ),
      ),
    );
  }

  @override
  Future<TainaResult<Page<TimelineGroup>>> photoTimeline({
    int? limit,
    String? cursor,
  }) async {
    return Ok(Page(items: const [], nextCursor: null));
  }

  @override
  Future<TainaResult<Uint8List>> thumbnail({
    required String rkey,
    required ThumbnailSize size,
  }) {
    return _assets.thumbnail(rkey: rkey, size: size);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('${invocation.memberName} is not used here');
  }
}
