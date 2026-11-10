import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The test seam for [SessionGateway].
///
/// It passes the outcome through untouched, except for `GET /me`: when a
/// [me] is given, that identity answers instead. The production model still
/// asks the API; the fake only supplies a signed-in identity to a
/// [FakeTainaApi] that keeps no session.
final class FakeSession implements SessionGateway {
  FakeSession(this._api, {this.me});

  final TainaApi _api;
  final Me? me;

  @override
  TainaApi get api => _api;

  @override
  Me? get identity => me;

  @override
  late final ThumbnailStore thumbnails = ThumbnailStore(api: _api);

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async {
    final Me? injected = me;
    if (injected != null && T == Me) {
      return Ok<Me>(injected) as TainaResult<T>;
    }
    return outcome;
  }
}

const Ava ana = Ava(
  publicId: 'avap2xw5m8q3',
  username: 'ana',
  displayName: 'Ana Souza',
  papel: Papel.zelador,
  activatedAt: '2026-02-01T09:00:00Z',
  deactivatedAt: null,
  createdAt: '2026-02-01T09:00:00Z',
);

const Ava joana = Ava(
  publicId: 'avaq7r2m5xk9p1',
  username: 'joana',
  displayName: 'Joana Reis',
  papel: Papel.morador,
  activatedAt: '2026-02-02T09:00:00Z',
  deactivatedAt: null,
  createdAt: '2026-02-02T09:00:00Z',
);

const Tekoa tekoa = Tekoa(
  publicId: 'tekp2xw5m8q3',
  name: 'Tekoa Sapukai',
  domain: 'taina.sapukai.ts.net',
  storageQuotaBytes: 268435456000,
  storageUsedBytes: 1832110000,
  createdAt: '2026-02-01T09:00:00Z',
);

const DeviceToken currentDevice = DeviceToken(
  publicId: 'devcurrent01',
  name: 'iPhone da Ana',
  lastUsedAt: '2026-10-14T10:00:00Z',
  revokedAt: null,
  createdAt: '2026-05-12T11:00:00Z',
);

Me identity(Ava ava, {DeviceToken? device}) {
  return Me(ava: ava, tekoa: tekoa, device: device ?? currentDevice);
}

const ApiError offline = ApiError(
  code: 'network_error',
  status: 0,
  serverMessage: 'Não foi possível falar com a comunidade.',
);

/// A [TainaApi] that owns the device list, so the account screens can be
/// exercised with an active current device and an active other one. Every
/// other call is the real fake's.
final class DevicesApi implements TainaApi {
  DevicesApi(this._inner, List<DeviceToken> devices) : _devices = [...devices];

  final TainaApi _inner;
  final List<DeviceToken> _devices;

  /// The ids revoked through this seam, in order.
  final List<String> revoked = [];

  List<DeviceToken> get listed => List<DeviceToken>.unmodifiable(_devices);

  @override
  Future<TainaResult<List<DeviceToken>>> devices() async {
    return Ok(listed);
  }

  @override
  Future<TainaResult<void>> revokeDevice({required String id}) async {
    final int index = _devices.indexWhere(
      (DeviceToken device) => device.publicId == id,
    );
    if (index < 0) {
      return const Err(
        ApiError(
          code: 'not_found',
          status: 404,
          serverMessage: 'Não encontramos este aparelho.',
        ),
      );
    }
    final DeviceToken device = _devices[index];
    _devices[index] = DeviceToken(
      publicId: device.publicId,
      name: device.name,
      lastUsedAt: device.lastUsedAt,
      revokedAt: '2026-10-14T12:00:00Z',
      createdAt: device.createdAt,
    );
    revoked.add(id);
    return const Ok<void>(null);
  }

  @override
  Future<TainaResult<Me>> me() => _inner.me();

  @override
  Future<TainaResult<Instance>> instance() => _inner.instance();

  @override
  Future<TainaResult<void>> updatePassword({
    required String current,
    required String newPassword,
  }) {
    return _inner.updatePassword(current: current, newPassword: newPassword);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const DeviceToken otherDevice = DeviceToken(
  publicId: 'devother02',
  name: 'Tablet da Ana',
  lastUsedAt: '2026-10-13T10:00:00Z',
  revokedAt: null,
  createdAt: '2026-06-12T11:00:00Z',
);
