import 'dart:convert';

import '../Models/Db/DbHelper.dart';
import '../Pages/Share/qr_payload_codec.dart';

class QrScheduleImporter {
  static Future<int> import(Map<String, dynamic> payload) async {
    final table = Map<String, dynamic>.from(payload['table'] as Map);
    final name = (table['name'] ?? '').toString().trim();
    if (name.isEmpty) throw const FormatException('missing_table_name');
    final rows = (payload['courses'] as List)
        .map(
          (row) => QrPayloadCodec.payloadCourseToDbMap(
            Map<String, dynamic>.from(row as Map),
            tableId: 0,
          ),
        )
        .toList();
    final data = (table['data'] ?? '').toString();
    if (data.isNotEmpty && jsonDecode(data) is! Map) {
      throw const FormatException('invalid_table_data');
    }
    final db = await DbHelper().open();
    return db.transaction((txn) async {
      final id = await txn.insert(DbHelper.COURSETABLE_TABLE_NAME, {
        'name': name,
        'data': data,
      });
      final max = await txn.rawQuery(
        'SELECT MAX(course_id) AS value FROM Course',
      );
      var next = (max.first['value'] as int? ?? -1) + 1;
      final courseIds = <String, int>{};
      for (final row in rows) {
        row['tableid'] = id;
        row['course_id'] = courseIds.putIfAbsent(
          row['name'].toString(),
          () => next++,
        );
        await txn.insert(DbHelper.COURSE_TABLE_NAME, row);
      }
      return id;
    });
  }
}
