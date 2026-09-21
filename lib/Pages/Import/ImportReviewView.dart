import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../Utils/States/MainState.dart';
import '../../Models/CourseTableModel.dart';
import '../../Models/ScheduleImportDraft.dart';
import '../../Utils/ScheduleImportService.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../../Utils/ScheduleFeedback.dart';
import '../Settings/DeepSeekSettingsView.dart';
import '../Personal/Widgets/ScheduleStatusBadge.dart';
import 'Widgets/AIKeyStatus.dart';
import 'Widgets/RecognitionProgress.dart';

enum _ImportStage {
  idle,
  recognizing,
  reviewingAI,
  comparing,
  confirming,
  saving,
}

/// Input adapters produce draft fields; this is the only route that commits them.
class ImportReviewView extends StatefulWidget {
  final List<Map<String, dynamic>> courses;
  final String source;
  final String? accountLocalId;
  final String? timetableText;
  final List<String> warnings;
  final List<String> imagePaths;
  final List<String> expectedCourseNames;
  const ImportReviewView({
    super.key,
    required this.courses,
    required this.source,
    this.accountLocalId,
    this.timetableText,
    this.warnings = const [],
    this.imagePaths = const [],
    this.expectedCourseNames = const [],
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
  _ImportStage _stage = _ImportStage.idle;
  bool get _busy => _stage != _ImportStage.idle;
  bool _recognizing = false;
  bool _portalAICompleted = false;
  List<Map<String, dynamic>>? _beforeAI;
  bool _beforeAICompleted = false;
  int _keyRevision = 0;
  bool _loadingTables = true;
  bool _tablesFailed = false;
  bool _schoolEdited = false, _termEdited = false, _mondayEdited = false;
  String? _metadataNote;
  bool _triedSave = false;
  late ScheduleRecognitionPreparation _preparation;
  List<String> _replacementWarnings = [];
  bool _gateAcknowledged = false;
  bool _ocrAttempted = false;
  bool get _requiresGateReview =>
      _preparation.hasStructuralAnomaly || _replacementWarnings.isNotEmpty;
  bool get _offersOCR =>
      _preparation.shouldOfferOCR &&
      widget.imagePaths.isNotEmpty &&
      !_ocrAttempted;
  bool get _needsPortalAI =>
      widget.source == 'school-portal' && !_portalAICompleted;
  int _recognitionTicket = 0;
  String? _error;
  bool get _hasPortalText => (widget.timetableText ?? '').trim().isNotEmpty;
  @override
  void initState() {
    super.initState();
    _preparation = prepareScheduleRecognition(
      widget.courses,
      source: widget.source,
      expectedCourseNames: widget.courses.isEmpty
          ? const []
          : widget.expectedCourseNames,
    );
    _courses = _copyCourses(_preparation.courses);
    _loadTables();
  }

  Future<void> _loadTables() async {
    setState(() {
      _loadingTables = true;
      if (_tablesFailed) _error = null;
      _tablesFailed = false;
    });
    try {
      final provider = CourseTableProvider();
      final tables = await provider.getAllCourseTable();
      final loaded = await Future.wait(
        tables.map((row) async {
          final table = await provider.getCourseTable(row['id'] as int);
          Map metadata = {};
          try {
            final decoded = jsonDecode(table?.data ?? '{}');
            if (decoded is Map) metadata = decoded;
          } catch (_) {
            // A legacy table can have no import metadata. Do not invent it.
          }
          return <String, dynamic>{
            ...Map<String, dynamic>.from(row),
            'metadata': metadata,
          };
        }),
      );
      if (!mounted) return;
      setState(() {
        _tables = loaded;
        _applySavedContext();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _tablesFailed = true;
          _error = '暂时无法读取已有课表，请重试；已填写的内容保留。';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingTables = false);
    }
  }

  List<dynamic>? _sourceKey(Map table) {
    try {
      final value = jsonDecode(
        table['metadata']['import_source_key'] as String,
      );
      return value is List && value.length == 5 ? value : null;
    } catch (_) {
      return null;
    }
  }

  void _applySavedContext() {
    final matches = _tables.where((table) {
      if (_target != null) return table['id'] == _target;
      final key = _sourceKey(table);
      return key != null &&
          key[0] == widget.source &&
          key[1] == 'school-timetable' &&
          key[2] == widget.accountLocalId &&
          (!_schoolEdited || key[3] == _school.text.trim()) &&
          (!_termEdited || key[4] == _term.text.trim());
    }).toList();
    if (!_schoolEdited) _school.text = '中国艺术研究院';
    if (!_termEdited) _term.clear();
    if (!_mondayEdited) _monday = null;
    _metadataNote = matches.length > 1 ? '存在多个已保存学期，请填写学期或选择已有课表。' : null;
    if (matches.length != 1) return;
    final table = matches.single;
    final key = _sourceKey(table);
    if (key != null &&
        (key[0] != widget.source ||
            key[1] != 'school-timetable' ||
            key[2] != widget.accountLocalId ||
            (_schoolEdited && key[3] != _school.text.trim()) ||
            (_termEdited && key[4] != _term.text.trim()))) {
      _metadataNote = '所选课表的来源、账号或学期不同，请检查填写内容或保存位置。';
      return;
    }
    // Malformed source metadata must not be treated as an unowned legacy table.
    if (key == null && table['metadata']['import_source_key'] != null) return;
    var filled = false;
    if (key != null) {
      if (!_schoolEdited && key[3] is String) {
        _school.text = key[3];
        filled = true;
      }
      if (!_termEdited && key[4] is String) {
        _term.text = key[4];
        filled = true;
      }
    }
    final raw = table['metadata']['semester_start_monday'];
    final monday = raw is String ? DateTime.tryParse(raw) : null;
    if (!_mondayEdited &&
        monday != null &&
        monday.weekday == DateTime.monday &&
        monday.year >= 2020 &&
        monday.year <= 2040 &&
        raw == monday.toIso8601String().split('T').first) {
      _monday = monday;
      filled = true;
    }
    if (filled) _metadataNote = '已带入“${table['name']}”的已保存信息，请核对学期与开学日期。';
  }

  List<Map<String, dynamic>> _copyCourses(List<Map<String, dynamic>> courses) =>
      (jsonDecode(jsonEncode(courses)) as List)
          .map((course) => Map<String, dynamic>.from(course))
          .toList();

  Future<void> _openAISettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const DeepSeekSettingsView()),
    );
    if (mounted) setState(() => _keyRevision++);
  }

  void _restoreBeforeAI() {
    if (_beforeAI == null || _busy) return;
    final restored = _copyCourses(_beforeAI!);
    setState(() {
      _preparation = prepareScheduleRecognition(
        restored,
        source: widget.source,
        expectedCourseNames: restored.isEmpty
            ? const []
            : widget.expectedCourseNames,
      );
      _courses = _copyCourses(_preparation.courses);
      _portalAICompleted = _beforeAICompleted;
      _beforeAI = null;
      _replacementWarnings = [];
      _gateAcknowledged = false;
      _error = null;
    });
    ScheduleFeedback.success(context, '已恢复本次 AI 处理前的内容');
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
    if (result != null && mounted) {
      setState(() {
        _courses[index] = result;
        _preparation = prepareScheduleRecognition(
          _courses,
          source: widget.source,
          expectedCourseNames: _courses.isEmpty
              ? const []
              : widget.expectedCourseNames,
        );
        _courses = _copyCourses(_preparation.courses);
        _gateAcknowledged = false;
      });
    }
  }

  Future<void> _assist({bool withOCR = false}) async {
    if (_busy || (withOCR && !_offersOCR)) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          withOCR
              ? '使用 OCR 复核'
              : _hasPortalText
              ? 'AI 识别网页课表'
              : 'AI 辅助核对',
        ),
        content: Text(
          withOCR
              ? '将原课表图片与本机识别出的文字一同发送到 DeepSeek，再核对一次，可能再次消耗账户余额。文字识别也可能出错，复核结果需要你确认后才会替换当前内容。'
              : _hasPortalText
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
            child: Text(withOCR ? '发送并复核' : '发送并整理'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final ticket = ++_recognitionTicket;
    setState(() {
      _stage = _ImportStage.recognizing;
      _recognizing = true;
      _error = null;
      if (withOCR) _ocrAttempted = true;
    });
    try {
      final Map<String, dynamic>? result;
      if (withOCR) {
        result = await ScheduleDerivedDataService.channel
            .invokeMapMethod<String, dynamic>('recognizePhotosWithOCR', {
              'paths': widget.imagePaths,
            });
      } else {
        final text = _hasPortalText
            ? widget.timetableText!
            : _courses
                  .map(
                    (c) =>
                        '课程名称：${c['name']}\n教师：${c['teacher'] ?? ''}\n课程编码：${c['courseCode'] ?? ''}\n${_summary(c)}',
                  )
                  .join('\n\n');
        result = await ScheduleDerivedDataService.channel
            .invokeMapMethod<String, dynamic>('recognizeText', {'text': text});
      }
      if (!mounted || ticket != _recognitionTicket) return;
      setState(() {
        _recognizing = false;
        _stage = _ImportStage.reviewingAI;
      });
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
        // StandardMessageCodec leaves nested dictionaries as Object? maps.
        // Convert their keys instead of casting the native map's type.
        final raw = Map<String, dynamic>.from(
          course['raw'] as Map? ?? const {},
        );
        course['raw'] = {
          ...raw,
          'recognition': withOCR ? 'deepseek-ocr-review' : 'deepseek',
          'sourceLine': course['sourceLine'] ?? raw['sourceLine'],
        };
      }
      final prepared = prepareScheduleRecognition(
        candidates,
        source: widget.source,
        expectedCourseNames: widget.expectedCourseNames,
      );
      final changes = scheduleRecognitionReplacementWarnings(
        _courses,
        prepared.courses,
      );
      final reviewed = prepared.courses;
      // A follow-up must not silently replace corrections or drop meetings.
      if (_courses.isNotEmpty) {
        final useResult = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('核对 AI 识别结果'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前 ${_courses.length} 门课程 · 复核整理后 ${reviewed.length} 门',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '采用后将替换当前核对内容，包括手动修改；保存前可恢复本次 AI 处理前的内容。正式课表尚不会改变。',
                    ),
                    if (prepared.warnings.isNotEmpty || changes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final warning in [...prepared.warnings, ...changes])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(warning),
                        ),
                    ],
                    const SizedBox(height: 12),
                    ..._aiChanges(reviewed),
                    _draftSummaryGroup('当前核对内容', _courses),
                    _draftSummaryGroup('AI 返回内容', reviewed, expanded: true),
                  ],
                ),
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
        _beforeAI = _copyCourses(_courses);
        _beforeAICompleted = _portalAICompleted;
        _preparation = prepared;
        _courses = _copyCourses(prepared.courses);
        _replacementWarnings = changes;
        _gateAcknowledged = false;
        if (!withOCR) _portalAICompleted = true;
      });
      ScheduleFeedback.success(context, 'AI 结果已采用，请继续核对');
    } catch (e) {
      if (mounted && ticket == _recognitionTicket) {
        setState(
          () => _error = ScheduleFeedback.message(
            e,
            fallback: 'AI 识别失败，当前核对内容已保留；请检查网络或 Key 后重试。',
          ),
        );
      }
    } finally {
      if (mounted && ticket == _recognitionTicket) {
        setState(() {
          _stage = _ImportStage.idle;
          _recognizing = false;
        });
      }
    }
  }

  List<Widget> _aiChanges(List<Map<String, dynamic>> candidates) {
    String key(Map<String, dynamic> course) {
      final stable = '${course['stableId'] ?? ''}'.trim();
      if (stable.isNotEmpty) return 'stable:$stable';
      final code = '${course['courseCode'] ?? ''}'.trim();
      return jsonEncode([
        code.isEmpty ? 'name' : 'code',
        code.isEmpty ? '${course['name'] ?? ''}'.trim() : code,
        course['section'],
      ]);
    }

    final paired = <Map<String, dynamic>>{};
    final changes = <Widget>[];
    for (final candidate in candidates) {
      final matches = _courses.where((c) => key(c) == key(candidate)).toList();
      if (matches.length != 1 ||
          candidates.where((c) => key(c) == key(candidate)).length != 1) {
        changes.add(Text('新增或未匹配：${candidate['name']}'));
        continue;
      }
      final before = matches.single;
      paired.add(before);
      final fields = _fieldChanges(before, candidate, const {
        'name': '课程名称',
        'teacher': '教师',
        'courseCode': '课程编码',
        'section': '教学班',
        'pendingReason': '待定说明',
      });
      final oldMeetings = List<Map>.from(before['meetings'] ?? []);
      final newMeetings = List<Map>.from(candidate['meetings'] ?? []);
      if (oldMeetings.length == 1 && newMeetings.length == 1) {
        fields.addAll(
          _fieldChanges(oldMeetings.single, newMeetings.single, const {
            'weekday': '星期',
            'weeks': '周次',
            'startMinute': '开始时间',
            'endMinute': '结束时间',
            'location': '教室',
            'periodIndex': '开始节次',
            'periodCount': '节次跨度',
          }),
        );
      } else {
        String meetingKey(Map meeting) => ScheduleImportMeetingDraft.fromJson(
          Map<String, dynamic>.from(meeting),
        ).meetingKey;
        // Multiple arrangements have no safe positional pairing. Show additions
        // and removals instead of implying that two unrelated rows are the same.
        for (final meeting in oldMeetings) {
          if (!newMeetings.any((m) => meetingKey(m) == meetingKey(meeting))) {
            fields.add(
              Text(
                '原安排未包含：${_summary({
                  'meetings': [meeting],
                })}',
              ),
            );
          }
        }
        for (final meeting in newMeetings) {
          if (!oldMeetings.any((m) => meetingKey(m) == meetingKey(meeting))) {
            fields.add(
              Text(
                'AI 新增安排：${_summary({
                  'meetings': [meeting],
                })}',
              ),
            );
          }
        }
      }
      if (fields.isNotEmpty) {
        changes.add(
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('字段变化 · ${candidate['name']}'),
            initiallyExpanded: true,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: fields,
          ),
        );
      }
    }
    for (final course in _courses.where((c) => !paired.contains(c))) {
      changes.add(Text('AI 结果未匹配：${course['name']}'));
    }
    return [
      const Text('字段对照', style: TextStyle(fontWeight: FontWeight.w600)),
      const Text('按唯一课程编码或同名课程对照，未匹配项请结合完整内容核对。'),
      if (changes.isEmpty) const Text('未发现课程字段变化。') else ...changes,
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _fieldChanges(
    Map before,
    Map after,
    Map<String, String> labels,
  ) {
    String value(String key, dynamic raw) {
      if (raw == null || raw == '' || raw is List && raw.isEmpty) return '待定';
      if (key == 'startMinute' || key == 'endMinute') return _clock(raw);
      if (key == 'weeks' && raw is List) {
        final weeks = List<int>.from(raw)..sort();
        return weeks.join('、');
      }
      return '$raw';
    }

    return [
      for (final label in labels.entries)
        if (value(label.key, before[label.key]) !=
            value(label.key, after[label.key]))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${label.value}\n原：${value(label.key, before[label.key])}\nAI：${value(label.key, after[label.key])}',
            ),
          ),
    ];
  }

  Widget _draftSummaryGroup(
    String title,
    List<Map<String, dynamic>> courses, {
    bool expanded = false,
  }) => ExpansionTile(
    title: Text(title),
    tilePadding: EdgeInsets.zero,
    initiallyExpanded: expanded,
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final course in courses)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${course['name']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if ('${course['teacher'] ?? ''}'.isNotEmpty)
                Text('教师：${course['teacher']}'),
              Text(_summary(course)),
            ],
          ),
        ),
    ],
  );

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
          _stage = _ImportStage.idle;
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
                            itemHeight: null,
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
    if (_needsPortalAI ||
        _busy ||
        _loadingTables ||
        _courses.isEmpty ||
        (_requiresGateReview && !_gateAcknowledged)) {
      return;
    }
    final model = MainStateModel.of(context);
    var committed = false;
    setState(() {
      _stage = _ImportStage.comparing;
      _triedSave = true;
      _error = null;
    });
    try {
      if (_school.text.trim().isEmpty || _term.text.trim().isEmpty) {
        throw const FormatException('请填写学校和学期，再查看导入变化。');
      }
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
        setState(() => _stage = _ImportStage.confirming);
        final choices = await _chooseBindings(diff);
        if (choices == null || !mounted) return;
        bindings = choices;
        setState(() => _stage = _ImportStage.comparing);
        diff = await ScheduleImportService.preview(
          draft,
          mergeTableId: _target,
          periods: periods,
          legacyBindings: bindings,
        );
        if (!mounted) return;
      }
      setState(() => _stage = _ImportStage.confirming);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认导入变化'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ScheduleStatusBadge('新增 ${diff.added.length}'),
                      ScheduleStatusBadge('变更 ${diff.changed.length}'),
                      ScheduleStatusBadge('移除 ${diff.removed.length}'),
                      ScheduleStatusBadge('待定 ${diff.pending.length}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('数量按课程安排统计，待定项可能同时属于新增或变更。'),
                  if (diff.conflicts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '${diff.conflicts.length} 处来源或本地编辑冲突。冲突字段保留本地内容，其余无冲突字段仍可能更新；请核对后手动处理。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
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
      if (accepted != true || !mounted) return;
      setState(() => _stage = _ImportStage.saving);
      final result = await ScheduleImportService.commit(
        draft,
        mergeTableId: _target,
        acceptChanges: true,
        expectedReviewToken: diff.reviewToken,
        legacyBindings: bindings,
        periods: periods,
      );
      committed = true;
      await model.changeclassTable(result.tableId);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = committed
              ? '课表已保存，但页面未能刷新。请返回设置重新选择该课表。'
              : ScheduleFeedback.message(
                  e,
                  fallback: '保存未完成，请重新查看变化后重试。核对内容已保留。',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _stage = _ImportStage.idle);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_needsPortalAI ? 'AI 识别网页课表' : '核对导入课表')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed:
                      _busy ||
                          _loadingTables ||
                          _courses.isEmpty ||
                          _needsPortalAI ||
                          (_requiresGateReview && !_gateAcknowledged)
                      ? null
                      : _save,
                  child: Text(switch (_stage) {
                    _ImportStage.idle => '查看变化并保存',
                    _ImportStage.recognizing => 'AI 正在识别…',
                    _ImportStage.reviewingAI => '等待核对 AI 结果',
                    _ImportStage.comparing => '正在比较导入变化…',
                    _ImportStage.confirming => '等待确认保存',
                    _ImportStage.saving => '正在保存课表…',
                  }),
                ),
                if (_tablesFailed)
                  TextButton(
                    onPressed: _loadingTables ? null : _loadTables,
                    child: const Text('重新读取已有课表'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('请核对课程、周次、钟点和教室。缺失信息保持待定，确认前不会保存。'),
                for (final warning in [
                  ...widget.warnings,
                  ..._preparation.warnings,
                  ..._replacementWarnings,
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(warning),
                  ),
                if (_courses.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('已识别 ${_courses.length} 门课程，请对照原课表检查是否齐全。'),
                  ),
                if (_offersOCR)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _assist(withOCR: true),
                    child: const Text('使用 OCR 复核'),
                  ),
                if (_requiresGateReview)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('我已对照原课表核对以上差异和待定信息'),
                    value: _gateAcknowledged,
                    onChanged: _busy
                        ? null
                        : (value) => setState(
                            () => _gateAcknowledged = value ?? false,
                          ),
                  ),
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
                  AIKeyStatus(revision: _keyRevision),
                if (widget.source == 'school-portal')
                  TextButton(
                    onPressed: _busy ? null : _openAISettings,
                    child: const Text('DeepSeek 设置'),
                  ),
                if (_recognizing) const RecognitionProgress(),
                if (_recognizing)
                  TextButton(
                    onPressed: _cancelRecognition,
                    child: const Text('取消识别'),
                  ),
                if (_beforeAI != null) ...[
                  const Text('保存前可恢复原稿，将撤销本次 AI 结果及采用后的编辑。'),
                  TextButton.icon(
                    onPressed: _busy ? null : _restoreBeforeAI,
                    icon: const Icon(Icons.undo),
                    label: const Text('恢复本次 AI 处理前的内容'),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _school,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {
                    _schoolEdited = true;
                    _applySavedContext();
                  }),
                  decoration: InputDecoration(
                    labelText: '学校',
                    errorText: _triedSave && _school.text.trim().isEmpty
                        ? '请填写学校'
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _term,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {
                    _termEdited = true;
                    _applySavedContext();
                  }),
                  decoration: InputDecoration(
                    labelText: '学期，例如 2026 秋季',
                    errorText: _triedSave && _term.text.trim().isEmpty
                        ? '请填写学期'
                        : null,
                  ),
                ),
                if (_metadataNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_metadataNote!),
                    ),
                  ),
                const SizedBox(height: 16),
                InkWell(
                  key: const ValueKey('first-week-monday'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: _busy
                      ? null
                      : () async {
                          final day = await showDatePicker(
                            context: context,
                            initialDate: _monday,
                            selectableDayPredicate: (day) =>
                                day.weekday == DateTime.monday,
                            helpText: '选择学期第一周的周一',
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2040, 12, 31),
                          );
                          if (day != null && mounted) {
                            setState(() {
                              _monday = day;
                              _mondayEdited = true;
                              _error = null;
                            });
                          }
                        },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: '第一周周一',
                      enabled: !_busy,
                      suffixIcon: const Icon(Icons.calendar_today_outlined),
                      errorText: _triedSave && _monday == null
                          ? '请选择学期第一周的周一'
                          : null,
                    ),
                    child: Text(
                      _monday == null
                          ? '请选择，不能以导入日期代替'
                          : '${_monday!.year}-${_monday!.month}-${_monday!.day}',
                      style: TextStyle(
                        color: _monday == null
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  itemHeight: null,
                  initialValue: _target ?? -1,
                  decoration: const InputDecoration(labelText: '保存到'),
                  items: [
                    const DropdownMenuItem(
                      value: -1,
                      child: Text('自动回到同来源课表／首次新建'),
                    ),
                    for (final table in _tables)
                      DropdownMenuItem(
                        value: table['id'] as int,
                        child: Text('合并到 ${table['name']}'),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _target = v == -1 ? null : v;
                          _applySavedContext();
                        }),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < _courses.length; i++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      title: Text(
                        '${_courses[i]['name'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(_summary(_courses[i])),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _busy ? null : () => _edit(i),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
  bool _showFieldErrors = false;
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
    setState(() => _showFieldErrors = true);
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
      setState(() => _error = '请检查课程名称和起止时间。星期、周次与钟点可保留待定。');
    }
  }

  Future<void> _chooseWeeks(int index) async {
    final current = _meetings[index]['weeks']!.text;
    final selected = current
        .split(RegExp('[,， ]+'))
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    var rangeEnd = selected.fold<int>(20, (a, b) => a > b ? a : b).clamp(1, 60);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '选择周次',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭周次选择',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('按课表勾选。未选择任何周次时保留待定，快捷选择会替换当前选择。'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: rangeEnd,
                        decoration: const InputDecoration(labelText: '快捷选择范围'),
                        items: [
                          for (var week = 1; week <= 60; week++)
                            DropdownMenuItem(
                              value: week,
                              child: Text('第 1–$week 周'),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) update(() => rangeEnd = v);
                        },
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final mode in ['全选', '单周', '双周'])
                            TextButton(
                              onPressed: () => update(() {
                                selected.clear();
                                for (var week = 1; week <= rangeEnd; week++) {
                                  if (mode == '全选' ||
                                      (mode == '单周' && week.isOdd) ||
                                      (mode == '双周' && week.isEven)) {
                                    selected.add(week);
                                  }
                                }
                              }),
                              child: Text(mode),
                            ),
                          TextButton(
                            onPressed: () => update(selected.clear),
                            child: const Text('待定'),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (
                            var week = 1;
                            week <=
                                selected.fold<int>(
                                  rangeEnd,
                                  (a, b) => a > b ? a : b,
                                );
                            week++
                          )
                            FilterChip(
                              label: Text('第 $week 周'),
                              selected: selected.contains(week),
                              onSelected: (v) => update(() {
                                if (v) {
                                  selected.add(week);
                                } else {
                                  selected.remove(week);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () {
                      final weeks = selected.toList()..sort();
                      Navigator.pop(sheetContext, weeks.join(','));
                    },
                    child: const Text('确认周次'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _meetings[index]['weeks']!.text = result);
    }
  }

  Future<void> _chooseClock(int index, String key) async {
    final field = _meetings[index][key]!;
    final minute = _minute(field.text);
    final result = await showTimePicker(
      context: context,
      helpText: key == 'startMinute' ? '选择开始时间' : '选择结束时间',
      initialTime: TimeOfDay(
        hour: (minute ?? 540) ~/ 60,
        minute: (minute ?? 0) % 60,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    // Opening or canceling the picker never fills an unknown time.
    if (result != null && mounted) {
      setState(() => field.text = _clock(result.hour * 60 + result.minute));
    }
  }

  Widget _meetingField(int index, String key, String label) {
    final fields = _meetings[index];
    if (key == 'weekday') {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DropdownButtonFormField<int>(
          initialValue: int.tryParse(fields[key]!.text) ?? 0,
          decoration: const InputDecoration(labelText: '星期'),
          items: [
            const DropdownMenuItem(value: 0, child: Text('待定')),
            for (var day = 1; day <= 7; day++)
              DropdownMenuItem(
                value: day,
                child: Text(
                  '星期${const ['一', '二', '三', '四', '五', '六', '日'][day - 1]}',
                ),
              ),
          ],
          onChanged: (v) => setState(
            () => fields[key]!.text = v == null || v == 0 ? '' : '$v',
          ),
        ),
      );
    }
    final isTime = key == 'startMinute' || key == 'endMinute';
    String? error;
    if (isTime) {
      final start = _minute(fields['startMinute']!.text),
          end = _minute(fields['endMinute']!.text);
      if ((start == null) != (end == null)) {
        error = '请选择完整的起止时间，或清除本组时间。';
      } else if (start != null && end! <= start) {
        error = '结束时间需要晚于开始时间。';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: fields[key],
        readOnly: isTime || key == 'weeks',
        onTap: isTime
            ? () => _chooseClock(index, key)
            : key == 'weeks'
            ? () => _chooseWeeks(index)
            : null,
        decoration: InputDecoration(
          labelText: key == 'weeks' ? '上课周次' : label,
          hintText: key == 'weeks' || isTime ? '待定，点击选择' : null,
          errorText: error,
          suffixIcon: isTime
              ? IconButton(
                  tooltip: '清除本组时间',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    fields['startMinute']!.clear();
                    fields['endMinute']!.clear();
                  }),
                )
              : key == 'weeks'
              ? const Icon(Icons.expand_more)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('编辑课程')),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          for (final e in const {
            'name': '课程名称',
            'courseCode': '课程编码',
            'section': '教学班',
            'teacher': '教师',
            'pendingReason': '待定原因',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: _fields[e.key],
                onChanged: e.key == 'name' ? (_) => setState(() {}) : null,
                decoration: InputDecoration(
                  labelText: e.value,
                  errorText:
                      e.key == 'name' &&
                          _showFieldErrors &&
                          _fields['name']!.text.trim().isEmpty
                      ? '请填写课程名称'
                      : null,
                ),
              ),
            ),
          for (var i = 0; i < _meetings.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      '安排 ${i + 1}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final e in const {
                      'weekday': '星期（1–7）',
                      'weeks': '周次，用逗号分隔；空白为未知',
                      'startMinute': '开始 HH:mm',
                      'endMinute': '结束 HH:mm',
                      'location': '教室',
                    }.entries)
                      _meetingField(i, e.key, e.value),
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
    ),
  );
}
