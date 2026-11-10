/// How a list asks the server to order itself. One word on the wire, for
/// example `date_desc`.
final class Sort {
  const Sort({required this.key, this.direction = SortDirection.asc});

  final SortKey key;
  final SortDirection direction;

  String get wire => '${key.name}_${direction.name}';

  @override
  bool operator ==(Object other) =>
      other is Sort && other.key == key && other.direction == direction;

  @override
  int get hashCode => Object.hash(Sort, key, direction);
}

enum SortKey { name, date, size }

enum SortDirection { asc, desc }
