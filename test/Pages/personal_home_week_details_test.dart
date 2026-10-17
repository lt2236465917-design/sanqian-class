import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanqian_class/Models/CourseModel.dart';
import 'package:sanqian_class/Models/PersonalSchedule.dart';
import 'package:sanqian_class/Models/ScreenshotSchedule.dart';
import 'package:sanqian_class/Components/ScheduleDesign.dart';
import 'package:sanqian_class/Pages/Personal/PersonalHomeView.dart';
import 'package:sanqian_class/Resources/PersonalTheme.dart';
import 'package:sanqian_class/Utils/CourseWeeks.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('manual timetable clocks are not described as pending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final schedule = PersonalSchedule(
      tableId: 2,
      name: '手动课表',
      firstMonday: DateTime(2026, 10, 12),
      periods: [
        {'start': '08:00', 'end': '08:50'},
      ],
      courses: [Course(2, '手动课程', '[1]', 6, 1, 0, 0)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalHomeView(
          loader: () async => schedule,
          clock: () => DateTime(2026, 10, 17, 8, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('08:00–08:50'), findsWidgets);
    expect(find.textContaining('时间待定'), findsNothing);
    await tester.tap(find.text('手动课程').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('周六 · 08:00–08:50'), findsOneWidget);
    expect(find.textContaining('时段待定'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home details use the same week parser as the schedule', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cases = <(String, String?)>[
      ('字符串周次', '["1","2"]'),
      ('混合周次', '[1,99]'),
      ('越界周次', '[99]'),
      ('空值周次', null),
      ('空白周次', ''),
      ('坏数据周次', '{'),
    ];
    final courses = [
      for (final item in cases)
        Course(1, item.$1, item.$2, 1, 1, 1, 0, classroom: '6406'),
    ];
    final schedule = PersonalSchedule(
      tableId: 1,
      name: '周次详情',
      firstMonday: DateTime(2026, 9, 7),
      periods: [
        {'label': '上午', 'start': '09:00', 'end': '12:00'},
      ],
      courses: courses,
    );

    for (final course in courses) {
      expect(
        schedule.occurrences
            .where((item) => identical(item.course, course))
            .map((item) => item.week)
            .toList(),
        CourseWeeks.parse(course.weeks),
        reason: course.name,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: PersonalHomeView(
          loader: () async => schedule,
          clock: () => DateTime(2026, 9, 7, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openDetails(
      String name, {
      bool rejectOutOfRange = false,
    }) async {
      await tester.tap(find.text(name).hitTestable());
      await tester.pumpAndSettle();
      final course = courses.firstWhere((item) => item.name == name);
      expect(
        find.text(
          ScreenshotSchedule.formatWeeks(CourseWeeks.parse(course.weeks)),
        ),
        findsOneWidget,
      );
      if (rejectOutOfRange) {
        expect(find.textContaining('99'), findsNothing);
      }
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭详情'), findsNothing);
    }

    await openDetails('字符串周次');
    await openDetails('混合周次', rejectOutOfRange: true);

    await tester.tap(find.byKey(const ValueKey('tab-week')));
    await tester.pumpAndSettle();
    expect(find.text('4 门课程待安排'), findsOneWidget);
    await tester.tap(find.text('4 门课程待安排'));
    await tester.pumpAndSettle();
    await openDetails('越界周次');
    await openDetails('空值周次');
    await openDetails('空白周次');
    await openDetails('坏数据周次');
    expect(tester.takeException(), isNull);
  });

  testWidgets('day, week, and month headers keep the same height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final schedule = PersonalSchedule(
      tableId: 1,
      name: '秋季课表',
      firstMonday: DateTime(2026, 9, 7),
      periods: [
        {'label': '上午', 'start': '09:00', 'end': '12:00'},
      ],
      courses: [Course(1, '艺术史', '[1]', 1, 1, 0, 0, classroom: '6406')],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: personalTheme(Brightness.light),
        home: PersonalHomeView(
          loader: () async => schedule,
          clock: () => DateTime(2026, 9, 7, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double headerHeight() =>
        tester.getSize(find.byKey(const ValueKey('schedule-header'))).height;

    double gapUnderHeader(Finder content) {
      final header = tester.getRect(
        find.byKey(const ValueKey('schedule-header')),
      );
      return tester.getRect(content).top - header.bottom;
    }

    final dayHeight = headerHeight();
    expect(find.text('1 节课').hitTestable(), findsOneWidget);
    final dayGap = gapUnderHeader(
      find.ancestor(
        of: find.text('艺术史').hitTestable(),
        matching: find.byType(Card),
      ),
    );
    expect(dayGap, scheduleTitleContentGap);

    await tester.tap(find.byKey(const ValueKey('tab-week')));
    await tester.pumpAndSettle();
    expect(headerHeight(), dayHeight);
    expect(find.text('1 节课').hitTestable(), findsNothing);
    expect(
      gapUnderHeader(
        find.ancestor(of: find.text('第 1 周'), matching: find.byType(Row)).first,
      ),
      dayGap,
    );

    await tester.tap(find.byKey(const ValueKey('tab-month')));
    await tester.pumpAndSettle();
    expect(headerHeight(), dayHeight);
    expect(find.text('1 节课').hitTestable(), findsNothing);
    expect(
      gapUnderHeader(
        find
            .ancestor(of: find.text('2026年9月'), matching: find.byType(Row))
            .first,
      ),
      dayGap,
    );

    await tester.tap(find.byKey(const ValueKey('tab-today')));
    await tester.pumpAndSettle();
    expect(headerHeight(), dayHeight);
    expect(find.text('1 节课').hitTestable(), findsOneWidget);
  });
}
