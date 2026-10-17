import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanqian_class/Models/CourseModel.dart';
import 'package:sanqian_class/Models/PersonalSchedule.dart';
import 'package:sanqian_class/Models/WidgetLaunchTarget.dart';
import 'package:sanqian_class/Pages/Personal/PersonalHomeView.dart';
import 'package:sanqian_class/Resources/PersonalTheme.dart';

void main() {
  final start = DateTime.utc(2026, 10, 17).millisecondsSinceEpoch;
  WidgetLaunchTarget target([String occurrence = '2.7.1']) =>
      WidgetLaunchTarget.parse(
        'ncs://schedule?date=$start&occurrence=$occurrence',
      )!;
  final schedule = PersonalSchedule(
    tableId: 2,
    name: '课表',
    firstMonday: DateTime(2026, 10, 12),
    periods: [
      {'start': '08:00', 'end': '08:50'},
    ],
    courses: [Course(2, '艺术史', '[1]', 6, 1, 0, 0, id: 7, classroom: '6406')],
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('widget links preserve Shanghai dates and reject foreign routes', () {
    final midnight = DateTime.utc(2026, 10, 16, 16).millisecondsSinceEpoch;
    final parsed = WidgetLaunchTarget.parse(
      'ncs://schedule?date=$midnight&occurrence=2.7.1',
    )!;
    expect(parsed.date, DateTime(2026, 10, 17));
    expect(parsed.tableId, 2);
    expect(parsed.courseId, 7);
    expect(
      WidgetLaunchTarget.parse('https://schedule?occurrence=2.7.1'),
      isNull,
    );
    expect(WidgetLaunchTarget.parse('ncs://course'), isNull);
    expect(
      WidgetLaunchTarget.parse('ncs://schedule?date=999999999999999999')!.date,
      isNull,
    );
    expect(target('2.7.-1').occurrence, isNull);
  });

  Future<void> mount(
    WidgetTester tester,
    ValueNotifier<WidgetLaunchTarget?> notifier, {
    Future<PersonalSchedule> Function()? loader,
    DateTime? now,
  }) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: personalTheme(Brightness.light),
        home: PersonalHomeView(
          widgetTarget: notifier,
          loader: loader ?? () async => schedule,
          clock: () => now ?? DateTime(2026, 10, 17, 8, 10),
        ),
      ),
    );
  }

  testWidgets(
    'cold target waits for schedule and opens the matching course once',
    (tester) async {
      final loaded = Completer<PersonalSchedule>();
      final notifier = ValueNotifier<WidgetLaunchTarget?>(target());
      await mount(tester, notifier, loader: () => loaded.future);
      await tester.pump();
      expect(find.text('课程详情'), findsNothing);
      loaded.complete(schedule);
      await tester.pumpAndSettle();
      expect(find.text('课程详情'), findsOneWidget);
      expect(find.text('周六 · 08:00–08:50'), findsOneWidget);
      expect(notifier.value, isNull);
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pumpAndSettle();
      expect(find.text('课程详情'), findsNothing);
    },
  );

  testWidgets('warm target opens course details', (tester) async {
    final notifier = ValueNotifier<WidgetLaunchTarget?>(null);
    await mount(tester, notifier);
    await tester.pumpAndSettle();
    notifier.value = target();
    await tester.pumpAndSettle();
    expect(find.text('课程详情'), findsOneWidget);
    expect(find.text('6406').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stale course or another timetable never opens an unrelated course',
    (tester) async {
      final notifier = ValueNotifier<WidgetLaunchTarget?>(target('2.999.1'));
      await mount(tester, notifier);
      await tester.pumpAndSettle();
      expect(find.text('课程详情'), findsNothing);
      expect(find.text('这条课程安排已变化，请查看当前课表。'), findsOneWidget);
      notifier.value = target('3.7.1');
      await tester.pumpAndSettle();
      expect(find.text('课程详情'), findsNothing);
      expect(notifier.value, isNull);
    },
  );

  testWidgets('future date opens its month schedule without a detail sheet', (
    tester,
  ) async {
    final notifier = ValueNotifier<WidgetLaunchTarget?>(
      WidgetLaunchTarget.parse('ncs://schedule?date=$start'),
    );
    await mount(tester, notifier, now: DateTime(2026, 10, 16));
    await tester.pumpAndSettle();
    expect(find.text('课程详情'), findsNothing);
    expect(find.text('艺术史').hitTestable(), findsWidgets);
    expect(find.textContaining('10月17日').hitTestable(), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
