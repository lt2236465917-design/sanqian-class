import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Models/CourseModel.dart';
import 'package:wheretosleepinnju/Models/PersonalSchedule.dart';
import 'package:wheretosleepinnju/Models/ScreenshotSchedule.dart';
import 'package:wheretosleepinnju/Pages/Personal/Widgets/WeekScheduleDetailPage.dart';

PersonalSchedule reviewedSchedule() {
  final source = ScreenshotSchedule.fromJson(
    jsonDecode(File(ScreenshotSchedule.assetPath).readAsStringSync()),
  );
  return PersonalSchedule(
    tableId: 2,
    name: source.name,
    firstMonday: source.firstMonday,
    periods: source.periods,
    courses: source.toCourses(tableId: 2, firstCourseId: 100),
  );
}

void main() {
  testWidgets('week detail uses class periods and has no text list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final schedule = reviewedSchedule();
    final opened = <Course>[];
    await tester.pumpWidget(
      MaterialApp(
        home: WeekScheduleDetailPage(
          schedule: schedule,
          week: 3,
          now: DateTime(2026, 9, 22, 10),
          colorForCourse: (_) => const Color(0xFF6750A4),
          onCourseTap: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('上午'), findsNothing);
    expect(find.text('下午'), findsNothing);
    expect(find.text('晚上'), findsNothing);
    expect(find.text('时间待定'), findsNothing);
    expect(find.text('思政大讲堂：形势与政策'), findsNothing);
    expect(find.text('导师课'), findsNothing);
    expect(find.text('09:00\n12:00'), findsOneWidget);
    expect(find.text('09:00\n09:45'), findsNothing);
    expect(find.text('13:30\n16:30'), findsOneWidget);
    expect(find.text('19:00\n21:30'), findsOneWidget);
    expect(find.text('12:00\n13:30'), findsNothing);

    final history = schedule
        .inWeek(3)
        .where((item) => item.course.name == '中国艺术史')
        .length;
    expect(history, greaterThan(0));
    expect(find.text('中国艺术史'), findsNWidgets(history));

    await tester.tap(find.textContaining('中国艺术史').first);
    await tester.pumpAndSettle();
    if (find.text('这个时段有多门课程').evaluate().isNotEmpty) {
      await tester.tap(find.widgetWithText(ListTile, '中国艺术史'));
      await tester.pumpAndSettle();
    }
    expect(opened, isNotEmpty);
    expect(opened.first.name, '中国艺术史');
    expect(tester.takeException(), isNull);
  });

  testWidgets('one imported session spanning several periods is one cell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final periods = [
      {'label': '1', 'start': '09:00', 'end': '09:45'},
      {'label': '2', 'start': '09:45', 'end': '10:30'},
      {'label': '3', 'start': '10:30', 'end': '11:15'},
      {'label': '4', 'start': '11:15', 'end': '12:00'},
    ];
    final schedule = PersonalSchedule(
      tableId: 1,
      name: '账号导入',
      firstMonday: DateTime(2026, 9, 7),
      periods: periods,
      courses: [
        for (var slot = 1; slot <= 4; slot++)
          Course(1, '英语', '[3]', 1, slot, 0, 1, classroom: '6406', courseId: 7),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WeekScheduleDetailPage(
          schedule: schedule,
          week: 3,
          now: DateTime(2026, 9, 22, 10),
          colorForCourse: (_) => const Color(0xFF6750A4),
          onCourseTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('09:00\n09:45'), findsOneWidget);
    expect(find.text('11:15\n12:00'), findsOneWidget);
    expect(find.text('英语'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
