import 'package:flutter/widgets.dart';

/// The small lifecycle boundary used by the mirror runtime.
abstract interface class MirrorForeground {
  bool get isForeground;

  void attach(void Function(bool isForeground) onChanged);

  void dispose();
}

/// Reads app lifecycle changes without making the mirror runtime depend on
/// Flutter's binding.
final class FlutterMirrorForeground implements MirrorForeground {
  FlutterMirrorForeground();

  AppLifecycleListener? _listener;
  void Function(bool isForeground)? _onChanged;
  bool? _lastState;

  @override
  bool get isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void attach(void Function(bool isForeground) onChanged) {
    if (_listener != null) return;
    _onChanged = onChanged;
    _lastState = isForeground;
    _listener = AppLifecycleListener(onStateChange: _handleStateChange);
  }

  void _handleStateChange(AppLifecycleState state) {
    final next = state == AppLifecycleState.resumed;
    if (_lastState == next) return;
    _lastState = next;
    _onChanged?.call(next);
  }

  @override
  void dispose() {
    _listener?.dispose();
    _listener = null;
    _onChanged = null;
    _lastState = null;
  }
}
