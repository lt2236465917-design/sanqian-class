import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Models/PersonalSchedule.dart';
import 'package:wheretosleepinnju/Models/ScreenshotSchedule.dart';

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
  test('Sunday in week two points to Monday afternoon in week three', () {
    final schedule = reviewedSchedule();
    final next = schedule.next(DateTime(2026, 9, 20, 23, 59))!;
    expect(schedule.weekAt(DateTime(2026, 9, 20, 23, 59)), 2);
    expect(schedule.weekAt(DateTime(2026, 9, 21)), 3);
    expect(next.course.name, '中国艺术史');
    expect(next.course.teacher, '杨明刚');
    expect(next.course.classroom, '6406（主校区）');
    expect(next.start, DateTime(2026, 9, 21, 13, 30));
    expect(next.end, DateTime(2026, 9, 21, 16, 30));
  });

  test('ongoing includes the start and excludes the exact end', () {
    final schedule = reviewedSchedule();
    final start = DateTime(2026, 9, 21, 13, 30);
    expect(schedule.next(start)!.isOngoing(start), isTrue);
    final beforeEnd = DateTime(2026, 9, 21, 16, 29, 59);
    expect(schedule.next(beforeEnd)!.course.name, '中国艺术史');
    expect(schedule.next(beforeEnd)!.isOngoing(beforeEnd), isTrue);
    final end = DateTime(2026, 9, 21, 16, 30);
    expect(schedule.next(end)!.course.name, '硕士英语(全日制学术型)');
    expect(schedule.next(end)!.isOngoing(end), isFalse);
  });

  test(
    'next skips weeks without the course and uses its current classroom',
    () {
      final all = reviewedSchedule();
      final english = PersonalSchedule(
        tableId: 2,
        name: all.name,
        firstMonday: all.firstMonday,
        periods: all.periods,
        courses: all.courses
            .where((c) => c.classNumber == 'S90001014')
            .toList(),
      );
      expect(
        english.next(DateTime(2026, 9, 29, 8))!.course.classroom,
        '第五会议室（主校区）',
      );
      final afterWeek4 = english.next(DateTime(2026, 9, 29, 12))!;
      expect(afterWeek4.week, 6);
      expect(afterWeek4.date, DateTime(2026, 10, 13));
      expect(afterWeek4.course.classroom, '6310（主校区）');
      expect(english.next(DateTime(2026, 11, 10, 12))!.week, 12);
    },
  );

  test(
    'pending courses have no invented occurrences and completed term has no next',
    () {
      final schedule = reviewedSchedule();
      expect(schedule.pending.map((c) => c.name), ['思政大讲堂：形势与政策', '导师课']);
      expect(schedule.occurrences, hasLength(73));
      expect(
        schedule.occurrences.any((c) => schedule.pending.contains(c.course)),
        isFalse,
      );
      expect(schedule.next(DateTime(2027, 3)), isNull);
    },
  );

  test('weekend photography retains four separate sessions', () {
    final schedule = reviewedSchedule();
    final saturday = schedule.onDay(DateTime(2026, 10, 10));
    final sunday = schedule.onDay(DateTime(2026, 10, 11));
    expect(saturday, hasLength(2));
    expect(sunday, hasLength(2));
    expect(saturday.map((c) => c.clockRange), ['09:00–12:00', '13:30–16:30']);
    expect(schedule.next(DateTime(2026, 10, 10, 12))!.period, '下午');
    expect(
      schedule.next(DateTime(2026, 10, 10, 16, 30))!.date,
      DateTime(2026, 10, 11),
    );
  });

  test('missing clocks remain unknown instead of being fabricated', () {
    final all = reviewedSchedule();
    final schedule = PersonalSchedule(
      tableId: 2,
      name: all.name,
      firstMonday: all.firstMonday,
      periods: [
        for (final period in all.periods)
          {'label': period['label'], 'start': '', 'end': ''},
      ],
      courses: all.courses,
    );
    final next = schedule.next(DateTime(2026, 9, 20))!;
    expect(next.period, '下午');
    expect(next.clockRange, isNull);
    expect(next.start, isNull);
    expect(next.end, isNull);
    expect(next.isOngoing(DateTime(2026, 9, 21, 14)), isFalse);
  });
}
