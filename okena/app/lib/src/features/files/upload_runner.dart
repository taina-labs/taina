import 'package:okena_core/okena_core.dart';

import '../../session/session_gateway.dart';
import 'file_actions.dart';

/// The one path from a local picked file to the authenticated upload API.
final class UploadRunner {
  const UploadRunner({required this.session});

  final SessionGateway session;

  Future<TainaResult<FileRecord>> upload(
    PickedFile file, {
    String? folderRkey,
  }) async {
    return session.screen(
      await session.api.upload(
        filePath: file.path,
        name: file.name,
        mime: file.mime,
        folderRkey: folderRkey,
      ),
    );
  }
}
