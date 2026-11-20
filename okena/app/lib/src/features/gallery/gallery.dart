/// Jaci, the Galeria screen: the grid and timeline, shared thumbnail store,
/// session-owned upload handoff and fullscreen media viewer.
///
/// The app integration provides a `SessionGateway`, wires
/// [GalleryScreen.onShareFile] to the system share sheet, supplies a
/// `MediaPicker` and `UploadCenter`, and owns the route replacement callbacks.
/// [GalleryVideoPlayerFactory] can be injected for tests.
library;

export 'gallery_details.dart';
export 'gallery_model.dart';
export 'gallery_screen.dart';
export 'gallery_thumbnail.dart';
export 'gallery_video.dart';
export 'gallery_viewer.dart';
