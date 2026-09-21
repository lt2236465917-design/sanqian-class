import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Utils/States/MainState.dart';
import '../../Models/CourseTableModel.dart';
import '../../Models/ScheduleImportDraft.dart';
import '../../Utils/ScheduleImportService.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../Settings/DeepSeekSettingsView.dart';

/// Input adapters produce draft fields; this is the only route that commits them.
class ImportReviewView extends StatefulWidget {
  final List<Map<String, dynamic>> courses;
  final String source;
  final String? accountLocalId;
  final String? timetableText;
  final List<String> warnings;
  const ImportReviewView({
    super.key,
    required this.courses,
    required this.source,
    this.accountLocalId,
    this.timetableText,
    this.warnings = const [],
  });
  @override
  State<ImportReviewView> createState() => _ImportReviewViewState();
}

class _ImportReviewViewState extends State<ImportReviewView> {
  final _school = TextEditingController(text: '中国艺术研究院');
  final _term = TextEditingController();
  DateTime? _monday;
  List<Map<String, dynamic>> _courses = [];
  List<Map> _tables = [];
  int? _target;
  bool _busy = false;
  bool _recognizing = false;
  bool _portalAICompleted = false;
  bool get _needsPortalAI =>
      widget.source == 'school-portal' && !_portalAICompleted;
  int _recognitionTicket = 0;
  String? _error;
  bool get _hasPortalText => (widget.timetableText ?? '').trim().isNotEmpty;
  @override
  void initState() {
    super.initState();
    _courses = widget.courses;
    _loadTables();
  }

  Future<void> _loadTables() async {
    final tables = await CourseTableProvider().getAllCourseTable();
    if (mounted) setState(() => _tables = List<Map>.from(tables));
  }

  @override
  void dispose() {
    _recognitionTicket++;
    if (_recognizing) {
      unawaited(
        ScheduleDerivedDataService.channel
            .invokeMethod<void>('cancelRecognition')
            .catchError((Object _) {}),
      );
    }
    _school.dispose();
    _term.dispose();
    super.dispose();
  }

  Future<void> _edit(int index) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => _CourseEditor(course: _courses[index])),
    );
    if (result != null && mounted) setState(() => _courses[index] = result);
  }

  Future<void> _assist() async {
    if (_busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_hasPortalText ? 'AI 识别网页课表' : 'AI 辅助核对'),
        content: Text(
          _hasPortalText
              ? '将网页中读取到的原始课表单元格发送到 DeepSeek，包含尚未解析出的课程行，可能消耗账户余额。不会发送账号、密码或网页会话。识别后仍需核对和确认保存。'
              : '将当前课程名称、教师和课表安排发送到 DeepSeek，可能消耗账户余额。不会发送账号、密码或网页会话。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('发送并整理'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final ticket = ++_recognitionTicket;
    setState(() {
      _busy = true;
      _recognizing = true;
      _error = null;
    });
    try {
      final text = _hasPortalText
          ? widget.timetableText!
          : _courses
                .map(
                  (c) =>
                      '课程名称：${c['name']}\n教师：${c['teacher'] ?? ''}\n课程编码：${c['courseCode'] ?? ''}\n${_summary(c)}',
                )
                .join('\n\n');
      final result = await ScheduleDerivedDataService.channel
          .invokeMapMethod<String, dynamic>('recognizeText', {'text': text});
      if (!mounted || ticket != _recognitionTicket) return;
      _recognizing = false;
      final candidates = (result?['courses'] as List? ?? [])
          .map((c) => Map<String, dynamic>.from(c))
          .toList();
      if (candidates.isEmpty) {
        throw const FormatException('AI 未返回可用课程，当前核对内容已保留');
      }
      for (final course in candidates) {
        if (ScheduleImportCourseDraft.fromJson(course).validate().isNotEmpty) {
          throw const FormatException('AI 返回的课程字段不完整或有误，当前核对内容已保留');
        }
        course['raw'] = {
          // StandardMessageCodec leaves nested dictionaries as Object? maps.
          // Convert their keys instead of casting the native map's type.
          ...Map<String, dynamic>.from(course['raw'] as Map? ?? const {}),
          'recognition': 'deepseek',
          'sourceLine': course['sourceLine'],
        };
      }
      // A retry must not silently replace local corrections or drop courses.
      if (_courses.isNotEmpty) {
        final useResult = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('核对 AI 识别结果'),
            content: SingleChildScrollView(
              child: Text(
                '当前有 ${_courses.length} 项，AI 返回 ${candidates.length} 项。采用后将替换当前核对内容，包括手动修改；正式课表尚不会改变。\n\n'
                '${candidates.map((course) => '${course['name']}\n${_summary(course)}').join('\n\n')}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('保留当前内容'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('采用并继续核对'),
              ),
            ],
          ),
        );
        if (useResult != true || !mounted || ticket != _recognitionTicket) {
          return;
        }
      }
      setState(() {
        _courses = candidates;
        _portalAICompleted = true;
      });
    } catch (e) {
      if (mounted && ticket == _recognitionTicket) {
        setState(
          () => _error = e is PlatformException
              ? e.message ?? 'AI 识别失败，当前核对内容已保留'
              : e is FormatException
              ? e.message
              : 'AI 识别失败，当前核对内容已保留',
        );
      }
    } finally {
      if (mounted && ticket == _recognitionTicket) {
        setState(() {
          _busy = false;
          _recognizing = false;
        });
      }
    }
  }

  Future<void> _cancelRecognition() async {
    final ticket = ++_recognitionTicket;
    try {
      await ScheduleDerivedDataService.channel.invokeMethod(
        'cancelRecognition',
      );
    } catch (_) {
      // The ticket also invalidates a late reply if the native channel closes.
    } finally {
      if (mounted && ticket == _recognitionTicket) {
        setState(() {
          _busy = false;
          _recognizing = false;
          _error = '已取消识别，当前核对内容已保留';
        });
      }
    }
  }

  Future<Map<String, int>?> _chooseBindings(ScheduleImportDiff diff) async {
    final selected = <String, int>{};
    return showDialog<Map<String, int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('关联已有课程'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '若这些是内置课表中的同一安排，请明确选择对应项。关联会保留原课程 ID 和本地修改。未关联的歧义项保持冲突，不会猜测覆盖。',
                  ),
                  for (final detail in diff.details.where(
                    (d) => d['incoming'] != null,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${detail['name']} · ${_fieldsDescription(detail['incoming'])}',
                          ),
                          DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: 0,
                            items: [
                              const DropdownMenuItem(
                                value: 0,
                                child: Text('不关联'),
                              ),
                              for (final row in diff.legacyCandidates)
                                DropdownMenuItem(
                                  value: row['id'] as int,
                                  child: Text(
                                    '${row['name']} · ${_fieldsDescription(row)}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (id) => update(() {
                              if (id == null || id == 0) {
                                selected.remove(detail['key']);
                              } else {
                                selected[detail['key'] as String] = id;
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('返回核对'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('继续查看变化'),
            ),
          ],
        ),
      ),
    );
  }

  String _fieldsDescription(dynamic fields) {
    if (fields == null) return '此次来源中已移除';
    if (fields is List) {
      return fields.isEmpty
          ? '无匹配安排'
          : fields.map(_fieldsDescription).join('；');
    }
    if (fields is! Map) return '';
    final day = fields['week_time'];
    return '${day == null || day == 0 ? '安排待定' : '星期 $day'} · 周次 ${fields['weeks'] ?? '待定'}'
        ' · ${fields['start_time'] == null || fields['start_time'] == 0 ? '钟点待定' : '第 ${fields['start_time']}–${(fields['start_time'] as int) + (fields['time_count'] as int? ?? 0)} 时段'}'
        ' · ${fields['classroom'] ?? '教室待定'} · ${fields['teacher'] ?? '教师待定'}';
  }

  Future<void> _save() async {
    if (_needsPortalAI || _busy || _courses.isEmpty) return;
    final model = MainStateModel.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_monday == null) throw const FormatException('请选择学期第一周周一');
      final draft = ScheduleImportDraft(
        source: widget.source,
        sourceId: 'school-timetable',
        accountLocalId: widget.accountLocalId,
        school: _school.text.trim(),
        term: _term.text.trim(),
        firstWeekMonday: _monday,
        courses: _courses.map(ScheduleImportCourseDraft.fromJson).toList(),
      );
      draft.requireValid();
      final periods = <Map<String, dynamic>>[];
      for (final course in draft.courses) {
        for (final meeting in course.meetings) {
          if (meeting.startMinute != null && meeting.endMinute != null) {
            final start = _clock(meeting.startMinute),
                end = _clock(meeting.endMinute);
            if (!periods.any((p) => p['start'] == start && p['end'] == end)) {
              periods.add({'start': start, 'end': end, 'label': '$start–$end'});
            }
          }
        }
      }
      periods.sort(
        (a, b) => (a['start'] as String).compareTo(b['start'] as String),
      );
      var diff = await ScheduleImportService.preview(
        draft,
        mergeTableId: _target,
        periods: periods,
      );
      if (!mounted) return;
      var bindings = <String, int>{};
      if (diff.legacyCandidates.isNotEmpty) {
        final choices = await _chooseBindings(diff);
        if (choices == null || !mounted) return;
        bindings = choices;
        diff = await ScheduleImportService.preview(
          draft,
          mergeTableId: _target,
          periods: periods,
          legacyBindings: bindings,
        );
        if (!mounted) return;
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认导入变化'),
          content: SingleChildScrollView(
            child: Text(
              '首次新建会采用以下已核对钟点作为作息：\n${periods.map((p) => p['label']).join('、')}\n已有课表会保留原作息。\n\n新增 ${diff.added.length} 项，变更 ${diff.changed.length} 项，移除 ${diff.removed.length} 项，待定 ${diff.pending.length} 项。\n'
              '${diff.conflicts.isEmpty ? '' : '${diff.conflicts.length} 处来源或本地编辑冲突将保留原内容，请核对后手动处理。\n'}'
              '${diff.details.map((d) => '${d['name']}\n原安排：${_fieldsDescription(d['current'])}\n新安排：${_fieldsDescription(d['incoming'])}').join('\n\n')}\n确认后保存；已手动删除的课程不会恢复。时间未匹配作息的安排保留为待定。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回核对'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认保存'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      final result = await ScheduleImportService.commit(
        draft,
        mergeTableId: _target,
        acceptChanges: true,
        expectedReviewToken: diff.reviewToken,
        legacyBindings: bindings,
        periods: periods,
      );
      await model.changeclassTable(result.tableId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_needsPortalAI ? 'AI 识别网页课表' : '核对导入课表')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('请核对课程、周次、钟点和教室。缺失信息保持待定，确认前不会保存。'),
        for (final warning in widget.warnings) Text(warning),
        if (_courses.isEmpty && _hasPortalText)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '已读取网页课表原文。点击下方按钮，由 AI 识别课程、周次、时间和教室，再核对保存。未配置 Key 时，请先进入 DeepSeek 设置。',
            ),
          ),
        if (widget.source == 'school-portal' &&
            (_hasPortalText || _courses.isNotEmpty))
          FilledButton(
            onPressed: _busy ? null : _assist,
            child: Text(_hasPortalText ? 'AI 识别网页课表' : 'AI 辅助核对课表文字'),
          ),
        if (widget.source == 'school-portal')
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DeepSeekSettingsView(),
                    ),
                  ),
            child: const Text('DeepSeek 设置'),
          ),
        if (_recognizing)
          TextButton(onPressed: _cancelRecognition, child: const Text('取消识别')),
        TextField(
          controller: _school,
          decoration: const InputDecoration(labelText: '学校'),
        ),
        TextField(
          controller: _term,
          decoration: const InputDecoration(labelText: '学期，例如 2026 秋季'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('第一周周一'),
          subtitle: Text(
            _monday == null
                ? '请选择，不能以导入日期代替'
                : '${_monday!.year}-${_monday!.month}-${_monday!.day}',
          ),
          onTap: _busy
              ? null
              : () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: _monday ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (day != null && mounted) {
                    setState(() {
                      if (day.weekday == DateTime.monday) {
                        _monday = day;
                        _error = null;
                      } else {
                        _error = '请选择第一周的周一';
                      }
                    });
                  }
                },
        ),
        DropdownButtonFormField<int>(
          initialValue: _target ?? -1,
          decoration: const InputDecoration(labelText: '保存到'),
          items: [
            const DropdownMenuItem(value: -1, child: Text('自动回到同来源课表／首次新建')),
            for (final table in _tables)
              DropdownMenuItem(
                value: table['id'] as int,
                child: Text('合并到 ${table['name']}'),
              ),
          ],
          onChanged: _busy
              ? null
              : (v) => setState(() => _target = v == -1 ? null : v),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _courses.length; i++)
          Card(
            child: ListTile(
              title: Text('${_courses[i]['name'] ?? ''}'),
              subtitle: Text(_summary(_courses[i])),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _busy ? null : () => _edit(i),
            ),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || _courses.isEmpty || _needsPortalAI ? null : _save,
          child: Text(_busy ? '处理中…' : '查看变化并保存'),
        ),
      ],
    ),
  );
  String _summary(Map<String, dynamic> course) {
    final meetings = (course['meetings'] as List? ?? []).whereType<Map>();
    if (meetings.isEmpty) return '${course['pendingReason'] ?? '安排待定'}';
    return meetings
        .map(
          (m) =>
              '星期 ${m['weekday'] ?? '待定'} · ${m['weeks'] ?? '周次待定'}\n'
              '${_clock(m['startMinute'])}–${_clock(m['endMinute'])} · ${m['location'] ?? '地点待定'}',
        )
        .join('\n');
  }
}

String _clock(dynamic minute) => minute is int
    ? '${minute ~/ 60}'.padLeft(2, '0') + ':' + '${minute % 60}'.padLeft(2, '0')
    : '待定';

class _CourseEditor extends StatefulWidget {
  final Map<String, dynamic> course;
  const _CourseEditor({required this.course});
  @override
  State<_CourseEditor> createState() => _CourseEditorState();
}

class _CourseEditorState extends State<_CourseEditor> {
  late final Map<String, TextEditingController> _fields;
  late final List<Map<String, TextEditingController>> _meetings;
  String? _error;
  @override
  void initState() {
    super.initState();
    _fields = {
      for (final k in [
        'name',
        'courseCode',
        'section',
        'teacher',
        'pendingReason',
      ])
        k: TextEditingController(text: '${widget.course[k] ?? ''}'),
    };
    _meetings = (widget.course['meetings'] as List? ?? [])
        .whereType<Map>()
        .map(
          (m) => {
            'weekday': TextEditingController(text: '${m['weekday'] ?? ''}'),
            'weeks': TextEditingController(
              text: (m['weeks'] as List? ?? []).join(','),
            ),
            'startMinute': TextEditingController(
              text: m['startMinute'] == null ? '' : _clock(m['startMinute']),
            ),
            'endMinute': TextEditingController(
              text: m['endMinute'] == null ? '' : _clock(m['endMinute']),
            ),
            'location': TextEditingController(text: '${m['location'] ?? ''}'),
          },
        )
        .toList();
  }

  @override
  void dispose() {
    for (final c in [..._fields.values, ..._meetings.expand((m) => m.values)]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _minute(String s) {
    if (s.trim().isEmpty) return null;
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(s)) {
      throw const FormatException('钟点请填 HH:mm');
    }
    final p = s.split(':').map(int.parse).toList();
    return p[0] * 60 + p[1];
  }

  void _done() {
    try {
      final original = (widget.course['meetings'] as List? ?? []);
      final meetings = <Map<String, dynamic>>[];
      for (var i = 0; i < _meetings.length; i++) {
        final m = _meetings[i];
        final weeks = m['weeks']!.text.trim();
        meetings.add({
          if (i < original.length) ...Map<String, dynamic>.from(original[i]),
          'weekday': m['weekday']!.text.trim().isEmpty
              ? null
              : int.parse(m['weekday']!.text),
          'weeks': weeks.isEmpty
              ? null
              : weeks.split(RegExp('[,， ]+')).map(int.parse).toList(),
          'startMinute': _minute(m['startMinute']!.text),
          'endMinute': _minute(m['endMinute']!.text),
          'periodIndex': null,
          'periodCount': null,
          'location': m['location']!.text,
        });
      }
      final data = {
        ...widget.course,
        for (final e in _fields.entries) e.key: e.value.text.trim(),
        'meetings': meetings,
      };
      if (meetings.isEmpty && data['pendingReason'] == '') {
        data['pendingReason'] = '安排待定';
      }
      final errors = ScheduleImportCourseDraft.fromJson(data).validate();
      if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
      Navigator.pop(context, data);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('编辑课程')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final e in const {
          'name': '课程名称',
          'courseCode': '课程编码',
          'section': '教学班',
          'teacher': '教师',
          'pendingReason': '待定原因',
        }.entries)
          TextField(
            controller: _fields[e.key],
            decoration: InputDecoration(labelText: e.value),
          ),
        for (var i = 0; i < _meetings.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text('安排 ${i + 1}'),
                  for (final e in const {
                    'weekday': '星期（1–7）',
                    'weeks': '周次，用逗号分隔；空白为未知',
                    'startMinute': '开始 HH:mm',
                    'endMinute': '结束 HH:mm',
                    'location': '教室',
                  }.entries)
                    TextField(
                      controller: _meetings[i][e.key],
                      decoration: InputDecoration(labelText: e.value),
                    ),
                ],
              ),
            ),
          ),
        TextButton(
          onPressed: () => setState(
            () => _meetings.add({
              for (final k in [
                'weekday',
                'weeks',
                'startMinute',
                'endMinute',
                'location',
              ])
                k: TextEditingController(),
            }),
          ),
          child: const Text('添加安排'),
        ),
        if (_error != null) Text(_error!),
        FilledButton(onPressed: _done, child: const Text('完成核对')),
      ],
    ),
  );
}
