import 'dart:convert';
import 'package:wheretosleepinnju/Models/CourseTableModel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wheretosleepinnju/Models/Db/DbHelper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Models/ScheduleImportDraft.dart';
import 'package:wheretosleepinnju/Utils/ScheduleImportService.dart';

ScheduleImportMeetingDraft meeting({
  List<int>? weeks,
  String? room = 'A101',
  int period = 2,
}) => ScheduleImportMeetingDraft(
  weekday: 2,
  weeks: weeks ?? [1, 2],
  periodIndex: period,
  periodCount: 0,
  location: room,
);

ScheduleImportCourseDraft course({
  String? code = 'C-1',
  String name = '课程一',
  String? teacher = '老师',
  List<ScheduleImportMeetingDraft>? meetings,
}) => ScheduleImportCourseDraft(
  courseCode: code,
  name: name,
  teacher: teacher,
  meetings: meetings ?? [meeting()],
  pendingReason: meetings == null ? null : '时间待定',
);

ScheduleImportDraft draft(List<ScheduleImportCourseDraft> courses) =>
    ScheduleImportDraft(
      source: 'portal',
      sourceId: 'semester-1',
      accountLocalId: 'account-a',
      school: 'NJU',
      term: '2026-fall',
      firstWeekMonday: DateTime(2026, 9, 7),
      courses: courses,
    );

void main() {
  sqliteTests();
  test(
    'bridge contract accepts weeks 1 through 60 and rejects outside bounds',
    () {
      final accepted = ScheduleImportMeetingDraft.fromJson({
        'weeks': [1, 53, 54, 60],
      });
      expect(accepted.validate(), isEmpty);
      final rejected = ScheduleImportMeetingDraft.fromJson({
        'weeks': [0, 61],
      });
      expect(
        rejected.validate(),
        contains('meeting.weeks contains an invalid week'),
      );
    },
  );
  test(
    'JSON integers and week arrays reject malformed types without truncation or filtering',
    () {
      for (final field in [
        'weekday',
        'periodIndex',
        'periodCount',
        'startMinute',
        'endMinute',
      ]) {
        for (final invalid in [1.5, 1.0, '2', true]) {
          expect(
            () => ScheduleImportMeetingDraft.fromJson({field: invalid}),
            throwsFormatException,
            reason: '$field must reject $invalid',
          );
        }
      }
      for (final invalid in [
        <dynamic>[1, 2.5],
        <dynamic>[1, '2'],
        <dynamic>[1, null],
        '1,2',
        true,
      ]) {
        expect(
          () => ScheduleImportMeetingDraft.fromJson({'weeks': invalid}),
          throwsFormatException,
        );
      }
      expect(
        ScheduleImportMeetingDraft.fromJson({'weeks': null}).weeks,
        isNull,
      );
      expect(
        ScheduleImportMeetingDraft.fromJson({
          'weeks': [1, 60],
        }).weeks,
        [1, 60],
      );
    },
  );

  test(
    'dedupe keeps week gaps, room changes and fills missing scalar fields',
    () {
      final merged = draft([
        course(teacher: null),
        course(
          teacher: '补全教师',
          meetings: [
            meeting(weeks: [3]),
            meeting(weeks: [1, 2], room: 'B202'),
          ],
        ),
      ]).normalised();

      expect(merged.courses, hasLength(1));
      expect(merged.courses.single.teacher, '补全教师');
      expect(merged.courses.single.meetings, hasLength(3));
      expect(
        merged.courses.single.meetings.map((item) => item.location),
        containsAll(<String?>['A101', 'B202']),
      );
    },
  );

  test(
    'validation distinguishes unknown weeks and rejects fabricated invalid clocks',
    () {
      final pending = ScheduleImportCourseDraft(
        courseCode: 'P-1',
        name: '待定课',
        meetings: const [],
        pendingReason: '门户未提供时间',
      );
      final invalid = ScheduleImportMeetingDraft(
        weekday: 8,
        weeks: [1, 1],
        startMinute: 18 * 60,
        endMinute: 17 * 60,
      );
      final errors = draft([
        pending,
        ScheduleImportCourseDraft(
          courseCode: 'X',
          name: '坏课',
          meetings: [invalid],
        ),
      ]).validate();

      expect(pending.isPending, isTrue);
      expect(
        errors,
        contains('courses[1].meetings[0].weekday must be between 1 and 7'),
      );
      expect(
        errors,
        contains('courses[1].meetings[0].weeks contains duplicates'),
      );
      expect(
        errors,
        contains('courses[1].meetings[0].endMinute must be after startMinute'),
      );
    },
  );

  test(
    'diff classifies added, changed, unchanged and pending stable identities',
    () {
      final incoming = draft([
        course(code: 'same'),
        course(
          code: 'changed',
          meetings: [meeting(room: 'B202')],
        ),
        course(code: 'new'),
        course(code: 'pending', meetings: const []),
      ]);
      final existing = [
        ScheduleImportStoredCourse(
          identity: 'code:same',
          meetingKey: meeting().meetingKey,
          fields: {
            'name': '课程一',
            'class_number': 'same',
            'teacher': '老师',
            'classroom': 'A101',
          },
        ),
        ScheduleImportStoredCourse(
          identity: 'code:changed',
          meetingKey: meeting().meetingKey,
          fields: {
            'name': '课程一',
            'class_number': 'changed',
            'teacher': '老师',
            'classroom': 'A101',
          },
        ),
      ];
      final result = ScheduleImportService.diff(incoming, existing: existing);

      expect(result.unchanged, ['code:same']);
      expect(result.changed, ['code:changed']);
      expect(result.added, containsAll(['code:new', 'code:pending']));
      expect(result.pending, contains('code:pending'));
    },
  );

  test(
    'deleted identities are skipped by diff and null semester start is review-only',
    () {
      final review = ScheduleImportDraft(
        source: 'portal',
        sourceId: 'semester-1',
        school: 'NJU',
        term: '2026-fall',
        firstWeekMonday: null,
        courses: [course()],
      );
      expect(review.validate(), isEmpty);
      final result = ScheduleImportService.diff(
        review,
        deletedIdentities: const ['code:c-1'],
      );
      expect(result.added, isEmpty);
      expect(result.changed, isEmpty);
      expect(result.pending, isEmpty);
    },
  );
}

void sqliteTests() {
  late Database db;
  final periods = [
    {'label': '上午', 'start': '09:00', 'end': '12:00'},
    {'label': '下午', 'start': '13:30', 'end': '16:30'},
  ];
  Future<List<Map<String, dynamic>>> rows() => db.query('Course');
  ScheduleImportDraft withAccount(String account) => ScheduleImportDraft(
    source: 'portal',
    sourceId: 'semester-1',
    accountLocalId: account,
    school: 'NJU',
    term: '2026-fall',
    firstWeekMonday: DateTime(2026, 9, 7),
    courses: [course()],
  );
  group('real SQLite transaction contract', () {
    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(DbHelper.SQL_CREATE_COURSETABLE);
      await db.execute(DbHelper.SQL_CREATE_COURSES);
    });
    tearDown(() async => db.close());
    Future<int> createLegacyTable() async {
      final tableId = await db.insert('CourseTable', {
        'name': '内置截图课表',
        'data': jsonEncode({
          'semester_start_monday': '2026-09-07',
          'class_time_list': periods,
          'source_id': 'built-in',
          'source_kind': 'screenshot',
        }),
      });
      await db.insert('Course', {
        'tableid': tableId,
        'course_id': 80,
        'name': '课程一',
        'class_number': 'C-1',
        'teacher': '本地老师',
        'classroom': 'A101',
        'weeks': '[1,2]',
        'week_time': 2,
        'start_time': 2,
        'time_count': 0,
        'import_type': 0,
        'info': '用户笔记',
        'data': jsonEncode({'custom': 'keep'}),
      });
      return tableId;
    }

    test(
      'renaming preserves courses and import metadata and rejects empty names',
      () async {
        final tableId = await createLegacyTable();
        final before = (await db.query(
          'CourseTable',
          where: 'id = ?',
          whereArgs: [tableId],
        )).single;
        final courses = await rows();
        final provider = CourseTableProvider()..dbHelper = _MemoryTableDb(db);
        await provider.rename(tableId, '  我的秋季课表  ');
        final after = (await db.query(
          'CourseTable',
          where: 'id = ?',
          whereArgs: [tableId],
        )).single;
        expect(after, {...before, 'name': '我的秋季课表'});
        expect(await rows(), courses);
        await expectLater(provider.rename(tableId, '  '), throwsArgumentError);
        await expectLater(provider.rename(-1, '不存在'), throwsStateError);
        expect((await db.query('CourseTable')).single, after);
      },
    );

    test(
      'explicit reviewed legacy binding preserves business fields and protects later imports',
      () async {
        final tableId = await createLegacyTable();
        final input = draft([course()]);
        final first = await ScheduleImportService.preview(
          input,
          database: db,
          mergeTableId: tableId,
        );
        expect(first.conflicts, isNotEmpty);
        expect(first.legacyCandidates, hasLength(1));
        final rowId = first.legacyCandidates.single['id'] as int;
        final bindings = {first.details.single['key'] as String: rowId};
        final review = await ScheduleImportService.preview(
          input,
          database: db,
          mergeTableId: tableId,
          legacyBindings: bindings,
        );
        expect(review.details.single['bindingRowId'], rowId);
        expect(review.requiresChangeConfirmation, isTrue);
        await expectLater(
          ScheduleImportService.commit(
            input,
            database: db,
            mergeTableId: tableId,
            legacyBindings: bindings,
            acceptChanges: true,
          ),
          throwsStateError,
        );
        await ScheduleImportService.commit(
          input,
          database: db,
          mergeTableId: tableId,
          legacyBindings: bindings,
          acceptChanges: true,
          expectedReviewToken: review.reviewToken,
        );
        final saved = (await rows()).single;
        expect(saved['id'], rowId);
        expect(saved['teacher'], '本地老师');
        expect(saved['info'], '用户笔记');
        expect(saved['import_type'], 0);
        expect(jsonDecode(saved['data'] as String)['custom'], 'keep');
        final changed = draft([course(teacher: '源教师改名')]);
        final next = await ScheduleImportService.preview(changed, database: db);
        await ScheduleImportService.commit(
          changed,
          database: db,
          acceptChanges: true,
          expectedReviewToken: next.reviewToken,
        );
        expect((await rows()).single['teacher'], '本地老师');
        expect((await rows()).single['info'], '用户笔记');
        expect(await rows(), hasLength(1));
      },
    );
    test(
      'legacy binding rejects duplicate row IDs, unknown inputs and rows already owned by a source',
      () async {
        final tableId = await createLegacyTable();
        final input = draft([
          course(meetings: [meeting(), meeting(period: 1)]),
        ]);
        final review = await ScheduleImportService.preview(
          input,
          database: db,
          mergeTableId: tableId,
        );
        final rowId = review.legacyCandidates.single['id'] as int;
        await expectLater(
          ScheduleImportService.preview(
            input,
            database: db,
            mergeTableId: tableId,
            legacyBindings: {
              for (final detail in review.details)
                detail['key'] as String: rowId,
            },
          ),
          throwsStateError,
        );
        await expectLater(
          ScheduleImportService.preview(
            input,
            database: db,
            mergeTableId: tableId,
            legacyBindings: {'invalid': rowId},
          ),
          throwsStateError,
        );
        final simple = draft([course()]);
        final key =
            (await ScheduleImportService.preview(
                  simple,
                  database: db,
                  mergeTableId: tableId,
                )).details.single['key']
                as String;
        final binding = {key: rowId};
        final valid = await ScheduleImportService.preview(
          simple,
          database: db,
          mergeTableId: tableId,
          legacyBindings: binding,
        );
        await ScheduleImportService.commit(
          simple,
          database: db,
          mergeTableId: tableId,
          legacyBindings: binding,
          acceptChanges: true,
          expectedReviewToken: valid.reviewToken,
        );
        await expectLater(
          ScheduleImportService.preview(
            simple,
            database: db,
            mergeTableId: tableId,
            legacyBindings: binding,
          ),
          throwsStateError,
        );
      },
    );
    test('a legacy binding selection is part of the reviewed token', () async {
      final tableId = await createLegacyTable();
      final input = draft([course()]);
      final first = await ScheduleImportService.preview(
        input,
        database: db,
        mergeTableId: tableId,
      );
      final bindings = {
        first.details.single['key'] as String:
            first.legacyCandidates.single['id'] as int,
      };
      await expectLater(
        ScheduleImportService.commit(
          input,
          database: db,
          mergeTableId: tableId,
          legacyBindings: bindings,
          acceptChanges: true,
          expectedReviewToken: first.reviewToken,
        ),
        throwsStateError,
      );
      expect(jsonDecode((await rows()).single['data'] as String), {
        'custom': 'keep',
      });
    });
    test('duplicate image courses retain evidence from both images', () async {
      final input = draft([
        for (final index in [0, 1])
          ScheduleImportCourseDraft(
            courseCode: 'OCR-X',
            name: '图片课',
            meetings: [meeting()],
            raw: {
              'sources': [
                {'imageIndex': index},
              ],
            },
          ),
      ]);
      await ScheduleImportService.commit(input, database: db, periods: periods);
      expect(await rows(), hasLength(1));
      final original = jsonDecode(
        (await rows()).single['data'] as String,
      )['schedule_import_row']['original_course'];
      expect(original['raw']['sources'], [
        {'imageIndex': 0},
        {'imageIndex': 1},
      ]);
    });
    test(
      'course OCR source evidence persists and can be refreshed without duplicating a row',
      () async {
        ScheduleImportDraft evidence(String text) => draft([
          ScheduleImportCourseDraft(
            courseCode: 'OCR-1',
            name: '证据课',
            teacher: '已知教师',
            section: '教学班一',
            meetings: [meeting()],
            raw: {
              'sources': [
                {
                  'imageIndex': 0,
                  'text': text,
                  'confidence': 0.92,
                  'box': {'x': 0.1, 'y': 0.2},
                },
              ],
            },
          ),
        ]);
        await ScheduleImportService.commit(
          evidence('第一张图片'),
          database: db,
          periods: periods,
        );
        final first = (await rows()).single;
        final source = jsonDecode(
          first['data'] as String,
        )['schedule_import_row']['original_course'];
        expect(source['courseCode'], 'OCR-1');
        expect(source['teacher'], '已知教师');
        expect(source['section'], '教学班一');
        expect(source['raw']['sources'][0]['imageIndex'], 0);
        expect(source['raw']['sources'][0]['box']['x'], 0.1);
        final preview = await ScheduleImportService.preview(
          evidence('补充图片'),
          database: db,
        );
        await ScheduleImportService.commit(
          evidence('补充图片'),
          database: db,
          expectedReviewToken: preview.reviewToken,
        );
        final refreshed = (await rows()).single;
        expect(refreshed['id'], first['id']);
        expect(
          jsonDecode(
            refreshed['data'] as String,
          )['schedule_import_row']['original_course']['raw']['sources'][0]['text'],
          '补充图片',
        );
      },
    );
    test(
      'review token is deterministic and accepts an unchanged reviewed input',
      () async {
        final input = draft([course()]);
        final first = await ScheduleImportService.preview(
          input,
          database: db,
          periods: periods,
        );
        final second = await ScheduleImportService.preview(
          input,
          database: db,
          periods: periods,
        );
        expect(first.reviewToken, isNotNull);
        expect(first.reviewToken, second.reviewToken);
        await ScheduleImportService.commit(
          input,
          database: db,
          periods: periods,
          expectedReviewToken: first.reviewToken,
        );
        expect(await rows(), hasLength(1));
      },
    );
    test(
      'accept changes does not accept rows modified after preview',
      () async {
        await ScheduleImportService.commit(
          draft([course()]),
          database: db,
          periods: periods,
        );
        final input = draft([course(teacher: '门户新教师')]);
        final preview = await ScheduleImportService.preview(
          input,
          database: db,
        );
        await db.update('Course', {'teacher': '预览后手动编辑'});
        final before = await rows();
        final tableBefore = await db.query('CourseTable');
        await expectLater(
          ScheduleImportService.commit(
            input,
            database: db,
            acceptChanges: true,
            expectedReviewToken: preview.reviewToken,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'import_review_stale',
            ),
          ),
        );
        expect(await rows(), before);
        expect(await db.query('CourseTable'), tableBefore);
      },
    );
    test(
      'token rejects changed draft, periods and table metadata before any writes',
      () async {
        final input = draft([course()]);
        final preview = await ScheduleImportService.preview(
          input,
          database: db,
          periods: periods,
        );
        await expectLater(
          ScheduleImportService.commit(
            draft([course(teacher: '未核对改动')]),
            database: db,
            periods: periods,
            expectedReviewToken: preview.reviewToken,
          ),
          throwsStateError,
        );
        await expectLater(
          ScheduleImportService.commit(
            input,
            database: db,
            periods: [
              {'start': '10:00', 'end': '12:00'},
            ],
            expectedReviewToken: preview.reviewToken,
          ),
          throwsStateError,
        );
        expect(await db.query('CourseTable'), isEmpty);
        await ScheduleImportService.commit(
          input,
          database: db,
          periods: periods,
          expectedReviewToken: preview.reviewToken,
        );
        final second = await ScheduleImportService.preview(input, database: db);
        final data =
            jsonDecode((await db.query('CourseTable')).single['data'] as String)
                as Map<String, dynamic>;
        data['semester_start_monday'] = '2026-09-14';
        await db.update('CourseTable', {'data': jsonEncode(data)});
        final before = await rows();
        await expectLater(
          ScheduleImportService.commit(
            input,
            database: db,
            acceptChanges: true,
            expectedReviewToken: second.reviewToken,
          ),
          throwsStateError,
        );
        expect(await rows(), before);
      },
    );
    test(
      'preview is read-only; repeat uses nested stable ID and preserves IDs',
      () async {
        final input = draft([
          ScheduleImportCourseDraft(
            stableId: 'stable-1',
            name: '编码缺失课',
            meetings: [meeting()],
          ),
        ]);
        await ScheduleImportService.preview(
          input,
          database: db,
          periods: periods,
        );
        expect(await db.query('CourseTable'), isEmpty);
        final first = await ScheduleImportService.commit(
          input,
          database: db,
          periods: periods,
        );
        final before = await rows();
        final second = await ScheduleImportService.commit(
          input,
          database: db,
          periods: periods,
        );
        expect(first.tableId, second.tableId);
        expect(second.inserted, 0);
        expect(await rows(), before);
        expect(before.single['week_time'], 2);
      },
    );
    test(
      'same source ID with different account creates a separate table and merge refuses',
      () async {
        final first = await ScheduleImportService.commit(
          withAccount('one'),
          database: db,
          periods: periods,
        );
        final second = await ScheduleImportService.commit(
          withAccount('two'),
          database: db,
          periods: periods,
        );
        expect(first.tableId, isNot(second.tableId));
        await expectLater(
          ScheduleImportService.commit(
            withAccount('two'),
            database: db,
            mergeTableId: first.tableId,
          ),
          throwsStateError,
        );
        expect(await db.query('CourseTable'), hasLength(2));
      },
    );
    test('failed insert rolls back table and all preceding rows', () async {
      await db.execute(
        "CREATE TRIGGER fail_import BEFORE INSERT ON Course WHEN NEW.name = '坏课' BEGIN SELECT RAISE(ABORT, 'failure'); END",
      );
      await expectLater(
        ScheduleImportService.commit(
          draft([course(), course(code: 'bad', name: '坏课')]),
          database: db,
          periods: periods,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await rows(), isEmpty);
      expect(await db.query('CourseTable'), isEmpty);
    });
    test('partial deletion stays deleted across three imports', () async {
      final input = draft([
        course(
          meetings: [
            meeting(),
            meeting(weeks: [3], room: 'B'),
          ],
        ),
      ]);
      await ScheduleImportService.commit(input, database: db, periods: periods);
      final initial = await rows();
      expect(initial[0]['course_id'], initial[1]['course_id']);
      await db.delete(
        'Course',
        where: 'id=?',
        whereArgs: [initial.first['id']],
      );
      for (var i = 0; i < 3; i++) {
        final result = await ScheduleImportService.commit(input, database: db);
        expect(result.preservedDeleted, 1);
        expect(await rows(), hasLength(1));
        expect((await rows()).single['id'], initial.last['id']);
      }
    });
    test('local edit plus moved meeting does not add a duplicate', () async {
      await ScheduleImportService.commit(
        draft([course()]),
        database: db,
        periods: periods,
      );
      await db.update('Course', {'name': '本地改名'});
      final before = await rows();
      final result = await ScheduleImportService.commit(
        draft([
          course(meetings: [meeting(period: 1)]),
        ]),
        database: db,
        acceptChanges: true,
      );
      expect(result.conflicts, isNotEmpty);
      expect(await rows(), before);
    });
    test(
      'pending course and known partial fields survive serialization and SQLite',
      () async {
        final input = draft([course(code: 'pending', meetings: [])]);
        final roundTrip = ScheduleImportDraft.fromJson(input.toJson());
        expect(roundTrip.sourceKey, input.sourceKey);
        await ScheduleImportService.commit(roundTrip, database: db);
        final saved = (await rows()).single;
        expect(saved['week_time'], 0);
        expect(saved['weeks'], '[]');
        expect(saved['name'], '课程一');
        final metadata = jsonDecode(
          saved['data'] as String,
        )['schedule_import_row'];
        expect(metadata['pending_reason'], '时间待定');
        expect(
          () => ScheduleImportMeetingDraft.fromJson({
            'weeks': [1, '2'],
          }),
          throwsFormatException,
        );
        expect(
          () => ScheduleImportMeetingDraft.fromJson({'weekday': 1.5}),
          throwsFormatException,
        );
      },
    );
    test(
      'source field change needs acceptance; source snapshot never absorbs local edit',
      () async {
        await ScheduleImportService.commit(
          draft([course()]),
          database: db,
          periods: periods,
        );
        await db.update('Course', {'teacher': '本机老师'});
        for (final teacher in ['源老师二', '源老师三', '源老师四']) {
          final input = draft([course(teacher: teacher)]);
          final preview = await ScheduleImportService.preview(
            input,
            database: db,
          );
          expect(preview.requiresChangeConfirmation, isTrue);
          await expectLater(
            ScheduleImportService.commit(input, database: db),
            throwsStateError,
          );
          final result = await ScheduleImportService.commit(
            input,
            database: db,
            acceptChanges: true,
          );
          expect(result.conflicts, isNotEmpty);
          expect((await rows()).single['teacher'], '本机老师');
          final data = jsonDecode(
            (await db.query('CourseTable')).single['data'] as String,
          );
          expect(data['course_snapshot'].single['fields']['teacher'], teacher);
        }
      },
    );
    test(
      'moved meeting needs acceptance and never uses ordinal mapping',
      () async {
        await ScheduleImportService.commit(
          draft([course()]),
          database: db,
          periods: periods,
        );
        final old = (await rows()).single['id'];
        final input = draft([
          course(meetings: [meeting(period: 1)]),
        ]);
        final preview = await ScheduleImportService.preview(
          input,
          database: db,
        );
        expect(preview.removed, hasLength(1));
        await expectLater(
          ScheduleImportService.commit(input, database: db),
          throwsStateError,
        );
        expect((await rows()).single['id'], old);
        await ScheduleImportService.commit(
          input,
          database: db,
          acceptChanges: true,
        );
        expect(await rows(), hasLength(1));
        expect((await rows()).single['id'], isNot(old));
      },
    );
    test(
      'exact clocks map to periods; unmatched times and unknown weeks stay pending with raw values',
      () async {
        final input = draft([
          course(
            meetings: [
              ScheduleImportMeetingDraft(
                weekday: 2,
                weeks: [1, 3],
                startMinute: 810,
                endMinute: 990,
              ),
              ScheduleImportMeetingDraft(
                weekday: 3,
                weeks: [1],
                startMinute: 800,
                endMinute: 990,
              ),
              ScheduleImportMeetingDraft(
                weekday: 4,
                weeks: null,
                startMinute: 810,
                endMinute: 990,
              ),
            ],
          ),
        ]);
        await ScheduleImportService.commit(
          input,
          database: db,
          periods: periods,
        );
        final saved = await rows();
        expect(saved[0]['start_time'], 2);
        expect(saved[0]['weeks'], '[1,3]');
        expect(saved[1]['week_time'], 0);
        expect(saved[2]['week_time'], 0);
        final meta = jsonDecode(
          saved[1]['data'] as String,
        )['schedule_import_row'];
        expect(meta['original_meeting']['startMinute'], 800);
        expect(meta['original_meeting']['weekday'], 3);
      },
    );
    test(
      'existing calendar metadata survives a new draft and invalid periods fail before writes',
      () async {
        await expectLater(
          ScheduleImportService.commit(
            draft([course()]),
            database: db,
            periods: [
              {'start': '9:00', 'end': '12:00'},
            ],
          ),
          throwsFormatException,
        );
        expect(await rows(), isEmpty);
        final initial = await ScheduleImportService.commit(
          draft([course()]),
          database: db,
          periods: periods,
        );
        final input = ScheduleImportDraft(
          source: 'portal',
          sourceId: 'semester-1',
          accountLocalId: 'account-a',
          school: 'NJU',
          term: '2026-fall',
          firstWeekMonday: DateTime(2026, 9, 14),
          courses: [course()],
        );
        await ScheduleImportService.commit(
          input,
          database: db,
          mergeTableId: initial.tableId,
          periods: [
            {'start': '14:00', 'end': '18:00'},
          ],
        );
        final data = jsonDecode(
          (await db.query('CourseTable')).single['data'] as String,
        );
        expect(data['semester_start_monday'], '2026-09-07');
        expect(data['class_time_list'], periods);
      },
    );
    test(
      'same name without stable identity remains an ambiguity rather than overwrite or duplicate',
      () async {
        await ScheduleImportService.commit(
          draft([course(code: null)]),
          database: db,
          periods: periods,
        );
        final before = await rows();
        final input = draft([course(code: null, teacher: '另一个老师')]);
        final preview = await ScheduleImportService.preview(
          input,
          database: db,
        );
        expect(preview.conflicts, isNotEmpty);
        await ScheduleImportService.commit(
          input,
          database: db,
          acceptChanges: true,
        );
        expect(await rows(), before);
      },
    );
  });
}

class _MemoryTableDb extends DbHelper {
  final Database database;
  _MemoryTableDb(this.database);
  @override
  Future<Database> open() async => database;
}
