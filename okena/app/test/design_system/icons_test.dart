import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/design_system/components/icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every TainaIcon resolves to one template-friendly SVG asset', () async {
    expect(TainaIcon.values, hasLength(37));

    for (final TainaIcon icon in TainaIcon.values) {
      final String path = 'assets/icons/${icon.assetName}.svg';
      final String svg = await rootBundle.loadString(path);

      expect(svg, contains('<svg'));
      expect(svg, contains('currentColor'));
      expect(svg, isNot(contains(RegExp(r'#[0-9a-fA-F]{3,8}(?:\b|$)'))));
    }
  });
}
