import 'dart:convert';

import 'CourseModel.dart';
import '../Resources/Constant.dart';
import '../Utils/ClassTimeUtil.dart';

/// A reviewed transcription, not an OCR service or a live school connection.
class ScreenshotSchedule {
  static const assetPath = 'res/schedules/zgysyjy_2026_fall.json';

  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> courses;
  final List<Map<String, dynamic>> periods;
  final DateTime firstMonday;

  ScreenshotSchedule._(this.data, this.courses, this.periods, this.firstMonday);

  factory ScreenshotSchedule.fromJson(Map<String, dynamic> data) {
    final courses = List<Map<String, dynamic>>.from(data['courses'] as List);
    final periods = List<Map<String, dynamic>>.from(data['periods'] as List);
    final monday = DateTime.parse(data['semester_start_monday'] as String);
    final result = ScreenshotSchedule._(data, courses, periods, monday);
    if (data['schema_version'] != 1 ||
        monday.weekday != DateTime.monday ||
        periods.isEmpty ||
        courses.isEmpty) {
      throw const FormatException('课表格式或学期起始周无效');
    }
    if (result.weekAt(DateTime.parse(data['reference_date'] as String)) !=
        data['reference_week']) {
      throw const FormatException('周次与校准日期不一致');
    }
    final codes = <String>{};
    final periodIds = periods.map((p) => p['id']).toSet();
    for (final course in courses) {
      if (!codes.add(course['code'] as String) ||
          (course['name'] as String).trim().isEmpty) {
        throw const FormatException('课程代码重复或课程名称为空');
      }
      for (final raw in course['meetings'] as List) {
        final meeting = Map<String, dynamic>.from(raw as Map);
        final weeks = List<int>.from(meeting['weeks'] as List);
        final day = meeting['weekday'] as int;
        if (weeks.isEmpty ||
            weeks.any((w) => w < 1 || w > 25) ||
            weeks.toSet().length != weeks.length ||
            day < 1 ||
            day > 7 ||
            !periodIds.contains(meeting['period'])) {
          throw const FormatException('课程周次、星期或时段无效');
        }
      }
    }
    return result;
  }

  String get id => data['id'] as String;
  int get revision => data['revision'] as int? ?? 1;
  String get name => data['name'] as String;
  String get startDate => data['semester_start_date'] as String;
  int get pendingCount =>
      courses.where((c) => (c['meetings'] as List).isEmpty).length;
  int get occurrenceCount => courses.fold(
    0,
    (total, c) =>
        total +
        (c['meetings'] as List).fold<int>(
          0,
          (count, m) => count + (m['weeks'] as List).length,
        ),
  );

  // Compare calendar dates; a time of day or DST must not shift the week.
  int weekAt(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final start = DateTime.utc(
      firstMonday.year,
      firstMonday.month,
      firstMonday.day,
    );
    return (day.difference(start).inDays / 7).floor() + 1;
  }

  DateTime dateFor(int week, int weekday) => DateTime.utc(
    firstMonday.year,
    firstMonday.month,
    firstMonday.day,
  ).add(Duration(days: (week - 1) * 7 + weekday - 1));

  String get tableData => jsonEncode({
    'source_id': id,
    'source_revision': revision,
    'source_kind': 'screenshot',
    'semester_start_date': startDate,
    'semester_start_monday': data['semester_start_monday'],
    'time_precision': ClassTimeUtil.hasClockTimes(periods)
        ? 'clock_range'
        : 'period',
    'class_time_list': periods
        .map((p) => {'label': p['label'], 'start': p['start'], 'end': p['end']})
        .toList(),
  });

  String periodLabel(String id) =>
      periods.firstWhere((p) => p['id'] == id)['label'] as String;

  String periodDescription(String id) {
    final index = periods.indexWhere((p) => p['id'] == id);
    final time = ClassTimeUtil.clockRange(periods, index + 1, 0);
    return '${periodLabel(id)}${time == null ? '' : ' $time'}';
  }

  String _courseInfo(Map<String, dynamic> course) =>
      '课程代码：${course['code']} · ${course['credits']} 学分\n'
              '来源：课表截图\n${course['note'] ?? ''}'
          .trim();

  /// Supplement the old screenshot's empty fields without replacing edits.
  /// A changed period layout cannot safely use the original slot indexes.
  Map<String, dynamic> supplementedTableData(Map<String, dynamic> existing) {
    final result = Map<String, dynamic>.from(existing);
    final rawPeriods = existing['class_time_list'];
    if (rawPeriods is! List || rawPeriods.length != periods.length) {
      return result;
    }
    for (var i = 0; i < periods.length; i++) {
      if (rawPeriods[i] is! Map ||
          rawPeriods[i]['label'] != periods[i]['label']) {
        return result;
      }
    }
    final merged = <Map<String, dynamic>>[];
    for (var i = 0; i < periods.length; i++) {
      final current = Map<String, dynamic>.from(rawPeriods[i]);
      // Fill a wholly unknown range, never combine a custom half-range
      // with a source time that could produce an invalid interval.
      if ((current['start'] ?? '') == '' && (current['end'] ?? '') == '') {
        current['start'] = periods[i]['start'];
        current['end'] = periods[i]['end'];
      }
      merged.add(current);
    }
    result['class_time_list'] = merged;
    result['time_precision'] = ClassTimeUtil.hasClockTimes(merged)
        ? 'clock_range'
        : 'period';
    return result;
  }

  Map<String, dynamic> supplementFor(Course existing) {
    if (existing.importType != Constant.ADD_BY_IMPORT) return {};
    final matches = courses.where((c) => c['code'] == existing.classNumber);
    if (matches.length != 1) return {};
    final source = matches.single;
    final patch = <String, dynamic>{};
    final teacher = (source['teacher'] as String? ?? '').trim();
    if ((existing.teacher ?? '').trim().isEmpty && teacher.isNotEmpty) {
      patch['teacher'] = teacher;
    }
    final slot = existing.startTime ?? 0;
    if (existing.weekTime != 0 && slot > 0 && slot <= periods.length) {
      final oldInfo =
          '${_courseInfo(source)}\n'
          '${periods[slot - 1]['label']}课；具体起止时间留空。';
      if (existing.info == oldInfo) patch['info'] = _courseInfo(source);
    }
    return patch;
  }

  static String formatWeeks(List<int> weeks) {
    if (weeks.isEmpty) return '周次待定';
    final sorted = weeks.toSet().toList()..sort();
    final ranges = <String>[];
    var start = sorted.first;
    var end = start;
    for (final week in sorted.skip(1)) {
      if (week == end + 1) {
        end = week;
      } else {
        ranges.add(start == end ? '$start' : '$start–$end');
        start = end = week;
      }
    }
    ranges.add(start == end ? '$start' : '$start–$end');
    return '第 ${ranges.join('、')} 周';
  }

  /// Merge only identical weekday/period/room entries of the same course.
  /// This preserves week gaps and room changes without duplicate cards.
  List<Course> toCourses({required int tableId, int firstCourseId = 0}) {
    final result = <Course>[];
    for (var index = 0; index < courses.length; index++) {
      final course = courses[index];
      final meetings = course['meetings'] as List;
      final info = _courseInfo(course);
      if (meetings.isEmpty) {
        result.add(
          Course(
            tableId,
            course['name'],
            '[]',
            0,
            0,
            0,
            Constant.ADD_BY_IMPORT,
            classNumber: course['code'],
            classroom: '',
            teacher: course['teacher'] as String?,
            info: info,
            courseId: firstCourseId + index,
          ),
        );
        continue;
      }
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final raw in meetings) {
        final m = Map<String, dynamic>.from(raw as Map);
        final key = jsonEncode([m['weekday'], m['period'], m['location']]);
        groups.putIfAbsent(key, () => []).add(m);
      }
      for (final group in groups.values) {
        final m = group.first;
        final weeks =
            group.expand((m) => List<int>.from(m['weeks'])).toSet().toList()
              ..sort();
        final slot = periods.indexWhere((p) => p['id'] == m['period']) + 1;
        result.add(
          Course(
            tableId,
            course['name'],
            jsonEncode(weeks),
            m['weekday'],
            slot,
            0,
            Constant.ADD_BY_IMPORT,
            classNumber: course['code'],
            classroom: m['location'],
            teacher: course['teacher'] as String?,
            courseId: firstCourseId + index,
            info: info,
          ),
        );
      }
    }
    return result;
  }
}
