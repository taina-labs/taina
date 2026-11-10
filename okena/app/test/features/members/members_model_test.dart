import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/members/members_model.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

const Ava pendingInvite = Ava(
  publicId: 'avapending',
  username: null,
  displayName: null,
  papel: Papel.morador,
  activatedAt: null,
  deactivatedAt: null,
  createdAt: '2026-10-14T10:00:00Z',
);

void main() {
  test(
    'load lists the roster zeladoras first and reads the identity',
    () async {
      final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
      final MembersModel model = MembersModel(
        gateway: FakeSession(api, me: identity(ana)),
      );

      await model.load();

      expect(model.loading, isFalse);
      expect(model.members, hasLength(3));
      expect(model.members.first.papel, Papel.zelador);
      expect(model.isZelador, isTrue);
      expect(model.mePublicId, ana.publicId);
      expect(model.error, isNull);
    },
  );

  test('a morador never gets the zeladora acts', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MembersModel model = MembersModel(
      gateway: FakeSession(api, me: identity(joana)),
    );

    await model.load();

    expect(model.isZelador, isFalse);
    expect(model.mePublicId, joana.publicId);
  });

  test('invite adds the pending person to the roster', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MembersModel model = MembersModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();

    final result = await model.invite(Papel.morador);

    expect(result.isSuccess, isTrue);
    expect(model.members, hasLength(4));
    expect(
      model.members.any((Ava member) => MembersModel.isPendingInvite(member)),
      isTrue,
    );
  });

  test('changeRole swaps the row for the answer', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MembersModel model = MembersModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();

    final result = await model.changeRole(joana.publicId, Papel.zelador);

    expect(result.isSuccess, isTrue);
    expect(
      model.members
          .firstWhere((Ava member) => member.publicId == joana.publicId)
          .papel,
      Papel.zelador,
    );
  });

  test('the last zeladora cannot step down, and the code survives', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MembersModel model = MembersModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();

    final result = await model.changeRole(ana.publicId, Papel.morador);

    expect(result.isFailure, isTrue);
    expect(result.error, isA<ApiError>());
    expect((result.error! as ApiError).code, 'last_zelador');
  });

  test('deactivate reads the list again and keeps the fact', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MembersModel model = MembersModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();

    final result = await model.deactivate('avam4t8y2w6q0s3');

    expect(result.isSuccess, isTrue);
    expect(
      model.members
          .firstWhere((Ava member) => member.publicId == 'avam4t8y2w6q0s3')
          .deactivatedAt,
      isNotNull,
    );
  });

  test('reactivate brings the account back', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MembersModel model = MembersModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();
    await model.deactivate('avam4t8y2w6q0s3');

    final result = await model.reactivate('avam4t8y2w6q0s3');

    expect(result.isSuccess, isTrue);
    expect(
      model.members
          .firstWhere((Ava member) => member.publicId == 'avam4t8y2w6q0s3')
          .deactivatedAt,
      isNull,
    );
  });

  test('revokeInvite removes the pending person', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MembersModel model = MembersModel(
      gateway: FakeSession(api, me: identity(ana)),
    );
    await model.load();
    final invited = (await model.invite(Papel.morador)).value!;

    final result = await model.revokeInvite(invited.ava.publicId);

    expect(result.isSuccess, isTrue);
    expect(
      model.members.any(
        (Ava member) => member.publicId == invited.ava.publicId,
      ),
      isFalse,
    );
  });

  test('resetLink answers a one-time password link', () async {
    final FakeTainaApi api = FakeTainaApi(delay: Duration.zero);
    final MembersModel model = MembersModel(
      gateway: FakeSession(api, me: identity(ana)),
    );

    final result = await model.resetLink(joana.publicId);

    expect(result.isSuccess, isTrue);
    expect(result.value!.resetUrl, contains('taina://redefinir/'));
    expect(result.value!.ava.label, 'Joana Reis');
  });

  group('pure transitions', () {
    test('countLine says pessoa and pessoas', () {
      expect(MembersModel.countLine(1), '1 pessoa');
      expect(MembersModel.countLine(3), '3 pessoas');
    });

    test('metaFor prioritizes deactivated over the person acting', () {
      final Ava off = Ava(
        publicId: ana.publicId,
        username: ana.username,
        displayName: ana.displayName,
        papel: Papel.zelador,
        activatedAt: ana.activatedAt,
        deactivatedAt: '2026-10-14T10:00:00Z',
        createdAt: ana.createdAt,
      );
      expect(MembersModel.metaFor(off, ana.publicId), 'Conta desativada');
      expect(MembersModel.metaFor(ana, ana.publicId), 'Você');
      expect(MembersModel.metaFor(joana, ana.publicId), isNull);
    });

    test('isPendingInvite means no username and no activation', () {
      expect(MembersModel.isPendingInvite(pendingInvite), isTrue);
      expect(MembersModel.isPendingInvite(joana), isFalse);
    });

    test('tintIndex is stable and within the four palette slots', () {
      expect(MembersModel.tintIndex('Ana Souza'), inInclusiveRange(0, 3));
      expect(
        MembersModel.tintIndex('Ana Souza'),
        MembersModel.tintIndex('Ana Souza'),
      );
    });

    test('inserting keeps zeladoras first, then the label', () {
      final List<Ava> next = MembersModel.inserting(pendingInvite, const [
        joana,
        ana,
      ]);
      expect(next.first.papel, Papel.zelador);
      expect(next.map((Ava member) => member.publicId), [
        ana.publicId,
        pendingInvite.publicId,
        joana.publicId,
      ]);
    });

    test('replacing and removing work by public_id', () {
      final Ava promoted = Ava(
        publicId: joana.publicId,
        username: joana.username,
        displayName: joana.displayName,
        papel: Papel.zelador,
        activatedAt: joana.activatedAt,
        deactivatedAt: null,
        createdAt: joana.createdAt,
      );
      final List<Ava> replaced = MembersModel.replacing(
        joana.publicId,
        promoted,
        const [ana, joana],
      );
      expect(replaced.last.papel, Papel.zelador);
      expect(MembersModel.removing(joana.publicId, const [ana, joana]), [ana]);
    });
  });
}
