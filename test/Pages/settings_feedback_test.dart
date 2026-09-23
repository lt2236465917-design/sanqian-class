import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wheretosleepinnju/Models/Db/DbHelper.dart';
import 'package:wheretosleepinnju/Pages/Settings/DeepSeekSettingsView.dart';
import 'package:wheretosleepinnju/Pages/Settings/ReminderSettingsView.dart';
import 'package:wheretosleepinnju/Pages/Import/PhotoScheduleImportView.dart';
import 'package:wheretosleepinnju/Pages/Import/SchoolAccountView.dart';
import 'package:wheretosleepinnju/Resources/PersonalTheme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sanqian/schedule_import');
  const settings = MethodChannel('sanqian/settings');
  const calendar = MethodChannel('plugins.builttoroam.com/device_calendar');
  late Directory folder;
  late Database db;
  late bool hasKey, failSave, granted, failSync, failStatus;
  late List<MethodCall> calls;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    folder = await Directory.systemTemp.createTemp('settings-feedback-');
    await databaseFactory.setDatabasesPath(folder.path);
    db = await DbHelper().open();
    hasKey = false;
    failSave = false;
    failStatus = false;
    granted = false;
    failSync = false;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'hasAPIKey':
              if (failStatus) throw PlatformException(code: 'keychain');
              return hasKey;
            case 'saveAPIKey':
              if (failSave) throw PlatformException(code: 'keychain');
              hasKey = true;
              return true;
            case 'deleteAPIKey':
              hasKey = false;
              return true;
            case 'syncDerivedData':
              if (failSync) throw PlatformException(code: 'notifications');
              return <String, dynamic>{};
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(calendar, (call) async {
          calls.add(call);
          return granted;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settings, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settings, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(calendar, null);
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: personalTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settleReminders(WidgetTester tester) async {
    // SQLite can finish between frames without scheduling an animation.
    // Wait for the visible operation to finish, not just for animation quiescence.
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pumpAndSettle();
      if (find.text('正在更新提醒设置…').evaluate().isEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(find.text('正在更新提醒设置…'), findsNothing);
  }

  testWidgets(
    'key save failure keeps input, retries once and clears it only on success',
    (tester) async {
      failSave = true;
      await show(tester, const DeepSeekSettingsView());
      await tester.enterText(find.byType(TextField), 'fixture-key');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('保存未完成，输入已保留，请重试。'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'fixture-key',
      );
      expect(find.textContaining('PlatformException'), findsNothing);
      failSave = false;
      await tester.tap(find.widgetWithText(TextButton, '重试'));
      await tester.pumpAndSettle();
      expect(find.text('Key 已保存到本机安全存储'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(calls.where((c) => c.method == 'saveAPIKey'), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('key status failure is unknown and has a working retry', (
    tester,
  ) async {
    failStatus = true;
    hasKey = true;
    await show(tester, const DeepSeekSettingsView());
    expect(find.text('Key 状态暂不可用'), findsOneWidget);
    expect(find.text('尚未保存 Key'), findsNothing);
    failStatus = false;
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await tester.pumpAndSettle();
    expect(find.text('已保存 Key · ••••••••'), findsOneWidget);
  });

  testWidgets(
    'photo key status is visible before picking and refreshes after settings',
    (tester) async {
      await show(tester, const PhotoScheduleImportView());
      expect(find.text('尚未配置 DeepSeek Key，请先打开下方设置。'), findsOneWidget);
      expect(calls.where((c) => c.method.startsWith('recognize')), isEmpty);
      await tester.scrollUntilVisible(find.text('DeepSeek 设置'), 200);
      await tester.tap(find.text('DeepSeek 设置'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'fixture-key');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('已保存 DeepSeek Key · 识别时需联网验证'), findsOneWidget);
      expect(calls.where((c) => c.method.startsWith('recognize')), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'denied reminders keep switch off and resume retries the requested choice',
    (tester) async {
      await show(tester, const ReminderSettingsView());
      await tester.tap(find.text('提前 15 分钟'));
      await settleReminders(tester);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '提前 15 分钟'),
            )
            .value,
        isFalse,
      );
      expect(
        (await SharedPreferences.getInstance()).getBool('reminder_15'),
        isNull,
      );
      expect(calls.where((c) => c.method == 'syncDerivedData'), isEmpty);
      await tester.tap(find.text('打开系统设置'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'openAppSettings'), hasLength(1));
      granted = true;
      // The shared scheduling queue and SQLite must run outside each test's
      // separate fake clock, just as they do in the application event loop.
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await settleReminders(tester);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '提前 15 分钟'),
            )
            .value,
        isTrue,
      );
      expect(
        (await SharedPreferences.getInstance()).getBool('reminder_15'),
        isTrue,
      );
      expect(calls.where((c) => c.method == 'syncDerivedData'), hasLength(1));
      expect(find.text('打开系统设置'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reminder scheduling failure retries without toggling saved preference',
    (tester) async {
      granted = true;
      failSync = true;
      await show(tester, const ReminderSettingsView());
      await tester.runAsync(() => tester.tap(find.text('提前 3 小时')));
      await settleReminders(tester);
      expect(find.text('提醒设置已保存，但提醒尚未完成安排，请重试。'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool('reminder_180'),
        isTrue,
      );
      failSync = false;
      await tester.runAsync(() => tester.tap(find.text('重试提醒设置')));
      await settleReminders(tester);
      expect(find.text('已同步，当前没有待提醒的课程。'), findsOneWidget);
      expect(
        calls.where((c) => c.method == 'requestPermissions'),
        hasLength(1),
      );
      expect(calls.where((c) => c.method == 'syncDerivedData'), hasLength(2));
      expect(
        (await SharedPreferences.getInstance()).getBool('reminder_180'),
        isTrue,
      );
    },
  );

  testWidgets('deepseek settings explain key creation and local storage', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: personalTheme(Brightness.light),
        home: const DeepSeekSettingsView(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('怎么创建'), findsOneWidget);
    expect(find.text('打开 DeepSeek 开放平台'), findsOneWidget);
    expect(find.textContaining('不要把 Key 告诉他人'), findsOneWidget);
    expect(find.textContaining('学校账号、密码和验证码不会随识别发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('school import keeps the key shortcut below the login steps', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: personalTheme(Brightness.light),
        home: const SchoolAccountView(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('学校账号导入课表'), findsOneWidget);
    expect(find.text('学校账号与导入'), findsNothing);
    expect(find.text('尚未配置 DeepSeek Key，请先打开下方设置。'), findsOneWidget);
    expect(find.textContaining('只有你确认发送才会联网'), findsOneWidget);
    final open = tester.getTopLeft(
      find.widgetWithText(FilledButton, '打开学校网页'),
    );
    final shortcut = tester.getTopLeft(
      find.widgetWithText(TextButton, 'DeepSeek 设置'),
    );
    expect(shortcut.dy, greaterThan(open.dy));
    expect(tester.takeException(), isNull);
  });
}
