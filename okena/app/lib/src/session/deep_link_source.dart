import 'package:flutter/widgets.dart';

import 'deep_link.dart';

/// The native deep-link seam.
///
/// The Flutter engine hands incoming URLs to the binding as route
/// information, so this observes the binding instead of adding `app_links`.
/// Production registers it before the router is built, which is what lets a
/// cold-start link win the restore race.
abstract class DeepLinkSource {
  void attach(void Function(Uri uri) onLink);

  void detach();
}

/// Flutter's own navigation channel.
///
/// `didPushRouteInformation` returns true only for a URL this app owns, so
/// ordinary route information still reaches `go_router`. A cold-start link
/// lives in `platformDispatcher.defaultRouteName` and is delivered once,
/// asynchronously, after the caller finished composing.
final class PlatformDeepLinkSource
    with WidgetsBindingObserver
    implements DeepLinkSource {
  PlatformDeepLinkSource({WidgetsBinding? binding})
    : _binding = binding ?? WidgetsBinding.instance;

  final WidgetsBinding _binding;
  void Function(Uri uri)? _onLink;

  @override
  void attach(void Function(Uri uri) onLink) {
    _onLink = onLink;
    _binding.addObserver(this);
    final initial = _binding.platformDispatcher.defaultRouteName;
    final uri = Uri.tryParse(initial);
    if (uri != null && DeepLink.parse(uri) != null) {
      Future<void>.microtask(() => _deliver(uri));
    }
  }

  @override
  void detach() {
    _onLink = null;
    _binding.removeObserver(this);
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final uri = routeInformation.uri;
    if (DeepLink.parse(uri) == null) return false;
    _deliver(uri);
    return true;
  }

  void _deliver(Uri uri) {
    _onLink?.call(uri);
  }
}

/// The inert source of previews and tests that call the model directly.
final class DetachedDeepLinkSource implements DeepLinkSource {
  const DetachedDeepLinkSource();

  @override
  void attach(void Function(Uri uri) onLink) {}

  @override
  void detach() {}
}
