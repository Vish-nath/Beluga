import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beluga_health/main.dart';

void main() {
  testWidgets('Beluga Health app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BelugaApp());

    // Verify that app builds successfully.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
