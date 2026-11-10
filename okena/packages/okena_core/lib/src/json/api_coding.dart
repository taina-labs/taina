import 'dart:convert';

import '../result.dart';
import '../taina_error.dart';

typedef JsonMap = Map<String, Object?>;

/// Decodes a JSON object at the service boundary.
///
/// The whole decode is one boundary: a malformed body, a wrong type or a
/// missing required field all become an [InvalidResponseError] with the
/// [label] that names the call. Above this line, failure is a value.
TainaResult<T> decodeJsonBody<T>(
  List<int> body,
  String label,
  T Function(JsonReader reader) decode,
) {
  try {
    final decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
    if (decoded is! Map<String, Object?>) {
      return Err(InvalidResponseError('$label: not an object'));
    }
    return Ok(decode(JsonReader(decoded, label)));
  } on FormatException {
    return Err(InvalidResponseError(label));
  } on TypeError {
    return Err(InvalidResponseError(label));
  }
}

/// A typed read over one decoded JSON object.
///
/// Missing and `null` are the same for optional fields, like Swift's
/// `decodeIfPresent`; a required field that is absent or `null` is a
/// malformed body.
final class JsonReader {
  const JsonReader(this.json, this.label);

  final JsonMap json;
  final String label;

  String string(String key) => _string(json[key], key);

  String? stringOrNull(String key) {
    final value = json[key];
    return value == null ? null : _string(value, key);
  }

  bool boolean(String key) {
    final value = json[key];
    if (value is bool) return value;
    throw _malformed(key, 'a boolean');
  }

  int integer(String key) {
    final value = json[key];
    return _integer(value, key);
  }

  int? integerOrNull(String key) {
    final value = json[key];
    return value == null ? null : _integer(value, key);
  }

  List<String> stringList(String key) {
    final value = json[key];
    if (value is! List) throw _malformed(key, 'a list');
    return List.unmodifiable([
      for (final item in value)
        if (item is String)
          item
        else
          throw _malformed(key, 'a list of strings'),
    ]);
  }

  List<String> stringListOrEmpty(String key) {
    if (json[key] == null) return const [];
    return stringList(key);
  }

  Map<String, List<String>> stringListMapOrEmpty(String key) {
    final value = json[key];
    if (value == null) return const {};
    if (value is! Map) throw _malformed(key, 'an object');
    final result = <String, List<String>>{};
    for (final entry in value.entries) {
      final name = entry.key;
      if (name is! String) throw _malformed(key, 'an object');
      result[name] = _stringList(entry.value, key);
    }
    return Map.unmodifiable(result);
  }

  Map<String, int> integerMap(String key) {
    final value = json[key];
    if (value is! Map) throw _malformed(key, 'an object');
    final result = <String, int>{};
    for (final entry in value.entries) {
      final name = entry.key;
      if (name is! String) throw _malformed(key, 'an object');
      result[name] = _integer(entry.value, key);
    }
    return Map.unmodifiable(result);
  }

  JsonReader object(String key) {
    final value = json[key];
    if (value is! Map<String, Object?>) throw _malformed(key, 'an object');
    return JsonReader(value, '$label.$key');
  }

  JsonReader? objectOrNull(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! Map<String, Object?>) throw _malformed(key, 'an object');
    return JsonReader(value, '$label.$key');
  }

  List<T> list<T>(String key, T Function(JsonReader item) read) {
    final value = json[key];
    if (value is! List) throw _malformed(key, 'a list');
    return List.unmodifiable([
      for (var index = 0; index < value.length; index++)
        read(JsonReader(_object(value[index], key), '$label.$key[$index]')),
    ]);
  }

  T enumValue<T>(String key, Map<String, T> values) {
    final raw = string(key);
    final value = values[raw];
    if (value == null) {
      throw FormatException('$label.$key: unknown "$raw"');
    }
    return value;
  }

  String _string(Object? value, String key) {
    if (value is String) return value;
    throw _malformed(key, 'a string');
  }

  int _integer(Object? value, String key) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw _malformed(key, 'an integer');
  }

  List<String> _stringList(Object? value, String key) {
    if (value is! List) throw _malformed(key, 'a list');
    return List.unmodifiable([
      for (final item in value)
        if (item is String)
          item
        else
          throw _malformed(key, 'a list of strings'),
    ]);
  }

  JsonMap _object(Object? value, String key) {
    if (value is Map<String, Object?>) return value;
    throw _malformed(key, 'an object');
  }

  FormatException _malformed(String key, String expected) =>
      FormatException('$label.$key is not $expected');
}
