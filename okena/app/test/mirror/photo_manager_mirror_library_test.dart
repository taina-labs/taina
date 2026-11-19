import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/mirror/mirror_library.dart';
import 'package:okena_app/src/mirror/photo_manager_mirror_library.dart';
import 'package:okena_core/okena_core.dart';

void main() {
  group('PhotoManagerMirrorLibrary', () {
    test('maps every permission value', () async {
      final mappings = {
        PhotoManagerPermission.authorized: MirrorLibraryAccess.full,
        PhotoManagerPermission.limited: MirrorLibraryAccess.limited,
        PhotoManagerPermission.denied: MirrorLibraryAccess.denied,
        PhotoManagerPermission.restricted: MirrorLibraryAccess.restricted,
        PhotoManagerPermission.notDetermined: MirrorLibraryAccess.notDetermined,
      };

      for (final mapping in mappings.entries) {
        final library = PhotoManagerMirrorLibrary(
          gateway: _FakePhotoManagerGateway()..permission = mapping.key,
        );
        expect((await library.requestAccess()).value, mapping.value);
      }
    });

    test(
      'maps metadata fallbacks and filters trashed or unsupported assets',
      () async {
        final library = PhotoManagerMirrorLibrary(
          gateway: _FakePhotoManagerGateway()
            ..assetPage = PhotoManagerAssetPage(
              assets: [
                _record(
                  id: 'still',
                  modified: DateTime.fromMillisecondsSinceEpoch(0),
                  created: DateTime.utc(2026, 11, 15, 10),
                  title: '../album/photo\nname.jpg',
                  mimeType: '',
                  fallbackMimeType: ' image/jpeg ',
                  fileSize: 37,
                ),
                _record(
                  id: 'video',
                  type: PhotoManagerAssetType.video,
                  modified: DateTime.utc(2026, 11, 16, 10),
                  created: DateTime.utc(2026, 11, 14, 10),
                  title: null,
                  mimeType: null,
                  fallbackMimeType: null,
                  fileSize: -1,
                ),
                _record(
                  id: 'trashed',
                  trashed: true,
                  modified: DateTime.utc(2026, 11, 16),
                  created: DateTime.utc(2026, 11, 15),
                ),
                _record(
                  id: 'unsupported',
                  type: PhotoManagerAssetType.unsupported,
                  modified: DateTime.utc(2026, 11, 16),
                  created: DateTime.utc(2026, 11, 15),
                ),
              ],
              hasMore: true,
            ),
        );

        final result = await library.page(page: 0, size: 4);

        expect(result, isA<Ok<MirrorAssetPage>>());
        final page = (result as Ok<MirrorAssetPage>).value;
        expect(page.hasMore, isTrue);
        expect(page.assets, hasLength(2));
        expect(page.assets[0].assetId, 'still');
        expect(page.assets[0].filename, 'photoname.jpg');
        expect(page.assets[0].mime, 'image/jpeg');
        expect(page.assets[0].size, 37);
        expect(page.assets[0].modificationDate, DateTime.utc(2026, 11, 15, 10));
        expect(page.assets[0].takenAt, DateTime.utc(2026, 11, 15, 10));
        expect(page.assets[1].filename, 'asset');
        expect(page.assets[1].mime, 'application/octet-stream');
        expect(page.assets[1].size, isNull);
        expect(page.assets[1].modificationDate, DateTime.utc(2026, 11, 16, 10));
      },
    );

    test(
      'preserves raw hasMore when every returned asset is filtered',
      () async {
        final gateway = _FakePhotoManagerGateway()
          ..assetPage = PhotoManagerAssetPage(
            assets: [
              _record(id: 'trashed', trashed: true),
              _record(
                id: 'unsupported',
                type: PhotoManagerAssetType.unsupported,
              ),
            ],
            hasMore: true,
          );
        final library = PhotoManagerMirrorLibrary(gateway: gateway);

        final result = await library.page(page: 3, size: 2);

        expect(result.value?.assets, isEmpty);
        expect(result.value?.hasMore, isTrue);
        expect(gateway.pageCalls, [(3, 2)]);
      },
    );

    test('validates page arguments before calling the gateway', () async {
      final gateway = _FakePhotoManagerGateway();
      final library = PhotoManagerMirrorLibrary(gateway: gateway);

      expect((await library.page(page: -1)).isFailure, isTrue);
      expect((await library.page(page: 0, size: 0)).isFailure, isTrue);
      expect(gateway.pageCalls, isEmpty);
    });

    test(
      'returns read errors for missing originals and plugin exceptions',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'mirror-library-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final missing = File('${directory.path}/missing.jpg');
        final gateway = _FakePhotoManagerGateway()..original = missing;
        final library = PhotoManagerMirrorLibrary(gateway: gateway);

        expect(
          (await library.originalFile('gone')).error,
          isA<MirrorAssetReadError>(),
        );

        gateway.originalFailure = const FileSystemException('plugin failed');
        final pluginFailure = await library.originalFile('broken');
        expect(pluginFailure.error, isA<MirrorAssetReadError>());
        expect((await library.page(page: 0)).error, isNull);

        gateway.pageFailure = const FileSystemException('page failed');
        final pageFailure = await library.page(page: 0);
        expect(pageFailure.error, isA<MirrorAssetReadError>());
      },
    );

    test('limited-selection plugin failures become read errors', () async {
      final library = PhotoManagerMirrorLibrary(
        gateway: _FakePhotoManagerGateway()
          ..selectionFailure = const FileSystemException('picker failed'),
      );

      expect(
        (await library.presentLimitedSelection()).error,
        isA<MirrorAssetReadError>(),
      );
    });
  });
}

PhotoManagerAssetRecord _record({
  required String id,
  PhotoManagerAssetType type = PhotoManagerAssetType.image,
  bool trashed = false,
  DateTime? modified,
  DateTime? created,
  String? title = 'photo.jpg',
  String? mimeType = 'image/jpeg',
  String? fallbackMimeType = 'image/jpeg',
  int? fileSize = 10,
}) => PhotoManagerAssetRecord(
  id: id,
  type: type,
  isTrashed: trashed,
  modifiedDateTime: modified ?? DateTime.utc(2026, 11, 18),
  createDateTime: created ?? DateTime.utc(2026, 11, 17),
  title: title,
  mimeType: mimeType,
  fallbackMimeType: fallbackMimeType,
  fileSize: fileSize,
);

final class _FakePhotoManagerGateway implements PhotoManagerGateway {
  PhotoManagerPermission permission = PhotoManagerPermission.authorized;
  PhotoManagerAssetPage assetPage = PhotoManagerAssetPage(
    assets: const [],
    hasMore: false,
  );
  File? original;
  Exception? requestFailure;
  Exception? pageFailure;
  Exception? originalFailure;
  Exception? selectionFailure;
  final List<(int, int)> pageCalls = [];

  @override
  Future<PhotoManagerPermission> requestAccess() async {
    if (requestFailure case final failure?) throw failure;
    return permission;
  }

  @override
  Future<PhotoManagerAssetPage> page({
    required int page,
    required int size,
  }) async {
    pageCalls.add((page, size));
    if (pageFailure case final failure?) throw failure;
    return assetPage;
  }

  @override
  Future<void> presentLimitedSelection() async {
    if (selectionFailure case final failure?) throw failure;
  }

  @override
  Future<File?> originalFile(String assetId) async {
    if (originalFailure case final failure?) throw failure;
    return original;
  }
}
