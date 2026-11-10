import 'package:flutter/foundation.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The glyph of a saude row. The model stays free of icons; the widget maps
/// the meaning to the design system.
enum SaudeRowIcon { disk, backup, jobs }

/// One row of the panel: a glyph, a label, the facts as lines, and the warning
/// when the fact needs one. Icon and phrase together, never a color alone.
final class SaudeRow {
  const SaudeRow({
    required this.icon,
    required this.label,
    required this.lines,
    this.warning,
  });

  final SaudeRowIcon icon;
  final String label;
  final List<String> lines;
  final String? warning;
}

/// The saúde panel's state: one load of `GET /saude`, the rows built by pure
/// functions.
///
/// Facts of the present, in plain words, for the whole community. The backup
/// trigger is the zeladora's act and the server enforces it.
final class SaudeModel extends ChangeNotifier {
  SaudeModel({required this.gateway});

  final SessionGateway gateway;

  /// The share of the quota where "o espaço está acabando" starts, the web's
  /// own threshold.
  static const double diskWarningShare = 0.9;

  /// The label of the backup row, the anchor the screen hangs the zeladora's
  /// act on.
  static const String backupLabel = 'Último backup';

  Saude? _saude;
  bool _loading = true;
  TainaError? _error;
  bool _triggering = false;
  Ava? _me;
  bool _disposed = false;

  Saude? get saude => _saude;
  bool get loading => _loading;
  TainaError? get error => _error;

  /// Whether the box is taking the backup request right now.
  bool get triggering => _triggering;

  /// The acts belong to whoever cares for the box; the server enforces it
  /// again anyway.
  bool get isZelador => _me?.papel == Papel.zelador;

  Future<void> load() async {
    _loading = true;
    _notify();
    await _loadMe();
    final result = await gateway.screen(await gateway.api.saude());
    switch (result) {
      case Ok(:final value):
        _saude = value;
        _error = null;
      case Err(:final error):
        _error = error;
    }
    _loading = false;
    _notify();
  }

  /// Asks the box to back itself up now: the answer is the queue, not the
  /// backup, so the row still reads the last one that finished.
  Future<TainaResult<void>> backupNow() async {
    _triggering = true;
    _notify();
    final result = await gateway.screen(await gateway.api.triggerBackup());
    _triggering = false;
    _notify();
    return result;
  }

  Future<void> _loadMe() async {
    final result = await gateway.screen(await gateway.api.me());
    if (result case Ok(:final value)) {
      _me = value.ava;
    }
  }

  // Pure transitions.

  /// The panel's rows, in the order of the web's: disco, backup, and the
  /// queued work, which disappears when there is none.
  static List<SaudeRow> rows(Saude saude) {
    return [
      diskRow(saude.storage),
      backupRow(saude.backup),
      jobsRow(saude.jobs),
    ].whereType<SaudeRow>().toList(growable: false);
  }

  static SaudeRow diskRow(StorageStats stats) {
    final List<String> lines;
    final int? quota = stats.quotaBytes;
    if (quota != null) {
      final int free = quota - stats.usedBytes < 0
          ? 0
          : quota - stats.usedBytes;
      lines = [
        '${TainaFormat.bytes(stats.usedBytes)} usados de '
            '${TainaFormat.bytes(quota)}. ${TainaFormat.bytes(free)} livres.',
      ];
    } else {
      lines = ['${TainaFormat.bytes(stats.usedBytes)} usados. Sem limite.'];
    }
    lines.addAll(trashLines(stats.trash));
    return SaudeRow(
      icon: SaudeRowIcon.disk,
      label: 'Disco',
      lines: List<String>.unmodifiable(lines),
      warning: isAlmostFull(stats)
          ? 'O espaço está acabando. Quem cuida da máquina pode aumentar o '
                'limite.'
          : null,
    );
  }

  /// The trash still counts against the quota until the purge: said in
  /// aggregate, no names. An empty trash is no fact, no line.
  static List<String> trashLines(StorageTrash trash) {
    if (trash.count <= 0) return const [];
    final String files = trash.count == 1
        ? '1 arquivo'
        : '${trash.count} arquivos';
    return [
      '${TainaFormat.bytes(trash.bytes)} na lixeira esperando a limpeza '
          '($files).',
    ];
  }

  static bool isAlmostFull(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    if (quota == null || quota <= 0) return false;
    return stats.usedBytes / quota >= diskWarningShare;
  }

  static SaudeRow backupRow(SaudeBackup backup) {
    final List<String> lines;
    if (backup.at case final String at) {
      final int? bytes = backup.bytes;
      lines = [
        bytes != null
            ? 'Terminou bem ${TainaFormat.date(at)} '
                  '(${TainaFormat.bytes(bytes)} guardados).'
            : 'Terminou bem ${TainaFormat.date(at)}.',
      ];
    } else {
      lines = [
        'Nunca foi feito um backup.',
        'Quem cuida da máquina cuida do backup.',
      ];
    }
    return SaudeRow(
      icon: SaudeRowIcon.backup,
      label: backupLabel,
      lines: List<String>.unmodifiable(lines),
    );
  }

  /// Work waiting or running, one line per queue with work. All quiet, no row
  /// at all: a zero is a number, not a fact.
  static SaudeRow? jobsRow(Map<String, int> jobs) {
    final List<String> lines = jobLines(jobs);
    if (lines.isEmpty) return null;
    return SaudeRow(
      icon: SaudeRowIcon.jobs,
      label: 'Trabalhos da caixa',
      lines: List<String>.unmodifiable(lines),
    );
  }

  static List<String> jobLines(Map<String, int> jobs) {
    final List<MapEntry<String, int>> active = [
      for (final MapEntry<String, int> entry in jobs.entries)
        if (entry.value > 0) entry,
    ];
    active.sort(
      (MapEntry<String, int> lhs, MapEntry<String, int> rhs) =>
          lhs.key.compareTo(rhs.key),
    );
    return List<String>.unmodifiable([
      for (final MapEntry<String, int> entry in active)
        jobLine(queue: entry.key, count: entry.value),
    ]);
  }

  /// The queues the box has, in the words the web uses; an unknown queue keeps
  /// its name and is said plainly.
  static String jobLine({required String queue, required int count}) {
    switch (queue) {
      case 'renditions':
        return count == 1
            ? '1 miniatura ainda sendo gerada'
            : '$count miniaturas ainda sendo geradas';
      case 'trash_purge':
        return count == 1
            ? '1 limpeza da lixeira em andamento'
            : '$count limpezas da lixeira em andamento';
      case 'backups':
        return count == 1
            ? '1 backup em andamento'
            : '$count backups em andamento';
      default:
        return count == 1
            ? '1 trabalho na fila $queue'
            : '$count trabalhos na fila $queue';
    }
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
