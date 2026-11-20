import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, FileSystemEntity, FileSystemEntityType;

import 'package:background_downloader/background_downloader.dart';
import 'package:okena_app/src/mirror/mirror_paths.dart';
import 'package:okena_app/src/mirror/mirror_transfer.dart';
import 'package:okena_core/okena_core.dart';
import 'package:path_provider/path_provider.dart';

typedef MirrorUploadRequestProvider =
    Future<TainaResult<HttpRequest>> Function();
typedef MirrorSupportDirectoryProvider = Future<Directory> Function();

/// The plugin operations used by [BackgroundMirrorTransfer].
///
/// Keeping this boundary small lets tests use downloader value objects without
/// initializing native plugin channels.
abstract interface class BackgroundDownloaderGateway {
  Stream<TaskUpdate> get updates;

  Future<void> start();

  Future<Task?> taskForId(String taskId);

  Future<TaskRecord?> recordForId(String taskId);

  Future<(BaseDirectory baseDirectory, String directory, String filename)>
  split(String filePath);

  Future<bool> enqueue(UploadTask task);

  Future<bool> cancel(String taskId);
}

final Expando<_DownloaderUpdateHub> _updateHubs = Expando<_DownloaderUpdateHub>(
  'background mirror update hubs',
);

_DownloaderUpdateHub _updateHubFor(BackgroundDownloaderGateway gateway) =>
    _updateHubs[gateway] ??= _DownloaderUpdateHub(gateway.updates);

/// Owns the gateway's sole native update subscription for its lifetime.
final class _DownloaderUpdateHub {
  _DownloaderUpdateHub(Stream<TaskUpdate> source) {
    source.listen(
      _updates.add,
      onError: (Object error, StackTrace stackTrace) {
        _updates.addError(error, stackTrace);
      },
    );
  }

  final StreamController<TaskUpdate> _updates =
      StreamController<TaskUpdate>.broadcast(sync: true);

  Stream<TaskUpdate> get updates => _updates.stream;
}

sealed class MirrorTransferEvent {
  const MirrorTransferEvent();
}

final class MirrorTransferProgress extends MirrorTransferEvent {
  const MirrorTransferProgress({
    required this.assetId,
    required this.taskId,
    required this.value,
  });

  final String assetId;
  final String taskId;
  final double value;
}

final class MirrorTransferCompleted extends MirrorTransferEvent {
  const MirrorTransferCompleted({
    required this.assetId,
    required this.taskId,
    required this.modificationDate,
    required this.file,
  });

  final String assetId;
  final String taskId;
  final DateTime modificationDate;
  final FileRecord file;
}

final class MirrorTransferFailed extends MirrorTransferEvent {
  const MirrorTransferFailed({
    required this.assetId,
    required this.taskId,
    required this.error,
  });

  final String assetId;
  final String taskId;
  final TainaError error;
}

final class MirrorTransferStreamFailed extends MirrorTransferEvent {
  const MirrorTransferStreamFailed({required this.error});

  final TainaError error;
}

/// Schedules mirror uploads and translates downloader updates into core events.
final class BackgroundMirrorTransfer implements MirrorTransfer {
  BackgroundMirrorTransfer({
    required this.ownerId,
    required this.requestProvider,
    BackgroundDownloaderGateway? gateway,
    MirrorSupportDirectoryProvider? supportDirectoryProvider,
    this.requiresWiFi = true,
    this.requiresWiFiProvider,
  }) : _gateway = gateway ?? _FileDownloaderGateway(),
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory {
    _subscription = _updateHubFor(_gateway).updates.listen(
      _handleUpdate,
      onError: (Object error, StackTrace _) {
        if (_disposed) return;
        _events.add(
          MirrorTransferStreamFailed(error: NetworkError(error.toString())),
        );
      },
    );
  }

  static const String mirrorGroup = 'taina-mirror';

  final String ownerId;
  final MirrorUploadRequestProvider requestProvider;
  final bool requiresWiFi;
  final bool Function()? requiresWiFiProvider;
  final BackgroundDownloaderGateway _gateway;
  final MirrorSupportDirectoryProvider _supportDirectoryProvider;
  final StreamController<MirrorTransferEvent> _events =
      StreamController<MirrorTransferEvent>.broadcast(sync: true);
  final Set<String> _emittedFailureTaskIds = {};
  final Set<(String, String, int, String)> _completedTaskIdentities = {};

  late final StreamSubscription<TaskUpdate> _subscription;
  Future<void> _operationTail = Future<void>.value();
  Future<TainaResult<void>>? _startInFlight;
  bool _started = false;
  bool _disposed = false;

  /// Updates are broadcast and are not replayed; attach before [start].
  Stream<MirrorTransferEvent> get events => _events.stream;

  /// Starts the downloader once after its first successful initialization.
  ///
  /// A failed initialization is not cached, so a later call can retry.
  Future<TainaResult<void>> start() {
    if (_disposed) {
      return Future.value(
        const Err(MirrorAssetReadError('mirror transfer is disposed')),
      );
    }
    if (ownerId.trim().isEmpty) {
      return Future.value(
        const Err(MirrorAssetReadError('mirror owner ID is missing')),
      );
    }
    if (_started) return Future.value(const Ok<void>(null));
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;

    final started = _startGateway();
    _startInFlight = started;
    return started;
  }

  Future<TainaResult<void>> _startGateway() async {
    try {
      await _gateway.start();
      _started = true;
      return const Ok<void>(null);
    } on Exception catch (error) {
      return Err(NetworkError(error.toString()));
    } finally {
      _startInFlight = null;
    }
  }

  @override
  Future<TainaResult<void>> ensureStarted({
    required MirrorEntry entry,
    required String folderRkey,
  }) => _serialize(() => _ensureStarted(entry: entry, folderRkey: folderRkey));

  Future<TainaResult<void>> _ensureStarted({
    required MirrorEntry entry,
    required String folderRkey,
  }) async {
    if (_disposed) {
      return _rejected(
        const MirrorAssetReadError('mirror transfer is disposed'),
      );
    }
    if (ownerId.trim().isEmpty) {
      return _rejected(
        const MirrorAssetReadError('mirror owner ID is missing'),
      );
    }

    final taskId = entry.backgroundTaskId;
    if (taskId == null || taskId.trim().isEmpty) {
      return _rejected(const MirrorAssetReadError('mirror task ID is missing'));
    }

    final started = await start();
    if (started case Err<void>(:final error)) return _rejected(error);

    final Task? existing;
    final TaskRecord? record;
    try {
      existing = await _gateway.taskForId(taskId);
      record = await _gateway.recordForId(taskId);
    } on Exception catch (error) {
      return _uncertain(MirrorAssetReadError(error.toString()));
    }
    if (existing != null && !_taskMatchesEntry(existing, entry, taskId)) {
      return _rejected(
        const MirrorAssetReadError(
          'existing background task does not match this mirror entry',
        ),
      );
    }
    if (record != null && !_taskMatchesEntry(record.task, entry, taskId)) {
      return _rejected(
        const MirrorAssetReadError(
          'stored background task does not match this mirror entry',
        ),
      );
    }
    if (record != null && record.status.isFinalState) {
      switch (record.status) {
        case TaskStatus.complete:
          final metadata = _metadataFor(record.task)!;
          final identity = _taskIdentity(record.task, metadata);
          if (!_completedTaskIdentities.contains(identity)) {
            _emitInvalidResponse(
              TaskStatusUpdate(record.task, record.status, record.exception),
              'mirror upload completed response is missing',
            );
          }
          return const Ok<void>(null);
        case TaskStatus.failed || TaskStatus.notFound || TaskStatus.canceled:
          _emitFailed(
            TaskStatusUpdate(record.task, record.status, record.exception),
            record.status == TaskStatus.canceled
                ? const CancelledError()
                : _failedStatusError(
                    TaskStatusUpdate(
                      record.task,
                      record.status,
                      record.exception,
                    ),
                  ),
          );
          return const Ok<void>(null);
        case TaskStatus.enqueued ||
            TaskStatus.running ||
            TaskStatus.waitingToRetry ||
            TaskStatus.paused:
          break;
      }
    }
    if (existing != null) return const Ok<void>(null);

    final sha256 = entry.sha256;
    final storedPath = entry.localPath;
    if (sha256 == null || !_isSha256(sha256)) {
      return _rejected(const MirrorAssetReadError('mirror sha256 is invalid'));
    }
    final resolvedPath = await resolveMirrorStoredPath(
      storedPath: storedPath ?? '',
      supportDirectoryProvider: _supportDirectoryProvider,
    );
    if (resolvedPath case Err<String>(:final error)) return _rejected(error);
    final localPath = (resolvedPath as Ok<String>).value;

    try {
      if (await FileSystemEntity.type(localPath, followLinks: false) !=
          FileSystemEntityType.file) {
        return _rejected(
          const MirrorAssetReadError('mirror local path is not a regular file'),
        );
      }
    } on Exception catch (error) {
      return _rejected(MirrorAssetReadError(error.toString()));
    }

    final TainaResult<HttpRequest> provided;
    try {
      provided = await requestProvider();
    } on Exception catch (error) {
      return _rejected(NetworkError(error.toString()));
    }
    if (provided case Err<HttpRequest>(:final error)) {
      return _rejected(error);
    }
    final request = (provided as Ok<HttpRequest>).value;

    final UploadTask task;
    try {
      final (baseDirectory, directory, filename) = await _gateway.split(
        localPath,
      );
      if (baseDirectory == BaseDirectory.root) {
        return _rejected(
          const MirrorAssetReadError(
            'mirror local path is outside a stable application directory',
          ),
        );
      }
      if (filename.isEmpty) {
        return _rejected(
          const MirrorAssetReadError('mirror local filename is missing'),
        );
      }
      task = UploadTask(
        taskId: taskId,
        url: request.url.toString(),
        httpRequestMethod: request.method,
        headers: request.headers,
        baseDirectory: baseDirectory,
        directory: directory,
        filename: filename,
        fileField: 'file',
        fields: {'folder': folderRkey},
        mimeType: entry.mime,
        updates: Updates.statusAndProgress,
        requiresWiFi: requiresWiFiProvider?.call() ?? requiresWiFi,
        retries: 0,
        group: mirrorGroup,
        metaData: _metadata(ownerId: ownerId, entry: entry, sha256: sha256),
        displayName: entry.filename,
      );
    } on Exception catch (error) {
      return _rejected(MirrorAssetReadError(error.toString()));
    }

    if (_disposed) {
      return _rejected(
        const MirrorAssetReadError('mirror transfer is disposed'),
      );
    }

    final bool enqueued;
    try {
      enqueued = await _gateway.enqueue(task);
    } on Exception catch (error) {
      return _uncertain(MirrorAssetReadError(error.toString()));
    }
    if (enqueued) return const Ok<void>(null);

    try {
      if (await _gateway.taskForId(taskId) != null) {
        return const Ok<void>(null);
      }
    } on Exception catch (error) {
      return _uncertain(MirrorAssetReadError(error.toString()));
    }
    return _rejected(
      const MirrorAssetReadError('background mirror task was not enqueued'),
    );
  }

  @override
  Future<TainaResult<void>> cancel(String backgroundTaskId) =>
      _serialize(() => _cancel(backgroundTaskId));

  Future<TainaResult<void>> _cancel(String taskId) async {
    if (_disposed) {
      return const Err(MirrorAssetReadError('mirror transfer is disposed'));
    }
    if (ownerId.trim().isEmpty) {
      return const Err(MirrorAssetReadError('mirror owner ID is missing'));
    }
    if (taskId.trim().isEmpty) {
      return const Err(MirrorAssetReadError('mirror task ID is missing'));
    }

    final started = await start();
    if (started case Err<void>(:final error)) return Err(error);

    try {
      if (await _gateway.cancel(taskId)) return const Ok<void>(null);
      if (await _gateway.taskForId(taskId) == null) {
        return const Ok<void>(null);
      }
      return const Err(
        MirrorAssetReadError('background mirror task could not be cancelled'),
      );
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  void _handleUpdate(TaskUpdate update) {
    if (_disposed) return;
    switch (update) {
      case TaskProgressUpdate():
        final metadata = _metadataFor(update.task);
        final progress = update.progress;
        if (metadata == null ||
            !progress.isFinite ||
            progress < 0 ||
            progress > 1) {
          return;
        }
        _events.add(
          MirrorTransferProgress(
            assetId: metadata.assetId,
            taskId: update.task.taskId,
            value: progress,
          ),
        );
      case TaskStatusUpdate():
        _handleStatusUpdate(update);
    }
  }

  void _handleStatusUpdate(TaskStatusUpdate update) {
    final metadata = _metadataFor(update.task);
    if (metadata == null) return;

    switch (update.status) {
      case TaskStatus.enqueued ||
          TaskStatus.running ||
          TaskStatus.waitingToRetry ||
          TaskStatus.paused:
        return;
      case TaskStatus.canceled:
        _emitFailed(update, const CancelledError());
      case TaskStatus.failed || TaskStatus.notFound:
        _emitFailed(update, _failedStatusError(update));
      case TaskStatus.complete:
        _complete(update, metadata);
    }
  }

  void _complete(TaskStatusUpdate update, _MirrorTaskMetadata metadata) {
    final status = update.responseStatusCode;
    if (status != null && (status < 200 || status >= 300)) {
      _emitFailed(
        update,
        _httpFailure(
          status: status,
          responseBody: update.responseBody ?? update.exception?.description,
          responseHeaders: update.responseHeaders,
        ),
      );
      return;
    }

    final responseBody = update.responseBody;
    if (responseBody == null) {
      _emitInvalidResponse(update, 'mirror upload response is missing');
      return;
    }

    final decoded = decodeJsonBody(
      utf8.encode(responseBody),
      'mirror upload response',
      FileRecord.fromJson,
    );
    if (decoded case Err<FileRecord>(:final error)) {
      _emitFailed(update, error);
      return;
    }
    final file = (decoded as Ok<FileRecord>).value;
    if (file.sha256 != metadata.expectedSha256) {
      _emitInvalidResponse(update, 'mirror upload sha256 does not match');
      return;
    }

    _completedTaskIdentities.add(_taskIdentity(update.task, metadata));
    _events.add(
      MirrorTransferCompleted(
        assetId: metadata.assetId,
        taskId: update.task.taskId,
        modificationDate: metadata.modificationDate,
        file: file,
      ),
    );
  }

  TainaError _failedStatusError(TaskStatusUpdate update) {
    final exception = update.exception;
    final httpStatus = switch (exception) {
      TaskHttpException(:final httpResponseCode) when httpResponseCode > 0 =>
        httpResponseCode,
      _ => update.responseStatusCode,
    };
    if (httpStatus != null && httpStatus > 0) {
      return _httpFailure(
        status: httpStatus,
        responseBody: update.responseBody ?? exception?.description,
        responseHeaders: update.responseHeaders,
      );
    }
    return NetworkError(exception?.description ?? 'background upload failed');
  }

  TainaError _httpFailure({
    required int status,
    required String? responseBody,
    required Map<String, String>? responseHeaders,
  }) => LiveTainaApi.apiFailure(
    HttpResponse(
      status: status,
      headers: responseHeaders ?? const {},
      data: responseBody == null ? const [] : utf8.encode(responseBody),
    ),
  );

  void _emitInvalidResponse(TaskStatusUpdate update, String cause) {
    _emitFailed(update, InvalidResponseError(cause));
  }

  void _emitFailed(TaskStatusUpdate update, TainaError error) {
    final metadata = _metadataFor(update.task);
    if (_disposed ||
        metadata == null ||
        !_emittedFailureTaskIds.add(update.task.taskId)) {
      return;
    }
    _events.add(
      MirrorTransferFailed(
        assetId: metadata.assetId,
        taskId: update.task.taskId,
        error: error,
      ),
    );
  }

  bool _taskMatchesEntry(Task task, MirrorEntry entry, String taskId) {
    if (task is! UploadTask || task.taskId != taskId) return false;
    final metadata = _metadataFor(task);
    return metadata != null &&
        metadata.assetId == entry.assetId &&
        metadata.modificationDate.microsecondsSinceEpoch ==
            entry.modificationDate.toUtc().microsecondsSinceEpoch &&
        metadata.expectedSha256 == entry.sha256;
  }

  (String, String, int, String) _taskIdentity(
    Task task,
    _MirrorTaskMetadata metadata,
  ) => (
    task.taskId,
    metadata.assetId,
    metadata.modificationDate.microsecondsSinceEpoch,
    metadata.expectedSha256,
  );

  _MirrorTaskMetadata? _metadataFor(Task task) {
    if (ownerId.trim().isEmpty ||
        task is! UploadTask ||
        task.group != mirrorGroup ||
        task.taskId.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(task.metaData);
      if (decoded is! Map<String, dynamic>) return null;
      final taskOwnerId = decoded['ownerId'];
      final assetId = decoded['assetId'];
      final modificationDate = decoded['modificationDate'];
      final expectedSha256 = decoded['sha256'];
      if (taskOwnerId != ownerId ||
          assetId is! String ||
          assetId.isEmpty ||
          modificationDate is! int ||
          expectedSha256 is! String ||
          !_isSha256(expectedSha256)) {
        return null;
      }
      return _MirrorTaskMetadata(
        assetId: assetId,
        modificationDate: DateTime.fromMicrosecondsSinceEpoch(
          modificationDate,
          isUtc: true,
        ),
        expectedSha256: expectedSha256,
      );
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    await _events.close();
  }

  static String _metadata({
    required String ownerId,
    required MirrorEntry entry,
    required String sha256,
  }) => jsonEncode({
    'ownerId': ownerId,
    'assetId': entry.assetId,
    'modificationDate': entry.modificationDate.toUtc().microsecondsSinceEpoch,
    'sha256': sha256,
  });

  static bool _isSha256(String value) =>
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);

  static Err<void> _rejected(TainaError error) =>
      Err(MirrorTransferRejected(error));

  static Err<void> _uncertain(TainaError error) =>
      Err(MirrorTransferUncertain(error));
}

final class _MirrorTaskMetadata {
  const _MirrorTaskMetadata({
    required this.assetId,
    required this.modificationDate,
    required this.expectedSha256,
  });

  final String assetId;
  final DateTime modificationDate;
  final String expectedSha256;
}

final class _FileDownloaderGateway implements BackgroundDownloaderGateway {
  factory _FileDownloaderGateway() => _instance;

  _FileDownloaderGateway._() : _downloader = FileDownloader();

  static final _FileDownloaderGateway _instance = _FileDownloaderGateway._();

  final FileDownloader _downloader;

  @override
  Stream<TaskUpdate> get updates => _downloader.updates;

  @override
  Future<void> start() => _downloader.start(
    doTrackTasks: true,
    doRescheduleKilledTasks: false,
    autoCleanDatabase: true,
  );

  @override
  Future<Task?> taskForId(String taskId) => _downloader.taskForId(taskId);

  @override
  Future<TaskRecord?> recordForId(String taskId) =>
      _downloader.database.recordForId(taskId);

  @override
  Future<(BaseDirectory, String, String)> split(String filePath) =>
      Task.split(filePath: filePath);

  @override
  Future<bool> enqueue(UploadTask task) => _downloader.enqueue(task);

  @override
  Future<bool> cancel(String taskId) => _downloader.cancelTaskWithId(taskId);
}
