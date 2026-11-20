import 'package:okena_core/okena_core.dart';

import '../session/session_state.dart';

/// Canonical app locations. The hub is the root and every service place is a
/// route, so selecting a place can replace the current service location.
abstract final class AppRoutes {
  static const String home = '/';
  static const String login = '/login';
  static const String checking = '/checking';
  static const String inviteAuth = '/convite';
  static const String invitePaste = '/convite/colar';
  static const String resetAuth = '/redefinir';

  static const String documentsPraca = '/documentos/praca';
  static const String documentsCasa = '/documentos/casa';
  static const String documentsTrash = '/documentos/lixeira';
  static const String documentsUpload = '/documentos/enviar';

  static const String galleryGrid = '/galeria/grade';
  static const String galleryTimeline = '/galeria/linha-do-tempo';
  static const String galleryViewer = '/galeria/visualizador';

  static const String mural = '/mural';
  static const String health = '/saude';
  static const String members = '/moradores';
  static const String inviteMember = '/moradores/convidar';
  static const String storage = '/armazenamento';
  static const String account = '/conta';
  static const String requests = '/conta/pedidos';
  static const String privacy = '/conta/privacidade';
  static const String devices = '/conta/dispositivos';
  static const String cameraRoll = '/conta/rolo-de-camera';

  static String folder(String rkey, Zona zona) =>
      '/documentos/pasta/${Uri.encodeComponent(rkey)}'
      '?zona=${zona.name}';

  static String file(String rkey) =>
      '/documentos/arquivo/${Uri.encodeComponent(rkey)}';

  static String galleryPhoto(String rkey) =>
      '$galleryViewer/${Uri.encodeComponent(rkey)}';
}

enum ServiceTab {
  documentsPraca(AppRoutes.documentsPraca),
  documentsCasa(AppRoutes.documentsCasa),
  documentsTrash(AppRoutes.documentsTrash),
  galleryGrid(AppRoutes.galleryGrid),
  galleryTimeline(AppRoutes.galleryTimeline);

  const ServiceTab(this.location);

  final String location;
}

/// Resolves a service tab as a destination, not as another item on a tab
/// history stack. Callers should replace the current route, never push.
String serviceTabLocation(ServiceTab tab) => tab.location;

/// Maps the debug launch shortcut to a real route, without route-stack state.
///
/// Examples: `documentos/casa`, `galeria/linha-do-tempo`, `pasta/<rkey>`,
/// or any already-canonical local path.
String? debugRouteLocation(String? value) {
  final String raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  if (raw.startsWith('/')) return _isSafeLocalLocation(raw) ? raw : null;

  const Map<String, String> known = {
    'inicio': AppRoutes.home,
    'hub': AppRoutes.home,
    'documentos/praca': AppRoutes.documentsPraca,
    'documentos/casa': AppRoutes.documentsCasa,
    'documentos/lixeira': AppRoutes.documentsTrash,
    'documentos/enviar': AppRoutes.documentsUpload,
    'galeria/grade': AppRoutes.galleryGrid,
    'galeria/linha-do-tempo': AppRoutes.galleryTimeline,
    'galeria/visualizador': AppRoutes.galleryViewer,
    'mural': AppRoutes.mural,
    'saude': AppRoutes.health,
    'moradores': AppRoutes.members,
    'moradores/convidar': AppRoutes.inviteMember,
    'armazenamento': AppRoutes.storage,
    'conta': AppRoutes.account,
    'conta/pedidos': AppRoutes.requests,
    'conta/privacidade': AppRoutes.privacy,
    'conta/dispositivos': AppRoutes.devices,
    'conta/rolo-de-camera': AppRoutes.cameraRoll,
  };
  final String? location = known[raw];
  if (location != null) return location;

  if (raw.startsWith('pasta/')) {
    final Uri? parsed = Uri.tryParse('/$raw');
    if (parsed == null) return null;
    final List<String> segments = parsed.pathSegments;
    if (segments.length != 2 || segments.last.isEmpty) return null;
    final String zone = parsed.queryParameters['zona'] ?? 'praca';
    if (zone != 'casa' && zone != 'praca') return null;
    return AppRoutes.folder(segments.last, Zona.values.byName(zone));
  }

  if (raw.startsWith('arquivo/')) {
    final String rkey = raw.substring('arquivo/'.length);
    if (rkey.isEmpty || rkey.contains('/')) return null;
    return AppRoutes.file(rkey);
  }
  if (raw.startsWith('galeria/visualizador/')) {
    final String rkey = raw.substring('galeria/visualizador/'.length);
    if (rkey.isEmpty || rkey.contains('/')) return null;
    return AppRoutes.galleryPhoto(rkey);
  }

  return null;
}

/// Whether a route represents a place inside a service. Details, upload and
/// the fullscreen viewer intentionally have no service tab bar.
bool serviceTabBarVisible(String location) {
  final String path = _pathOf(location);
  if (path == AppRoutes.documentsPraca ||
      path == AppRoutes.documentsCasa ||
      path == AppRoutes.documentsTrash ||
      path.startsWith('/documentos/pasta/')) {
    return true;
  }
  return path == AppRoutes.galleryGrid || path == AppRoutes.galleryTimeline;
}

/// Invitation creation is a zelador-only action, including direct links.
bool inviteRouteAllowed(Papel? papel) => papel == Papel.zelador;

/// The iOS/mobile back label rule, expressed without router or widget state.
String parentAwareBackLabel({required bool parentIsHub, String? parentName}) {
  if (parentIsHub) return 'Início';
  final String parent = parentName?.trim() ?? '';
  if (parent.isEmpty || parent.length > 12) return 'Voltar';
  return parent;
}

/// Keeps a local deep link through restore and login. The `from` parameter is
/// internal router state and is never allowed to become an external URL.
String? sessionRedirect(SessionState state, String location) {
  final Uri uri = Uri.tryParse(location) ?? Uri(path: location);
  final String path = uri.path;
  final String? intended = _intendedLocation(uri, path);

  switch (state) {
    case SessionChecking():
      if (path == AppRoutes.checking) return null;
      return _withReturnLocation(AppRoutes.checking, intended);
    case SessionNeedsInstance():
    case SessionNeedsLogin():
      if (path == AppRoutes.invitePaste) return null;
      if (intended == AppRoutes.invitePaste) return AppRoutes.invitePaste;
      if (path == AppRoutes.login) return null;
      return _withReturnLocation(AppRoutes.login, intended);
    case SessionPendingAuth(:final pending):
      final String target = pending.kind == PendingAuthKind.invite
          ? AppRoutes.inviteAuth
          : AppRoutes.resetAuth;
      return path == target ? null : target;
    case SessionReady():
      const Set<String> preAuth = {
        AppRoutes.checking,
        AppRoutes.login,
        AppRoutes.inviteAuth,
        AppRoutes.resetAuth,
        '/setup',
      };
      if (preAuth.contains(path) || path.isEmpty) {
        return intended ?? AppRoutes.home;
      }
      return null;
  }
}

String? _intendedLocation(Uri uri, String path) {
  final String? from = uri.queryParameters['from'];
  if (from != null && _isSafeLocalLocation(from)) return from;
  if (path == AppRoutes.invitePaste) return AppRoutes.invitePaste;

  const Set<String> preAuth = {
    AppRoutes.checking,
    AppRoutes.login,
    AppRoutes.inviteAuth,
    AppRoutes.resetAuth,
    '/setup',
  };
  if (preAuth.contains(path)) return null;
  final String value = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  return _isSafeLocalLocation(value) ? value : null;
}

String _withReturnLocation(String path, String? intended) {
  if (intended == null || intended == AppRoutes.home) return path;
  return Uri(path: path, queryParameters: {'from': intended}).toString();
}

bool _isSafeLocalLocation(String location) {
  final Uri? parsed = Uri.tryParse(location);
  return parsed != null &&
      !parsed.hasScheme &&
      !parsed.hasAuthority &&
      parsed.path.startsWith('/');
}

String _pathOf(String location) =>
    (Uri.tryParse(location)?.path ?? location).split('?').first;
