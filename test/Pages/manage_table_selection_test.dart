import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wheretosleepinnju/Models/Db/DbHelper.dart';
import 'package:wheretosleepinnju/Models/CourseTableModel.dart';
import 'package:wheretosleepinnju/Pages/ManageTable/ManageTableView.dart';
import 'package:wheretosleepinnju/Utils/States/MainState.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late Database db;
  late CourseTableProvider provider;
  late CourseTable a, b;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    folder = await Directory.systemTemp.createTemp('table-selection-');
    await databaseFactory.setDatabasesPath(folder.path);
    db = await DbHelper().open();
    addTearDown(() async {
      await db.close();
      await folder.delete(recursive: true);
    });
    await db.delete('CourseTable');
    provider = CourseTableProvider();
    a = await provider.insert(CourseTable('春季'));
    b = await provider.insert(CourseTable('秋季'));
    SharedPreferences.setMockInitialValues({'tableId': a.id!});
  });
  testWidgets(
    'tapping a name persists selection, keeps editing focus and uses one trailing icon',
    (tester) async {
      await tester.pumpWidget(
        ScopedModel<MainStateModel>(
          model: MainStateModel(),
          child: const MaterialApp(home: ManageTableView()),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump();
          if (find.byType(TextField).evaluate().length == 2 &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pumpAndSettle();
      }

      await settle();
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      Finder nameField(String name) => find.byWidgetPredicate(
        (w) => w is TextField && w.controller!.text == name,
      );
      await tester.runAsync(() => tester.tap(nameField('秋季')));
      await settle();
      expect((await SharedPreferences.getInstance()).getInt('tableId'), b.id);
      expect(find.text('课表管理'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        tester.widget<TextField>(nameField('秋季')).decoration!.labelText,
        '课表名称 · 当前课表',
      );
      expect(find.byTooltip('删除春季'), findsOneWidget);
      expect(find.byTooltip('删除秋季'), findsNothing);
      await tester.enterText(nameField('秋季'), '我的秋季');
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('保存')));
      await settle();
      final saved = await tester.runAsync(() => provider.getCourseTable(b.id!));
      expect(saved!.name, '我的秋季');
      expect((await SharedPreferences.getInstance()).getInt('tableId'), b.id);
      expect(tester.takeException(), isNull);
    },
  );
}
