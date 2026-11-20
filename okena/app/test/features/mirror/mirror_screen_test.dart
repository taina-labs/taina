import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/mirror/mirror_screen.dart';
import 'package:okena_app/src/mirror/background_mirror_transfer.dart';
import 'package:okena_app/src/mirror/mirror_library.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_core/okena_core.dart';

import 'mirror_test_support.dart';

final class _RuntimeFixture {
  _RuntimeFixture({
    required this.changes,
    required this.foreground,
    required this.runtime,
  });

  final MirrorTestChanges changes;
  final MirrorTestForeground foreground;
  final MirrorRuntime runtime;

  Future<void> dispose() => runtime.dispose();
}

_RuntimeFixture _runtime({
  required Future<TainaResult<MirrorOwnerMirror>> Function({
    required String ownerId,
    required Me identity,
  })
  ownerFactory,
}) {
  final changes = MirrorTestChanges(mirrorTestIdentity());
  final foreground = MirrorTestForeground();
  final runtime = MirrorRuntime(
    changes: changes,
    identity: () => changes.identity,
    foreground: foreground,
    ownerFactory: ownerFactory,
  );
  runtime.attach();
  return _RuntimeFixture(
    changes: changes,
    foreground: foreground,
    runtime: runtime,
  );
}

_RuntimeFixture _runtimeForOwner(MirrorTestOwner owner) => _runtime(
  ownerFactory: ({required ownerId, required identity}) async =>
      Ok(owner.owner),
);

Widget _app(MirrorRuntime runtime, {VoidCallback? onOpenStorage}) =>
    MaterialApp(
      theme: TainaTheme.data,
      home: MirrorScreen(runtime: runtime, onOpenStorage: onOpenStorage),
    );

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  int attempts = 30,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('widget did not appear: $finder');
}

Future<void> _pumpActions(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _disposeFixture(
  WidgetTester tester,
  _RuntimeFixture fixture,
) async {
  final disposal = fixture.dispose();
  await _pumpActions(tester);
  await disposal;
}

void main() {
  testWidgets('disabled explanation and activation action', (tester) async {
    final owner = makeMirrorTestOwner(ownerId: 'tekoa-test:ava-test');
    final fixture = _runtimeForOwner(owner);
    addTearDown(() async {
      await _disposeFixture(tester, fixture);
      await owner.dispose();
    });

    await tester.pumpWidget(_app(fixture.runtime));
    await _waitFor(tester, find.text('Ligar espelho'));

    expect(find.text('Espelho do rolo de câmera'), findsOneWidget);
    expect(find.text('Desligado neste aparelho'), findsOneWidget);
    expect(
      find.text(
        'O espelho está desligado. O que já foi enviado continua na sua casa.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Fotos e vídeos deste aparelho vão para Rolo de câmera, na sua casa, '
        'e usam o espaço da comunidade. Nada vai para a praça.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'O envio acontece aos poucos, mais rápido com o Tainá aberto. '
        'Apagar do aparelho não apaga a cópia da sua casa.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Ligar espelho'));
    await tester.tap(find.text('Ligar espelho'));
    await _pumpActions(tester);

    expect(owner.library.requestAccessCalls, 1);
    expect(owner.owner.enabled, isTrue);
    expect(find.text('Retomar espelho'), findsNothing);
    expect(find.text('Ver armazenamento'), findsNothing);
  });

  testWidgets('denied access offers settings and activation', (tester) async {
    final owner = makeMirrorTestOwner(
      ownerId: 'tekoa-test:ava-test',
      library: MirrorTestLibrary(access: MirrorLibraryAccess.denied),
    );
    final fixture = _runtimeForOwner(owner);
    addTearDown(() async {
      await _disposeFixture(tester, fixture);
      await owner.dispose();
    });

    await tester.pumpWidget(_app(fixture.runtime));
    await _waitFor(tester, find.text('Abrir Ajustes'));

    expect(find.text('Ligar espelho'), findsOneWidget);
    await tester.ensureVisible(find.text('Abrir Ajustes'));
    await tester.tap(find.text('Abrir Ajustes'));
    await _pumpActions(tester);

    expect(owner.library.settingsCalls, 1);
    expect(find.text('Ligar espelho'), findsOneWidget);

    await tester.ensureVisible(find.text('Ligar espelho'));
    await tester.tap(find.text('Ligar espelho'));
    await _pumpActions(tester);

    expect(owner.library.requestAccessCalls, 1);
    expect(owner.owner.enabled, isTrue);
  });

  testWidgets('limited access offers a limited photo picker', (tester) async {
    final owner = makeMirrorTestOwner(
      ownerId: 'tekoa-test:ava-test',
      enabled: true,
      library: MirrorTestLibrary(access: MirrorLibraryAccess.limited),
    );
    final fixture = _runtimeForOwner(owner);
    addTearDown(() async {
      await _disposeFixture(tester, fixture);
      await owner.dispose();
    });

    await tester.pumpWidget(_app(fixture.runtime));
    await _waitFor(tester, find.text('Escolher mais fotos'));
    expect(
      find.text('O Tainá pode enviar as fotos que você escolheu.'),
      findsOneWidget,
    );
    expect(find.byType(TainaEmptyState), findsOneWidget);

    await tester.ensureVisible(find.text('Escolher mais fotos'));
    await tester.tap(find.text('Escolher mais fotos'));
    await _pumpActions(tester);

    expect(owner.library.limitedPickerCalls, 1);
    expect(owner.library.requestAccessCalls, 0);
  });

  testWidgets('shows progress counts, approximate bytes, and unknown sizes', (
    tester,
  ) async {
    final ledger = mirrorLedger(
      ownerId: 'tekoa-test:ava-test',
      entries: [
        mirrorEntry(
          assetId: 'uploading',
          state: MirrorState.uploading,
          size: 1024,
          progress: 0.5,
        ),
        mirrorEntry(assetId: 'unknown', state: MirrorState.queued, size: null),
      ],
    );
    final owner = makeMirrorTestOwner(
      ownerId: 'tekoa-test:ava-test',
      enabled: true,
      store: MirrorTestStore(ledger: ledger),
    );
    final fixture = _runtimeForOwner(owner);
    addTearDown(() async {
      await _disposeFixture(tester, fixture);
      await owner.dispose();
    });

    await tester.pumpWidget(_app(fixture.runtime));
    await _waitFor(tester, find.text('Enviando fotos e vídeos'));

    expect(
      find.text('0 já estão na sua casa; 2 ainda faltam.'),
      findsOneWidget,
    );
    expect(find.text('Faltam cerca de 512 B.'), findsOneWidget);
    expect(
      find.text('O tamanho de alguns arquivos ainda está sendo calculado.'),
      findsOneWidget,
    );
  });

  testWidgets('Wi-Fi preference explains upcoming mobile-data use', (
    tester,
  ) async {
    final owner = makeMirrorTestOwner(
      ownerId: 'tekoa-test:ava-test',
      enabled: true,
    );
    final fixture = _runtimeForOwner(owner);
    addTearDown(() async {
      await _disposeFixture(tester, fixture);
      await owner.dispose();
    });

    await tester.pumpWidget(_app(fixture.runtime));
    await _waitFor(tester, find.byType(Switch, skipOffstage: false));
    await tester.ensureVisible(find.byType(Switch, skipOffstage: false));
    await tester.pump();
    expect(
      find.text(
        'Esta escolha vale para os próximos envios.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(Switch, skipOffstage: false));
    await _pumpActions(tester);

    expect(owner.owner.wifiOnly, isFalse);
    expect(
      find.text(
        'Esta escolha vale para os próximos envios, que também podem usar '
        'dados móveis.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('quota pause leads to storage', (tester) async {
    var openedStorage = false;
    final ledger = mirrorLedger(
      ownerId: 'tekoa-test:ava-test',
      entries: [mirrorEntry(assetId: 'asset-a', state: MirrorState.uploading)],
    );
    final owner = makeMirrorTestOwner(
      ownerId: 'tekoa-test:ava-test',
      enabled: true,
      store: MirrorTestStore(ledger: ledger),
      persistPreferences: (_) async => const Ok<void>(null),
    );
    final fixture = _runtimeForOwner(owner);
    addTearDown(() async {
      await _disposeFixture(tester, fixture);
      await owner.dispose();
    });

    await tester.pumpWidget(
      _app(fixture.runtime, onOpenStorage: () => openedStorage = true),
    );
    await _waitFor(tester, find.byType(Switch, skipOffstage: false));
    owner.events.add(
      const MirrorTransferFailed(
        assetId: 'asset-a',
        taskId: 'task-asset-a',
        error: mirrorQuotaError,
      ),
    );
    await _waitFor(
      tester,
      find.text(
        'Pausado: a comunidade atingiu o limite de espaço. Nada foi apagado.',
      ),
    );

    expect(find.text('Converse com quem cuida da caixa.'), findsOneWidget);
    expect(find.text('Retomar espelho'), findsOneWidget);
    expect(owner.library.requestAccessCalls, 0);
    await tester.ensureVisible(find.text('Ver armazenamento'));
    await tester.tap(find.text('Ver armazenamento'));
    await tester.pump();

    expect(openedStorage, isTrue);
    expect(owner.owner.enabled, isFalse);

    await tester.ensureVisible(find.text('Retomar espelho'));
    await tester.tap(find.text('Retomar espelho'));
    await _pumpActions(tester);

    expect(owner.library.requestAccessCalls, 1);
    expect(owner.owner.enabled, isTrue);
  });

  testWidgets('ordinary failure offers retry without saying it is paused', (
    tester,
  ) async {
    final owner = makeMirrorTestOwner(
      ownerId: 'tekoa-test:ava-test',
      enabled: true,
    );
    final fixture = _runtimeForOwner(owner);
    addTearDown(() async {
      await _disposeFixture(tester, fixture);
      await owner.dispose();
    });

    await tester.pumpWidget(_app(fixture.runtime));
    await _waitFor(tester, find.byType(Switch, skipOffstage: false));
    owner.events.add(
      const MirrorTransferStreamFailed(error: mirrorOfflineError),
    );
    await _waitFor(tester, find.text('Tentar de novo'));

    expect(find.textContaining('Pausado:'), findsNothing);
    await tester.ensureVisible(find.text('Tentar de novo'));
    await tester.tap(find.text('Tentar de novo'));
    await _pumpActions(tester);

    expect(find.text('Não foi possível continuar o envio.'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('factory loading and error states can be retried', (
    tester,
  ) async {
    final firstFactory = Completer<TainaResult<MirrorOwnerMirror>>();
    final owner = makeMirrorTestOwner(ownerId: 'tekoa-test:ava-test');
    var factoryCalls = 0;
    final fixture = _runtime(
      ownerFactory: ({required ownerId, required identity}) async {
        factoryCalls++;
        if (factoryCalls == 1) return firstFactory.future;
        return Ok(owner.owner);
      },
    );
    addTearDown(() async {
      await _disposeFixture(tester, fixture);
      await owner.dispose();
    });

    await tester.pumpWidget(_app(fixture.runtime));
    await tester.pump();
    expect(find.byType(TainaLoadingList), findsOneWidget);

    firstFactory.complete(const Err(mirrorOfflineError));
    await _waitFor(tester, find.byType(TainaErrorState));
    expect(find.text(mirrorOfflineError.message), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await _pumpActions(tester);

    expect(factoryCalls, 2);
    expect(find.byType(TainaErrorState), findsNothing);
    expect(find.text('Desligado neste aparelho'), findsOneWidget);
  });

  testWidgets('resume re-reads current access without requesting it', (
    tester,
  ) async {
    final owner = makeMirrorTestOwner(
      ownerId: 'tekoa-test:ava-test',
      library: MirrorTestLibrary(access: MirrorLibraryAccess.full),
    );
    final fixture = _runtimeForOwner(owner);
    addTearDown(() async {
      await _disposeFixture(tester, fixture);
      await owner.dispose();
    });

    await tester.pumpWidget(_app(fixture.runtime));
    await _waitFor(tester, find.text('Ligar espelho'));
    final readsBeforeResume = owner.library.currentAccessCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpActions(tester);

    expect(owner.library.currentAccessCalls, greaterThan(readsBeforeResume));
    expect(owner.library.requestAccessCalls, 0);
  });
}
