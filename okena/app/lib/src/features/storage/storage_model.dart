import 'package:flutter/foundation.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The kind of content a storage line counts: the wire's four buckets.
enum StorageKind {
  photos,
  videos,
  documents,
  others;

  String get label => switch (this) {
    StorageKind.photos => 'Fotos',
    StorageKind.videos => 'Vídeos',
    StorageKind.documents => 'Documentos',
    StorageKind.others => 'Outros',
  };
}

/// One segment of the usage bar: a kind and its share of the used bytes.
final class StorageSegment {
  const StorageSegment({required this.kind, required this.fraction});

  final StorageKind kind;
  final double fraction;
}

/// One row of the by-kind breakdown.
final class StorageKindLine {
  const StorageKindLine({required this.kind, required this.bytes});

  final StorageKind kind;
  final int bytes;
}

/// The armazenamento screen's state: one load of the storage portrait, the
/// math pure.
///
/// The quota belongs to the box, and setting it is the zeladora's, from this
/// screen.
final class StorageModel extends ChangeNotifier {
  StorageModel({required this.gateway});

  final SessionGateway gateway;

  StorageStats? _stats;
  bool _loading = true;
  TainaError? _error;
  bool _saving = false;
  Ava? _me;
  bool _disposed = false;

  StorageStats? get stats => _stats;
  bool get loading => _loading;
  TainaError? get error => _error;

  /// The quota the box is saving right now.
  bool get saving => _saving;

  /// The acts belong to whoever cares for the box; the server enforces it
  /// again anyway.
  bool get isZelador => _me?.papel == Papel.zelador;

  Future<void> load() async {
    _loading = true;
    _notify();
    await _loadMe();
    final result = await gateway.screen(await gateway.api.storage());
    switch (result) {
      case Ok(:final value):
        _stats = value;
        _error = null;
      case Err(:final error):
        _error = error;
    }
    _loading = false;
    _notify();
  }

  /// The zeladora's new limit, in bytes. The answer is the Tekoa; the portrait
  /// is read again so every line agrees with the box.
  Future<TainaResult<void>> setQuota(int bytes) async {
    _saving = true;
    _notify();
    final result = await gateway.screen(
      await gateway.api.setQuota(bytes: bytes),
    );
    _saving = false;
    switch (result) {
      case Ok():
        await load();
        return const Ok<void>(null);
      case Err(:final error):
        _notify();
        return Err<void>(error);
    }
  }

  Future<void> _loadMe() async {
    final result = await gateway.screen(await gateway.api.me());
    if (result case Ok(:final value)) {
      _me = value.ava;
    }
  }

  // Pure transitions.

  /// The by-kind rows, widest first, the order the web shows.
  static List<StorageKindLine> kinds(StorageStats stats) {
    final List<StorageKindLine> lines = [
      StorageKindLine(kind: StorageKind.photos, bytes: stats.byKind.photos),
      StorageKindLine(kind: StorageKind.videos, bytes: stats.byKind.videos),
      StorageKindLine(
        kind: StorageKind.documents,
        bytes: stats.byKind.documents,
      ),
      StorageKindLine(kind: StorageKind.others, bytes: stats.byKind.others),
    ];
    lines.sort(
      (StorageKindLine lhs, StorageKindLine rhs) =>
          rhs.bytes.compareTo(lhs.bytes),
    );
    return List<StorageKindLine>.unmodifiable(lines);
  }

  /// The bar's segments: only the kinds holding bytes, each as a share of the
  /// used total. Nothing used, no segments, just the track.
  static List<StorageSegment> segments(StorageStats stats) {
    if (stats.usedBytes <= 0) return const [];
    final List<(StorageKind, int)> all = [
      (StorageKind.photos, stats.byKind.photos),
      (StorageKind.videos, stats.byKind.videos),
      (StorageKind.documents, stats.byKind.documents),
      (StorageKind.others, stats.byKind.others),
    ];
    final List<(StorageKind, int)> used = [
      for (final entry in all)
        if (entry.$2 > 0) entry,
    ];
    used.sort((a, b) => b.$2.compareTo(a.$2));
    return List<StorageSegment>.unmodifiable([
      for (final entry in used)
        StorageSegment(kind: entry.$1, fraction: entry.$2 / stats.usedBytes),
    ]);
  }

  /// What the by-kind list adds up to: the part of the vault this person can
  /// see, not the box's whole usage.
  static int byKindTotal(StorageStats stats) {
    return stats.byKind.photos +
        stats.byKind.videos +
        stats.byKind.documents +
        stats.byKind.others;
  }

  /// True when the free room is at most a tenth of the quota, the web's
  /// threshold for the amber "livres". Without a quota, never.
  static bool isLowFree(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    if (quota == null || quota <= 0) return false;
    return (quota - stats.usedBytes) / quota <= 0.1;
  }

  /// True when what is already kept is past the quota: the free room went
  /// negative, and "X livres" would be a lie. Setting a limit below the use is
  /// allowed on the box, on purpose.
  static bool isOverQuota(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    if (quota == null) return false;
    return stats.usedBytes > quota;
  }

  /// The quota in whole gigabytes, rounded up, for the field that edits it.
  /// Without a quota, the field opens at the web's default.
  static int gigabytes(int? bytes) {
    if (bytes == null || bytes <= 0) return 250;
    const int gib = 1073741824;
    return (bytes + gib - 1) ~/ gib;
  }

  /// The bytes of a whole number of gigabytes, the way the wire wants.
  static int bytesFromGigabytes(int gigabytes) => gigabytes * 1073741824;

  /// The trash row's value: "1 arquivo, 2,4 MB".
  static String trashSummary(StorageTrash trash) {
    final String files = trash.count == 1
        ? '1 arquivo'
        : '${trash.count} arquivos';
    return '$files, ${TainaFormat.bytes(trash.bytes)}';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
