import 'package:flutter/foundation.dart';
import 'package:okena_app/src/features/mural/mural_phrase.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The mural's state: the community's ledger, newest first, read-only for
/// every papel, one page at a time.
///
/// The screen's sentences come from the feature's [MuralPhrase] table.
final class MuralModel extends ChangeNotifier {
  MuralModel({required this.gateway});

  final SessionGateway gateway;

  List<MuralEntry> _entries = const [];
  Map<String, String> _names = const {};
  List<String> _caretakers = const [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreError = false;
  TainaError? _error;
  bool _disposed = false;

  List<MuralEntry> get entries => _entries;

  /// `public_id` -> social label, so the chain's actor ids read as people.
  Map<String, String> get names => _names;
  List<String> get caretakers => _caretakers;
  String? get nextCursor => _nextCursor;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get moreError => _moreError;
  TainaError? get error => _error;

  Future<void> load() async {
    _loading = true;
    _notify();
    await _loadNames();
    final result = await gateway.screen(await gateway.api.mural());
    _apply(result);
    _loading = false;
    _notify();
  }

  Future<void> loadMore() async {
    final String? cursor = _nextCursor;
    if (_loading || _loadingMore || cursor == null) return;
    _loadingMore = true;
    _notify();
    final result = await gateway.screen(
      await gateway.api.mural(cursor: cursor),
    );
    _applyMore(result);
    _loadingMore = false;
    _notify();
  }

  /// The sentence for one entry, from the shared table and the roster.
  String sentenceFor(MuralEntry entry) => MuralPhrase.sentence(entry, _names);

  /// Sequence is the chain's chronological order; the board displays newest
  /// entries first, including when a page arrives out of order.
  static List<MuralEntry> chronological(List<MuralEntry> entries) {
    final List<MuralEntry> ordered = [...entries]
      ..sort(
        (MuralEntry left, MuralEntry right) => right.seq.compareTo(left.seq),
      );
    return List<MuralEntry>.unmodifiable(ordered);
  }

  /// Board time: "Hoje, 09:12", "Ontem, 18:02", then a short date.
  static String timeLabel(String iso, {DateTime? now}) {
    final DateTime? parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final DateTime local = parsed.toLocal();
    final DateTime today = now ?? DateTime.now();
    final int days = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(local.year, local.month, local.day)).inDays;
    final String clock =
        '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
    return switch (days) {
      0 => 'Hoje, $clock',
      1 => 'Ontem, $clock',
      2 => 'Antes de ontem, $clock',
      _ => '${_shortDate(local)}, $clock',
    };
  }

  /// The roster that turns the chain's actor ids into names. Best effort: a
  /// mural that cannot resolve names still shows its sentences with "O
  /// sistema" speaking.
  Future<void> _loadNames() async {
    final result = await gateway.screen(await gateway.api.members());
    if (result case Ok(:final value)) {
      _names = MuralPhrase.actorNames(value.items);
      _caretakers = List<String>.unmodifiable([
        for (final Ava ava in value.items)
          if (ava.papel == Papel.zelador &&
              ava.activatedAt != null &&
              ava.deactivatedAt == null)
            ava.label,
      ]);
    }
  }

  static String _shortDate(DateTime date) {
    const List<String> months = [
      'jan.',
      'fev.',
      'mar.',
      'abr.',
      'mai.',
      'jun.',
      'jul.',
      'ago.',
      'set.',
      'out.',
      'nov.',
      'dez.',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  void _apply(TainaResult<Page<MuralEntry>> result) {
    switch (result) {
      case Ok(:final value):
        _entries = chronological(value.items);
        _nextCursor = value.nextCursor;
        _moreError = false;
        _error = null;
      case Err(:final error):
        _error = error;
    }
  }

  void _applyMore(TainaResult<Page<MuralEntry>> result) {
    switch (result) {
      case Ok(:final value):
        _entries = chronological([..._entries, ...value.items]);
        _nextCursor = value.nextCursor;
        _moreError = false;
      case Err():
        // A page that fails leaves the list as it is and the cursor alive:
        // the sentinel offers the retry.
        _moreError = true;
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
