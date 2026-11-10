import 'package:flutter/foundation.dart';
import 'package:okena_app/src/features/mural/mural_phrase.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The mural's state: the community's ledger, newest first, read-only for
/// every papel, one page at a time.
///
/// The sentences come from the one shared table ([MuralPhrase]), so the screen
/// and the Home teaser never drift.
final class MuralModel extends ChangeNotifier {
  MuralModel({required this.gateway});

  final SessionGateway gateway;

  List<MuralEntry> _entries = const [];
  Map<String, String> _names = const {};
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreError = false;
  TainaError? _error;
  bool _disposed = false;

  List<MuralEntry> get entries => _entries;

  /// `public_id` -> social label, so the chain's actor ids read as people.
  Map<String, String> get names => _names;
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

  /// The roster that turns the chain's actor ids into names. Best effort: a
  /// mural that cannot resolve names still shows its sentences with "O
  /// sistema" speaking.
  Future<void> _loadNames() async {
    final result = await gateway.screen(await gateway.api.members());
    if (result case Ok(:final value)) {
      _names = MuralPhrase.actorNames(value.items);
    }
  }

  void _apply(TainaResult<Page<MuralEntry>> result) {
    switch (result) {
      case Ok(:final value):
        _entries = value.items;
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
        _entries = [..._entries, ...value.items];
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
