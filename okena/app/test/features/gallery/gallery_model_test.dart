import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/gallery/gallery_model.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fake_gateway.dart';

void main() {
  group('pure helpers', () {
    test('columns follow the mobile and wide gallery boards', () {
      expect(GalleryModel.columnsFor(320), 3);
      expect(GalleryModel.columnsFor(599), 3);
      expect(GalleryModel.columnsFor(600), 4);
      expect(GalleryModel.columnsFor(999), 4);
      expect(GalleryModel.columnsFor(1000), 5);
    });

    test('labels speak the gallery destinations', () {
      expect(GalleryModel.labelOfTab(GalleryTab.grid), 'Grade');
      expect(GalleryModel.labelOfTab(GalleryTab.timeline), 'Linha do tempo');
    });

    test('fusing joins a day split across pages', () {
      final GalleryDay first = GalleryDay(
        date: '2026-06-21',
        photos: [sampleFile(rkey: 'a')],
      );
      final List<GalleryDay> fused = GalleryModel.fusing(
        [first],
        [
          TimelineGroup(
            date: '2026-06-21',
            photos: [sampleFile(rkey: 'b')],
          ),
          TimelineGroup(
            date: '2026-06-20',
            photos: [sampleFile(rkey: 'c')],
          ),
        ],
      );
      expect(fused, hasLength(2));
      expect(fused.first.photos.map((FileRecord f) => f.rkey), ['a', 'b']);
      expect(fused.last.date, '2026-06-20');
    });

    test('section title preserves the day and month from the wire date', () {
      final GalleryDay today = GalleryDay(
        date: '2026-11-09',
        photos: [sampleFile(rkey: 'a')],
      );
      final GalleryDay yesterday = GalleryDay(
        date: '2026-11-08',
        photos: [
          sampleFile(rkey: 'b'),
          sampleFile(rkey: 'c'),
        ],
      );
      expect(GalleryModel.sectionTitle(today), '9 de novembro');
      expect(GalleryModel.sectionTitle(yesterday), '8 de novembro');
      expect(
        GalleryModel.sectionTitle(
          GalleryDay(date: '2026-06-21', photos: const []),
        ),
        '21 de junho',
      );
    });

    test('a day that cannot be parsed comes back as sent', () {
      expect(GalleryModel.dayTitle('nao-e-dia'), 'nao-e-dia');
      expect(GalleryModel.uploadedDay('nao-e-data'), 'nao-e-data');
    });

    test('uploaded day is the file clock, day only', () {
      expect(
        GalleryModel.uploadedDay('2026-06-21T21:12:00Z'),
        matches(RegExp(r'^\d{2}/\d{2}/2026$')),
      );
    });

    test('human type adds the subtype when it says something', () {
      expect(GalleryModel.humanType('video/mp4'), 'Vídeo MP4');
      expect(GalleryModel.humanType('image/jpeg'), 'Imagem JPEG');
      expect(GalleryModel.humanType('application/pdf'), 'PDF');
      expect(GalleryModel.humanType('application/zip'), 'ZIP');
      expect(GalleryModel.humanType('text/plain'), 'Texto PLAIN');
    });

    test('zone sentence and empty copy speak the product promise', () {
      expect(GalleryModel.zoneSentence(Zona.praca), 'Todos os moradores veem.');
      expect(
        GalleryModel.zoneSentence(Zona.casa),
        'Só você, e quem você deixar, vê.',
      );
      expect(GalleryModel.noPhotos.title, 'Ainda não há fotos');
    });

    test('count line handles the BE-6 video count and its fallback', () {
      const StorageStats withVideos = StorageStats(
        usedBytes: 0,
        quotaBytes: null,
        byKind: StorageByKind(photos: 0, videos: 0, documents: 0, others: 0),
        files: 0,
        photos: 38,
        videos: 4,
        trash: StorageTrash(count: 0, bytes: 0),
      );
      const StorageStats withoutVideos = StorageStats(
        usedBytes: 0,
        quotaBytes: null,
        byKind: StorageByKind(photos: 0, videos: 0, documents: 0, others: 0),
        files: 0,
        photos: 38,
        trash: StorageTrash(count: 0, bytes: 0),
      );
      expect(
        GalleryModel.countLabelFor(withVideos, fallbackCount: 2),
        '38 fotos, 4 vídeos',
      );
      expect(
        GalleryModel.countLabelFor(withoutVideos, fallbackCount: 2),
        '38 fotos e vídeos',
      );
      expect(
        GalleryModel.countLabelFor(null, fallbackCount: 2),
        '2 fotos e vídeos',
      );
    });

    test('viewer caption includes the file date and zone', () {
      expect(
        GalleryModel.viewerCaption(
          sampleFile(
            rkey: 'a',
            name: 'Foto.jpg',
            zona: Zona.praca,
            createdAt: '2026-06-21T12:00:00Z',
          ),
        ),
        'Foto.jpg, 21 de junho, na praça',
      );
    });
    test('viewer position is 1-based and 1 when absent', () {
      final FileRecord a = sampleFile(rkey: 'a');
      final FileRecord b = sampleFile(rkey: 'b');
      expect(GalleryModel.positionOf(b, [a, b]), 2);
      expect(GalleryModel.positionOf(sampleFile(rkey: 'z'), [a, b]), 1);
    });
  });

  group('loading', () {
    test('ensureLoaded fills the grid once', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);

      await model.ensureLoaded();

      expect(model.loaded, isTrue);
      expect(model.loading, isFalse);
      expect(model.photos, hasLength(3));
      expect(model.photos, hasLength(3));
      expect(model.nextCursor, isNull);
      expect(model.canLoadMore, isFalse);
      expect(model.error, isNull);
    });

    test('a failure is a value, and a retry recovers', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);

      gateway.failNextScreen = true;
      await model.ensureLoaded();
      expect(model.error, isA<NetworkError>());
      expect(model.photos, isEmpty);
      expect(model.loaded, isTrue);

      await model.refresh();
      expect(model.error, isNull);
      expect(model.photos, hasLength(3));
    });

    test(
      'entering the timeline marks the left tab stale and loads it',
      () async {
        final GalleryTestGateway gateway = GalleryTestGateway();
        final GalleryModel model = GalleryModel(gateway);
        addTearDown(model.dispose);
        await model.ensureLoaded();
        final int gridCalls = gateway.screenCalls;

        model.selectTab(GalleryTab.timeline);
        await model.ensureLoaded();
        expect(gateway.screenCalls, greaterThan(gridCalls));
        expect(model.days, hasLength(1));
        expect(model.timelineDays.single.photos, hasLength(3));

        model.selectTab(GalleryTab.grid);
        await model.ensureLoaded();
        expect(gateway.screenCalls, greaterThan(gridCalls + 1));
      },
    );

    test('a response after dispose does not notify', () async {
      final GalleryTestGateway gateway = GalleryTestGateway(
        delay: const Duration(milliseconds: 10),
      );
      final GalleryModel model = GalleryModel(gateway);
      final Future<void> pending = model.ensureLoaded();
      model.dispose();
      await pending;
      expect(model.loaded, isFalse);
    });
  });

  group('pagination', () {
    test('loadMore appends and advances the cursor', () async {
      final FileRecord first = sampleFile(rkey: 'a');
      final FileRecord second = sampleFile(rkey: 'b');
      final _PagingApi api = _PagingApi(
        photoPages: [
          Page(items: [first], nextCursor: '1'),
          Page(items: [second], nextCursor: null),
        ],
      );
      final GalleryTestGateway gateway = GalleryTestGateway(api: api);
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);

      await model.ensureLoaded();
      expect(model.photos, [first]);
      expect(model.canLoadMore, isTrue);
      expect(model.loadedPageCount, 1);

      await model.loadMore();
      expect(model.photos, [first, second]);
      expect(model.canLoadMore, isFalse);
      expect(model.loadedPageCount, 2);
    });

    test('a page failure keeps the cursor and the list, and says so', () async {
      final FileRecord first = sampleFile(rkey: 'a');
      final FileRecord second = sampleFile(rkey: 'b');
      final _PagingApi api = _PagingApi(
        photoPages: [
          Page(items: [first], nextCursor: '1'),
          Page(items: [second], nextCursor: null),
        ],
      );
      final GalleryTestGateway gateway = GalleryTestGateway(api: api);
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();

      api.failNextPhotos = true;
      await model.loadMore();
      expect(model.photos, [first]);
      expect(model.nextCursor, '1');
      expect(model.alertMessage, GalleryModel.loadMoreMessage);
      expect(model.loadingMore, isFalse);
      expect(model.loadedPageCount, 1);

      model.dismissAlert();
      await model.loadMore();
      expect(model.photos, [first, second]);
      expect(model.nextCursor, isNull);
    });

    test('timeline pages fuse a day split across the boundary', () async {
      final FileRecord a = sampleFile(rkey: 'a');
      final FileRecord b = sampleFile(rkey: 'b');
      final _PagingApi api = _PagingApi(
        timelinePages: [
          Page(
            items: [
              TimelineGroup(date: '2026-06-21', photos: [a]),
            ],
            nextCursor: '1',
          ),
          Page(
            items: [
              TimelineGroup(date: '2026-06-21', photos: [b]),
            ],
            nextCursor: null,
          ),
        ],
      );
      final GalleryTestGateway gateway = GalleryTestGateway(api: api);
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);

      model.selectTab(GalleryTab.timeline);
      await model.ensureLoaded();
      expect(model.days, hasLength(1));

      await model.loadMore();
      expect(model.days, hasLength(1));
      expect(model.days.single.photos, hasLength(2));
      expect(model.timelineCursor, isNull);
    });
  });

  group('viewer', () {
    test(
      'openRkey walks the selected grid pages and preserves their order',
      () async {
        final FileRecord first = sampleFile(rkey: 'first');
        final FileRecord target = sampleFile(rkey: 'target');
        final FileRecord after = sampleFile(rkey: 'after');
        final _PagingApi api = _PagingApi(
          photoPages: [
            Page(items: [first], nextCursor: '1'),
            Page(items: [target], nextCursor: '2'),
            Page(items: [after], nextCursor: null),
          ],
        );
        final GalleryModel model = GalleryModel(GalleryTestGateway(api: api));
        addTearDown(model.dispose);

        final bool opened = await model.openRkey(target.rkey);

        expect(opened, isTrue);
        expect(model.tab, GalleryTab.grid);
        expect(model.viewer?.file, target);
        expect(model.viewer?.files, [first, target]);
        expect(model.viewer?.index, 1);
        expect(model.canLoadMore, isTrue);
      },
    );

    test('openRkey pages the timeline without switching its tab', () async {
      final FileRecord first = sampleFile(rkey: 'first');
      final FileRecord target = sampleFile(rkey: 'target');
      final _PagingApi api = _PagingApi(
        timelinePages: [
          Page(
            items: [
              TimelineGroup(date: '2026-06-22', photos: [first]),
            ],
            nextCursor: '1',
          ),
          Page(
            items: [
              TimelineGroup(date: '2026-06-21', photos: [target]),
            ],
            nextCursor: null,
          ),
        ],
      );
      final GalleryModel model = GalleryModel(
        GalleryTestGateway(api: api),
        initialTab: GalleryTab.timeline,
      );
      addTearDown(model.dispose);

      final bool opened = await model.openRkey(target.rkey);

      expect(opened, isTrue);
      expect(model.tab, GalleryTab.timeline);
      expect(model.viewer?.files, [first, target]);
      expect(model.viewer?.file, target);
      expect(model.viewer?.index, 1);
      expect(model.canLoadMore, isFalse);
    });

    test(
      'openRkey returns false when the item is absent or a page fails',
      () async {
        final _PagingApi absentApi = _PagingApi(
          photoPages: [
            Page(items: [sampleFile(rkey: 'first')], nextCursor: null),
          ],
        );
        final GalleryModel absentModel = GalleryModel(
          GalleryTestGateway(api: absentApi),
        );
        addTearDown(absentModel.dispose);
        expect(await absentModel.openRkey('missing'), isFalse);
        expect(absentModel.viewer, isNull);

        final _PagingApi failingApi = _PagingApi(
          photoPages: [
            Page(
              items: [sampleFile(rkey: 'first')],
              nextCursor: '1',
            ),
            Page(items: [sampleFile(rkey: 'target')], nextCursor: null),
          ],
        );
        final GalleryModel failingModel = GalleryModel(
          GalleryTestGateway(api: failingApi),
        );
        addTearDown(failingModel.dispose);
        await failingModel.ensureLoaded();
        failingApi.failNextPhotos = true;
        expect(await failingModel.openRkey('target'), isFalse);
        expect(failingModel.viewer, isNull);
        expect(failingModel.alertMessage, GalleryModel.loadMoreMessage);
        expect(failingModel.nextCursor, '1');
      },
    );

    test('open, move and close follow the visible list', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();

      final FileRecord file = model.photos[1];
      model.open(file);
      expect(model.viewer, isNotNull);
      expect(model.viewer!.files, hasLength(3));
      expect(model.viewer!.file, file);

      model.moveViewer(2);
      expect(model.viewer!.index, 2);
      expect(
        GalleryModel.positionOf(model.viewer!.file!, model.viewer!.files),
        3,
      );

      model.moveViewer(99);
      expect(model.viewer!.index, 2);

      model.close();
      expect(model.viewer, isNull);
    });

    test('changeZone flips the zone and closes the viewer', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();

      final FileRecord praca = model.photos.firstWhere(
        (FileRecord file) => file.zona == Zona.praca,
      );
      model.open(praca);
      await model.changeZone(praca);

      expect(model.viewer, isNull);
      expect(model.working, isFalse);
      final FileRecord updated = model.photos.firstWhere(
        (FileRecord file) => file.rkey == praca.rkey,
      );
      expect(updated.zona, Zona.casa);
    });

    test('delete removes the file from the grid and the viewer', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();
      final FileRecord file = model.photos[1];
      model.open(file);
      final int before = model.photos.length;

      await model.delete(file);

      expect(model.photos, hasLength(before - 1));
      expect(
        model.photos.where((FileRecord item) => item.rkey == file.rkey),
        isEmpty,
      );
      expect(model.viewer, isNull);
    });

    test('an act failure becomes the alert and keeps the viewer', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();
      final FileRecord file = model.photos[1];
      model.open(file);

      gateway.failNextScreen = true;
      await model.delete(file);

      expect(model.viewer, isNotNull);
      expect(model.alertMessage, const NetworkError().message);
      expect(model.photos, hasLength(3));
    });

    test('the confirm copy offers the opposite zone', () {
      expect(GalleryModel.zonaActionLabel(Zona.casa), 'Publicar na praça');
      expect(GalleryModel.zonaActionLabel(Zona.praca), 'Tirar da praça');
      expect(
        GalleryModel.zonaConfirmTitle('Foto.jpg', Zona.casa),
        'Publicar "Foto.jpg" na praça?',
      );
      expect(GalleryModel.zonaConfirmPrimary(Zona.praca), 'Tirar da praça');
      expect(GalleryModel.deleteFileTitle('Foto.jpg'), 'Excluir "Foto.jpg"?');
    });
  });

  group('video', () {
    test('play downloads the video and reaches ready', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();
      final FileRecord video = model.photos.firstWhere(GalleryModel.isVideo);

      final Future<void> playing = model.play(video);
      expect(model.video, isA<GalleryVideoLoading>());
      await playing;
      expect(model.video, isA<GalleryVideoReady>());
      expect((model.video as GalleryVideoReady).file, video);
      expect((model.video as GalleryVideoReady).path, isNotEmpty);
      expect(model.working, isFalse);
    });

    test(
      'a download failure reaches failed and retry reuses the path',
      () async {
        final GalleryTestGateway gateway = GalleryTestGateway();
        final GalleryModel model = GalleryModel(gateway);
        addTearDown(model.dispose);
        await model.ensureLoaded();
        final FileRecord video = model.photos.firstWhere(GalleryModel.isVideo);

        gateway.failNextScreen = true;
        await model.play(video);
        expect(model.video, isA<GalleryVideoFailed>());
        expect((model.video as GalleryVideoFailed).error, isA<NetworkError>());

        await model.retryVideo(video);
        expect(model.video, isA<GalleryVideoReady>());
      },
    );

    test('moving the viewer stops the video page', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();
      final FileRecord video = model.photos.firstWhere(GalleryModel.isVideo);
      model.open(video);
      await model.play(video);
      expect(model.video, isA<GalleryVideoReady>());

      model.moveViewer(1);
      expect(model.video, isA<GalleryVideoIdle>());
      model.close();
      expect(model.video, isA<GalleryVideoIdle>());
    });

    test('a stale download does not overwrite a stopped page', () async {
      final GalleryTestGateway gateway = GalleryTestGateway(
        delay: const Duration(milliseconds: 10),
      );
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();
      final FileRecord video = model.photos.firstWhere(GalleryModel.isVideo);
      model.open(video);

      final Future<void> playing = model.play(video);
      model.stopVideo();
      await playing;
      expect(model.video, isA<GalleryVideoIdle>());
    });
  });
}

/// The paginated API: the model decides how many pages it wants and this
/// answers them in order, so the cursor flows without a real box.
final class _PagingApi implements TainaApi {
  _PagingApi({this.photoPages = const [], this.timelinePages = const []});

  final List<Page<FileRecord>> photoPages;
  final List<Page<TimelineGroup>> timelinePages;
  int photoCalls = 0;
  int timelineCalls = 0;
  bool failNextPhotos = false;
  bool failNextTimeline = false;

  @override
  Future<TainaResult<Page<FileRecord>>> photos({
    int? limit,
    String? cursor,
  }) async {
    if (failNextPhotos) {
      failNextPhotos = false;
      return const Err(NetworkError());
    }
    if (photoCalls >= photoPages.length) {
      return Ok(Page(items: const [], nextCursor: null));
    }
    return Ok(photoPages[photoCalls++]);
  }

  @override
  Future<TainaResult<Page<TimelineGroup>>> photoTimeline({
    int? limit,
    String? cursor,
  }) async {
    if (failNextTimeline) {
      failNextTimeline = false;
      return const Err(NetworkError());
    }
    if (timelineCalls >= timelinePages.length) {
      return Ok(Page(items: const [], nextCursor: null));
    }
    return Ok(timelinePages[timelineCalls++]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('${invocation.memberName} is not used here');
  }
}
