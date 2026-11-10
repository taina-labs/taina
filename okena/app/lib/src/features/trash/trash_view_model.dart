import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_gateway.dart';

/// The lixeira's state: what the community discarded, one page at a time,
/// with restore. The loading logic lives here once; the trash rules are pure
/// functions of [TrashLogic].
final class TrashViewModel extends ChangeNotifier {
  TrashViewModel({required this.session, this.pageSize});

  final SessionGateway session;

  /// The page size the box is asked for. Null means the server's default,
  /// exactly like the Swift app; tests pass a small one to walk pages.
  final int? pageSize;

  List<FileRecord> _items = const [];
  String? _nextCursor;
  bool _loading = false;
  bool _loadingMore = false;
  bool _moreError = false;
  TainaError? _error;
  String? _restoringRkey;

  List<FileRecord> get items => _items;
  String? get nextCursor => _nextCursor;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get moreError => _moreError;
  TainaError? get error => _error;

  /// The row being restored, so only its button spins.
  String? get restoringRkey => _restoringRkey;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final result = await session.screen(
      await session.api.trash(limit: pageSize),
    );
    _apply(result);
    _loading = false;
    notifyListeners();
  }

  /// The next page, walking the cursor the last answer carried. A page that
  /// fails leaves the list as it is and the cursor alive, so the sentinel
  /// offers the retry.
  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (_loading || _loadingMore || cursor == null) return;
    _loadingMore = true;
    notifyListeners();
    final result = await session.screen(
      await session.api.trash(limit: pageSize, cursor: cursor),
    );
    _applyMore(result);
    _loadingMore = false;
    notifyListeners();
  }

  /// Restores one file and drops the row on success; the failure goes back
  /// for the alert.
  Future<TainaResult<void>> restore({required String rkey}) async {
    if (_restoringRkey != null) return const Ok<void>(null);
    _restoringRkey = rkey;
    notifyListeners();
    final result = await session.screen(
      await session.api.restoreFile(rkey: rkey),
    );
    switch (result) {
      case Ok():
        _items = _items
            .where((file) => file.rkey != rkey)
            .toList(growable: false);
        _restoringRkey = null;
        notifyListeners();
        return const Ok<void>(null);
      case Err(:final error):
        _restoringRkey = null;
        notifyListeners();
        return Err(error);
    }
  }

  void _apply(TainaResult<Page<FileRecord>> result) {
    switch (result) {
      case Ok(:final value):
        _items = value.items;
        _nextCursor = value.nextCursor;
        _moreError = false;
        _error = null;
      case Err(:final error):
        _error = error;
    }
  }

  void _applyMore(TainaResult<Page<FileRecord>> result) {
    switch (result) {
      case Ok(:final value):
        _items = [..._items, ...value.items];
        _nextCursor = value.nextCursor;
        _moreError = false;
      case Err():
        _moreError = true;
    }
  }
}
