import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/home/home.dart';
import 'package:okena_core/okena_core.dart';

import 'support/fake_gateway.dart';

Widget _app(Widget child) => MaterialApp(theme: TainaTheme.data, home: child);

Future<void> _pumpHome(
  WidgetTester tester, {
  required HomeTestGateway gateway,
  DateTime Function()? clock,
  HomeOpenFile? onOpenFile,
  HomeOpenDestination? onOpenAccount,
  HomeOpenDestination? onOpenDocuments,
  HomeOpenDestination? onOpenGallery,
  HomeOpenDestination? onOpenMural,
  HomeOpenDestination? onOpenHealth,
  HomeOpenDestination? onOpenMembers,
  HomeOpenDestination? onOpenStorage,
  HomeOpenDestination? onOpenRequests,
}) async {
  await tester.pumpWidget(
    _app(
      HomeScreen(
        gateway: gateway,
        clock: clock ?? () => DateTime(2026, 11, 9, 10),
        onOpenFile: onOpenFile,
        onOpenAccount: onOpenAccount,
        onOpenDocuments: onOpenDocuments,
        onOpenGallery: onOpenGallery,
        onOpenMural: onOpenMural,
        onOpenHealth: onOpenHealth,
        onOpenMembers: onOpenMembers,
        onOpenStorage: onOpenStorage,
        onOpenRequests: onOpenRequests,
      ),
    ),
  );
}

void main() {
  testWidgets('the default board renders live Hub sections in order', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway();
    await _pumpHome(tester, gateway: gateway);
    await tester.pumpAndSettle();

    expect(find.text('Bom dia, Ana'), findsOneWidget);
    expect(find.text('Quilombo do Café'), findsOneWidget);
    expect(find.byType(HubHeader), findsOneWidget);
    expect(find.byType(ServiceCard), findsNWidgets(2));
    expect(find.text('Documentos'), findsOneWidget);
    expect(find.text('Galeria'), findsOneWidget);
    expect(find.text('Arquivos da casa e da praça'), findsOneWidget);
    expect(find.text('Fotos da casa e da praça'), findsOneWidget);
    expect(find.byType(ServiceSquare), findsNWidgets(5));
    expect(find.text('DA COMUNIDADE'), findsOneWidget);
    expect(find.text('Saúde da comunidade'), findsOneWidget);
    expect(find.text('Moradores'), findsOneWidget);
    expect(find.text('Espaço da comunidade'), findsOneWidget);
    expect(find.text('RECENTES'), findsOneWidget);
    expect(find.text('Apresentacao na escola.mp4'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    final Iterable<TainaListRow> civicRows = tester
        .widgetList<TainaListRow>(find.byType(TainaListRow))
        .where((row) => row.kind == TainaListRowKind.civic);
    expect(civicRows, hasLength(3));
    final List<TainaServiceMark> marks = tester
        .widgetList<ServiceSquare>(find.byType(ServiceSquare))
        .map((square) => square.mark)
        .toList();
    expect(
      marks,
      containsAll([
        TainaServiceMark.mural,
        TainaServiceMark.saude,
        TainaServiceMark.moradores,
      ]),
    );

    await tester.scrollUntilVisible(
      find.textContaining('pessoas na comunidade'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('na comunidade'), findsWidgets);
  });

  testWidgets('the pending-request board adds a CareLine to Pedidos', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway();
    var requests = 0;
    await _pumpHome(tester, gateway: gateway, onOpenRequests: () => requests++);
    await tester.pumpAndSettle();

    expect(find.byType(CareLine), findsOneWidget);
    expect(
      find.text('Joana pediu para abrir um arquivo da sua casa'),
      findsOneWidget,
    );
    await tester.tap(find.text('Responder'));
    expect(requests, 1);
  });

  testWidgets('the recent-empty board keeps the live Hub and empty copy', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway()..emptyRecent = true;
    var documents = 0;
    await _pumpHome(
      tester,
      gateway: gateway,
      onOpenDocuments: () => documents++,
    );
    await tester.pumpAndSettle();

    expect(find.text('Nada recente'), findsOneWidget);
    expect(find.text('O que chegar de novo aparece aqui.'), findsOneWidget);
    expect(find.text('Enviar arquivos'), findsOneWidget);
    expect(find.text('Espaço da comunidade'), findsOneWidget);
    await tester.ensureVisible(find.text('Enviar arquivos'));
    await tester.tap(find.text('Enviar arquivos'));
    expect(documents, 1);
  });

  testWidgets('the degraded board preserves each failed section and retry', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway()
      ..failStats = true
      ..failRecent = true
      ..failMural = true
      ..failRequests = true
      ..failMembers = true
      ..failHealth = true;
    await _pumpHome(tester, gateway: gateway, onOpenMembers: () {});
    await tester.pumpAndSettle();

    expect(find.byType(ErrorCard), findsNWidgets(6));
    expect(
      find.text('Não conseguimos falar com a nuvem agora.'),
      findsNWidgets(6),
    );
    expect(find.text('Tentar de novo'), findsNWidgets(6));
    expect(find.text('Falar com quem cuida'), findsNWidgets(6));

    gateway
      ..failStats = false
      ..failRecent = false
      ..failMural = false
      ..failRequests = false
      ..failMembers = false
      ..failHealth = false;
    await tester.ensureVisible(find.text('Tentar de novo').first);
    await tester.tap(find.text('Tentar de novo').first);
    await tester.pumpAndSettle();
    expect(find.byType(ErrorCard), findsNothing);
    expect(find.byType(ServiceCard), findsNWidgets(2));
  });

  testWidgets('the greeting follows the injected clock', (tester) async {
    final HomeTestGateway gateway = HomeTestGateway();
    await _pumpHome(
      tester,
      gateway: gateway,
      clock: () => DateTime(2026, 11, 9, 15),
    );
    await tester.pumpAndSettle();
    expect(find.text('Boa tarde, Ana'), findsOneWidget);
  });

  testWidgets('service, civic, account and file rows delegate navigation', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway();
    FileRecord? opened;
    final List<String> destinations = [];
    await _pumpHome(
      tester,
      gateway: gateway,
      onOpenFile: (file) => opened = file,
      onOpenAccount: () => destinations.add('conta'),
      onOpenDocuments: () => destinations.add('documentos'),
      onOpenGallery: () => destinations.add('galeria'),
      onOpenMural: () => destinations.add('mural'),
      onOpenHealth: () => destinations.add('saude'),
      onOpenMembers: () => destinations.add('moradores'),
      onOpenStorage: () => destinations.add('armazenamento'),
      onOpenRequests: () => destinations.add('pedidos'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conta'));
    await tester.tap(find.text('Documentos'));
    await tester.tap(find.text('Galeria'));
    await tester.ensureVisible(find.text('Apresentacao na escola.mp4'));
    await tester.tap(find.text('Apresentacao na escola.mp4'));
    expect(opened?.name, 'Apresentacao na escola.mp4');
    expect(destinations, ['conta', 'documentos', 'galeria']);

    await tester.scrollUntilVisible(
      find.text('Saúde da comunidade'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Mural'));
    await tester.tap(find.text('Mural'));
    await tester.ensureVisible(find.text('Saúde da comunidade'));
    await tester.tap(find.text('Saúde da comunidade'));
    await tester.ensureVisible(find.text('Moradores'));
    await tester.tap(find.text('Moradores'));
    await tester.scrollUntilVisible(
      find.text('Ver detalhes'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Ver detalhes'));
    expect(destinations, [
      'conta',
      'documentos',
      'galeria',
      'mural',
      'saude',
      'moradores',
      'armazenamento',
    ]);
  });

  testWidgets('the Hub header remains visible while sections load', (
    tester,
  ) async {
    final HomeTestGateway gateway = HomeTestGateway(
      delay: const Duration(milliseconds: 120),
    );
    await _pumpHome(tester, gateway: gateway);
    await tester.pump();

    expect(find.byType(HubHeader), findsOneWidget);
    expect(find.text('Quilombo do Café'), findsOneWidget);
    expect(find.byType(TainaLoadingList), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(TainaLoadingList), findsNothing);
    expect(find.text('RECENTES'), findsOneWidget);
  });
}
