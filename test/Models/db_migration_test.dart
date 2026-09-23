import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wheretosleepinnju/Models/CourseModel.dart';
import 'package:wheretosleepinnju/Models/Db/DbHelper.dart';

const v1CourseTable = '''
CREATE TABLE CourseTable (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT
)''';

const v1Course = '''
CREATE TABLE Course (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tableid INTEGER,
  name TEXT,
  classroom TEXT,
  class_number TEXT,
  teacher TEXT,
  test_time TEXT,
  test_location TEXT,
  link TEXT,
  weeks TEXT,
  week_time INTEGER,
  start_time INTEGER,
  time_count INTEGER,
  import_type INTEGER,
  color TEXT
)''';

const v2Course = '''
CREATE TABLE Course (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tableid INTEGER,
  name TEXT,
  classroom TEXT,
  class_number TEXT,
  teacher TEXT,
  test_time TEXT,
  test_location TEXT,
  link TEXT,
  weeks TEXT,
  week_time INTEGER,
  start_time INTEGER,
  time_count INTEGER,
  import_type INTEGER,
  color TEXT,
  course_id INTEGER
)''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Future<Set<String>> columns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toSet();
  }

  Future<Database> upgraded(int version) async {
    final folder = await Directory.systemTemp.createTemp('db-v$version-');
    addTearDown(() async {
      if (folder.existsSync()) folder.deleteSync(recursive: true);
    });
    await databaseFactory.setDatabasesPath(folder.path);
    final path = join(folder.path, DbHelper.DATABASE_NAME);
    final seeded = await openDatabase(
      path,
      version: version,
      onCreate: (db, _) async {
        await db.execute(version == 1 ? v1CourseTable : v1CourseTable);
        await db.execute(version == 1 ? v1Course : v2Course);
        final tableId = await db.insert('CourseTable', {'name': '旧课表'});
        await db.insert('Course', {
          'tableid': tableId,
          'name': '旧课程',
          'classroom': '旧教室',
          'teacher': '旧老师',
          'weeks': '[1,2,2]',
          'week_time': 1,
          'start_time': 1,
          'time_count': 1,
          'import_type': 0,
          'color': '#112233',
          if (version >= 2) 'course_id': 7,
        });
      },
    );
    await seeded.close();
    return DbHelper().open();
  }

  for (final version in [1, 2]) {
    test('v$version database upgrades to v3 and keeps course rows', () async {
      final db = await upgraded(version);
      addTearDown(db.close);
      expect(await columns(db, 'Course'), containsAll(['info', 'data', 'course_id', 'name']));
      expect(await columns(db, 'CourseTable'), containsAll(['name', 'data']));
      await db.rawQuery('SELECT data, info FROM Course');
      await db.rawQuery('SELECT data FROM CourseTable');

      final oldRows = await db.query('Course');
      expect(oldRows, hasLength(1));
      expect(oldRows.single['name'], '旧课程');
      expect(oldRows.single['teacher'], '旧老师');
      expect(oldRows.single['classroom'], '旧教室');
      expect(oldRows.single['weeks'], '[1,2,2]');
      if (version == 2) expect(oldRows.single['course_id'], 7);
      expect((await db.query('CourseTable')).single['name'], '旧课表');

      await DbHelper.upgrade(db, version, DbHelper.DATABASE_VERSION);

      final tableId = (await db.query('CourseTable')).single['id'] as int;
      final provider = CourseProvider();
      final created = await provider.insert(Course(
        tableId,
        '新课程',
        '[1,3]',
        2,
        3,
        1,
        0,
        teacher: '新老师',
        classroom: 'A1',
        info: '说明',
        data: '{"k":1}',
      ));
      created.classroom = 'B2';
      created.info = '更新说明';
      expect(await provider.update(created), 1);
      final rows = await provider.getAllCourses(tableId);
      final fresh = rows.cast<Map>().singleWhere((row) => row['name'] == '新课程');
      expect(fresh['classroom'], 'B2');
      expect(fresh['info'], '更新说明');
      expect(fresh['data'], '{"k":1}');
      expect(fresh['teacher'], '新老师');
      final kept = rows.cast<Map>().singleWhere((row) => row['name'] == '旧课程');
      expect(kept['teacher'], '旧老师');
      expect(await provider.delete(created.id!), 1);
      expect(await provider.getAllCourses(tableId), hasLength(1));
    });
  }
}
