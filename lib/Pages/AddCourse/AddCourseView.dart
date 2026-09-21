import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../Models/CourseTableModel.dart';
import '../../Utils/ClassTimeUtil.dart';
import '../../Utils/CourseWeekSelection.dart';

import '../../generated/l10n.dart';
import 'package:flutter/material.dart';
import '../../Resources/Constant.dart';
import '../../Resources/Config.dart';
import '../../Components/Dialog.dart';
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

  String _periodSummary() =>
      ClassTimeUtil.clockRange(
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
      appBar: AppBar(title: Text(S.of(context).add_manually_title)),
      body: _periods == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Builder(
                builder: (BuildContext context) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(10),
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: <Widget>[
                        const Padding(padding: EdgeInsets.all(5)),
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
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            child: Text(
                              _saving ? '正在保存…' : S.of(context).add_class,
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
                                      showDialog<String>(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return MDialog(
                                            S
                                                .of(context)
                                                .class_num_invalid_dialog_title,
                                            Text(
                                              S
                                                  .of(context)
                                                  .class_num_invalid_dialog_content,
                                            ),
                                            widgetOKAction: () {
                                              Navigator.of(context).pop();
                                            },
                                          );
                                        },
                                      );
                                      return;
                                    }
                                    if (_node['startWeek'] > _node['endWeek']) {
                                      showDialog<String>(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return MDialog(
                                            S
                                                .of(context)
                                                .week_num_invalid_dialog_title,
                                            Text(
                                              S
                                                  .of(context)
                                                  .week_num_invalid_dialog_content,
                                            ),
                                            widgetOKAction: () {
                                              Navigator.of(context).pop();
                                            },
                                          );
                                        },
                                      );
                                      return;
                                    }
                                    FocusScope.of(context).unfocus();
                                    setState(() => _saving = true);
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
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('课程未保存，请检查上课周次后重试。'),
                                          ),
                                        );
                                      }
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('保存失败，请重试。'),
                                          ),
                                        );
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
                  );
                },
              ),
            ),
    );
  }
}
