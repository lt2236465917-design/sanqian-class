import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sanqian_class/Models/Db/DbHelper.dart';
import 'package:sanqian_class/Models/CourseTableModel.dart';
import 'package:sanqian_class/Pages/ManageTable/ManageTableView.dart';
import 'package:sanqian_class/Utils/States/MainState.dart';

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
      expect(find.text('管理学期课表'), findsOneWidget);
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
      expect(find.text('课表名称已保存'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('课表名称已保存'), findsNothing);
      expect(nameField('我的秋季'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deleting a non-current table removes it without a failure message',
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
      Finder nameField(String name) => find.byWidgetPredicate(
        (w) => w is TextField && w.controller!.text == name,
      );
      await tester.runAsync(() => tester.tap(nameField('春季')));
      await settle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.byTooltip('删除秋季'));
      await tester.pumpAndSettle();
      expect(find.text('删除“秋季”？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      var sawFailure = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('操作未完成，请重试。').evaluate().isNotEmpty) {
          sawFailure = true;
        }
        final gone =
            find.byTooltip('删除秋季').evaluate().isEmpty &&
            nameField('秋季').evaluate().isEmpty;
        if (gone && find.byType(LinearProgressIndicator).evaluate().isEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(sawFailure, isFalse);
      expect(nameField('秋季'), findsNothing);
      expect(nameField('春季'), findsOneWidget);
      expect(find.text('操作未完成，请重试。'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
