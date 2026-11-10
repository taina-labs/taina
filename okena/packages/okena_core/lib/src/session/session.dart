import 'package:okena_core/src/json/api_coding.dart';
import 'package:okena_core/src/models/wire.dart';

/// What `POST /session` returns and what gets persisted: the same shape by
/// contract (`token`, `device`, `me`, `tekoa`), so one type, not two. The
/// token is the raw device secret (`tnd_...`), shown once, kept here.
final class Session {
  const Session({
    required this.token,
    required this.device,
    required this.me,
    required this.tekoa,
  });

  factory Session.fromJson(JsonReader reader) {
    return Session(
      token: reader.string('token'),
      device: DeviceToken.fromJson(reader.object('device')),
      me: Ava.fromJson(reader.object('me')),
      tekoa: Tekoa.fromJson(reader.object('tekoa')),
    );
  }

  /// The JSON the platform-backed [SessionStorage] persists. The device token
  /// never leaves the device's secure storage.
  factory Session.fromPersistedJson(Map<String, Object?> json) {
    return Session.fromJson(JsonReader(json, 'stored session'));
  }

  final String token;
  final DeviceToken device;
  final Ava me;
  final Tekoa tekoa;

  /// The identity a restored session already carries, without another round
  /// trip: the shape `GET /me` answers with.
  Me get identity => Me(ava: me, tekoa: tekoa, device: device);

  Map<String, Object?> toJson() => {
    'token': token,
    'device': device.toJson(),
    'me': me.toJson(),
    'tekoa': tekoa.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Session &&
      other.token == token &&
      other.device == device &&
      other.me == me &&
      other.tekoa == tekoa;

  @override
  int get hashCode => Object.hash(Session, token, device, me, tekoa);
}

/// `GET /me`: the same identity without the token.
final class Me {
  const Me({required this.ava, required this.tekoa, required this.device});

  factory Me.fromJson(JsonReader reader) {
    final device = reader.objectOrNull('device');
    return Me(
      ava: Ava.fromJson(reader.object('ava')),
      tekoa: Tekoa.fromJson(reader.object('tekoa')),
      device: device == null ? null : DeviceToken.fromJson(device),
    );
  }

  final Ava ava;
  final Tekoa tekoa;
  final DeviceToken? device;

  @override
  bool operator ==(Object other) =>
      other is Me &&
      other.ava == ava &&
      other.tekoa == tekoa &&
      other.device == device;

  @override
  int get hashCode => Object.hash(Me, ava, tekoa, device);
}
