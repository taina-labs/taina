import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/storage/storage_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

final class _StorageApi implements TainaApi {
  _StorageApi(this._inner, this.value);

  final TainaApi _inner;
  final StorageStats value;

  @override
  Future<TainaResult<StorageStats>> storage() async => Ok(value);

  @override
  Future<TainaResult<Me>> me() => _inner.me();

  @override
  Future<TainaResult<Page<Ava>>> members() => _inner.members();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const StorageByKind _noKinds = StorageByKind(
  photos: 0,
  videos: 0,
  documents: 0,
  others: 0,
);

const StorageStats _zoned = StorageStats(
  usedBytes: 1000,
  quotaBytes: 2000,
  byZone: StorageByZone(casa: 700, praca: 200, lixeira: 100),
  byKind: _noKinds,
  files: 4,
  photos: 1,
  trash: StorageTrash(count: 1, bytes: 100),
);

Widget _app(SessionGateway session) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: StorageScreen(session: session),
  );
}

void _large(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('morador sees the full community card and explanation', (
    tester,
  ) async {
    _large(tester);
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    expect(find.text('Espaço da comunidade'), findsOneWidget);
    expect(find.textContaining(' de '), findsWidgets);
    expect(find.text('Mudar limite'), findsNothing);
    expect(
      find.textContaining('Quem cuida da caixa escolhe quanto'),
      findsOneWidget,
    );
    expect(find.textContaining('por pessoa'), findsNothing);
    expect(find.text('O que ocupa espaço'), findsNothing);
  });

  testWidgets('renders zone rows only when they partition used bytes', (
    tester,
  ) async {
    _large(tester);
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    final _StorageApi api = _StorageApi(inner, _zoned);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(joana))));
    await tester.pumpAndSettle();

    expect(find.text('O que ocupa espaço'), findsOneWidget);
    expect(find.text('Casas (de cada morador)'), findsOneWidget);
    expect(find.text('Praça'), findsOneWidget);
    expect(find.text('Lixeira'), findsOneWidget);
  });

  testWidgets('zelador can set a quota from the sheet', (tester) async {
    _large(tester);
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mudar limite'));
    await tester.pumpAndSettle();

    expect(find.text('Limite de espaço'), findsOneWidget);
    expect(find.text('Usar o disco inteiro'), findsOneWidget);
    expect(find.text('Definir um limite'), findsOneWidget);
    expect(find.text('Limite (GB)'), findsOneWidget);
    expect(find.text('Em GB.'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '500');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('de 500,0 GB'), findsOneWidget);
  });

  testWidgets('zelador can select the whole disk and save a null quota', (
    tester,
  ) async {
    _large(tester);
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mudar limite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar o disco inteiro'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Usando o disco inteiro:'), findsOneWidget);
    expect(find.textContaining('em uso'), findsOneWidget);
  });
}
