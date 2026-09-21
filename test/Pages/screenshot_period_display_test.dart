import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/generated/l10n.dart';
import 'package:wheretosleepinnju/Models/CourseModel.dart';
import 'package:wheretosleepinnju/Pages/CourseTable/Widgets/ClassTitle.dart';
import 'package:wheretosleepinnju/Pages/CourseTable/Widgets/CourseDetailDialog.dart';

const periods = <Map>[
  {'label': '上午', 'start': '', 'end': ''},
  {'label': '下午', 'start': '', 'end': ''},
  {'label': '晚上', 'start': '', 'end': ''},
];

const clockPeriods = <Map>[
  {'label': '上午', 'start': '09:00', 'end': '12:00'},
  {'label': '下午', 'start': '13:30', 'end': '16:30'},
  {'label': '晚上', 'start': '19:00', 'end': '21:30'},
];

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
  testWidgets('period rows have labels without invented clock times', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const ClassTitle(3, 160, 50, true, null, classTimeList: periods)),
    );
    await tester.pumpAndSettle();
    expect(find.text('上午'), findsOneWidget);
    expect(find.text('下午'), findsOneWidget);
    expect(find.text('晚上'), findsOneWidget);
    expect(find.textContaining('08:00'), findsNothing);
  });

  testWidgets('pending course opens without a fabricated week or range error', (
    tester,
  ) async {
    final course = Course(
      1,
      '导师课',
      '[]',
      0,
      0,
      0,
      1,
      classroom: '',
      info: '截图未提供上课安排。',
    );
    await tester.pumpWidget(
      host(
        CourseDetailDialog(course, false, () {}, classTimeList: clockPeriods),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('导师课'), findsOneWidget);
    expect(find.textContaining('时间待定'), findsOneWidget);
    expect(find.textContaining('周次待定'), findsOneWidget);
    expect(find.textContaining('09:00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid clock times appear alongside the three period labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ClassTitle(3, 160, 50, true, null, classTimeList: clockPeriods),
      ),
    );
    await tester.pumpAndSettle();
    for (final period in clockPeriods) {
      expect(find.text(period['label']), findsOneWidget);
      expect(find.text('${period['start']}\n${period['end']}'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('evening detail displays the teacher and full evening range', (
    tester,
  ) async {
    final course = Course(
      1,
      '曲艺学导论',
      '[4,6]',
      1,
      3,
      0,
      1,
      teacher: '吴文科',
      classroom: '6401教室（自排教室）',
    );
    await tester.pumpWidget(
      host(
        CourseDetailDialog(course, true, () {}, classTimeList: clockPeriods),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('吴文科'), findsOneWidget);
    expect(find.textContaining('周一 晚上\n19:00–21:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
