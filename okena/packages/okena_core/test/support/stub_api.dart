import 'dart:typed_data';

import 'package:okena_core/okena_core.dart';

/// A [TainaApi] with only the thumbnail read wired, for [ThumbnailStore]'s
/// tests. Every other call is a programming error in those tests.
final class ThumbnailStubApi implements TainaApi {
  ThumbnailStubApi(this.thumbnailAnswer);

  final Future<TainaResult<Uint8List>> Function(String rkey, ThumbnailSize size)
  thumbnailAnswer;

  @override
  Future<TainaResult<Uint8List>> thumbnail({
    required String rkey,
    required ThumbnailSize size,
  }) {
    return thumbnailAnswer(rkey, size);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
