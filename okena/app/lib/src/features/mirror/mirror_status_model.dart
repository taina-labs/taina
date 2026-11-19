// Public test seams use named parameters to keep dependency roles explicit.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:okena_app/src/mirror/mirror_library.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_core/okena_core.dart';

typedef MirrorOwnerReader = MirrorOwnerMirror? Function();
typedef MirrorErrorReader = TainaError? Function();
typedef MirrorRuntimeRefresh = Future<void> Function();

enum MirrorStatusKind {
  quotaPaused,
  permissionRevoked,
  disabled,
  preparing,
  sending,
  idle,
  failed,
}

final class MirrorStatusPresentation {
  const MirrorStatusPresentation({required this.kind, required this.title});

  final MirrorStatusKind kind;
  final String title;
}

/// The current mirror view state and the actions available on its screen.
///
/// Runtime and owner listeners are the imperative edges. The status and copy
/// decisions are pure functions over the values they expose.
final class MirrorStatusModel extends ChangeNotifier {
  MirrorStatusModel({
    required Listenable runtimeChanges,
    required MirrorOwnerReader currentOwner,
    required MirrorErrorReader runtimeError,
    required MirrorRuntimeRefresh refreshRuntime,
  }) : _runtimeChanges = runtimeChanges,
       _currentOwner = currentOwner,
       _runtimeError = runtimeError,
       _refreshRuntime = refreshRuntime {
    _runtimeChanges.addListener(_onRuntimeChanged);
    _replaceOwner(_currentOwner());
  }

  factory MirrorStatusModel.fromRuntime(MirrorRuntime runtime) =>
      MirrorStatusModel(
        runtimeChanges: runtime.changes,
        currentOwner: () => runtime.currentOwner,
        runtimeError: () => runtime.lastError,
        refreshRuntime: runtime.refresh,
      );

  final Listenable _runtimeChanges;
  final MirrorOwnerReader _currentOwner;
  final MirrorErrorReader _runtimeError;
  final MirrorRuntimeRefresh _refreshRuntime;

  MirrorOwnerMirror? _owner;
  MirrorSummary? _summary;
  MirrorLibraryAccess? _access;
  TainaError? _summaryError;
  TainaError? _actionError;
  bool _loading = true;
  bool _accessLoading = false;
  bool _actionRunning = false;
  bool _disposed = false;
  bool _enabled = false;
  bool _wifiOnly = true;
  bool _reconciling = false;
  int _ownerRevision = 0;
  int _summaryRequest = 0;
  int _accessRequest = 0;
  int _actionRevision = 0;

  MirrorOwnerMirror? get owner => _owner;
  MirrorSummary? get summary => _summary;
  MirrorLibraryAccess? get access => _access;
  bool get loading => _loading;
  bool get accessLoading => _accessLoading;
  bool get actionRunning => _actionRunning;
  TainaError? get actionError => _actionError;
  bool get enabled => _enabled;
  bool get wifiOnly => _wifiOnly;
  bool get reconciling => _reconciling;

  TainaError? get lastError {
    final ownerError = _owner?.lastError;
    final runtimeError = _runtimeError();
    for (final error in [
      ownerError,
      runtimeError,
      _actionError,
      _summaryError,
    ]) {
      if (error case ApiError(isQuotaExceeded: true)) return error;
    }
    return _actionError ?? _summaryError ?? ownerError ?? runtimeError;
  }

  String? get actionableMessage => lastError?.message;

  MirrorStatusPresentation get presentation => mirrorStatusPresentation(
    enabled: _enabled,
    access: _access,
    reconciling: _reconciling,
    summary: _summary,
    error: lastError,
  );

  bool get permissionNeedsSettings =>
      _access == MirrorLibraryAccess.denied ||
      _access == MirrorLibraryAccess.restricted;

  bool get hasLimitedAccess => _access == MirrorLibraryAccess.limited;
  bool get canEnable =>
      !_enabled &&
      !permissionNeedsSettings &&
      presentation.kind != MirrorStatusKind.quotaPaused;
  bool get canResumeQuota =>
      !_enabled && presentation.kind == MirrorStatusKind.quotaPaused;
  bool get canOpenSettings =>
      permissionNeedsSettings ||
      presentation.kind == MirrorStatusKind.permissionRevoked;
  bool get canDisable =>
      _enabled && presentation.kind != MirrorStatusKind.quotaPaused;
  bool get canChooseMore =>
      hasLimitedAccess && presentation.kind != MirrorStatusKind.quotaPaused;
  bool get canOpenStorage => presentation.kind == MirrorStatusKind.quotaPaused;
  bool get canRetry =>
      presentation.kind == MirrorStatusKind.failed &&
      (_owner?.lastError != null ||
          _summaryError != null ||
          (_summary?.failedCount ?? 0) > 0);
  bool get showEmptyState =>
      _enabled &&
      _summary?.totalEntries == 0 &&
      presentation.kind == MirrorStatusKind.idle;

  String get statusMessage =>
      mirrorStatusMessage(kind: presentation.kind, error: lastError);

  /// Reads permission state without presenting a system prompt.
  ///
  /// Screens call this on lifecycle resume because the person may have changed
  /// photo access in system settings.
  Future<void> reloadAccess() async {
    final owner = _owner;
    if (owner == null) return;

    final revision = _ownerRevision;
    final accessRequest = ++_accessRequest;
    _accessLoading = true;
    _notify();
    final result = await owner.library.currentAccess();
    if (!_isCurrent(owner, revision) || accessRequest != _accessRequest) return;
    _accessLoading = false;
    switch (result) {
      case Ok<MirrorLibraryAccess>(:final value):
        _access = value;
        _actionError = null;
      case Err<MirrorLibraryAccess>(:final error):
        _actionError = error;
    }
    _notify();
  }

  Future<void> enable() => _runOwnerAction((owner, revision) async {
    final accessRequest = ++_accessRequest;
    final requested = await owner.library.requestAccess();
    if (!_isCurrent(owner, revision) || accessRequest != _accessRequest) return;
    switch (requested) {
      case Err<MirrorLibraryAccess>(:final error):
        _actionError = error;
      case Ok<MirrorLibraryAccess>(:final value):
        _access = value;
        if (value == MirrorLibraryAccess.full ||
            value == MirrorLibraryAccess.limited) {
          _recordActionResult(await owner.setEnabled(true), owner, revision);
        }
    }
    _notify();
  });

  Future<void> resumeQuota() => enable();

  Future<void> disable() => _runOwnerAction((owner, revision) async {
    _recordActionResult(await owner.setEnabled(false), owner, revision);
    _notify();
  });

  Future<void> setWifiOnly(bool wifiOnly) =>
      _runOwnerAction((owner, revision) async {
        _recordActionResult(await owner.setWifiOnly(wifiOnly), owner, revision);
        _notify();
      });

  Future<void> chooseMore() => _runOwnerAction((owner, revision) async {
    if (_access != MirrorLibraryAccess.limited) return;
    final selected = await owner.library.presentLimitedSelection();
    _recordActionResult(selected, owner, revision);
    if (!_isCurrent(owner, revision)) return;
    if (selected case Err<void>()) return;
    await _reloadAccessFor(owner, revision);
    if (owner.enabled) {
      _recordActionResult(
        await owner.reconcile(refreshLibrary: true),
        owner,
        revision,
      );
      await _reloadSummaryFor(owner, revision);
    }
    _notify();
  });

  Future<void> openSettings() => _runOwnerAction((owner, revision) async {
    _recordActionResult(await owner.library.openSettings(), owner, revision);
    if (!_isCurrent(owner, revision)) return;
    await _reloadAccessFor(owner, revision);
    _notify();
  });

  /// Retries owner creation, or refreshes the current enabled mirror.
  Future<void> retry() async {
    if (_disposed || _actionRunning) return;
    final actionRevision = ++_actionRevision;
    _actionRunning = true;
    _actionError = null;
    _notify();
    try {
      var owner = _owner;
      var ownerRevision = _ownerRevision;
      if (owner == null) {
        await _refreshRuntime();
        if (_disposed || actionRevision != _actionRevision) return;
        owner = _owner;
        ownerRevision = _ownerRevision;
        if (owner == null) {
          _actionError = _runtimeError();
          return;
        }
      }

      if (owner.enabled && _isCurrent(owner, ownerRevision)) {
        _recordActionResult(
          await owner.reconcile(refreshLibrary: true),
          owner,
          ownerRevision,
        );
      }
      if (_isCurrent(owner, ownerRevision)) {
        await _reloadSummaryFor(owner, ownerRevision);
      }
    } on Exception catch (error) {
      if (!_disposed && actionRevision == _actionRevision) {
        _actionError = MirrorAssetReadError(error.toString());
      }
    } finally {
      if (!_disposed && actionRevision == _actionRevision) {
        _actionRunning = false;
        _notify();
      }
    }
  }

  Future<void> _runOwnerAction(
    Future<void> Function(MirrorOwnerMirror owner, int revision) action,
  ) async {
    final owner = _owner;
    if (_disposed || owner == null || _actionRunning) return;
    final ownerRevision = _ownerRevision;
    final actionRevision = ++_actionRevision;
    _actionRunning = true;
    _actionError = null;
    _notify();
    try {
      await action(owner, ownerRevision);
    } on Exception catch (error) {
      if (_isCurrent(owner, ownerRevision)) {
        _actionError = MirrorAssetReadError(error.toString());
      }
    } finally {
      if (!_disposed && actionRevision == _actionRevision) {
        _actionRunning = false;
        _notify();
      }
    }
  }

  void _recordActionResult<T>(
    TainaResult<T> result,
    MirrorOwnerMirror owner,
    int revision,
  ) {
    if (!_isCurrent(owner, revision)) return;
    switch (result) {
      case Ok<T>():
        _actionError = null;
      case Err<T>(:final error):
        _actionError = error;
    }
  }

  Future<void> _reloadAccessFor(MirrorOwnerMirror owner, int revision) async {
    final accessRequest = ++_accessRequest;
    final result = await owner.library.currentAccess();
    if (!_isCurrent(owner, revision) || accessRequest != _accessRequest) return;
    switch (result) {
      case Ok<MirrorLibraryAccess>(:final value):
        _access = value;
      case Err<MirrorLibraryAccess>(:final error):
        _actionError = error;
    }
  }

  Future<void> _reloadSummaryFor(MirrorOwnerMirror owner, int revision) async {
    final request = ++_summaryRequest;
    final loaded = await owner.store.load();
    if (!_isCurrent(owner, revision) || request != _summaryRequest) return;
    switch (loaded) {
      case Err<MirrorLedger?>(:final error):
        _summaryError = error;
      case Ok<MirrorLedger?>(:final value):
        _summary = MirrorSummary.fromLedger(
          value ?? MirrorLedger(ownerId: owner.engine.ownerId),
        );
        _summaryError = null;
    }
    _notify();
  }

  void _onRuntimeChanged() {
    if (_disposed) return;
    final current = _currentOwner();
    if (!identical(current, _owner)) {
      _replaceOwner(current);
      return;
    }
    if (current == null) _loading = _runtimeError() == null;
    _notify();
  }

  void _onOwnerChanged() {
    final owner = _owner;
    if (owner == null || _disposed) return;
    _copyOwnerState(owner);
    _notify();
    unawaited(_reloadSummaryFor(owner, _ownerRevision));
  }

  void _replaceOwner(MirrorOwnerMirror? owner) {
    _owner?.changes.removeListener(_onOwnerChanged);
    _owner = owner;
    final revision = ++_ownerRevision;
    _summaryRequest++;
    _accessRequest++;
    _summary = null;
    _access = null;
    _accessLoading = false;
    _summaryError = null;
    _actionError = null;
    _copyOwnerState(owner);
    if (owner == null) {
      _loading = _runtimeError() == null;
      _notify();
      return;
    }

    owner.changes.addListener(_onOwnerChanged);
    _loading = true;
    _notify();
    final summaryRequest = ++_summaryRequest;
    final accessRequest = ++_accessRequest;
    unawaited(_loadOwner(owner, revision, summaryRequest, accessRequest));
  }

  Future<void> _loadOwner(
    MirrorOwnerMirror owner,
    int revision,
    int summaryRequest,
    int accessRequest,
  ) async {
    final access = owner.library.currentAccess();
    final ledger = owner.store.load();
    final results = await Future.wait<Object>([access, ledger]);
    if (!_isCurrent(owner, revision)) return;
    if (accessRequest == _accessRequest) {
      switch (results[0] as TainaResult<MirrorLibraryAccess>) {
        case Ok<MirrorLibraryAccess>(:final value):
          _access = value;
        case Err<MirrorLibraryAccess>(:final error):
          _actionError = error;
      }
    }
    if (summaryRequest == _summaryRequest) {
      switch (results[1] as TainaResult<MirrorLedger?>) {
        case Err<MirrorLedger?>(:final error):
          _summaryError = error;
        case Ok<MirrorLedger?>(:final value):
          _summary = MirrorSummary.fromLedger(
            value ?? MirrorLedger(ownerId: owner.engine.ownerId),
          );
          _summaryError = null;
      }
    }
    _loading = false;
    _notify();
  }

  void _copyOwnerState(MirrorOwnerMirror? owner) {
    _enabled = owner?.enabled ?? false;
    _wifiOnly = owner?.wifiOnly ?? true;
    _reconciling = owner?.reconciling ?? false;
  }

  bool _isCurrent(MirrorOwnerMirror owner, int revision) =>
      !_disposed && identical(_owner, owner) && _ownerRevision == revision;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _runtimeChanges.removeListener(_onRuntimeChanged);
    _owner?.changes.removeListener(_onOwnerChanged);
    super.dispose();
  }
}

MirrorStatusPresentation mirrorStatusPresentation({
  required bool enabled,
  required MirrorLibraryAccess? access,
  required bool reconciling,
  required MirrorSummary? summary,
  required TainaError? error,
}) {
  if (error case ApiError(isQuotaExceeded: true)) {
    return const MirrorStatusPresentation(
      kind: MirrorStatusKind.quotaPaused,
      title:
          'Pausado: a comunidade atingiu o limite de espaço. Nada foi apagado.',
    );
  }
  if (enabled &&
      (access == MirrorLibraryAccess.denied ||
          access == MirrorLibraryAccess.restricted ||
          access == MirrorLibraryAccess.notDetermined)) {
    return const MirrorStatusPresentation(
      kind: MirrorStatusKind.permissionRevoked,
      title: 'Pausado: o Tainá não tem acesso às suas fotos',
    );
  }
  if (!enabled) {
    return const MirrorStatusPresentation(
      kind: MirrorStatusKind.disabled,
      title: 'Desligado neste aparelho',
    );
  }
  if (reconciling || summary == null) {
    return const MirrorStatusPresentation(
      kind: MirrorStatusKind.preparing,
      title: 'Preparando arquivos...',
    );
  }
  if (summary.uploadingCount > 0) {
    return const MirrorStatusPresentation(
      kind: MirrorStatusKind.sending,
      title: 'Enviando fotos e vídeos',
    );
  }
  if (summary.pendingCount == 0 && error == null) {
    return const MirrorStatusPresentation(
      kind: MirrorStatusKind.idle,
      title: 'Nada para enviar agora',
    );
  }
  return const MirrorStatusPresentation(
    kind: MirrorStatusKind.failed,
    title: 'Não foi possível continuar o envio.',
  );
}

String mirrorProgressMessage(MirrorSummary summary) =>
    '${summary.storedCount} ${summary.storedCount == 1 ? 'já está' : 'já estão'} '
    'na sua casa; ${summary.pendingCount} ${summary.pendingCount == 1 ? 'ainda falta' : 'ainda faltam'}.';

String mirrorStatusMessage({
  required MirrorStatusKind kind,
  required TainaError? error,
}) => switch (kind) {
  MirrorStatusKind.quotaPaused => 'Converse com quem cuida da caixa.',
  MirrorStatusKind.permissionRevoked =>
    'Abra os ajustes do aparelho e permita o acesso às fotos para continuar.',
  MirrorStatusKind.disabled =>
    'O espelho está desligado. O que já foi enviado continua na sua casa.',
  MirrorStatusKind.preparing =>
    'O Tainá está organizando os arquivos para o envio.',
  MirrorStatusKind.sending =>
    'Os envios seguem aos poucos, mais rápido com o Tainá aberto.',
  MirrorStatusKind.idle =>
    'Quando houver fotos e vídeos novos, o envio continua.',
  MirrorStatusKind.failed => error?.message ?? 'Não foi possível enviar agora.',
};
