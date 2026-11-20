import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/login/invite_paste_view_model.dart';
import 'package:okena_app/src/session/deep_link.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/support/session_support.dart';

void main() {
  test('a bare token needs an address when no host is saved', () {
    expect(
      InvitePasteViewModel.prepare('abc_123', address: '', hasSavedHost: false),
      isNull,
    );
    expect(
      InvitePasteViewModel.problemFor(
        'abc_123',
        address: '',
        hasSavedHost: false,
      ),
      'O código sozinho não diz qual é a comunidade.',
    );
  });

  test('a bare token with an address becomes a session deep link', () {
    final request = InvitePasteViewModel.prepare(
      'abc_123',
      address: 'http://box.local',
      hasSavedHost: false,
    );

    expect(request?.kind, DeepLinkKind.invite);
    expect(request?.token, 'abc_123');
    expect(request?.address, testBox('http://box.local'));
    expect(
      request?.link,
      'taina://convite/abc_123?host=http%3A%2F%2Fbox.local',
    );
  });

  test('a full link keeps its parsed kind and address', () {
    final request = InvitePasteViewModel.prepare(
      'https://box.local/redefinir/token_1',
      address: '',
      hasSavedHost: false,
    );

    expect(request?.kind, DeepLinkKind.reset);
    expect(request?.token, 'token_1');
    expect(request?.address, testBox());
  });

  test('a saved host is enough for a bare invite token', () {
    final request = InvitePasteViewModel.prepare(
      'abc123',
      address: '',
      hasSavedHost: true,
    );

    expect(request?.kind, DeepLinkKind.invite);
    expect(request?.address, isNull);
    expect(request?.link, 'taina://convite/abc123');
  });

  test(
    'opening a bare token uses the same session deep-link boundary',
    () async {
      final composed = makeSession(state: const SessionNeedsInstance());
      final model = InvitePasteViewModel(session: composed.model);

      await model.open('abc123', address: 'box.local');

      expect(model.problem, isNull);
      expect(composed.model.state, isA<SessionPendingAuth>());
      expect(composed.model.host, testBox());
    },
  );

  test('a link for another host asks before switching', () async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
      probe: (_) async => const Ok(
        Instance(bootstrapped: true, tekoa: testTekoa, version: '0.6.0'),
      ),
    );
    await composed.model.restore();
    final model = InvitePasteViewModel(session: composed.model);
    InstanceAddress? confirmedAddress;
    String? confirmedName;

    await model.open(
      'https://other.local/convite/token',
      confirmCommunitySwitch: (address, communityName) async {
        confirmedAddress = address;
        confirmedName = communityName;
        return false;
      },
    );

    expect(confirmedAddress, testBox('https://other.local'));
    expect(confirmedName, 'Tekoa Sapukai');
    expect(composed.model.state, isA<SessionNeedsLogin>());
    expect(composed.model.host, testBox());

    await model.open(
      'https://other.local/convite/token',
      confirmCommunitySwitch: (_, communityName) async {
        expect(communityName, 'Tekoa Sapukai');
        return true;
      },
    );

    expect(composed.model.state, isA<SessionPendingAuth>());
    expect(composed.model.host, testBox('https://other.local'));
  });

  test(
    'failed destination probe falls back to the address in confirmation',
    () async {
      final composed = makeSession(
        host: testBox(),
        state: const SessionNeedsLogin(),
        probe: (_) async => const Err(NetworkError('unreachable')),
      );
      await composed.model.restore();
      final model = InvitePasteViewModel(session: composed.model);
      String? confirmedName;

      await model.open(
        'https://other.local/convite/token',
        confirmCommunitySwitch: (_, communityName) async {
          confirmedName = communityName;
          return false;
        },
      );

      expect(confirmedName, 'other.local');
      expect(composed.model.host, testBox());
      expect(composed.model.instance, isNull);
    },
  );

  test('malformed text returns the established parser message', () async {
    final composed = makeSession(state: const SessionNeedsInstance());
    final model = InvitePasteViewModel(session: composed.model);

    await model.open('not an invite');

    expect(
      model.problem,
      'Este link não pôde ser lido. Confira se copiou o link inteiro, '
      'do começo ao fim.',
    );
    expect(composed.model.state, isA<SessionNeedsInstance>());
  });
}
