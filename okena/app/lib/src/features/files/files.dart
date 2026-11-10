/// The files feature: the root and folder browser, the file screen, the move
/// sheet and the platform boundaries behind them.
///
/// The orchestrator wires navigation and provides a [SessionGateway] and a
/// [FileActions]; the production implementation is [PlatformFileActions].
library;

export 'browser_list.dart';
export 'browser_scaffold.dart';
export 'file_actions.dart';
export 'file_detail_screen.dart';
export 'file_detail_view_model.dart';
export 'file_row.dart';
export 'files_logic.dart';
export 'files_screen.dart';
export 'files_view_model.dart';
export 'folder_actions_view_model.dart';
export 'folder_screen.dart';
export 'move_sheet.dart';
export 'move_view_model.dart';
export 'platform_file_actions.dart';
