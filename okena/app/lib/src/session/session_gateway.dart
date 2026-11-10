import 'package:okena_core/okena_core.dart';

/// The session surface consumed by feature ViewModels.
///
/// The concrete session model owns authentication and app lifecycle. Features
/// depend on this contract so they can be implemented and tested independently.
abstract class SessionGateway {
  TainaApi get api;
  ThumbnailStore get thumbnails;

  /// The identity already held by the session, when one is ready. Features use
  /// it as an offline-friendly display fallback instead of another API call.
  Me? get identity => null;

  /// Applies the shared deactivated/unauthorized handling to an API result.
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome);
}
