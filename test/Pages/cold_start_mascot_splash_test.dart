import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Pages/Personal/Widgets/ColdStartMascotSplash.dart';

void main() {
  testWidgets('cold start shows the poster for half a second before video', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ColdStartMascotSplash(child: Text('home'))),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('cold-start-mascot-splash')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cold-start-mascot-poster')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cold-start-mascot-video')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('skip-cold-start-splash')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('cold-start-mascot-splash')),
      findsNothing,
    );
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system reduce-motion setting skips the animation', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      const MaterialApp(home: ColdStartMascotSplash(child: Text('home'))),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('cold-start-mascot-splash')),
      findsNothing,
    );
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
