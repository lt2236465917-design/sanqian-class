import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Use the existing image_picker platform contract without invoking a photo library.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:wheretosleepinnju/Pages/Import/PhotoScheduleImportView.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wheretosleepinnju/Models/Db/DbHelper.dart';
import 'package:wheretosleepinnju/Pages/Import/ImportReviewView.dart';
import 'package:wheretosleepinnju/Pages/Import/SchoolAccountView.dart';

const sourceText =
    '[[[{"text":"科目"},{"text":"安排"}],'
    '[{"text":"规则遗漏课程"},{"text":"3,4,6周一 13:30-16:30 6406"}]]]';

Map<String, dynamic> course(String name) => {
  'name': name,
  'meetings': [
    {
      'weekday': 1,
      'weeks': [3, 4, 6],
      'startMinute': 810,
      'endMinute': 990,
      'location': '6406',
    },
  ],
  'sourceLine': '3,4,6周一 13:30-16:30 6406',
};

class FixtureImagePicker extends ImagePickerPlatform {
  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async => [XFile('/fixture/one.png'), XFile('/fixture/two.png')];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sanqian/schedule_import');
  late Directory folder;
  late Database db;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) recognize;
  late Map<String, dynamic> portal;
  late bool hasKey;
  late ImagePickerPlatform originalPicker;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('portal-ai-review-');
    await databaseFactory.setDatabasesPath(folder.path);
    db = await DbHelper().open();
    calls = [];
    hasKey = true;
    originalPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = FixtureImagePicker();
    portal = {
      'courses': [],
      'timetableText': sourceText,
      'warnings': ['请核对网页课程是否完整'],
    };
    recognize = (_) async => {
      'courses': [course('规则遗漏课程')],
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'schoolAccount':
              return {
                'account': 'fixture-account',
                'accountLocalId': 'local-fixture',
              };
            case 'openPortal':
              return portal;
            case 'recognizePhotos':
            case 'recognizeText':
              return recognize(call);
            case 'cancelRecognition':
              return true;
            case 'hasAPIKey':
              return hasKey;
          }
          throw MissingPluginException(call.method);
        });
  });

  tearDown(() async {
    ImagePickerPlatform.instance = originalPicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<void> showReview(
    WidgetTester tester, {
    List<Map<String, dynamic>>? courses,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ImportReviewView(
          courses: courses ?? [],
          source: 'school-portal',
          timetableText: sourceText,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'AI 识别网页课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送并整理'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'empty local parse reaches review; consent sends source and never writes courses',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录并导入'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportReviewView), findsOneWidget);
      expect(find.text('请核对网页课程是否完整'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '查看变化并保存'))
            .onPressed,
        isNull,
      );
      expect(calls.where((c) => c.method == 'recognizeText'), isEmpty);

      hasKey = false;
      await tester.tap(find.text('DeepSeek 设置'));
      await tester.pumpAndSettle();
      expect(find.text('尚未保存 Key'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ImportReviewView), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'AI 识别网页课表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'recognizeText'), isEmpty);

      hasKey = true;
      await send(tester);
      expect(find.text('规则遗漏课程'), findsOneWidget);
      final request = calls.singleWhere((c) => c.method == 'recognizeText');
      expect(request.arguments, {'text': sourceText});
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '查看变化并保存'))
            .onPressed,
        isNotNull,
      );
      expect(await db.query('Course'), isEmpty);
      expect(await db.query('CourseTable'), isEmpty);
    },
  );

  testWidgets('native nested metadata reaches portal review after AI', (
    tester,
  ) async {
    recognize = (_) async => {
      'courses': [
        {
          ...course('原生桥接课程'),
          'raw': <Object?, Object?>{
            'recognition': 'deepseek',
            'sourceLine': '3,4,6周一 13:30-16:30 6406',
          },
        },
      ],
    };
    await showReview(tester);
    await send(tester);
    expect(find.text('原生桥接课程'), findsOneWidget);
    expect(find.text('AI 识别失败，当前核对内容已保留'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '查看变化并保存'))
          .onPressed,
      isNotNull,
    );
    expect(await db.query('Course'), isEmpty);
  });

  testWidgets(
    'AI reads original omitted rows and replacement requires another review',
    (tester) async {
      await showReview(tester, courses: [course('手动核对课程')]);
      await send(tester);
      expect(calls.singleWhere((c) => c.method == 'recognizeText').arguments, {
        'text': sourceText,
      });
      expect(find.text('核对 AI 识别结果'), findsOneWidget);
      await tester.tap(find.text('保留当前内容'));
      await tester.pumpAndSettle();
      expect(find.text('手动核对课程'), findsOneWidget);
      expect(find.text('规则遗漏课程'), findsNothing);
      await send(tester);
      await tester.tap(find.text('采用并继续核对'));
      await tester.pumpAndSettle();
      expect(find.text('规则遗漏课程'), findsOneWidget);
      expect(find.text('手动核对课程'), findsNothing);
      expect(await db.query('Course'), isEmpty);
    },
  );

  for (final failure in ['empty', 'invalid', 'network']) {
    testWidgets('$failure AI response preserves current review', (
      tester,
    ) async {
      recognize = (_) async {
        if (failure == 'network') {
          throw PlatformException(code: 'recognition', message: '网络暂不可用');
        }
        if (failure == 'empty') return {'courses': []};
        return {
          'courses': [
            {
              'name': '错误结果',
              'meetings': [
                {'weekday': 9},
              ],
            },
          ],
        };
      };
      await showReview(tester, courses: [course('手动核对课程')]);
      await send(tester);
      expect(find.text('手动核对课程'), findsOneWidget);
      expect(find.text('核对 AI 识别结果'), findsNothing);
      expect(
        find.textContaining(failure == 'network' ? '网络暂不可用' : '当前核对内容已保留'),
        findsOneWidget,
      );
      expect(await db.query('Course'), isEmpty);
    });
  }

  testWidgets('cancel ignores a late successful reply', (tester) async {
    final response = Completer<Object?>();
    recognize = (_) => response.future;
    await showReview(tester, courses: [course('手动核对课程')]);
    await send(tester);
    await tester.tap(find.text('取消识别'));
    await tester.pumpAndSettle();
    response.complete({
      'courses': [course('迟到结果')],
    });
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'cancelRecognition'), hasLength(1));
    expect(find.text('手动核对课程'), findsOneWidget);
    expect(find.text('迟到结果'), findsNothing);
    expect(find.text('核对 AI 识别结果'), findsNothing);
    expect(await db.query('Course'), isEmpty);
  });

  testWidgets('empty page without timetable material remains an error', (
    tester,
  ) async {
    portal = {'courses': []};
    await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录并导入'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportReviewView), findsNothing);
    expect(find.textContaining('未读取到可供 AI 识别的课表原文'), findsOneWidget);
    expect(calls.where((c) => c.method == 'recognizeText'), isEmpty);
  });

  testWidgets('local portal courses cannot bypass AI or missing source', (
    tester,
  ) async {
    portal = {
      'courses': [course('本地解析课程')],
    };
    await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录并导入'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportReviewView), findsNothing);
    expect(calls.where((c) => c.method == 'recognizeText'), isEmpty);
    expect(await db.query('Course'), isEmpty);
  });

  Future<void> showPhotos(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: PhotoScheduleImportView()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择课表图片'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 张'), findsOneWidget);
    expect(find.text('本机识别'), findsNothing);
    await tester.tap(find.text('AI 识别课表'));
    await tester.pumpAndSettle();
  }

  testWidgets('photos missing key preserves selection and sends nothing', (
    tester,
  ) async {
    hasKey = false;
    await showPhotos(tester);
    expect(find.text('尚未保存 Key'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 张'), findsOneWidget);
    expect(calls.where((c) => c.method == 'recognizePhotos'), isEmpty);
  });

  testWidgets('photos consent then AI result reaches review without writes', (
    tester,
  ) async {
    await showPhotos(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'recognizePhotos'), isEmpty);
    await tester.tap(find.text('AI 识别课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送并识别'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportReviewView), findsOneWidget);
    expect(calls.singleWhere((c) => c.method == 'recognizePhotos').arguments, {
      'paths': ['/fixture/one.png', '/fixture/two.png'],
      'ai': true,
    });
    expect(await db.query('Course'), isEmpty);
    expect(await db.query('CourseTable'), isEmpty);
  });

  testWidgets('photos failure retains selection and shows readable error', (
    tester,
  ) async {
    recognize = (_) async => throw PlatformException(
      code: 'recognition',
      message: 'AI 返回的课表字段格式不正确',
    );
    await showPhotos(tester);
    await tester.tap(find.text('发送并识别'));
    await tester.pumpAndSettle();
    expect(find.text('AI 返回的课表字段格式不正确'), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.text('已选择 2 张'), findsOneWidget);
    expect(find.byType(ImportReviewView), findsNothing);
  });

  testWidgets('photos cancel ignores late successful result', (tester) async {
    final reply = Completer<Object?>();
    recognize = (_) => reply.future;
    await showPhotos(tester);
    await tester.tap(find.text('发送并识别'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('取消识别'));
    await tester.pumpAndSettle();
    reply.complete({
      'courses': [course('迟到结果')],
    });
    await tester.pumpAndSettle();
    expect(find.byType(ImportReviewView), findsNothing);
    expect(find.text('已取消识别，已选图片保留'), findsOneWidget);
    expect(await db.query('Course'), isEmpty);
  });

  testWidgets('credentials save failure is visible and preserves typed input', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'schoolAccount') return null;
          if (call.method == 'saveSchoolAccount') {
            throw PlatformException(
              code: 'schedule_import',
              message: '无法访问安全凭据存储（-34018）',
            );
          }
          throw StateError('Unexpected method ${call.method}');
        });
    await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'fixture-account');
    await tester.enterText(fields.at(1), 'fixture-only-password');
    await tester.tap(find.text('登录并导入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前安装版本缺少安全存储权限'), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(
      tester.widget<TextField>(fields.at(1)).controller!.text,
      'fixture-only-password',
    );
    expect(calls.where((c) => c.method == 'openPortal'), isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '登录并导入'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'credentials saved metadata opens portal once without rereading passwords',
    (tester) async {
      final saved = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'schoolAccount') return null;
            if (call.method == 'saveSchoolAccount') return saved.future;
            if (call.method == 'openPortal') return null;
            throw StateError('Unexpected method ${call.method}');
          });
      await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'fixture-account');
      await tester.enterText(fields.at(1), 'fixture-only-password');
      await tester.tap(find.text('登录并导入'));
      await tester.pumpAndSettle();
      expect(find.text('正在打开学校网页…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      saved.complete({
        'account': 'fixture-account',
        'accountLocalId': 'local-fixture',
      });
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), [
        'schoolAccount',
        'saveSchoolAccount',
        'openPortal',
      ]);
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, isEmpty);
      expect(find.text('已保存账号（不代表当前网页登录成功）'), findsOneWidget);
    },
  );
}
