// The public named parameters cannot be initializing formals because the
// fields they assign are private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import 'deep_link.dart';
import 'deep_link_source.dart';
import 'local_network_gate.dart';
import 'session_gateway.dart';
import 'session_lifecycle.dart';
import 'session_poller.dart';
import 'session_state.dart';

/// The per-address probe a connect runs. Production builds a `LiveTainaApi`
/// over the address and the shared session store; the fake composition answers
/// from its in-memory world.
typedef InstanceProbe = Future<TainaResult<Instance>> Function(
  InstanceAddress address,
);

/// The app's session: which box, which person, and the API bound to both.
///
/// The imperative shell only assigns and calls; every decision lives here or
/// in a pure helper. Features depend on [SessionGateway], never on this class.
final class SessionModel extends ChangeNotifier implements SessionGateway {
  SessionModel({
    required TainaApi api,
    required SessionStore store,
    required HostStore hostStore,
    required InstanceProbe probe,
    SessionLifecycle? lifecycle,
    SessionPoller? poller,
    DeepLinkSource? deepLinks,
    LocalNetworkGate? localNetwork,
    this.pollInterval = const Duration(seconds: 30),
  }) : _api = api,
       _store = store,
       _hostStore = hostStore,
       _probe = probe,
       _lifecycle = lifecycle ?? const DetachedSessionLifecycle(),
       _poller = poller ?? const IdleSessionPoller(),
       _deepLinks = deepLinks,
       _localNetwork = localNetwork ?? const AllowLocalNetworkGate(),
       _thumbnails = ThumbnailStore(api: api);

  /// A model already in a state, for previews and isolated router tests.
  ///
  /// The running app never uses this path: it arrives through [restore] and
  /// [connect]. The store is still real, so leaving and the forced sign out
  /// behave like the production flow.
  @visibleForTesting
  factory SessionModel.seeded({
    required TainaApi api,
    required SessionStore store,
    required HostStore hostStore,
    required SessionState state,
    InstanceProbe? probe,
    SessionLifecycle? lifecycle,
    SessionPoller? poller,
    DeepLinkSource? deepLinks,
    LocalNetworkGate? localNetwork,
    Duration pollInterval = const Duration(seconds: 30),
  }) {
    final model = SessionModel(
      api: api,
      store: store,
      hostStore: hostStore,
      probe: probe ?? (_) => api.instance(),
      lifecycle: lifecycle,
      poller: poller,
      deepLinks: deepLinks,
      localNetwork: localNetwork,
      pollInterval: pollInterval,
    );
    model._state = state;
    return model;
  }

  final TainaApi _api;
  final SessionStore _store;
  final HostStore _hostStore;
  final InstanceProbe _probe;
  final SessionLifecycle _lifecycle;
  final SessionPoller _poller;
  final DeepLinkSource? _deepLinks;
  final LocalNetworkGate _localNetwork;
  final ThumbnailStore _thumbnails;

  /// The scene-active refresh cadence. Injectable so tests never wait 30s.
  final Duration pollInterval;

  SessionState _state = const SessionChecking();
  InstanceAddress? _host;
  Instance? _instance;
  String? _notice;
  bool _polling = false;
  bool _disposed = false;

  SessionState get state => _state;

  InstanceAddress? get host => _host;

  Instance? get instance => _instance;

  /// A sentence for the screen a forced sign out lands on, shown by the login
  /// screen and cleared at the next connect or login.
  String? get notice => _notice;

  @override
  TainaApi get api => _api;

  @override
  ThumbnailStore get thumbnails => _thumbnails;

  @override
  Me? get identity => switch (_state) {
    SessionReady(:final me) => me,
    _ => null,
  };

  /// Restores the saved session, if any, and decides the first screen.
  ///
  /// A session that cannot be read counts as absent: the person signs in
  /// again. On a cold start the deep link can arrive while the restore is
  /// still reading storage, and the link wins: it already decided the screen,
  /// so the restore writes only while nothing else has.
  Future<void> restore() async {
    _lifecycle.attach(
      onActivated: _sceneActivated,
      onDeactivated: _sceneDeactivated,
    );
    _deepLinks?.attach((uri) => unawaited(handleDeepLink(uri)));

    final storedHost = await _hostStore.address();
    _host ??= storedHost;
    final restored = await _store.restore();
    if (_state is! SessionChecking) return;

    final session = restored.value;
    if (session != null) {
      // Keychain items can survive an uninstall while preferences do not.
      // A credential without its box cannot be used safely, so discard it and
      // let the person choose the community again.
      if (_host == null) {
        await _store.signOut();
        _setState(const SessionNeedsInstance());
        return;
      }
      _setState(SessionReady(session.identity));
    } else {
      _setState(
        _host == null
            ? const SessionNeedsInstance()
            : const SessionNeedsLogin(),
      );
    }
  }

  /// Validates what was typed, asks the box, and keeps the address when the
  /// community answers.
  ///
  /// A bare host tries https first and then http, because the pilot box
  /// answers plain http; an explicit scheme is tried as typed. A box that
  /// answers but has no community yet is its own outcome: the address is not
  /// saved, and Setup explains it.
  Future<TainaResult<Instance>> connect(String input) async {
    _clearNotice();
    _setInstance(null);

    final candidates = InstanceAddress.candidates(input);
    if (candidates is Err<AddressCandidates>) {
      return Err(candidates.error);
    }
    final ordered = (candidates as Ok<AddressCandidates>).value;

    if (!await _localNetwork.ensure()) {
      return const Err(NetworkError('local network permission denied'));
    }
    return _connect(ordered);
  }

  /// Tries the candidates in order and keeps the first address the box
  /// answers; when none does, the primary's failure is the answer the screen
  /// shows.
  Future<TainaResult<Instance>> _connect(AddressCandidates candidates) async {
    final first = await _probe(candidates.primary);
    final fallback = candidates.fallback;
    if (_unreachable(first) && fallback != null) {
      final second = await _probe(fallback);
      if (_unreachable(second)) return first;
      return _settleConnect(second, fallback);
    }
    return _settleConnect(first, candidates.primary);
  }

  /// Nothing answered: the transport never reached a box. The one failure
  /// where the person can act, so the screens say which three things to check
  /// instead of the generic sentence.
  static bool _unreachable(TainaResult<Instance> result) =>
      result.error is NetworkError;

  /// A box that answered earns the address: kept, saved, and the app moves on
  /// to the login.
  Future<TainaResult<Instance>> _settleConnect(
    TainaResult<Instance> result,
    InstanceAddress address,
  ) async {
    final found = result.value;
    if (found == null) return result;
    _setInstance(found);
    if (!found.bootstrapped) return result;

    _host = address;
    await _hostStore.save(address);
    _setState(const SessionNeedsLogin());
    return result;
  }

  /// Creates the session, keeps it, and confirms with the box before moving
  /// on. A failure of the confirmation stays on the login screen; the stored
  /// session is picked up at the next launch.
  Future<TainaResult<Me>> login({
    required String username,
    required String password,
    required String deviceName,
  }) async {
    _clearNotice();
    final created = await _api.createSession(
      username: username,
      password: password,
      deviceName: deviceName,
    );
    return _settle(created);
  }

  /// Accepts the invite with what the person typed. On success the session
  /// lands in the store exactly like a login, and the shell takes over.
  Future<TainaResult<Me>> acceptInvite({
    required String token,
    required String username,
    required String password,
    String? displayName,
    required String deviceName,
  }) async {
    final created = await _api.acceptInvite(
      token: token,
      username: username,
      password: password,
      displayName: displayName,
      deviceName: deviceName,
    );
    return _settle(created);
  }

  /// Defines the new password of the reset link and signs the person in, the
  /// same way a login lands.
  Future<TainaResult<Me>> resetPassword({
    required String token,
    required String password,
    required String deviceName,
  }) async {
    final created = await _api.resetPassword(
      token: token,
      password: password,
      deviceName: deviceName,
    );
    return _settle(created);
  }

  /// The self-service password change, while signed in: the box keeps this
  /// device's token and revokes the others.
  Future<TainaResult<void>> updatePassword({
    required String current,
    required String newPassword,
  }) {
    return _api.updatePassword(current: current, newPassword: newPassword);
  }

  /// The tail every sign in shares, whatever produced the session: store it,
  /// confirm with the box, and become ready.
  Future<TainaResult<Me>> _settle(TainaResult<Session> created) async {
    final session = created.value;
    if (session == null) {
      return Err(created.error ?? const InvalidResponseError('session'));
    }

    final saved = await _store.signIn(session);
    if (saved is Err<void>) return Err(saved.error);

    final confirmed = await _api.me();
    switch (confirmed) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        _setState(SessionReady(value));
        return Ok(value);
    }
  }

  /// The light read the deep-link screens open with: does the token still
  /// count? The real validation stays on the submit.
  Future<TainaResult<bool>> checkToken(PendingAuth pending) async {
    return switch (pending.kind) {
      PendingAuthKind.invite => (await _api.inviteStatus(
        token: pending.token,
      )).map((status) => status.valid),
      PendingAuthKind.reset => (await _api.resetStatus(
        token: pending.token,
      )).map((status) => status.valid),
    };
  }

  /// The box's deep link, opened natively: `taina://convite/<token>` or
  /// `taina://redefinir/<token>`, with the box address in the `host` query
  /// param. The link speaks for its own community, so its address replaces
  /// the saved one; without it, the saved box is the one. A malformed link
  /// changes nothing.
  Future<void> handleDeepLink(Uri url) async {
    await _open(DeepLink.parse(url));
  }

  /// The invite or reset link pasted as text, resolved through the same path
  /// a tapped link takes. Returns the sentence for what blocked it, or null
  /// when the deep-link screen took over.
  Future<String?> openPastedInvite(String text) async {
    final link = DeepLink.parsePasted(text);
    if (link == null) {
      return 'Este link não pôde ser lido. Confira se copiou o link inteiro, '
          'do começo ao fim.';
    }
    if (link.box == null && await _hostStore.address() == null) {
      return 'O link não diz qual é a comunidade e nenhuma foi conectada '
          'ainda. Peça o link completo a quem convidou você.';
    }
    await _open(link);
    return null;
  }

  /// The tail of every arrival, tapped or pasted.
  Future<void> _open(DeepLink? link) async {
    if (link == null) return;

    final InstanceAddress box;
    if (link.box != null) {
      final parsed = InstanceAddress.parse(link.box!);
      if (parsed is! Ok<InstanceAddress>) return;
      box = parsed.value;
    } else {
      final saved = await _hostStore.address();
      if (saved == null) return;
      box = saved;
    }

    final previousHost = _host ?? await _hostStore.address();
    if (previousHost != null && previousHost != box && _store.current != null) {
      // Device tokens are scoped to a community. Never carry the previous
      // box's bearer token into a host named by an external link.
      await _store.signOut();
      _thumbnails.clear();
    }

    _host = box;
    await _hostStore.save(box);
    _setInstance(null);
    final probed = await _api.instance();
    final found = probed.value;
    if (found != null && found.bootstrapped) {
      _setInstance(found);
    }
    _setState(
      SessionPendingAuth(
        PendingAuth(
          kind: link.kind == DeepLinkKind.invite
              ? PendingAuthKind.invite
              : PendingAuthKind.reset,
          token: link.token,
        ),
      ),
    );
  }

  /// Leaves the deep-link screen for the normal flow: a session the person
  /// already held is still theirs, so it is the way back; without one, the
  /// saved box leads to the login, and with no box, the setup.
  Future<void> leavePendingAuth() async {
    final current = _store.current;
    if (current != null) {
      _setState(SessionReady(current.identity));
      return;
    }
    _host = await _hostStore.address();
    _setState(
      _host == null ? const SessionNeedsInstance() : const SessionNeedsLogin(),
    );
  }

  /// Revokes on the box, then leaves locally whatever the answer: leaving is
  /// local, and a stored token the server has already forgotten is worse than
  /// either.
  Future<void> signOut() async {
    await _api.revokeSession();
    await _leaveLocally();
  }

  /// Screens any authenticated result: a 401 or a deactivated account signs
  /// the app out, leaving a sentence for the login screen.
  @override
  Future<TainaResult<T>> screen<T>(TainaResult<T> outcome) async {
    final failure = outcome.error;
    if (failure is! ApiError) return outcome;

    if (failure.isDeactivated) {
      _notice =
          'Esta conta foi desativada. Fale com o zelador ou a zeladora da '
          'comunidade.';
      await _leaveLocally();
    } else if (failure.isUnauthorized) {
      _notice = 'Sua entrada expirou. Entre de novo para continuar.';
      await _leaveLocally();
    }
    return outcome;
  }

  /// Asks the saved box which community it serves, changing nothing: the
  /// login and account screens show the name and the version.
  Future<void> probe() async {
    if (_host == null || _instance != null) return;
    final result = await _api.instance();
    final found = result.value;
    if (found != null && found.bootstrapped) {
      _setInstance(found);
    }
  }

  /// The scene is active again (or the poll ticked): the box may have moved
  /// on, and the token may have been revoked elsewhere.
  ///
  /// A fresh `me` keeps the identity and its quota honest and re-saves it; a
  /// revoked or deactivated session leaves through [screen], with its
  /// sentence on the login. A box away for a moment changes nothing, and the
  /// deep-link screens decide on their own.
  Future<void> refresh() async {
    switch (_state) {
      case SessionReady():
        final result = await screen(await _api.me());
        final me = result.value;
        if (me == null) return;
        _setState(SessionReady(me));
        await _store.refreshIdentity(me);
      case SessionNeedsLogin():
      case SessionNeedsInstance():
        await probe();
      case SessionChecking():
      case SessionPendingAuth():
        break;
    }
  }

  void _sceneActivated() {
    if (_polling) return;
    _polling = true;
    unawaited(refresh());
    _poller.start(pollInterval, () => unawaited(refresh()));
  }

  void _sceneDeactivated() {
    _polling = false;
    _poller.stop();
  }

  Future<void> _leaveLocally() async {
    await _store.signOut();
    _thumbnails.clear();
    _setInstance(null);
    _host ??= await _hostStore.address();
    _setState(
      _host == null ? const SessionNeedsInstance() : const SessionNeedsLogin(),
    );
  }

  void _setState(SessionState next) {
    _state = next;
    _notify();
  }

  void _setInstance(Instance? next) {
    if (_instance == next) return;
    _instance = next;
    _notify();
  }

  void _clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.stop();
    _lifecycle.detach();
    _deepLinks?.detach();
    super.dispose();
  }
}
