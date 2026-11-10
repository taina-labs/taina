import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/mural/mural_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

MuralEntry entry(int seq) {
  return MuralEntry(
    seq: seq,
    tipo: 'put',
    payload: const {'actor': JsonString('avap2xw5m8q3')},
    cid: 'cid$seq',
    prev: seq == 1 ? null : 'cid${seq - 1}',
    createdAt: '2026-10-14T10:00:00Z',
  );
}

/// A mural that hands the scripted pages out in order, delegating the roster
/// to the real fake.
final class _ScriptedMuralApi implements TainaApi {
  _ScriptedMuralApi(this._inner, this.results);

  final TainaApi _inner;
  final List<TainaResult<Page<MuralEntry>>> results;
  int calls = 0;

  @override
  Future<TainaResult<Page<MuralEntry>>> mural({
    int? limit,
    String? cursor,
  }) async {
    final int index = calls;
    calls += 1;
    return results[index];
  }

  @override
  Future<TainaResult<Page<Ava>>> members() => _inner.members();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('load reads the first page and resolves the actors', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MuralModel model = MuralModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    await model.load();

    expect(model.loading, isFalse);
    expect(model.entries, hasLength(4));
    expect(model.nextCursor, isNull);
    expect(model.error, isNull);
    expect(model.names, containsPair('avap2xw5m8q3', 'Ana Souza'));
    expect(
      model.sentenceFor(model.entries.first),
      'O sistema fez um ato registrado na comunidade.',
    );
  });

  test('loadMore appends the next page and moves the cursor', () async {
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    final _ScriptedMuralApi api = _ScriptedMuralApi(inner, [
      Ok(Page(items: [entry(3), entry(2)], nextCursor: '1')),
      Ok(Page(items: [entry(1)], nextCursor: null)),
    ]);
    final MuralModel model = MuralModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    await model.load();
    expect(model.entries.map((MuralEntry e) => e.seq), [3, 2]);
    expect(model.nextCursor, '1');

    await model.loadMore();
    expect(model.entries.map((MuralEntry e) => e.seq), [3, 2, 1]);
    expect(model.nextCursor, isNull);
    expect(model.loadingMore, isFalse);
    expect(api.calls, 2);
  });

  test('a failed next page keeps the list and offers the retry', () async {
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    final _ScriptedMuralApi api = _ScriptedMuralApi(inner, [
      Ok(Page(items: [entry(2)], nextCursor: '1')),
      const Err(offline),
    ]);
    final MuralModel model = MuralModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    await model.load();
    await model.loadMore();

    expect(model.entries, hasLength(1));
    expect(model.nextCursor, '1');
    expect(model.moreError, isTrue);
    expect(model.error, isNull);
  });

  test('loadMore does nothing without a cursor', () async {
    final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
    final _ScriptedMuralApi api = _ScriptedMuralApi(inner, [
      Ok(Page(items: [entry(1)], nextCursor: null)),
    ]);
    final MuralModel model = MuralModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    await model.load();
    await model.loadMore();

    expect(api.calls, 1);
  });

  test(
    'a failed first page surfaces the error and keeps the list empty',
    () async {
      final FakeTainaApi inner = FakeTainaApi(delay: Duration.zero);
      final _ScriptedMuralApi api = _ScriptedMuralApi(inner, [
        const Err(offline),
      ]);
      final MuralModel model = MuralModel(
        gateway: FakeSession(api, me: identity(ana)),
      );

      await model.load();

      expect(model.entries, isEmpty);
      expect(model.error, offline);
      expect(model.loading, isFalse);
    },
  );
}
