import 'package:flutter/widgets.dart';

/// The scene lifecycle seam, seen from the session model.
///
/// Production reads Flutter's own lifecycle, so no view feeds the model.
/// Tests drive it directly, which is what makes the 30-second poll
/// deterministic without waiting on a real clock.
abstract class SessionLifecycle {
  void attach({
    required VoidCallback onActivated,
    required VoidCallback onDeactivated,
  });

  void detach();
}

/// Flutter's lifecycle, through [AppLifecycleListener].
///
/// The launch activation can land before the listener is registered, so an
/// already resumed scene is announced right away, the way the Swift model
/// reads `UIApplication.shared.applicationState`.
final class FlutterSessionLifecycle implements SessionLifecycle {
  FlutterSessionLifecycle({WidgetsBinding? binding})
    : _binding = binding ?? WidgetsBinding.instance;

  final WidgetsBinding _binding;
  AppLifecycleListener? _listener;

  @override
  void attach({
    required VoidCallback onActivated,
    required VoidCallback onDeactivated,
  }) {
    detach();
    _listener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          onActivated();
        } else {
          onDeactivated();
        }
      },
    );
    if (_binding.lifecycleState == AppLifecycleState.resumed) {
      onActivated();
    }
  }

  @override
  void detach() {
    _listener?.dispose();
    _listener = null;
  }
}

/// The detached lifecycle of previews and tests that do not drive the scene.
final class DetachedSessionLifecycle implements SessionLifecycle {
  const DetachedSessionLifecycle();

  @override
  void attach({
    required VoidCallback onActivated,
    required VoidCallback onDeactivated,
  }) {}

  @override
  void detach() {}
}
