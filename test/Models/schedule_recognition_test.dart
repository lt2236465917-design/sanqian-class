import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanqian_class/Models/ScheduleImportDraft.dart';

Map<String, dynamic> meeting({
  int day = 1,
  List<int>? weeks = const [3, 4, 6],
  int? start = 540,
  int? end = 720,
  String? room = '6406',
}) => {
  'weekday': day,
  'weeks': weeks,
  'startMinute': start,
  'endMinute': end,
  'location': room,
};
Map<String, dynamic> course({
  String name = '摄影-1',
  String? teacher = '张老师',
  String? code,
  String? section,
  List<Map<String, dynamic>>? meetings,
}) => {
  'name': name,
  'teacher': teacher,
  'courseCode': code,
  'section': section,
  'meetings': meetings ?? [meeting()],
  if (meetings?.isEmpty ?? false) 'pendingReason': '自行联系老师',
};

void main() {
  test(
    'quoted week and weekday contradictions warn without rewriting dates',
    () {
      final result = prepareScheduleRecognition([
        course(
          meetings: [
            {
              ...meeting(day: 7, weeks: [8]),
              'sourceReference': '8周二-上午课-6406',
            },
          ],
        ),
      ], source: 'photos');
      expect(result.warnings.single, contains('与 AI 引用的原文不一致'));
      expect(result.courses.single['meetings'][0]['weekday'], 7);
      expect(result.shouldOfferOCR, isTrue);
    },
  );

  test('quoted ranges, multiple weekdays and absent references stay valid', () {
    for (final reference in [
      '3,4周一-上午课 6-10周一-上午课',
      '3,4周一-上午课 3,4周二-下午课 6周一-上午课',
      '请核对原图',
      null,
    ]) {
      final result = prepareScheduleRecognition([
        course(
          meetings: [
            {...meeting(), 'sourceReference': reference},
          ],
        ),
      ], source: 'photos');
      expect(result.warnings, isEmpty);
      expect(result.shouldOfferOCR, isFalse);
    }
  });

  test('overlapping courses warn without discarding either arrangement', () {
    final input = [
      course(
        name: '课程甲',
        meetings: [
          meeting(weeks: [3, 6]),
        ],
      ),
      course(
        name: '课程乙',
        meetings: [
          meeting(weeks: [6, 8], start: 600),
        ],
      ),
    ];
    final original = jsonEncode(input);
    final result = prepareScheduleRecognition(input, source: 'photos');
    expect(result.warnings.single, contains('同周同时段重叠'));
    expect(result.shouldOfferOCR, isTrue);
    expect(result.courses, hasLength(2));
    expect(result.courses[0]['meetings'][0]['weeks'], [3, 6]);
    expect(result.courses[1]['meetings'][0]['weeks'], [6, 8]);
    expect(jsonEncode(input), original);
  });

  test(
    'different weeks, days, adjacent times and pending times do not clash',
    () {
      for (final other in [
        meeting(weeks: [7, 8]),
        meeting(day: 2),
        meeting(start: 720, end: 780),
        meeting(start: null, end: null),
        meeting(weeks: null),
      ]) {
        final result = prepareScheduleRecognition([
          course(name: '课程甲'),
          course(name: '课程乙', meetings: [other]),
        ], source: 'photos');
        expect(result.warnings.where((w) => w.contains('重叠')), isEmpty);
        expect(result.courses, hasLength(2));
      }
    },
  );

  test('merge multi-image courses and only exact scheduled duplicates', () {
    final input = [
      course(),
      course(meetings: [meeting(), meeting(day: 6)]),
      course(
        meetings: [
          meeting(weeks: [8]),
          meeting(room: '6407'),
        ],
      ),
    ];
    final original = jsonEncode(input);
    final result = prepareScheduleRecognition(input, source: 'photos');
    expect(result.courses, hasLength(1));
    expect(result.courses.single['meetings'], hasLength(4));
    expect(result.extraCourses, isEmpty);
    expect(result.shouldOfferOCR, isTrue);
    expect(result.hasStructuralAnomaly, isTrue);
    expect(jsonEncode(input), original);
    expect(
      prepareScheduleRecognition(result.courses, source: 'photos').courses,
      result.courses,
    );
  });

  test('repeated meetings within a single course are deduplicated', () {
    final result = prepareScheduleRecognition([
      course(
        meetings: [
          meeting(weeks: [6, 3, 4]),
          meeting(),
        ],
      ),
    ], source: 'photos');
    expect(result.courses.single['meetings'], hasLength(1));
    expect(result.warnings.single, contains('完全重复'));
  });

  for (final field in ['teacher', 'section', 'courseCode', 'stableId']) {
    test('conflicting $field remains separate', () {
      final result = prepareScheduleRecognition([
        {...course(), field: 'A'},
        {...course(), field: 'B'},
      ], source: 'photos');
      expect(result.courses, hasLength(2));
      expect(result.warnings.any((w) => w.contains('同名')), isTrue);
    });
  }

  test('unknown identity cannot attach to a parallel class by input order', () {
    final rows = [
      course(teacher: null),
      course(teacher: '甲'),
      course(teacher: '乙'),
    ];
    for (final order in [
      [0, 1, 2],
      [1, 0, 2],
      [2, 1, 0],
    ]) {
      final result = prepareScheduleRecognition(
        order.map((i) => rows[i]),
        source: 'photos',
      );
      expect(result.courses, hasLength(3));
      expect(result.courses.map((c) => c['teacher']).toSet(), {null, '甲', '乙'});
    }
  });

  test('numeric name suffixes do not silently merge courses or sections', () {
    final result = prepareScheduleRecognition([
      course(name: '英语（1）'),
      course(name: '英语（2）'),
      course(name: '英语-1'),
      course(name: '英语-2'),
    ], source: 'photos');
    expect(result.courses, hasLength(4));
  });

  test('portal name-section candidates match an explicitly known section', () {
    final result = prepareScheduleRecognition(
      [course(name: '英语', section: '1')],
      source: 'school-portal',
      expectedCourseNames: ['英语', '英语-1'],
    );
    expect(result.missingCourses, isEmpty);
    expect(result.extraCourses, isEmpty);
    expect(result.courses.single['name'], '英语');
    expect(result.courses.single['section'], '1');
  });

  test('candidate suffix cannot infer an unknown or different section', () {
    for (final section in [null, '2']) {
      final result = prepareScheduleRecognition(
        [course(name: '英语', section: section)],
        source: 'school-portal',
        expectedCourseNames: ['英语-1'],
      );
      expect(result.missingCourses, ['英语-1']);
      expect(result.extraCourses, ['英语']);
    }
  });

  test('unknown arrangements remain distinct and cannot borrow fields', () {
    final unknown = meeting(start: null, end: null);
    final result = prepareScheduleRecognition([
      course(
        meetings: [
          {...unknown, 'sourceReference': '上午'},
          {...unknown, 'sourceReference': '下午'},
          meeting(),
        ],
      ),
      course(meetings: []),
    ], source: 'photos');
    expect(result.courses, hasLength(2));
    final meetings = result.courses.first['meetings'] as List;
    expect(meetings, hasLength(3));
    expect(meetings.take(2).every((m) => m['startMinute'] == null), isTrue);
    expect(result.courses.last['meetings'], isEmpty);
    expect(result.courses.last['pendingReason'], '自行联系老师');
    expect(result.shouldOfferOCR, isTrue);
  });

  test(
    'candidate coverage is explicit and cannot prove screenshot completeness',
    () {
      final result = prepareScheduleRecognition(
        [course(name: '新课程')],
        source: 'school-portal',
        expectedCourseNames: ['来源课程'],
      );
      expect(result.missingCourses, ['来源课程']);
      expect(result.extraCourses, ['新课程']);
      expect(result.shouldOfferOCR, isFalse);
      final noReference = prepareScheduleRecognition([
        course(),
      ], source: 'photos');
      expect(noReference.missingCourses, isEmpty);
      expect(noReference.extraCourses, isEmpty);
      expect(noReference.shouldOfferOCR, isFalse);
    },
  );

  test('source references survive merging exact duplicates', () {
    final result = prepareScheduleRecognition([
      course(
        meetings: [
          {...meeting(), 'sourceReference': '图一'},
        ],
      ),
      course(
        meetings: [
          {...meeting(), 'sourceReference': '图二'},
        ],
      ),
    ], source: 'photos');
    final row = (result.courses.single['meetings'] as List).single;
    expect(row['sourceReference'], '图一');
    expect(row['raw']['sourceReference'], '图二');
  });

  test(
    'partial failures reject invalid fields instead of silently repairing',
    () {
      expect(
        () => prepareScheduleRecognition([
          course(meetings: [meeting(day: 9)]),
        ], source: 'photos'),
        throwsA(isA<ScheduleImportValidationException>()),
      );
    },
  );

  test('follow-up warns when a course survives but loses a meeting', () {
    final warnings = scheduleRecognitionReplacementWarnings(
      [
        course(
          meetings: [
            meeting(),
            meeting(day: 6, weeks: [5]),
          ],
        ),
      ],
      [course()],
    );
    expect(warnings.single, contains('1 条原有安排'));
    expect(
      scheduleRecognitionReplacementWarnings(
        [course()],
        [
          course(
            meetings: [
              meeting(weeks: [3]),
              meeting(weeks: [4, 6]),
            ],
          ),
        ],
      ),
      isEmpty,
    );
  });

  test('a follow-up cannot silently drop a completely pending course', () {
    final warnings = scheduleRecognitionReplacementWarnings(
      [course(name: '导师课', meetings: []), course()],
      [course()],
    );
    expect(warnings.single, contains('未保留当前课程：导师课'));
  });

  test('labeled and agreed teachers are kept, bare names are not', () {
    expect(
      ScheduleImportCourseDraft.fromJson({
        'name': '中国画',
        'teacher': null,
        'sourceLine': '中国画 教师：李四 周一',
        'meetings': [meeting()],
      }).teacher,
      '李四',
    );
    expect(
      ScheduleImportCourseDraft.fromJson({
        'name': '中国画',
        'teacher': null,
        'raw': {'sourceLine': '教师：李四'},
        'meetings': [meeting()],
      }).teacher,
      '李四',
    );
    expect(
      ScheduleImportCourseDraft.fromJson({
        'name': '中国画',
        'teacher': null,
        'meetings': [
          {...meeting(), 'teacher': '葛玉清'},
          {...meeting(day: 2), 'teacher': '葛玉清'},
        ],
      }).teacher,
      '葛玉清',
    );
    expect(
      ScheduleImportCourseDraft.fromJson({
        'name': '中国画',
        'teacher': null,
        'meetings': [
          {...meeting(), 'teacher': '葛玉清'},
          {...meeting(day: 2), 'teacher': '李老师'},
        ],
      }).teacher,
      isNull,
    );
    expect(
      ScheduleImportCourseDraft.fromJson({
        'name': '中国画',
        'teacher': null,
        'sourceLine': '中国画 葛玉清 周一',
        'meetings': [meeting()],
      }).teacher,
      isNull,
    );
    expect(
      ScheduleImportCourseDraft.fromJson({
        'name': '中国画',
        'sourceLine': '教师：张三',
        'raw': {'sourceLine': '教师：李四'},
        'meetings': [meeting()],
      }).teacher,
      isNull,
    );
    expect(
      ScheduleImportCourseDraft.fromJson({
        'name': '导师课',
        'teacher': '待定',
        'meetings': [],
        'pendingReason': '联系老师',
      }).teacher,
      isNull,
    );
    final aliases = ScheduleImportCourseDraft.fromJson({
      'name': '中国画',
      '课程代码': 'ART-01',
      '教学班': '一班',
      '教师': '葛玉清',
      '教室': '6406',
      'meetings': [
        {'weekday': 1, 'weeks': null, 'startMinute': null, 'endMinute': null},
      ],
    });
    expect(aliases.courseCode, 'ART-01');
    expect(aliases.section, '一班');
    expect(aliases.teacher, '葛玉清');
    expect(aliases.meetings.single.location, '6406');
    expect(aliases.meetings.single.weeks, isNull);
    expect(aliases.meetings.single.startMinute, isNull);
    expect(aliases.meetings.single.endMinute, isNull);
    expect(
      ScheduleImportCourseDraft.fromJson({
        'name': '中国画',
        '教室': '其他',
        'meetings': [meeting(room: '6406')],
      }).meetings.single.location,
      '6406',
    );
  });

  test('a later review keeps a seen teacher and room, not another time', () {
    final previous = [course(name: '摄影', teacher: '张老师')];
    expect(
      preserveReviewedFields(previous, [
        course(name: '摄影', teacher: null),
      ]).single['teacher'],
      '张老师',
    );
    expect(
      preserveReviewedFields(previous, [
        course(name: '摄影', teacher: '王老师'),
      ]).single['teacher'],
      '王老师',
    );
    expect(
      preserveReviewedFields(previous, [
        course(name: '英语', teacher: null),
      ]).single['teacher'],
      isNull,
    );
    expect(
      preserveReviewedFields(
        [course(teacher: '张老师', section: '一班')],
        [course(teacher: null, section: '二班')],
      ).single['teacher'],
      isNull,
    );
    final sameTime = preserveReviewedFields(
      [
        course(
          meetings: [
            meeting(weeks: [8], room: '6406'),
          ],
        ),
      ],
      [
        course(meetings: [meeting(weeks: null, room: null)]),
      ],
    );
    final sameRow = (sameTime.single['meetings'] as List).single as Map;
    expect(sameRow['location'], '6406');
    expect(sameRow['weeks'], isNull);
    final otherTime = preserveReviewedFields(
      [
        course(meetings: [meeting(room: '6406')]),
      ],
      [
        course(meetings: [meeting(room: null, start: 810, end: 990)]),
      ],
    );
    expect(
      ((otherTime.single['meetings'] as List).single as Map)['location'],
      isNull,
    );
    final unknownClock = preserveReviewedFields(
      [
        course(meetings: [meeting(room: '6406')]),
      ],
      [
        course(meetings: [meeting(room: null, start: null, end: null)]),
      ],
    );
    expect(
      ((unknownClock.single['meetings'] as List).single as Map)['location'],
      isNull,
    );
    final ambiguousRoom = preserveReviewedFields(
      [
        course(
          meetings: [
            meeting(room: '6406'),
            meeting(room: '6407'),
          ],
        ),
      ],
      [
        course(meetings: [meeting(room: null)]),
      ],
    );
    expect(
      ((ambiguousRoom.single['meetings'] as List).single as Map)['location'],
      isNull,
    );
  });
}
