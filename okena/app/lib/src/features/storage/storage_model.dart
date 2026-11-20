import 'package:flutter/foundation.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// One community-wide zone in the storage breakdown.
final class StorageZoneLine {
  const StorageZoneLine({
    required this.title,
    required this.bytes,
    required this.icon,
  });

  final String title;
  final int bytes;
  final TainaIcon icon;
}

/// The community storage portrait and the zelador's quota action.
final class StorageModel extends ChangeNotifier {
  StorageModel({required this.gateway});

  final SessionGateway gateway;

  StorageStats? _stats;
  bool _loading = true;
  TainaError? _error;
  bool _saving = false;
  Ava? _me;
  List<String> _zeladorNames = const [];
  bool _disposed = false;

  StorageStats? get stats => _stats;
  bool get loading => _loading;
  TainaError? get error => _error;
  bool get saving => _saving;
  bool get isZelador => _me?.papel == Papel.zelador;
  List<String> get zeladorNames => _zeladorNames;

  Future<void> load() async {
    _loading = true;
    _notify();
    await Future.wait<void>([_loadMe(), _loadZeladores()]);
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

  /// The quota belongs to the whole community. Null means the whole disk.
  Future<TainaResult<void>> setQuota(int? bytes) async {
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
    if (result case Ok(:final value)) _me = value.ava;
  }

  Future<void> _loadZeladores() async {
    final result = await gateway.screen(await gateway.api.members());
    if (result case Ok(:final value)) {
      _zeladorNames = List<String>.unmodifiable([
        for (final Ava ava in value.items)
          if (ava.papel == Papel.zelador &&
              ava.activatedAt != null &&
              ava.deactivatedAt == null)
            ava.label,
      ]);
    }
  }

  // Pure transitions.

  /// Optional only when the returned zone values are a non-negative partition
  /// of the reported community-wide total.
  static List<StorageZoneLine>? zones(StorageStats stats) {
    final StorageByZone? byZone = stats.byZone;
    if (byZone == null ||
        byZone.casa < 0 ||
        byZone.praca < 0 ||
        byZone.lixeira < 0 ||
        byZone.casa + byZone.praca + byZone.lixeira != stats.usedBytes) {
      return null;
    }

    return [
      StorageZoneLine(
        title: 'Casas (de cada morador)',
        bytes: byZone.casa,
        icon: TainaIcon.casa,
      ),
      StorageZoneLine(
        title: 'Praça',
        bytes: byZone.praca,
        icon: TainaIcon.praca,
      ),
      StorageZoneLine(
        title: 'Lixeira',
        bytes: byZone.lixeira,
        icon: TainaIcon.lixeira,
      ),
    ];
  }

  /// The size of the box data disk, preferring the current field and retaining
  /// the older total-size fields as a fallback.
  static int? diskBytes(StorageStats stats) =>
      stats.diskBytes ?? stats.diskTotalBytes;

  /// Physical free space, derived from the disk size when the box did not send
  /// its explicit free-space count.
  static int? diskFreeBytes(StorageStats stats) {
    final int? free = stats.diskFreeBytes;
    if (free != null) return free < 0 ? 0 : free;
    final int? total = diskBytes(stats);
    if (total == null) return null;
    return (total - stats.usedBytes).clamp(0, total).toInt();
  }

  static StorageSummary summary(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    final int? disk = diskBytes(stats);
    final String used = TainaFormat.bytes(stats.usedBytes);
    final String usedLabel;
    final int? denominator;

    if (quota != null) {
      usedLabel = '$used de ${TainaFormat.bytes(quota)}';
      denominator = quota;
    } else if (disk != null) {
      usedLabel = 'Usando o disco inteiro: $used de ${TainaFormat.bytes(disk)}';
      denominator = disk;
    } else {
      usedLabel = 'Usando o disco inteiro: $used em uso';
      denominator = null;
    }

    final String caption;
    if (quota != null && stats.usedBytes > quota) {
      caption = 'O limite está abaixo do espaço usado.';
    } else {
      final int? free = quota == null
          ? diskFreeBytes(stats)
          : quota - stats.usedBytes;
      caption = free == null
          ? 'Espaço livre não informado.'
          : '${TainaFormat.bytes(free)} livres';
    }
    final double progress = denominator == null || denominator <= 0
        ? 0
        : (stats.usedBytes / denominator).clamp(0.0, 1.0).toDouble();

    return StorageSummary(
      usedLabel: usedLabel,
      caption: caption,
      progress: progress,
    );
  }

  static bool isOverQuota(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    return quota != null && stats.usedBytes > quota;
  }

  /// The quota in whole gigabytes, rounded up.
  static int gigabytes(int? bytes) {
    if (bytes == null || bytes <= 0) return 250;
    const int gib = 1073741824;
    return (bytes + gib - 1) ~/ gib;
  }

  /// The bytes of a whole number of gigabytes, the way the wire wants.
  static int bytesFromGigabytes(int gigabytes) => gigabytes * 1073741824;

  static String moradorFooter(String? zeladorName) {
    const String opening =
        'Quem cuida da caixa escolhe quanto do disco a comunidade usa.';
    if (zeladorName == null) return opening;
    return '$opening Hoje, esse cuidado é de $zeladorName.';
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
