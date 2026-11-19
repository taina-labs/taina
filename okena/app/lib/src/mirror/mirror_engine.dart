// The public constructor names stay separate from the private stored fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:okena_app/src/mirror/mirror_asset_hasher.dart';
import 'package:okena_app/src/mirror/mirror_transition_store.dart';
import 'package:okena_app/src/mirror/mirror_transfer.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

typedef MirrorClock = DateTime Function();
typedef _ProgressKey = ({String assetId, String backgroundTaskId});

final class _ProgressBatch {
  _ProgressBatch({required this.key, required this.progress});

  final _ProgressKey key;
  final List<Completer<TainaResult<void>>> waiters = [];
  double progress;
  Timer? timer;
}

final class _PendingCancellationResolution {
  _PendingCancellationResolution({
    required this.ledger,
    required this.firstLocalFailure,
    required Iterable<String> excludedAssetIds,
    required Iterable<String> deferredUploadAssetIds,
  }) : excludedAssetIds = Set.unmodifiable(excludedAssetIds),
       deferredUploadAssetIds = Set.unmodifiable(deferredUploadAssetIds);

  final MirrorLedger ledger;
  final TainaError? firstLocalFailure;
  final Set<String> excludedAssetIds;
  final Set<String> deferredUploadAssetIds;
}

/// Coordinates the persisted camera-roll mirror state and its external edges.
final class MirrorEngine {
  MirrorEngine({
    required SessionGateway session,
    required MirrorStore store,
    required MirrorAssetHasher hasher,
    required MirrorTransfer transfer,
    required this.ownerId,
    Random? random,
    MirrorClock? clock,
    this.progressBatchWindow = const Duration(milliseconds: 250),
  }) : _session = session,
       _store = store,
       _hasher = hasher,
       _transfer = transfer,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  static const String destinationFolderName = 'Rolo de câmera';

  final SessionGateway _session;
  final MirrorStore _store;
  final MirrorAssetHasher _hasher;
  final MirrorTransfer _transfer;
  final Random _random;
  final String ownerId;
  final MirrorClock _clock;
  final Duration progressBatchWindow;

  Future<void> _operationTail = Future<void>.value();
  Future<TainaResult<void>>? _reconcileInFlight;
  final Map<_ProgressKey, _ProgressBatch> _progressBatches = {};

  /// Reconciles one camera-roll snapshot. Concurrent calls share this run.
  Future<TainaResult<void>> reconcile(Iterable<MirrorAsset> assets) {
    final inFlight = _reconcileInFlight;
    if (inFlight != null) return inFlight;

    final snapshot = List<MirrorAsset>.unmodifiable(assets);
    late final Future<TainaResult<void>> run;
    run = _enqueue(() async {
      try {
        return await _runReconcile(snapshot);
      } finally {
        if (identical(_reconcileInFlight, run)) {
          _reconcileInFlight = null;
        }
      }
    });
    _reconcileInFlight = run;
    return run;
  }

  /// Applies a native completion. A completion for an older asset revision is
  /// ignored by [MirrorLedger.markUploaded].
  Future<TainaResult<void>> complete({
    required String assetId,
    required DateTime modificationDate,
    required FileRecord file,
  }) => _enqueue(() async {
    final loaded = await _loadLedger();
    if (loaded is Err<MirrorLedger>) return Err(loaded.error);
    final ledger = (loaded as Ok<MirrorLedger>).value;
    return _saveLedger(
      ledger.markUploaded(
        assetId: assetId,
        modificationDate: modificationDate,
        file: file,
        updatedAt: _now(),
      ),
      changedAssetIds: {assetId},
      removedAssetIds: const {},
    );
  });

  /// Applies a native transfer failure, leaving the asset eligible for a
  /// later retry after the ledger's backoff period.
  Future<TainaResult<void>> fail({
    required String assetId,
    required String backgroundTaskId,
    required TainaError error,
  }) => _enqueue(() async {
    final loaded = await _loadLedger();
    if (loaded is Err<MirrorLedger>) return Err(loaded.error);
    final ledger = (loaded as Ok<MirrorLedger>).value;
    final entry = ledger.entries[assetId];
    if (!_isCurrentTask(entry, backgroundTaskId)) {
      return const Ok<void>(null);
    }
    return _saveLedger(
      ledger.markFailed(
        assetId: assetId,
        error: error.message,
        updatedAt: _now(),
      ),
      changedAssetIds: {assetId},
      removedAssetIds: const {},
    );
  });

  /// Coalesces progress by asset and task for [progressBatchWindow].
  ///
  /// The latest value in a batch is persisted once, and every caller waiting
  /// on that batch receives the same result. Completion, failure, cancellation
  /// and reconciliation do not wait for the timer; a later flush rechecks the
  /// task against the persisted ledger before applying progress.
  Future<TainaResult<void>> updateProgress({
    required String assetId,
    required String backgroundTaskId,
    required double progress,
  }) {
    if (!progress.isFinite || progress < 0 || progress > 1) {
      return Future<TainaResult<void>>.value(
        const Err<void>(InvalidResponseError('mirror progress is invalid')),
      );
    }

    final key = (assetId: assetId, backgroundTaskId: backgroundTaskId);
    var batch = _progressBatches[key];
    if (batch == null) {
      batch = _ProgressBatch(key: key, progress: progress);
      _progressBatches[key] = batch;
      final scheduled = batch;
      batch.timer = Timer(progressBatchWindow, () {
        if (!identical(_progressBatches[key], scheduled)) return;
        _progressBatches.remove(key);
        scheduled.timer = null;
        _flushProgressBatch(scheduled);
      });
    } else {
      batch.progress = progress;
    }

    final waiter = Completer<TainaResult<void>>();
    batch.waiters.add(waiter);
    return waiter.future;
  }

  void _flushProgressBatch(_ProgressBatch batch) {
    final operation = _enqueue(() => _applyProgress(batch));
    for (final waiter in batch.waiters) {
      waiter.complete(operation);
    }
  }

  Future<TainaResult<void>> _applyProgress(_ProgressBatch batch) async {
    final loaded = await _loadLedger();
    if (loaded is Err<MirrorLedger>) return Err(loaded.error);
    final ledger = (loaded as Ok<MirrorLedger>).value;
    final entry = ledger.entries[batch.key.assetId];
    if (!_isCurrentTask(entry, batch.key.backgroundTaskId)) {
      return const Ok<void>(null);
    }
    return _saveLedger(
      ledger.updateProgress(
        assetId: batch.key.assetId,
        progress: batch.progress,
        updatedAt: _now(),
      ),
      changedAssetIds: {batch.key.assetId},
      removedAssetIds: const {},
    );
  }

  /// Persists cancellation intent before asking native work to stop.
  ///
  /// The task ID remains in the queued entry until native cancellation is
  /// confirmed, so reconciliation can finish the cancellation after restart.
  Future<TainaResult<void>> cancel({required String assetId}) =>
      _enqueue(() async {
        final loaded = await _loadLedger();
        if (loaded is Err<MirrorLedger>) return Err(loaded.error);
        var ledger = (loaded as Ok<MirrorLedger>).value;
        final entry = ledger.entries[assetId];
        final taskId = entry?.backgroundTaskId;
        if (entry == null) return const Ok<void>(null);

        if (entry.state == MirrorState.uploading && taskId == null) {
          return _saveLedger(
            ledger.cancelUpload(assetId: assetId, updatedAt: _now()),
            changedAssetIds: {assetId},
            removedAssetIds: const {},
          );
        }

        if (taskId == null) return const Ok<void>(null);

        if (entry.state == MirrorState.uploading) {
          final pending = entry.copyWith(
            state: MirrorState.queued,
            progress: 0,
            clearLastError: true,
            updatedAt: _now(),
          );
          ledger = ledger.upsert(pending);
          final intentSaved = await _saveLedger(
            ledger,
            changedAssetIds: {assetId},
            removedAssetIds: const {},
          );
          if (intentSaved is Err<void>) return intentSaved;
          return _cancelPendingTask(ledger, pending);
        }

        if (entry.state == MirrorState.queued) {
          return _cancelPendingTask(ledger, entry);
        }

        return const Ok<void>(null);
      });

  Future<TainaResult<void>> _enqueue(
    Future<TainaResult<void>> Function() operation,
  ) {
    final result = _operationTail.then((_) => operation());
    // Keep the FIFO tail usable if an unexpected programmer error escapes an
    // operation. The caller still receives the original failing Future.
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<TainaResult<void>> _runReconcile(List<MirrorAsset> assets) async {
    final loaded = await _loadLedger();
    if (loaded is Err<MirrorLedger>) return Err(loaded.error);
    var ledger = (loaded as Ok<MirrorLedger>).value;

    final cancellations = await _resolvePendingCancellations(ledger, assets);
    if (cancellations is Err<_PendingCancellationResolution>) {
      return Err(cancellations.error);
    }
    final cancellationResolution =
        (cancellations as Ok<_PendingCancellationResolution>).value;
    ledger = cancellationResolution.ledger;

    final manifest = await _manifestHashes();
    if (manifest is Err<Set<String>>) return Err(manifest.error);
    final knownHashes = (manifest as Ok<Set<String>>).value;

    final planAssets = assets
        .where(
          (asset) =>
              !cancellationResolution.excludedAssetIds.contains(asset.assetId),
        )
        .toList(growable: false);
    final previousLedger = ledger;
    final planned = MirrorPlan.plan(
      planAssets,
      ledger,
      knownHashes,
      updatedAt: _now(),
    );
    ledger = planned.updatedLedger;
    final changedAssetIds = <String>{
      for (final entry in ledger.entries.entries)
        if (previousLedger.entries[entry.key] != entry.value) entry.key,
    };
    final removedAssetIds = <String>{
      for (final assetId in previousLedger.entries.keys)
        if (!ledger.entries.containsKey(assetId)) assetId,
    };
    final plannedSave = await _saveLedger(
      ledger,
      changedAssetIds: changedAssetIds,
      removedAssetIds: removedAssetIds,
    );
    if (plannedSave is Err<void>) return plannedSave;

    TainaError? firstHashFailure;
    for (final entry in planned.toHash) {
      final hashed = await _hasher.hash(entry);
      if (hashed case Err<MirrorHashResult>(:final error)) {
        ledger = ledger.markFailed(
          assetId: entry.assetId,
          error: error.message,
          updatedAt: _now(),
        );
        final saved = await _saveLedger(
          ledger,
          changedAssetIds: {entry.assetId},
          removedAssetIds: const {},
        );
        if (saved is Err<void>) return saved;
        firstHashFailure ??= error;
        continue;
      }

      final hashResult = (hashed as Ok<MirrorHashResult>).value;
      ledger = ledger.markHashed(
        assetId: entry.assetId,
        sha256: hashResult.sha256,
        localPath: hashResult.localPath,
        updatedAt: _now(),
      );
      final saved = await _saveLedger(
        ledger,
        changedAssetIds: {entry.assetId},
        removedAssetIds: const {},
      );
      if (saved is Err<void>) return saved;
    }

    final lookedUp = await _resolveKnownHashes(
      ledger,
      knownHashes,
      excludedAssetIds: cancellationResolution.excludedAssetIds,
    );
    if (lookedUp is Err<MirrorLedger>) return Err(lookedUp.error);
    ledger = (lookedUp as Ok<MirrorLedger>).value;

    final now = _now();
    final active = _activeEntries(ledger)
        .where(
          (entry) =>
              !cancellationResolution.excludedAssetIds.contains(entry.assetId),
        )
        .toList(growable: false);
    final candidates = ledger
        .nextUploads()
        .where(
          (entry) => !cancellationResolution.deferredUploadAssetIds.contains(
            entry.assetId,
          ),
        )
        .where(
          (entry) =>
              !cancellationResolution.excludedAssetIds.contains(entry.assetId),
        )
        .where((entry) => _retryIsReady(entry, now))
        .toList(growable: false);
    TainaError? firstTransferFailure;
    if (active.isNotEmpty || candidates.isNotEmpty) {
      final destination = await _ensureDestination(ledger);
      if (destination is Err<MirrorLedger>) return Err(destination.error);
      ledger = (destination as Ok<MirrorLedger>).value;
      final folderRkey = ledger.destinationFolderRkey;
      if (folderRkey == null) {
        return const Err(
          InvalidResponseError('mirror destination folder was not saved'),
        );
      }

      for (final entry in active) {
        final started = await _transfer.ensureStarted(
          entry: entry,
          folderRkey: folderRkey,
        );
        if (started is Err<void>) {
          final error = started.error;
          if (error is MirrorTransferRejected) {
            ledger = ledger.markFailed(
              assetId: entry.assetId,
              error: error.message,
              updatedAt: _now(),
            );
            final saved = await _saveLedger(
              ledger,
              changedAssetIds: {entry.assetId},
              removedAssetIds: const {},
            );
            if (saved is Err<void>) return saved;
            if (_isGlobalTransferFailure(error)) return Err(error);
            firstTransferFailure ??= error;
            continue;
          }

          if (error is MirrorTransferUncertain) {
            if (_isGlobalTransferFailure(error)) return Err(error);
            firstTransferFailure ??= error;
            continue;
          }

          return Err(error);
        }
      }

      // nextUploads already suppresses hashes held by active uploads and
      // chooses only one local copy for each remaining hash.
      for (final candidate in candidates) {
        final taskId = _taskId(candidate);
        ledger = ledger.markUploading(
          assetId: candidate.assetId,
          backgroundTaskId: taskId,
          progress: 0,
          updatedAt: _now(),
        );
        final saved = await _saveLedger(
          ledger,
          changedAssetIds: {candidate.assetId},
          removedAssetIds: const {},
        );
        if (saved is Err<void>) return saved;

        final uploading = ledger.entries[candidate.assetId];
        if (uploading == null) {
          return const Err(
            InvalidResponseError('planned mirror entry was not persisted'),
          );
        }
        final started = await _transfer.ensureStarted(
          entry: uploading,
          folderRkey: folderRkey,
        );
        if (started is Err<void>) {
          final error = started.error;
          if (error is MirrorTransferRejected) {
            ledger = ledger.markFailed(
              assetId: uploading.assetId,
              error: error.message,
              updatedAt: _now(),
            );
            final failedSave = await _saveLedger(
              ledger,
              changedAssetIds: {uploading.assetId},
              removedAssetIds: const {},
            );
            if (failedSave is Err<void>) return failedSave;
            if (_isGlobalTransferFailure(error)) return Err(error);
            firstTransferFailure ??= error;
            continue;
          }

          if (error is MirrorTransferUncertain) {
            if (_isGlobalTransferFailure(error)) return Err(error);
            firstTransferFailure ??= error;
            continue;
          }

          return Err(error);
        }
      }
    }

    final localCancellationFailure = cancellationResolution.firstLocalFailure;
    if (localCancellationFailure != null) {
      return Err(localCancellationFailure);
    }
    if (firstTransferFailure != null) {
      return Err(firstTransferFailure);
    }
    if (firstHashFailure != null) return Err(firstHashFailure);
    return const Ok<void>(null);
  }

  Future<TainaResult<Set<String>>> _manifestHashes() async {
    final hashes = <String>{};
    final cursors = <String>{};
    String? cursor;

    while (true) {
      final response = await _session.screen(
        await _session.api.manifest(
          after: cursor,
          limit: 1000,
          mode: ManifestMode.mirror,
        ),
      );
      if (response case Err<Page<FileRecord>>(:final error)) {
        return Err(error);
      }
      final page = (response as Ok<Page<FileRecord>>).value;
      hashes.addAll(page.items.map((file) => file.sha256));
      final next = page.nextCursor;
      if (next == null) return Ok(hashes);
      if (!cursors.add(next)) {
        return const Err(InvalidResponseError('mirror manifest cursor loop'));
      }
      cursor = next;
    }
  }

  Future<TainaResult<MirrorLedger>> _resolveKnownHashes(
    MirrorLedger initial,
    Set<String> knownHashes, {
    Set<String> excludedAssetIds = const {},
  }) async {
    var ledger = initial;
    final ordered = ledger.entries.values.toList()
      ..sort((a, b) => a.assetId.compareTo(b.assetId));
    final assetIdsByHash = <String, List<String>>{};
    final hashesToLookup = <String>{};

    for (final entry in ordered) {
      final hash = entry.sha256;
      if (hash == null ||
          excludedAssetIds.contains(entry.assetId) ||
          !_needsLookup(entry.state)) {
        continue;
      }
      assetIdsByHash.putIfAbsent(hash, () => []).add(entry.assetId);
      if (!knownHashes.contains(hash) || entry.state == MirrorState.hashed) {
        hashesToLookup.add(hash);
      }
    }

    for (final hashEntry in assetIdsByHash.entries) {
      final hash = hashEntry.key;
      if (!hashesToLookup.contains(hash)) continue;
      final response = await _session.screen(
        await _session.api.hashLookup(sha256: hash),
      );
      if (response case Err<MirrorHashLookup>(:final error)) {
        if (error case ApiError(status: 404, code: 'not_found')) {
          for (final assetId in hashEntry.value) {
            final item = ledger.entries[assetId];
            if (item == null ||
                item.sha256 != hash ||
                item.state != MirrorState.hashed) {
              continue;
            }
            ledger = ledger.markQueued(
              assetId: item.assetId,
              updatedAt: _now(),
            );
            final saved = await _saveLedger(
              ledger,
              changedAssetIds: {item.assetId},
              removedAssetIds: const {},
            );
            if (saved is Err<void>) return Err(saved.error);
          }
          continue;
        }
        return Err(error);
      }

      final lookup = (response as Ok<MirrorHashLookup>).value;
      switch (lookup) {
        case MirrorHashPresent(:final file):
          for (final assetId in hashEntry.value) {
            final item = ledger.entries[assetId];
            if (item == null ||
                item.sha256 != hash ||
                !_needsLookup(item.state)) {
              continue;
            }
            ledger = ledger.markUploaded(
              assetId: item.assetId,
              modificationDate: item.modificationDate,
              file: file,
              updatedAt: _now(),
            );
            final saved = await _saveLedger(
              ledger,
              changedAssetIds: {item.assetId},
              removedAssetIds: const {},
            );
            if (saved is Err<void>) return Err(saved.error);
          }
        case MirrorHashSuppressed():
          for (final assetId in hashEntry.value) {
            final item = ledger.entries[assetId];
            if (item == null ||
                item.sha256 != hash ||
                !_needsLookup(item.state)) {
              continue;
            }
            ledger = ledger.markSkipped(
              assetId: item.assetId,
              updatedAt: _now(),
            );
            final saved = await _saveLedger(
              ledger,
              changedAssetIds: {item.assetId},
              removedAssetIds: const {},
            );
            if (saved is Err<void>) return Err(saved.error);
          }
      }
    }

    return Ok(ledger);
  }

  Future<TainaResult<MirrorLedger>> _ensureDestination(
    MirrorLedger ledger,
  ) async {
    if (ledger.destinationFolderRkey != null) return Ok(ledger);

    final listed = await _session.screen(await _session.api.listFolders());
    if (listed case Err<List<Folder>>(:final error)) return Err(error);
    final folders = (listed as Ok<List<Folder>>).value;
    final existing = _cameraRollFolder(folders);
    final Folder destination;
    if (existing != null) {
      destination = existing;
    } else {
      final created = await _session.screen(
        await _session.api.createFolder(name: destinationFolderName),
      );
      if (created case Err<Folder>(:final error)) return Err(error);
      destination = (created as Ok<Folder>).value;
      if (destination.zona != Zona.casa ||
          destination.folder != null ||
          destination.name != destinationFolderName) {
        return const Err(
          InvalidResponseError('camera-roll folder is not a root casa folder'),
        );
      }
    }

    final updated = ledger.withDestinationFolder(destination.rkey);
    final saved = await _saveLedger(
      updated,
      changedAssetIds: const {},
      removedAssetIds: const {},
    );
    if (saved is Err<void>) return Err(saved.error);
    return Ok(updated);
  }

  Future<TainaResult<_PendingCancellationResolution>>
  _resolvePendingCancellations(
    MirrorLedger initial,
    List<MirrorAsset> assets,
  ) async {
    var ledger = initial;
    TainaError? firstLocalFailure;
    final excludedAssetIds = <String>{};
    final deferredUploadAssetIds = _pendingCancellationIds(ledger);
    final pending =
        ledger.entries.values
            .where(
              (entry) =>
                  entry.state == MirrorState.queued &&
                  entry.backgroundTaskId != null,
            )
            .toList()
          ..sort((a, b) => a.assetId.compareTo(b.assetId));

    for (final entry in pending) {
      final taskId = entry.backgroundTaskId;
      if (taskId == null) continue;

      final cancelled = await _transfer.cancel(taskId);
      if (cancelled case Err<void>(:final error)) {
        if (_isGlobalTransferFailure(error)) return Err(error);
        excludedAssetIds.add(entry.assetId);
        firstLocalFailure ??= error;
        continue;
      }

      final current = ledger.entries[entry.assetId];
      if (current == null) {
        return const Err(
          InvalidResponseError('pending cancellation entry is missing'),
        );
      }
      final cleared = current.copyWith(
        state: MirrorState.queued,
        clearBackgroundTaskId: true,
        progress: 0,
        clearLastError: true,
        updatedAt: _now(),
      );
      ledger = ledger.upsert(cleared);
      final saved = await _saveLedger(
        ledger,
        changedAssetIds: {entry.assetId},
        removedAssetIds: const {},
      );
      if (saved is Err<void>) return Err(saved.error);
    }

    final latestAssets = _latestAssetsById(assets);
    final superseded = ledger.entries.values.where((entry) {
      final asset = latestAssets[entry.assetId];
      return asset != null &&
          !entry.isTerminal &&
          entry.state != MirrorState.queued &&
          entry.backgroundTaskId != null &&
          entry.modificationDate != asset.modificationDate;
    }).toList()..sort((a, b) => a.assetId.compareTo(b.assetId));

    for (final entry in superseded) {
      final taskId = entry.backgroundTaskId;
      if (taskId == null) continue;

      final pendingEntry = entry.copyWith(
        state: MirrorState.queued,
        progress: 0,
        clearLastError: true,
        updatedAt: _now(),
      );
      ledger = ledger.upsert(pendingEntry);
      final intentSaved = await _saveLedger(
        ledger,
        changedAssetIds: {entry.assetId},
        removedAssetIds: const {},
      );
      if (intentSaved is Err<void>) return Err(intentSaved.error);

      final cancelled = await _transfer.cancel(taskId);
      if (cancelled case Err<void>(:final error)) {
        if (_isGlobalTransferFailure(error)) return Err(error);
        excludedAssetIds.add(entry.assetId);
        firstLocalFailure ??= error;
        continue;
      }

      final current = ledger.entries[entry.assetId];
      if (current == null) {
        return const Err(
          InvalidResponseError('superseded cancellation entry is missing'),
        );
      }
      final cleared = current.copyWith(
        state: MirrorState.queued,
        clearBackgroundTaskId: true,
        progress: 0,
        clearLastError: true,
        updatedAt: _now(),
      );
      ledger = ledger.upsert(cleared);
      final saved = await _saveLedger(
        ledger,
        changedAssetIds: {entry.assetId},
        removedAssetIds: const {},
      );
      if (saved is Err<void>) return Err(saved.error);
    }

    return Ok(
      _PendingCancellationResolution(
        ledger: ledger,
        firstLocalFailure: firstLocalFailure,
        excludedAssetIds: excludedAssetIds,
        deferredUploadAssetIds: deferredUploadAssetIds,
      ),
    );
  }

  Future<TainaResult<void>> _cancelPendingTask(
    MirrorLedger ledger,
    MirrorEntry entry,
  ) async {
    final taskId = entry.backgroundTaskId;
    if (taskId == null) return const Ok<void>(null);

    final cancelled = await _transfer.cancel(taskId);
    if (cancelled is Err<void>) return Err(cancelled.error);

    final cleared = entry.copyWith(
      state: MirrorState.queued,
      clearBackgroundTaskId: true,
      progress: 0,
      clearLastError: true,
      updatedAt: _now(),
    );
    return _saveLedger(
      ledger.upsert(cleared),
      changedAssetIds: {entry.assetId},
      removedAssetIds: const {},
    );
  }

  Future<TainaResult<MirrorLedger>> _loadLedger() async {
    final result = await _store.load();
    if (result case Err<MirrorLedger?>(:final error)) return Err(error);
    final stored = (result as Ok<MirrorLedger?>).value;
    final ledger = stored ?? MirrorLedger(ownerId: ownerId);
    if (ledger.ownerId != ownerId) {
      return const Err(InvalidResponseError('mirror ledger owner mismatch'));
    }
    return Ok(ledger);
  }

  Future<TainaResult<void>> _saveLedger(
    MirrorLedger ledger, {
    required Set<String> changedAssetIds,
    required Set<String> removedAssetIds,
  }) async {
    final store = _store;
    if (store is MirrorTransitionStore) {
      final orderedChangedIds = changedAssetIds.toList()..sort();
      final changedEntries = <MirrorEntry>[];
      for (final assetId in orderedChangedIds) {
        final entry = ledger.entries[assetId];
        if (entry == null) {
          return const Err(
            InvalidResponseError('changed mirror entry is missing from ledger'),
          );
        }
        changedEntries.add(entry);
      }

      final orderedRemovedIds = removedAssetIds.toList()..sort();
      for (final assetId in orderedRemovedIds) {
        if (ledger.entries.containsKey(assetId)) {
          return const Err(
            InvalidResponseError('removed mirror entry remains in ledger'),
          );
        }
      }

      final result = await store.saveTransition(
        ledger,
        changedEntries: changedEntries,
        removedAssetIds: orderedRemovedIds,
      );
      if (result case Err<void>(:final error)) return Err(error);
      return const Ok<void>(null);
    }

    final result = await store.save(ledger);
    if (result case Err<void>(:final error)) return Err(error);
    return const Ok<void>(null);
  }

  static Folder? _cameraRollFolder(List<Folder> folders) {
    for (final folder in folders) {
      if (folder.name == destinationFolderName &&
          folder.folder == null &&
          folder.zona == Zona.casa &&
          folder.deletedAt == null) {
        return folder;
      }
    }
    return null;
  }

  static List<MirrorEntry> _activeEntries(MirrorLedger ledger) {
    final entries =
        ledger.entries.values
            .where(
              (entry) =>
                  entry.state == MirrorState.uploading &&
                  entry.backgroundTaskId != null,
            )
            .toList()
          ..sort((a, b) => a.assetId.compareTo(b.assetId));
    return entries;
  }

  static Set<String> _pendingCancellationIds(MirrorLedger ledger) => {
    for (final entry in ledger.entries.values)
      if (entry.state == MirrorState.queued && entry.backgroundTaskId != null)
        entry.assetId,
  };

  static Map<String, MirrorAsset> _latestAssetsById(
    Iterable<MirrorAsset> assets,
  ) {
    final latest = <String, MirrorAsset>{};
    for (final asset in assets) {
      final current = latest[asset.assetId];
      if (current == null ||
          asset.modificationDate.isAfter(current.modificationDate)) {
        latest[asset.assetId] = asset;
      }
    }
    return latest;
  }

  static bool _needsLookup(MirrorState state) => switch (state) {
    MirrorState.hashed ||
    MirrorState.queued ||
    MirrorState.failed ||
    MirrorState.uploading => true,
    MirrorState.newAsset ||
    MirrorState.uploaded ||
    MirrorState.skipped => false,
  };

  static bool _isCurrentTask(MirrorEntry? entry, String backgroundTaskId) =>
      entry?.state == MirrorState.uploading &&
      entry?.backgroundTaskId == backgroundTaskId;

  static bool _isGlobalTransferFailure(TainaError error) => switch (error) {
    MirrorTransferStartError(:final cause) => _isGlobalTransferFailure(cause),
    NotSignedInError() || NetworkError() => true,
    ApiError(status: 401 || 403) => true,
    ApiError(status: >= 500 && < 600) => true,
    _ => false,
  };

  bool _retryIsReady(MirrorEntry entry, DateTime now) {
    if (entry.state != MirrorState.failed) return true;
    return now.difference(entry.updatedAt) >=
        MirrorLedger.retryDelay(entry.attempts);
  }

  String _taskId(MirrorEntry entry) {
    final modifiedMicros = entry.modificationDate.microsecondsSinceEpoch;
    final nonce = List.generate(
      8,
      (_) => _random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
    ).join();
    return 'mirror-$ownerId-${entry.assetId}-$modifiedMicros-$nonce';
  }

  DateTime _now() => _clock().toUtc();
}
