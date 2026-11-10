/// Jaci, the Fotos screen: the grid and the timeline over the same readable
/// set, the casa/praça filter, the shared thumbnail store and the fullscreen
/// viewer with its photo and video pages.
///
/// The app integration provides a `SessionGateway`, wires
/// [GalleryScreen.onShareFile] to the system share sheet and may inject a
/// `GalleryVideoPlayerFactory`; navigation never lives here.
library;

export 'gallery_details.dart';
export 'gallery_model.dart';
export 'gallery_screen.dart';
export 'gallery_thumbnail.dart';
export 'gallery_video.dart';
export 'gallery_viewer.dart';
