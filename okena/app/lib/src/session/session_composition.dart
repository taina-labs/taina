import 'package:okena_core/okena_core.dart';

import 'deep_link_source.dart';
import 'local_network_gate.dart';
import 'preferences_host_store.dart';
import 'secure_session_storage.dart';
import 'session_lifecycle.dart';
import 'session_model.dart';
import 'session_poller.dart';

/// The two composition roots of the session: the real one the app runs, and
/// the fake one previews and tests use.
abstract final class SessionComposition {
  /// The production model: `IoTransport`, `LiveTainaApi`, platform secure
  /// storage and `shared_preferences`.
  ///
  /// The probe builds a temporary `LiveTainaApi` per candidate address over
  /// an in-memory host store, so trying https and then http never disturbs
  /// the address the app has already kept.
  static SessionModel production({
    SessionStorage? storage,
    HostStore? hostStore,
    Transport? transport,
    SessionLifecycle? lifecycle,
    SessionPoller? poller,
    LocalNetworkGate? localNetwork,
  }) {
    final savedHosts = hostStore ?? PreferencesHostStore();
    final sessions = SessionStore(storage: storage ?? SecureSessionStorage());
    final wire = transport ?? IoTransport();
    final api = LiveTainaApi(
      transport: wire,
      host: savedHosts,
      session: sessions,
    );

    return SessionModel(
      api: api,
      store: sessions,
      hostStore: savedHosts,
      probe: (address) => LiveTainaApi(
        transport: wire,
        host: InMemoryHostStore(address),
        session: sessions,
      ).instance(),
      lifecycle: lifecycle ?? FlutterSessionLifecycle(),
      poller: poller ?? TimerSessionPoller(),
      deepLinks: PlatformDeepLinkSource(),
      localNetwork: localNetwork ?? const PermissionLocalNetworkGate(),
    );
  }

  /// A model over the fake API: no box, no network, no platform plugins.
  static SessionModel fake({
    FakeTainaApi? api,
    InstanceAddress? host,
    SessionStorage? storage,
    SessionLifecycle? lifecycle,
    SessionPoller? poller,
  }) {
    final fakeApi = api ?? FakeTainaApi(delay: Duration.zero);
    final sessions = SessionStore(storage: storage ?? InMemorySessionStorage());

    return SessionModel(
      api: fakeApi,
      store: sessions,
      hostStore: InMemoryHostStore(host),
      probe: (_) => fakeApi.instance(),
      lifecycle: lifecycle ?? const DetachedSessionLifecycle(),
      poller: poller ?? const IdleSessionPoller(),
      deepLinks: const DetachedDeepLinkSource(),
      localNetwork: const AllowLocalNetworkGate(),
    );
  }
}
