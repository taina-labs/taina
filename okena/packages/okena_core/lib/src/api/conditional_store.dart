import 'dart:typed_data';

/// The etag book of the collection reads: one entry per request and session,
/// holding the tag the box sent and the body it named.
///
/// The box answers 304 with no body, so the body is kept here and handed back
/// when the answer is "not modified". In memory only: a relaunch reads the
/// collections again. The key carries the session token, because the etag is
/// scope-local and another session's tag is not ours to send.
final class ConditionalStore {
  final Map<String, _Entry> _entries = {};

  /// The tag to send as `If-None-Match`, when there is one.
  String? tag(String key) => _entries[key]?.tag;

  /// The body the tag named.
  Uint8List? body(String key) => _entries[key]?.body;

  /// Remembers the body under the tag the box sent. A 200 without a tag
  /// drops the entry: there is nothing to condition the next read on.
  void keep({
    required String? tag,
    required Uint8List body,
    required String key,
  }) {
    if (tag == null || tag.isEmpty) {
      _entries.remove(key);
      return;
    }
    _entries[key] = _Entry(tag: tag, body: body);
  }

  void clear() => _entries.clear();
}

final class _Entry {
  const _Entry({required this.tag, required this.body});

  final String tag;
  final Uint8List body;
}
