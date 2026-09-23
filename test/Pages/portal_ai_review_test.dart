import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Use the existing image_picker platform contract without invoking a photo library.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:wheretosleepinnju/Pages/Import/PhotoScheduleImportView.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wheretosleepinnju/Models/Db/DbHelper.dart';
import 'package:wheretosleepinnju/Pages/Import/ImportReviewView.dart';
import 'package:wheretosleepinnju/Pages/Import/SchoolAccountView.dart';
import 'package:wheretosleepinnju/Resources/PersonalTheme.dart';
import 'package:wheretosleepinnju/Models/ScheduleImportDraft.dart';
import 'package:wheretosleepinnju/Utils/ScheduleImportService.dart';
import 'package:wheretosleepinnju/Utils/States/MainState.dart';
import 'package:wheretosleepinnju/Pages/Import/Widgets/RecognitionProgress.dart';

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

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

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
    SharedPreferences.setMockInitialValues({});
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

  Future<void> send(WidgetTester tester, {bool settle = true}) async {
    await tester.tap(find.widgetWithText(FilledButton, 'AI 识别网页课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送并整理'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets(
    'empty local parse reaches review; consent sends source and never writes courses',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '打开学校网页'));
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
    await send(tester, settle: false);
    expect(find.byType(RecognitionProgress), findsOneWidget);
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
    expect(find.byType(RecognitionProgress), findsNothing);
    expect(await db.query('Course'), isEmpty);
  });

  testWidgets(
    'AI field changes can be restored including the prior review gate',
    (tester) async {
      final original = {
        ...course('同一课程'),
        'courseCode': 'C1',
        'teacher': '原教师',
      };
      final updated = {
        ...course('同一课程'),
        'courseCode': 'C1',
        'teacher': 'AI 教师',
        'meetings': [
          {
            ...(course('同一课程')['meetings'] as List).single as Map,
            'weekday': 2,
            'location': 'AI 教室',
          },
        ],
      };
      recognize = (_) async => {
        'courses': [updated],
      };
      await showReview(tester, courses: [original]);
      await send(tester);
      expect(find.text('教师\n原：原教师\nAI：AI 教师'), findsOneWidget);
      expect(find.text('星期\n原：1\nAI：2'), findsOneWidget);
      expect(find.text('教室\n原：6406\nAI：AI 教室'), findsOneWidget);
      await tester.tap(find.text('采用并继续核对'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '查看变化并保存'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('恢复本次 AI 处理前的内容'));
      await tester.pumpAndSettle();
      expect(find.textContaining('AI 教室'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '查看变化并保存'))
            .onPressed,
        isNull,
      );
      expect(original['teacher'], '原教师');
      expect(await db.query('Course'), isEmpty);
    },
  );

  testWidgets(
    'recognition honors reduced motion and cancel still rejects late output',
    (tester) async {
      final response = Completer<Object?>();
      recognize = (_) => response.future;
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const ImportReviewView(
            courses: [],
            source: 'school-portal',
            timetableText: sourceText,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await send(tester);
      expect(find.byType(RecognitionProgress), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.tap(find.text('取消识别'));
      await tester.pumpAndSettle();
      response.complete({
        'courses': [course('迟到结果')],
      });
      await tester.pumpAndSettle();
      expect(find.text('迟到结果'), findsNothing);
      expect(await db.query('Course'), isEmpty);
    },
  );

  Future<int> savedContext({
    String term = '2026 秋季',
    String? account,
    String source = 'school-portal',
  }) => db.insert('CourseTable', {
    'name': term,
    'data': jsonEncode({
      'import_source_key': jsonEncode([
        source,
        'school-timetable',
        account,
        '中国艺术研究院',
        term,
      ]),
      'semester_start_monday': '2026-09-07',
    }),
  });

  testWidgets(
    'saved semester fills only unique matching context and keeps manual input',
    (tester) async {
      await savedContext();
      final foreign = await savedContext(
        term: '其他账号学期',
        account: 'different-account',
      );
      await showReview(tester);
      expect(
        tester.widget<TextField>(field('学期，例如 2026 秋季')).controller!.text,
        '2026 秋季',
      );
      expect(find.text('2026-9-7'), findsOneWidget);
      await tester.enterText(field('学期，例如 2026 秋季'), '手动学期');
      await tester.pumpAndSettle();
      expect(find.text('请选择，不能以导入日期代替'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('合并到 其他账号学期').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('学期，例如 2026 秋季')).controller!.text,
        '手动学期',
      );
      expect(find.textContaining('所选课表的来源、账号或学期不同'), findsOneWidget);
      expect(find.text('2026-9-7'), findsNothing);
      expect(
        (await db.query(
          'CourseTable',
          where: 'id = ?',
          whereArgs: [foreign],
        )).single['name'],
        '其他账号学期',
      );
    },
  );

  testWidgets(
    'multiple semesters are not guessed and date picker only allows Mondays',
    (tester) async {
      await savedContext();
      await savedContext(term: '2027 春季');
      await showReview(tester);
      expect(
        tester.widget<TextField>(field('学期，例如 2026 秋季')).controller!.text,
        '',
      );
      expect(find.textContaining('存在多个已保存学期'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('first-week-monday')),
      );
      await tester.tap(find.byKey(const ValueKey('first-week-monday')));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.initialDate, isNull);
      expect(picker.selectableDayPredicate!(DateTime(2026, 9, 21)), isTrue);
      expect(picker.selectableDayPredicate!(DateTime(2026, 9, 22)), isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('请选择，不能以导入日期代替'), findsOneWidget);
    },
  );

  testWidgets(
    'save shows a compact summary and stale confirmation cannot overwrite changes',
    (tester) async {
      final original = {
        ...course('有本地修改的课程'),
        'courseCode': 'C1',
        'teacher': '原教师',
      };
      await ScheduleImportService.commit(
        ScheduleImportDraft(
          source: 'photos',
          sourceId: 'school-timetable',
          school: '中国艺术研究院',
          term: '2026 秋季',
          firstWeekMonday: DateTime(2026, 9, 7),
          courses: [ScheduleImportCourseDraft.fromJson(original)],
        ),
        database: db,
        periods: [
          {'start': '13:30', 'end': '16:30', 'label': '下午'},
        ],
      );
      await db.update('Course', {'teacher': '本地教师'});
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ScopedModel<MainStateModel>(
          model: MainStateModel(),
          child: MaterialApp(
            home: ImportReviewView(
              source: 'photos',
              courses: [
                {...original, 'teacher': '来源教师'},
                {...course('新增课程'), 'courseCode': 'C2'},
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看变化并保存'));
      await tester.tap(find.text('查看变化并保存'));
      await tester.pumpAndSettle();
      expect(find.text('确认导入变化'), findsOneWidget);
      expect(find.text('新增 1'), findsOneWidget);
      expect(find.textContaining('处来源或本地编辑冲突'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(ExpansionTile),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('新增课程'),
        ),
        findsNothing,
      );
      await db.update('Course', {'classroom': '核对期间改动'});
      await tester.tap(find.text('确认保存'));
      await tester.pumpAndSettle();
      expect(find.text('课表在核对期间发生了变化，请重新查看变化后保存。'), findsOneWidget);
      final rows = await db.query('Course');
      expect(rows, hasLength(1));
      expect(rows.single['teacher'], '本地教师');
      expect(rows.single['classroom'], '核对期间改动');
    },
  );

  testWidgets('empty page without timetable material remains an error', (
    tester,
  ) async {
    portal = {'courses': []};
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '打开学校网页'));
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
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '打开学校网页'));
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

  testWidgets(
    'photo removal updates only the consented batch in the same flow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: personalTheme(Brightness.light),
          home: const PhotoScheduleImportView(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择课表图片'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '查看第 1 张课表原图',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 1 张课表图片'), findsOneWidget);
      expect(calls.where((c) => c.method == 'recognizePhotos'), isEmpty);
      await tester.tap(find.byTooltip('关闭原图'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除第 1 张'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 张'), findsOneWidget);
      await tester.tap(find.text('AI 识别课表'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'recognizePhotos'), isEmpty);
      await tester.tap(find.text('发送并识别'));
      await tester.pumpAndSettle();
      expect(
        calls.singleWhere((c) => c.method == 'recognizePhotos').arguments,
        {
          'paths': ['/fixture/two.png'],
          'ai': true,
        },
      );
      expect(find.byType(ImportReviewView), findsOneWidget);
      expect(await db.query('Course'), isEmpty);
    },
  );

  Future<void> editCourse(
    WidgetTester tester,
    Map<String, dynamic> draft,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: personalTheme(Brightness.light),
        home: ImportReviewView(courses: [draft], source: 'photos'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(draft['name']));
    await tester.tap(find.text(draft['name']));
    await tester.pumpAndSettle();
    expect(find.text('编辑课程'), findsOneWidget);
  }

  testWidgets(
    'canceling an unknown time leaves it pending in the original editor',
    (tester) async {
      await editCourse(tester, {
        'name': '待定课程',
        'meetings': [<String, dynamic>{}],
      });
      await tester.ensureVisible(field('开始 HH:mm'));
      await tester.tap(field('开始 HH:mm'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('开始 HH:mm')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(field('结束 HH:mm')).controller!.text,
        isEmpty,
      );
      await tester.ensureVisible(find.text('完成核对'));
      await tester.tap(find.text('完成核对'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportReviewView), findsOneWidget);
      expect(find.textContaining('待定–待定'), findsOneWidget);
      expect(find.textContaining('09:00'), findsNothing);
      expect(await db.query('Course'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'week choices remain a draft and cancel preserves the existing selection',
    (tester) async {
      await editCourse(tester, course('周次核对课程'));
      await tester.binding.setSurfaceSize(const Size(320, 740));
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('上课周次'));
      await tester.tap(field('上课周次'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('单周'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭周次选择'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('上课周次')).controller!.text, '3,4,6');
      await tester.tap(field('上课周次'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('双周'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认周次'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('上课周次')).controller!.text,
        '2,4,6,8,10,12,14,16,18,20',
      );
      await tester.ensureVisible(find.text('完成核对'));
      await tester.tap(find.text('完成核对'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportReviewView), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('[2, 4, 6, 8, 10, 12, 14, 16, 18, 20]'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.textContaining('[2, 4, 6, 8, 10, 12, 14, 16, 18, 20]'),
        findsOneWidget,
      );
      expect(await db.query('Course'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

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
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'fixture-account');
    await tester.enterText(fields.at(1), 'fixture-only-password');
    await tester.tap(find.widgetWithText(FilledButton, '打开学校网页'));
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
          .widget<FilledButton>(find.widgetWithText(FilledButton, '打开学校网页'))
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
      await tester.binding.setSurfaceSize(const Size(430, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SchoolAccountView()));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'fixture-account');
      await tester.enterText(fields.at(1), 'fixture-only-password');
      await tester.tap(find.widgetWithText(FilledButton, '打开学校网页'));
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
      expect(find.textContaining('本机已记住账号 fixture-account'), findsOneWidget);
    },
  );
}
