import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Models/CourseModel.dart';
import 'package:wheretosleepinnju/Models/PersonalSchedule.dart';
import 'package:wheretosleepinnju/Utils/ScheduleDerivedDataService.dart';

void main() {
  test(
    'snapshot preserves gap weeks and uses Shanghai instants without credentials',
    () {
      final course = Course(
        9,
        '英语',
        '[4,6,10,12]',
        1,
        1,
        0,
        1,
        id: 23,
        classroom: 'A',
      );
      final pending = Course(9, '导师', '[]', 0, 0, 0, 1, id: 24);
      final schedule = PersonalSchedule(
        tableId: 9,
        name: '秋季',
        firstMonday: DateTime(2026, 9, 7),
        periods: [
          {'start': '09:00', 'end': '10:00'},
        ],
        courses: [course, pending],
      );
      final snapshot = ScheduleDerivedDataService.snapshot(schedule);
      final events = snapshot['occurrences'] as List;
      expect(events.length, 4);
      expect(
        events.first['startMs'],
        DateTime.utc(2026, 9, 28, 1).millisecondsSinceEpoch,
      );
      expect(events.map((e) => e['id']), [
        '9.23.4',
        '9.23.6',
        '9.23.10',
        '9.23.12',
      ]);
      expect(jsonEncode(snapshot), isNot(contains('account')));
      expect(
        ScheduleDerivedDataService.snapshot(schedule)['revision'],
        snapshot['revision'],
      );
    },
  );
  test('unknown clock never generates notification/widget occurrence', () {
    final schedule = PersonalSchedule(
      tableId: 1,
      name: 't',
      firstMonday: DateTime(2026, 9, 7),
      periods: [],
      courses: [Course(1, '未知时间', '[1]', 1, 1, 0, 1, id: 1)],
    );
    expect(
      ScheduleDerivedDataService.snapshot(schedule)['occurrences'],
      isEmpty,
    );
  });
  test('Course data round trip preserves provenance and unrelated keys', () {
    final value = Course(
      1,
      't',
      '[]',
      0,
      0,
      0,
      1,
      data: '{"schedule_import_row":{"identity":"code:1"},"local":true}',
    );
    expect(Course.fromMap(value.toMap()).data, value.data);
    expect(
      Course(1, 'edit', '[]', 0, 0, 0, 1).toMap().containsKey('data'),
      false,
    );
  });
}
