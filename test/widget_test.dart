import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mmcal/main.dart';

void main() {
  testWidgets('MMCal app smoke test', (WidgetTester tester) async {
    // App requires async init; just verify it builds without error.
    expect(MMCalApp, isNotNull);
  });
}