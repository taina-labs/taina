import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/camera_roll/media_picker.dart';
import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/features/gallery/gallery.dart';
import 'package:okena_app/src/session/upload_center.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fake_gateway.dart';

Widget _app(Widget child) => MaterialApp(theme: TainaTheme.data, home: child);

Future<void> _pumpGallery(
  WidgetTester tester, {
  required GalleryTestGateway gateway,
  GalleryShareFile? onShare,
  GalleryImmersiveChanged? onImmersive,
  FakeVideoPlayerFactory? players,
  TainaGalleryTab initialTab = TainaGalleryTab.grade,
  MediaPicker? mediaPicker,
  UploadCenter? uploadCenter,
  ValueChanged<TainaGalleryTab>? onNavigateTab,
  VoidCallback? onOpenUpload,
}) async {
  await tester.pumpWidget(
    _app(
      GalleryScreen(
        gateway: gateway,
        onShareFile: onShare,
        onImmersiveChanged: onImmersive,
        playerFactory: players?.call ?? defaultGalleryVideoPlayer,
        initialTab: initialTab,
        mediaPicker: mediaPicker,
        uploadCenter: uploadCenter,
        onNavigateTab: onNavigateTab,
        onOpenUpload: onOpenUpload,
      ),
    ),
  );
}

Future<void> _openViewer(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey<String>('gallery-tile-$name')));
  await tester.pumpAndSettle();
}

Future<void> _openActions(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Ações da foto'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('grade shows media without zone filters or tile badges', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text('Galeria'), findsOneWidget);
    expect(find.text('Grade'), findsOneWidget);
    expect(find.text('Linha do tempo'), findsOneWidget);
    expect(find.text('Tudo'), findsNothing);
    expect(find.text('Praça'), findsNothing);
    expect(find.text('Casa'), findsNothing);
    expect(find.byType(TainaZonaBadge), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('gallery-tile-Foto da quadra.jpg')),
      findsOneWidget,
    );
    expect(find.text('2 fotos e vídeos'), findsOneWidget);
  });

  testWidgets('timeline preserves day titles and reports route replacement', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    final List<TainaGalleryTab> selected = [];
    await _pumpGallery(tester, gateway: gateway, onNavigateTab: selected.add);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Linha do tempo'));
    await tester.pumpAndSettle();

    expect(selected, [TainaGalleryTab.linha]);
    expect(find.text('21 de junho'), findsOneWidget);
    expect(find.byType(TainaZonaBadge), findsNothing);
  });

  testWidgets('an initial timeline route selects the timeline tab', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(
      tester,
      gateway: gateway,
      initialTab: TainaGalleryTab.linha,
    );
    await tester.pumpAndSettle();

    expect(find.text('21 de junho'), findsOneWidget);
  });

  testWidgets('loading uses the photo-grid skeleton', (tester) async {
    final GalleryTestGateway gateway = GalleryTestGateway(
      delay: const Duration(milliseconds: 120),
    );
    await _pumpGallery(tester, gateway: gateway);
    await tester.pump();

    expect(find.byType(SkeletonView), findsOneWidget);
    expect(find.byType(TainaSkeleton), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonView), findsNothing);
  });

  testWidgets('empty gallery offers the Enviar uma foto action', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway(
      api: FastGalleryApi(emptyGallery: true),
    );
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text('Ainda não há fotos'), findsOneWidget);
    expect(
      find.text(
        'Quando alguém enviar uma foto, ela aparece aqui para toda a comunidade.',
      ),
      findsOneWidget,
    );
    expect(find.text('Enviar uma foto'), findsOneWidget);
    expect(find.bySemanticsLabel('Enviar'), findsOneWidget);
  });

  testWidgets('a gallery failure renders an error card and retry recovers', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    gateway.failNextScreen = true;
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorCard), findsOneWidget);
    expect(find.text(const NetworkError().message), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('gallery-tile-Foto da quadra.jpg')),
      findsOneWidget,
    );
  });

  testWidgets('storage videos count is used when available', (tester) async {
    const StorageStats stats = StorageStats(
      usedBytes: 0,
      quotaBytes: null,
      byKind: StorageByKind(photos: 0, videos: 0, documents: 0, others: 0),
      files: 0,
      photos: 38,
      videos: 4,
      trash: StorageTrash(count: 0, bytes: 0),
    );
    final GalleryTestGateway gateway = GalleryTestGateway(
      api: FastGalleryApi(storageStats: stats),
    );
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text('38 fotos, 4 vídeos'), findsOneWidget);
  });

  testWidgets('failed storage count falls back to loaded media count', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway(
      api: FastGalleryApi(failStorage: true),
    );
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text('3 fotos e vídeos'), findsOneWidget);
  });

  testWidgets('viewer uses chrome, caption and swipe navigation', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');

    expect(find.text('2 de 3'), findsOneWidget);
    expect(
      find.text('Foto da quadra.jpg, 21 de junho, na praça'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Fechar visualização'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Próxima foto'));
    await tester.pumpAndSettle();
    expect(find.text('3 de 3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Fechar visualização'));
    await tester.pumpAndSettle();
    expect(find.text('Galeria'), findsOneWidget);
  });

  testWidgets('viewer image failure shows retry in an error card', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway(
      api: FastGalleryApi(failThumbnail: true),
    );
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');

    expect(find.text('Não conseguimos abrir esta foto'), findsOneWidget);
    expect(find.byType(ErrorCard), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('viewer actions menu offers zone, download, share and remove', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');

    await _openActions(tester);
    expect(find.text('Tirar da praça'), findsOneWidget);
    expect(find.text('Baixar'), findsOneWidget);
    expect(find.text('Compartilhar'), findsOneWidget);
    expect(find.text('Excluir'), findsOneWidget);
    expect(find.text('Detalhes'), findsOneWidget);
  });

  testWidgets('details remain reachable through the actions menu', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');
    await _openActions(tester);

    await tester.tap(find.text('Detalhes'));
    await tester.pumpAndSettle();

    expect(find.text('NOME ORIGINAL'), findsOneWidget);
    expect(find.text('Foto da quadra.jpg'), findsWidgets);
    expect(find.text('ASSINATURA DO ARQUIVO'), findsOneWidget);
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
    await _openActions(tester);

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();

    expect(shared, isNotNull);
    expect(shared, isNotEmpty);
  });

  testWidgets('download opens the system save/share handoff', (tester) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    String? downloaded;
    await _pumpGallery(
      tester,
      gateway: gateway,
      onShare: (String path) async {
        downloaded = path;
        return null;
      },
    );
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');
    await _openActions(tester);

    await tester.tap(find.text('Baixar'));
    await tester.pumpAndSettle();

    expect(downloaded, '/tmp/okena-test-3m7d1wyzr4c8u');
  });

  testWidgets('zone action confirms and updates the viewer caption', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');
    await _openActions(tester);

    await tester.tap(find.text('Tirar da praça'));
    await tester.pumpAndSettle();
    expect(find.text('Tirar "Foto da quadra.jpg" da praça?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Tirar da praça'));
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');

    expect(
      find.text('Foto da quadra.jpg, 21 de junho, na casa'),
      findsOneWidget,
    );
  });

  testWidgets('download failure is a toast, not an alert dialog', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');
    await _openActions(tester);

    gateway.failNextScreen = true;
    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();

    expect(find.byType(TainaToast), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('deleting closes the viewer and removes the tile', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    await _pumpGallery(tester, gateway: gateway);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');
    await _openActions(tester);

    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir "Foto da quadra.jpg"?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Excluir'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Fechar visualização'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('gallery-tile-Foto da quadra.jpg')),
      findsNothing,
    );
  });

  testWidgets('viewer reports immersive mode until it closes', (tester) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    final List<bool> immersive = [];
    await _pumpGallery(tester, gateway: gateway, onImmersive: immersive.add);
    await tester.pumpAndSettle();
    await _openViewer(tester, 'Foto da quadra.jpg');

    expect(immersive, [true]);

    await tester.tap(find.bySemanticsLabel('Fechar visualização'));
    await tester.pumpAndSettle();
    expect(immersive, [true, false]);
  });

  testWidgets(
    'Enviar starts UploadCenter and calls the existing route callback',
    (tester) async {
      final FastGalleryApi api = FastGalleryApi();
      final GalleryTestGateway gateway = GalleryTestGateway(api: api);
      final UploadCenter center = UploadCenter(gateway: gateway);
      addTearDown(center.dispose);
      final _FakeMediaPicker picker = _FakeMediaPicker(
        MediaPickerSelected([
          PickedFile(
            path: '/tmp/foto.jpg',
            name: 'foto.jpg',
            mime: 'image/jpeg',
          ),
        ]),
      );
      int openUploadCalls = 0;
      await _pumpGallery(
        tester,
        gateway: gateway,
        mediaPicker: picker,
        uploadCenter: center,
        onOpenUpload: () => openUploadCalls += 1,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Enviar'));
      await tester.pumpAndSettle();

      expect(picker.pickCalls, 1);
      expect(api.lastUpload?.path, '/tmp/foto.jpg');
      expect(api.lastUpload?.folderRkey, isNull);
      expect(center.state, isA<UploadSucceeded>());
      expect((center.state as UploadSucceeded).file.zona, Zona.casa);
      expect(openUploadCalls, 1);
    },
  );

  testWidgets('without a navigation callback upload still uses UploadCenter', (
    tester,
  ) async {
    final GalleryTestGateway gateway = GalleryTestGateway();
    final UploadCenter center = UploadCenter(gateway: gateway);
    addTearDown(center.dispose);
    await _pumpGallery(
      tester,
      gateway: gateway,
      mediaPicker: _FakeMediaPicker(
        MediaPickerSelected([
          PickedFile(
            path: '/tmp/foto.jpg',
            name: 'foto.jpg',
            mime: 'image/jpeg',
          ),
        ]),
      ),
      uploadCenter: center,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Enviar'));
    await tester.pumpAndSettle();

    expect(center.state, isA<UploadSucceeded>());
    expect(find.text('Galeria'), findsOneWidget);
  });

  testWidgets('the video player abstraction still controls playback', (
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

    await tester.tap(find.bySemanticsLabel('Fechar visualização'));
    await tester.pumpAndSettle();
    expect(players.made.single.disposed, isTrue);
  });

  testWidgets('video download failure offers a retry', (tester) async {
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
}

final class _FakeMediaPicker implements MediaPicker {
  _FakeMediaPicker(this.outcome);

  final MediaPickerOutcome outcome;
  int pickCalls = 0;

  @override
  Future<MediaPickerOutcome> pickPhotos() async {
    pickCalls += 1;
    return outcome;
  }

  @override
  Future<MediaPickerOutcome> recoverLostData() async =>
      const MediaPickerCancelled();

  @override
  Future<MediaPickerOutcome> takePhoto() async => const MediaPickerCancelled();
}
