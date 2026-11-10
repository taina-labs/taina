import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/session_gateway.dart';
import 'files_logic.dart';

/// The move sheet's state: every readable folder, filtered by the pure rule
/// so the source and its descendants are never offered.
final class MoveViewModel extends ChangeNotifier {
  MoveViewModel({
    required this.session,
    required this.sourceRkey,
    required this.isFolder,
  });

  final SessionGateway session;
  final String sourceRkey;
  final bool isFolder;

  List<Folder> _folders = const [];
  bool _loading = true;
  TainaError? _error;

  bool get loading => _loading;
  TainaError? get error => _error;

  List<Folder> get destinations => FilesLogic.moveDestinations(
    sourceRkey: sourceRkey,
    isFolder: isFolder,
    folders: _folders,
  );

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final result = await session.screen(await session.api.listFolders());
    switch (result) {
      case Ok(:final value):
        _folders = value;
      case Err(:final error):
        _error = error;
    }
    _loading = false;
    notifyListeners();
  }
}
