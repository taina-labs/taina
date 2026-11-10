import 'package:okena_core/src/internal/equality.dart';
import 'package:okena_core/src/json/api_coding.dart';
import 'package:okena_core/src/models/wire.dart';

/// One day of the photo timeline: the effective date (EXIF when there is one,
/// otherwise the upload) with the photos taken inside it.
final class TimelineGroup {
  TimelineGroup({required this.date, required List<FileRecord> photos})
    : photos = List.unmodifiable(photos);

  factory TimelineGroup.fromJson(JsonReader reader) {
    return TimelineGroup(
      date: reader.string('date'),
      photos: reader.list('photos', FileRecord.fromJson),
    );
  }

  final String date;
  final List<FileRecord> photos;

  @override
  bool operator ==(Object other) =>
      other is TimelineGroup &&
      other.date == date &&
      listEquals(other.photos, photos);

  @override
  int get hashCode => Object.hash(TimelineGroup, date, Object.hashAll(photos));
}
