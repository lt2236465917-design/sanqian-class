import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Models/CourseModel.dart';
import 'package:wheretosleepinnju/Models/ScheduleModel.dart';
import 'package:wheretosleepinnju/Models/ScreenshotSchedule.dart';
import 'package:wheretosleepinnju/Utils/ClassTimeUtil.dart';

void main() {
  late ScreenshotSchedule schedule;
  late List<Course> courses;

  setUp(() {
    schedule = ScreenshotSchedule.fromJson(
      jsonDecode(File(ScreenshotSchedule.assetPath).readAsStringSync()),
    );
    courses = schedule.toCourses(tableId: 42, firstCourseId: 100);
  });

  List<Course> atWeek(int week) => courses
      .where(
        (c) => c.weekTime != 0 && (jsonDecode(c.weeks!) as List).contains(week),
      )
      .toList();

  test(
    'the screenshot has 14 subjects, 2 pending and 73 dated occurrences',
    () {
      expect(schedule.courses, hasLength(14));
      expect(schedule.pendingCount, 2);
      expect(schedule.occurrenceCount, 73);
      expect(courses, hasLength(20));
      expect(courses.map((c) => c.classNumber).toSet(), hasLength(14));
      expect(courses.every((c) => c.tableId == 42), isTrue);
      expect(courses.map((c) => c.courseId).toSet(), hasLength(14));
    },
  );

  test('September 9 opening and second-week Sunday use September 7 Monday', () {
    expect(schedule.startDate, '2026-09-09');
    expect(schedule.weekAt(DateTime(2026, 9, 9)), 1);
    expect(schedule.weekAt(DateTime(2026, 9, 20, 23, 59)), 2);
    expect(schedule.weekAt(DateTime(2026, 9, 21)), 3);
    expect(schedule.weekAt(DateTime(2026, 9, 6)), 0);
    expect(schedule.dateFor(3, 1), DateTime.utc(2026, 9, 21));
  });

  test(
    'week three has the five visible weekday classes and no evening class',
    () {
      expect(atWeek(2), isEmpty);
      expect(
        atWeek(3).map((c) => '${c.weekTime}/${c.startTime}/${c.name}'),
        unorderedEquals([
          '1/2/中国艺术史',
          '2/1/硕士英语(全日制学术型)',
          '2/2/艺术美学',
          '3/2/艺术人类学理论与沿革专题研究',
          '4/1/中国特色社会主义理论与实践研究',
        ]),
      );
      final model = ScheduleModel(courses, 3)..init();
      final displayed = [
        ...model.activeCourses,
        ...model.multiCourses.map((group) => group.first),
      ].where((c) => (jsonDecode(c.weeks!) as List).contains(3));
      expect(displayed, hasLength(5));
      expect(model.freeCourses, hasLength(2));
    },
  );

  test(
    'gaps are preserved rather than turned into a continuous date range',
    () {
      final history = courses.singleWhere((c) => c.name == '中国艺术史');
      expect(jsonDecode(history.weeks!), [3, 4, 6, 7, 8, 9, 10, 11]);
      final english = courses.where((c) => c.classNumber == 'S90001014');
      final weeks =
          english.expand((c) => List<int>.from(jsonDecode(c.weeks!))).toList()
            ..sort();
      expect(weeks, [3, 4, 6, 7, 8, 9, 10, 12]);
      expect(atWeek(4), hasLength(8));
      expect(atWeek(6), hasLength(9));
    },
  );

  test('English room changes from meeting room five to room 6310', () {
    for (final week in [3, 4]) {
      expect(
        atWeek(week).singleWhere((c) => c.classNumber == 'S90001014').classroom,
        '第五会议室（主校区）',
      );
    }
    for (final week in [6, 10, 12]) {
      expect(
        atWeek(week).singleWhere((c) => c.classNumber == 'S90001014').classroom,
        '6310（主校区）',
      );
    }
  });

  test('photography occurs only on both periods of October 10 and 11', () {
    final photography = courses.where((c) => c.classNumber == '49106104');
    expect(photography, hasLength(4));
    expect(
      photography.map((c) => '${c.weekTime}/${c.startTime}'),
      unorderedEquals(['6/1', '6/2', '7/1', '7/2']),
    );
    expect(photography.every((c) => c.weeks == '[5]'), isTrue);
    expect(schedule.dateFor(5, 6), DateTime.utc(2026, 10, 10));
    expect(schedule.dateFor(5, 7), DateTime.utc(2026, 10, 11));
    // In addition to photography: Friday ideology and Thursday socialism.
    expect(atWeek(5), hasLength(6));
  });

  test(
    'grid times supplement the periods while unassigned courses stay unknown',
    () {
      final pending = courses.where((c) => c.weekTime == 0).toList();
      expect(
        pending.map((c) => c.name),
        unorderedEquals(['思政大讲堂：形势与政策', '导师课']),
      );
      expect(pending.every((c) => c.weeks == '[]' && c.startTime == 0), isTrue);
      final periods = List<Map>.from(
        jsonDecode(schedule.tableData)['class_time_list'],
      );
      expect(periods, [
        {'label': '上午', 'start': '09:00', 'end': '12:00'},
        {'label': '下午', 'start': '13:30', 'end': '16:30'},
        {'label': '晚上', 'start': '19:00', 'end': '21:30'},
      ]);
      expect(ClassTimeUtil.hasClockTimes(periods), isTrue);
      expect(ClassTimeUtil.clockRange(periods, 3, 0), '19:00–21:30');
      expect(ClassTimeUtil.clockRange(periods, 0, 0), isNull);
      expect(ClassTimeUtil.rangeLabel(periods, 2, 0), '下午');
      expect(
        ClassTimeUtil.hasClockTimes([
          {'start': '08:00', 'end': '09:30'},
        ]),
        isTrue,
      );
      expect(
        ClassTimeUtil.hasClockTimes([
          {'start': '25:00', 'end': '26:30'},
        ]),
        isFalse,
      );
      expect(
        ClassTimeUtil.hasClockTimes([
          {'start': '19:00', 'end': '18:00'},
        ]),
        isFalse,
      );
      expect(
        ClassTimeUtil.hasClockTimes([
          {'start': '', 'end': ''},
        ]),
        isFalse,
      );
    },
  );

  test(
    'teachers are transcribed without filling the three unknown subjects',
    () {
      final byCode = {for (final c in courses) c.classNumber: c.teacher};
      expect(byCode, {
        '49106104': '张涛',
        '90001003': '杨明刚',
        '90001005': '孙伟科',
        '90001020': '',
        '10121S102': '韩子勇',
        '10118B103': '方李莉',
        '10121S104': '葛玉清',
        '90001011': '',
        'S90001014': '林敬和、刘先福',
        '10118s300': '',
        '10118s105': '罗微',
        '10118s106': '郑长铃',
        '90001001': '申坤',
        '30101009': '吴文科',
      });
      final evening = courses.where((c) => c.startTime == 3).toList();
      expect(evening, hasLength(3));
      expect(
        evening.expand((c) => List<int>.from(jsonDecode(c.weeks!))),
        hasLength(4),
      );
      expect(courses.any((c) => (c.info ?? '').contains('起止时间留空')), isFalse);
    },
  );

  test(
    'supplement fills only unknown clock ranges and preserves local metadata',
    () {
      final existing = jsonDecode(schedule.tableData) as Map<String, dynamic>;
      existing['class_time_list'] = [
        {'label': '上午', 'start': '', 'end': '', 'custom': 'kept'},
        {'label': '下午', 'start': '14:00', 'end': '17:00'},
        {'label': '晚上', 'start': '', 'end': ''},
      ];
      existing['local_note'] = '保留';
      final merged = schedule.supplementedTableData(existing);
      expect(merged['class_time_list'], [
        {'label': '上午', 'start': '09:00', 'end': '12:00', 'custom': 'kept'},
        {'label': '下午', 'start': '14:00', 'end': '17:00'},
        {'label': '晚上', 'start': '19:00', 'end': '21:30'},
      ]);
      expect(merged['local_note'], '保留');
      expect(merged['time_precision'], 'clock_range');
      expect(schedule.supplementedTableData(merged), merged);
      expect(existing['class_time_list'][0]['start'], '');
      existing['class_time_list'][0]['start'] = '13:00';
      expect(
        schedule.supplementedTableData(existing)['class_time_list'][0]['end'],
        '',
      );
      existing['class_time_list'].removeLast();
      expect(schedule.supplementedTableData(existing), existing);
    },
  );

  test(
    'supplement keeps edits and updates only the original empty teacher and note',
    () {
      final old = courses.firstWhere((c) => c.classNumber == 'S90001014');
      old.teacher = null;
      old.info = '${old.info}\n上午课；具体起止时间留空。';
      final before = old.toMap();
      final patch = schedule.supplementFor(old);
      expect(patch, {
        'teacher': '林敬和、刘先福',
        'info': '课程代码：S90001014 · 2.0 学分\n来源：课表截图',
      });
      expect(old.toMap(), before);
      old.teacher = '自定义教师';
      old.info = '我的笔记';
      old.name = '自定义课程名';
      old.classroom = '自定义教室';
      expect(schedule.supplementFor(old), isEmpty);
      old.teacher = null;
      old.importType = 0;
      expect(schedule.supplementFor(old), isEmpty);
    },
  );
}
