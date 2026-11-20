import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/account/devices_screen.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';

import '../support/fake_session.dart';

final class _FailingDevicesApi implements TainaApi {
  @override
  Future<TainaResult<Me>> me() async => Ok(identity(ana));

  @override
  Future<TainaResult<List<DeviceToken>>> devices() async => const Err(offline);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LoadingDevicesApi implements TainaApi {
  final Completer<TainaResult<List<DeviceToken>>> devicesResult =
      Completer<TainaResult<List<DeviceToken>>>();

  @override
  Future<TainaResult<Me>> me() async => Ok(identity(ana));

  @override
  Future<TainaResult<List<DeviceToken>>> devices() => devicesResult.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(SessionGateway session) {
  return MaterialApp(
    theme: TainaTheme.data,
    home: DevicesScreen(
      session: session,
      key: ValueKey<SessionGateway>(session),
    ),
  );
}

void _large(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('shows current and other devices with the current id', (
    tester,
  ) async {
    _large(tester);
    final DevicesApi api = DevicesApi(
      FakeTainaApi(delay: Duration.zero),
      const [currentDevice, otherDevice],
    );
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('iPhone da Ana'), findsOneWidget);
    expect(find.text('Tablet da Ana'), findsOneWidget);
    expect(find.text('Este aparelho'), findsOneWidget);
    expect(find.text('Identificação deste aparelho'), findsOneWidget);
    expect(find.text(currentDevice.publicId), findsOneWidget);
    expect(find.text('Revogar'), findsOneWidget);
  });

  testWidgets('revokes a different device after confirmation', (tester) async {
    _large(tester);
    final DevicesApi api = DevicesApi(
      FakeTainaApi(delay: Duration.zero),
      const [currentDevice, otherDevice],
    );
    await tester.pumpWidget(_app(FakeSession(api, me: identity(ana))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revogar'));
    await tester.pumpAndSettle();
    expect(find.text('Revogar o acesso deste aparelho?'), findsOneWidget);

    await tester.tap(find.text('Revogar').last);
    await tester.pumpAndSettle();

    expect(api.revoked, [otherDevice.publicId]);
    expect(find.textContaining('Revogado em'), findsOneWidget);
  });

  testWidgets('renders loading, empty and error states', (tester) async {
    _large(tester);
    final _LoadingDevicesApi loadingApi = _LoadingDevicesApi();
    await tester.pumpWidget(_app(FakeSession(loadingApi, me: identity(ana))));
    await tester.pump();
    expect(find.byType(SkeletonView), findsOneWidget);

    loadingApi.devicesResult.complete(const Ok(<DeviceToken>[]));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum aparelho'), findsOneWidget);

    await tester.pumpWidget(_app(FakeSession(_FailingDevicesApi())));
    await tester.pumpAndSettle();
    expect(find.text('Não conseguimos carregar os aparelhos.'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
