import '../Resources/Config.dart';
import '../Resources/Constant.dart';

/// UI indices are zero-based; stored teaching weeks are one-based and inclusive.
class CourseWeekSelection {
  static List<int> weeks(Map node) {
    final start = (node['startWeek'] as int) + 1;
    final end = (node['endWeek'] as int) + 1;
    final type = node['weekType'] as int;
    if (type == Constant.DEFINED_WEEKS) {
      final defined = (node['definedWeeks'] as List? ?? [])
          .whereType<num>()
          .map((week) => week.toInt())
          .where((week) => week >= 1 && week <= Config.MAX_WEEKS)
          .toSet()
          .toList()
        ..sort();
      return defined;
    }
    if (start < 1 || end > Config.MAX_WEEKS || start > end) return [];
    return [
      for (var week = start; week <= end; week++)
        if (type == Constant.FULL_WEEKS ||
            (type == Constant.SINGLE_WEEKS && week.isOdd) ||
            (type == Constant.DOUBLE_WEEKS && week.isEven))
          week,
    ];
  }

  static String summary(Map node) {
    final selected = weeks(node);
    if (selected.isEmpty) return '请选择至少一周上课。';
    if (selected.length == 1) return '第 ${selected.single} 周';
    if (node['weekType'] == Constant.FULL_WEEKS) {
      return '第 ${selected.first}–${selected.last} 周 · 共 ${selected.length} 周';
    }
    return '第 ${selected.join('、')} 周 · 共 ${selected.length} 周';
  }
}
