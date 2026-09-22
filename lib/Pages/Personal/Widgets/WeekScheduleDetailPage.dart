import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../Models/CourseModel.dart';
import '../../../Models/PersonalSchedule.dart';
import '../../../Utils/ClassTimeUtil.dart';

class WeekScheduleDetailPage extends StatelessWidget {
  final PersonalSchedule schedule;
  final int week;
  final DateTime now;
  final Color Function(CourseOccurrence) colorForCourse;
  final ValueChanged<Course> onCourseTap;

  const WeekScheduleDetailPage({
    super.key,
    required this.schedule,
    required this.week,
    required this.now,
    required this.colorForCourse,
    required this.onCourseTap,
  });

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const _timeWidth = 46.0;
  static String _date(DateTime date) => '${date.month}/${date.day}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final occurrences = schedule.inWeek(week);
    final placed = <_PeriodCourse>[];
    final unplaced = <CourseOccurrence>[];
    for (final item in occurrences) {
      final startRow = (item.course.startTime ?? 0) - 1;
      final count = item.course.timeCount ?? 0;
      final endRow = startRow + count + 1;
      if (startRow < 0 || count < 0 || endRow > schedule.periods.length) {
        unplaced.add(item);
      } else {
        placed.add(_PeriodCourse(item, startRow, endRow));
      }
    }
    final axis = _PeriodAxis(
      schedule.periods,
      MediaQuery.textScalerOf(context).scale(1),
    );
    final today = schedule.weekAt(now) == week ? now.weekday : 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 8, 12),
                child: Row(
                  children: [
                    const Text(
                      '完整周表',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${week < 1 ? '开学前' : '第 $week 周'} · '
                        '${_date(schedule.dateFor(week, 1))} — '
                        '${_date(schedule.dateFor(week, 7))}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭完整周表',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 22),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: _timeWidth,
                      child: Text(
                        '时间',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (var day = 1; day <= 7; day++)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: day == today
                                ? colors.primaryContainer.withValues(alpha: .6)
                                : null,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          ),
                          child: Text(
                            '周${_weekdays[day - 1]}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: day == today
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    key: const ValueKey('week-detail-scroll'),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: Column(
                      children: [
                        if (occurrences.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              '这一周暂无课程',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: _timeWidth,
                              height: axis.height,
                              child: Stack(
                                children: [
                                  for (var i = 0; i < axis.periods.length; i++)
                                    Positioned(
                                      top: axis.y(i),
                                      height: axis.rowHeight,
                                      left: 0,
                                      right: 4,
                                      child: _periodLabel(
                                        context,
                                        axis.periods[i],
                                        i,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SizedBox(
                                height: axis.height,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final dayWidth = constraints.maxWidth / 7;
                                    return Stack(
                                      clipBehavior: Clip.hardEdge,
                                      children: [
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: _WeekGridPainter(
                                              axis: axis,
                                              lineColor: colors.outlineVariant
                                                  .withValues(alpha: .5),
                                              today: today,
                                              todayColor: colors.primary
                                                  .withValues(alpha: .035),
                                            ),
                                          ),
                                        ),
                                        for (final block in _blocks(placed))
                                          Positioned(
                                            left:
                                                (block.day - 1) * dayWidth + 2,
                                            width: math.max(0, dayWidth - 4),
                                            top: axis.y(block.startRow) + 2,
                                            height:
                                                axis.y(block.endRow) -
                                                axis.y(block.startRow) -
                                                4,
                                            child: _courseBlock(context, block),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (unplaced.isNotEmpty ||
                            schedule.pending.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '时间待定',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final item in unplaced)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(item.course.name ?? '未命名课程'),
                              subtitle: Text(
                                '周${_weekdays[item.date.weekday - 1]} · ${item.period}',
                              ),
                              onTap: () => onCourseTap(item.course),
                            ),
                          for (final course in schedule.pending)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(course.name ?? '未命名课程'),
                              onTap: () => onCourseTap(course),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodLabel(BuildContext context, Map period, int index) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final hasClock = ClassTimeUtil.hasClockTimes([period]);
    final rawLabel = (period['label'] as String? ?? '').trim();
    final range = hasClock ? '${period['start']}–${period['end']}' : null;
    final label = rawLabel.isEmpty
        ? '第 ${index + 1} 节'
        : rawLabel.replaceAll('—', '–').replaceAll('-', '–') == range
        ? ''
        : rawLabel;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 5),
        ],
        Text(
          hasClock ? '${period['start']}\n${period['end']}' : '时间待定',
          style: TextStyle(fontSize: 10, height: 1.5, color: color),
        ),
      ],
    );
  }

  Widget _courseBlock(BuildContext context, _CourseBlock block) {
    final item = block.courses.first.item;
    final color = colorForCourse(item);
    final multiple = block.courses.length > 1;
    final name = multiple
        ? '${block.courses.length} 门课\n${block.courses.map((c) => c.item.course.name ?? '未命名课程').join('、')}'
        : item.course.name ?? '未命名课程';
    final room = item.course.classroom?.trim() ?? '';
    final footer = multiple ? '时间重叠' : room;
    return Semantics(
      button: true,
      label:
          '周${_weekdays[block.day - 1]}，${block.courses.map((entry) => entry.item.clockRange ?? entry.item.period).toSet().join('、')}，$name${room.isEmpty ? '' : '，$room'}',
      child: Material(
        color: Color.alphaBlend(
          color.withValues(alpha: .16),
          Theme.of(context).colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (!multiple) {
              onCourseTap(item.course);
              return;
            }
            showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              builder: (sheetContext) => SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .7,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          '这个时段有多门课程',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final entry in block.courses)
                        ListTile(
                          title: Text(entry.item.course.name ?? '未命名课程'),
                          subtitle: Text(
                            '${entry.item.clockRange ?? entry.item.period}\n${entry.item.course.classroom ?? '教室待定'}',
                          ),
                          isThreeLine: true,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            onCourseTap(entry.item.course);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final showFooter =
                  footer.isNotEmpty && constraints.maxHeight >= 72 * scale;
              final lines =
                  ((constraints.maxHeight -
                              12 -
                              (showFooter ? 32 * scale : 0)) /
                          (14 * scale))
                      .floor()
                      .clamp(1, 8);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: lines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (showFooter) ...[
                      const Spacer(),
                      const SizedBox(height: 4),
                      Text(
                        footer,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.25,
                          color: color,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PeriodCourse {
  final CourseOccurrence item;
  final int startRow;
  final int endRow;
  const _PeriodCourse(this.item, this.startRow, this.endRow);
}

class _PeriodAxis {
  final List<Map> periods;
  final double rowHeight;

  _PeriodAxis(this.periods, double textScale)
    : rowHeight = (periods.length <= 4 ? 112.0 : 76.0) * textScale;

  double get height => periods.length * rowHeight;
  double y(int row) => row * rowHeight;
  Iterable<double> get offsets sync* {
    for (var row = 0; row <= periods.length; row++) {
      yield y(row);
    }
  }
}

class _CourseBlock {
  final List<_PeriodCourse> courses;
  final int day;
  final int startRow;
  int endRow;

  _CourseBlock(_PeriodCourse course)
    : courses = [course],
      day = course.item.date.weekday,
      startRow = course.startRow,
      endRow = course.endRow;
}

List<_CourseBlock> _blocks(List<_PeriodCourse> courses) {
  final sorted = [...courses]
    ..sort((a, b) {
      final day = a.item.date.weekday.compareTo(b.item.date.weekday);
      return day == 0 ? a.startRow.compareTo(b.startRow) : day;
    });
  final result = <_CourseBlock>[];
  for (final course in sorted) {
    if (result.isNotEmpty &&
        result.last.day == course.item.date.weekday &&
        course.startRow < result.last.endRow) {
      result.last.courses.add(course);
      result.last.endRow = math.max(result.last.endRow, course.endRow);
    } else {
      result.add(_CourseBlock(course));
    }
  }
  return result;
}

class _WeekGridPainter extends CustomPainter {
  final _PeriodAxis axis;
  final Color lineColor;
  final int today;
  final Color todayColor;
  const _WeekGridPainter({
    required this.axis,
    required this.lineColor,
    required this.today,
    required this.todayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dayWidth = size.width / 7;
    if (today > 0) {
      canvas.drawRect(
        Rect.fromLTWH((today - 1) * dayWidth, 0, dayWidth, size.height),
        Paint()..color = todayColor,
      );
    }
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = .6;
    for (var day = 0; day <= 7; day++) {
      canvas.drawLine(
        Offset(day * dayWidth, 0),
        Offset(day * dayWidth, size.height),
        paint,
      );
    }
    for (final y in axis.offsets) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeekGridPainter oldDelegate) =>
      oldDelegate.axis != axis ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.today != today ||
      oldDelegate.todayColor != todayColor;
}
