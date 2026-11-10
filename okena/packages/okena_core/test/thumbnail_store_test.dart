import 'dart:typed_data';

import 'package:okena_core/okena_core.dart';
import 'package:test/test.dart';

import 'support/stub_api.dart';

void main() {
  test('a miss fetches once and hits serve from cache', () async {
    var calls = 0;
    final store = ThumbnailStore(
      api: ThumbnailStubApi((rkey, size) async {
        calls += 1;
        return Ok(Uint8List.fromList([0x01]));
      }),
    );

    expect(
      (await store.data(rkey: '3m2a8twqpv5z2', size: ThumbnailSize.sm)).value,
      isNotNull,
    );
    expect(calls, 1);

    // A second pass over the grid does not fetch again.
    expect(
      (await store.data(rkey: '3m2a8twqpv5z2', size: ThumbnailSize.sm)).value,
      isNotNull,
    );
    expect(calls, 1);

    // The size is part of the key.
    expect(
      (await store.data(rkey: '3m2a8twqpv5z2', size: ThumbnailSize.md)).value,
      isNotNull,
    );
    expect(calls, 2);
  });

  test('a failure is not cached', () async {
    var calls = 0;
    final store = ThumbnailStore(
      api: ThumbnailStubApi((rkey, size) async {
        calls += 1;
        return const Err(
          ApiError(
            code: 'not_found',
            status: 404,
            serverMessage: 'Este arquivo não tem miniatura.',
          ),
        );
      }),
    );

    expect(
      (await store.data(rkey: '3m2a8twqpv5z2', size: ThumbnailSize.sm)).value,
      isNull,
    );
    expect(
      (await store.data(rkey: '3m2a8twqpv5z2', size: ThumbnailSize.sm)).value,
      isNull,
    );
    expect(calls, 2);
  });

  test('clear drops the cache', () async {
    var calls = 0;
    final store = ThumbnailStore(
      api: ThumbnailStubApi((rkey, size) async {
        calls += 1;
        return Ok(Uint8List.fromList([0x01]));
      }),
    );

    expect(
      (await store.data(rkey: '3m2a8twqpv5z2', size: ThumbnailSize.sm)).value,
      isNotNull,
    );
    store.clear();
    expect(
      (await store.data(rkey: '3m2a8twqpv5z2', size: ThumbnailSize.sm)).value,
      isNotNull,
    );
    expect(calls, 2);
  });

  test('the cache is bounded and evicts the oldest entry', () async {
    var calls = 0;
    final store = ThumbnailStore(
      api: ThumbnailStubApi((rkey, size) async {
        calls += 1;
        return Ok(Uint8List.fromList([0x01]));
      }),
      countLimit: 1,
    );

    await store.data(rkey: 'a', size: ThumbnailSize.sm);
    await store.data(rkey: 'b', size: ThumbnailSize.sm);
    expect(calls, 2);

    // `a` was evicted; `b` is still cached.
    await store.data(rkey: 'b', size: ThumbnailSize.sm);
    expect(calls, 2);
    await store.data(rkey: 'a', size: ThumbnailSize.sm);
    expect(calls, 3);
  });
}
