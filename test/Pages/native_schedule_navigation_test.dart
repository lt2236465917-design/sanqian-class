import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Pages/Personal/Widgets/FloatingScheduleNavigation.dart';

void main() {
  const capability = MethodChannel('chaoxi/schedule_navigation');
  const codec = StandardMethodCodec();
  final nativeUpdates = <Map<dynamic, dynamic>>[];
  final nativeChannels = <MethodChannel>[];
  final disposedViews = <int>[];
  final acceptedGestures = <int>[];
  int? viewId;

  setUp(() {
    nativeUpdates.clear();
    nativeChannels.clear();
    disposedViews.clear();
    acceptedGestures.clear();
    viewId = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(capability, (_) async => true);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<dynamic, dynamic>;
        expect(args['viewType'], 'chaoxi/schedule_tab_bar');
        viewId = args['id'] as int;
        final channel = MethodChannel('chaoxi/schedule_navigation/$viewId');
        nativeChannels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'update') {
            nativeUpdates.add(call.arguments as Map<dynamic, dynamic>);
          }
          return null;
        });
      } else if (call.method == 'dispose') {
        disposedViews.add(call.arguments as int);
      } else if (call.method == 'acceptGesture') {
        acceptedGestures.add((call.arguments as Map)['id'] as int);
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(capability, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in nativeChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> selectFromNative(WidgetTester tester, Object value) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'chaoxi/schedule_navigation/$viewId',
      codec.encodeMethodCall(MethodCall('select', value)),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets(
    'native selections stay in sync through rapid changes and theme',
    (tester) async {
      var selected = 0;
      var dark = false;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              home: Scaffold(
                body: Text('Page $selected'),
                bottomNavigationBar: FloatingScheduleNavigation(
                  selectedIndex: selected,
                  onSelected: (value) => setState(() => selected = value),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('floating-tab-indicator')),
        findsNothing,
      );
      expect(nativeUpdates.last['selectedIndex'], 0);
      final initialId = viewId;
      await tester.tapAt(tester.getCenter(find.byType(UiKitView)));
      await tester.pump();
      expect(acceptedGestures, contains(initialId));
      expect(selected, 0); // Only UIKit's selection callback commits the tap.

      for (final index in [2, 1, 2, 0, 1]) {
        await selectFromNative(tester, index);
        expect(find.text('Page $index'), findsOneWidget);
        expect(nativeUpdates.last['selectedIndex'], index);
      }
      for (final invalid in [-1, 3, 'month']) {
        await selectFromNative(tester, invalid);
        expect(find.text('Page 1'), findsOneWidget);
      }
      update(() {
        dark = true;
        selected = 2;
      });
      await tester.pumpAndSettle();
      expect(nativeUpdates.last['selectedIndex'], 2);
      expect(nativeUpdates.last['dark'], true);
      expect(viewId, initialId); // Theme/selection must not recreate the lens.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(disposedViews, contains(initialId));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'older iOS keeps a working Flutter navigation bar',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        capability,
        (_) async => false,
      );
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: FloatingScheduleNavigation(
              selectedIndex: 0,
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tab-month')));
      expect(selected, 2);
      final button = tester.widget<TextButton>(
        find.descendant(
          of: find.byKey(const ValueKey('tab-month')),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.style?.splashFactory, InkSparkle.splashFactory);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'older iOS slides the frosted indicator continuously',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        capability,
        (_) async => false,
      );
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: FloatingScheduleNavigation(
                selectedIndex: selected,
                onSelected: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final indicator = find.byKey(const ValueKey('floating-tab-indicator'));
      final start = tester.getCenter(indicator).dx;
      await tester.tap(find.byKey(const ValueKey('tab-month')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final during = tester.getCenter(indicator).dx;
      await tester.pumpAndSettle();
      final end = tester.getCenter(indicator).dx;
      expect(during, greaterThan(start));
      expect(during, lessThan(end));
      expect(
        end,
        closeTo(
          tester.getCenter(find.byKey(const ValueKey('tab-month'))).dx,
          1,
        ),
      );
      expect(selected, 2);
      expect(find.byType(UiKitView), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'late capability reply after leaving the page is ignored',
    (tester) async {
      final reply = Completer<bool>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        capability,
        (_) => reply.future,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: FloatingScheduleNavigation(
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      reply.complete(true);
      await tester.pumpAndSettle();
      expect(viewId, isNull);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
