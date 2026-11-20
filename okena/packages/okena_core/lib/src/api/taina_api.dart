import 'dart:typed_data';

import 'package:okena_core/src/api/sort.dart';
import 'package:okena_core/src/models/access.dart';
import 'package:okena_core/src/models/mirror_hash_lookup.dart';
import 'package:okena_core/src/models/mural.dart';
import 'package:okena_core/src/models/page.dart';
import 'package:okena_core/src/models/storage.dart';
import 'package:okena_core/src/models/timeline.dart';
import 'package:okena_core/src/models/token_status.dart';
import 'package:okena_core/src/models/wire.dart';
import 'package:okena_core/src/result.dart';
import 'package:okena_core/src/session/session.dart';
import 'package:okena_core/src/transport/transport.dart';

/// Thumbnail size. [sm] for list rows, [md] for the detail view.
enum ThumbnailSize {
  sm,
  md;

  String get wire => name;
}

/// Which file set the manifest reads.
enum ManifestMode {
  readable,
  mirror;

  String get wire => name;
}

/// The API the app talks to. The whole app depends on this and never on
/// [LiveTainaApi]; previews and tests use [FakeTainaApi]. One box serves one
/// community, so no method carries an instance parameter.
abstract class TainaApi {
  Future<TainaResult<Instance>> instance();

  Future<TainaResult<Session>> createSession({
    required String username,
    required String password,
    required String deviceName,
  });
  Future<TainaResult<TokenStatus>> inviteStatus({required String token});
  Future<TainaResult<Session>> acceptInvite({
    required String token,
    required String username,
    required String password,
    String? displayName,
    required String deviceName,
  });
  Future<TainaResult<TokenStatus>> resetStatus({required String token});
  Future<TainaResult<Session>> resetPassword({
    required String token,
    required String password,
    required String deviceName,
  });
  Future<TainaResult<void>> revokeSession();
  Future<TainaResult<Me>> me();
  Future<TainaResult<List<DeviceToken>>> devices();
  Future<TainaResult<void>> revokeDevice({required String id});

  Future<TainaResult<List<Folder>>> listFolders();
  Future<TainaResult<Folder>> folder({required String rkey});
  Future<TainaResult<Folder>> createFolder({
    required String name,
    String? parentRkey,
  });
  Future<TainaResult<Folder>> updateFolder({
    required String rkey,
    String? name,
    Zona? zona,
  });
  Future<TainaResult<Folder>> moveFolder({
    required String rkey,
    String? parentRkey,
  });
  Future<TainaResult<void>> deleteFolder({required String rkey});
  Future<TainaResult<FolderContents>> folderContents({
    String? folderRkey,
    int? limit,
    String? cursor,
    Sort? sort,
    Zona? zona,
  });

  /// Streams a file to the box. [progress], when supplied, reports request
  /// body bytes sent and the complete body length.
  Future<TainaResult<FileRecord>> upload({
    required String filePath,
    required String name,
    required String mime,
    String? folderRkey,
    UploadProgress? progress,
  });
  Future<TainaResult<FileRecord>> file({required String rkey});
  Future<TainaResult<FileRecord>> updateFile({
    required String rkey,
    String? name,
    Zona? zona,
  });
  Future<TainaResult<FileRecord>> moveFile({
    required String rkey,
    String? folderRkey,
  });
  Future<TainaResult<void>> deleteFile({required String rkey});
  Future<TainaResult<Page<FileRecord>>> recent({int? limit});

  /// The downloaded file's path on disk, named after the server's
  /// `Content-Disposition` when it carries one.
  Future<TainaResult<String>> download({required String rkey});
  Future<TainaResult<Uint8List>> thumbnail({
    required String rkey,
    required ThumbnailSize size,
  });

  Future<TainaResult<Page<FileRecord>>> trash({int? limit, String? cursor});
  Future<TainaResult<FileRecord>> restoreFile({required String rkey});
  Future<TainaResult<Page<FileRecord>>> photos({int? limit, String? cursor});
  Future<TainaResult<Page<TimelineGroup>>> photoTimeline({
    int? limit,
    String? cursor,
  });

  /// The readable backup manifest, or this person's live and trashed files
  /// in mirror mode, oldest first.
  Future<TainaResult<Page<FileRecord>>> manifest({
    String? after,
    int? limit,
    ManifestMode mode = ManifestMode.readable,
  });

  /// Looks up this person's file by its SHA-256, including trash suppression.
  Future<TainaResult<MirrorHashLookup>> hashLookup({required String sha256});

  /// One act over many files. The batch answers 200 even on partial failure;
  /// the outcome list carries what each item became.
  Future<TainaResult<List<BatchOutcome>>> batch({
    required BatchOp op,
    required List<String> ids,
    String? folderRkey,
  });

  Future<TainaResult<AccessTarget>> accessTarget({required String fileRkey});
  Future<TainaResult<Pedido>> requestAccess({
    required String fileRkey,
    String? motivo,
  });
  Future<TainaResult<Page<Pedido>>> accessRequests();
  Future<TainaResult<Page<Pedido>>> myRequests();
  Future<TainaResult<Concessao>> approveRequest({required String id});
  Future<TainaResult<Pedido>> denyRequest({required String id});

  /// The caller's grants, given ([GrantRole.owner]) or received
  /// ([GrantRole.reader]), the revoked ones included: granting must stay
  /// visible to be reversible.
  Future<TainaResult<Page<Concessao>>> grants({required GrantRole role});
  Future<TainaResult<void>> revokeGrant({required String id});

  Future<TainaResult<MemberInvite>> inviteMember({required Papel papel});
  Future<TainaResult<Ava>> updateMember({
    required String id,
    required Papel papel,
  });
  Future<TainaResult<void>> deactivateMember({required String id});
  Future<TainaResult<Ava>> reactivateMember({required String id});
  Future<TainaResult<void>> revokeInvite({required String id});
  Future<TainaResult<ResetLink>> memberResetLink({required String id});

  /// The zeladora sets the community's quota in bytes, or clears it to use the
  /// whole disk.
  Future<TainaResult<Tekoa>> setQuota({required int? bytes});

  /// The zeladora asks the box to back itself up now.
  Future<TainaResult<void>> triggerBackup();

  /// Changes the caller's own password while signed in. The box keeps the
  /// calling device signed in and revokes every other one.
  Future<TainaResult<void>> updatePassword({
    required String current,
    required String newPassword,
  });

  Future<TainaResult<Page<MuralEntry>>> mural({int? limit, String? cursor});
  Future<TainaResult<StorageStats>> storage();
  Future<TainaResult<Saude>> saude();

  Future<TainaResult<Page<Ava>>> members();
}
