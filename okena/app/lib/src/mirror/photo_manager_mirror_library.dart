import 'dart:io';

import 'package:okena_core/okena_core.dart';
import 'package:photo_manager/photo_manager.dart';

import 'mirror_asset_materializer.dart';
import 'mirror_library.dart';

enum PhotoManagerPermission {
  authorized,
  limited,
  denied,
  restricted,
  notDetermined,
}

enum PhotoManagerAssetType { image, video, unsupported }

const _permissionRequestOption = PermissionRequestOption(
  androidPermission: AndroidPermission(
    type: RequestType.common,
    mediaLocation: false,
  ),
);

final class PhotoManagerAssetRecord {
  const PhotoManagerAssetRecord({
    required this.id,
    required this.type,
    required this.isTrashed,
    required this.modifiedDateTime,
    required this.createDateTime,
    required this.title,
    required this.mimeType,
    required this.fallbackMimeType,
    required this.fileSize,
  });

  final String id;
  final PhotoManagerAssetType type;
  final bool isTrashed;
  final DateTime modifiedDateTime;
  final DateTime createDateTime;
  final String? title;
  final String? mimeType;
  final String? fallbackMimeType;
  final int? fileSize;
}

final class PhotoManagerAssetPage {
  PhotoManagerAssetPage({
    required List<PhotoManagerAssetRecord> assets,
    required this.hasMore,
  }) : assets = List<PhotoManagerAssetRecord>.unmodifiable(assets);

  final List<PhotoManagerAssetRecord> assets;
  final bool hasMore;
}

abstract class PhotoManagerGateway {
  Future<PhotoManagerPermission> currentAccess();

  Future<PhotoManagerPermission> requestAccess();

  Future<void> openSettings();

  Future<PhotoManagerAssetPage> page({required int page, required int size});

  Future<void> presentLimitedSelection();

  Future<File?> originalFile(String assetId);
}

final class PhotoManagerMirrorLibrary
    implements MirrorLibrary, MirrorOriginalFileProvider {
  PhotoManagerMirrorLibrary({PhotoManagerGateway? gateway})
    : _gateway = gateway ?? const _PhotoManagerGateway();

  final PhotoManagerGateway _gateway;

  @override
  Future<TainaResult<MirrorLibraryAccess>> currentAccess() async {
    try {
      final permission = await _gateway.currentAccess();
      return Ok(_mirrorLibraryAccess(permission));
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  @override
  Future<TainaResult<MirrorLibraryAccess>> requestAccess() async {
    try {
      final permission = await _gateway.requestAccess();
      return Ok(_mirrorLibraryAccess(permission));
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  @override
  Future<TainaResult<void>> openSettings() async {
    try {
      await _gateway.openSettings();
      return const Ok<void>(null);
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  @override
  Future<TainaResult<MirrorAssetPage>> page({
    required int page,
    int size = 200,
  }) async {
    if (page < 0 || size <= 0) {
      return const Err(InvalidResponseError('mirror library page'));
    }

    try {
      final rawPage = await _gateway.page(page: page, size: size);
      final assets = <MirrorAsset>[];
      for (final record in rawPage.assets) {
        if (record.isTrashed ||
            (record.type != PhotoManagerAssetType.image &&
                record.type != PhotoManagerAssetType.video)) {
          continue;
        }

        final modificationDate =
            record.modifiedDateTime.millisecondsSinceEpoch == 0
            ? record.createDateTime
            : record.modifiedDateTime;
        assets.add(
          MirrorAsset(
            assetId: record.id,
            modificationDate: modificationDate,
            filename: _safeFilename(record.title),
            mime: _mimeType(record.mimeType, record.fallbackMimeType),
            size: record.fileSize != null && record.fileSize! >= 0
                ? record.fileSize
                : null,
            takenAt: record.createDateTime,
          ),
        );
      }
      return Ok(MirrorAssetPage(assets: assets, hasMore: rawPage.hasMore));
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  @override
  Future<TainaResult<void>> presentLimitedSelection() async {
    try {
      await _gateway.presentLimitedSelection();
      return const Ok<void>(null);
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }

  @override
  Future<TainaResult<File>> originalFile(String assetId) async {
    try {
      final file = await _gateway.originalFile(assetId);
      if (file == null || !await file.exists()) {
        return Err(MirrorAssetReadError('original asset is missing'));
      }
      return Ok(file);
    } on Exception catch (error) {
      return Err(MirrorAssetReadError(error.toString()));
    }
  }
}

final class _PhotoManagerGateway implements PhotoManagerGateway {
  const _PhotoManagerGateway();

  @override
  Future<PhotoManagerPermission> currentAccess() async {
    final state = await PhotoManager.getPermissionState(
      requestOption: _permissionRequestOption,
    );
    return _photoManagerPermission(state);
  }

  @override
  Future<PhotoManagerPermission> requestAccess() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: _permissionRequestOption,
    );
    return _photoManagerPermission(state);
  }

  @override
  Future<PhotoManagerAssetPage> page({
    required int page,
    required int size,
  }) async {
    final rawAssets = await PhotoManager.getAssetListPaged(
      page: page,
      pageCount: size,
      type: RequestType.common,
    );
    final hasMore = rawAssets.length == size;
    final records = await Future.wait(
      rawAssets.map(_recordFor),
      eagerError: true,
    );
    return PhotoManagerAssetPage(assets: records, hasMore: hasMore);
  }

  Future<PhotoManagerAssetRecord> _recordFor(AssetEntity asset) async {
    final type = switch (asset.type) {
      AssetType.image => PhotoManagerAssetType.image,
      AssetType.video => PhotoManagerAssetType.video,
      _ => PhotoManagerAssetType.unsupported,
    };
    final includeMetadata =
        !asset.isTrashed &&
        (type == PhotoManagerAssetType.image ||
            type == PhotoManagerAssetType.video);
    final String? title;
    final String? mimeType;
    final int? fileSize;
    if (includeMetadata) {
      final metadata = await Future.wait<Object?>([
        asset.titleAsync,
        asset.mimeTypeAsync,
        asset.fileSize,
      ], eagerError: true);
      title = metadata[0] as String?;
      mimeType = metadata[1] as String?;
      fileSize = metadata[2] as int?;
    } else {
      title = null;
      mimeType = null;
      fileSize = null;
    }

    return PhotoManagerAssetRecord(
      id: asset.id,
      type: type,
      isTrashed: asset.isTrashed,
      modifiedDateTime: asset.modifiedDateTime,
      createDateTime: asset.createDateTime,
      title: title,
      mimeType: mimeType,
      fallbackMimeType: asset.mimeType,
      fileSize: fileSize,
    );
  }

  @override
  Future<void> presentLimitedSelection() =>
      PhotoManager.presentLimited(type: RequestType.common);

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<File?> originalFile(String assetId) async {
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) return null;
    return asset.originFile;
  }
}

PhotoManagerPermission _photoManagerPermission(PermissionState state) =>
    switch (state) {
      PermissionState.authorized => PhotoManagerPermission.authorized,
      PermissionState.limited => PhotoManagerPermission.limited,
      PermissionState.denied => PhotoManagerPermission.denied,
      PermissionState.restricted => PhotoManagerPermission.restricted,
      PermissionState.notDetermined => PhotoManagerPermission.notDetermined,
    };

MirrorLibraryAccess _mirrorLibraryAccess(PhotoManagerPermission permission) =>
    switch (permission) {
      PhotoManagerPermission.authorized => MirrorLibraryAccess.full,
      PhotoManagerPermission.limited => MirrorLibraryAccess.limited,
      PhotoManagerPermission.denied => MirrorLibraryAccess.denied,
      PhotoManagerPermission.restricted => MirrorLibraryAccess.restricted,
      PhotoManagerPermission.notDetermined => MirrorLibraryAccess.notDetermined,
    };

String _safeFilename(String? title) {
  final normalized = (title ?? '').trim().replaceAll('\\', '/');
  final basename = normalized.split('/').last;
  final withoutControls = basename.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  final safe = withoutControls.trim();
  if (safe.isEmpty || safe == '.' || safe == '..') return 'asset';
  return safe.length <= 255 ? safe : safe.substring(0, 255);
}

String _mimeType(String? primary, String? fallback) {
  final preferred = primary?.trim();
  if (preferred != null && preferred.isNotEmpty) return preferred;
  final alternative = fallback?.trim();
  if (alternative != null && alternative.isNotEmpty) return alternative;
  return 'application/octet-stream';
}
