import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sanqian_class/Components/ScheduleDesign.dart';
import 'package:sanqian_class/Models/CourseTableModel.dart';
import 'package:sanqian_class/Models/Db/DbHelper.dart';
import 'package:sanqian_class/Pages/AddCourse/AddCourseView.dart';
import 'package:sanqian_class/generated/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    folder = await Directory.systemTemp.createTemp('add-course-intro-');
    await databaseFactory.setDatabasesPath(folder.path);
    db = await DbHelper().open();
    final table = await CourseTableProvider().insert(
      CourseTable(
        '秋季',
        data: jsonEncode({
          'class_time_list': [
            {'label': '上午', 'start': '09:00', 'end': '12:00'},
          ],
        }),
      ),
    );
    SharedPreferences.setMockInitialValues({'tableId': table.id!});
  });

  tearDown(() async {
    await db.close();
    await folder.delete(recursive: true);
  });

  testWidgets('manual add course uses the shared title card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: const AddView(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ScheduleIntro), findsOneWidget);
    expect(find.byType(ScheduleSection), findsNothing);
    expect(find.text('手动添加课程'), findsNWidgets(2));
    expect(find.text('课程信息'), findsOneWidget);
    expect(find.text('补充课程名称与教师，再选择上课安排。'), findsOneWidget);
    expect(find.widgetWithText(AppBar, '手动添加课程'), findsOneWidget);
    final intro = tester.getRect(find.byType(ScheduleIntro));
    final field = tester.getRect(find.byType(TextField).first);
    expect(field.top - intro.bottom, scheduleTitleContentGap);
    expect(tester.takeException(), isNull);
  });
}
