import 'dart:convert';
import 'package:flutter/material.dart';
import '../../Utils/States/MainState.dart';
import '../../Models/CourseModel.dart';
import '../../Resources/Constant.dart';
import '../../Utils/CourseWeekSelection.dart';
import '../../core/widget_data/utils/widget_refresh_helper.dart';

class AddCoursePresenter {
  Future<bool> addCourse(
    BuildContext context,
    String name,
    String teacher,
    String info,
    List<Map> nodes,
  ) async {
    int tableId = await MainStateModel.of(context).getClassTable();
    // initialize
    if (tableId == 0) {
      tableId = 1;
      await MainStateModel.of(context).changeclassTable(1);
    }
    for (Map node in nodes) {
      final weeks = CourseWeekSelection.weeks(node);
      if (weeks.isEmpty) return false;
      Course course = Course(
        tableId,
        name,
        jsonEncode(weeks),
        node['weekTime'] + 1,
        node['startTime'] + 1,
        node['endTime'] - node['startTime'],
        Constant.ADD_MANUALLY,
        classroom: node['classroom'] == '' ? null : node['classroom'],
        teacher: teacher == '' ? null : teacher,
        info: info,
      );
      CourseProvider courseProvider = CourseProvider();
      course = await courseProvider.insert(course);
      if (course.id == null) return false;
    }

    // 刷新 Widget
    await WidgetRefreshHelper.refreshAfterCourseAdded();

    return true;
  }
}
