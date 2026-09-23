import 'dart:convert';
import 'package:flutter/material.dart';
import '../../Components/ScheduleDesign.dart';
import '../../Models/CourseModel.dart';
import '../../Models/CourseTableModel.dart';
import '../../Utils/ClassTimeUtil.dart';
import '../../Utils/CourseWeeks.dart';
import '../../Resources/Config.dart';

class EditCourseView extends StatefulWidget {
  final Course course;
  const EditCourseView({super.key, required this.course});
  @override
  State<EditCourseView> createState() => _EditCourseViewState();
}

class _EditCourseViewState extends State<EditCourseView> {
  late final TextEditingController _name, _teacher, _place, _note;
  late Set<int> _weeks;
  late int _weekday, _start, _end;
  List<Map>? _periods;
  bool _saving = false, _scheduleEdited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _name = TextEditingController(text: c.name ?? '');
    _teacher = TextEditingController(text: c.teacher ?? '');
    _place = TextEditingController(text: c.classroom ?? '');
    _note = TextEditingController(text: c.info ?? '');
    _weeks = CourseWeeks.parse(c.weeks).toSet();
    _weekday = (c.weekTime ?? 0).clamp(0, 7);
    _start = c.startTime ?? 0;
    _end = _start + (c.timeCount ?? 0);
    _load();
  }

  Future<void> _load() async {
    try {
      final periods = await CourseTableProvider().getClassTimeList(
        widget.course.tableId!,
      );
      if (mounted) setState(() => _periods = periods);
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法读取作息，可重试后编辑。');
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _teacher, _place, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请填写课程名称');
      return;
    }
    if (_scheduleEdited &&
        _weekday > 0 &&
        (_weeks.isEmpty ||
            !((_start == 0 && _end == 0) ||
                (_start >= 1 &&
                    _end >= _start &&
                    _end <= (_periods?.length ?? 0))))) {
      setState(() => _error = '请选择上课周次和有效的起止时段，或把安排设为待定。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    // Work on a detached copy. Cancel or a failed write never changes the home page.
    final course = Course.fromMap(widget.course.toMap());
    course.name = _name.text.trim();
    if (_teacher.text.trim() != (widget.course.teacher ?? '')) {
      course.teacher = _teacher.text.trim();
    }
    if (_place.text.trim() != (widget.course.classroom ?? '')) {
      course.classroom = _place.text.trim();
    }
    if (_note.text.trim() != (widget.course.info ?? '')) {
      course.info = _note.text.trim();
    }
    course.weeks = widget.course.weeks;
    if (_scheduleEdited) {
      course.weekTime = _weekday;
      course.weeks = jsonEncode(_weeks.toList()..sort());
      course.startTime = _weekday == 0 ? 0 : _start;
      course.timeCount = _weekday == 0 ? 0 : _end - _start;
    }
    try {
      final updated = await CourseProvider().update(course);
      if (updated != 1) throw StateError('course_missing');
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存未完成，原课程仍保留。请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('编辑课程')),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const ScheduleNotice('修改只用于这条课程安排；同名课程的其他安排保持独立。'),
          const ScheduleSection('课程信息'),
          TextField(
            controller: _name,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '课程名称'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _teacher,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '教师 · 可留空'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _place,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '地点 · 可留空'),
          ),
          const ScheduleSection('上课安排', subtitle: '未确认的时间可以保持待定。'),
          DropdownButtonFormField<int>(
            initialValue: _weekday,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '星期'),
            items: [
              for (var i = 0; i <= 7; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(i == 0 ? '安排待定' : '星期${'一二三四五六日'[i - 1]}'),
                ),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() {
                    _weekday = v!;
                    _scheduleEdited = true;
                  }),
          ),
          if (_periods == null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('重新读取作息')),
          ] else if (_weekday > 0) ...[
            const SizedBox(height: 14),
            for (final isStart in [true, false])
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  itemHeight: null,
                  initialValue:
                      (isStart ? _start : _end) >= 1 &&
                          (isStart ? _start : _end) <= _periods!.length
                      ? (isStart ? _start : _end)
                      : 0,
                  decoration: InputDecoration(
                    labelText: isStart ? '开始时段' : '结束时段',
                  ),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('时间待定')),
                    for (var i = 1; i <= _periods!.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          ClassTimeUtil.clockRange(_periods!, i, 0) ??
                              ClassTimeUtil.rangeLabel(_periods!, i, 0) ??
                              '第 $i 节',
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                          if (isStart) {
                            _start = v!;
                          } else {
                            _end = v!;
                          }
                          _scheduleEdited = true;
                        }),
                ),
              ),
            const ScheduleSection('上课周次'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var week = 1; week <= Config.MAX_WEEKS; week++)
                  FilterChip(
                    label: Text('第 $week 周'),
                    selected: _weeks.contains(week),
                    onSelected: _saving
                        ? null
                        : (selected) => setState(() {
                            selected ? _weeks.add(week) : _weeks.remove(week);
                            _scheduleEdited = true;
                          }),
                  ),
              ],
            ),
          ],
          const ScheduleSection('备注'),
          TextField(
            controller: _note,
            enabled: !_saving,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: '备注 · 可留空'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ScheduleNotice(_error!, error: true),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || widget.course.id == null ? null : _save,
            child: Text(_saving ? '正在保存…' : '保存课程'),
          ),
        ],
      ),
    ),
  );
}
