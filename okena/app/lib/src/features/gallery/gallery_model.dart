import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The gallery screen's state: the grid and the timeline, each with its own
/// cursor, and the fullscreen viewer over whichever list is showing.
///
/// The loading logic lives here once; the decisions are the pure helpers
/// below; the widgets only assign and call. The model talks to [SessionGateway]
/// and never to the concrete session class.
final class GalleryModel extends ChangeNotifier {
  GalleryModel(this._gateway, {GalleryTab initialTab = GalleryTab.grid})
    : _tab = initialTab;

  final SessionGateway _gateway;

  GalleryTab _tab;
  List<FileRecord> _photos = const [];
  List<GalleryDay> _days = const [];
  StorageStats? _storage;
  String? _nextCursor;
  String? _timelineCursor;
  bool _loading = false;
  bool _loadingCount = false;
  bool _countLoaded = false;
  bool _loadingMore = false;
  bool _loaded = false;
  bool _working = false;
  TainaError? _error;
  String? _alertMessage;
  GalleryViewerState? _viewer;
  GalleryVideoState _video = const GalleryVideoIdle();

  bool _gridStale = true;
  bool _timelineStale = true;
  bool _disposed = false;
  int _gridGeneration = 0;
  int _timelineGeneration = 0;
  int _videoGeneration = 0;
  int _reloadToken = 0;
  int _loadedPageCount = 0;

  GalleryTab get tab => _tab;
  List<FileRecord> get photos => _photos;
  List<GalleryDay> get days => _days;
  StorageStats? get storage => _storage;
  String? get nextCursor => _nextCursor;
  String? get timelineCursor => _timelineCursor;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get loaded => _loaded;
  bool get working => _working;
  TainaError? get error => _error;
  String? get alertMessage => _alertMessage;
  GalleryViewerState? get viewer => _viewer;
  GalleryVideoState get video => _video;

  /// Another page may come for the tab that is showing.
  bool get canLoadMore => switch (_tab) {
    GalleryTab.grid => _nextCursor != null,
    GalleryTab.timeline => _timelineCursor != null,
  };

  /// The footer's re-arm key. It advances for every successful page, including
  /// pages that add no media.
  int get loadedPageCount => _loadedPageCount;

  /// The timeline's non-empty days, retaining the underlying groups for
  /// pagination when a page boundary splits a date.
  List<GalleryDay> get timelineDays => [
    for (final GalleryDay day in _days)
      if (day.photos.isNotEmpty) day,
  ];

  /// The count line prefers community-wide totals and falls back to the
  /// loaded media count when the storage endpoint is unavailable.
  String get countLabel => countLabelFor(
    _storage,
    fallbackCount: _photos.length > GalleryModel.photosOf(_days).length
        ? _photos.length
        : GalleryModel.photosOf(_days).length,
  );

  /// The list the viewer swipes through, in the order it is showing.
  List<FileRecord> get visiblePhotos => switch (_tab) {
    GalleryTab.grid => _photos,
    GalleryTab.timeline => photosOf(_days),
  };

  /// Whether the selected view has no media.
  bool get rawEmpty => switch (_tab) {
    GalleryTab.grid => _photos.isEmpty,
    GalleryTab.timeline => GalleryModel.photosOf(_days).isEmpty,
  };

  /// Whether the selected view has nothing to show.
  bool get empty => switch (_tab) {
    GalleryTab.grid => _photos.isEmpty,
    GalleryTab.timeline => GalleryModel.photosOf(_days).isEmpty,
  };

  /// An empty view is definitive only after its cursor is exhausted.
  bool get showEmpty => empty && !canLoadMore;

  // MARK: transitions

  /// Entering a tab marks the one left stale, like the web: whichever list
  /// you leave refetches on the way back.
  void selectTab(GalleryTab tab) {
    if (tab == _tab) return;
    switch (tab) {
      case GalleryTab.grid:
        _timelineStale = true;
        break;
      case GalleryTab.timeline:
        _gridStale = true;
        break;
    }
    _tab = tab;
    _video = const GalleryVideoIdle();
    _videoGeneration += 1;
    _notify();
  }

  /// Loads the tab that is showing, once. The stale flag flips before the
  /// first await, so a second caller in the same pass waits for nothing.
  Future<void> ensureLoaded() async {
    if (_disposed) return;
    final bool stale = switch (_tab) {
      GalleryTab.grid => _gridStale,
      GalleryTab.timeline => _timelineStale,
    };
    if (!stale) return;
    await _reload();
  }

  /// Loads the community totals separately so the count request never holds
  /// the gallery content behind it.
  Future<void> ensureCountLoaded() async {
    if (_disposed || _loadingCount || _countLoaded) return;
    _loadingCount = true;
    final TainaResult<StorageStats> result = await _gateway.api.storage();
    final TainaResult<StorageStats> screened = await _gateway.screen(result);
    if (_disposed) return;
    if (screened case Ok<StorageStats>(:final value)) _storage = value;
    _loadingCount = false;
    _countLoaded = true;
    _notify();
  }

  Future<void> refresh() async {
    if (_loading || _disposed) return;
    _countLoaded = false;
    await Future.wait([_reload(), ensureCountLoaded()]);
  }

  Future<void> loadMore() async {
    if (_loadingMore || _disposed) return;
    switch (_tab) {
      case GalleryTab.grid:
        final String? cursor = _nextCursor;
        if (cursor == null) return;
        _loadingMore = true;
        _notify();
        final int generation = _gridGeneration;
        final TainaResult<Page<FileRecord>> result = await _gateway.api.photos(
          limit: null,
          cursor: cursor,
        );
        final TainaResult<Page<FileRecord>> screened = await _gateway.screen(
          result,
        );
        if (_disposed) return;
        if (generation == _gridGeneration) {
          switch (screened) {
            case Ok(:final value):
              _photos = [..._photos, ...value.items];
              _nextCursor = value.nextCursor;
              _loadedPageCount += 1;
            case Err():
              _alertMessage = loadMoreMessage;
          }
        }
        _loadingMore = false;
        _notify();
        break;
      case GalleryTab.timeline:
        final String? cursor = _timelineCursor;
        if (cursor == null) return;
        _loadingMore = true;
        _notify();
        final int generation = _timelineGeneration;
        final TainaResult<Page<TimelineGroup>> result = await _gateway.api
            .photoTimeline(limit: null, cursor: cursor);
        final TainaResult<Page<TimelineGroup>> screened = await _gateway.screen(
          result,
        );
        if (_disposed) return;
        if (generation == _timelineGeneration) {
          switch (screened) {
            case Ok(:final value):
              _days = fusing(_days, value.items);
              _timelineCursor = value.nextCursor;
              _loadedPageCount += 1;
            case Err():
              _alertMessage = loadMoreMessage;
          }
        }
        _loadingMore = false;
        _notify();
        break;
    }
  }

  /// Opens the viewer over the list that is showing, at the photo tapped.
  void open(FileRecord file) {
    final List<FileRecord> files = visiblePhotos;
    final int index = files.indexWhere(
      (FileRecord item) => item.rkey == file.rkey,
    );
    _viewer = GalleryViewerState(files: files, index: index < 0 ? 0 : index);
    _video = const GalleryVideoIdle();
    _videoGeneration += 1;
    _notify();
  }

  void close() {
    _viewer = null;
    _video = const GalleryVideoIdle();
    _videoGeneration += 1;
    _notify();
  }

  /// The swipe landed on another photo; a video that was playing elsewhere
  /// stops, the page that arrives owns its own playback.
  void moveViewer(int index) {
    final GalleryViewerState? current = _viewer;
    if (current == null) return;
    if (index < 0 || index >= current.files.length || index == current.index) {
      return;
    }
    _viewer = GalleryViewerState(files: current.files, index: index);
    _video = const GalleryVideoIdle();
    _videoGeneration += 1;
    _notify();
  }

  void dismissAlert() {
    _alertMessage = null;
    _notify();
  }

  /// A failure the screen itself noticed (a share sheet that would not open,
  /// for instance), said with the same alert the API failures use.
  void reportAlert(String message) {
    _alertMessage = message;
    _notify();
  }

  // MARK: the viewer's acts

  /// Publishes to the praça, or takes back: the opposite of where the file is
  /// now. The viewer closes on success.
  Future<void> changeZone(FileRecord file) async {
    if (_working || _disposed) return;
    final Zona target = file.zona == Zona.casa ? Zona.praca : Zona.casa;
    _working = true;
    _notify();
    final TainaResult<FileRecord> result = await _gateway.api.updateFile(
      rkey: file.rkey,
      name: null,
      zona: target,
    );
    final TainaResult<FileRecord> screened = await _gateway.screen(result);
    if (_disposed) return;
    switch (screened) {
      case Ok(:final value):
        _replace(value);
        _viewer = null;
        _video = const GalleryVideoIdle();
        _videoGeneration += 1;
      case Err(:final error):
        _alertMessage = failureMessage(error);
    }
    _working = false;
    _notify();
  }

  /// To the trash: the file leaves both lists, and the viewer with them.
  Future<void> delete(FileRecord file) async {
    if (_working || _disposed) return;
    _working = true;
    _notify();
    final TainaResult<void> result = await _gateway.api.deleteFile(
      rkey: file.rkey,
    );
    final TainaResult<void> screened = await _gateway.screen(result);
    if (_disposed) return;
    switch (screened) {
      case Ok():
        _removePhoto(file.rkey);
        _viewer = null;
        _video = const GalleryVideoIdle();
        _videoGeneration += 1;
      case Err(:final error):
        _alertMessage = failureMessage(error);
    }
    _working = false;
    _notify();
  }

  /// The download behind the viewer's share: the local file the share sheet
  /// hands to the system. A failure becomes the alert; the sheet on success
  /// belongs to the app integration.
  Future<TainaResult<String>> download(FileRecord file) async {
    if (_disposed) {
      return const Err(
        ApiError(
          code: 'cancelled',
          status: 0,
          serverMessage: 'A tela foi fechada.',
        ),
      );
    }
    _working = true;
    _notify();
    final TainaResult<String> result = await _gateway.api.download(
      rkey: file.rkey,
    );
    final TainaResult<String> screened = await _gateway.screen(result);
    if (_disposed) return screened;
    if (screened case Err(:final error)) {
      _alertMessage = failureMessage(error);
    }
    _working = false;
    _notify();
    return screened;
  }

  /// The video file for the viewer's playback. The page owns its own loading
  /// state, so the action row does not spin with it.
  Future<void> play(FileRecord file) async {
    if (_disposed) return;
    _videoGeneration += 1;
    final int generation = _videoGeneration;
    _video = GalleryVideoLoading(file);
    _notify();
    final TainaResult<String> result = await _gateway.api.download(
      rkey: file.rkey,
    );
    final TainaResult<String> screened = await _gateway.screen(result);
    if (_disposed || generation != _videoGeneration) return;
    switch (screened) {
      case Ok(:final value):
        _video = GalleryVideoReady(file: file, path: value);
      case Err(:final error):
        _video = GalleryVideoFailed(file: file, error: error);
    }
    _notify();
  }

  Future<void> retryVideo(FileRecord file) => play(file);

  void stopVideo() {
    if (_video is GalleryVideoIdle) return;
    _videoGeneration += 1;
    _video = const GalleryVideoIdle();
    _notify();
  }

  // MARK: pure helpers

  static bool isVideo(FileRecord file) => file.mime.startsWith('video/');

  /// The label of a gallery destination.
  static String labelOfTab(GalleryTab tab) => switch (tab) {
    GalleryTab.grid => 'Grade',
    GalleryTab.timeline => 'Linha do tempo',
  };

  /// The timeline as days: the raw page groups, fused where a day straddles a
  /// page boundary. A fresh page against empty days lays the first ones out.
  static List<GalleryDay> fusing(
    List<GalleryDay> days,
    List<TimelineGroup> groups,
  ) {
    final List<GalleryDay> next = [...days];
    for (final TimelineGroup group in groups) {
      if (next.isNotEmpty && next.last.date == group.date) {
        next[next.length - 1] = GalleryDay(
          date: next.last.date,
          photos: [...next.last.photos, ...group.photos],
        );
      } else {
        next.add(GalleryDay(date: group.date, photos: group.photos));
      }
    }
    return next;
  }

  /// Every photo of the timeline in day order: the list the viewer swipes
  /// through.
  static List<FileRecord> photosOf(List<GalleryDay> days) => [
    for (final GalleryDay day in days) ...day.photos,
  ];

  /// Where the photo sits in the list, 1-based, 1 when absent.
  static int positionOf(FileRecord file, List<FileRecord> files) {
    final int index = files.indexWhere(
      (FileRecord item) => item.rkey == file.rkey,
    );
    return (index < 0 ? 0 : index) + 1;
  }

  static List<FileRecord> replacing(FileRecord file, List<FileRecord> files) {
    final int index = files.indexWhere(
      (FileRecord item) => item.rkey == file.rkey,
    );
    if (index < 0) return files;
    final List<FileRecord> next = [...files];
    next[index] = file;
    return next;
  }

  /// Puts the updated file back inside its day. The day stays even when its
  /// last photo is gone: a later page for the same date fuses onto it.
  static List<GalleryDay> replacingInDays(
    FileRecord file,
    List<GalleryDay> days,
  ) {
    final bool present = days.any(
      (GalleryDay day) =>
          day.photos.any((FileRecord item) => item.rkey == file.rkey),
    );
    if (!present) return days;
    return [
      for (final GalleryDay day in days)
        GalleryDay(date: day.date, photos: replacing(file, day.photos)),
    ];
  }

  static List<FileRecord> removing(String rkey, List<FileRecord> files) => [
    for (final FileRecord file in files)
      if (file.rkey != rkey) file,
  ];

  /// The file out of its day, the day itself kept.
  static List<GalleryDay> removingFromDays(String rkey, List<GalleryDay> days) {
    return [
      for (final GalleryDay day in days)
        GalleryDay(date: day.date, photos: removing(rkey, day.photos)),
    ];
  }

  /// The type for a person: the kind plus the subtype when it adds anything
  /// ("Vídeo MP4", "PDF").
  static String humanType(String mime) {
    final String kind;
    if (mime.startsWith('image/')) {
      kind = 'Imagem';
    } else if (mime.startsWith('video/')) {
      kind = 'Vídeo';
    } else if (mime.startsWith('audio/')) {
      kind = 'Áudio';
    } else if (mime == 'application/pdf') {
      kind = 'PDF';
    } else if (mime == 'application/zip') {
      kind = 'ZIP';
    } else if (mime.startsWith('text/')) {
      kind = 'Texto';
    } else {
      kind = 'Arquivo';
    }
    final String subtype = mime.split('/').last.toUpperCase();
    return subtype.isEmpty || kind == subtype ? kind : '$kind $subtype';
  }

  /// The zone in the details, in plain words.
  static String zoneSentence(Zona zona) => zona == Zona.praca
      ? 'Todos os moradores veem.'
      : 'Só você, e quem você deixar, vê.';

  static const GalleryEmptyCopy noPhotos = GalleryEmptyCopy(
    title: 'Ainda não há fotos',
    message: 'Quando alguém enviar uma foto, ela aparece aqui para toda a comunidade.',
  );

  /// Grid density follows the three-column mobile board.
  static int columnsFor(double width) {
    if (width < 600) return 3;
    if (width < 1000) return 4;
    return 5;
  }

  /// The date heading shown above a timeline group.
  static String sectionTitle(GalleryDay day) {
    final DateTime? parsed = _parseDay(day.date);
    if (parsed == null) return day.date;
    return '${parsed.day} de ${_monthName(parsed.month)}';
  }

  /// "Hoje" / "Ontem" / "21/06/2026". The wire date is day only, read as UTC:
  /// the day is the one the box named, not the viewer's zone.
  static String dayTitle(String date, {DateTime? now}) {
    final DateTime? day = _parseDay(date);
    if (day == null) return date;
    final DateTime reference = now ?? DateTime.now();
    final DateTime today = DateTime.utc(
      reference.year,
      reference.month,
      reference.day,
    );
    final int elapsed = today
        .difference(DateTime.utc(day.year, day.month, day.day))
        .inDays;
    return switch (elapsed) {
      0 => 'Hoje',
      1 => 'Ontem',
      _ => _numericDay(day),
    };
  }

  /// The upload day for the viewer header: the file's own clock, day only.
  static String uploadedDay(String iso) {
    final DateTime? parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final DateTime local = parsed.toLocal();
    return _numericDay(local);
  }

  /// The viewer caption keeps the file name, date and zone in one sentence.
  static String viewerCaption(FileRecord file) {
    final DateTime? parsed = DateTime.tryParse(file.createdAt);
    final DateTime? local = parsed?.toLocal();
    final String date = local == null
        ? file.createdAt
        : '${local.day} de ${_monthName(local.month)}';
    final String zone = file.zona == Zona.praca ? 'na praça' : 'na casa';
    return '${file.name}, $date, $zone';
  }

  static String countLabelFor(
    StorageStats? storage, {
    required int fallbackCount,
  }) {
    if (storage case final StorageStats stats) {
      final int? videos = stats.videos;
      if (videos != null) return '${stats.photos} fotos, $videos vídeos';
      return '${stats.photos} fotos e vídeos';
    }
    return '$fallbackCount fotos e vídeos';
  }

  /// The load-more failure, the web's flash sentence.
  static const String loadMoreMessage =
      'Não foi possível carregar mais fotos agora.';

  /// The act failure's sentence: the box's own pt-BR when it spoke, the
  /// generic otherwise.
  static String failureMessage(TainaError failure) => failure.message;

  /// The action always offers the opposite of where the item is: the guarded
  /// zone is the CURRENT one.
  static String zonaActionLabel(Zona zona) =>
      zona == Zona.casa ? 'Publicar na praça' : 'Tirar da praça';

  static String zonaConfirmTitle(String name, Zona zona) => zona == Zona.casa
      ? 'Publicar "$name" na praça?'
      : 'Tirar "$name" da praça?';

  static String zonaConfirmBody(Zona zona) => zona == Zona.casa
      ? 'Todos os moradores vão poder ver. Você pode tirar da praça quando quiser.'
      : 'Volta a ser só seu. Só você, e quem você deixar, vê de novo.';

  static String zonaConfirmPrimary(Zona zona) =>
      zona == Zona.casa ? 'Publicar' : 'Tirar da praça';

  static String deleteFileTitle(String name) => 'Excluir "$name"?';

  static const String deleteFileMessage =
      'Vai para a lixeira. Dá para restaurar em até 30 dias.';

  static DateTime? _parseDay(String date) {
    final List<String> parts = date.split('-');
    if (parts.length != 3) return null;
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    final int? day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    final DateTime parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static String _numericDay(DateTime day) {
    final String dayPart = day.day.toString().padLeft(2, '0');
    final String monthPart = day.month.toString().padLeft(2, '0');
    return '$dayPart/$monthPart/${day.year}';
  }

  static String _monthName(int month) => const [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ][month - 1];

  // MARK: internals

  void _replace(FileRecord file) {
    _photos = replacing(file, _photos);
    _days = replacingInDays(file, _days);
  }

  void _removePhoto(String rkey) {
    _photos = removing(rkey, _photos);
    _days = removingFromDays(rkey, _days);
  }

  Future<void> _reload() async {
    _loading = true;
    _error = null;
    _reloadToken += 1;
    final int token = _reloadToken;
    _notify();
    switch (_tab) {
      case GalleryTab.grid:
        _gridStale = false;
        _gridGeneration += 1;
        final int generation = _gridGeneration;
        final TainaResult<Page<FileRecord>> result = await _gateway.api.photos(
          limit: null,
          cursor: null,
        );
        final TainaResult<Page<FileRecord>> screened = await _gateway.screen(
          result,
        );
        if (_disposed) return;
        if (generation == _gridGeneration) {
          switch (screened) {
            case Ok(:final value):
              _photos = value.items;
              _nextCursor = value.nextCursor;
              _loadedPageCount += 1;
            case Err(:final error):
              _error = error;
          }
        }
        break;
      case GalleryTab.timeline:
        _timelineStale = false;
        _timelineGeneration += 1;
        final int generation = _timelineGeneration;
        final TainaResult<Page<TimelineGroup>> result = await _gateway.api
            .photoTimeline(limit: null, cursor: null);
        final TainaResult<Page<TimelineGroup>> screened = await _gateway.screen(
          result,
        );
        if (_disposed) return;
        if (generation == _timelineGeneration) {
          switch (screened) {
            case Ok(:final value):
              _days = fusing(const [], value.items);
              _timelineCursor = value.nextCursor;
              _loadedPageCount += 1;
            case Err(:final error):
              _error = error;
          }
        }
        break;
    }
    if (_disposed || token != _reloadToken) return;
    _loading = false;
    _loaded = true;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The two lists on the segmented row.
enum GalleryTab { grid, timeline }

/// One day of the timeline for display: a page may split a day in two, so the
/// day shown is derived, fusing adjacent groups of the same date.
final class GalleryDay {
  GalleryDay({required this.date, required List<FileRecord> photos})
    : photos = List.unmodifiable(photos);

  final String date;
  final List<FileRecord> photos;

  @override
  bool operator ==(Object other) =>
      other is GalleryDay &&
      other.date == date &&
      _listEquals(other.photos, photos);

  @override
  int get hashCode => Object.hash(GalleryDay, date, Object.hashAll(photos));
}

/// The fullscreen viewer: the photos it swipes through and where it is.
final class GalleryViewerState {
  GalleryViewerState({required List<FileRecord> files, required this.index})
    : files = List.unmodifiable(files);

  final List<FileRecord> files;
  final int index;

  FileRecord? get file =>
      index >= 0 && index < files.length ? files[index] : null;
}

/// The empty state's words, per what is empty.
final class GalleryEmptyCopy {
  const GalleryEmptyCopy({required this.title, required this.message});

  final String title;
  final String message;
}

/// The viewer video page's own state, so the action row never spins with it.
sealed class GalleryVideoState {
  const GalleryVideoState();
}

final class GalleryVideoIdle extends GalleryVideoState {
  const GalleryVideoIdle();
}

final class GalleryVideoLoading extends GalleryVideoState {
  const GalleryVideoLoading(this.file);

  final FileRecord file;
}

final class GalleryVideoReady extends GalleryVideoState {
  const GalleryVideoReady({required this.file, required this.path});

  final FileRecord file;
  final String path;
}

final class GalleryVideoFailed extends GalleryVideoState {
  const GalleryVideoFailed({required this.file, required this.error});

  final FileRecord file;
  final TainaError error;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
