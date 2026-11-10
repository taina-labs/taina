import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_gateway.dart';

/// The acts on the folder itself, not on its contents: the caller owns what
/// the screen shows of the folder afterwards. The results are screened like
/// every other call, so a 401 leaves on its own.
final class FolderActionsViewModel extends ChangeNotifier {
  FolderActionsViewModel({required this.session});

  final SessionGateway session;

  bool _working = false;

  bool get working => _working;

  Future<TainaResult<Folder>> rename(Folder folder, String name) {
    return _run(() => session.api.updateFolder(rkey: folder.rkey, name: name));
  }

  /// Moves the folder under another one, null for the root.
  Future<TainaResult<Folder>> move(Folder folder, Folder? parent) {
    return _run(
      () => session.api.moveFolder(rkey: folder.rkey, parentRkey: parent?.rkey),
    );
  }

  /// The same updateFolder the rename uses, with the zona instead of the
  /// name: publishing to the praca and coming back are one field.
  Future<TainaResult<Folder>> setZona(Folder folder, Zona zona) {
    return _run(() => session.api.updateFolder(rkey: folder.rkey, zona: zona));
  }

  Future<TainaResult<void>> delete(Folder folder) async {
    _working = true;
    notifyListeners();
    final result = await session.screen(
      await session.api.deleteFolder(rkey: folder.rkey),
    );
    _working = false;
    notifyListeners();
    return result;
  }

  Future<TainaResult<Folder>> _run(
    Future<TainaResult<Folder>> Function() call,
  ) async {
    _working = true;
    notifyListeners();
    final result = await session.screen(await call());
    _working = false;
    notifyListeners();
    return result;
  }
}
