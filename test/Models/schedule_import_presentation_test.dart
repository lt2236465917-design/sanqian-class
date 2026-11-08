import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanqian_class/Models/ScheduleImportDraft.dart';
import 'package:sanqian_class/Models/ScheduleImportPresentation.dart';

void main() {
  test(
    'review order preserves the source list, classrooms and evening gap',
    () {
      final meetings = [
        {
          'weekday': 2,
          'weeks': [12],
          'startMinute': 540,
          'endMinute': 720,
          'location': '6310',
        },
        {
          'weekday': 2,
          'weeks': [6, 7, 8, 9, 10],
          'startMinute': 540,
          'endMinute': 720,
          'location': '6310',
        },
        {
          'weekday': 2,
          'weeks': [3, 4],
          'startMinute': 540,
          'endMinute': 720,
          'location': '第五会议室',
        },
        {
          'weekday': 7,
          'weeks': [5],
          'startMinute': 810,
          'endMinute': 990,
        },
        {
          'weekday': 6,
          'weeks': [5],
          'startMinute': 810,
          'endMinute': 990,
        },
        {
          'weekday': 7,
          'weeks': [5],
          'startMinute': 540,
          'endMinute': 720,
        },
        {
          'weekday': 6,
          'weeks': [5],
          'startMinute': 540,
          'endMinute': 720,
        },
        {
          'weekday': 1,
          'weeks': [4],
          'startMinute': 1230,
          'endMinute': 1290,
        },
        {
          'weekday': 1,
          'weeks': [4],
          'startMinute': 1140,
          'endMinute': 1180,
        },
      ];
      final draft = {'name': '多安排课程', 'meetings': meetings};
      final original = jsonEncode(draft);
      final parsed = meetings.map(ScheduleImportMeetingDraft.fromJson).toList();
      final order = ScheduleImportPresentation.meetingOrder(parsed);
      expect(order, [8, 7, 2, 1, 0, 6, 4, 5, 3]);
      final summary = ScheduleImportPresentation.courseSummary(draft);
      expect(summary.indexOf('第 3–4 周'), lessThan(summary.indexOf('第 6–10 周')));
      expect(summary.indexOf('第 6–10 周'), lessThan(summary.indexOf('第 12 周')));
      expect(summary, contains('09:00–12:00 · 第五会议室'));
      expect(summary, contains('19:00–19:40'));
      expect(summary, contains('20:30–21:30'));
      expect(summary, isNot(contains('19:00–21:30')));
      expect(jsonEncode(draft), original);
    },
  );

  test(
    'unknown fields remain pending and equal arrangements keep their order',
    () {
      final input = [
        ScheduleImportMeetingDraft(sourceReference: '未知甲'),
        ScheduleImportMeetingDraft(weekday: 1, periodLabel: '晚上'),
        ScheduleImportMeetingDraft(weekday: 1, periodIndex: 2),
        ScheduleImportMeetingDraft(
          weekday: 1,
          startMinute: 540,
          endMinute: 600,
        ),
        ScheduleImportMeetingDraft(
          weekday: 1,
          weeks: [2],
          startMinute: 540,
          endMinute: 600,
          location: 'B',
        ),
        ScheduleImportMeetingDraft(
          weekday: 1,
          weeks: [2],
          startMinute: 540,
          endMinute: 600,
          location: 'A',
        ),
        ScheduleImportMeetingDraft(sourceReference: '未知乙'),
      ];
      expect(ScheduleImportPresentation.meetingOrder(input), [
        4,
        5,
        3,
        2,
        1,
        0,
        6,
      ]);
      final summary = ScheduleImportPresentation.courseSummary({
        'name': '待确认课程',
        'meetings': input.map((m) => m.toJson()).toList(),
      });
      expect(summary, contains('星期待定 · 周次待定'));
      expect(summary, contains('第 2 节（具体时间待确认）'));
      expect(summary, contains('晚上（具体时间待确认）'));
      expect(input[3].weeks, isNull);
    },
  );
}
