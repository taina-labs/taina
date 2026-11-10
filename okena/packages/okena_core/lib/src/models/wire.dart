import 'package:okena_core/src/json/api_coding.dart';

/// The two zones of the social model. The word on the wire, in the model and
/// on the screen is the same.
enum Zona {
  casa,
  praca;

  static const Map<String, Zona> byWire = {'casa': casa, 'praca': praca};
}

/// The social role inside a Tekoa. "zelador" and "morador" are the words on
/// screen, never "admin" or "member".
enum Papel {
  zelador,
  morador;

  static const Map<String, Papel> byWire = {
    'zelador': zelador,
    'morador': morador,
  };
}

/// The person inside a Tekoa.
final class Ava {
  const Ava({
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.papel,
    required this.activatedAt,
    required this.deactivatedAt,
    required this.createdAt,
  });

  factory Ava.fromJson(JsonReader reader) {
    return Ava(
      publicId: reader.string('public_id'),
      username: reader.stringOrNull('username'),
      displayName: reader.stringOrNull('display_name'),
      papel: reader.enumValue('papel', Papel.byWire),
      activatedAt: reader.stringOrNull('activated_at'),
      deactivatedAt: reader.stringOrNull('deactivated_at'),
      createdAt: reader.string('created_at'),
    );
  }

  final String publicId;
  final String? username;
  final String? displayName;
  final Papel papel;
  final String? activatedAt;
  final String? deactivatedAt;
  final String createdAt;

  /// What a row shows: the display name when there is one, the username
  /// otherwise, and the invite's own words while the person has not chosen a
  /// name yet (the web's `display_name/1`). Pure, so the UI does not repeat
  /// the rule.
  String get label => displayName ?? username ?? 'Convite pendente';

  Map<String, Object?> toJson() => {
    'public_id': publicId,
    'username': username,
    'display_name': displayName,
    'papel': papel.name,
    'activated_at': activatedAt,
    'deactivated_at': deactivatedAt,
    'created_at': createdAt,
  };

  @override
  bool operator ==(Object other) =>
      other is Ava &&
      other.publicId == publicId &&
      other.username == username &&
      other.displayName == displayName &&
      other.papel == papel &&
      other.activatedAt == activatedAt &&
      other.deactivatedAt == deactivatedAt &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    Ava,
    publicId,
    username,
    displayName,
    papel,
    activatedAt,
    deactivatedAt,
    createdAt,
  );
}

/// The community. One per box.
final class Tekoa {
  const Tekoa({
    required this.publicId,
    required this.name,
    required this.domain,
    required this.storageQuotaBytes,
    required this.storageUsedBytes,
    required this.createdAt,
  });

  factory Tekoa.fromJson(JsonReader reader) {
    return Tekoa(
      publicId: reader.string('public_id'),
      name: reader.string('name'),
      domain: reader.string('domain'),
      storageQuotaBytes: reader.integerOrNull('storage_quota_bytes'),
      storageUsedBytes: reader.integer('storage_used_bytes'),
      createdAt: reader.string('created_at'),
    );
  }

  final String publicId;
  final String name;
  final String domain;
  final int? storageQuotaBytes;
  final int storageUsedBytes;
  final String createdAt;

  Map<String, Object?> toJson() => {
    'public_id': publicId,
    'name': name,
    'domain': domain,
    'storage_quota_bytes': storageQuotaBytes,
    'storage_used_bytes': storageUsedBytes,
    'created_at': createdAt,
  };

  @override
  bool operator ==(Object other) =>
      other is Tekoa &&
      other.publicId == publicId &&
      other.name == name &&
      other.domain == domain &&
      other.storageQuotaBytes == storageQuotaBytes &&
      other.storageUsedBytes == storageUsedBytes &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    Tekoa,
    publicId,
    name,
    domain,
    storageQuotaBytes,
    storageUsedBytes,
    createdAt,
  );
}

/// The instance: whether the box is set up and which community it serves.
final class Instance {
  const Instance({
    required this.bootstrapped,
    required this.tekoa,
    required this.version,
  });

  factory Instance.fromJson(JsonReader reader) {
    final tekoa = reader.objectOrNull('tekoa');
    return Instance(
      bootstrapped: reader.boolean('bootstrapped'),
      tekoa: tekoa == null ? null : Tekoa.fromJson(tekoa),
      version: reader.stringOrNull('version'),
    );
  }

  final bool bootstrapped;
  final Tekoa? tekoa;
  final String? version;

  @override
  bool operator ==(Object other) =>
      other is Instance &&
      other.bootstrapped == bootstrapped &&
      other.tekoa == tekoa &&
      other.version == version;

  @override
  int get hashCode => Object.hash(Instance, bootstrapped, tekoa, version);
}

/// One authorized device, without the hash of the secret, ever.
final class DeviceToken {
  const DeviceToken({
    required this.publicId,
    required this.name,
    required this.lastUsedAt,
    required this.revokedAt,
    required this.createdAt,
  });

  factory DeviceToken.fromJson(JsonReader reader) {
    return DeviceToken(
      publicId: reader.string('public_id'),
      name: reader.string('name'),
      lastUsedAt: reader.stringOrNull('last_used_at'),
      revokedAt: reader.stringOrNull('revoked_at'),
      createdAt: reader.string('created_at'),
    );
  }

  final String publicId;
  final String name;
  final String? lastUsedAt;
  final String? revokedAt;
  final String createdAt;

  Map<String, Object?> toJson() => {
    'public_id': publicId,
    'name': name,
    'last_used_at': lastUsedAt,
    'revoked_at': revokedAt,
    'created_at': createdAt,
  };

  @override
  bool operator ==(Object other) =>
      other is DeviceToken &&
      other.publicId == publicId &&
      other.name == name &&
      other.lastUsedAt == lastUsedAt &&
      other.revokedAt == revokedAt &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    DeviceToken,
    publicId,
    name,
    lastUsedAt,
    revokedAt,
    createdAt,
  );
}

/// Where the thumbnails of an image stand: the words the box derives from
/// the photo record. [none] is for everything that is not an image, so a
/// document never waits on a rendition that is not coming.
enum Rendition {
  ready,
  pending,
  unavailable,
  none;

  static const Map<String, Rendition> byWire = {
    'ready': ready,
    'pending': pending,
    'unavailable': unavailable,
    'none': none,
  };
}

/// The file of the community, a record of the vault.
///
/// Named [FileRecord] instead of the Swift `File`, because `dart:io` owns
/// that name in every consumer.
final class FileRecord {
  const FileRecord({
    required this.rkey,
    required this.cid,
    required this.blobCid,
    required this.sha256,
    required this.name,
    required this.mime,
    required this.size,
    required this.zona,
    required this.folder,
    required this.takenAt,
    required this.width,
    required this.height,
    required this.rendition,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FileRecord.fromJson(JsonReader reader) {
    return FileRecord(
      rkey: reader.string('rkey'),
      cid: reader.string('cid'),
      blobCid: reader.string('blob_cid'),
      sha256: reader.string('sha256'),
      name: reader.string('name'),
      mime: reader.string('mime'),
      size: reader.integer('size'),
      zona: reader.enumValue('zona', Zona.byWire),
      folder: reader.stringOrNull('folder'),
      takenAt: reader.stringOrNull('taken_at'),
      width: reader.integerOrNull('width'),
      height: reader.integerOrNull('height'),
      rendition: reader.enumValue('rendition', Rendition.byWire),
      deletedAt: reader.stringOrNull('deleted_at'),
      createdAt: reader.string('created_at'),
      updatedAt: reader.string('updated_at'),
    );
  }

  final String rkey;
  final String cid;
  final String blobCid;
  final String sha256;
  final String name;
  final String mime;
  final int size;
  final Zona zona;
  final String? folder;
  final String? takenAt;
  final int? width;
  final int? height;
  final Rendition rendition;
  final String? deletedAt;
  final String createdAt;
  final String updatedAt;

  @override
  bool operator ==(Object other) =>
      other is FileRecord &&
      other.rkey == rkey &&
      other.cid == cid &&
      other.blobCid == blobCid &&
      other.sha256 == sha256 &&
      other.name == name &&
      other.mime == mime &&
      other.size == size &&
      other.zona == zona &&
      other.folder == folder &&
      other.takenAt == takenAt &&
      other.width == width &&
      other.height == height &&
      other.rendition == rendition &&
      other.deletedAt == deletedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
    FileRecord,
    rkey,
    cid,
    blobCid,
    sha256,
    name,
    mime,
    size,
    zona,
    folder,
    takenAt,
    width,
    height,
    rendition,
    deletedAt,
    createdAt,
    updatedAt,
  ]);
}

/// The folder that organizes files, itself a record.
final class Folder {
  const Folder({
    required this.rkey,
    required this.cid,
    required this.name,
    required this.zona,
    required this.folder,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Folder.fromJson(JsonReader reader) {
    return Folder(
      rkey: reader.string('rkey'),
      cid: reader.string('cid'),
      name: reader.string('name'),
      zona: reader.enumValue('zona', Zona.byWire),
      folder: reader.stringOrNull('folder'),
      deletedAt: reader.stringOrNull('deleted_at'),
      createdAt: reader.string('created_at'),
      updatedAt: reader.string('updated_at'),
    );
  }

  final String rkey;
  final String cid;
  final String name;
  final Zona zona;
  final String? folder;
  final String? deletedAt;
  final String createdAt;
  final String updatedAt;

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.rkey == rkey &&
      other.cid == cid &&
      other.name == name &&
      other.zona == zona &&
      other.folder == folder &&
      other.deletedAt == deletedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    Folder,
    rkey,
    cid,
    name,
    zona,
    folder,
    deletedAt,
    createdAt,
    updatedAt,
  );
}

/// The act a batch runs over every id it carries. The words are the wire's.
enum BatchOp {
  trash,
  restore,
  move,
  publish,
  unpublish;

  static const Map<String, BatchOp> byWire = {
    'trash': trash,
    'restore': restore,
    'move': move,
    'publish': publish,
    'unpublish': unpublish,
  };
}

/// One item of a batch answer: the rkey it acted on and either the file after
/// the act or the error code the context answered.
final class BatchOutcome {
  const BatchOutcome({
    required this.rkey,
    required this.ok,
    required this.file,
    required this.error,
  });

  factory BatchOutcome.fromJson(JsonReader reader) {
    final file = reader.objectOrNull('file');
    return BatchOutcome(
      rkey: reader.string('rkey'),
      ok: reader.boolean('ok'),
      file: file == null ? null : FileRecord.fromJson(file),
      error: reader.stringOrNull('error'),
    );
  }

  final String rkey;
  final bool ok;
  final FileRecord? file;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is BatchOutcome &&
      other.rkey == rkey &&
      other.ok == ok &&
      other.file == file &&
      other.error == error;

  @override
  int get hashCode => Object.hash(BatchOutcome, rkey, ok, file, error);
}

/// Which side of a grant the caller reads: the ones she gave (`owner`, she is
/// the dono) or the ones she received (`reader`, she is the leitor). Both come
/// with the revoked ones included.
enum GrantRole {
  owner,
  reader;

  static const Map<String, GrantRole> byWire = {
    'owner': owner,
    'reader': reader,
  };
}

/// The invite the zeladora minted. The token and the deep link come once.
final class MemberInvite {
  const MemberInvite({
    required this.ava,
    required this.token,
    required this.inviteUrl,
  });

  factory MemberInvite.fromJson(JsonReader reader) {
    return MemberInvite(
      ava: Ava.fromJson(reader.object('ava')),
      token: reader.string('token'),
      inviteUrl: reader.string('invite_url'),
    );
  }

  final Ava ava;
  final String token;
  final String inviteUrl;

  @override
  bool operator ==(Object other) =>
      other is MemberInvite &&
      other.ava == ava &&
      other.token == token &&
      other.inviteUrl == inviteUrl;

  @override
  int get hashCode => Object.hash(MemberInvite, ava, token, inviteUrl);
}

/// The password link of one morador, minted by the zeladora. Same one time
/// rule as the invite's token.
final class ResetLink {
  const ResetLink({
    required this.ava,
    required this.token,
    required this.resetUrl,
  });

  factory ResetLink.fromJson(JsonReader reader) {
    return ResetLink(
      ava: Ava.fromJson(reader.object('ava')),
      token: reader.string('token'),
      resetUrl: reader.string('reset_url'),
    );
  }

  final Ava ava;
  final String token;
  final String resetUrl;

  @override
  bool operator ==(Object other) =>
      other is ResetLink &&
      other.ava == ava &&
      other.token == token &&
      other.resetUrl == resetUrl;

  @override
  int get hashCode => Object.hash(ResetLink, ava, token, resetUrl);
}
