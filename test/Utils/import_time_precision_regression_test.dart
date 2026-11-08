import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sanqian_class/Models/CourseModel.dart';
import 'package:sanqian_class/Models/Db/DbHelper.dart';
import 'package:sanqian_class/Models/PersonalSchedule.dart';
import 'package:sanqian_class/Models/ScheduleImportDraft.dart';
import 'package:sanqian_class/Utils/SavedCourseFacts.dart';
import 'package:sanqian_class/Utils/ScheduleCalendarExporter.dart';
import 'package:sanqian_class/Utils/ScheduleDerivedDataService.dart';
import 'package:sanqian_class/Utils/ScheduleImportService.dart';

// The real fixture is the first simulator run's reviewed AI output, not the
// bundled sample timetable (which includes separately supplied clock times).
List<ScheduleImportCourseDraft> realCourses() {
  final json =
      jsonDecode(
            File('test/fixtures/ai_import_real_list.json').readAsStringSync(),
          )
          as Map;
  return (json['courses'] as List)
      .map(
        (c) => ScheduleImportCourseDraft.fromJson(
          Map<String, dynamic>.from(c as Map),
        ),
      )
      .toList();
}

ScheduleImportMeetingDraft meeting({
  int? day = 1,
  List<int>? weeks = const [1, 3],
  String? label,
  int? period,
  int? count,
  int? start,
  int? end,
  String? reference,
  String? room = 'A101',
}) => ScheduleImportMeetingDraft.fromJson({
  'weekday': day,
  'weeks': weeks,
  if (label != null) 'periodLabel': label,
  'periodIndex': period,
  'periodCount': count,
  'startMinute': start,
  'endMinute': end,
  'location': room,
  'sourceReference': reference,
});

ScheduleImportCourseDraft course(
  String code,
  List<ScheduleImportMeetingDraft> meetings, {
  String? teacher,
}) => ScheduleImportCourseDraft(
  courseCode: code,
  section: 'A',
  name: '课程 $code',
  teacher: teacher,
  meetings: meetings,
  pendingReason: meetings.isEmpty ? '来源没有排课信息' : null,
);

ScheduleImportDraft draft(List<ScheduleImportCourseDraft> courses) =>
    ScheduleImportDraft(
      source: 'photos',
      sourceId: 'generic-time-precision',
      school: '任意学校',
      term: 'regression',
      firstWeekMonday: DateTime(2026, 9, 7),
      courses: courses,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(DbHelper.SQL_CREATE_COURSETABLE);
    await db.execute(DbHelper.SQL_CREATE_COURSES);
  });
  tearDown(() async => db.close());

  Future<List<Map<String, dynamic>>> rows() =>
      db.query('Course', orderBy: 'id');
  Future<PersonalSchedule> savedSchedule(int id) async {
    final table = (await db.query(
      'CourseTable',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    final data = jsonDecode(table['data'] as String) as Map;
    final saved = await db.query(
      'Course',
      where: 'tableid = ?',
      whereArgs: [id],
      orderBy: 'id',
    );
    return PersonalSchedule(
      tableId: id,
      name: table['name'] as String,
      firstMonday: DateTime.parse(data['semester_start_monday'] as String),
      periods: (data['class_time_list'] as List? ?? [])
          .map((p) => Map.from(p as Map))
          .toList(),
      courses: saved.map(Course.fromMap).toList(),
    );
  }

  test(
    'real reviewed image survives SQLite as 14 identities, 23 meetings, 73 dated sessions and 2 undated courses',
    () async {
      final input = realCourses();
      expect(input, hasLength(14));
      expect(input.expand((c) => c.meetings), hasLength(23));
      expect(input.every((c) => c.teacher == null), isTrue);
      final result = await ScheduleImportService.commit(
        draft(input),
        database: db,
      );
      final saved = await rows();
      expect(saved, hasLength(25));
      final identities = saved
          .map(
            (r) =>
                (jsonDecode(r['data'] as String)
                    as Map)['schedule_import_row']['identity'],
          )
          .toSet();
      expect(identities, hasLength(14));
      final schedule = await savedSchedule(result.tableId);
      expect(schedule.occurrences, hasLength(73));
      expect(schedule.pending, hasLength(2));
      expect(schedule.pending.map((c) => c.classNumber).toSet(), {
        '90001011',
        '90001020',
      });
      expect(
        schedule.occurrences.every(
          (e) => e.start == null && e.end == null && e.clockRange == null,
        ),
        isTrue,
      );
      expect(ScheduleCalendarExporter.exportable(schedule), isEmpty);
      expect(
        ScheduleDerivedDataService.snapshot(schedule)['occurrences'],
        isEmpty,
      );
    },
  );

  test(
    'four weekend sessions of one course remain distinct and repeated import is idempotent',
    () async {
      final input = draft(realCourses());
      final first = await ScheduleImportService.commit(input, database: db);
      final before = await rows();
      final photography = before
          .where((r) => r['class_number'] == '49106104')
          .toList();
      expect(photography, hasLength(4));
      final schedule = await savedSchedule(first.tableId);
      final saturday = schedule.onDay(DateTime(2026, 10, 10));
      final sunday = schedule.onDay(DateTime(2026, 10, 11));
      expect(saturday.map((e) => e.period).toSet(), {'上午', '下午'});
      expect(sunday.map((e) => e.period).toSet(), {'上午', '下午'});
      final repeat = await ScheduleImportService.commit(input, database: db);
      expect(repeat.tableId, first.tableId);
      expect(repeat.inserted, 0);
      expect(repeat.deleted, 0);
      expect(await rows(), before);
    },
  );

  test(
    'source time labels come from the individual meeting and do not turn classroom text into time',
    () {
      final morning = meeting(reference: '1,3周一-上午课-A101');
      final afternoon = meeting(reference: '2周二-下午课-B202');
      final evening = meeting(reference: '4周三-晚上课-C303');
      expect(morning.toJson()['periodLabel'], '上午');
      expect(afternoon.toJson()['periodLabel'], '下午');
      expect(evening.toJson()['periodLabel'], '晚上');
      expect(morning.isPending, isFalse);
      final roomOnly = meeting(reference: '1周一-时间待定-上午楼101', room: '上午楼101');
      expect(roomOnly.toJson()['periodLabel'], isNull);
      expect(roomOnly.isPending, isTrue);
      expect(morning.startMinute, isNull);
      expect(morning.endMinute, isNull);
    },
  );

  test(
    'arbitrary explicit clocks need no school template and retain exact instants',
    () async {
      final result = await ScheduleImportService.commit(
        draft([
          course('CLOCK', [meeting(day: 3, start: 497, end: 581)]),
        ]),
        database: db,
      );
      final schedule = await savedSchedule(result.tableId);
      expect(schedule.pending, isEmpty);
      expect(schedule.occurrences, hasLength(2));
      expect(schedule.occurrences.first.start, DateTime(2026, 9, 9, 8, 17));
      expect(schedule.occurrences.first.end, DateTime(2026, 9, 9, 9, 41));
      expect(schedule.occurrences.first.clockRange, '08:17–09:41');
      expect(ScheduleCalendarExporter.exportable(schedule), hasLength(2));
      final events =
          ScheduleDerivedDataService.snapshot(schedule)['occurrences'] as List;
      expect(events, hasLength(2));
      expect(
        events.first['startMs'],
        DateTime.utc(2026, 9, 9, 0, 17).millisecondsSinceEpoch,
      );
    },
  );

  test(
    'explicit periods without a clock table preserve periods without assigning clock times',
    () async {
      final result = await ScheduleImportService.commit(
        draft([
          course('PERIOD', [
            meeting(period: 3, count: 1, reference: '1,3周一第3-4节'),
          ]),
        ]),
        database: db,
      );
      final schedule = await savedSchedule(result.tableId);
      expect(schedule.pending, isEmpty);
      expect(schedule.occurrences, hasLength(2));
      expect(schedule.occurrences.first.period, contains('3'));
      expect(schedule.occurrences.first.period, contains('4'));
      expect(
        schedule.occurrences.every((e) => e.start == null && e.end == null),
        isTrue,
      );
      expect(
        ScheduleDerivedDataService.snapshot(schedule)['occurrences'],
        isEmpty,
      );
    },
  );

  test(
    'custom period labels remain visible and never imply predefined school clock times',
    () async {
      final result = await ScheduleImportService.commit(
        draft([
          course('CUSTOM', [
            meeting(day: 2, weeks: [2], label: '午间研讨'),
          ]),
        ]),
        database: db,
      );
      final schedule = await savedSchedule(result.tableId);
      expect(schedule.pending, isEmpty);
      expect(schedule.occurrences.single.period, '午间研讨');
      expect(schedule.occurrences.single.start, isNull);
      expect(schedule.occurrences.single.end, isNull);
      expect(ScheduleCalendarExporter.exportable(schedule), isEmpty);
    },
  );

  test(
    'mixed time precision keeps explicit period numbers and only exports genuine clocks',
    () async {
      final result = await ScheduleImportService.commit(
        draft([
          course('CLOCK', [meeting(start: 497, end: 581)]),
          course('PERIOD', [meeting(period: 3, count: 1)]),
          course('LABEL', [meeting(label: '下午')]),
          course('CUSTOM', [
            meeting(day: 2, weeks: [2], label: '午间研讨'),
          ]),
          course('UNKNOWN', [meeting(day: 3, reference: '上课时间待通知')]),
        ]),
        database: db,
      );
      final schedule = await savedSchedule(result.tableId);
      expect(schedule.occurrences, hasLength(7));
      expect(schedule.pending, hasLength(1));
      final periods = schedule.occurrences.where(
        (e) => e.course.classNumber == 'PERIOD',
      );
      expect(
        periods.every((e) => e.period.contains('3') && e.period.contains('4')),
        isTrue,
      );
      expect(periods.every((e) => e.start == null && e.end == null), isTrue);
      final label = schedule.occurrences.where(
        (e) => e.course.classNumber == 'LABEL',
      );
      expect(label.every((e) => e.period == '下午' && e.start == null), isTrue);
      expect(ScheduleCalendarExporter.exportable(schedule), hasLength(2));
      final events =
          ScheduleDerivedDataService.snapshot(schedule)['occurrences'] as List;
      expect(events, hasLength(2));
      expect(events.every((e) => e['title'] == '课程 CLOCK'), isTrue);
    },
  );

  test(
    'unknown time preserves known date fields and distinct source rows without inventing dated sessions',
    () async {
      final input = draft([
        course('UNKNOWN', [
          meeting(reference: '第一条安排：具体时间待教务通知'),
          meeting(reference: '第二条安排：具体时间待教师通知'),
        ]),
        course('NO-WEEK', [meeting(day: 2, weeks: null, label: '上午')]),
        course('NO-DAY', [
          meeting(day: null, weeks: [2], label: '下午'),
        ]),
        course('EMPTY-WEEKS', [meeting(day: 5, weeks: [], label: '晚上')]),
      ]);
      final result = await ScheduleImportService.commit(input, database: db);
      final saved = await rows();
      expect(saved, hasLength(5));
      final unknown = saved.where((r) => r['class_number'] == 'UNKNOWN');
      expect(unknown, hasLength(2));
      expect(
        unknown.every((r) => r['week_time'] == 1 && r['weeks'] == '[1,3]'),
        isTrue,
      );
      final schedule = await savedSchedule(result.tableId);
      expect(schedule.pending, hasLength(5));
      expect(schedule.occurrences, isEmpty);
      final repeat = await ScheduleImportService.commit(input, database: db);
      expect(repeat.inserted, 0);
      expect(await rows(), saved);
    },
  );

  test(
    'same course retains disjoint weeks, changed rooms and two dayparts while exact duplicates collapse',
    () async {
      final first = meeting(weeks: [1, 3], label: '上午', room: 'A101');
      final result = await ScheduleImportService.commit(
        draft([
          course('MULTI', [
            first,
            first,
            meeting(weeks: [5, 7], label: '上午', room: 'B202'),
            meeting(weeks: [1, 3], label: '下午', room: 'A101'),
          ]),
        ]),
        database: db,
      );
      expect(await rows(), hasLength(3));
      final schedule = await savedSchedule(result.tableId);
      expect(schedule.occurrences, hasLength(6));
      expect(schedule.inWeek(2), isEmpty);
      expect(schedule.inWeek(5).single.course.classroom, 'B202');
      expect(schedule.inWeek(1).map((e) => e.period).toSet(), {'上午', '下午'});
    },
  );

  test(
    'repeat import preserves local clearing, schedule edits and a deleted meeting',
    () async {
      final input = draft([
        course('LOCAL', [
          meeting(label: '上午'),
          meeting(day: 2, label: '下午'),
        ], teacher: '来源教师'),
      ]);
      final first = await ScheduleImportService.commit(input, database: db);
      final before = await rows();
      await db.update(
        'Course',
        {
          'name': '我的课程名',
          'teacher': '',
          'classroom': '',
          'week_time': 0,
          'weeks': '[]',
          'start_time': 0,
          'time_count': 0,
        },
        where: 'id = ?',
        whereArgs: [before.first['id']],
      );
      await db.delete(
        'Course',
        where: 'id = ?',
        whereArgs: [before.last['id']],
      );
      final repeat = await ScheduleImportService.commit(input, database: db);
      expect(repeat.inserted, 0);
      expect(repeat.preservedDeleted, 1);
      final saved = (await rows()).single;
      expect(saved['id'], before.first['id']);
      expect(saved['name'], '我的课程名');
      expect(saved['teacher'], '');
      expect(saved['classroom'], '');
      expect(saved['week_time'], 0);
      expect(saved['weeks'], '[]');
      final facts = SavedCourseFacts.fromCourse(Course.fromMap(saved));
      expect(facts.teacherLabel, '教师待定');
      expect(facts.classroomLabel, '地点待定');
      final schedule = await savedSchedule(first.tableId);
      expect(schedule.pending, hasLength(1));
      expect(schedule.occurrences, isEmpty);
    },
  );

  test(
    'existing explicit class clocks still determine period-based course timing',
    () async {
      final result = await ScheduleImportService.commit(
        draft([
          course('KNOWN-PERIOD', [meeting(period: 2, count: 0)]),
        ]),
        database: db,
        periods: [
          {'label': '第1节', 'start': '08:05', 'end': '08:50'},
          {'label': '第2节', 'start': '09:05', 'end': '09:50'},
        ],
      );
      final schedule = await savedSchedule(result.tableId);
      expect(schedule.occurrences.first.start, DateTime(2026, 9, 7, 9, 5));
      expect(schedule.occurrences.first.end, DateTime(2026, 9, 7, 9, 50));
      expect(ScheduleCalendarExporter.exportable(schedule), hasLength(2));
    },
  );

  test(
    'invalid complete or partial clock ranges are not repaired with assumed times',
    () {
      for (final value in [
        meeting(start: 600, end: 599),
        meeting(start: 600, end: 600),
        meeting(start: -1, end: 600),
        meeting(start: 600, end: 1440),
        meeting(start: 600),
      ]) {
        expect(value.validate(), isNotEmpty);
      }
    },
  );

  test(
    'later numbered periods cannot inherit clocks from auto-generated exact-range slots',
    () async {
      final initial = draft([
        course('CLOCK', [meeting(start: 497, end: 581)]),
      ]);
      final first = await ScheduleImportService.commit(initial, database: db);
      final next = draft([
        course('CLOCK', [meeting(start: 497, end: 581)]),
        course('NUMBERED', [meeting(period: 1, count: 0)]),
      ]);
      await ScheduleImportService.commit(
        next,
        database: db,
        acceptChanges: true,
      );
      final schedule = await savedSchedule(first.tableId);
      final numbered = schedule.occurrences
          .where((e) => e.course.classNumber == 'NUMBERED')
          .toList();
      expect(numbered, hasLength(2));
      expect(numbered.every((e) => e.period.contains('1')), isTrue);
      expect(
        numbered.every((e) => e.start == null && e.end == null),
        isTrue,
        reason:
            'An auto-generated exact clock range is not a user-provided period-1 clock definition',
      );
      expect(ScheduleCalendarExporter.exportable(schedule), hasLength(2));
    },
  );

  test(
    'later numbered periods cannot alias previously generated morning or afternoon slots',
    () async {
      final initial = draft([
        course('BANDS', [meeting(label: '上午'), meeting(day: 2, label: '下午')]),
      ]);
      final first = await ScheduleImportService.commit(initial, database: db);
      final old = (await rows()).map((r) => r['id']).toSet();
      await ScheduleImportService.commit(
        draft([
          ...initial.courses,
          course('NUMBERED', [meeting(period: 2, count: 0)]),
        ]),
        database: db,
        acceptChanges: true,
      );
      final schedule = await savedSchedule(first.tableId);
      final numbered = schedule.occurrences.where(
        (e) => e.course.classNumber == 'NUMBERED',
      );
      expect(numbered, hasLength(2));
      expect(
        numbered.every((e) => e.period.contains('2') && e.period != '下午'),
        isTrue,
      );
      expect(numbered.every((e) => e.start == null && e.end == null), isTrue);
      expect(
        (await rows())
            .where((r) => r['class_number'] == 'BANDS')
            .map((r) => r['id'])
            .toSet(),
        old,
      );
    },
  );

  test(
    'refining an imported daypart to an exact clock updates one meeting without making it disappear',
    () async {
      final initial = draft([
        course('REFINE', [meeting(label: '上午')]),
      ]);
      final first = await ScheduleImportService.commit(initial, database: db);
      final refined = draft([
        course('REFINE', [meeting(start: 497, end: 581)]),
      ]);
      await ScheduleImportService.commit(
        refined,
        database: db,
        acceptChanges: true,
      );
      expect(await rows(), hasLength(1));
      final schedule = await savedSchedule(first.tableId);
      expect(schedule.pending, isEmpty);
      expect(schedule.occurrences, hasLength(2));
      expect(schedule.occurrences.first.start, DateTime(2026, 9, 7, 8, 17));
      expect(schedule.occurrences.first.end, DateTime(2026, 9, 7, 9, 41));
      final repeat = await ScheduleImportService.commit(refined, database: db);
      expect(repeat.inserted, 0);
      expect(await rows(), hasLength(1));
    },
  );
}
