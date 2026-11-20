import 'package:flutter/foundation.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The home's state: the recent uploads, the storage card, a mural teaser and
/// the count of pending access requests.
///
/// The home degrades instead of falling: every section carries its own error,
/// so one failing call never blanks the screen.
final class HomeModel extends ChangeNotifier {
  HomeModel(this._gateway) {
    final Me? identity = _gateway.identity;
    _communityName = identity?.tekoa.name;
    _userName = identity == null ? null : firstName(identity.ava.label);
  }

  final SessionGateway _gateway;

  bool _loaded = false;
  String? _communityName;
  String? _userName;
  List<FileRecord> _recent = const [];
  TainaError? _recentError;
  StorageStats? _stats;
  TainaError? _statsError;
  List<HomeMuralLine> _mural = const [];
  TainaError? _muralError;
  int? _activeMembers;
  TainaError? _membersError;
  String? _healthSummary;
  TainaError? _healthError;
  int? _pendingRequests;
  String? _firstPendingName;
  TainaError? _requestsError;
  bool _disposed = false;
  Future<void>? _activeLoad;

  bool get loaded => _loaded;
  String? get communityName => _communityName;
  String? get userName => _userName;
  List<FileRecord> get recent => _recent;
  TainaError? get recentError => _recentError;
  StorageStats? get stats => _stats;
  TainaError? get statsError => _statsError;
  List<HomeMuralLine> get mural => _mural;
  TainaError? get muralError => _muralError;
  int? get activeMembers => _activeMembers;
  TainaError? get membersError => _membersError;
  String? get healthSummary => _healthSummary;
  TainaError? get healthError => _healthError;
  int? get pendingRequests => _pendingRequests;
  String? get firstPendingName => _firstPendingName;
  TainaError? get requestsError => _requestsError;

  Future<void> load() {
    if (_disposed) return Future<void>.value();
    final Future<void>? active = _activeLoad;
    if (active != null) return active;
    final Future<void> next = _load();
    _activeLoad = next;
    return next.whenComplete(() {
      if (identical(_activeLoad, next)) _activeLoad = null;
    });
  }

  Future<void> _load() async {
    _loaded = false;
    _notify();
    await Future.wait<void>([
      _loadRecent(),
      _loadStorage(),
      _loadRequests(),
      _loadHealth(),
      _loadCommunity(),
    ]);
    if (_disposed) return;
    _loaded = true;
    _notify();
  }

  /// The storage card's own way back: only the stats, never the whole screen.
  Future<void> retryStorage() => _loadStorage();

  // MARK: pure transitions

  /// The greeting by the clock of the device: the phone is where the person
  /// is, so its hour is the hour that greets them.
  static String greeting(int hour, {String? name}) {
    final String dayPart;
    if (hour >= 5 && hour <= 11) {
      dayPart = 'Bom dia';
    } else if (hour >= 12 && hour <= 17) {
      dayPart = 'Boa tarde';
    } else {
      dayPart = 'Boa noite';
    }
    final String first = firstName(name ?? '');
    return first.isEmpty ? '$dayPart,' : '$dayPart, $first';
  }

  static String firstName(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
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

  static String memberCountLabel(int count) =>
      '$count ${count == 1 ? 'pessoa' : 'pessoas'} na comunidade';

  static String muralMeta(HomeMuralLine line) {
    final String sentence = line.sentence.trim().replaceFirst(
      RegExp(r'\.$'),
      '',
    );
    return '$sentence, ${line.ago}';
  }

  static String? careLine({
    required int? count,
    required String? firstRequester,
  }) {
    if (count == null || count == 0) return null;
    if (count == 1) {
      final String requester = firstName(firstRequester ?? '');
      if (requester.isEmpty) {
        return 'Uma pessoa pediu para abrir um arquivo da sua casa';
      }
      return '$requester pediu para abrir um arquivo da sua casa';
    }
    return '$count pessoas pediram para abrir arquivos da sua casa';
  }

  /// Mirrors `TainaWeb.Saude.summary_line/1` until the box supplies BE-4's
  /// ready-to-show `summary.line`.
  static String saudeSummaryLine(Saude saude) {
    final SaudeSummary? summary = saude.summary;
    if (summary != null) return summary.line;
    final StorageStats stats = saude.storage;
    final int? quota = stats.quotaBytes;
    if (quota != null && quota > 0 && stats.usedBytes / quota >= 0.9) {
      return 'Disco quase cheio';
    }
    if (saude.backup.at == null) return 'Nenhum backup ainda';
    return 'Backup em dia';
  }

  static int activeCount(List<Ava> avas) => avas
      .where((Ava ava) => ava.activatedAt != null && ava.deactivatedAt == null)
      .length;

  static StorageSummary storageSummary(StorageStats stats) {
    final int? quota = stats.quotaBytes;
    final bool quotaAvailable = quota != null && quota > 0;
    final int percent = storagePercent(stats);
    final String caption = quotaAvailable
        ? '${TainaFormat.bytes(stats.usedBytes)} de '
              '${TainaFormat.bytes(quota)} usados'
        : '${TainaFormat.bytes(stats.usedBytes)} em uso';
    return StorageSummary(
      usedLabel: caption,
      caption: caption,
      progress: percent / 100,
      freeLabel: quotaAvailable ? freeLabel(stats) : null,
    );
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
        _recent = value.items.take(4).toList(growable: false);
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
        _statsError = null;
      case Err(:final error):
        _stats = null;
        _statsError = error;
    }
    _notify();
  }

  Future<void> _loadCommunity() async {
    Future<TainaResult<Page<Ava>>> loadMembers() async =>
        _gateway.screen(await _gateway.api.members());
    Future<TainaResult<Page<MuralEntry>>> loadMural() async =>
        _gateway.screen(await _gateway.api.mural(limit: 1, cursor: null));
    final List<Object> results = await Future.wait<Object>([
      loadMembers(),
      loadMural(),
    ]);
    if (_disposed) return;
    final TainaResult<Page<Ava>> members =
        results.first as TainaResult<Page<Ava>>;
    final TainaResult<Page<MuralEntry>> mural =
        results.last as TainaResult<Page<MuralEntry>>;
    Map<String, String> names = _gateway.identity == null
        ? const {}
        : actorNames([_gateway.identity!.ava]);
    switch (members) {
      case Ok(:final value):
        _activeMembers = activeCount(value.items);
        _membersError = null;
        names = actorNames(value.items);
      case Err(:final error):
        _activeMembers = null;
        _membersError = error;
    }
    switch (mural) {
      case Ok(:final value):
        _mural = lines(value.items, names).take(1).toList(growable: false);
        _muralError = null;
      case Err(:final error):
        _mural = const [];
        _muralError = error;
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
        final List<Pedido> pending = value.items
            .where((Pedido pedido) => pedido.status == PedidoStatus.pendente)
            .toList(growable: false);
        _firstPendingName = pending.isEmpty
            ? null
            : pending.first.pedinte?.label;
        _requestsError = null;
      case Err(:final error):
        _pendingRequests = null;
        _firstPendingName = null;
        _requestsError = error;
    }
    _notify();
  }

  Future<void> _loadHealth() async {
    final TainaResult<Saude> result = await _gateway.screen(
      await _gateway.api.saude(),
    );
    if (_disposed) return;
    switch (result) {
      case Ok(:final value):
        _healthSummary = saudeSummaryLine(value);
        _healthError = null;
      case Err(:final error):
        _healthSummary = null;
        _healthError = error;
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
