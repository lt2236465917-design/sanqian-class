import 'dart:convert';

/// A single occurrence extracted from a portal, image or AI response.
///
/// `weeks == null` means that the source did not provide weeks.  An empty
/// list is retained as an explicitly empty/undated value.  The importer never
/// turns either value into "every week".
class ScheduleImportMeetingDraft {
  final int? weekday;
  final List<int>? weeks;
  final int? periodIndex;
  final int? periodCount;
  final int? startMinute;
  final int? endMinute;
  final String? location;
  final String? sourceReference;
  final Map<String, dynamic> raw;

  ScheduleImportMeetingDraft({
    this.weekday,
    List<int>? weeks,
    this.periodIndex,
    this.periodCount,
    this.startMinute,
    this.endMinute,
    this.location,
    this.sourceReference,
    Map<String, dynamic>? raw,
  }) : weeks = weeks == null ? null : List.unmodifiable(weeks),
       raw = Map.unmodifiable(raw ?? const {});

  bool get isPending =>
      weekday == null ||
      (weeks == null || weeks!.isEmpty) ||
      (periodIndex == null && (startMinute == null || endMinute == null));

  List<String> validate([String path = 'meeting']) {
    final errors = <String>[];
    if (weekday != null && (weekday! < 1 || weekday! > 7)) {
      errors.add('$path.weekday must be between 1 and 7');
    }
    if (weeks != null) {
      final invalid = weeks!.where((week) => week < 1 || week > 60);
      if (invalid.isNotEmpty) {
        errors.add('$path.weeks contains an invalid week');
      }
      if (weeks!.toSet().length != weeks!.length) {
        errors.add('$path.weeks contains duplicates');
      }
    }
    if (periodIndex != null && periodIndex! < 1) {
      errors.add('$path.periodIndex must be at least 1');
    }
    if (periodCount != null && periodCount! < 0) {
      errors.add('$path.periodCount must be non-negative');
    }
    if (startMinute != null && (startMinute! < 0 || startMinute! >= 24 * 60)) {
      errors.add('$path.startMinute must be between 0 and 1439');
    }
    if (endMinute != null && (endMinute! < 0 || endMinute! >= 24 * 60)) {
      errors.add('$path.endMinute must be between 0 and 1439');
    }
    if (startMinute != null &&
        endMinute != null &&
        endMinute! <= startMinute!) {
      errors.add('$path.endMinute must be after startMinute');
    }
    if ((startMinute != null) != (endMinute != null)) {
      errors.add('$path must provide both startMinute and endMinute');
    }
    return errors;
  }

  /// Content equality only, never a stable meeting ID. A room/time change
  /// is reviewed as a removal and addition, not matched by list position.
  String get meetingKey => jsonEncode([
    weekday,
    weeks == null ? null : (List<int>.from(weeks!)..sort()),
    periodIndex,
    periodCount,
    startMinute,
    endMinute,
    _normalise(location),
  ]);

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'weeks': weeks,
    'periodIndex': periodIndex,
    'periodCount': periodCount,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'location': location,
    'sourceReference': sourceReference,
    'raw': raw,
  };

  factory ScheduleImportMeetingDraft.fromJson(Map<String, dynamic> json) =>
      ScheduleImportMeetingDraft(
        weekday: _asInt(json['weekday']),
        weeks: _asIntList(json['weeks']),
        periodIndex: _asInt(json['periodIndex']),
        periodCount: _asInt(json['periodCount']),
        startMinute: _asInt(json['startMinute']),
        endMinute: _asInt(json['endMinute']),
        location: _asString(json['location']),
        sourceReference: _asString(json['sourceReference']),
        raw: _asMap(json['raw']),
      );
}

class ScheduleImportCourseDraft {
  final String? stableId;
  final String? courseCode;
  final String name;
  final String? section;
  final String? teacher;
  final List<ScheduleImportMeetingDraft> meetings;
  final String? pendingReason;
  final Map<String, dynamic> raw;

  ScheduleImportCourseDraft({
    this.stableId,
    this.courseCode,
    required this.name,
    this.section,
    this.teacher,
    List<ScheduleImportMeetingDraft>? meetings,
    this.pendingReason,
    Map<String, dynamic>? raw,
  }) : meetings = List.unmodifiable(meetings ?? const []),
       raw = Map.unmodifiable(raw ?? const {});

  String get identity {
    final explicit = _normalise(stableId);
    if (explicit.isNotEmpty) return 'stable:$explicit';
    final code = _normalise(courseCode);
    final sectionValue = _normalise(section);
    if (code.isNotEmpty && sectionValue.isNotEmpty) {
      return 'code:$code|section:$sectionValue';
    }
    if (code.isNotEmpty) return 'code:$code';
    // A content candidate is only an exact-match key, never a stable ID.
    final keys = meetings.map((m) => m.meetingKey).toList()..sort();
    return 'candidate:${jsonEncode([name.trim(), section, teacher, pendingReason, keys])}';
  }

  bool get hasStableIdentity =>
      (stableId ?? '').trim().isNotEmpty ||
      (courseCode ?? '').trim().isNotEmpty;

  bool get isPending =>
      meetings.isEmpty || meetings.any((meeting) => meeting.isPending);

  List<String> validate([String path = 'course']) {
    final errors = <String>[];
    if (name.trim().isEmpty) errors.add('$path.name is required');
    if (meetings.isEmpty && (pendingReason ?? '').trim().isEmpty) {
      errors.add('$path.pendingReason is required when meetings are empty');
    }
    for (var i = 0; i < meetings.length; i++) {
      errors.addAll(meetings[i].validate('$path.meetings[$i]'));
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
    'stableId': stableId,
    'courseCode': courseCode,
    'name': name,
    'section': section,
    'teacher': teacher,
    'meetings': meetings.map((meeting) => meeting.toJson()).toList(),
    'pendingReason': pendingReason,
    'raw': raw,
  };

  factory ScheduleImportCourseDraft.fromJson(Map<String, dynamic> json) =>
      ScheduleImportCourseDraft(
        stableId: _asString(json['stableId']),
        courseCode: _asString(json['courseCode']),
        name: _asString(json['name']) ?? '',
        section: _asString(json['section']),
        teacher: _asString(json['teacher']),
        meetings: (json['meetings'] as List? ?? const [])
            .map(
              (meeting) => ScheduleImportMeetingDraft.fromJson(
                Map<String, dynamic>.from(meeting as Map),
              ),
            )
            .toList(),
        pendingReason: _asString(json['pendingReason']),
        raw: _asMap(json['raw']),
      );
}

class ScheduleImportDraft {
  final String source;
  final String sourceId;
  final String? accountLocalId;
  final String school;
  final String term;
  final DateTime? firstWeekMonday;
  final List<ScheduleImportCourseDraft> courses;
  final Map<String, dynamic> sourceMetadata;

  ScheduleImportDraft({
    required this.source,
    required this.sourceId,
    this.accountLocalId,
    required this.school,
    required this.term,
    required this.firstWeekMonday,
    required List<ScheduleImportCourseDraft> courses,
    Map<String, dynamic>? sourceMetadata,
  }) : courses = List.unmodifiable(courses),
       sourceMetadata = Map.unmodifiable(sourceMetadata ?? const {});

  String get sourceKey =>
      jsonEncode([source, sourceId, accountLocalId, school, term]);

  List<String> validate() {
    final errors = <String>[];
    if (source.trim().isEmpty) errors.add('source is required');
    if (sourceId.trim().isEmpty) errors.add('sourceId is required');
    if (school.trim().isEmpty) errors.add('school is required');
    if (term.trim().isEmpty) errors.add('term is required');
    if (firstWeekMonday != null &&
        firstWeekMonday!.weekday != DateTime.monday) {
      errors.add('firstWeekMonday must be a Monday');
    }
    if (courses.isEmpty) errors.add('courses must not be empty');
    for (var i = 0; i < courses.length; i++) {
      errors.addAll(courses[i].validate('courses[$i]'));
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
    'source': source,
    'sourceId': sourceId,
    'accountLocalId': accountLocalId,
    'school': school,
    'term': term,
    'firstWeekMonday': firstWeekMonday?.toIso8601String(),
    'courses': courses.map((c) => c.toJson()).toList(),
    'sourceMetadata': sourceMetadata,
  };

  factory ScheduleImportDraft.fromJson(Map<String, dynamic> json) {
    final rawCourses = json['courses'];
    if (rawCourses is! List || rawCourses.any((c) => c is! Map)) {
      throw const FormatException('courses must be an array of objects');
    }
    return ScheduleImportDraft(
      source: _asString(json['source']) ?? '',
      sourceId: _asString(json['sourceId']) ?? '',
      accountLocalId: _asString(json['accountLocalId']),
      school: _asString(json['school']) ?? '',
      term: _asString(json['term']) ?? '',
      firstWeekMonday: json['firstWeekMonday'] == null
          ? null
          : DateTime.parse(json['firstWeekMonday'] as String),
      courses: rawCourses
          .map(
            (c) => ScheduleImportCourseDraft.fromJson(
              Map<String, dynamic>.from(c as Map),
            ),
          )
          .toList(),
      sourceMetadata: _asMap(json['sourceMetadata']),
    );
  }

  void requireValid() {
    final errors = validate();
    if (errors.isNotEmpty) throw ScheduleImportValidationException(errors);
  }

  /// Dedupe repeated parser output while preserving distinct weeks, times and
  /// rooms. Scalar fields use the first non-empty value; the raw payload from
  /// every duplicate is retained under the first draft's raw map.
  ScheduleImportDraft normalised() {
    final byIdentity = <String, ScheduleImportCourseDraft>{};
    for (final course in courses) {
      final old = byIdentity[course.identity];
      if (old != null &&
          [
            [old.name, course.name],
            [old.teacher, course.teacher],
            [old.section, course.section],
            [old.courseCode, course.courseCode],
          ].any(
            (pair) =>
                _normalise(pair[0]).isNotEmpty &&
                _normalise(pair[1]).isNotEmpty &&
                _normalise(pair[0]) != _normalise(pair[1]),
          )) {
        throw ScheduleImportValidationException([
          'ambiguous identity: ${course.identity}',
        ]);
      }
      byIdentity[course.identity] = old == null
          ? course
          : _mergeCourse(old, course);
    }
    return ScheduleImportDraft(
      source: source,
      sourceId: sourceId,
      accountLocalId: accountLocalId,
      school: school,
      term: term,
      firstWeekMonday: firstWeekMonday,
      courses: byIdentity.values.toList(),
      sourceMetadata: sourceMetadata,
    );
  }
}

class ScheduleImportValidationException implements Exception {
  final List<String> errors;
  ScheduleImportValidationException(Iterable<String> errors)
    : errors = List.unmodifiable(errors);

  @override
  String toString() =>
      'ScheduleImportValidationException: ${errors.join('; ')}';
}

/// Deterministic preparation of model output before the user reviews it.
/// Source names are candidates, not an authoritative or exhaustive answer.
class ScheduleRecognitionPreparation {
  final List<Map<String, dynamic>> courses;
  final List<String> warnings;
  final List<String> missingCourses;
  final List<String> extraCourses;
  final bool hasStructuralAnomaly;
  final bool shouldOfferOCR;

  const ScheduleRecognitionPreparation({
    required this.courses,
    this.warnings = const [],
    this.missingCourses = const [],
    this.extraCourses = const [],
    this.hasStructuralAnomaly = false,
    this.shouldOfferOCR = false,
  });
}

ScheduleRecognitionPreparation prepareScheduleRecognition(
  Iterable<Map<String, dynamic>> rawCourses, {
  required String source,
  Iterable<String> expectedCourseNames = const [],
}) {
  final parsed = rawCourses.map(ScheduleImportCourseDraft.fromJson).toList();
  for (final course in parsed) {
    final errors = course.validate();
    if (errors.isNotEmpty) throw ScheduleImportValidationException(errors);
  }
  final groups = <ScheduleImportCourseDraft>[];
  for (final incoming in parsed) {
    // Consider the entire response, so an unknown teacher appearing first
    // cannot be assigned to one of two parallel classes by input order.
    final index = groups.indexWhere((existing) {
      if (!_recognitionCompatible(existing, incoming)) return false;
      if (_recognitionIdentity(existing) == _recognitionIdentity(incoming)) {
        return true;
      }
      return !parsed.any(
        (other) =>
            (_recognitionCompatible(other, incoming) &&
                !_recognitionCompatible(other, existing)) ||
            (_recognitionCompatible(other, existing) &&
                !_recognitionCompatible(other, incoming)),
      );
    });
    if (index < 0) {
      groups.add(incoming);
    } else {
      groups[index] = _mergeRecognitionCourses(groups[index], incoming);
    }
  }
  // meetingKey includes every schedule field, including null and empty weeks.
  // Never treat an unknown field as a wildcard or fill it from another row.
  final canonical = groups
      .map(
        (course) => _mergeRecognitionCourses(
          course,
          ScheduleImportCourseDraft(name: course.name),
        ),
      )
      .toList();
  final warnings = <String>[];
  final merged = parsed.length - canonical.length;
  final removed =
      parsed.fold<int>(0, (n, c) => n + c.meetings.length) -
      canonical.fold<int>(0, (n, c) => n + c.meetings.length);
  if (merged > 0) {
    warnings.add('已合并 $merged 项重复课程；请核对合并后的课程和安排。');
  }
  if (removed > 0) {
    warnings.add('已去除 $removed 条完全重复的上课安排；不同周次、时段和地点仍保留。');
  }
  final names = <String, List<ScheduleImportCourseDraft>>{};
  for (final course in canonical) {
    names.putIfAbsent(_recognitionName(course.name), () => []).add(course);
  }
  final ambiguous = names.values
      .where((rows) => rows.length > 1)
      .map((rows) => rows.first.name)
      .toList();
  if (ambiguous.isNotEmpty) {
    warnings.add(
      '同名课程的身份或待定安排有歧义，已分别保留：${ambiguous.join('、')}。请核对教师、教学班和课程编码。',
    );
  }
  final expected = <String, String>{
    for (final name in expectedCourseNames)
      if (name.trim().isNotEmpty) _recognitionName(name): name.trim(),
  };
  final actual = <String, String>{
    for (final course in canonical) _recognitionName(course.name): course.name,
  };
  final missing = expected.keys
      .where((key) => !actual.containsKey(key))
      .map((key) => expected[key]!)
      .toList();
  // An absent local candidate list means coverage is unknown, not that all
  // model courses are extra. Unparsed webpage rows can legitimately add names.
  final extra = expected.isEmpty
      ? <String>[]
      : actual.keys
            .where((key) => !expected.containsKey(key))
            .map((key) => actual[key]!)
            .toList();
  if (missing.isNotEmpty) {
    warnings.add('来源候选中有课程未出现在识别结果中：${missing.join('、')}。请对照原课表检查是否漏课。');
  }
  if (extra.isNotEmpty) {
    warnings.add('以下课程未出现在来源候选中：${extra.join('、')}。候选可能不完整，请核对是否为额外课程。');
  }
  final pending = canonical.where((course) => course.isPending).length;
  if (pending > 0) {
    warnings.add('有 $pending 门课程包含待定安排，缺失信息未自动补全，请核对。');
  }
  final anomaly =
      merged > 0 ||
      removed > 0 ||
      ambiguous.isNotEmpty ||
      missing.isNotEmpty ||
      extra.isNotEmpty ||
      pending > 0;
  return ScheduleRecognitionPreparation(
    courses: canonical.map((course) => course.toJson()).toList(),
    warnings: List.unmodifiable(warnings),
    missingCourses: List.unmodifiable(missing),
    extraCourses: List.unmodifiable(extra),
    hasStructuralAnomaly: anomaly,
    shouldOfferOCR: source == 'photos' && anomaly,
  );
}

ScheduleImportCourseDraft _mergeRecognitionCourses(
  ScheduleImportCourseDraft first,
  ScheduleImportCourseDraft second,
) {
  final meetings = <String, ScheduleImportMeetingDraft>{};
  for (final meeting in [...first.meetings, ...second.meetings]) {
    // Two unknown times may be different morning/afternoon occurrences.
    // They are not proven duplicates even when all known fields match.
    final key = meeting.isPending
        ? '${meeting.meetingKey}:pending:${meetings.length}'
        : meeting.meetingKey;
    final old = meetings[key];
    meetings[key] = old == null
        ? meeting
        : ScheduleImportMeetingDraft(
            weekday: old.weekday,
            weeks: old.weeks,
            periodIndex: old.periodIndex,
            periodCount: old.periodCount,
            startMinute: old.startMinute,
            endMinute: old.endMinute,
            location: old.location,
            sourceReference: old.sourceReference ?? meeting.sourceReference,
            raw: _mergeRaw(old.raw, {
              ...meeting.raw,
              if (meeting.sourceReference != null)
                'sourceReference': meeting.sourceReference,
            }),
          );
  }
  return ScheduleImportCourseDraft(
    name: first.name.trim(),
    stableId: _firstNonEmpty(first.stableId, second.stableId),
    courseCode: _firstNonEmpty(first.courseCode, second.courseCode),
    section: _firstNonEmpty(first.section, second.section),
    teacher: _firstNonEmpty(first.teacher, second.teacher),
    pendingReason: _firstNonEmpty(first.pendingReason, second.pendingReason),
    meetings: meetings.values.toList(),
    raw: _mergeRaw(first.raw, second.raw),
  );
}

// Comparing a follow-up with the current review is not a truth check. It
// makes losses visible before replacement, including lost meetings of a
// course whose name remains present. Expand weeks so regrouping is harmless.
List<String> scheduleRecognitionReplacementWarnings(
  Iterable<Map<String, dynamic>> previous,
  Iterable<Map<String, dynamic>> replacement,
) {
  Set<String> occurrences(Iterable<Map<String, dynamic>> courses) => {
    for (final json in courses)
      for (final meeting in ScheduleImportCourseDraft.fromJson(json).meetings)
        for (final week
            in (meeting.weeks?.isNotEmpty ?? false)
                ? meeting.weeks!.cast<int?>()
                : <int?>[null])
          jsonEncode([
            _recognitionName(json['name'] as String),
            week,
            meeting.weekday,
            meeting.periodIndex,
            meeting.periodCount,
            meeting.startMinute,
            meeting.endMinute,
            _normalise(meeting.location),
          ]),
  };
  final before = occurrences(previous);
  final after = occurrences(replacement);
  final lost = before.difference(after).length;
  final replacementNames = replacement
      .map((course) => _recognitionName(course['name'] as String))
      .toSet();
  final missingNames = previous
      .where(
        (course) => !replacementNames.contains(
          _recognitionName(course['name'] as String),
        ),
      )
      .map((course) => course['name'] as String)
      .toSet();
  return [
    if (missingNames.isNotEmpty)
      '复核结果未保留当前课程：${missingNames.join('、')}。请对照原课表检查，包括完全待定的课程。',
    if (lost > 0) '复核结果有 $lost 条原有安排未保留或字段发生变化（按周展开）；请检查漏课、周次、时间和地点后再决定是否采用。',
  ];
}

String _recognitionName(String value) => _recognitionField(value);
String _recognitionField(String? value) =>
    _normalise(value).replaceAll(RegExp(r'\s+'), '').replaceAll('，', ',');

List<String> _recognitionFields(ScheduleImportCourseDraft course) => [
  _recognitionField(course.stableId),
  _recognitionField(course.courseCode),
  _recognitionField(course.section),
  _recognitionField(course.teacher),
];

String _recognitionIdentity(ScheduleImportCourseDraft course) => jsonEncode([
  _recognitionName(course.name),
  ..._recognitionFields(course),
  course.meetings.isEmpty,
]);

bool _recognitionCompatible(
  ScheduleImportCourseDraft first,
  ScheduleImportCourseDraft second,
) {
  if (_recognitionName(first.name) != _recognitionName(second.name) ||
      first.meetings.isEmpty != second.meetings.isEmpty) {
    return false;
  }
  final left = _recognitionFields(first);
  final right = _recognitionFields(second);
  for (var i = 0; i < left.length; i++) {
    if (left[i].isNotEmpty && right[i].isNotEmpty && left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

String _normalise(String? value) => (value ?? '').trim().toLowerCase();
String? _asString(dynamic value) => value?.toString();
int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  throw const FormatException('Expected an integer or null');
}

List<int>? _asIntList(dynamic value) {
  if (value == null) return null;
  if (value is! List || value.any((item) => item is! int)) {
    throw const FormatException('Expected an integer array or null');
  }
  return List<int>.from(value);
}

Map<String, dynamic> _asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

ScheduleImportCourseDraft _mergeCourse(
  ScheduleImportCourseDraft first,
  ScheduleImportCourseDraft second,
) {
  final meetings = <String, ScheduleImportMeetingDraft>{};
  for (final meeting in [...first.meetings, ...second.meetings]) {
    final old = meetings[meeting.meetingKey];
    if (old == null) {
      meetings[meeting.meetingKey] = meeting;
    } else {
      final weeks = <int>{
        ...(old.weeks ?? const []),
        ...(meeting.weeks ?? const []),
      };
      meetings[meeting.meetingKey] = ScheduleImportMeetingDraft(
        weekday: old.weekday ?? meeting.weekday,
        weeks: old.weeks == null && meeting.weeks == null
            ? null
            : (weeks.toList()..sort()),
        periodIndex: old.periodIndex ?? meeting.periodIndex,
        periodCount: old.periodCount ?? meeting.periodCount,
        startMinute: old.startMinute ?? meeting.startMinute,
        endMinute: old.endMinute ?? meeting.endMinute,
        location: _firstNonEmpty(old.location, meeting.location),
        sourceReference: _firstNonEmpty(
          old.sourceReference,
          meeting.sourceReference,
        ),
        raw: _mergeRaw(old.raw, meeting.raw),
      );
    }
  }
  return ScheduleImportCourseDraft(
    stableId: _firstNonEmpty(first.stableId, second.stableId),
    courseCode: _firstNonEmpty(first.courseCode, second.courseCode),
    name: first.name.trim().isEmpty ? second.name : first.name,
    section: _firstNonEmpty(first.section, second.section),
    teacher: _firstNonEmpty(first.teacher, second.teacher),
    meetings: meetings.values.toList(),
    pendingReason: _firstNonEmpty(first.pendingReason, second.pendingReason),
    raw: _mergeRaw(first.raw, second.raw),
  );
}

String? _firstNonEmpty(String? first, String? second) {
  if (first != null && first.trim().isNotEmpty) return first;
  if (second != null && second.trim().isNotEmpty) return second;
  return first ?? second;
}

// Preserve all image/token evidence when identical courses appear in several
// images. Other raw fields retain both conflicting values under alternatives.
Map<String, dynamic> _mergeRaw(
  Map<String, dynamic> first,
  Map<String, dynamic> second,
) {
  final result = <String, dynamic>{...first};
  final alternatives = <String, dynamic>{};
  for (final entry in second.entries) {
    final old = result[entry.key];
    if (old is List && entry.value is List) {
      final values = <String, dynamic>{};
      for (final item in [...old, ...entry.value as List]) {
        values[jsonEncode(item)] = item;
      }
      result[entry.key] = values.values.toList();
    } else {
      if (old != null && jsonEncode(old) != jsonEncode(entry.value)) {
        alternatives[entry.key] = [old, entry.value];
      } else {
        result[entry.key] = entry.value;
      }
    }
  }
  if (alternatives.isNotEmpty) result['mergeAlternatives'] = alternatives;
  return result;
}
