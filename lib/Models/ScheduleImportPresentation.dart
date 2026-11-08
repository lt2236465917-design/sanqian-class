import 'ScheduleImportDraft.dart';

/// Read-only presentation shared by review, comparison and editing surfaces.
/// Indices always refer to the original list; sorting never rewrites a draft.
class ScheduleImportPresentation {
  static List<int> meetingOrder(List<ScheduleImportMeetingDraft> meetings) {
    final order = List.generate(meetings.length, (i) => i);
    order.sort((a, b) {
      final left = meetings[a], right = meetings[b];
      var result = (left.weekday ?? 8).compareTo(right.weekday ?? 8);
      if (result != 0) return result;
      result = _timeKind(left).compareTo(_timeKind(right));
      if (result != 0) return result;
      result = _timeOrder(left).compareTo(_timeOrder(right));
      if (result != 0) return result;
      result = _firstWeek(left).compareTo(_firstWeek(right));
      if (result != 0) return result;
      result = (left.endMinute ?? left.periodCount ?? 0).compareTo(
        right.endMinute ?? right.periodCount ?? 0,
      );
      if (result != 0) return result;
      // Preserve input order for indistinguishable or unresolved arrangements.
      return a.compareTo(b);
    });
    return List.unmodifiable(order);
  }

  // Clocks and section numbers are different axes. Do not invent a mapping.
  static int _timeKind(ScheduleImportMeetingDraft m) => m.hasClock
      ? 0
      : m.periodIndex != null
      ? 1
      : (m.periodLabel ?? '').isNotEmpty
      ? 2
      : 3;

  static int _timeOrder(ScheduleImportMeetingDraft m) =>
      m.hasClock ? m.startMinute! : (m.periodIndex ?? 0);

  static int _firstWeek(ScheduleImportMeetingDraft m) =>
      (m.weeks ?? const <int>[]).fold(61, (a, b) => a < b ? a : b);

  static String courseSummary(Map<String, dynamic> course) {
    final identity = [
      for (final field in const [
        ['teacher', '教师'],
        ['section', '教学班'],
        ['courseCode', '课程编码'],
      ])
        if ('${course[field[0]] ?? ''}'.trim().isNotEmpty)
          '${field[1]}：${'${course[field[0]]}'.trim()}',
    ];
    final meetings = (course['meetings'] as List? ?? [])
        .whereType<Map>()
        .map(
          (m) =>
              ScheduleImportMeetingDraft.fromJson(Map<String, dynamic>.from(m)),
        )
        .toList();
    final schedule = meetings.isEmpty
        ? '${course['pendingReason'] ?? '安排待定'}'
        : meetingOrder(meetings)
              .map((i) {
                final meeting = meetings[i];
                return '${weekdayLabel(meeting.weekday)} · ${weekLabel(meeting.weeks)}\n'
                    '${meeting.timeDescription} · ${meeting.location ?? '地点待定'}';
              })
              .join('\n');
    return [...identity, schedule].join('\n');
  }

  static String weekdayLabel(int? day) => day != null && day >= 1 && day <= 7
      ? '星期${const ['一', '二', '三', '四', '五', '六', '日'][day - 1]}'
      : '星期待定';

  static String weekLabel(List<int>? value) {
    final weeks = (value ?? const <int>[]).toSet().toList()..sort();
    if (weeks.isEmpty) return '周次待定';
    final ranges = <String>[];
    var start = weeks.first, end = start;
    for (final week in weeks.skip(1)) {
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
}
