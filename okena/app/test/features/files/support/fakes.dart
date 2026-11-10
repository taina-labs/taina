import 'package:okena_app/src/features/files/file_actions.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

/// The session contract the feature consumes, without the concrete session
/// model. [thumbnails] can be backed by a different API so a denied-download
/// double still serves preview thumbnails.
final class FakeSessionGateway implements SessionGateway {
  @override
  Me? get identity => null;

  FakeSessionGateway({required this.api, ThumbnailStore? thumbnails})
    : thumbnails = thumbnails ?? ThumbnailStore(api: api);

  @override
  final TainaApi api;

  @override
  final ThumbnailStore thumbnails;

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async => outcome;
}

/// Deterministic platform boundary: no picker, no share sheet, no viewer.
final class FakeFileActions implements FileActions {
  PickedFileOutcome pickOutcome = const PickedFileCancelled();
  String? shareFailure;
  String? openFailure;
  final List<String> sharedPaths = [];
  final List<String> openedPaths = [];
  final List<String?> shareSubjects = [];

  @override
  Future<PickedFileOutcome> pick() async => pickOutcome;

  @override
  Future<String?> share(String path, {String? subject}) async {
    if (shareFailure != null) return shareFailure;
    sharedPaths.add(path);
    shareSubjects.add(subject);
    return null;
  }

  @override
  Future<String?> open(String path) async {
    if (openFailure != null) return openFailure;
    openedPaths.add(path);
    return null;
  }
}
