import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// A [SessionGateway] over [FakeTainaApi] whose screened calls can fail by
/// section, so each home card can be degraded on its own.
final class HomeTestGateway implements SessionGateway {
  @override
  Me? get identity => null;

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

  int screenCalls = 0;
  int storageCalls = 0;
  int recentCalls = 0;
  int muralCalls = 0;
  int requestsCalls = 0;

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
    } else if (outcome is Ok<Page<FileRecord>>) {
      recentCalls += 1;
      if (failRecent) return Err<T>(const NetworkError());
    } else if (outcome is Ok<Page<MuralEntry>>) {
      muralCalls += 1;
      if (failMural) return Err<T>(const NetworkError());
    } else if (outcome is Ok<Page<Pedido>>) {
      requestsCalls += 1;
      if (failRequests) return Err<T>(const NetworkError());
    }
    return outcome;
  }
}
