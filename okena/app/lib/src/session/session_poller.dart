import 'dart:async';

import 'package:flutter/foundation.dart';

/// The ticker behind the scene-active refresh poll.
///
/// The model starts it when the scene becomes active and stops it when the
/// scene leaves; tests inject a manual ticker so the interval never depends
/// on wall-clock time.
abstract class SessionPoller {
  void start(Duration interval, VoidCallback onTick);

  void stop();
}

/// Production: one periodic [Timer], replaced when a new interval starts.
final class TimerSessionPoller implements SessionPoller {
  Timer? _timer;

  @override
  void start(Duration interval, VoidCallback onTick) {
    stop();
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// The idle poller of previews and tests that drive `refresh` by hand.
final class IdleSessionPoller implements SessionPoller {
  const IdleSessionPoller();

  @override
  void start(Duration interval, VoidCallback onTick) {}

  @override
  void stop() {}
}
