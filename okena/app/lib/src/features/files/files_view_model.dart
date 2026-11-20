import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_gateway.dart';
import 'file_actions.dart';
import 'files_logic.dart';

/// The browser's state, for the root and for any folder alike. The loading
/// logic lives here once; the transitions are pure functions of
/// [FilesLogic] the views never reimplement.
final class FilesViewModel extends ChangeNotifier {
  FilesViewModel({
    required this.session,
    required this.actions,
    this.folderRkey,
    this.zona,
    this.pageSize,
  });

  final SessionGateway session;
  final FileActions actions;
  final String? folderRkey;
  final Zona? zona;

  /// The page size the box is asked for. Null means the server's default,
  /// exactly like the Swift app; tests pass a small one to walk pages.
  final int? pageSize;
  FilesEntries _entries = const FilesEntries();
  bool _loading = false;
  TainaError? _error;
  String? _nextCursor;
  bool _loadingMore = false;
  bool _moreError = false;
  bool _lastFilteredPageEmpty = false;
  bool _disposed = false;
  bool _ownerNamesLoaded = false;
  bool _loadingOwnerNames = false;
  Map<String, String> _ownerNames = const {};
  String? _publishingRkey;
  final Set<String> _uploadedRkeys = {};
  final Set<String> _createdFolderRkeys = {};

  FilesEntries get entries => _entries;
  bool get loading => _loading;
  TainaError? get error => _error;
  String? get nextCursor => _nextCursor;
  bool get loadingMore => _loadingMore;
  bool get moreError => _moreError;
  bool get lastFilteredPageEmpty => _lastFilteredPageEmpty;
  Map<String, String> get ownerNames => Map.unmodifiable(_ownerNames);

  /// The file a row's publish action is running on, so only that row spins.
  String? get publishingRkey => _publishingRkey;

  /// The files this model uploaded, so the rows still in the casa carry the
  /// one-tap publish to the praca.
  Set<String> get uploadedRkeys => Set.unmodifiable(_uploadedRkeys);
  Set<String> get createdFolderRkeys => Set.unmodifiable(_createdFolderRkeys);

  bool get isEmpty => _entries.isEmpty;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final result = await session.screen(
      await session.api.folderContents(
        folderRkey: folderRkey,
        limit: pageSize,
        zona: zona,
      ),
    );
    _apply(result);
    _loading = false;
    notifyListeners();
    if (_error == null &&
        !_moreError &&
        zona != null &&
        FilesLogic.needsAnotherPage(
          filteredPageEmpty: _lastFilteredPageEmpty,
          cursor: _nextCursor,
        )) {
      unawaited(loadMore());
    }
  }

  /// The next page of files, walking the cursor the last answer carried. A
  /// page that fails leaves the list and the cursor as they are, so the
  /// sentinel offers the retry.
  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (_loading || _loadingMore || cursor == null) return;
    _loadingMore = true;
    notifyListeners();
    final result = await session.screen(
      await session.api.folderContents(
        folderRkey: folderRkey,
        limit: pageSize,
        cursor: cursor,
        zona: zona,
      ),
    );
    _applyMore(result);
    _loadingMore = false;
    notifyListeners();
    if (!_moreError &&
        zona != null &&
        FilesLogic.needsAnotherPage(
          filteredPageEmpty: _lastFilteredPageEmpty,
          cursor: _nextCursor,
        )) {
      unawaited(loadMore());
    }
  }

  /// Creates the folder and puts it at the end of the list, where the
  /// server's own order would put it on the next refresh.
  Future<TainaResult<void>> createFolder(String name) async {
    final result = await session.screen(
      await session.api.createFolder(name: name, parentRkey: folderRkey),
    );
    switch (result) {
      case Ok(:final value):
        final Folder created;
        if (zona == Zona.praca && value.zona != Zona.praca) {
          final published = await session.screen(
            await session.api.updateFolder(rkey: value.rkey, zona: Zona.praca),
          );
          if (published case Err(:final error)) return Err(error);
          created = published.value!;
        } else {
          created = value;
        }
        _createdFolderRkeys.add(created.rkey);
        _entries = FilesLogic.insertingFolder(_entries, created);
        notifyListeners();
        return const Ok<void>(null);
      case Err(:final error):
        return Err(error);
    }
  }

  /// Records a successful session-owned upload in any mounted Casa list.
  void recordUpload(FileRecord file) {
    if (file.zona != Zona.casa) return;
    _uploadedRkeys.add(file.rkey);
    if (zona == null || zona == Zona.casa) {
      final alreadyPresent = _entries.files.any(
        (entry) => entry.rkey == file.rkey,
      );
      if (!alreadyPresent) _entries = FilesLogic.insertingFile(_entries, file);
    }
    notifyListeners();
  }

  /// The completed row's one tap to the praca: the consent the upload screen
  /// owes, at the moment of the intention. The success swaps the row in
  /// place and ends the reminder.
  Future<TainaResult<void>> publish(FileRecord file) async {
    return setZona(file, Zona.praca);
  }

  Future<TainaResult<void>> setZona(FileRecord file, Zona zona) async {
    if (_publishingRkey != null) return const Ok<void>(null);
    _publishingRkey = file.rkey;
    notifyListeners();
    final result = await session.screen(
      await session.api.updateFile(rkey: file.rkey, zona: zona),
    );
    switch (result) {
      case Ok(:final value):
        _entries = this.zona == null || value.zona == this.zona
            ? FilesLogic.replacingFile(_entries, value)
            : FilesLogic.removingFile(_entries, file.rkey);
        _uploadedRkeys.remove(file.rkey);
        _publishingRkey = null;
        notifyListeners();
        return const Ok<void>(null);
      case Err(:final error):
        _publishingRkey = null;
        notifyListeners();
        return Err(error);
    }
  }

  bool showsPublishAction(FileRecord file) {
    return FilesLogic.showsPublishAction(file, _uploadedRkeys);
  }

  void _apply(TainaResult<FolderContents> result) {
    switch (result) {
      case Ok(:final value):
        final filtered = FilesLogic.forZona(value, zona);
        _entries = FilesLogic.entriesFrom(filtered);
        _nextCursor = filtered.nextCursor;
        _lastFilteredPageEmpty =
            filtered.folders.isEmpty && filtered.items.isEmpty;
        _moreError = false;
        _error = null;
        if (filtered.items.any((file) => file.dono != null)) {
          unawaited(_loadOwnerNames());
        }
      case Err(:final error):
        _error = error;
    }
  }

  void _applyMore(TainaResult<FolderContents> result) {
    switch (result) {
      case Ok(:final value):
        final filtered = FilesLogic.forZona(value, zona);
        _entries = FilesLogic.appending(_entries, filtered);
        _nextCursor = filtered.nextCursor;
        _lastFilteredPageEmpty =
            filtered.folders.isEmpty && filtered.items.isEmpty;
        _moreError = false;
        if (filtered.items.any((file) => file.dono != null)) {
          unawaited(_loadOwnerNames());
        }
      case Err():
        // A page that fails leaves the list as it is and the cursor alive:
        // the sentinel offers the retry.
        _moreError = true;
    }
  }

  Future<void> _loadOwnerNames() async {
    if (_ownerNamesLoaded || _loadingOwnerNames) return;
    _loadingOwnerNames = true;
    final result = await session.screen(await session.api.members());
    _loadingOwnerNames = false;
    switch (result) {
      case Ok(:final value):
        _ownerNames = FilesLogic.memberNames(value.items);
        _ownerNamesLoaded = true;
        notifyListeners();
      case Err():
        break;
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
