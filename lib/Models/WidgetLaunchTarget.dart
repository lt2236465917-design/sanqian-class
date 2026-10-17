/// Only accepts our widget route and identifiers from a schedule snapshot.
class WidgetLaunchTarget {
  final DateTime? date;
  final String? occurrence;
  final int? tableId;
  final int? courseId;

  const WidgetLaunchTarget(
    this.date,
    this.occurrence,
    this.tableId,
    this.courseId,
  );

  static WidgetLaunchTarget? parse(Object? raw) {
    if (raw is! String) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'ncs' || uri.host != 'schedule') {
      return null;
    }
    final milliseconds = int.tryParse(uri.queryParameters['date'] ?? '');
    DateTime? date;
    // Keep malformed external links out of DateTime and the calendar UI.
    if (milliseconds != null &&
        milliseconds >= 946684800000 &&
        milliseconds < 4133980800000) {
      final shanghai = DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ).add(const Duration(hours: 8));
      date = DateTime(shanghai.year, shanghai.month, shanghai.day);
    }
    final occurrence = uri.queryParameters['occurrence'];
    final parts = occurrence?.split('.') ?? const <String>[];
    final table = parts.length == 3 ? int.tryParse(parts[0]) : null;
    final course = parts.length == 3 ? int.tryParse(parts[1]) : null;
    final week = parts.length == 3 ? int.tryParse(parts[2]) : null;
    final valid =
        table != null &&
        table >= 0 &&
        course != null &&
        course > 0 &&
        week != null &&
        week > 0;
    return WidgetLaunchTarget(
      date,
      valid ? occurrence : null,
      valid ? table : null,
      valid ? course : null,
    );
  }
}
