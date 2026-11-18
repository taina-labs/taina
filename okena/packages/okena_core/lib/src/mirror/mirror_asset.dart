/// Platform-neutral metadata for one item in the device's camera roll.
final class MirrorAsset {
  MirrorAsset({
    required this.assetId,
    required DateTime modificationDate,
    required this.filename,
    required this.mime,
    required this.size,
    required DateTime? takenAt,
  }) : modificationDate = modificationDate.toUtc(),
       takenAt = takenAt?.toUtc();

  final String assetId;
  final DateTime modificationDate;
  final String filename;
  final String mime;
  final int? size;
  final DateTime? takenAt;

  @override
  bool operator ==(Object other) =>
      other is MirrorAsset &&
      other.assetId == assetId &&
      other.modificationDate == modificationDate &&
      other.filename == filename &&
      other.mime == mime &&
      other.size == size &&
      other.takenAt == takenAt;

  @override
  int get hashCode => Object.hash(
    MirrorAsset,
    assetId,
    modificationDate,
    filename,
    mime,
    size,
    takenAt,
  );
}
