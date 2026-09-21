import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/Models/ScheduleImportDraft.dart';

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
}
