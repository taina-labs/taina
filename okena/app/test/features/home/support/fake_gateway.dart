import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// A [SessionGateway] over [FakeTainaApi] whose screened calls can fail by
/// section, so each home card can be degraded on its own.
final class HomeTestGateway implements SessionGateway {
  @override
  Me? get identity => const Me(
    ava: Ava(
      publicId: 'ava-ana',
      username: 'ana',
      displayName: 'Ana Souza',
      papel: Papel.morador,
      activatedAt: '2026-01-01T00:00:00Z',
      deactivatedAt: null,
      createdAt: '2026-01-01T00:00:00Z',
    ),
    tekoa: Tekoa(
      publicId: 'tekoa-test',
      name: 'Quilombo do Café',
      domain: 'cafe.taina.local',
      storageQuotaBytes: 100,
      storageUsedBytes: 50,
      createdAt: '2026-01-01T00:00:00Z',
    ),
    device: null,
  );

  HomeTestGateway({Duration delay = Duration.zero}) {
    api = FakeTainaApi(delay: delay);
    thumbnails = ThumbnailStore(api: api);
  }

  @override
  late final TainaApi api;

  @override
  late final ThumbnailStore thumbnails;

  bool failNextScreen = false;
  bool failStats = false;
  bool failRecent = false;
  bool failMural = false;
  bool failRequests = false;
  bool failMembers = false;
  bool failHealth = false;
  bool emptyRecent = false;

  int screenCalls = 0;
  int storageCalls = 0;
  int recentCalls = 0;
  int muralCalls = 0;
  int requestsCalls = 0;
  int membersCalls = 0;
  int healthCalls = 0;

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async {
    screenCalls += 1;
    if (failNextScreen) {
      failNextScreen = false;
      return Err<T>(const NetworkError());
    }
    if (outcome is Ok<StorageStats>) {
      storageCalls += 1;
      if (failStats) return Err<T>(const NetworkError());
    } else if (outcome is Ok<Saude>) {
      healthCalls += 1;
      if (failHealth) return Err<T>(const NetworkError());
    } else if (outcome is Ok<Page<FileRecord>>) {
      recentCalls += 1;
      if (failRecent) return Err<T>(const NetworkError());
      if (emptyRecent) {
        return Ok<Page<FileRecord>>(
          Page<FileRecord>(items: const [], nextCursor: null),
        ) as TainaResult<T>;
      }
    } else if (outcome is Ok<Page<MuralEntry>>) {
      muralCalls += 1;
      if (failMural) return Err<T>(const NetworkError());
    } else if (outcome is Ok<Page<Ava>>) {
      membersCalls += 1;
      if (failMembers) return Err<T>(const NetworkError());
    } else if (outcome is Ok<Page<Pedido>>) {
      requestsCalls += 1;
      if (failRequests) return Err<T>(const NetworkError());
    }
    return outcome;
  }
}
