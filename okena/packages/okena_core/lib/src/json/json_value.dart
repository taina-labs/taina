import 'package:okena_core/src/internal/equality.dart';

/// Any JSON, kept whole: the mural payload is free-form and must arrive
/// without losing a field, a nesting level or a type.
sealed class JsonValue {
  const JsonValue();

  factory JsonValue.fromJson(Object? value) {
    if (value == null) return const JsonNull();
    if (value is bool) return JsonBool(value);
    if (value is int) return JsonInt(value);
    if (value is double) return JsonDouble(value);
    if (value is String) return JsonString(value);
    if (value is List) {
      return JsonArray([for (final item in value) JsonValue.fromJson(item)]);
    }
    if (value is Map) {
      final fields = <String, JsonValue>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException('json object key is not a string');
        }
        fields[key] = JsonValue.fromJson(entry.value);
      }
      return JsonObject(fields);
    }
    throw const FormatException('value is not valid JSON');
  }

  /// The value back in `dart:convert` shape, for re-encoding.
  Object? toJson() => switch (this) {
    JsonNull() => null,
    JsonBool(:final value) => value,
    JsonInt(:final value) => value,
    JsonDouble(:final value) => value,
    JsonString(:final value) => value,
    JsonArray(:final values) => [for (final value in values) value.toJson()],
    JsonObject(:final fields) => {
      for (final entry in fields.entries) entry.key: entry.value.toJson(),
    },
  };
}

final class JsonNull extends JsonValue {
  const JsonNull();

  @override
  bool operator ==(Object other) => other is JsonNull;

  @override
  int get hashCode => (JsonNull).hashCode;
}

final class JsonBool extends JsonValue {
  const JsonBool(this.value);

  final bool value;

  @override
  bool operator ==(Object other) => other is JsonBool && other.value == value;

  @override
  int get hashCode => Object.hash(JsonBool, value);
}

final class JsonInt extends JsonValue {
  const JsonInt(this.value);

  final int value;

  @override
  bool operator ==(Object other) => other is JsonInt && other.value == value;

  @override
  int get hashCode => Object.hash(JsonInt, value);
}

final class JsonDouble extends JsonValue {
  const JsonDouble(this.value);

  final double value;

  @override
  bool operator ==(Object other) => other is JsonDouble && other.value == value;

  @override
  int get hashCode => Object.hash(JsonDouble, value);
}

final class JsonString extends JsonValue {
  const JsonString(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is JsonString && other.value == value;

  @override
  int get hashCode => Object.hash(JsonString, value);
}

final class JsonArray extends JsonValue {
  const JsonArray(this.values);

  final List<JsonValue> values;

  @override
  bool operator ==(Object other) =>
      other is JsonArray && listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(JsonArray, Object.hashAll(values));
}

final class JsonObject extends JsonValue {
  const JsonObject(this.fields);

  final Map<String, JsonValue> fields;

  @override
  bool operator ==(Object other) =>
      other is JsonObject && mapEquals(other.fields, fields);

  @override
  int get hashCode => Object.hash(
    JsonObject,
    Object.hashAllUnordered([
      for (final entry in fields.entries) Object.hash(entry.key, entry.value),
    ]),
  );
}
