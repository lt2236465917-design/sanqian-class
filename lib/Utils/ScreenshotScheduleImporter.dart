import 'dart:convert';

import '../Models/Db/DbHelper.dart';
import '../Models/CourseModel.dart';
import '../Models/ScreenshotSchedule.dart';

class ScreenshotScheduleImporter {
  /// One transaction prevents a partially imported timetable. Reopening the
  /// same source supplements missing details and keeps existing course IDs,
  /// local edits and deletions. It never inserts duplicate courses.
  static Future<int> importOrOpen(ScreenshotSchedule schedule) async {
    final db = await DbHelper().open();
    return db.transaction((txn) async {
      final tables = await txn.query(DbHelper.COURSETABLE_TABLE_NAME);
      for (final table in tables) {
        try {
          final data = jsonDecode((table['data'] ?? '').toString());
          if (data is Map && data['source_id'] == schedule.id) {
            final tableId = table['id'] as int;
            if ((data['source_revision'] as int? ?? 1) < schedule.revision) {
              final rows = await txn.query(
                DbHelper.COURSE_TABLE_NAME,
                where: 'tableid = ?',
                whereArgs: [tableId],
              );
              for (final row in rows) {
                final patch = schedule.supplementFor(Course.fromMap(row));
                if (patch.isNotEmpty) {
                  await txn.update(
                    DbHelper.COURSE_TABLE_NAME,
                    patch,
                    where: 'id = ? AND tableid = ?',
                    whereArgs: [row['id'], tableId],
                  );
                }
              }
              final merged = schedule.supplementedTableData(
                Map<String, dynamic>.from(data),
              );
              merged['source_revision'] = schedule.revision;
              await txn.update(
                DbHelper.COURSETABLE_TABLE_NAME,
                {'data': jsonEncode(merged)},
                where: 'id = ?',
                whereArgs: [tableId],
              );
            }
            return tableId;
          }
        } on FormatException {
          // Older tables may have no metadata.
        }
      }
      final tableId = await txn.insert(DbHelper.COURSETABLE_TABLE_NAME, {
        'name': schedule.name,
        'data': schedule.tableData,
      });
      final maxId = await txn.rawQuery(
        'SELECT MAX(course_id) AS max_id FROM ${DbHelper.COURSE_TABLE_NAME}',
      );
      final firstId = (maxId.first['max_id'] as int? ?? -1) + 1;
      for (final course in schedule.toCourses(
        tableId: tableId,
        firstCourseId: firstId,
      )) {
        await txn.insert(DbHelper.COURSE_TABLE_NAME, course.toMap());
      }
      return tableId;
    });
  }
}
