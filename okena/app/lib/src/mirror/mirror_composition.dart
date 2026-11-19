import 'package:okena_app/src/mirror/background_mirror_transfer.dart';
import 'package:okena_app/src/mirror/file_mirror_store.dart';
import 'package:okena_app/src/mirror/mirror_engine.dart';
import 'package:okena_app/src/mirror/mirror_foreground.dart';
import 'package:okena_app/src/mirror/mirror_runtime.dart';
import 'package:okena_app/src/mirror/mirror_settings.dart';
import 'package:okena_app/src/mirror/photo_manager_asset_materializer.dart';
import 'package:okena_app/src/mirror/photo_manager_mirror_library.dart';
import 'package:okena_app/src/mirror/streaming_mirror_hasher.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_app/src/session/session_model.dart';
import 'package:okena_core/okena_core.dart';

abstract final class MirrorComposition {
  /// Builds the production mirror runtime. Tests may replace the owner factory
  /// and lifecycle edge to avoid constructing platform plugins.
  static MirrorRuntime production(
    SessionModel session, {
    MirrorOwnerFactory? ownerFactory,
    MirrorForeground? foreground,
    MirrorSettings? settings,
  }) => MirrorRuntime(
    changes: session,
    identity: () => session.identity,
    foreground: foreground ?? FlutterMirrorForeground(),
    ownerFactory:
        ownerFactory ??
        ({required ownerId, required identity}) => _createProductionOwner(
          session,
          ownerId,
          identity,
          settings ?? PreferencesMirrorSettings(),
        ),
  );

  static Future<TainaResult<MirrorOwnerMirror>> _createProductionOwner(
    SessionModel session,
    String ownerId,
    Me identity,
    MirrorSettings settings,
  ) async {
    final baseApi = session.api;
    if (baseApi is! LiveTainaApi) {
      return const Err(NotSignedInError());
    }

    final address = session.host;
    if (address == null) {
      return const Err(InvalidAddressError(AddressProblem.empty));
    }

    final current = baseApi.session.current;
    if (current == null) return const Err(NotSignedInError());

    final scopedSession = SessionStore(
      storage: InMemorySessionStorage(current),
    );
    final restored = await scopedSession.restore();
    if (restored case Err<Session?>(:final error)) return Err(error);
    if ((restored as Ok<Session?>).value == null) {
      return const Err(NotSignedInError());
    }

    final loadedSettings = await settings.load(ownerId);
    if (loadedSettings case Err<MirrorPreferences>(:final error)) {
      return Err(error);
    }
    final preferences = (loadedSettings as Ok<MirrorPreferences>).value;

    final scopedApi = LiveTainaApi(
      transport: baseApi.transport,
      host: InMemoryHostStore(address),
      session: scopedSession,
    );
    MirrorOwnerMirror? owner;
    final gateway = _OwnerSessionGateway(
      api: scopedApi,
      thumbnails: session.thumbnails,
      identity: identity,
      session: session,
      isActive: () => owner?.isActive ?? false,
    );

    final library = PhotoManagerMirrorLibrary();
    final materializer = PhotoManagerAssetMaterializer(
      ownerId: ownerId,
      originalFileProvider: library,
    );
    final store = FileMirrorStore(ownerId: ownerId);
    final transfer = BackgroundMirrorTransfer(
      ownerId: ownerId,
      requestProvider: () async => LiveTainaApi.build(
        base: address.url,
        path: 'files',
        method: 'POST',
        authenticated: true,
        token: current.token,
      ),
      requiresWiFiProvider: () => owner?.wifiOnly ?? preferences.wifiOnly,
    );
    final engine = MirrorEngine(
      session: gateway,
      store: store,
      hasher: StreamingMirrorAssetHasher(materializer),
      transfer: transfer,
      ownerId: ownerId,
    );

    owner = MirrorOwnerMirror(
      engine: engine,
      library: library,
      store: store,
      materializer: materializer,
      transferEvents: transfer.events,
      startTransfer: transfer.start,
      disposeTransfer: transfer.dispose,
      enabled: preferences.enabled,
      wifiOnly: preferences.wifiOnly,
      persistPreferences: (next) => settings.save(ownerId, next),
    );
    return Ok(owner);
  }
}

final class _OwnerSessionGateway implements SessionGateway {
  const _OwnerSessionGateway({
    required this.api,
    required this.thumbnails,
    required this.identity,
    required this.session,
    required this.isActive,
  });

  @override
  final TainaApi api;

  @override
  final ThumbnailStore thumbnails;

  @override
  final Me identity;
  final SessionModel session;

  final bool Function() isActive;

  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) {
    if (!isActive()) return Future.value(outcome);
    return session.screen(outcome);
  }
}
