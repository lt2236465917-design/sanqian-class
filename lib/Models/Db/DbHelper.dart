import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DbHelper {
  static const int DATABASE_VERSION = 3;
  static const String DATABASE_NAME = "course.db";

  static const String TEXT_TYPE = " TEXT";
  static const String INTEGER_TYPE = " INTEGER";

  static const String COMMA_SEP = ",";

  static const String COURSE_TABLE_NAME = "Course";
  static const String COURSE_COLUMN_ID = 'id';
  static const String COURSE_COLUMN_NAME = 'name';
  static const String COURSE_COLUMN_COURSETABLEID = 'tableid';
  static const String COURSE_COLUMN_CLASS_ROOM = "classroom";
  static const String COURSE_COLUMN_CLASS_NUMBER = "class_number";
  static const String COURSE_COLUMN_TEACHER = "teacher";
  static const String COURSE_COLUMN_TEST_TIME = "test_time";
  static const String COURSE_COLUMN_TEST_LOCATION = "test_location";
  static const String COURSE_COLUMN_INFO_LINK = "link";
  static const String COURSE_COLUMN_INFO = "info";
  static const String COURSE_COLUMN_DATA = "data";

  static const String COURSE_COLUMN_WEEKS = "weeks";
  static const String COURSE_COLUMN_WEEK_TIME = "week_time";
  static const String COURSE_COLUMN_START_TIME = "start_time";
  static const String COURSE_COLUMN_TIME_COUNT = "time_count";
  static const String COURSE_COLUMN_IMPORT_TYPE = "import_type";
  static const String COURSE_COLUMN_COLOR = "color";
  static const String COURSE_COLUMN_COURSE_ID = "course_id";

  static const String COURSETABLE_TABLE_NAME = "CourseTable";
  static const String COURSETABLE_COLUMN_ID = 'id';
  static const String COURSETABLE_COLUMN_NAME = 'name';
  static const String COURSETABLE_COLUMN_DATA = "data";

  static const String SQL_CREATE_COURSES =
      "CREATE TABLE " + COURSE_TABLE_NAME + " (" +
          COURSE_COLUMN_ID + INTEGER_TYPE + " PRIMARY KEY AUTOINCREMENT" + COMMA_SEP +
          COURSE_COLUMN_COURSETABLEID + INTEGER_TYPE + COMMA_SEP +
          COURSE_COLUMN_NAME + TEXT_TYPE + COMMA_SEP +
          COURSE_COLUMN_CLASS_ROOM + TEXT_TYPE + COMMA_SEP +
          COURSE_COLUMN_CLASS_NUMBER + TEXT_TYPE + COMMA_SEP +
          COURSE_COLUMN_TEACHER + TEXT_TYPE + COMMA_SEP +
          COURSE_COLUMN_TEST_TIME + TEXT_TYPE + COMMA_SEP +
          COURSE_COLUMN_TEST_LOCATION + TEXT_TYPE + COMMA_SEP +
          COURSE_COLUMN_INFO_LINK + TEXT_TYPE + COMMA_SEP +
          COURSE_COLUMN_INFO + TEXT_TYPE + COMMA_SEP +
          COURSE_COLUMN_DATA + TEXT_TYPE + COMMA_SEP +

          COURSE_COLUMN_WEEKS + TEXT_TYPE + COMMA_SEP +

          COURSE_COLUMN_WEEK_TIME + INTEGER_TYPE + COMMA_SEP +
          COURSE_COLUMN_START_TIME + INTEGER_TYPE + COMMA_SEP +
          COURSE_COLUMN_TIME_COUNT + INTEGER_TYPE + COMMA_SEP +

          COURSE_COLUMN_IMPORT_TYPE + INTEGER_TYPE + COMMA_SEP +
          COURSE_COLUMN_COLOR + TEXT_TYPE + COMMA_SEP +
          COURSE_COLUMN_COURSE_ID + INTEGER_TYPE +
//
//          COLUMN_NAME_WEEK + INTEGER_TYPE + COMMA_SEP +
//          COLUMN_NAME_START_WEEK + INTEGER_TYPE + COMMA_SEP +
//          COLUMN_NAME_END_WEEK + INTEGER_TYPE + COMMA_SEP +
//          COLUMN_NAME_WEEK_TYPE + INTEGER_TYPE + COMMA_SEP +
//
//          COLUMN_NAME_SOURCE + TEXT_TYPE +
          " )";

//  static const String SQL_CREATE_NODE =
//      "CREATE TABLE " + CoursesPsc.NodeEntry.TABLE_NAME + " (" +
//          CoursesPsc.NodeEntry.COLUMN_NAME_COURSE_ID + INTEGER_TYPE + COMMA_SEP +
//          CoursesPsc.NodeEntry.COLUMN_NAME_NODE_NUM + INTEGER_TYPE +
//          " )";

  static const String SQL_CREATE_COURSETABLE =
      "CREATE TABLE " + COURSETABLE_TABLE_NAME + " (" +
          COURSETABLE_COLUMN_ID + INTEGER_TYPE + " PRIMARY KEY AUTOINCREMENT" + COMMA_SEP +
          COURSETABLE_COLUMN_NAME + TEXT_TYPE + COMMA_SEP +
          COURSETABLE_COLUMN_DATA + TEXT_TYPE +
          " )";

  static const String SQL_UPDATE_COURSES_FROM_VERSION_1 =
      "ALTER TABLE " + COURSE_TABLE_NAME +
          " ADD COLUMN " + COURSE_COLUMN_COURSE_ID + INTEGER_TYPE;

  static const String SQL_UPDATE_COURSES_FROM_Version_2_PART_1 =
      "ALTER TABLE " + COURSE_TABLE_NAME +
          " ADD COLUMN " + COURSE_COLUMN_INFO + TEXT_TYPE;

  static const String SQL_UPDATE_COURSES_FROM_Version_2_PART_2 =
      "ALTER TABLE " + COURSE_TABLE_NAME +
          " ADD COLUMN " + COURSE_COLUMN_DATA + TEXT_TYPE;

  static const String SQL_UPDATE_COURSETABLE_FROM_Version_2 =
      "ALTER TABLE " + COURSETABLE_TABLE_NAME +
          " ADD COLUMN " + COURSETABLE_COLUMN_DATA + TEXT_TYPE;

  /// Version 2 added `course_id`. Version 3 added `info` / `data`.
  /// Each step checks PRAGMA table_info so a version-1 database that already
  /// has the tables still receives the missing columns, and a repeated upgrade
  /// does not fail when the column is already present.
  static Future<void> upgrade(
      Database db, int oldVersion, int newVersion) async {
    if (!await _tableExists(db, COURSETABLE_TABLE_NAME)) {
      await db.execute(SQL_CREATE_COURSETABLE);
    }
    if (!await _tableExists(db, COURSE_TABLE_NAME)) {
      await db.execute(SQL_CREATE_COURSES);
    }
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, COURSE_TABLE_NAME, COURSE_COLUMN_COURSE_ID,
          SQL_UPDATE_COURSES_FROM_VERSION_1);
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, COURSE_TABLE_NAME, COURSE_COLUMN_INFO,
          SQL_UPDATE_COURSES_FROM_Version_2_PART_1);
      await _addColumnIfMissing(db, COURSE_TABLE_NAME, COURSE_COLUMN_DATA,
          SQL_UPDATE_COURSES_FROM_Version_2_PART_2);
      await _addColumnIfMissing(db, COURSETABLE_TABLE_NAME,
          COURSETABLE_COLUMN_DATA, SQL_UPDATE_COURSETABLE_FROM_Version_2);
    }
  }

  static Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [table]);
    return rows.isNotEmpty;
  }

  static Future<void> _addColumnIfMissing(
      Database db, String table, String column, String statement) async {
    if (!await _tableExists(db, table)) return;
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((row) => row['name'] == column);
    if (exists) return;
    await db.execute(statement);
  }

  Future<Database> open() async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, DATABASE_NAME);
    Database db = await openDatabase(path, version: DATABASE_VERSION,
        onUpgrade: upgrade,
        onCreate: (Database db, int version) async {
          await db.execute(SQL_CREATE_COURSETABLE);
          await db.execute(SQL_CREATE_COURSES);
        });
    return db;
  }
}
