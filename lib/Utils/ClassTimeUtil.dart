class ClassTimeUtil {
  static final _clock = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');

  static bool hasClockTimes(List<Map> periods) {
    return periods.isNotEmpty &&
        periods.every(
          (p) =>
              _clock.hasMatch((p['start'] ?? '').toString()) &&
              _clock.hasMatch((p['end'] ?? '').toString()) &&
              (p['start'] as String).compareTo(p['end'] as String) < 0,
        );
  }

  static String? clockRange(List<Map> periods, int start, int count) {
    final end = start + count;
    if (start < 1 || count < 0 || end > periods.length) return null;
    final range = periods.sublist(start - 1, end);
    if (!hasClockTimes(range)) return null;
    return '${range.first['start']}–${range.last['end']}';
  }

  static String? rangeLabel(List<Map> periods, int start, int count) {
    final end = start + count;
    if (start < 1 || count < 0 || end > periods.length) return null;
    final first = periods[start - 1]['label'] as String?;
    final last = periods[end - 1]['label'] as String?;
    if (first == null || last == null) return null;
    return first == last ? first : '$first–$last';
  }
}
