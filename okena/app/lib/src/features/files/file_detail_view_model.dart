import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_gateway.dart';
import 'file_actions.dart';
import 'files_logic.dart';

/// The file screen's state: the download/preview/share sequence, the owner's
/// acts, and the casa-of-another-person turn into an access request.
///
/// A 403 on the content is not a dead end: the model asks the box who owns
/// the file, the screen becomes the request, and the person decides.
final class FileDetailViewModel extends ChangeNotifier {
  factory FileDetailViewModel({
    required SessionGateway session,
    required FileActions actions,
    required FileRecord file,
  }) {
    return FileDetailViewModel._(file, session, actions);
  }

  FileDetailViewModel._(this._file, this.session, this.actions);

  final SessionGateway session;
  final FileActions actions;

  FileRecord _file;
  String? _downloadedPath;
  bool _working = false;
  bool _resolving = false;
  TainaError? _failure;
  String? _actionFailure;
  AccessTarget? _denied;
  bool _requested = false;

  FileRecord get file => _file;
  String? get downloadedPath => _downloadedPath;
  bool get working => _working;
  bool get resolving => _resolving;
  TainaError? get failure => _failure;
  AccessTarget? get denied => _denied;
  bool get requested => _requested;

  /// The sentence the alert shows. API errors keep their own pt-BR message;
  /// the local share/viewer failures carry theirs.
  String? get errorMessage => _actionFailure ?? _failure?.message;

  /// Downloads the file to disk. Returns true when the file is here (or the
  /// screen turned into the access request, where there is nothing else to
  /// do), false when the alert must show [errorMessage].
  Future<bool> download() async {
    if (_working) return false;
    _working = true;
    _failure = null;
    _actionFailure = null;
    notifyListeners();
    final result = await session.screen(
      await session.api.download(rkey: _file.rkey),
    );
    switch (result) {
      case Ok(:final value):
        _downloadedPath = value;
        _denied = null;
      case Err(:final error):
        await _onDownloadFailure(error);
    }
    _working = false;
    notifyListeners();
    return _denied != null || _downloadedPath != null;
  }

  /// Shares the file that is already here. Download happens first, so the
  /// sheet always has a real path.
  Future<bool> share() async {
    if (_downloadedPath == null) {
      final ready = await download();
      if (!ready) return false;
    }
    final path = _downloadedPath;
    if (path == null) return false;
    final failure = await actions.share(path, subject: _file.name);
    if (failure == null) return true;
    _actionFailure = failure;
    notifyListeners();
    return false;
  }

  /// Opens the platform viewer on the same downloaded file, downloading when
  /// it is not here yet.
  Future<bool> preview() async {
    if (_downloadedPath == null) {
      final ready = await download();
      if (!ready) return false;
    }
    final path = _downloadedPath;
    if (path == null) return false;
    final failure = await actions.open(path);
    if (failure == null) return true;
    _actionFailure = failure;
    notifyListeners();
    return false;
  }

  Future<bool> rename(String name) async {
    return _runFileUpdate(
      () => session.api.updateFile(rkey: _file.rkey, name: name),
    );
  }

  Future<bool> move(Folder? folder) async {
    return _runFileUpdate(
      () => session.api.moveFile(rkey: _file.rkey, folderRkey: folder?.rkey),
    );
  }

  /// The action always offers the opposite of where the file is now.
  Future<bool> changeZona() async {
    final target = _file.zona == Zona.casa ? Zona.praca : Zona.casa;
    return _runFileUpdate(
      () => session.api.updateFile(rkey: _file.rkey, zona: target),
    );
  }

  Future<bool> delete() async {
    if (_working) return false;
    _working = true;
    _failure = null;
    notifyListeners();
    final result = await session.screen(
      await session.api.deleteFile(rkey: _file.rkey),
    );
    _working = false;
    final deleted = result.isSuccess;
    if (!deleted) _failure = result.error;
    notifyListeners();
    return deleted;
  }

  /// The pedido registers the question; it grants nothing.
  Future<bool> requestAccess() async {
    final target = _denied;
    if (target == null) return false;
    if (_working) return false;
    _working = true;
    _failure = null;
    notifyListeners();
    final result = await session.screen(
      await session.api.requestAccess(
        fileRkey: target.rkey,
        motivo: FilesLogic.accessMotivo,
      ),
    );
    _working = false;
    final sent = result.isSuccess;
    if (sent) {
      _requested = true;
    } else {
      _failure = result.error;
    }
    notifyListeners();
    return sent;
  }

  void dismissError() {
    _failure = null;
    _actionFailure = null;
    notifyListeners();
  }

  Future<void> _onDownloadFailure(TainaError error) async {
    if (error is! ApiError || !error.isForbidden) {
      _failure = error;
      return;
    }
    _resolving = true;
    notifyListeners();
    final target = await session.screen(
      await session.api.accessTarget(fileRkey: _file.rkey),
    );
    switch (target) {
      case Ok(:final value):
        _denied = value;
      case Err(:final error):
        _failure = error;
    }
    _resolving = false;
  }

  Future<bool> _runFileUpdate(
    Future<TainaResult<FileRecord>> Function() call,
  ) async {
    if (_working) return false;
    _working = true;
    _failure = null;
    _actionFailure = null;
    notifyListeners();
    final result = await session.screen(await call());
    _working = false;
    final updated = result.value;
    final success = updated != null;
    if (updated != null) {
      _file = updated;
    } else {
      _failure = result.error;
    }
    notifyListeners();
    return success;
  }
}
