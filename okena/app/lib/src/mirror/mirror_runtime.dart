// The public constructor parameters assign private runtime state.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:okena_app/src/mirror/mirror_asset_materializer.dart';
import 'package:okena_app/src/mirror/mirror_engine.dart';
import 'package:okena_app/src/mirror/mirror_library.dart';
import 'package:okena_app/src/mirror/background_mirror_transfer.dart';
import 'package:okena_app/src/mirror/mirror_settings.dart';
import 'package:okena_core/okena_core.dart';

import 'mirror_foreground.dart';

typedef MirrorOwnerFactory = Future<TainaResult<MirrorOwnerMirror>> Function({
  required String ownerId,
  required Me identity,
});

void _reportMirrorAsyncError(
  Object error,
  StackTrace stackTrace,
  String context,
) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'Tainá mirror',
      context: ErrorDescription(context),
    ),
  );
}

final class _MirrorChangeNotifier extends ChangeNotifier {
  void emit() => notifyListeners();
}

/// Keeps one owner-scoped mirror attached across app lifecycle changes.
final class MirrorRuntime {
  MirrorRuntime({
    required Listenable changes,
    required Me? Function() identity,
    required MirrorForeground foreground,
    required MirrorOwnerFactory ownerFactory,
  }) : _changes = changes,
       _identity = identity,
       _foreground = foreground,
       _ownerFactory = ownerFactory;

  final Listenable _changes;
  final Me? Function() _identity;
  final MirrorForeground _foreground;
  final MirrorOwnerFactory _ownerFactory;
  final _MirrorChangeNotifier _notifier = _MirrorChangeNotifier();

  MirrorOwnerMirror? _owner;
  String? _ownerId;
  String? _requestedOwnerId;
  int _generation = 0;
  bool _attached = false;
  bool _disposed = false;
  bool? _lastForeground;
  final Map<String, Future<void>> _retirements = {};
  final Map<String, Future<void>> _ownerCreations = {};
  TainaError? _lastError;
  Future<void>? _disposal;
  bool _notifierDisposed = false;

  Listenable get changes => _notifier;

  TainaError? get lastError => _lastError;

  /// The owner currently attached to this runtime, if one has been created.
  MirrorOwnerMirror? get currentOwner => _owner;

  /// Connects session and foreground changes. The caller owns this boundary.
  void attach() {
    if (_attached || _disposed) return;
    _attached = true;
    _changes.addListener(_synchronize);
    final isForeground = _foreground.isForeground;
    _lastForeground = isForeground;
    _foreground.attach(_onForegroundChanged);
    _owner?.setForeground(isForeground);
    _synchronize();
  }

  void _onForegroundChanged(bool isForeground) {
    final resumed = isForeground && _lastForeground != true;
    final changed = _lastForeground != isForeground;
    _lastForeground = isForeground;
    if (changed) _notifyChanges();
    _owner?.setForeground(isForeground);
    _synchronize(resumed: resumed);
  }

  void _synchronize({bool resumed = false}) {
    if (_disposed || !_attached) return;

    final identity = _identity();
    final ownerId = identity == null ? null : _ownerKey(identity);
    if (ownerId != _requestedOwnerId) {
      _requestedOwnerId = ownerId;
      final generation = ++_generation;
      _retireCurrentOwner();
      if (identity != null && ownerId != null) {
        _queueOwnerCreation(generation, ownerId, identity);
      }
      return;
    }

    if (resumed && _foreground.isForeground) {
      final owner = _owner;
      if (owner != null) {
        _reconcileAutomatically(owner, refreshLibrary: true);
      } else if (ownerId != null && !_ownerCreations.containsKey(ownerId)) {
        _queueOwnerCreation(_generation, ownerId, identity!);
      }
    }
  }

  /// Retries owner creation when the current identity has no attached owner.
  ///
  /// The same generation checks as session-driven creation apply, so a retry
  /// cannot attach an owner after the identity changes.
  Future<void> refresh() async {
    if (_disposed || !_attached) return;

    final identity = _identity();
    final ownerId = identity == null ? null : _ownerKey(identity);
    if (ownerId != _requestedOwnerId) {
      _synchronize();
    }
    if (ownerId == null) return;

    final owner = _owner;
    if (owner != null) return;

    final pending = _ownerCreations[ownerId];
    if (pending != null) {
      await pending;
      return;
    }

    final currentIdentity = _identity();
    if (!_isCurrentIdentity(_generation, ownerId, currentIdentity)) return;

    _setLastError(null);
    _queueOwnerCreation(_generation, ownerId, currentIdentity!);
    await _ownerCreations[ownerId];
  }

  void _queueOwnerCreation(int generation, String ownerId, Me identity) {
    final previousCreation = _ownerCreations[ownerId];
    late final Future<void> creation;
    creation = _createOwner(
      generation,
      ownerId,
      identity,
      previousCreation: previousCreation,
    );
    _ownerCreations[ownerId] = creation;
    unawaited(_observeOwnerCreation(ownerId, creation));
  }

  Future<void> _observeOwnerCreation(
    String ownerId,
    Future<void> creation,
  ) async {
    try {
      await creation;
    } catch (error, stackTrace) {
      _reportMirrorAsyncError(
        error,
        stackTrace,
        'Creating the mirror owner for "$ownerId" failed.',
      );
    } finally {
      if (identical(_ownerCreations[ownerId], creation)) {
        _ownerCreations.remove(ownerId);
      }
    }
  }

  Future<void> _createOwner(
    int generation,
    String ownerId,
    Me identity, {
    required Future<void>? previousCreation,
  }) async {
    if (previousCreation != null) {
      try {
        await previousCreation;
      } catch (_) {
        // The previous creation's observer reports its original error/stack.
        // A stale attempt must not block a newer generation for this key.
      }
    }
    if (!_isCurrent(generation, ownerId)) return;
    final previousRetirement = _retirements[ownerId];
    if (previousRetirement != null) await previousRetirement;
    if (!_isCurrent(generation, ownerId)) return;

    final created = await _ownerFactory(ownerId: ownerId, identity: identity);

    if (created case Err<MirrorOwnerMirror>(:final error)) {
      if (_isCurrent(generation, ownerId)) _setLastError(error);
      return;
    }
    final owner = (created as Ok<MirrorOwnerMirror>).value;
    if (!_isCurrent(generation, ownerId)) {
      await owner.dispose();
      return;
    }

    _owner = owner;
    _ownerId = ownerId;
    _setLastError(null);
    owner.setForeground(_foreground.isForeground);
    owner.activate();
    _notifyChanges();
    if (_foreground.isForeground || !owner.enabled) {
      _reconcileAutomatically(owner, refreshLibrary: true);
    }
  }

  void _reconcileAutomatically(
    MirrorOwnerMirror owner, {
    required bool refreshLibrary,
  }) {
    final reconciliation = owner.enabled
        ? owner.reconcile(refreshLibrary: refreshLibrary)
        : owner.pause();
    unawaited(
      reconciliation.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _reportMirrorAsyncError(
            error,
            stackTrace,
            'Automatic mirror reconciliation failed.',
          );
        },
      ),
    );
  }

  bool _isCurrent(int generation, String ownerId) =>
      _isCurrentIdentity(generation, ownerId, _identity());

  bool _isCurrentIdentity(int generation, String ownerId, Me? identity) =>
      !_disposed &&
      _attached &&
      generation == _generation &&
      _requestedOwnerId == ownerId &&
      identity != null &&
      _ownerKey(identity) == ownerId;

  void _retireCurrentOwner() {
    final owner = _owner;
    final ownerId = _ownerId;
    _owner = null;
    _ownerId = null;
    if (owner == null || ownerId == null) return;

    final retirement = owner.deactivate();
    late final Future<void> trackedRetirement;
    trackedRetirement = retirement.then<void>(
      (_) {
        if (identical(_retirements[ownerId], trackedRetirement)) {
          _retirements.remove(ownerId);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _reportMirrorAsyncError(
          error,
          stackTrace,
          'Deactivating the mirror owner for "$ownerId" failed.',
        );
        if (identical(_retirements[ownerId], trackedRetirement)) {
          _retirements.remove(ownerId);
        }
      },
    );
    _retirements[ownerId] = trackedRetirement;
    _notifyChanges();
  }

  static String? _ownerKey(Me identity) {
    final tekoaId = identity.tekoa.publicId;
    final avaId = identity.ava.publicId;
    if (tekoaId.trim().isEmpty || avaId.trim().isEmpty) return null;
    return '$tekoaId:$avaId';
  }

  /// Stops observing and deactivates the current owner without clearing data.
  Future<void> dispose() {
    final previous = _disposal;
    if (previous != null) return previous;
    _disposed = true;
    _attached = false;
    _lastForeground = null;
    _requestedOwnerId = null;
    _generation++;
    _changes.removeListener(_synchronize);
    _foreground.dispose();
    _retireCurrentOwner();
    final pending = <Future<void>>[
      ..._retirements.values,
      for (final creation in _ownerCreations.values) _ignoreFailure(creation),
    ];
    final disposal = _finishDisposal(pending);
    _disposal = disposal;
    return disposal;
  }

  Future<void> _finishDisposal(List<Future<void>> pending) async {
    await Future.wait(pending);
    _notifierDisposed = true;
    _notifier.dispose();
  }

  Future<void> _ignoreFailure(Future<void> future) async {
    try {
      await future;
    } catch (_) {
      // Creation observers report their original error and stack.
    }
  }

  void _setLastError(TainaError? error) {
    if (_lastError == error) return;
    _lastError = error;
    _notifyChanges();
  }

  void _notifyChanges() {
    if (!_notifierDisposed) _notifier.emit();
  }
}

typedef MirrorTransferStarter = Future<TainaResult<void>> Function();
typedef MirrorTransferDisposer = Future<void> Function();

/// Coordinates one owner's local mirror ledger, photo library and transfer.
final class MirrorOwnerMirror {
  MirrorOwnerMirror({
    required this.engine,
    required this.library,
    required this.store,
    required this.materializer,
    required Stream<MirrorTransferEvent> transferEvents,
    required this.startTransfer,
    required this.disposeTransfer,
    bool enabled = true,
    bool wifiOnly = true,
    Future<TainaResult<void>> Function(MirrorPreferences preferences)?
    persistPreferences,
  }) {
    _enabled = enabled;
    _wifiOnly = wifiOnly;
    _persistPreferences = persistPreferences;
    _events = transferEvents.listen(
      _onTransferEvent,
      onError: (Object error, StackTrace _) {
        _onTransferEvent(
          MirrorTransferStreamFailed(error: NetworkError(error.toString())),
        );
      },
    );
  }

  final MirrorEngine engine;
  final MirrorLibrary library;
  final MirrorStore store;
  final MirrorAssetMaterializer materializer;
  final MirrorTransferStarter startTransfer;
  final MirrorTransferDisposer disposeTransfer;
  late bool _enabled;
  late bool _wifiOnly;
  late final Future<TainaResult<void>> Function(MirrorPreferences preferences)?
  _persistPreferences;

  final _MirrorChangeNotifier _notifier = _MirrorChangeNotifier();
  late final StreamSubscription<MirrorTransferEvent> _events;
  Future<void> _operationTail = Future<void>.value();
  Future<void>? _deactivation;
  bool _active = false;
  bool _foreground = true;
  bool _disposedTransfer = false;
  bool _notifierDisposed = false;
  bool _reconciling = false;
  bool _quotaPaused = false;
  bool _reconcileScheduled = false;
  bool _reconcileRequested = false;
  bool _refreshRequested = false;
  bool _skipNextPrune = false;
  List<MirrorAsset>? _cachedAssets;
  TainaError? _lastError;
  int _errorRevision = 0;
  Completer<TainaResult<void>>? _reconcileCompleter;
  int _enabledRevision = 0;

  Listenable get changes => _notifier;

  bool get isActive => _active;

  bool get isForeground => _foreground;

  bool get enabled => _enabled;

  bool get wifiOnly => _wifiOnly;

  bool get reconciling => _reconciling;

  TainaError? get lastError => _lastError;

  void setForeground(bool isForeground) {
    if (_foreground == isForeground) return;
    _foreground = isForeground;
    _notifyChanges();
  }

  /// Marks this owner active after the runtime's generation check succeeds.
  void activate() {
    if (_deactivation != null || _disposedTransfer) return;
    if (_active) return;
    _active = true;
    _notifyChanges();
  }

  /// Foreground work shares one queued pass and at most one pending refresh
  /// bit, regardless of how many lifecycle notifications arrive during it.
  Future<TainaResult<void>> reconcile({bool refreshLibrary = true}) {
    if (!_enabled) return Future.value(const Ok<void>(null));
    if (!_active) return Future.value(_inactiveResult());

    final running = _reconcileCompleter;
    if (running != null) {
      _reconcileRequested = true;
      _refreshRequested = _refreshRequested || refreshLibrary;
      return running.future;
    }

    final completer = Completer<TainaResult<void>>();
    _reconcileCompleter = completer;
    _reconcileRequested = true;
    _refreshRequested = _refreshRequested || refreshLibrary;
    _scheduleReconcile();
    return completer.future;
  }

  void _reconcileAutomatically({required bool refreshLibrary}) {
    final reconciliation = reconcile(refreshLibrary: refreshLibrary);
    unawaited(
      reconciliation.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _reportMirrorAsyncError(
            error,
            stackTrace,
            'Automatic owner mirror reconciliation failed.',
          );
        },
      ),
    );
  }

  void _scheduleReconcile() {
    if (_reconcileScheduled || !_active || !_enabled) return;
    _reconcileScheduled = true;
    unawaited(_enqueue(_drainReconciles));
  }

  Future<void> _drainReconciles() async {
    TainaResult<void> result = const Ok<void>(null);
    Object? failure;
    StackTrace? failureStackTrace;
    _setReconciling(true);
    try {
      while (_active && _enabled && _reconcileRequested) {
        _reconcileRequested = false;
        final refreshLibrary = _refreshRequested;
        _refreshRequested = false;
        result = await _runReconcile(refreshLibrary: refreshLibrary);
      }
    } on Exception catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
      rethrow;
    } on Error catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
      rethrow;
    } finally {
      _reconcileScheduled = false;
      _setReconciling(false);
      final completer = _reconcileCompleter;
      _reconcileCompleter = null;
      if (completer != null && !completer.isCompleted) {
        if (failure == null) {
          completer.complete(result);
        } else {
          completer.completeError(failure, failureStackTrace);
        }
      }
      if (failure == null && _active && _reconcileRequested) {
        _scheduleReconcile();
      }
    }
  }

  Future<TainaResult<void>> _runReconcile({
    required bool refreshLibrary,
  }) async {
    if (!_active) return _inactiveResult();
    if (!_enabled) return const Ok<void>(null);
    final initialErrorRevision = _errorRevision;

    final refreshAssets = refreshLibrary || _cachedAssets == null;
    if (refreshAssets) {
      _cachedAssets = null;
      final access = await library.currentAccess();
      if (!_active) return _inactiveResult();
      if (!_enabled) return const Ok<void>(null);
      if (_quotaPaused) return const Ok<void>(null);
      if (access case Err<MirrorLibraryAccess>(:final error)) {
        _cachedAssets = null;
        _recordError(error);
        return Err(error);
      }
      final currentAccess = (access as Ok<MirrorLibraryAccess>).value;
      if (currentAccess != MirrorLibraryAccess.full &&
          currentAccess != MirrorLibraryAccess.limited) {
        _cachedAssets = null;
        const error = MirrorAssetReadError(
          'photo library access is unavailable',
        );
        _recordError(error);
        return const Err(error);
      }
    }

    if (!_active) return _inactiveResult();
    if (!_enabled || _quotaPaused) return const Ok<void>(null);
    final started = await _startTransfer();
    if (!_active) return _inactiveResult();
    if (!_enabled || _quotaPaused) return const Ok<void>(null);
    if (started case Err<void>(:final error)) {
      _recordError(error);
      return Err(error);
    }

    if (refreshAssets) {
      final collected = await _collectAssets();
      if (!_active) return _inactiveResult();
      if (!_enabled || _quotaPaused) return const Ok<void>(null);
      if (collected case Err<List<MirrorAsset>>(:final error)) {
        _recordError(error);
        return Err(error);
      }
      _cachedAssets = List<MirrorAsset>.unmodifiable(
        (collected as Ok<List<MirrorAsset>>).value,
      );
    }

    final assets = _cachedAssets;
    if (assets == null) {
      const error = InvalidResponseError(
        'mirror library snapshot is unavailable',
      );
      _recordError(error);
      return const Err(error);
    }

    if (!_active) return _inactiveResult();
    if (!_enabled || _quotaPaused) return const Ok<void>(null);
    final reconciled = await engine.reconcile(assets);
    if (!_active) return _inactiveResult();
    if (!_enabled || _quotaPaused) return const Ok<void>(null);
    if (reconciled case Err<void>(:final error)) {
      _recordError(error);
      return Err(error);
    }

    if (_skipNextPrune) {
      _skipNextPrune = false;
      return const Ok<void>(null);
    }

    final loaded = await store.load();
    if (!_active) return _inactiveResult();
    if (!_enabled || _quotaPaused) return const Ok<void>(null);
    if (_skipNextPrune) {
      _skipNextPrune = false;
      return const Ok<void>(null);
    }
    if (loaded case Err<MirrorLedger?>(:final error)) {
      _recordError(error);
      return const Ok<void>(null);
    }
    final ledger = (loaded as Ok<MirrorLedger?>).value;
    final retainedPaths = <String>{
      for (final entry in ledger?.entries.values ?? const <MirrorEntry>[])
        if ((!entry.isTerminal || entry.backgroundTaskId != null) &&
            entry.localPath != null)
          entry.localPath!,
    };

    if (!_active) return _inactiveResult();
    if (!_enabled || _quotaPaused) return const Ok<void>(null);
    final pruned = await _prune(retainedPaths);
    if (pruned case Err<void>(:final error)) {
      _recordError(error);
      return const Ok<void>(null);
    }
    if (_errorRevision == initialErrorRevision && !_skipNextPrune) {
      _clearError();
    }
    return const Ok<void>(null);
  }

  Future<TainaResult<void>> _startTransfer() async {
    try {
      return await startTransfer();
    } on Exception catch (error) {
      return Err(NetworkError(error.toString()));
    }
  }

  Future<TainaResult<List<MirrorAsset>>> _collectAssets() async {
    try {
      return await collectMirrorAssets(library);
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  Future<TainaResult<void>> _prune(Set<String> retainedPaths) async {
    try {
      return await materializer.prune(retainedPaths: retainedPaths);
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  void _onTransferEvent(MirrorTransferEvent event) {
    if (!_active) return;
    switch (event) {
      case MirrorTransferProgress(:final assetId, :final taskId, :final value):
        unawaited(
          _enqueue(() async {
            final result = await engine.updateProgress(
              assetId: assetId,
              backgroundTaskId: taskId,
              progress: value,
            );
            _recordResult(result);
            _notifyChanges();
          }),
        );
      case MirrorTransferCompleted(
        :final assetId,
        :final modificationDate,
        :final file,
      ):
        unawaited(
          _enqueue(() async {
            final result = await engine.complete(
              assetId: assetId,
              modificationDate: modificationDate,
              file: file,
            );
            _recordResult(result);
            _notifyChanges();
            if (result.isSuccess && _active && _foreground && _enabled) {
              _reconcileAutomatically(refreshLibrary: false);
            }
          }),
        );
      case MirrorTransferFailed(:final assetId, :final taskId, :final error):
        final quotaExceeded = error is ApiError && error.isQuotaExceeded;
        var notifyQuotaPause = false;
        if (quotaExceeded) {
          _enabledRevision++;
          _quotaPaused = true;
          notifyQuotaPause = _enabled;
          _setEnabled(false, notify: false);
          _reconcileRequested = false;
        }
        final processing = _enqueue(() async {
          final result = await engine.fail(
            assetId: assetId,
            backgroundTaskId: taskId,
            error: error,
          );
          _recordResult(result);
          if (quotaExceeded) {
            await _persistDisableAndCancel();
            _recordError(error);
          } else if (result.isSuccess) {
            _recordError(error);
          }
          _notifyChanges();
        });
        if (notifyQuotaPause) _notifyChanges();
        unawaited(processing);
      case MirrorTransferStreamFailed(:final error):
        _recordError(error);
        _skipNextPrune = true;
        _notifyChanges();
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operationTail.then((_) async {
      if (_active) await operation();
    });
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<TainaResult<void>> setEnabled(bool enabled) async {
    final revision = ++_enabledRevision;
    if (!enabled) _setEnabled(false);

    final result = await _enqueueControl(() async {
      if (!enabled) return _persistDisableAndCancel();

      final persisted = await _persist(
        MirrorPreferences(enabled: enabled, wifiOnly: _wifiOnly),
      );

      if (persisted case Err<void>(:final error)) {
        _recordError(error);
        return Err(error);
      }
      if (revision == _enabledRevision) {
        _quotaPaused = false;
        _setEnabled(true);
      }
      return const Ok<void>(null);
    });

    if (enabled && result.isSuccess && _enabled && _active && _foreground) {
      _reconcileAutomatically(refreshLibrary: true);
    }
    return result;
  }

  Future<TainaResult<void>> setWifiOnly(bool wifiOnly) =>
      _enqueueControl(() async {
        final persisted = await _persist(
          MirrorPreferences(enabled: _enabled, wifiOnly: wifiOnly),
        );
        if (persisted case Err<void>(:final error)) {
          _recordError(error);
          return Err(error);
        }
        if (_wifiOnly == wifiOnly) return const Ok<void>(null);
        _wifiOnly = wifiOnly;
        _notifyChanges();
        return const Ok<void>(null);
      });

  /// Retries cancellation for every ledger entry that still has a native task.
  ///
  /// This does not change the saved preference or remove local data.
  Future<TainaResult<void>> pause() => _enqueueControl(_cancelPendingTasks);

  Future<TainaResult<void>> _persist(MirrorPreferences preferences) async {
    final persist = _persistPreferences;
    if (persist == null) return const Ok<void>(null);
    return persist(preferences);
  }

  Future<TainaResult<void>> _persistDisableAndCancel() async {
    final persisted = await _persist(
      MirrorPreferences(enabled: false, wifiOnly: _wifiOnly),
    );
    final paused = await _cancelPendingTasks();
    if (persisted case Err<void>(:final error)) {
      _recordError(error);
      return Err(error);
    }
    if (paused case Err<void>(:final error)) return Err(error);
    return const Ok<void>(null);
  }

  Future<TainaResult<void>> _cancelPendingTasks() async {
    final loaded = await store.load();
    if (loaded case Err<MirrorLedger?>(:final error)) {
      _recordError(error);
      return Err(error);
    }

    final ledger = (loaded as Ok<MirrorLedger?>).value;
    if (ledger == null) return const Ok<void>(null);
    if (ledger.ownerId != engine.ownerId) {
      const error = InvalidResponseError('mirror ledger owner mismatch');
      _recordError(error);
      return const Err(error);
    }

    TainaError? firstError;
    final entries = ledger.entries.values.toList()
      ..sort((a, b) => a.assetId.compareTo(b.assetId));
    for (final entry in entries) {
      if (entry.backgroundTaskId == null) continue;
      final cancelled = await engine.cancel(assetId: entry.assetId);
      if (cancelled case Err<void>(:final error)) {
        firstError ??= error;
        _recordError(error);
      }
    }
    return firstError == null ? const Ok<void>(null) : Err(firstError);
  }

  Future<TainaResult<void>> _enqueueControl(
    Future<TainaResult<void>> Function() operation,
  ) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _recordResult<T>(TainaResult<T> result) {
    if (result case Err<T>(:final error)) _recordError(error);
  }

  void _recordError(TainaError error) {
    final changed = _lastError != error;
    _lastError = error;
    _errorRevision++;
    if (changed) _notifyChanges();
  }

  void _clearError() {
    if (_lastError == null) return;
    _lastError = null;
    _notifyChanges();
  }

  void _setEnabled(bool enabled, {bool notify = true}) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (notify) _notifyChanges();
  }

  void _setReconciling(bool reconciling) {
    if (_reconciling == reconciling) return;
    _reconciling = reconciling;
    _notifyChanges();
  }

  void _notifyChanges() {
    if (!_notifierDisposed) _notifier.emit();
  }

  /// Deactivation is synchronous up to the event cancellation. It never
  /// clears the ledger or materialized files and does not cancel native tasks.
  Future<void> deactivate() {
    final previous = _deactivation;
    if (previous != null) return previous;

    if (_active) {
      _active = false;
      _notifyChanges();
    }
    const inactive = Err<void>(
      MirrorAssetReadError('mirror owner is inactive'),
    );
    final completer = _reconcileCompleter;
    _reconcileCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(inactive);
    }
    _reconcileRequested = false;
    _refreshRequested = false;

    final cancelledEvents = _events.cancel();
    final deactivation = _finishDeactivation(cancelledEvents);
    _deactivation = deactivation;
    return deactivation;
  }

  Future<void> _finishDeactivation(Future<void> cancelledEvents) async {
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      await cancelledEvents;
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }

    try {
      await _operationTail;
    } catch (error, stackTrace) {
      failure ??= error;
      failureStackTrace ??= stackTrace;
    }

    if (!_disposedTransfer) {
      _disposedTransfer = true;
      try {
        await disposeTransfer();
      } on Exception catch (error) {
        _recordError(MirrorAssetReadError(error.toString()));
      } catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      } finally {
        _notifierDisposed = true;
        _notifier.dispose();
      }
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }

  Future<void> dispose() => deactivate();

  static Err<void> _inactiveResult() =>
      const Err(MirrorAssetReadError('mirror owner is inactive'));
}
