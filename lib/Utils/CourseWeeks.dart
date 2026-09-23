import 'dart:convert';

import '../Resources/Config.dart';

/// Sorted, unique week numbers that can be shown or saved.
/// Null, blank, invalid JSON, non-numeric values and out-of-range weeks
/// become an empty list so callers can show “周次待定” without throwing.
class CourseWeeks {
  static List<int> parse(String? raw) {
    if (raw == null) return const [];
    final text = raw.trim();
    if (text.isEmpty) return const [];
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    final weeks = <int>{};
    for (final item in decoded) {
      final week = _week(item);
      if (week == null || week < 1 || week > Config.MAX_WEEKS) continue;
      weeks.add(week);
    }
    return weeks.toList()..sort();
  }

  /// First week that can be stored, or null when the course is still unscheduled.
  static int? firstAddable(String? raw) {
    final weeks = parse(raw);
    if (weeks.isEmpty) return null;
    return weeks.first;
  }

  static int? _week(dynamic item) {
    if (item is int) return item;
    if (item is num) {
      if (item % 1 != 0) return null;
      return item.toInt();
    }
    if (item is String) return int.tryParse(item.trim());
    return null;
  }
}
