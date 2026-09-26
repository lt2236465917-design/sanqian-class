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

  /// Maps a free clock range onto the timetable periods it overlaps.
  /// Indices are zero-based. A gap still keeps the nearest period so the
  /// course remains visible on the existing period grid.
  static ({int start, int end})? periodSpan(
    List<Map> periods,
    int startMinute,
    int endMinute,
  ) {
    if (!hasClockTimes(periods) || endMinute <= startMinute) return null;
    int minute(String value) {
      final parts = value.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final spans = [
      for (var i = 0; i < periods.length; i++)
        (
          index: i,
          start: minute(periods[i]['start'] as String),
          end: minute(periods[i]['end'] as String),
        ),
    ];
    final overlapping = spans
        .where((period) => startMinute < period.end && endMinute > period.start)
        .toList();
    if (overlapping.isEmpty) {
      final nearest = spans.reduce(
        (best, period) => (period.start - startMinute).abs() <
                (best.start - startMinute).abs()
            ? period
            : best,
      );
      return (start: nearest.index, end: nearest.index);
    }
    return (start: overlapping.first.index, end: overlapping.last.index);
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
