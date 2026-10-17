import '../../Components/ScheduleFeedbackNotice.dart';
import '../../Components/ScheduleDesign.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../Models/CourseTableModel.dart';
import '../../Utils/ClassTimeUtil.dart';
import '../../Utils/CourseWeekSelection.dart';

import '../../generated/l10n.dart';
import 'package:flutter/material.dart';
import '../../Resources/Constant.dart';
import '../../Resources/Config.dart';
import 'AddCoursePresenter.dart';

import 'Widgets/WeekNodeDialog.dart';
import 'Widgets/WeekTimeNodeDialog.dart';

class AddView extends StatefulWidget {
  const AddView({Key? key}) : super(key: key);

  @override
  _AddViewState createState() => _AddViewState();
}

class _AddViewState extends State<AddView> {
  final AddCoursePresenter _presenter = AddCoursePresenter();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _teacherController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _placeController = TextEditingController();

  final FocusNode nameTextFieldNode = FocusNode();
  final FocusNode teacherTextFieldNode = FocusNode();
  final FocusNode noteTextFieldNode = FocusNode();
  final FocusNode placeTextFieldNode = FocusNode();
  bool _classNameIsValid = true;
  bool _saving = false;
  String? _saveError;
  List<Map>? _periods;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  Future<void> _loadPeriods() async {
    final prefs = await SharedPreferences.getInstance();
    final periods = await CourseTableProvider().getClassTimeList(
      prefs.getInt('tableId') ?? 1,
    );
    if (mounted) setState(() => _periods = periods);
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _teacherController,
      _noteController,
      _placeController,
    ]) {
      controller.dispose();
    }
    for (final node in [
      nameTextFieldNode,
      teacherTextFieldNode,
      noteTextFieldNode,
      placeTextFieldNode,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  String _periodSummary() {
    final start = _node['startClock'];
    final end = _node['endClock'];
    if (start is String &&
        end is String &&
        start.isNotEmpty &&
        end.isNotEmpty) {
      return '$start–$end';
    }
    return ClassTimeUtil.clockRange(
          _periods ?? [],
          _node['startTime'] + 1,
          _node['endTime'] - _node['startTime'],
        ) ??
        ClassTimeUtil.rangeLabel(
          _periods ?? [],
          _node['startTime'] + 1,
          _node['endTime'] - _node['startTime'],
        ) ??
        S
            .of(context)
            .class_duration(
              '${_node['startTime'] + 1}',
              '${_node['endTime'] + 1}',
            );
  }

  // TODO: add multi node in one Widget
  Map _node = {
    'weekTime': 0,
    'startTime': 0,
    'endTime': 0,
    'classroom': '',
    'startWeek': 0,
    'endWeek': Config.MAX_WEEKS - 1,
    'weekType': Constant.FULL_WEEKS,
  };

  @override
  Widget build(BuildContext context) {
    bool resizeEnabled = true;
    if (Platform.operatingSystem == 'ohos') {
      resizeEnabled = false;
    }

    return Scaffold(
      resizeToAvoidBottomInset: resizeEnabled,
      appBar: AppBar(title: const Text('手动添加课程')),
      body: _periods == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  const ScheduleIntro(
                    icon: Icons.add_rounded,
                    eyebrow: '手动添加课程',
                    title: '课程信息',
                    description: '补充课程名称与教师，再选择上课安排。',
                  ),
                  const SizedBox(height: scheduleTitleContentGap),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      // focusedBorder: UnderlineInputBorder(
                      //   borderSide:
                      //       BorderSide(color: Theme.of(context).primaryColor),
                      // ),
                      icon: const Icon(Icons.book),
                      hintText: S.of(context).class_name,
                      errorText: _classNameIsValid
                          ? null
                          : S.of(context).class_name_empty,
                    ),
                    onEditingComplete: () => FocusScope.of(
                      context,
                    ).requestFocus(teacherTextFieldNode),
                  ),
                  const Padding(padding: EdgeInsets.all(5)),
                  TextField(
                    controller: _teacherController,
                    focusNode: teacherTextFieldNode,
                    decoration: InputDecoration(
                      // focusedBorder: UnderlineInputBorder(
                      //   borderSide:
                      //       BorderSide(color: Theme.of(context).primaryColor),
                      // ),
                      icon: const Icon(Icons.account_circle),
                      hintText: S.of(context).class_teacher,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.all(10)),
                  TextField(
                    controller: _noteController,
                    focusNode: noteTextFieldNode,
                    keyboardType: TextInputType.multiline,
                    maxLines: null,
                    decoration: InputDecoration(
                      // focusedBorder: UnderlineInputBorder(
                      //   borderSide:
                      //       BorderSide(color: Theme.of(context).primaryColor),
                      // ),
                      icon: const Icon(Icons.sticky_note_2),
                      hintText: S.of(context).class_info,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.all(10)),
                  const Divider(),
                  const Padding(padding: EdgeInsets.all(10)),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.calendar_month),
                      const Padding(padding: EdgeInsets.all(8)),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: '上课周',
                              suffixIcon: Icon(Icons.expand_more_rounded),
                            ),
                            child: Text(
                              CourseWeekSelection.summary(_node),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          onTap: () async {
                            final newNode = await showDialog<Map>(
                              context: context,
                              barrierDismissible: false,
                              builder: (BuildContext context) {
                                return WeekNodeDialog(node: _node);
                              },
                            );
                            if (newNode == null || !mounted) return;
                            setState(() {
                              _node = newNode;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.all(10)),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.access_time),
                      const Padding(padding: EdgeInsets.all(8)),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: '上课时间',
                              suffixIcon: Icon(Icons.expand_more_rounded),
                            ),
                            child: Text(
                              Constant.WEEK_WITHOUT_BIAS[_node['weekTime']] +
                                  ' ' +
                                  _periodSummary() +
                                  ' ' +
                                  (_node['classroom']),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          onTap: () async {
                            final newNode = await showDialog<Map>(
                              context: context,
                              barrierDismissible: false,
                              builder: (BuildContext context) {
                                return WeekTimeNodeDialog(
                                  node: _node,
                                  periods: _periods!,
                                );
                              },
                            );
                            if (newNode == null || !mounted) return;
                            setState(() {
                              _node = newNode;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.all(5)),
                  TextField(
                    controller: _placeController,
                    focusNode: placeTextFieldNode,
                    decoration: InputDecoration(
                      // focusedBorder: UnderlineInputBorder(
                      //   borderSide:
                      //       BorderSide(color: Theme.of(context).primaryColor),
                      // ),
                      icon: const Icon(Icons.place),
                      hintText: S.of(context).class_room,
                    ),
                    onChanged: (val) {
                      _node['classroom'] = val;
                    },
                  ),
                  const Padding(padding: EdgeInsets.all(10)),
                  const Padding(padding: EdgeInsets.all(10)),
                  if (_saveError != null) ...[
                    ScheduleInlineFeedback(message: _saveError!),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      child: Text(
                        _saving
                            ? '正在保存…'
                            : _saveError != null
                            ? '重试保存'
                            : S.of(context).add_class,
                      ),
                      onPressed: _saving
                          ? null
                          : () async {
                              if (_nameController.text.trim().isEmpty) {
                                setState(() {
                                  _classNameIsValid = false;
                                });
                                return;
                              }
                              if (_node['startTime'] > _node['endTime']) {
                                setState(
                                  () => _saveError = '开始时间需要早于结束时间，请调整上课时间。',
                                );
                                return;
                              }
                              if (_node['startWeek'] > _node['endWeek']) {
                                setState(
                                  () => _saveError = '开始周不能晚于结束周，请调整上课周次。',
                                );
                                return;
                              }
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _saving = true;
                                _saveError = null;
                              });
                              try {
                                final result = await _presenter.addCourse(
                                  context,
                                  _nameController.text.trim(),
                                  _teacherController.text.trim(),
                                  _noteController.text.trim(),
                                  [_node],
                                );
                                if (!context.mounted) return;
                                if (result) {
                                  Navigator.of(context).pop(true);
                                } else {
                                  setState(
                                    () => _saveError = '课程未保存，请检查上课周次后重试。',
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  setState(() => _saveError = '保存失败，请重试。');
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _saving = false);
                                }
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
