import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'CourseModel.dart';
import 'CourseTableModel.dart';
import '../Utils/ClassTimeUtil.dart';

class CourseOccurrence {
  final Course course;
  final DateTime date;
  final int week;
  final String period;
  final String? clockRange;
  final DateTime? start;
  final DateTime? end;

  CourseOccurrence(
    this.course,
    this.date,
    this.week,
    this.period,
    this.clockRange,
    this.start,
    this.end,
  );

  bool isOngoing(DateTime now) =>
      start != null &&
      end != null &&
      !now.isBefore(start!) &&
      now.isBefore(end!);
}

class PersonalSchedule {
  final int tableId;
  final String name;
  final DateTime firstMonday;
  final List<Map> periods;
  final List<Course> courses;

  PersonalSchedule({
    required this.tableId,
    required this.name,
    required this.firstMonday,
    required this.periods,
    required this.courses,
  });

  String exportTableData(String? existing) {
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(existing ?? '{}'));
    } catch (_) {
      data = {};
    }
    data['semester_start_monday'] = firstMonday
        .toIso8601String()
        .split('T')
        .first;
    data['class_time_list'] = periods;
    return jsonEncode(data);
  }

  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static bool sameDay(DateTime a, DateTime b) => day(a) == day(b);

  int weekAt(DateTime value) {
    final date = DateTime.utc(value.year, value.month, value.day);
    final first = DateTime.utc(
      firstMonday.year,
      firstMonday.month,
      firstMonday.day,
    );
    return (date.difference(first).inDays / 7).floor() + 1;
  }

  DateTime dateFor(int week, int weekday) => DateTime(
    firstMonday.year,
    firstMonday.month,
    firstMonday.day + (week - 1) * 7 + weekday - 1,
  );

  List<Course> get pending => courses
      .where(
        (c) =>
            c.weekTime == null ||
            c.weekTime! < 1 ||
            c.weekTime! > 7 ||
            _weeks(c).isEmpty,
      )
      .toList();

  static List<int> _weeks(Course course) {
    try {
      return List<int>.from(
        jsonDecode(course.weeks ?? '[]'),
      ).where((week) => week > 0).toSet().toList()..sort();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  List<CourseOccurrence> get occurrences {
    final result = <CourseOccurrence>[];
    for (final course in courses) {
      final weekday = course.weekTime ?? 0;
      if (weekday < 1 || weekday > 7) continue;
      final slot = course.startTime ?? 0;
      final count = course.timeCount ?? 0;
      final range = ClassTimeUtil.clockRange(periods, slot, count);
      final label = ClassTimeUtil.rangeLabel(periods, slot, count) ?? '时间待定';
      for (final week in _weeks(course)) {
        final date = dateFor(week, weekday);
        DateTime? start;
        DateTime? end;
        if (range != null) {
          DateTime clock(String value) {
            final parts = value.split(':').map(int.parse).toList();
            return DateTime(
              date.year,
              date.month,
              date.day,
              parts[0],
              parts[1],
            );
          }

          start = clock(periods[slot - 1]['start']);
          end = clock(periods[slot + count - 1]['end']);
        }
        result.add(
          CourseOccurrence(course, date, week, label, range, start, end),
        );
      }
    }
    result.sort((a, b) {
      final dateOrder = a.date.compareTo(b.date);
      if (dateOrder != 0) return dateOrder;
      final slotOrder = (a.course.startTime ?? 0).compareTo(
        b.course.startTime ?? 0,
      );
      if (slotOrder != 0) return slotOrder;
      return (a.course.name ?? '').compareTo(b.course.name ?? '');
    });
    return result;
  }

  List<CourseOccurrence> onDay(DateTime date) =>
      occurrences.where((c) => sameDay(c.date, date)).toList();

  List<CourseOccurrence> inWeek(int week) =>
      occurrences.where((c) => c.week == week).toList();

  CourseOccurrence? next(DateTime now) {
    for (final course in occurrences) {
      if (course.end != null
          ? course.end!.isAfter(now)
          : !course.date.isBefore(day(now))) {
        return course;
      }
    }
    return null;
  }
}

Future<PersonalSchedule> loadPersonalSchedule() async {
  final preferences = await SharedPreferences.getInstance();
  final provider = CourseTableProvider();
  final tables = await provider.getAllCourseTable();
  var id = preferences.getInt('tableId') ?? 0;
  if (!tables.any((table) => table['id'] == id) && tables.isNotEmpty) {
    id = tables.first['id'] as int;
    await preferences.setInt('tableId', id);
  }
  final table = await provider.getCourseTable(id);
  final monday = await provider.getSemesterStartMonday(id);
  final reference =
      DateTime.tryParse(preferences.getString('lastWeekMonday') ?? '') ??
      PersonalSchedule.day(
        DateTime.now(),
      ).subtract(Duration(days: DateTime.now().weekday - 1));
  final first =
      DateTime.tryParse(monday) ??
      DateTime(
        reference.year,
        reference.month,
        reference.day - ((preferences.getInt('weekIndex') ?? 1) - 1) * 7,
      );
  return PersonalSchedule(
    tableId: id,
    name: table?.name ?? '我的课表',
    firstMonday: first,
    periods: await provider.getClassTimeList(id),
    courses: (await CourseProvider().getAllCourses(
      id,
    )).map((row) => Course.fromMap(row)).toList(),
  );
}
