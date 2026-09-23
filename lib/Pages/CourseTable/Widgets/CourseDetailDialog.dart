import '../../../generated/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../Models/CourseModel.dart';
import '../../../Resources/Constant.dart';
import '../../../Components/Dialog.dart';
import '../../../Components/Toast.dart';
import '../../../Utils/ClassTimeUtil.dart';
import '../../../Utils/CourseWeeks.dart';

class CourseDetailDialog extends StatelessWidget {
  final VoidCallback? onPressed;
  final Course course;
  final bool isActive;
  final List<Map> classTimeList;

  const CourseDetailDialog(this.course, this.isActive, this.onPressed,
      {Key? key, this.classTimeList = Constant.CLASS_TIME_LIST})
      : super(key: key);

  String _getWeekListString(BuildContext context) {
    final weekList = CourseWeeks.parse(course.weeks);
    if (weekList.isEmpty) return '周次待定';
    if (weekList.length == 1) return S.of(context).week(weekList[0]);
    String base = S.of(context).week_duration(
        weekList[0].toString(), weekList[weekList.length - 1].toString());
    var contiguous = true;
    for (int i = 1; i < weekList.length; i++) {
      if (weekList[i] - weekList[0] != i) {
        contiguous = false;
        break;
      }
    }
    if (contiguous) return base;
    var alternating = true;
    for (int i = 1; i < weekList.length; i++) {
      if (weekList[i] - weekList[0] != 2 * i) {
        alternating = false;
        break;
      }
    }
    if (alternating) {
      if (weekList[0] % 2 == 0) {
        return base + " " + S.of(context).double_week;
      } else {
        return base + " " + S.of(context).single_week;
      }
    }
    return weekList.map((week) => S.of(context).week(week)).join(' ');
  }

  Widget linkifyText(context, String text) {
    return SelectableLinkify(
      onOpen: (link) async {
        String url = link.url.replaceAll(RegExp('[^\x00-\xff]'), '');
        if (await canLaunch(url)) {
          await launch(url);
        } else {
          Toast.showToast(S.of(context).network_error_toast, context);
        }
      },
      text: text,
      style: const TextStyle(fontSize: 16),
      linkStyle: TextStyle(
          color: Theme.of(context).brightness == Brightness.light
              ? Theme.of(context).primaryColor
              : Colors.white),
      options: const LinkifyOptions(humanize: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekday = course.weekTime;
    final weekdayKnown = weekday != null &&
        weekday > 0 &&
        weekday < Constant.WEEK_WITH_BIAS.length;
    String weekString;
    if (!weekdayKnown) {
      weekString = '时间待定';
    } else {
      weekString = Constant.WEEK_WITH_BIAS[weekday] +
          ' ' +
          S.of(context).class_duration('${course.startTime ?? 0}',
              '${(course.startTime ?? 0) + (course.timeCount ?? 0)}');
      final periodLabel = ClassTimeUtil.rangeLabel(
          classTimeList, course.startTime ?? 0, course.timeCount ?? 0);
      if (periodLabel != null) {
        weekString = '${Constant.WEEK_WITH_BIAS[weekday]} $periodLabel';
        final clockRange = ClassTimeUtil.clockRange(
            classTimeList, course.startTime ?? 0, course.timeCount ?? 0);
        if (clockRange != null) weekString += '\n$clockRange';
      }
    }

    String weekListString = _getWeekListString(context);

    String importTypeStr = '';
    switch (course.importType) {
      case Constant.ADD_BY_IMPORT:
        importTypeStr = S.of(context).import_auto;
        break;
      case Constant.ADD_MANUALLY:
        importTypeStr = S.of(context).import_manually;
        break;
      case Constant.ADD_BY_LECTURE:
        importTypeStr = S.of(context).import_from_lecture;
        break;
    }

    return MDialog(
      (isActive || course.weekTime == 0 ? '' : S.of(context).not_this_week) + course.name!,
      SingleChildScrollView(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: [
            const Icon(Icons.location_on),
            const Padding(padding: EdgeInsets.only(left: 5)),
            Flexible(
                child: linkifyText(
                    context,
                    course.classroom == ""
                        ? S.of(context).unknown_place
                        : course.classroom ?? S.of(context).unknown_place)),
          ]),
          const Padding(padding: EdgeInsets.only(bottom: 10)),
          Row(children: [
            const Icon(Icons.account_circle),
            const Padding(padding: EdgeInsets.only(left: 5)),
            Flexible(child: linkifyText(context, course.teacher ?? '')),
          ]),
          const Padding(padding: EdgeInsets.only(bottom: 10)),
          Row(children: [
            const Icon(Icons.access_time),
            const Padding(padding: EdgeInsets.only(left: 5)),
            Flexible(child: linkifyText(context, weekString)),
          ]),
          const Padding(padding: EdgeInsets.only(bottom: 10)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.event),
            const Padding(padding: EdgeInsets.only(left: 5)),
            Flexible(child: linkifyText(context, weekListString)),
          ]),
          const Padding(padding: EdgeInsets.only(bottom: 10)),
          Row(children: [
            const Icon(Icons.settings_suggest),
            const Padding(padding: EdgeInsets.only(left: 5)),
            Flexible(child: linkifyText(context, importTypeStr)),
          ]),
          const Padding(padding: EdgeInsets.only(bottom: 10)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.description),
            const Padding(padding: EdgeInsets.only(left: 5)),
            Flexible(
                child: linkifyText(
                    context,
                    course.info == ""
                        ? S.of(context).unknown_info
                        : course.info ?? S.of(context).unknown_info)),
          ]),
        ],
      )),
      widgetOKAction: onPressed,
    );
  }
}
