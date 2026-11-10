import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/app.dart';
import 'package:okena_app/src/routing/app_router.dart';

void main() {
  testWidgets('app boots into the initial route', (tester) async {
    await tester.pumpWidget(OkenaApp(router: createAppRouter()));

    expect(find.text('Tainá'), findsOneWidget);
    expect(find.text('Preparando o app.'), findsOneWidget);
  });
}
