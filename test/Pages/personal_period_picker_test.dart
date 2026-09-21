import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Pages/AddCourse/Widgets/WeekTimeNodeDialog.dart';
import 'package:wheretosleepinnju/Pages/AddCourse/Widgets/WeekNodeDialog.dart';
import 'package:wheretosleepinnju/Utils/CourseWeekSelection.dart';
import 'package:wheretosleepinnju/Utils/ClassTimeUtil.dart';

void main() {
  const periods = [
    {'label': '09:00–12:00', 'start': '09:00', 'end': '12:00'},
    {'label': '13:30–16:30', 'start': '13:30', 'end': '16:30'},
    {'label': '19:00–21:30', 'start': '19:00', 'end': '21:30'},
  ];
  Future<void> show(
    WidgetTester tester,
    Widget dialog,
    void Function(Map?) result,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await showDialog<Map>(context: context, builder: (_) => dialog),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is DropdownButtonFormField<int> && w.decoration.labelText == label,
  );
  Future<void> choose(WidgetTester tester, String label, String option) async {
    await tester.ensureVisible(field(label));
    await tester.tap(field(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'actual clock endpoints stay ordered and match the saved course range',
    (tester) async {
      final original = {'weekTime': 0, 'startTime': 0, 'endTime': 0};
      Map? result;
      await show(
        tester,
        WeekTimeNodeDialog(node: original, periods: periods),
        (v) => result = v,
      );
      expect(find.text('周一 09:00–12:00'), findsOneWidget);
      await choose(tester, '星期', '周日');
      await choose(tester, '开始时间', '19:00');
      expect(find.text('周日 19:00–21:30'), findsOneWidget);
      await tester.tap(field('结束时间'));
      await tester.pumpAndSettle();
      expect(find.text('12:00'), findsNothing);
      await tester.tap(find.text('21:30').last);
      await tester.pumpAndSettle();
      expect(original['startTime'], 0);
      await tester.ensureVisible(find.text('确认'));
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(result, {'weekTime': 6, 'startTime': 2, 'endTime': 2});
      expect(
        ClassTimeUtil.clockRange(
          periods,
          result!['startTime'] + 1,
          result!['endTime'] - result!['startTime'],
        ),
        '19:00–21:30',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'week 20 with odd weeks cannot confirm an empty course; cancel keeps original',
    (tester) async {
      final original = {'startWeek': 19, 'endWeek': 19, 'weekType': 0};
      Map? result;
      await show(tester, WeekNodeDialog(node: original), (v) => result = v);
      expect(find.text('选择上课周'), findsOneWidget);
      await tester.tap(find.text('单周'));
      await tester.pumpAndSettle();
      expect(find.text('所选范围没有单周，请调整周次。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认'))
            .onPressed,
        isNull,
      );
      expect(original['weekType'], 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(original, {'startWeek': 19, 'endWeek': 19, 'weekType': 0});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'odd weeks use actual semester parity and preview agrees with saved weeks',
    (tester) async {
      final node = {'startWeek': 1, 'endWeek': 5, 'weekType': 0};
      Map? result;
      await show(tester, WeekNodeDialog(node: node), (v) => result = v);
      await tester.tap(find.text('单周'));
      await tester.pumpAndSettle();
      expect(find.text('第 3、5 周 · 共 2 周'), findsOneWidget);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(CourseWeekSelection.weeks(result!), [3, 5]);
      expect(CourseWeekSelection.weeks({...result!, 'weekType': 2}), [2, 4, 6]);
    },
  );
}
