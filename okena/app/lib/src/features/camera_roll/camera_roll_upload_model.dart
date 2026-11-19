import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_gateway.dart';
import '../files/file_actions.dart';
import '../files/files_logic.dart';
import '../files/upload_runner.dart';
import 'media_picker.dart';

enum CameraRollUploadPhase {
  idle,
  picking,
  uploading,
  complete,
  failed,
  stopped,
}

enum _UploadStatus { pending, uploading, succeeded, failed }

final class _UploadItem {
  const _UploadItem({
    required this.file,
    this.status = _UploadStatus.pending,
    this.attempted = false,
  });

  final PickedFile file;
  final _UploadStatus status;
  final bool attempted;

  _UploadItem copyWith({_UploadStatus? status, bool? attempted}) {
    return _UploadItem(
      file: file,
      status: status ?? this.status,
      attempted: attempted ?? this.attempted,
    );
  }
}

/// Sequentially uploads manually selected media into the root of the casa.
/// Picker and network work stay at the edge; this model owns the queue state.
final class CameraRollUploadModel extends ChangeNotifier {
  CameraRollUploadModel({required this.picker, required SessionGateway session})
    : _uploadRunner = UploadRunner(session: session);

  final MediaPicker picker;
  final UploadRunner _uploadRunner;
  final List<_UploadItem> _items = [];

  CameraRollUploadPhase _phase = CameraRollUploadPhase.idle;
  bool _busy = false;
  bool _stopRequested = false;
  bool _interrupted = false;
  String? _currentFileName;
  String? _lastMessage;

  CameraRollUploadPhase get phase => _phase;
  int get total => _items.length;
  int get attempted => _items.where((item) => item.attempted).length;
  int get succeeded =>
      _items.where((item) => item.status == _UploadStatus.succeeded).length;
  int get failedCount =>
      _items.where((item) => item.status == _UploadStatus.failed).length;
  int get unstarted =>
      _items.where((item) => item.status == _UploadStatus.pending).length;
  String? get currentFileName => _currentFileName;
  bool get stopRequested => _stopRequested;
  bool get interrupted => _interrupted;
  String? get lastMessage => _lastMessage;
  bool get anySuccess => succeeded > 0;
  bool get busy => _busy;
  bool get uploading => _currentFileName != null;

  bool get canRetry {
    return !_busy &&
        (phase == CameraRollUploadPhase.failed ||
            phase == CameraRollUploadPhase.stopped) &&
        _items.any((item) => item.status != _UploadStatus.succeeded);
  }

  Future<void> pickPhotos() => _pick(picker.pickPhotos);

  Future<void> takePhoto() => _pick(picker.takePhoto);

  Future<void> recoverLostData() => _pick(picker.recoverLostData);

  Future<void> _pick(Future<MediaPickerOutcome> Function() operation) async {
    if (_busy) return;
    _busy = true;
    _phase = CameraRollUploadPhase.picking;
    _stopRequested = false;
    _interrupted = false;
    _currentFileName = null;
    _lastMessage = null;
    _items.clear();
    notifyListeners();

    try {
      final outcome = await operation();
      switch (outcome) {
        case MediaPickerSelected(:final files):
          if (files.isEmpty) {
            _phase = CameraRollUploadPhase.idle;
            _stopRequested = false;
            _interrupted = false;
            _lastMessage = null;
            return;
          }
          _items.addAll(files.map((file) => _UploadItem(file: file)));
          _phase = CameraRollUploadPhase.uploading;
          notifyListeners();
          await _uploadPending();
        case MediaPickerCancelled():
          _phase = CameraRollUploadPhase.idle;
          _stopRequested = false;
          _interrupted = false;
          _lastMessage = null;
        case MediaPickerFailed(:final message):
          _phase = CameraRollUploadPhase.failed;
          _lastMessage = message;
      }
    } on Exception {
      _phase = CameraRollUploadPhase.failed;
      _lastMessage = 'Não foi possível abrir as fotos e vídeos. Tente de novo.';
    } finally {
      if (_busy) {
        _busy = false;
        if (_phase == CameraRollUploadPhase.picking) {
          _phase = CameraRollUploadPhase.idle;
        }
        notifyListeners();
      }
    }
  }

  Future<void> retryRemaining() async {
    if (!canRetry) return;
    _busy = true;
    _stopRequested = false;
    _interrupted = false;
    _lastMessage = null;
    await _uploadPending();
  }

  /// Lets the current upload finish, then prevents every later file from
  /// starting.
  void stopNext() {
    if (!uploading || _stopRequested) return;
    _stopRequested = true;
    notifyListeners();
  }

  /// Called when the app moves to the background. It marks the run retryable
  /// immediately, while allowing a pending picker or in-flight request to
  /// settle.
  void interrupt() {
    if (!_busy || _interrupted) return;
    _stopRequested = true;
    _interrupted = true;
    _phase = CameraRollUploadPhase.stopped;
    _lastMessage =
        'O envio foi pausado ao sair do app. '
        'Tente os que faltam quando voltar.';
    notifyListeners();
  }

  Future<void> _uploadPending() async {
    _phase = CameraRollUploadPhase.uploading;
    notifyListeners();
    try {
      for (var index = 0; index < _items.length; index += 1) {
        if (_stopRequested || _interrupted) break;
        final item = _items[index];
        if (item.status == _UploadStatus.succeeded) continue;

        _items[index] = item.copyWith(
          status: _UploadStatus.uploading,
          attempted: true,
        );
        _currentFileName = item.file.name;
        notifyListeners();

        final TainaResult<FileRecord> result;
        try {
          result = await _uploadRunner.upload(item.file, folderRkey: null);
        } on Exception {
          _items[index] = _items[index].copyWith(status: _UploadStatus.failed);
          _lastMessage =
              'Não foi possível enviar ${item.file.name}. Tente de novo.';
          _currentFileName = null;
          notifyListeners();
          continue;
        }

        switch (result) {
          case Ok<FileRecord>():
            _items[index] = _items[index].copyWith(
              status: _UploadStatus.succeeded,
            );
          case Err<FileRecord>(:final error):
            _items[index] = _items[index].copyWith(
              status: _UploadStatus.failed,
            );
            _lastMessage = FilesLogic.uploadMessage(error);
        }
        _currentFileName = null;
        notifyListeners();
      }
    } finally {
      _currentFileName = null;
      _busy = false;
      if (_interrupted || (_stopRequested && _hasPending)) {
        _phase = CameraRollUploadPhase.stopped;
      } else if (failedCount > 0) {
        _phase = CameraRollUploadPhase.failed;
      } else {
        _phase = CameraRollUploadPhase.complete;
      }
      notifyListeners();
    }
  }

  bool get _hasPending => _items.any(
    (item) =>
        item.status == _UploadStatus.pending ||
        item.status == _UploadStatus.failed,
  );
}
