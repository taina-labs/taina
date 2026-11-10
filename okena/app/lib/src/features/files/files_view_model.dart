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
    this.pageSize,
  });

  final SessionGateway session;
  final FileActions actions;
  final String? folderRkey;

  /// The page size the box is asked for. Null means the server's default,
  /// exactly like the Swift app; tests pass a small one to walk pages.
  final int? pageSize;

  FilesEntries _entries = const FilesEntries();
  bool _loading = false;
  bool _uploading = false;
  TainaError? _error;
  String? _nextCursor;
  bool _loadingMore = false;
  bool _moreError = false;
  String? _publishingRkey;
  final Set<String> _uploadedRkeys = {};

  FilesEntries get entries => _entries;
  bool get loading => _loading;
  bool get uploading => _uploading;
  TainaError? get error => _error;
  String? get nextCursor => _nextCursor;
  bool get loadingMore => _loadingMore;
  bool get moreError => _moreError;

  /// The file a row's publish action is running on, so only that row spins.
  String? get publishingRkey => _publishingRkey;

  /// The files this model uploaded, so the rows still in the casa carry the
  /// one-tap publish to the praca.
  Set<String> get uploadedRkeys => Set.unmodifiable(_uploadedRkeys);

  bool get isEmpty => _entries.isEmpty;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final result = await session.screen(
      await session.api.folderContents(folderRkey: folderRkey, limit: pageSize),
    );
    _apply(result);
    _loading = false;
    notifyListeners();
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
      ),
    );
    _applyMore(result);
    _loadingMore = false;
    notifyListeners();
  }

  /// Creates the folder and puts it at the end of the list, where the
  /// server's own order would put it on the next refresh.
  Future<TainaResult<void>> createFolder(String name) async {
    final result = await session.screen(
      await session.api.createFolder(name: name, parentRkey: folderRkey),
    );
    switch (result) {
      case Ok(:final value):
        _entries = FilesLogic.insertingFolder(_entries, value);
        notifyListeners();
        return const Ok<void>(null);
      case Err(:final error):
        return Err(error);
    }
  }

  /// Picks one file and uploads it. Returns the pt-BR message to show on
  /// failure, null when the upload completed or the person cancelled.
  Future<String?> pickAndUpload() async {
    final outcome = await actions.pick();
    switch (outcome) {
      case PickedFileCancelled():
        return null;
      case PickedFileFailed(:final message):
        return message;
      case PickedFileSelected(:final file):
        final result = await upload(file);
        return result.error == null
            ? null
            : FilesLogic.uploadMessage(result.error!);
    }
  }

  /// Uploads a picked file and puts the completed row in the list, carrying
  /// the one-tap publish to the praca.
  Future<TainaResult<void>> upload(PickedFile picked) async {
    _uploading = true;
    notifyListeners();
    final result = await session.screen(
      await session.api.upload(
        filePath: picked.path,
        name: picked.name,
        mime: picked.mime,
        folderRkey: folderRkey,
      ),
    );
    switch (result) {
      case Ok(:final value):
        _entries = FilesLogic.insertingFile(_entries, value);
        _uploadedRkeys.add(value.rkey);
        _uploading = false;
        notifyListeners();
        return const Ok<void>(null);
      case Err(:final error):
        _uploading = false;
        notifyListeners();
        return Err(error);
    }
  }

  /// The completed row's one tap to the praca: the consent the upload screen
  /// owes, at the moment of the intention. The success swaps the row in
  /// place and ends the reminder.
  Future<TainaResult<void>> publish(FileRecord file) async {
    if (_publishingRkey != null) return const Ok<void>(null);
    _publishingRkey = file.rkey;
    notifyListeners();
    final result = await session.screen(
      await session.api.updateFile(rkey: file.rkey, zona: Zona.praca),
    );
    switch (result) {
      case Ok(:final value):
        _entries = FilesLogic.replacingFile(_entries, value);
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
        _entries = FilesLogic.entriesFrom(value);
        _nextCursor = value.nextCursor;
        _moreError = false;
        _error = null;
      case Err(:final error):
        _error = error;
    }
  }

  void _applyMore(TainaResult<FolderContents> result) {
    switch (result) {
      case Ok(:final value):
        _entries = FilesLogic.appending(_entries, value);
        _nextCursor = value.nextCursor;
        _moreError = false;
      case Err():
        // A page that fails leaves the list as it is and the cursor alive:
        // the sentinel offers the retry.
        _moreError = true;
    }
  }
}
