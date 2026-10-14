import 'dart:convert';

import '../Models/CourseModel.dart';
import 'ScheduleImportService.dart';

/// Fields the day, week, and month detail can show.
///
/// A column value of null means the import never wrote it, so the original
/// recognition stored beside the row can still supply it. An empty string is a
/// value the user cleared and is left empty.
class SavedCourseFacts {
  final String? teacher;
  final String? classroom;
  final String? courseCode;
  final String? section;

  const SavedCourseFacts({
    this.teacher,
    this.classroom,
    this.courseCode,
    this.section,
  });

  factory SavedCourseFacts.fromCourse(Course course) {
    final original = _originalCourse(course);
    final meetings = original['meetings'];
    final rooms = meetings is List
        ? meetings
              .whereType<Map>()
              .map((meeting) => _text(meeting['location']))
              .whereType<String>()
              .toSet()
        : <String>{};
    return SavedCourseFacts(
      teacher: _writtenOrRecovered(course.teacher, _text(original['teacher'])),
      classroom: _writtenOrRecovered(
        course.classroom,
        rooms.length == 1 ? rooms.single : null,
      ),
      courseCode: _writtenOrRecovered(
        course.classNumber,
        _text(original['courseCode']),
      ),
      section: _text(original['section']),
    );
  }

  String get teacherLabel =>
      (teacher ?? '').trim().isEmpty ? '教师待定' : teacher!.trim();

  String get classroomLabel =>
      (classroom ?? '').trim().isEmpty ? '地点待定' : classroom!.trim();
}

Map<String, dynamic> _originalCourse(Course course) {
  try {
    final data = jsonDecode(course.data ?? '{}');
    if (data is! Map) return {};
    final metadata = data[ScheduleImportService.rowMetadataKey];
    if (metadata is! Map) return {};
    final original = metadata['original_course'];
    if (original is Map) return Map<String, dynamic>.from(original);
  } on FormatException {
    return {};
  }
  return {};
}

String? _writtenOrRecovered(String? column, String? recovered) {
  if (column == null) return recovered;
  final written = column.trim();
  return written.isEmpty ? null : written;
}

String? _text(dynamic value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}
