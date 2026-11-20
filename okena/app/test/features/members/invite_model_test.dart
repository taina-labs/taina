import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/members/invite_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

void main() {
  test('selects the invite role and creates a real invite', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MembersInviteModel model = MembersInviteModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    expect(model.papel, Papel.morador);
    model.selectRole(Papel.zelador);
    final TainaResult<MemberInvite> result = await model.create();

    expect(result.isSuccess, isTrue);
    expect(model.invite!.ava.papel, Papel.zelador);
    expect(model.link, model.invite!.inviteUrl);
    expect(model.error, isNull);
    expect(model.working, isFalse);
  });

  test('prefers the web invite link and falls back to the app link', () {
    const MemberInvite invite = MemberInvite(
      ava: ana,
      token: 'token-123',
      inviteUrl: 'taina://convite/token-123',
      webUrl: 'https://taina.local/c/token-123',
    );
    const MemberInvite legacyInvite = MemberInvite(
      ava: ana,
      token: 'token-456',
      inviteUrl: 'taina://convite/token-456',
    );

    expect(
      MembersInviteModel.linkFor(invite),
      'https://taina.local/c/token-123',
    );
    expect(
      MembersInviteModel.linkFor(legacyInvite),
      'taina://convite/token-456',
    );
  });

  test('role descriptions follow the invite board', () {
    expect(
      MembersInviteModel.descriptionFor(Papel.morador),
      'Quem entrar vê a praça e ganha uma casa própria.',
    );
    expect(
      MembersInviteModel.descriptionFor(Papel.zelador),
      'Quem entrar cuida da máquina: disco, backups e convites. '
      'Para abrir uma casa, pede como todo mundo.',
    );
  });
}
