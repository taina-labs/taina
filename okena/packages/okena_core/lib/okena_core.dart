/// Pure Dart core for Tainá clients.
///
/// The package owns the API boundary, transport, immutable models,
/// result/error values, session contracts, fakes and unit tests. It cannot
/// import Flutter or platform plugins.
library;

export 'src/api/conditional_store.dart';
export 'src/api/fake_taina_api.dart';
export 'src/api/instance_address.dart';
export 'src/api/live_taina_api.dart';
export 'src/api/multipart_body.dart';
export 'src/api/sort.dart';
export 'src/api/taina_api.dart';
export 'src/json/api_coding.dart';
export 'src/json/json_value.dart';
export 'src/media/thumbnail_store.dart';
export 'src/models/access.dart';
export 'src/models/mural.dart';
export 'src/models/page.dart';
export 'src/models/storage.dart';
export 'src/models/timeline.dart';
export 'src/models/token_status.dart';
export 'src/models/wire.dart';
export 'src/result.dart';
export 'src/session/host_store.dart';
export 'src/session/session.dart';
export 'src/session/session_storage.dart';
export 'src/session/session_store.dart';
export 'src/taina_error.dart';
export 'src/transport/io_transport.dart';
export 'src/transport/transport.dart';
