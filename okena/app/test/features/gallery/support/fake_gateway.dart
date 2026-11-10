import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/widgets.dart' show ColoredBox, SizedBox, Widget;
import 'package:okena_app/src/features/gallery/gallery_video.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// A [SessionGateway] over [FastGalleryApi] with switches a test can flip:
/// the next screened call fails, or every call whose result type is in
/// [failTypes] fails.
final class GalleryTestGateway implements SessionGateway {
  @override
  Me? get identity => null;

  GalleryTestGateway({TainaApi? api, Duration delay = Duration.zero}) {
    this.api = api ?? FastGalleryApi(delay: delay);
    thumbnails = ThumbnailStore(api: this.api);
  }

  @override
  late final TainaApi api;

  @override
  late final ThumbnailStore thumbnails;

  bool failNextScreen = false;
  final Set<Type> failTypes = {};

  int screenCalls = 0;
  final Map<Type, int> callsByType = {};

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async {
    screenCalls += 1;
    callsByType[T] = (callsByType[T] ?? 0) + 1;
    if (failNextScreen) {
      failNextScreen = false;
      return Err<T>(const NetworkError());
    }
    if (failTypes.contains(T)) {
      return Err<T>(const NetworkError());
    }
    return outcome;
  }
}

/// The [FakeTainaApi] world with a download that answers a path at once: the
/// real fake writes a file, and disk IO does not complete inside the fake
/// async of a widget test.
final class FastGalleryApi implements TainaApi {
  FastGalleryApi({Duration delay = Duration.zero})
    : _inner = FakeTainaApi(delay: delay);

  final FakeTainaApi _inner;
  int thumbnailCalls = 0;

  @override
  Future<TainaResult<Page<FileRecord>>> photos({int? limit, String? cursor}) {
    return _inner.photos(limit: limit, cursor: cursor);
  }

  @override
  Future<TainaResult<Page<TimelineGroup>>> photoTimeline({
    int? limit,
    String? cursor,
  }) {
    return _inner.photoTimeline(limit: limit, cursor: cursor);
  }

  @override
  Future<TainaResult<Uint8List>> thumbnail({
    required String rkey,
    required ThumbnailSize size,
  }) {
    thumbnailCalls += 1;
    return _inner.thumbnail(rkey: rkey, size: size);
  }

  @override
  Future<TainaResult<String>> download({required String rkey}) async {
    return Ok<String>('/tmp/okena-test-$rkey');
  }

  @override
  Future<TainaResult<FileRecord>> updateFile({
    required String rkey,
    String? name,
    Zona? zona,
  }) {
    return _inner.updateFile(rkey: rkey, name: name, zona: zona);
  }

  @override
  Future<TainaResult<void>> deleteFile({required String rkey}) {
    return _inner.deleteFile(rkey: rkey);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('${invocation.memberName} is not used here');
  }
}

/// A test player that records the lifecycle without touching the plugin.
final class FakeVideoPlayer implements GalleryVideoPlayer {
  FakeVideoPlayer({this.failInitialize = false});

  final bool failInitialize;

  bool initialized = false;
  bool playing = false;
  bool paused = false;
  bool disposed = false;
  int playCalls = 0;
  String? path;

  @override
  Future<void> initialize(String path) async {
    if (failInitialize) throw StateError('no decoder');
    this.path = path;
    initialized = true;
  }

  @override
  Future<void> play() async {
    playing = true;
    paused = false;
    playCalls += 1;
  }

  @override
  Future<void> pause() async {
    playing = false;
    paused = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    playing = false;
  }

  @override
  bool get isInitialized => initialized && !disposed;

  @override
  bool get isPlaying => playing;

  @override
  double get aspectRatio => 16 / 9;

  @override
  Widget build() => ColoredBox(color: const Color(0xFF000000));

  @override
  Widget buildProgress() => const SizedBox.shrink();
}

/// A file record with just enough shape for the gallery tests.
FileRecord sampleFile({
  required String rkey,
  String name = 'Foto.jpg',
  String mime = 'image/jpeg',
  Zona zona = Zona.casa,
  String createdAt = '2026-06-21T21:12:00Z',
  int size = 1024,
}) {
  return FileRecord(
    rkey: rkey,
    cid: 'cid-$rkey',
    blobCid: 'blob-$rkey',
    sha256: 'sha-$rkey',
    name: name,
    mime: mime,
    size: size,
    zona: zona,
    folder: null,
    takenAt: null,
    width: null,
    height: null,
    rendition: mime.startsWith('image/') ? Rendition.ready : Rendition.none,
    deletedAt: null,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

/// A player factory that keeps the last player it made for assertions.
final class FakeVideoPlayerFactory {
  FakeVideoPlayerFactory({this.failInitialize = false});

  final bool failInitialize;
  final List<FakeVideoPlayer> made = [];

  GalleryVideoPlayer call() {
    final FakeVideoPlayer player = FakeVideoPlayer(
      failInitialize: failInitialize,
    );
    made.add(player);
    return player;
  }
}
