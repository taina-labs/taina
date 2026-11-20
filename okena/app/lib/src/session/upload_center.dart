import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../design_system/format.dart';
import 'session_gateway.dart';

/// A file selected for upload, independent of any picker implementation.
@immutable
final class UploadRequest {
  const UploadRequest({
    required this.path,
    required this.name,
    required this.mime,
    this.folderRkey,
    this.folderName,
  });

  final String path;
  final String name;
  final String mime;
  final String? folderRkey;
  final String? folderName;

  @override
  bool operator ==(Object other) =>
      other is UploadRequest &&
      other.path == path &&
      other.name == name &&
      other.mime == mime &&
      other.folderRkey == folderRkey &&
      other.folderName == folderName;

  @override
  int get hashCode => Object.hash(path, name, mime, folderRkey, folderName);
}

/// The visible state of the session's one-at-a-time upload.
sealed class UploadState {
  const UploadState();

  bool get canRetry => false;
  double? get progressFraction => null;
  String? get progressTitle => null;
  String? get progressDetail => null;
  String? get progressHelp => null;
}

final class UploadIdle extends UploadState {
  const UploadIdle();
}

final class UploadUploading extends UploadState {
  const UploadUploading({
    required this.request,
    required this.sentBytes,
    required this.totalBytes,
  });

  final UploadRequest request;
  final int sentBytes;
  final int totalBytes;

  @override
  double get progressFraction {
    if (totalBytes <= 0) return 0;
    return (sentBytes / totalBytes).clamp(0.0, 1.0).toDouble();
  }

  @override
  String get progressTitle => 'Enviando ${request.name}';

  @override
  String get progressDetail =>
      'Guardando na casa. ${TainaFormat.bytes(sentBytes)} de '
      '${TainaFormat.bytes(totalBytes)}';

  @override
  String get progressHelp => 'Você pode continuar usando o app enquanto envia.';
}

final class UploadSucceeded extends UploadState {
  const UploadSucceeded({required this.request, required this.file});

  final UploadRequest request;
  final FileRecord file;
}

final class UploadFailed extends UploadState {
  const UploadFailed({required this.request, required this.error});

  final UploadRequest request;
  final TainaError error;

  @override
  bool get canRetry => true;
}

/// Why a requested upload did not start.
enum UploadRejection { busy, noRetryableFailure }

/// Completion or typed rejection of [UploadCenter.start] and [UploadCenter.retry].
sealed class UploadStartResult {
  const UploadStartResult();
}

final class UploadFinished extends UploadStartResult {
  const UploadFinished(this.result);

  final TainaResult<FileRecord> result;
}

final class UploadRejected extends UploadStartResult {
  const UploadRejected(this.reason);

  final UploadRejection reason;
}

/// Session-owned upload state, so leaving an upload screen does not cancel work.
final class UploadCenter extends ChangeNotifier {
  // Keep the dependency private while preserving a named construction API.
  // ignore: prefer_initializing_formals
  UploadCenter({required SessionGateway gateway}) : _gateway = gateway;

  final SessionGateway _gateway;
  UploadState _state = const UploadIdle();
  int _nextRunId = 0;
  int? _activeRunId;
  bool _disposed = false;

  UploadState get state => _state;

  bool get isUploading => _activeRunId != null;

  bool get canRetry => _state.canRetry;

  double? get progressFraction => _state.progressFraction;

  /// Starts an upload or returns a typed rejection if another upload is active.
  ///
  /// The screened result is returned as well as stored in [state], which lets
  /// callers handle completion without bypassing session-level 401/403 rules.
  Future<UploadStartResult> start(UploadRequest request) async {
    if (_activeRunId != null) {
      return const UploadRejected(UploadRejection.busy);
    }

    final runId = ++_nextRunId;
    _activeRunId = runId;
    _setState(UploadUploading(request: request, sentBytes: 0, totalBytes: 0));

    final outcome = await _gateway.api.upload(
      filePath: request.path,
      name: request.name,
      mime: request.mime,
      folderRkey: request.folderRkey,
      progress: (sentBytes, totalBytes) {
        _reportProgress(runId, request, sentBytes, totalBytes);
      },
    );
    final screened = await _gateway.screen(outcome);

    if (_activeRunId == runId) {
      _activeRunId = null;
      _setState(switch (screened) {
        Ok<FileRecord>(:final value) => UploadSucceeded(
          request: request,
          file: value,
        ),
        Err<FileRecord>(:final error) => UploadFailed(
          request: request,
          error: error,
        ),
      });
    }

    return UploadFinished(screened);
  }

  /// Retries the last failed request, or returns a typed rejection otherwise.
  Future<UploadStartResult> retry() {
    if (_activeRunId != null) {
      return Future.value(const UploadRejected(UploadRejection.busy));
    }

    final current = _state;
    if (current is! UploadFailed) {
      return Future.value(
        const UploadRejected(UploadRejection.noRetryableFailure),
      );
    }
    return start(current.request);
  }

  /// Clears a completed state. An active transfer stays visible and continues.
  void clear() {
    if (_activeRunId != null || _state is UploadIdle) return;
    _setState(const UploadIdle());
  }

  void _reportProgress(
    int runId,
    UploadRequest request,
    int sentBytes,
    int totalBytes,
  ) {
    if (_activeRunId != runId) return;
    _setState(
      UploadUploading(
        request: request,
        sentBytes: sentBytes,
        totalBytes: totalBytes,
      ),
    );
  }

  void _setState(UploadState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
