import 'package:flutter/foundation.dart';
import 'package:okena_app/src/design_system/format.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The home's state: the recent uploads, the storage card, a mural teaser and
/// the count of pending access requests.
///
/// The home degrades instead of falling: every section carries its own error,
/// so one failing call never blanks the screen.
final class HomeModel extends ChangeNotifier {
  HomeModel(this._gateway) {
    _communityName = _gateway.identity?.tekoa.name;
  }

  final SessionGateway _gateway;

  bool _loaded = false;
  String? _communityName;
  List<FileRecord> _recent = const [];
  TainaError? _recentError;
  StorageStats? _stats;
  bool _statsError = false;
  List<HomeMuralLine> _mural = const [];
  bool _muralError = false;
  int? _pendingRequests;
  bool _requestsError = false;
  bool _disposed = false;

  bool get loaded => _loaded;
  String? get communityName => _communityName;
  List<FileRecord> get recent => _recent;
  TainaError? get recentError => _recentError;
  StorageStats? get stats => _stats;
  bool get statsError => _statsError;
  List<HomeMuralLine> get mural => _mural;
  bool get muralError => _muralError;
  int? get pendingRequests => _pendingRequests;
  bool get requestsError => _requestsError;

  Future<void> load() async {
    if (_disposed) return;
    await _loadInstance();
    await _loadMural();
    await _loadRecent();
    await _loadStorage();
    await _loadRequests();
    if (_disposed) return;
    _loaded = true;
    _notify();
  }

  /// The storage card's own way back: only the stats, never the whole screen.
  Future<void> retryStorage() => _loadStorage();

  // MARK: pure transitions

  /// The greeting by the clock of the device: the phone is where the person
  /// is, so its hour is the hour that greets them.
  static String greeting(int hour) {
    if (hour >= 5 && hour <= 11) return 'Bom dia,';
    if (hour >= 12 && hour <= 17) return 'Boa tarde,';
    return 'Boa noite,';
  }

  /// A quota defined and above zero: without one there is no free space to
  /// measure, and the card shows only the use.
  static bool hasQuota(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    return quota != null && quota > 0;
  }

  /// How much of the community's space is in use, 0...100.
  static int storagePercent(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    if (quota == null || quota <= 0) return 0;
    final double fraction = stats.usedBytes / quota;
    final int percent = (fraction * 100).round();
    return percent < 0 ? 0 : (percent > 100 ? 100 : percent);
  }

  /// Nearly full: 90% of the quota or more. Words and an icon carry the
  /// warning, never the color alone.
  static bool storageLow(StorageStats stats) =>
      hasQuota(stats) && storagePercent(stats) >= 90;

  static String freeLabel(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    if (quota == null || quota <= 0) return '';
    final String free = TainaFormat.bytes(quota - stats.usedBytes);
    return storageLow(stats) ? 'quase cheia: $free livres' : '$free livres';
  }

  /// The meta of a recent row ends in the zone, in words (never color alone):
  /// "Imagem, 2,4 MB, ontem, na praça".
  static String recentMeta(FileRecord file, {DateTime? now}) {
    return [
      fileKind(file.mime),
      TainaFormat.bytes(file.size),
      TainaFormat.relative(file.createdAt, now: now),
      zonaWord(file.zona),
    ].where((String part) => part.isNotEmpty).join(', ');
  }

  static String zonaWord(Zona zona) =>
      zona == Zona.praca ? 'na praça' : 'na casa';

  /// The short kind word for a row ("PDF", "Imagem"...).
  static String fileKind(String mime) {
    if (mime.startsWith('image/')) return 'Imagem';
    if (mime.startsWith('video/')) return 'Vídeo';
    if (mime.startsWith('audio/')) return 'Áudio';
    if (mime == 'application/pdf') return 'PDF';
    if (mime == 'application/zip') return 'ZIP';
    if (mime.startsWith('text/')) return 'Texto';
    return 'Arquivo';
  }

  static String pendingLabel(int count) {
    if (count == 0) return 'Nenhum pedido esperando';
    if (count == 1) return '1 pedido esperando';
    return '$count pedidos esperando';
  }

  /// The pending ones are the only count worth a card: a decided pedido
  /// registers a fact, it does not ask for anything.
  static int pendingCount(Page<Pedido> page) {
    return page.items
        .where((Pedido pedido) => pedido.status == PedidoStatus.pendente)
        .length;
  }

  /// The teaser rows, newest first, each a ready sentence, from the one
  /// shared table of mural phrases.
  static List<HomeMuralLine> lines(
    List<MuralEntry> entries,
    Map<String, String> names, {
    DateTime? now,
  }) {
    return [
      for (final MuralEntry entry in entries)
        HomeMuralLine(
          id: entry.cid,
          sentence: sentence(entry, names),
          ago: TainaFormat.relative(entry.createdAt, now: now),
        ),
    ];
  }

  /// The actor's public id becomes a label from the roster; the screen is
  /// who translates ids to people.
  static Map<String, String> actorNames(List<Ava> avas) => {
    for (final Ava ava in avas) ava.publicId: ava.label,
  };

  /// The sentence the entry becomes, the web's own table. The mural is
  /// append-only: a type the screen does not know yet keeps its row on the
  /// air with the generic sentence.
  static String sentence(MuralEntry entry, Map<String, String> names) {
    final String actor = actorLabel(entry, names);
    final String? role = _string(entry, 'role');
    final String? member = _string(entry, 'member');
    final bool folder = _string(entry, 'collection') == 'ypy.folder.v0';
    switch (entry.tipo) {
      case 'invite_created':
        return role == 'zelador'
            ? '$actor convidou uma nova pessoa para cuidar da máquina.'
            : '$actor convidou uma nova pessoa para a comunidade.';
      case 'invite_accepted':
        return role == 'zelador'
            ? '$actor entrou na comunidade para cuidar da máquina.'
            : '$actor entrou na comunidade.';
      case 'invite_revoked':
        return role == 'zelador'
            ? '$actor revogou um convite para cuidar da máquina.'
            : '$actor revogou um convite.';
      case 'reset_link_created':
        return member != null
            ? '$actor gerou um link de nova senha para $member.'
            : '$actor gerou um link de nova senha para um membro da comunidade.';
      case 'member_deactivated':
        return member != null
            ? '$actor desativou a conta de $member.'
            : '$actor desativou uma conta.';
      case 'member_reactivated':
        return member != null
            ? '$actor reativou a conta de $member.'
            : '$actor reativou uma conta.';
      case 'quota_changed':
        final int? to = _int(entry, 'to');
        final int? from = _int(entry, 'from');
        if (from != null && to != null) {
          return '$actor mudou o limite de armazenamento de '
              '${TainaFormat.bytes(from)} para ${TainaFormat.bytes(to)}.';
        }
        if (to != null) {
          return '$actor mudou o limite de armazenamento para '
              '${TainaFormat.bytes(to)}.';
        }
        return '$actor mudou o limite de armazenamento.';
      case 'put':
        return folder
            ? '$actor criou uma pasta.'
            : '$actor guardou um arquivo na caixa.';
      case 'publicar':
        return folder
            ? '$actor publicou uma pasta na praça.'
            : '$actor publicou um arquivo na praça.';
      case 'tirar_da_praca':
        return folder
            ? '$actor tirou uma pasta da praça.'
            : '$actor tirou um arquivo da praça.';
      case 'apagar':
        return folder
            ? '$actor mandou uma pasta para a lixeira.'
            : '$actor mandou um arquivo para a lixeira.';
      case 'restaurar':
        return '$actor tirou um arquivo da lixeira.';
      case 'mover':
        return '$actor moveu um arquivo de pasta.';
      case 'renomear':
        return folder
            ? '$actor renomeou uma pasta.'
            : '$actor renomeou um arquivo.';
      case 'concessao':
        return '$actor abriu a sua casa para a leitura de um morador.';
      case 'revogar':
        return '$actor tirou a leitura que tinha aberto.';
      case 'mudar_papel':
        return role == 'zelador'
            ? '$actor deu a um morador o cuidado da máquina.'
            : '$actor tirou de um morador o cuidado da máquina.';
      default:
        return '$actor fez um ato registrado na comunidade.';
    }
  }

  /// Without an actor, or with one the roster no longer knows, "O sistema"
  /// speaks, like the web does.
  static String actorLabel(MuralEntry entry, Map<String, String> names) {
    final String? pid = _string(entry, 'actor');
    final String? name = pid == null ? null : names[pid];
    return name ?? 'O sistema';
  }

  // MARK: internals

  Future<void> _loadInstance() async {
    final TainaResult<Instance> result = await _gateway.api.instance();
    final TainaResult<Instance> screened = await _gateway.screen(result);
    if (_disposed) return;
    if (screened case Ok(:final value)) {
      _communityName = value.tekoa?.name;
      _notify();
    }
  }

  Future<void> _loadRecent() async {
    final TainaResult<Page<FileRecord>> result = await _gateway.api.recent(
      limit: 4,
    );
    final TainaResult<Page<FileRecord>> screened = await _gateway.screen(
      result,
    );
    if (_disposed) return;
    switch (screened) {
      case Ok(:final value):
        _recent = value.items;
        _recentError = null;
      case Err(:final error):
        _recent = const [];
        _recentError = error;
    }
    _notify();
  }

  Future<void> _loadStorage() async {
    final TainaResult<StorageStats> result = await _gateway.api.storage();
    final TainaResult<StorageStats> screened = await _gateway.screen(result);
    if (_disposed) return;
    switch (screened) {
      case Ok(:final value):
        _stats = value;
        _statsError = false;
      case Err():
        _stats = null;
        _statsError = true;
    }
    _notify();
  }

  Future<void> _loadMural() async {
    Map<String, String> names = const {};
    final TainaResult<Page<Ava>> roster = await _gateway.api.members();
    final TainaResult<Page<Ava>> screenedRoster = await _gateway.screen(roster);
    if (_disposed) return;
    if (screenedRoster case Ok(:final value)) {
      names = actorNames(value.items);
    }
    final TainaResult<Page<MuralEntry>> result = await _gateway.api.mural(
      limit: 3,
      cursor: null,
    );
    final TainaResult<Page<MuralEntry>> screened = await _gateway.screen(
      result,
    );
    if (_disposed) return;
    switch (screened) {
      case Ok(:final value):
        _mural = lines(value.items, names);
        _muralError = false;
      case Err():
        _mural = const [];
        _muralError = true;
    }
    _notify();
  }

  Future<void> _loadRequests() async {
    final TainaResult<Page<Pedido>> result = await _gateway.api
        .accessRequests();
    final TainaResult<Page<Pedido>> screened = await _gateway.screen(result);
    if (_disposed) return;
    switch (screened) {
      case Ok(:final value):
        _pendingRequests = pendingCount(value);
        _requestsError = false;
      case Err():
        _pendingRequests = null;
        _requestsError = true;
    }
    _notify();
  }

  static String? _string(MuralEntry entry, String key) {
    final JsonValue? value = entry.payload[key];
    return value is JsonString ? value.value : null;
  }

  static int? _int(MuralEntry entry, String key) {
    final JsonValue? value = entry.payload[key];
    return value is JsonInt ? value.value : null;
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

/// One teaser row: the sentence the entry becomes and when it happened.
final class HomeMuralLine {
  const HomeMuralLine({
    required this.id,
    required this.sentence,
    required this.ago,
  });

  final String id;
  final String sentence;
  final String ago;

  @override
  bool operator ==(Object other) =>
      other is HomeMuralLine &&
      other.id == id &&
      other.sentence == sentence &&
      other.ago == ago;

  @override
  int get hashCode => Object.hash(HomeMuralLine, id, sentence, ago);
}
