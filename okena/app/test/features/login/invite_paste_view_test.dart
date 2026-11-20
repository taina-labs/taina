import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/login/invite_paste_view.dart';
import 'package:okena_app/src/features/login/invite_qr_scanner.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/support/session_support.dart';

Widget _app(Widget child) => MaterialApp(theme: TainaTheme.data, home: child);

const _destinationTekoa = Tekoa(
  publicId: 'tekother',
  name: 'Quilombo do Café',
  domain: 'other.local',
  storageQuotaBytes: 1000,
  storageUsedBytes: 100,
  createdAt: '2026-02-01T09:00:00Z',
);

final class _FakeInviteScanner implements InviteQrScanner {
  _FakeInviteScanner(this.value, {this.available = true});

  final String value;
  final bool available;

  @override
  bool get isSupported => true;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Widget build({required ValueChanged<String> onCapture}) {
    return Center(
      child: TextButton(
        onPressed: () => onCapture(value),
        child: const Text('Send fake scan'),
      ),
    );
  }
}

void main() {
  testWidgets('paste screen shows its QR action and address without a host', (
    tester,
  ) async {
    final composed = makeSession(state: const SessionNeedsInstance());

    await tester.pumpWidget(
      _app(
        InvitePasteView(
          session: composed.model,
          scanner: _FakeInviteScanner('abc123'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Colar um convite'), findsOneWidget);
    expect(find.text('Link ou código do convite'), findsOneWidget);
    expect(find.text('Ler QR code'), findsOneWidget);
    expect(find.text('Endereço da comunidade'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets('QR capture uses the same token parser and opens the invite', (
    tester,
  ) async {
    final composed = makeSession(state: const SessionNeedsInstance());

    await tester.pumpWidget(
      _app(
        InvitePasteView(
          session: composed.model,
          scanner: _FakeInviteScanner('abc123'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'box.local');
    await tester.tap(find.text('Ler QR code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send fake scan'));
    await tester.pumpAndSettle();

    expect(composed.model.state, isA<SessionPendingAuth>());
    expect(composed.model.host, testBox());
  });

  testWidgets('saved host hides the address field', (tester) async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
    );
    await composed.model.restore();

    await tester.pumpWidget(_app(InvitePasteView(session: composed.model)));
    await tester.pumpAndSettle();

    expect(find.text('Endereço da comunidade'), findsNothing);
  });

  testWidgets('host switch confirmation names the probed community', (
    tester,
  ) async {
    final composed = makeSession(
      host: testBox(),
      state: const SessionNeedsLogin(),
      probe: (_) async => const Ok(
        Instance(
          bootstrapped: true,
          tekoa: _destinationTekoa,
          version: '0.6.0',
        ),
      ),
    );
    await composed.model.restore();

    await tester.pumpWidget(
      _app(
        InvitePasteView(
          session: composed.model,
          scanner: _FakeInviteScanner('unused'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'https://other.local/convite/token',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Este convite é da comunidade Quilombo do Café (other.local). Quer '
        'trocar a comunidade conectada para continuar?',
      ),
      findsOneWidget,
    );
    expect(composed.model.host, testBox());
  });

  testWidgets('an unavailable scanner hides its action', (tester) async {
    final composed = makeSession(state: const SessionNeedsInstance());

    await tester.pumpWidget(
      _app(
        InvitePasteView(
          session: composed.model,
          scanner: _FakeInviteScanner('abc123', available: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ler QR code'), findsNothing);
  });
}
