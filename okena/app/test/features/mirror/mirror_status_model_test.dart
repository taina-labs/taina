import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/mirror/mirror_status_model.dart';
import 'package:okena_app/src/mirror/background_mirror_transfer.dart';
import 'package:okena_app/src/mirror/mirror_library.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_app/src/mirror/mirror_settings.dart';
import 'package:okena_core/okena_core.dart';

import 'mirror_test_support.dart';

final class _RuntimeHarness extends ChangeNotifier {
  MirrorOwnerMirror? owner;
  TainaError? error;
  Future<void> Function()? onRefresh;

  void setOwner(MirrorOwnerMirror? value) {
    owner = value;
    notifyListeners();
  }

  void setError(TainaError? value) {
    error = value;
    notifyListeners();
  }

  Future<void> refresh() async {
    await onRefresh?.call();
  }
}

MirrorStatusModel _model(_RuntimeHarness runtime) => MirrorStatusModel(
  runtimeChanges: runtime,
  currentOwner: () => runtime.owner,
  runtimeError: () => runtime.error,
  refreshRuntime: runtime.refresh,
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('condition did not become true');
}

void main() {
  group('MirrorStatusModel', () {
    test('reads current access without requesting permission', () async {
      final made = makeMirrorTestOwner(
        ownerId: 'tekoa-test:ava-test',
        library: MirrorTestLibrary(access: MirrorLibraryAccess.notDetermined),
      );
      addTearDown(made.dispose);
      final runtime = _RuntimeHarness()..owner = made.owner;
      final model = _model(runtime);
      addTearDown(model.dispose);

      await _waitFor(() => !model.loading);

      expect(model.access, MirrorLibraryAccess.notDetermined);
      expect(made.library.currentAccessCalls, 1);
      expect(made.library.requestAccessCalls, 0);
    });

    for (final access in [
      MirrorLibraryAccess.full,
      MirrorLibraryAccess.limited,
    ]) {
      test('enables after a user request with $access access', () async {
        final made = makeMirrorTestOwner(
          ownerId: 'tekoa-test:ava-test',
          library: MirrorTestLibrary(requestedAccess: access),
        );
        addTearDown(made.dispose);
        final runtime = _RuntimeHarness()..owner = made.owner;
        final model = _model(runtime);
        addTearDown(model.dispose);
        await _waitFor(() => !model.loading);

        await model.enable();

        expect(made.library.requestAccessCalls, 1);
        expect(model.access, access);
        expect(made.owner.enabled, isTrue);
        expect(model.enabled, isTrue);
      });
    }

    test('does not enable after denied permission', () async {
      final made = makeMirrorTestOwner(
        ownerId: 'tekoa-test:ava-test',
        library: MirrorTestLibrary(requestedAccess: MirrorLibraryAccess.denied),
      );
      addTearDown(made.dispose);
      final runtime = _RuntimeHarness()..owner = made.owner;
      final model = _model(runtime);
      addTearDown(model.dispose);
      await _waitFor(() => !model.loading);

      await model.enable();

      expect(made.library.requestAccessCalls, 1);
      expect(made.owner.enabled, isFalse);
      expect(model.access, MirrorLibraryAccess.denied);
      expect(model.permissionNeedsSettings, isTrue);
    });

    test(
      'reloads summary after owner changes following a ledger write',
      () async {
        final ledger = mirrorLedger(
          ownerId: 'tekoa-test:ava-test',
          entries: [mirrorEntry(assetId: 'asset-a', state: MirrorState.queued)],
        );
        final store = MirrorTestStore();
        await store.save(ledger);
        final made = makeMirrorTestOwner(
          ownerId: 'tekoa-test:ava-test',
          store: store,
        );
        addTearDown(made.dispose);
        final runtime = _RuntimeHarness()..owner = made.owner;
        final model = _model(runtime);
        addTearDown(model.dispose);
        await _waitFor(() => model.summary?.pendingCount == 1);

        await made.store.save(
          mirrorLedger(
            ownerId: 'tekoa-test:ava-test',
            entries: [
              mirrorEntry(assetId: 'asset-a', state: MirrorState.uploaded),
            ],
          ),
        );
        await made.owner.setWifiOnly(false);

        await _waitFor(() => model.summary?.storedCount == 1);
        expect(model.summary!.pendingCount, 0);
      },
    );

    test(
      'disable and Wi-Fi changes delegate and retain returned failures',
      () async {
        final saved = <MirrorPreferences>[];
        final made = makeMirrorTestOwner(
          ownerId: 'tekoa-test:ava-test',
          enabled: true,
          wifiOnly: true,
          persistPreferences: (preferences) async {
            saved.add(preferences);
            if (!preferences.wifiOnly) return const Err(mirrorOfflineError);
            return const Ok<void>(null);
          },
        );
        addTearDown(made.dispose);
        final runtime = _RuntimeHarness()..owner = made.owner;
        final model = _model(runtime);
        addTearDown(model.dispose);
        await _waitFor(() => !model.loading);

        await model.disable();
        expect(made.owner.enabled, isFalse);
        expect(saved.first.enabled, isFalse);

        await model.setWifiOnly(false);
        expect(made.owner.wifiOnly, isTrue);
        expect(model.actionableMessage, mirrorOfflineError.message);
        expect(
          saved.last,
          const MirrorPreferences(enabled: false, wifiOnly: false),
        );
      },
    );

    test(
      'limited picker and settings reload current access without prompting',
      () async {
        final made = makeMirrorTestOwner(
          ownerId: 'tekoa-test:ava-test',
          library: MirrorTestLibrary(access: MirrorLibraryAccess.limited),
        );
        addTearDown(made.dispose);
        final runtime = _RuntimeHarness()..owner = made.owner;
        final model = _model(runtime);
        addTearDown(model.dispose);
        await _waitFor(() => !model.loading);

        await model.chooseMore();
        await model.openSettings();

        expect(made.library.limitedPickerCalls, 1);
        expect(made.library.settingsCalls, 1);
        expect(made.library.requestAccessCalls, 0);
        expect(made.library.currentAccessCalls, 3);
        expect(model.access, MirrorLibraryAccess.limited);
      },
    );

    test('owner notifications reload summary but not native access', () async {
      final ledger = mirrorLedger(
        ownerId: 'tekoa-test:ava-test',
        entries: [
          mirrorEntry(
            assetId: 'asset-a',
            state: MirrorState.uploading,
            size: 100,
          ),
        ],
      );
      final made = makeMirrorTestOwner(
        ownerId: 'tekoa-test:ava-test',
        store: MirrorTestStore(ledger: ledger),
      );
      addTearDown(made.dispose);
      final runtime = _RuntimeHarness()..owner = made.owner;
      final model = _model(runtime);
      addTearDown(model.dispose);
      await _waitFor(() => model.summary?.pendingCount == 1);
      final initialReads = made.store.loadCalls;

      made.events.add(
        const MirrorTransferProgress(
          assetId: 'asset-a',
          taskId: 'task-asset-a',
          value: 0.5,
        ),
      );

      await _waitFor(() => model.summary?.knownPendingBytes == 50);
      expect(made.store.loadCalls, greaterThan(initialReads));
      expect(made.library.currentAccessCalls, 1);
    });

    test(
      'retry refreshes a missing owner through the runtime factory seam',
      () async {
        final runtime = _RuntimeHarness();
        final made = makeMirrorTestOwner(ownerId: 'tekoa-test:ava-test');
        addTearDown(made.dispose);
        var refreshCalls = 0;
        runtime.onRefresh = () async {
          refreshCalls++;
          runtime.setOwner(made.owner);
        };
        final model = _model(runtime);
        addTearDown(model.dispose);

        await model.retry();
        await _waitFor(() => !model.loading);

        expect(refreshCalls, 1);
        expect(model.owner, same(made.owner));
        expect(model.summary?.totalEntries, 0);
      },
    );

    test('ignores permission and summary results from a stale owner', () async {
      final accessGate = Completer<TainaResult<MirrorLibraryAccess>>();
      final ledgerA = mirrorLedger(
        ownerId: 'tekoa-test:ava-test',
        entries: [mirrorEntry(assetId: 'old', state: MirrorState.queued)],
      );
      final ownerA = makeMirrorTestOwner(
        ownerId: 'tekoa-test:ava-test',
        store: MirrorTestStore(ledger: ledgerA),
        library: MirrorTestLibrary(
          currentAccessHandler: () => accessGate.future,
        ),
      );
      addTearDown(ownerA.dispose);
      final ownerB = makeMirrorTestOwner(
        ownerId: 'tekoa-next:ava-test',
        store: MirrorTestStore(
          ledger: mirrorLedger(
            ownerId: 'tekoa-next:ava-test',
            entries: [mirrorEntry(assetId: 'new', state: MirrorState.uploaded)],
          ),
        ),
      );
      addTearDown(ownerB.dispose);
      final runtime = _RuntimeHarness()..owner = ownerA.owner;
      final model = _model(runtime);
      addTearDown(model.dispose);
      await _waitFor(() => ownerA.library.currentAccessCalls == 1);

      runtime.setOwner(ownerB.owner);
      await _waitFor(() => model.summary?.storedCount == 1);
      accessGate.complete(const Ok(MirrorLibraryAccess.denied));
      await Future<void>.delayed(Duration.zero);

      expect(model.owner, same(ownerB.owner));
      expect(model.access, MirrorLibraryAccess.full);
      expect(model.summary!.pendingCount, 0);
    });

    test('quota error wins over the persisted disabled state', () {
      final presentation = mirrorStatusPresentation(
        enabled: false,
        access: MirrorLibraryAccess.full,
        reconciling: false,
        summary: null,
        error: mirrorQuotaError,
      );

      expect(presentation.kind, MirrorStatusKind.quotaPaused);
      expect(
        presentation.title,
        'Pausado: a comunidade atingiu o limite de espaço. Nada foi apagado.',
      );
    });

    test('suppressed assets are not described as stored or pending', () {
      final summary = MirrorSummary.fromLedger(
        mirrorLedger(
          ownerId: 'tekoa-test:ava-test',
          entries: [
            mirrorEntry(assetId: 'suppressed', state: MirrorState.suppressed),
          ],
        ),
      );

      expect(summary.suppressedCount, 1);
      expect(summary.storedCount, 0);
      expect(summary.pendingCount, 0);
      expect(
        mirrorProgressMessage(summary),
        '0 já estão na sua casa; 0 ainda faltam.',
      );
    });

    test(
      'quota resume requests access and explicitly enables the mirror',
      () async {
        final saved = <MirrorPreferences>[];
        final ledger = mirrorLedger(
          ownerId: 'tekoa-test:ava-test',
          entries: [
            mirrorEntry(assetId: 'asset-a', state: MirrorState.uploading),
          ],
        );
        final made = makeMirrorTestOwner(
          ownerId: 'tekoa-test:ava-test',
          enabled: true,
          store: MirrorTestStore(ledger: ledger),
          persistPreferences: (preferences) async {
            saved.add(preferences);
            return const Ok<void>(null);
          },
        );
        addTearDown(made.dispose);
        final runtime = _RuntimeHarness()..owner = made.owner;
        final model = _model(runtime);
        addTearDown(model.dispose);
        await _waitFor(() => !model.loading);

        made.events.add(
          const MirrorTransferFailed(
            assetId: 'asset-a',
            taskId: 'task-asset-a',
            error: mirrorQuotaError,
          ),
        );
        await _waitFor(
          () => model.presentation.kind == MirrorStatusKind.quotaPaused,
        );

        expect(model.canResumeQuota, isTrue);
        expect(made.owner.enabled, isFalse);
        expect(made.library.requestAccessCalls, 0);
        expect(saved.last.enabled, isFalse);

        await model.resumeQuota();

        expect(made.library.requestAccessCalls, 1);
        expect(made.owner.enabled, isTrue);
        expect(saved.last.enabled, isTrue);
        expect(model.canResumeQuota, isFalse);
      },
    );
  });
}
