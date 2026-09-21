import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../Models/CourseModel.dart';
import '../../Models/PersonalSchedule.dart';
import '../../Models/ScreenshotSchedule.dart';
import '../../Utils/ClassTimeUtil.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../Import/PhotoScheduleImportView.dart';
import '../Settings/SettingsView.dart';
import 'Widgets/FloatingScheduleNavigation.dart';

enum _ScheduleTab { today, week, month }

class PersonalHomeView extends StatefulWidget {
  final Future<PersonalSchedule> Function()? loader;
  final DateTime Function()? clock;
  const PersonalHomeView({super.key, this.loader, this.clock});

  @override
  State<PersonalHomeView> createState() => _PersonalHomeViewState();
}

class _PersonalHomeViewState extends State<PersonalHomeView>
    with WidgetsBindingObserver {
  PersonalSchedule? _schedule;
  Object? _error;
  late DateTime _now;
  late DateTime _weekDay;
  late DateTime _monthDay;
  _ScheduleTab _tab = _ScheduleTab.today;
  Timer? _timer;
  final _scrolls = List.generate(3, (_) => ScrollController());
  int _request = 0;

  DateTime get _clock => (widget.clock ?? DateTime.now)();
  ColorScheme get _colors => Theme.of(context).colorScheme;
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  String _date(DateTime date) => '${date.month}月${date.day}日';
  String _shortDate(DateTime date) => '${date.month}/${date.day}';

  @override
  void initState() {
    super.initState();
    _now = _clock;
    _weekDay = _monthDay = PersonalSchedule.day(_now);
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FlutterNativeSplash.remove(),
    );
  }

  void _tick() {
    final now = _clock;
    if (!mounted) return;
    setState(() {
      if (!PersonalSchedule.sameDay(now, _now)) {
        final schedule = _schedule;
        if (schedule != null &&
            schedule.weekAt(_weekDay) == schedule.weekAt(_now)) {
          _weekDay = PersonalSchedule.day(now);
        }
        if (PersonalSchedule.sameDay(_monthDay, _now)) {
          _monthDay = PersonalSchedule.day(now);
        }
      }
      _now = now;
    });
  }

  Future<void> _load({bool today = false}) async {
    final request = ++_request;
    try {
      final data = await (widget.loader ?? loadPersonalSchedule)();
      if (!mounted || request != _request) return;
      setState(() {
        if (today ||
            (_schedule != null && _schedule!.tableId != data.tableId)) {
          _weekDay = _monthDay = PersonalSchedule.day(_clock);
        }
        _schedule = data;
        _now = _clock;
        _error = null;
      });
      if (widget.loader == null) {
        unawaited(ScheduleDerivedDataService.sync(data).catchError((Object error) => <String,dynamic>{'error': '$error'}));
      }
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        extendBody: true,
        bottomNavigationBar: FloatingScheduleNavigation(
          selectedIndex: _tab.index,
          onSelected: (index) =>
              setState(() => _tab = _ScheduleTab.values[index]),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _header(schedule),
              Expanded(child: _body(schedule)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(PersonalSchedule? schedule) {
    final title = switch (_tab) {
      _ScheduleTab.today => '日课表',
      _ScheduleTab.week => '周课表',
      _ScheduleTab.month => '月课表',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 18, 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _colors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _tab == _ScheduleTab.today
                      ? '${_date(_now)} · 星期${_weekdays[_now.weekday - 1]}'
                      : schedule?.name ?? '三千上课',
                  style: TextStyle(
                    fontSize: 12,
                    color: _colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => _open(const SettingsView()),
            icon: const Icon(Icons.settings_outlined),
            color: _colors.onSurface,
          ),
        ],
      ),
    );
  }

  Widget _body(PersonalSchedule? schedule) {
    if (_error != null) {
      return _page(_tab, [
        _empty('课表暂时未能读取', '再试一次，已保存的课程不会丢失。', Icons.refresh_rounded),
        TextButton(onPressed: () => _load(), child: const Text('重新读取')),
      ]);
    }
    if (schedule == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (schedule.courses.isEmpty) {
      return _page(_tab, [
        _empty('从这一学期开始', '导入课表后，就能看到每天的安排。', Icons.auto_stories_outlined),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => _open(const PhotoScheduleImportView()),
          child: const Text('导入我的课表'),
        ),
      ]);
    }
    return IndexedStack(
      index: _tab.index,
      children: [
        _page(_ScheduleTab.today, _todayContent(schedule)),
        _page(_ScheduleTab.week, [
          _weekNavigation(schedule),
          const SizedBox(height: 20),
          ..._agenda(
            schedule,
            schedule.inWeek(schedule.weekAt(_weekDay)),
            groupByDay: true,
            firstDayAction: _returnButton(
              '本周',
              () => setState(() => _weekDay = PersonalSchedule.day(_clock)),
            ),
            emptyTitle: '这一周暂无课程',
            emptySubtitle: '可以切换周次，看看接下来的安排。',
          ),
          if (schedule.pending.isNotEmpty) ...[
            const SizedBox(height: 12),
            _pendingCourses(schedule),
          ],
        ]),
        _page(_ScheduleTab.month, _monthContent(schedule)),
      ],
    );
  }

  Widget _page(_ScheduleTab tab, List<Widget> children) => Builder(
    builder: (pageContext) => RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: PageStorageKey('schedule-${tab.name}'),
        controller: _scrolls[tab.index],
        physics: const AlwaysScrollableScrollPhysics(),
        // Scaffold includes the floating bar in this padding when extendBody is on.
        padding: EdgeInsets.fromLTRB(
          22,
          0,
          22,
          24 + MediaQuery.paddingOf(pageContext).bottom,
        ),
        children: children,
      ),
    ),
  );

  List<Widget> _todayContent(PersonalSchedule schedule) {
    final courses = schedule.onDay(_now);
    final next = schedule.next(_now);
    return [
      ..._agenda(
        schedule,
        courses,
        emptyTitle: '今天没有课',
        emptySubtitle: '留一点时间，给阅读和生活。',
        highlightNext: true,
      ),
      if (courses.isEmpty && next != null) ...[
        const SizedBox(height: 20),
        _nextCard(next, schedule),
      ],
    ];
  }

  Widget _nextCard(CourseOccurrence next, PersonalSchedule schedule) {
    final tomorrow = DateTime(_now.year, _now.month, _now.day + 1);
    final date = PersonalSchedule.sameDay(next.date, tomorrow)
        ? '明天'
        : _date(next.date);
    return Card(
      color: _colors.primaryContainer.withValues(alpha: .45),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _details(next.course, schedule),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: _colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '下一节课',
                    style: TextStyle(fontSize: 12, color: _colors.primary),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: _colors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                next.course.name ?? '未命名课程',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$date 周${_weekdays[next.date.weekday - 1]} · ${_timeDescription(next.period, next.clockRange)}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: _colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _room(next.course),
                style: TextStyle(fontSize: 12, color: _colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weekNavigation(PersonalSchedule schedule) {
    final week = schedule.weekAt(_weekDay);
    final monday = schedule.dateFor(week, 1);
    final sunday = schedule.dateFor(week, 7);
    return _rangeNavigation(
      title: week < 1 ? '开学前' : '第 $week 周',
      subtitle: '${_shortDate(monday)} — ${_shortDate(sunday)}',
      previousLabel: '上一周',
      nextLabel: '下一周',
      previous: () => setState(() => _weekDay = schedule.dateFor(week - 1, 1)),
      next: () => setState(() => _weekDay = schedule.dateFor(week + 1, 1)),
    );
  }

  Widget _rangeNavigation({
    required String title,
    required String subtitle,
    required String previousLabel,
    required String nextLabel,
    required VoidCallback previous,
    required VoidCallback next,
  }) => Row(
    children: [
      IconButton(
        tooltip: previousLabel,
        onPressed: previous,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Expanded(
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: nextLabel,
        onPressed: next,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ],
  );

  Widget _returnButton(String label, VoidCallback onPressed) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(60, 32),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      backgroundColor: _colors.surface.withValues(alpha: .7),
      side: BorderSide(color: _colors.primary.withValues(alpha: .4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    child: Text(label),
  );

  Widget _sectionHeading(String title, {Widget? action}) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _colors.onSurfaceVariant,
          ),
        ),
      ),
      if (action != null) ...[const SizedBox(width: 12), action],
    ],
  );

  void _changeMonth(int delta) => setState(() {
    _monthDay = DateTime(_monthDay.year, _monthDay.month + delta, 1);
  });

  List<Widget> _monthContent(PersonalSchedule schedule) {
    final first = DateTime(_monthDay.year, _monthDay.month, 1);
    final last = DateTime(first.year, first.month + 1, 0);
    final coursesByDay = <int, List<CourseOccurrence>>{};
    for (final item in schedule.occurrences) {
      if (item.date.year == first.year && item.date.month == first.month) {
        coursesByDay.putIfAbsent(item.date.day, () => []).add(item);
      }
    }
    final count = coursesByDay.values.fold<int>(
      0,
      (sum, day) => sum + day.length,
    );
    final offset = first.weekday - 1;
    final rows = (offset + last.day + 6) ~/ 7;
    return [
      _rangeNavigation(
        title: '${first.year}年${first.month}月',
        subtitle: '$count 节课',
        previousLabel: '上个月',
        nextLabel: '下个月',
        previous: () => _changeMonth(-1),
        next: () => _changeMonth(1),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          for (final weekday in _weekdays)
            Expanded(
              child: Center(
                child: Text(
                  weekday,
                  style: TextStyle(
                    fontSize: 12,
                    color: _colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      for (var row = 0; row < rows; row++)
        Row(
          children: [
            for (var column = 0; column < 7; column++)
              Expanded(
                child: Builder(
                  builder: (context) {
                    final day = row * 7 + column - offset + 1;
                    if (day < 1 || day > last.day) return const SizedBox();
                    final date = DateTime(first.year, first.month, day);
                    return _monthCell(date, coursesByDay[day]?.length ?? 0);
                  },
                ),
              ),
          ],
        ),
      const SizedBox(height: 12),
      Center(
        child: Text(
          '圆点表示当天有课',
          style: TextStyle(fontSize: 11, color: _colors.onSurfaceVariant),
        ),
      ),
      const SizedBox(height: 24),
      _sectionHeading(
        '${_date(_monthDay)} · 星期${_weekdays[_monthDay.weekday - 1]}',
        action: _returnButton(
          '本月',
          () => setState(() => _monthDay = PersonalSchedule.day(_clock)),
        ),
      ),
      const SizedBox(height: 14),
      ..._agenda(
        schedule,
        coursesByDay[_monthDay.day] ?? [],
        emptyTitle: '这一天没有课',
        emptySubtitle: '选择其他日期，看看当天的安排。',
      ),
    ];
  }

  Widget _monthCell(DateTime date, int count) {
    final selected = PersonalSchedule.sameDay(date, _monthDay);
    final today = PersonalSchedule.sameDay(date, _now);
    final color = selected ? _colors.onPrimary : _colors.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: Semantics(
        button: true,
        selected: selected,
        onTap: () => setState(() => _monthDay = date),
        label:
            '${date.year}年${_date(date)} 星期${_weekdays[date.weekday - 1]}${today ? ' 今天' : ''}，$count 节课',
        child: ExcludeSemantics(
          child: Material(
            color: selected
                ? _colors.primary
                : today
                ? _colors.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: ValueKey('month-day-${date.year}-${date.month}-${date.day}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _monthDay = date),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected || today
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: count > 0 ? color : Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pendingCourses(PersonalSchedule schedule) => Card(
    child: ExpansionTile(
      key: PageStorageKey('pending-${schedule.tableId}'),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(Icons.more_time_rounded, color: _colors.primary),
      title: Text(
        '${schedule.pending.length} 门课程待安排',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      children: [
        for (final course in schedule.pending)
          ListTile(
            title: Text(course.name ?? '未命名课程'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _details(course, schedule),
          ),
      ],
    ),
  );

  List<Widget> _agenda(
    PersonalSchedule schedule,
    List<CourseOccurrence> courses, {
    required String emptyTitle,
    required String emptySubtitle,
    bool groupByDay = false,
    bool highlightNext = false,
    Widget? firstDayAction,
  }) {
    if (courses.isEmpty) {
      return [
        if (firstDayAction != null)
          _sectionHeading('课程安排', action: firstDayAction),
        _empty(emptyTitle, emptySubtitle, Icons.local_florist_outlined),
      ];
    }
    final result = <Widget>[];
    final next = highlightNext ? schedule.next(_now) : null;
    DateTime? lastDate;
    for (final occurrence in courses) {
      if (groupByDay && lastDate != occurrence.date) {
        result.add(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: _sectionHeading(
              '${_date(occurrence.date)}  周${_weekdays[occurrence.date.weekday - 1]}',
              action: lastDate == null ? firstDayAction : null,
            ),
          ),
        );
        lastDate = occurrence.date;
      }
      result.add(
        _courseCard(
          occurrence,
          schedule,
          isNext:
              next?.course == occurrence.course &&
              next?.date == occurrence.date,
        ),
      );
      result.add(const SizedBox(height: 12));
    }
    return result;
  }

  Widget _courseCard(
    CourseOccurrence item,
    PersonalSchedule schedule, {
    bool isNext = false,
  }) {
    final completed = item.end != null && !item.end!.isAfter(_now);
    return Card(
      color: isNext ? _colors.primaryContainer.withValues(alpha: .45) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _details(item.course, schedule),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _colors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _timeDescription(item.period, item.clockRange),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _colors.primary,
                      ),
                    ),
                  ),
                  if (item.isOngoing(_now))
                    const Text('正在上课', style: TextStyle(fontSize: 11))
                  else if (isNext)
                    const Text('下一节课', style: TextStyle(fontSize: 11))
                  else if (completed)
                    Text(
                      '已结束',
                      style: TextStyle(
                        fontSize: 11,
                        color: _colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.course.name ?? '未命名课程',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _room(item.course),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: _colors.onSurfaceVariant,
                ),
              ),
              if ((item.course.teacher ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.course.teacher!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(String title, String subtitle, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 34, color: _colors.primary),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: _colors.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ],
    ),
  );

  String _timeDescription(String? period, String? clock, {String separator = '  '}) {
    if (period != null && period == clock) return period;
    return "${period ?? '时段待定'}$separator${clock ?? '具体时间待定'}";
  }

  String _room(Course course) =>
      (course.classroom ?? '').trim().isEmpty ? '地点待定' : course.classroom!;

  void _details(Course course, PersonalSchedule schedule) {
    final period = ClassTimeUtil.rangeLabel(
      schedule.periods,
      course.startTime ?? 0,
      course.timeCount ?? 0,
    );
    final clock = ClassTimeUtil.clockRange(
      schedule.periods,
      course.startTime ?? 0,
      course.timeCount ?? 0,
    );
    final scheduled = (course.weekTime ?? 0) > 0 && (course.weekTime ?? 0) <= 7;
    List<int> weeks;
    try {
      weeks = List<int>.from(jsonDecode(course.weeks ?? '[]'));
    } catch (_) {
      weeks = [];
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .62,
        minChildSize: .35,
        maxChildSize: .94,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '关闭详情',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Text(
              course.name ?? '未命名课程',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            _detailLine(
              Icons.schedule_rounded,
              scheduled
                  ? '周${_weekdays[course.weekTime! - 1]} · ${_timeDescription(period, clock, separator: '\n')}'
                  : '时间待定',
            ),
            _detailLine(Icons.place_outlined, _room(course)),
            _detailLine(
              Icons.person_outline_rounded,
              (course.teacher ?? '').isEmpty ? '教师待定' : course.teacher!,
            ),
            _detailLine(
              Icons.date_range_outlined,
              ScreenshotSchedule.formatWeeks(weeks),
            ),
            if ((course.info ?? '').isNotEmpty) ...[
              const Divider(height: 32),
              Text(
                course.info!,
                style: TextStyle(
                  height: 1.7,
                  fontSize: 13,
                  color: _colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailLine(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: _colors.primary),
        const SizedBox(width: 13),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 16, height: 1.5)),
        ),
      ],
    ),
  );
}
