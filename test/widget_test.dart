import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_camera_with_llm/app/app.dart';

void main() {
  testWidgets('switches between two Cupertino placeholder tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const SomeCameraWithLlmApp());
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.text('Camera placeholder'), findsOneWidget);
    expect(find.text('Assistant placeholder'), findsNothing);
    expect(
      tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
      0,
    );

    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();

    expect(find.text('Camera placeholder'), findsNothing);
    expect(find.text('Assistant placeholder'), findsOneWidget);
    expect(
      tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex,
      1,
    );
  });
}
