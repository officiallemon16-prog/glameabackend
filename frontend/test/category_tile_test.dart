import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/features/discovery/widgets/category_tile.dart';
import 'package:glamea/models/category.dart';

Category _category(String name) => Category.fromJson({
      'id': 'cat-test',
      'slug': 'cat-test',
      'name': name,
    });

Future<void> _pumpTile(
  WidgetTester tester, {
  required double width,
  required double height,
  required String name,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: CategoryTile(category: _category(name)),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('CategoryTile layout', () {
    testWidgets('fits in the home category strip (96x104)', (tester) async {
      await _pumpTile(tester, width: 96, height: 104, name: 'Nail Art & Care');
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a short grid tile (90x100)', (tester) async {
      await _pumpTile(tester, width: 90, height: 100, name: 'Nail Art & Care');
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits the tightest tile (84x90)', (tester) async {
      await _pumpTile(tester, width: 84, height: 90, name: 'Nail Art & Care');
      expect(tester.takeException(), isNull);
    });

    testWidgets('long two-line names do not overflow', (tester) async {
      await _pumpTile(tester, width: 96, height: 104, name: 'Braids and Dreadlocks Styling');
      expect(tester.takeException(), isNull);
    });
  });
}
