import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Models/CourseModel.dart';
import 'package:wheretosleepinnju/Models/ScheduleModel.dart';
import 'package:wheretosleepinnju/Pages/AllCourse/Widgets/CourseCard.dart';
import 'package:wheretosleepinnju/Pages/CourseTable/Widgets/CourseDetailDialog.dart';
import 'package:wheretosleepinnju/Resources/Constant.dart';
import 'package:wheretosleepinnju/Utils/CourseWeeks.dart';
import 'package:wheretosleepinnju/generated/l10n.dart';

Widget host(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.delegate.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  test('weeks parser accepts only sorted unique in-range weeks', () {
    expect(CourseWeeks.parse(null), isEmpty);
    expect(CourseWeeks.parse(''), isEmpty);
    expect(CourseWeeks.parse('[]'), isEmpty);
    expect(CourseWeeks.parse('{'), isEmpty);
    expect(CourseWeeks.parse('null'), isEmpty);
    expect(CourseWeeks.parse('["a","b"]'), isEmpty);
    expect(CourseWeeks.parse('["1","2","2","0","26"]'), [1, 2]);
    expect(CourseWeeks.parse('[3, 3, 1, 99, -1, "4"]'), [1, 3, 4]);
    expect(CourseWeeks.firstAddable(null), isNull);
    expect(CourseWeeks.firstAddable('[2, 2, 1]'), 1);
  });

  test('schedule classification keeps pending courses without throwing', () {
    final model = ScheduleModel([
      Course(1, '待定', null, 1, 1, 1, 0),
      Course(1, '空白', '', 2, 1, 1, 0),
      Course(1, '空数组', '[]', 3, 1, 1, 0),
      Course(1, '坏数据', '{', 4, 1, 1, 0),
      Course(1, '字符串周次', '["5","5","30"]', 5, 1, 1, 0),
      Course(1, '正常', '[1,2,2]', 1, 1, 1, 0),
      Course(1, '过期讲座', '[1]', 1, 1, 1, Constant.ADD_BY_LECTURE),
      Course(1, '未排时间', '[]', 0, 0, 0, 0),
    ], 5);
    expect(() => model.init(), returnsNormally);
    expect(model.activeCourses.map((c) => c.name), ['字符串周次']);
    expect(model.freeCourses.map((c) => c.name), ['未排时间']);
    expect(
      model.hideCourses.map((c) => c.name),
      containsAll(['待定', '空白', '空数组', '坏数据', '正常']),
    );
    expect(model.hideCourses.map((c) => c.name), isNot(contains('过期讲座')));
  });

  testWidgets('course detail stays open for missing and invalid weeks', (
    tester,
  ) async {
    for (final raw in <String?>[null, '', '[]', '{', '["x"]']) {
      await tester.pumpWidget(
        host(
          CourseDetailDialog(
            Course(1, '导师课', raw, 1, 1, 1, 0, classroom: 'A', teacher: '张老师'),
            false,
            () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('周次待定'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('all-course cards render each course instead of the sample', (
    tester,
  ) async {
    final algebra = Course(
      0,
      '线性代数',
      '[1,2]',
      1,
      5,
      1,
      Constant.ADD_BY_LECTURE,
      classroom: '仙Ⅱ-201',
      teacher: '王老师',
      info: '线性代数详情',
    );
    final physics = Course(
      0,
      '大学物理',
      '[3,5,5]',
      3,
      3,
      1,
      Constant.ADD_BY_LECTURE,
      classroom: '仙Ⅱ-305',
      teacher: '赵老师',
    );
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            final labels = S.of(context);
            final cards = [algebra, physics].map((course) {
              final copy = CourseCardCopy.of(course, labels);
              return Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.name ?? ''),
                    Text(copy.time),
                    Text(copy.teacher),
                    Text(copy.detail),
                  ],
                ),
              );
            }).toList();
            return ListView(children: cards);
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('线性代数'), findsOneWidget);
    expect(find.textContaining('王老师'), findsOneWidget);
    expect(find.textContaining('仙Ⅱ-201'), findsOneWidget);
    expect(find.textContaining('第 1 周'), findsOneWidget);
    expect(find.textContaining('大学物理'), findsOneWidget);
    expect(find.textContaining('赵老师'), findsOneWidget);
    expect(find.textContaining('仙Ⅱ-305'), findsOneWidget);
    expect(find.textContaining('第 3 周'), findsOneWidget);
    expect(find.textContaining('第 5 周'), findsOneWidget);
    expect(find.text('线性代数详情'), findsOneWidget);
    expect(find.text('暂无备注'), findsOneWidget);
    expect(find.textContaining('李其芳'), findsNothing);
    expect(find.textContaining('仙Ⅰ-109'), findsNothing);
    expect(find.textContaining('形势与政策'), findsNothing);
    expect(algebra.info, '线性代数详情');
    expect(physics.info, isNull);
    expect(tester.takeException(), isNull);
  });
}
