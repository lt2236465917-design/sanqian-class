import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../Models/CourseModel.dart';
import '../../../Models/PersonalSchedule.dart';

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
    final axis = _TimeAxis.fromSchedule(
      schedule.periods,
      MediaQuery.textScalerOf(context).scale(1),
    );
    final placed = <_TimeCourse>[];
    for (final item in occurrences) {
      final bounds = axis.boundsFor(
        item.course.startTime ?? 0,
        item.course.timeCount ?? 0,
      );
      if (bounds != null) placed.add(_TimeCourse(item, bounds.$1, bounds.$2));
    }
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
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final blocks = _blocks(placed);
                            final dayWidth = math.max(
                              0.0,
                              (constraints.maxWidth - _timeWidth) / 7,
                            );
                            axis.fitCourseText(
                              blocks,
                              dayWidth,
                              MediaQuery.textScalerOf(context),
                            );
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: _timeWidth,
                                  height: axis.height,
                                  child: Stack(
                                    children: [
                                      for (var i = 0; i < axis.rows.length; i++)
                                        Positioned(
                                          top: axis.y(i),
                                          height: axis.rows[i].height,
                                          left: 0,
                                          right: 4,
                                          child: _periodLabel(
                                            context,
                                            axis.rows[i],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: math.max(
                                    0,
                                    constraints.maxWidth - _timeWidth,
                                  ),
                                  height: axis.height,
                                  child: Stack(
                                    clipBehavior: Clip.none,
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
                                      for (final block in blocks)
                                        Positioned(
                                          left: (block.day - 1) * dayWidth + 2,
                                          width: math.max(0, dayWidth - 4),
                                          top: axis.y(block.startRow) + 2,
                                          height: math.max(
                                            0,
                                            axis.y(block.endRow) -
                                                axis.y(block.startRow) -
                                                4,
                                          ),
                                          child: _courseBlock(context, block),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
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

  Widget _periodLabel(BuildContext context, _TimeRow row) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    if (row.isBreak) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        '${row.start}\n${row.end}',
        style: TextStyle(fontSize: 10, height: 1.15, color: color),
      ),
    );
  }

  Widget _courseBlock(BuildContext context, _CourseBlock block) {
    final item = block.courses.first.item;
    final color = colorForCourse(item);
    final multiple = block.courses.length > 1;
    final lines = [
      for (final entry in block.courses)
        (_courseName(entry.item.course), _courseRoom(entry.item.course)),
    ];
    return Semantics(
      button: true,
      label:
          '周${_weekdays[block.day - 1]}，${block.courses.map((entry) => entry.item.clockRange ?? entry.item.period).toSet().join('、')}，${lines.map((line) => '${line.$1}，${line.$2}').join('；')}',
      child: Material(
        color: Color.alphaBlend(
          color.withValues(alpha: .16),
          Theme.of(context).colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.none,
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
                          title: Text(_courseName(entry.item.course)),
                          subtitle: Text(
                            '${entry.item.clockRange ?? entry.item.period}\n${_courseRoom(entry.item.course)}',
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  Text(
                    lines[i].$1,
                    softWrap: true,
                    style: _courseNameStyle.copyWith(color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lines[i].$2,
                    softWrap: true,
                    style: _courseRoomStyle.copyWith(color: color),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _courseNameStyle = TextStyle(
  fontSize: 12,
  height: 1.25,
  fontWeight: FontWeight.w600,
);
const _courseRoomStyle = TextStyle(fontSize: 11, height: 1.25);

String _courseName(Course course) {
  final name = course.name?.trim() ?? '';
  return name.isEmpty ? '未命名课程' : name;
}

String _courseRoom(Course course) {
  final room = course.classroom?.trim() ?? '';
  return room.isEmpty ? '地点待定' : room;
}

class _TimeCourse {
  final CourseOccurrence item;
  final int startRow;
  final int endRow;
  const _TimeCourse(this.item, this.startRow, this.endRow);
}

class _TimeRow {
  final String start;
  final String end;
  double height;
  final bool isBreak;
  final int? sourcePeriod;

  _TimeRow({
    required this.start,
    required this.end,
    required this.height,
    required this.isBreak,
    this.sourcePeriod,
  });
}

class _TimeAxis {
  final List<_TimeRow> rows;
  final List<int> _sourceStarts;
  final List<int> _sourceEnds;

  const _TimeAxis(this.rows, this._sourceStarts, this._sourceEnds);

  static _TimeAxis fromSchedule(List<Map> periods, double scale) {
    final detailed = _fromPeriods(periods, scale);
    final starts = <int>[];
    final ends = <int>[];
    for (var source = 0; source < periods.length; source++) {
      final indexes = <int>[];
      for (var row = 0; row < detailed.length; row++) {
        if (detailed[row].sourcePeriod == source) indexes.add(row);
      }
      starts.add(indexes.isEmpty ? -1 : indexes.first);
      ends.add(indexes.isEmpty ? -1 : indexes.last + 1);
    }
    return _TimeAxis(detailed, starts, ends);
  }

  static List<_TimeRow> _fromPeriods(List<Map> periods, double scale) {
    final rows = <_TimeRow>[];
    for (var i = 0; i < periods.length; i++) {
      final p = periods[i];
      final start = '${p['start'] ?? ''}';
      final end = '${p['end'] ?? ''}';
      if (rows.isNotEmpty && _minutes(start) - _minutes(rows.last.end) > 5) {
        rows.add(
          _TimeRow(
            start: rows.last.end,
            end: start,
            height: 22 * scale,
            isBreak: true,
          ),
        );
      }
      rows.add(
        _TimeRow(
          start: start,
          end: end,
          height: 68 * scale,
          isBreak: false,
          sourcePeriod: i,
        ),
      );
    }
    return rows;
  }

  static int _minutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  (int, int)? boundsFor(int startPeriod, int count) {
    final source = startPeriod - 1;
    final span = count + 1;
    if (source < 0 || source >= _sourceStarts.length || span < 1) {
      return null;
    }
    final endSource = source + span - 1;
    if (endSource >= _sourceEnds.length ||
        _sourceStarts[source] < 0 ||
        _sourceEnds[endSource] < 0) {
      return null;
    }
    // One stored session keeps a single cell, including when it covers
    // several imported periods.
    return (_sourceStarts[source], _sourceEnds[endSource]);
  }

  /// Every class row uses the tallest cell, so the grid stays even.
  void fitCourseText(
    List<_CourseBlock> blocks,
    double dayWidth,
    TextScaler scaler,
  ) {
    final textWidth = math.max(8.0, dayWidth - 12);
    var uniform = 0.0;
    for (final row in rows) {
      if (!row.isBreak) uniform = math.max(uniform, row.height);
    }
    for (final block in blocks) {
      final teaching = <int>[
        for (var i = block.startRow; i < block.endRow && i < rows.length; i++)
          if (!rows[i].isBreak) i,
      ];
      if (teaching.isEmpty) continue;
      var breakHeight = 0.0;
      for (var i = block.startRow; i < block.endRow && i < rows.length; i++) {
        if (rows[i].isBreak) breakHeight += rows[i].height;
      }
      final needed = _courseTextHeight(block, textWidth, scaler) + 20;
      final perRow = math.max(0.0, (needed - breakHeight) / teaching.length);
      uniform = math.max(uniform, perRow);
    }
    for (final row in rows) {
      if (!row.isBreak) row.height = uniform;
    }
  }

  double get height => rows.fold(0, (sum, row) => sum + row.height);
  double y(int row) => rows.take(row).fold(0, (sum, item) => sum + item.height);
  Iterable<double> get offsets sync* {
    for (var row = 0; row <= rows.length; row++) {
      yield y(row);
    }
  }
}

class _CourseBlock {
  final List<_TimeCourse> courses;
  final int day;
  final int startRow;
  int endRow;

  _CourseBlock(_TimeCourse course)
    : courses = [course],
      day = course.item.date.weekday,
      startRow = course.startRow,
      endRow = course.endRow;
}

List<_CourseBlock> _blocks(List<_TimeCourse> courses) {
  final sorted = [...courses]
    ..sort((a, b) {
      final day = a.item.date.weekday.compareTo(b.item.date.weekday);
      return day == 0 ? a.startRow.compareTo(b.startRow) : day;
    });
  final result = <_CourseBlock>[];
  for (final course in sorted) {
    if (result.isNotEmpty && result.last.day == course.item.date.weekday) {
      final touches = course.startRow <= result.last.endRow;
      final overlaps = course.startRow < result.last.endRow;
      final sameSession =
          result.last.courses.length == 1 &&
          touches &&
          _sameSession(result.last.courses.first, course);
      if (sameSession) {
        result.last.endRow = math.max(result.last.endRow, course.endRow);
        continue;
      }
      if (overlaps) {
        result.last.courses.add(course);
        result.last.endRow = math.max(result.last.endRow, course.endRow);
        continue;
      }
    }
    result.add(_CourseBlock(course));
  }
  return result;
}

double _courseTextHeight(
  _CourseBlock block,
  double textWidth,
  TextScaler scaler,
) {
  var height = 0.0;
  for (var i = 0; i < block.courses.length; i++) {
    if (i > 0) height += 6;
    final course = block.courses[i].item.course;
    height += _textHeight(
      _courseName(course),
      _courseNameStyle,
      textWidth,
      scaler,
    );
    height += 2;
    height += _textHeight(
      _courseRoom(course),
      _courseRoomStyle,
      textWidth,
      scaler,
    );
  }
  return height;
}

double _textHeight(
  String text,
  TextStyle style,
  double width,
  TextScaler scaler,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: null,
  )..layout(maxWidth: math.max(1, width));
  return painter.height;
}

bool _sameSession(_TimeCourse a, _TimeCourse b) {
  if (!PersonalSchedule.sameDay(a.item.date, b.item.date)) return false;
  final left = a.item.course;
  final right = b.item.course;
  final sameId = left.courseId != null && left.courseId == right.courseId;
  final sameName =
      (left.name ?? '') == (right.name ?? '') &&
      (left.classNumber ?? '') == (right.classNumber ?? '');
  if (!sameId && !sameName) return false;
  final leftRoom = (left.classroom ?? '').trim();
  final rightRoom = (right.classroom ?? '').trim();
  return leftRoom.isEmpty || rightRoom.isEmpty || leftRoom == rightRoom;
}

class _WeekGridPainter extends CustomPainter {
  final _TimeAxis axis;
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
