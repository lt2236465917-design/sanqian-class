import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sanqian_class/Models/Db/DbHelper.dart';
import 'package:sanqian_class/Models/ScheduleImportDraft.dart';
import 'package:sanqian_class/Utils/ScheduleImportService.dart';
import 'import_time_precision_regression_test.dart' as cases;

void main() {
  late Database db;
  late Map<String, dynamic> fixture;
  late ScheduleImportDraft incoming;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(DbHelper.SQL_CREATE_COURSETABLE);
    await db.execute(DbHelper.SQL_CREATE_COURSES);
    fixture = jsonDecode(
      File('test/fixtures/ai_import_legacy_saved.json').readAsStringSync(),
    );
    final table = Map<String, dynamic>.from(fixture['table']);
    final metadata = Map<String, dynamic>.from(table['data']);
    final key = jsonDecode(metadata['import_source_key'] as String) as List;
    incoming = ScheduleImportDraft(
      source: key[0],
      sourceId: key[1],
      accountLocalId: key[2],
      school: key[3],
      term: key[4],
      firstWeekMonday: DateTime.parse(metadata['semester_start_monday']),
      courses: cases.realCourses(),
    );
    table['data'] = jsonEncode(metadata);
    await db.insert('CourseTable', table);
    for (final value in fixture['rows']) {
      final row = Map<String, dynamic>.from(value);
      row['data'] = jsonEncode(row['data']);
      row['weeks'] = jsonEncode(row['weeks']);
      await db.insert('Course', row);
    }
  });
  tearDown(() async => db.close());

  test(
    'reviewed reimport repairs an unedited old real export without duplicate course identities',
    () async {
      final before = await db.query('Course', orderBy: 'id');
      final preview = await ScheduleImportService.preview(
        incoming,
        database: db,
      );
      expect(preview.requiresChangeConfirmation, isTrue);
      await expectLater(
        ScheduleImportService.commit(incoming, database: db),
        throwsStateError,
      );
      expect(await db.query('Course', orderBy: 'id'), before);
      await ScheduleImportService.commit(
        incoming,
        database: db,
        acceptChanges: true,
        expectedReviewToken: preview.reviewToken,
      );
      final rows = await db.query('Course', orderBy: 'id');
      expect(rows, hasLength(25));
      expect(rows.where((r) => r['class_number'] == '49106104'), hasLength(4));
      expect(rows.where((r) => r['week_time'] == 0), hasLength(2));
      expect(rows.map((r) => r['course_id']).toSet(), hasLength(14));
      final repeated = await ScheduleImportService.commit(
        incoming,
        database: db,
      );
      expect(repeated.inserted, 0);
      expect(repeated.unchanged, 25);
      expect(repeated.conflicts, isEmpty);
      expect(await db.query('Course', orderBy: 'id'), rows);
    },
  );

  test(
    'a new coarse-time key cannot revive a deleted legacy arrangement or overwrite local edits',
    () async {
      final rows = await db.query('Course');
      final edited = rows.firstWhere((r) => r['class_number'] == '90001001');
      final deleted = rows.firstWhere(
        (r) =>
            r['class_number'] == '49106104' &&
            jsonDecode(
                  r['data'] as String,
                )['schedule_import_row']['original_meeting']['weekday'] ==
                6,
      );
      await db.update(
        'Course',
        {'name': '用户修改的课名', 'teacher': '', 'weeks': '[4]'},
        where: 'id = ?',
        whereArgs: [edited['id']],
      );
      await db.delete('Course', where: 'id = ?', whereArgs: [deleted['id']]);
      final result = await ScheduleImportService.commit(
        incoming,
        database: db,
        acceptChanges: true,
      );
      final after = await db.query('Course');
      expect(after.where((r) => r['class_number'] == '90001001'), hasLength(1));
      final kept = after.singleWhere((r) => r['id'] == edited['id']);
      expect(kept['name'], '用户修改的课名');
      expect(kept['teacher'], '');
      expect(kept['weeks'], '[4]');
      final resurrected = after.where((r) {
        if (r['class_number'] != '49106104') return false;
        final m = jsonDecode(
          r['data'] as String,
        )['schedule_import_row']['original_meeting'];
        return m['weekday'] == 6 && m['periodLabel'] == '下午';
      });
      expect(resurrected, isEmpty);
      expect(result.conflicts, isNotEmpty);
      expect(result.preservedDeleted, 2);
      final repeated = await ScheduleImportService.commit(
        incoming,
        database: db,
        acceptChanges: true,
      );
      expect(repeated.inserted, 0);
      expect(repeated.deleted, 0);
      expect(repeated.preservedDeleted, 2);
      expect(await db.query('Course'), after);
    },
  );
}
