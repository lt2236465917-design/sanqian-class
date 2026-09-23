import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wheretosleepinnju/Models/Db/DbHelper.dart';
import 'package:wheretosleepinnju/Models/CourseModel.dart';
import 'package:wheretosleepinnju/Models/CourseTableModel.dart';
import 'package:wheretosleepinnju/Pages/AddCourse/EditCourseView.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late Database db;
  late Course course;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    folder = await Directory.systemTemp.createTemp('edit-course-');
    await databaseFactory.setDatabasesPath(folder.path);
    db = await DbHelper().open();
    final table = await CourseTableProvider().insert(
      CourseTable(
        '秋季',
        data: jsonEncode({
          'class_time_list': [
            {'label': '上午', 'start': '09:00', 'end': '12:00'},
            {'label': '下午', 'start': '13:30', 'end': '16:30'},
          ],
        }),
      ),
    );
    course = await CourseProvider().insert(
      Course(
        table.id,
        '原课程',
        '[1,3,5]',
        3,
        1,
        0,
        7,
        teacher: '原教师',
        classroom: '6408',
        data: '{"source":"preserve"}',
        classNumber: 'ID001',
      ),
    );
    await CourseProvider().insert(Course(table.id, '另一安排', '[2]', 4, 2, 0, 7));
  });
  tearDown(() async {
    await db.close();
    await folder.delete(recursive: true);
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: EditCourseView(course: course)));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.text('重新读取作息').evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> save(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('保存课程'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.runAsync(() => tester.tap(find.text('保存课程')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'cancel discards draft without mutating database or source object',
    (tester) async {
      final before = await db.query('Course');
      await show(tester);
      await tester.enterText(field('课程名称'), '未保存');
      await tester.pumpWidget(const SizedBox());
      expect(course.name, '原课程');
      expect(await db.query('Course'), before);
    },
  );
  testWidgets(
    'save changes only selected course and preserves identity metadata and schedule',
    (tester) async {
      final other = (await db.query('Course')).last;
      await show(tester);
      await tester.enterText(field('课程名称'), '新课程');
      await save(tester);
      final rows = await db.query('Course');
      expect(rows.first['name'], '新课程');
      expect(rows.first['id'], course.id);
      expect(rows.first['weeks'], '[1,3,5]');
      expect(rows.first['import_type'], 7);
      expect(rows.first['class_number'], 'ID001');
      expect(rows.first['data'], '{"source":"preserve"}');
      expect(rows.last, other);
      expect(course.name, '原课程');
    },
  );
  testWidgets('unknown clock stays unknown when weekday changes', (
    tester,
  ) async {
    course.startTime = 0;
    course.timeCount = 0;
    await CourseProvider().update(course);
    await show(tester);
    final weekday = find.byType(DropdownButtonFormField<int>).first;
    await tester.ensureVisible(weekday);
    await tester.tap(weekday);
    await tester.pumpAndSettle();
    await tester.tap(find.text('星期四').last);
    await tester.pumpAndSettle();
    await save(tester);
    final row = (await db.query('Course')).first;
    expect(row['week_time'], 4);
    expect(row['start_time'], 0);
    expect(row['time_count'], 0);
    expect(row['weeks'], '[1,3,5]');
  });
  testWidgets(
    'invalid period range is rejected without changing the saved row',
    (tester) async {
      final before = await db.query('Course');
      await show(tester);
      final starts = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<int> &&
            w.decoration.labelText == '开始时段',
      );
      await tester.ensureVisible(starts);
      await tester.tap(starts);
      await tester.pumpAndSettle();
      await tester.tap(find.text('13:30–16:30').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect(find.text('请选择上课周次和有效的起止时段，或把安排设为待定。'), findsOneWidget);
      expect(await db.query('Course'), before);
    },
  );
  testWidgets('empty name is rejected and stored record remains unchanged', (
    tester,
  ) async {
    final before = await db.query('Course');
    await show(tester);
    await tester.enterText(field('课程名称'), '   ');
    await save(tester);
    expect(find.text('请填写课程名称'), findsOneWidget);
    expect(await db.query('Course'), before);
  });
}
