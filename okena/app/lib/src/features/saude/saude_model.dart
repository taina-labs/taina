import 'package:flutter/foundation.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

enum SaudePanelState { morador, zelador, atencao }

/// One board row for the community's four health facts.
final class SaudeStatus {
  const SaudeStatus({required this.state, required this.title});

  final TainaStatusState state;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is SaudeStatus && other.state == state && other.title == title;

  @override
  int get hashCode => Object.hash(state, title);
}

/// The cloud health panel. Its status selection and copy are pure; API calls
/// stay at the edge.
final class SaudeModel extends ChangeNotifier {
  SaudeModel({required this.gateway});

  final SessionGateway gateway;

  static const double diskWarningShare = 0.9;
  static const double diskFreeWarningShare = 0.1;

  Saude? _saude;
  bool _loading = true;
  TainaError? _error;
  bool _triggering = false;
  Ava? _me;
  List<String> _zeladorNames = const [];
  bool _disposed = false;

  Saude? get saude => _saude;
  bool get loading => _loading;
  TainaError? get error => _error;
  bool get triggering => _triggering;
  bool get isZelador => _me?.papel == Papel.zelador;
  List<String> get zeladorNames => _zeladorNames;

  /// A backup can be requested again after a failure, and the first backup can
  /// be started by a zelador. The box remains the authority.
  bool get canTriggerBackup =>
      isZelador &&
      switch (_saude?.backup.status) {
        SaudeBackupStatus.ok ||
        SaudeBackupStatus.none ||
        SaudeBackupStatus.never ||
        SaudeBackupStatus.failed ||
        SaudeBackupStatus.unreadable => true,
        SaudeBackupStatus.disabled ||
        SaudeBackupStatus.notConfigured ||
        null => false,
      };

  SaudePanelState get panelState {
    final Saude? value = _saude;
    if (value == null) {
      return isZelador ? SaudePanelState.zelador : SaudePanelState.morador;
    }
    return stateFor(value, isZelador: isZelador);
  }

  Future<void> load() async {
    _loading = true;
    _notify();
    await Future.wait<void>([_loadMe(), _loadZeladores()]);
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

  /// Queues a backup. The last-backup row changes only after one completes.
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

  static List<SaudeStatus> statuses(Saude saude) {
    final StorageStats storage = saude.storage;
    final bool nearlyFull =
        saude.summary?.line == 'Disco quase cheio' || isAlmostFull(storage);
    final SaudeStatus backup = backupStatus(saude.backup);
    final SaudeStatus update = updateStatus(saude.update);

    return [
      SaudeStatus(
        state: nearlyFull ? TainaStatusState.attention : TainaStatusState.ok,
        title: nearlyFull ? 'Disco quase cheio' : 'Espaço de sobra',
      ),
      backup,
      update,
      const SaudeStatus(state: TainaStatusState.ok, title: 'Tudo no ar'),
    ];
  }

  static SaudeStatus backupStatus(SaudeBackup backup) {
    return switch (backup.status) {
      SaudeBackupStatus.ok => const SaudeStatus(
        state: TainaStatusState.ok,
        title: 'Backup em dia',
      ),
      SaudeBackupStatus.none || SaudeBackupStatus.never => const SaudeStatus(
        state: TainaStatusState.attention,
        title: 'Nenhum backup ainda',
      ),
      SaudeBackupStatus.failed => const SaudeStatus(
        state: TainaStatusState.problem,
        title: 'Último backup falhou',
      ),
      SaudeBackupStatus.disabled => const SaudeStatus(
        state: TainaStatusState.attention,
        title: 'Backup desativado',
      ),
      SaudeBackupStatus.notConfigured => const SaudeStatus(
        state: TainaStatusState.attention,
        title: 'Backup sem destino',
      ),
      SaudeBackupStatus.unreadable => const SaudeStatus(
        state: TainaStatusState.unknown,
        title: 'Backup indisponível',
      ),
    };
  }

  /// Until BE-4 reports an update state, keep the row present but unknown.
  static SaudeStatus updateStatus(SaudeUpdate? update) {
    if (update == null) {
      return const SaudeStatus(
        state: TainaStatusState.unknown,
        title: 'Atualizações',
      );
    }

    return switch (update.status) {
      SaudeUpdateStatus.upToDate => const SaudeStatus(
        state: TainaStatusState.ok,
        title: 'Atualizações em dia',
      ),
      SaudeUpdateStatus.updateAvailable => const SaudeStatus(
        state: TainaStatusState.attention,
        title: 'Atualização disponível',
      ),
      SaudeUpdateStatus.checking => const SaudeStatus(
        state: TainaStatusState.unknown,
        title: 'Buscando atualizações',
      ),
      SaudeUpdateStatus.checkOff => const SaudeStatus(
        state: TainaStatusState.unknown,
        title: 'Atualizações desativadas',
      ),
      SaudeUpdateStatus.unavailable => const SaudeStatus(
        state: TainaStatusState.unknown,
        title: 'Atualizações indisponíveis',
      ),
      SaudeUpdateStatus.unknown => const SaudeStatus(
        state: TainaStatusState.unknown,
        title: 'Atualizações',
      ),
    };
  }

  static SaudePanelState stateFor(Saude saude, {required bool isZelador}) {
    final bool summaryNeedsAttention =
        saude.summary?.state == SaudeSummaryState.attention;
    final bool rowNeedsAttention = statuses(saude).any(
      (SaudeStatus row) =>
          row.state == TainaStatusState.attention ||
          row.state == TainaStatusState.problem,
    );
    if (summaryNeedsAttention || rowNeedsAttention) {
      return SaudePanelState.atencao;
    }
    return isZelador ? SaudePanelState.zelador : SaudePanelState.morador;
  }

  static String footer(SaudePanelState state, {String? zeladorName}) {
    return switch (state) {
      SaudePanelState.morador =>
        zeladorName == null
            ? 'Quem cuida da nuvem cuida da máquina, não dos arquivos.'
            : 'Quem cuida da nuvem: $zeladorName. '
                  'Cuida da máquina, não dos arquivos.',
      SaudePanelState.zelador =>
        'Você cuida da nuvem. O backup é a sua parte; os arquivos continuam '
            'de cada um.',
      SaudePanelState.atencao =>
        'Vale falar com quem cuida da nuvem. Ninguém perdeu arquivo.',
    };
  }

  static bool isAlmostFull(StorageStats stats) {
    return _physicalDiskAlmostFull(stats) || _quotaAlmostFull(stats);
  }

  static bool _quotaAlmostFull(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    if (quota == null || quota <= 0) return false;
    return stats.usedBytes / quota >= diskWarningShare;
  }

  static bool _physicalDiskAlmostFull(StorageStats stats) {
    final int? total = stats.diskBytes ?? stats.diskTotalBytes;
    final int? free =
        stats.diskFreeBytes ??
        (total == null
            ? null
            : (total - stats.usedBytes).clamp(0, total).toInt());
    if (total == null || total <= 0 || free == null || free < 0) {
      return false;
    }
    return free / total <= diskFreeWarningShare;
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
