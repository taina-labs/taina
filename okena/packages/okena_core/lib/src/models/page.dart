import 'dart:math' as math;

import 'package:okena_core/src/internal/equality.dart';
import 'package:okena_core/src/json/api_coding.dart';
import 'package:okena_core/src/models/wire.dart';

/// The uniform list envelope: `{"items": [...], "next_cursor": ...}`. The
/// cursor is opaque on keyset lists and a decimal offset in string form on
/// offset lists; null at the end.
final class Page<T> {
  Page({required List<T> items, required this.nextCursor})
    : items = List.unmodifiable(items);

  factory Page.fromJson(JsonReader reader, T Function(JsonReader item) read) {
    return Page(
      items: reader.list('items', read),
      nextCursor: reader.stringOrNull('next_cursor'),
    );
  }

  /// Slices a full, ordered list into one page, walking it by the offset
  /// cursor the contract allows. The server does this for the real lists;
  /// [FakeTainaApi] runs the same rule in memory so previews scroll for
  /// real. Pure: values, limit, cursor, page.
  static Page<T> slice<T>(List<T> values, {int? limit, String? cursor}) {
    // The contract's limits: 50 by default, never below 1 or above 100.
    final size = limit == null ? 50 : math.min(math.max(limit, 1), 100);
    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    if (start >= values.length) {
      return Page(items: const [], nextCursor: null);
    }
    final end = math.min(start + size, values.length);
    return Page(
      items: values.sublist(start, end),
      nextCursor: end < values.length ? '$end' : null,
    );
  }

  final List<T> items;
  final String? nextCursor;

  @override
  bool operator ==(Object other) =>
      other is Page<T> &&
      listEquals(other.items, items) &&
      other.nextCursor == nextCursor;

  @override
  int get hashCode => Object.hash(Page, Object.hashAll(items), nextCursor);
}

/// The contents of one folder: folders come complete, only the files
/// paginate.
final class FolderContents {
  FolderContents({
    required List<Folder> folders,
    required List<FileRecord> items,
    required this.nextCursor,
  }) : folders = List.unmodifiable(folders),
       items = List.unmodifiable(items);

  factory FolderContents.fromJson(JsonReader reader) {
    return FolderContents(
      folders: reader.list('folders', Folder.fromJson),
      items: reader.list('items', FileRecord.fromJson),
      nextCursor: reader.stringOrNull('next_cursor'),
    );
  }

  final List<Folder> folders;
  final List<FileRecord> items;
  final String? nextCursor;

  @override
  bool operator ==(Object other) =>
      other is FolderContents &&
      listEquals(other.folders, folders) &&
      listEquals(other.items, items) &&
      other.nextCursor == nextCursor;

  @override
  int get hashCode => Object.hash(
    FolderContents,
    Object.hashAll(folders),
    Object.hashAll(items),
    nextCursor,
  );
}
