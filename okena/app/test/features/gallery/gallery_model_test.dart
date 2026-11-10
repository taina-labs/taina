import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/gallery/gallery_model.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fake_gateway.dart';

void main() {
  group('pure helpers', () {
    test('columns step 2, 3 and 4 by width', () {
      expect(GalleryModel.columnsFor(320), 2);
      expect(GalleryModel.columnsFor(499), 2);
      expect(GalleryModel.columnsFor(500), 3);
      expect(GalleryModel.columnsFor(899), 3);
      expect(GalleryModel.columnsFor(900), 4);
    });

    test('labels speak the screen words', () {
      expect(GalleryModel.labelOfTab(GalleryTab.grid), 'Grade');
      expect(GalleryModel.labelOfTab(GalleryTab.timeline), 'Linha do tempo');
      expect(GalleryModel.labelOfFilter(GalleryFilter.all), 'Tudo');
      expect(GalleryModel.labelOfFilter(GalleryFilter.praca), 'Praça');
      expect(GalleryModel.labelOfFilter(GalleryFilter.casa), 'Casa');
      expect(GalleryFilter.praca.zona, Zona.praca);
      expect(GalleryFilter.casa.zona, Zona.casa);
      expect(GalleryFilter.all.zona, isNull);
    });

    test('filtering keeps the zone only', () {
      final FileRecord casa = sampleFile(rkey: 'a', zona: Zona.casa);
      final FileRecord praca = sampleFile(rkey: 'b', zona: Zona.praca);
      expect(GalleryModel.filtering([casa, praca], GalleryFilter.all), [
        casa,
        praca,
      ]);
      expect(GalleryModel.filtering([casa, praca], GalleryFilter.casa), [casa]);
      expect(GalleryModel.filtering([casa, praca], GalleryFilter.praca), [
        praca,
      ]);
    });

    test('filtering days drops the days that stay empty', () {
      final GalleryDay mixed = GalleryDay(
        date: '2026-06-21',
        photos: [
          sampleFile(rkey: 'a', zona: Zona.casa),
          sampleFile(rkey: 'b', zona: Zona.praca),
        ],
      );
      final GalleryDay casaOnly = GalleryDay(
        date: '2026-06-20',
        photos: [sampleFile(rkey: 'c', zona: Zona.casa)],
      );
      final List<GalleryDay> praca = GalleryModel.filteringDays([
        mixed,
        casaOnly,
      ], GalleryFilter.praca);
      expect(praca, hasLength(1));
      expect(praca.single.date, '2026-06-21');
      expect(praca.single.photos.single.rkey, 'b');
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

    test('section title reads Hoje and Ontem from the wire day', () {
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
      final DateTime now = DateTime(2026, 11, 9, 12);
      expect(GalleryModel.sectionTitle(today, now: now), 'Hoje, 1 foto');
      expect(GalleryModel.sectionTitle(yesterday, now: now), 'Ontem, 2 fotos');
      expect(
        GalleryModel.sectionTitle(
          GalleryDay(date: '2026-06-21', photos: const []),
          now: now,
        ),
        '21/06/2026, 0 fotos',
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
      expect(
        GalleryModel.emptyCopy(
          rawEmpty: false,
          filter: GalleryFilter.casa,
        ).title,
        'Nada na sua casa ainda',
      );
      expect(
        GalleryModel.emptyCopy(
          rawEmpty: false,
          filter: GalleryFilter.praca,
        ).title,
        'Nada na praça ainda',
      );
      expect(
        GalleryModel.emptyCopy(
          rawEmpty: true,
          filter: GalleryFilter.casa,
        ).title,
        'Nenhuma foto ainda',
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
      expect(model.filteredPhotos, hasLength(3));
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

    test('the filter narrows without refetching', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();
      final int calls = gateway.screenCalls;

      model.selectFilter(GalleryFilter.praca);
      expect(model.filteredPhotos, hasLength(3));
      model.selectFilter(GalleryFilter.casa);
      expect(model.filteredPhotos, isEmpty);
      expect(model.empty, isTrue);
      expect(model.rawEmpty, isFalse);
      expect(gateway.screenCalls, calls);
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
      expect(model.loadedCount, 1);

      await model.loadMore();
      expect(model.photos, [first, second]);
      expect(model.canLoadMore, isFalse);
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
    test('open, move and close follow the visible list', () async {
      final GalleryTestGateway gateway = GalleryTestGateway();
      final GalleryModel model = GalleryModel(gateway);
      addTearDown(model.dispose);
      await model.ensureLoaded();

      final FileRecord file = model.filteredPhotos[1];
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

      final FileRecord praca = model.filteredPhotos.firstWhere(
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
      final FileRecord file = model.filteredPhotos[1];
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
      final FileRecord file = model.filteredPhotos[1];
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
      final FileRecord video = model.filteredPhotos.firstWhere(
        GalleryModel.isVideo,
      );

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
        final FileRecord video = model.filteredPhotos.firstWhere(
          GalleryModel.isVideo,
        );

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
      final FileRecord video = model.filteredPhotos.firstWhere(
        GalleryModel.isVideo,
      );
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
      final FileRecord video = model.filteredPhotos.firstWhere(
        GalleryModel.isVideo,
      );
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
