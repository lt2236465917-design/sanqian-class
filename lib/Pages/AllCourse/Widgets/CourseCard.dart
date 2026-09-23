import 'package:dio/dio.dart';
import '../../../generated/l10n.dart';
import 'package:flutter/material.dart';

// import 'package:flutter_linkify/flutter_linkify.dart';
// import 'package:url_launcher/url_launcher.dart';
import 'package:scoped_model/scoped_model.dart';
import '../../../Models/CourseModel.dart';
import '../../../Utils/States/MainState.dart';
import '../../../Components/Toast.dart';
import '../../../Components/TransBgTextButton.dart';
import '../../../Resources/Config.dart';
import '../../../Resources/Constant.dart';
import '../../../Resources/Url.dart';
import '../../../Utils/CourseWeeks.dart';

//TODO: 全校课程

class CourseCardCopy {
  final String time;
  final String teacher;
  final String detail;

  const CourseCardCopy(this.time, this.teacher, this.detail);

  static CourseCardCopy of(Course course, S labels) {
    final weekday = course.weekTime;
    final day = weekday != null &&
            weekday > 0 &&
            weekday < Constant.WEEK_WITH_BIAS.length
        ? Constant.WEEK_WITH_BIAS[weekday]
        : '星期待定';
    final start = course.startTime;
    final count = course.timeCount ?? 0;
    final period = start == null || start <= 0
        ? labels.lecture_no_time
        : labels.class_duration('$start', '${start + count}');
    final weeks = CourseWeeks.parse(course.weeks);
    final weekText = weeks.isEmpty ? '周次待定' : weeks.map(labels.week).join(' ');
    final room = (course.classroom ?? '').trim();
    final place = room.isEmpty ? labels.lecture_no_classroom : room;
    final teacherName = (course.teacher ?? '').trim();
    final info = (course.info ?? '').trim();
    return CourseCardCopy(
      '时间&地点： $day $period $weekText $place',
      '授课教师：${teacherName.isEmpty ? labels.lecture_no_teacher : teacherName}',
      info.isEmpty ? labels.unknown_info : info,
    );
  }
}

class CourseCard extends StatefulWidget {
  final Course course;
  final int count;

  const CourseCard({Key? key, required this.course, required this.count})
      : super(key: key);

  @override
  _CourseCardState createState() => _CourseCardState();
}

class _CourseCardState extends State<CourseCard> {
  bool added = false;
  int count = 0;
  bool collapsed = true;

  @override
  void initState() {
    super.initState();
    count = widget.count;
    checkAdded();
  }

  checkAdded() async {
    widget.course.tableId =
        await ScopedModel.of<MainStateModel>(context).getClassTable();
    CourseProvider courseProvider = CourseProvider();
    bool rst = await courseProvider.checkHasClassByName(
        widget.course.tableId ?? 0, widget.course.name ?? '');
    if (rst) {
      setState(() {
        added = true;
      });
    }
  }

  addCourse() async {
    final weekInt = CourseWeeks.firstAddable(widget.course.weeks);
    if (weekInt == null || weekInt > Config.MAX_WEEKS) {
      Toast.showToast(S.of(context).lecture_add_fail_toast, context);
      return;
    }
    CourseProvider courseProvider = CourseProvider();
    await courseProvider.insert(widget.course);
    Dio dio = Dio();
    await dio.get(Url.URL_BACKEND + '/addCount',
        queryParameters: {'id': widget.course.courseId});
    // print(response);
    Toast.showToast(S.of(context).lecture_add_success_toast, context);
    setState(() {
      added = true;
      count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final labels = S.of(context);
    final course = widget.course;
    final copy = CourseCardCopy.of(course, labels);
    final time = copy.time;
    final teacher = copy.teacher;
    final detail = copy.detail;
    return Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 5, right: 5),
        child: Card(
          child: ExpansionTile(
            onExpansionChanged: (val) => setState(() {
              collapsed = !collapsed;
            }),
            // textColor: Theme.of(context).brightness == Brightness.light
            //           ? Theme.of(context).primaryColor
            //           : Colors.white,
            textColor: Colors.black,
            iconColor: Colors.grey,
            title: Column(
              children: [
                // Text(widget.course.name ?? S.of(context).lecture_no_name),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      widget.course.name ?? S.of(context).lecture_no_name,
                      overflow: collapsed
                          ? TextOverflow.ellipsis
                          : TextOverflow.visible,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          time,
                          maxLines: 2,
                          overflow: collapsed
                              ? TextOverflow.ellipsis
                              : TextOverflow.visible,
                        ),
                        Text(
                          teacher,
                          overflow: collapsed
                              ? TextOverflow.ellipsis
                              : TextOverflow.visible,
                        ),
                      ],
                    )),
              ],
            ),
            children: <Widget>[
              Container(
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.all(15.0),
                  child:
                      Text(detail)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  added
                      ? TransBgTextButton(
                          color: Colors.grey,
                          child: Text(S.of(context).lecture_added(count)),
                          onPressed: () {
                            Toast.showToast(
                                S.of(context).lecture_added_toast, context);
                          },
                        )
                      : TransBgTextButton(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Theme.of(context).primaryColor
                                  : Colors.white,
                          child: Text(S.of(context).lecture_add(count)),
                          onPressed: () async {
                            addCourse();
                          },
                        ),
                ],
              ),
            ],
          ),
          // Column(
          //   mainAxisSize: MainAxisSize.min,
          //   children: <Widget>[
          //     ListTile(
          //       // leading: Icon(Icons.album),
          //       title:
          //           Text(widget.course.name ?? S.of(context).lecture_no_name),
          //       subtitle: Text(subtitle),
          //     ),
          //     Container(
          //       alignment: Alignment.topLeft,
          //       padding: const EdgeInsets.all(15.0),
          //       child: SelectableLinkify(
          //         onOpen: (link) async {
          //           String url =
          //               link.url.replaceAll(RegExp('[^\x00-\xff]'), '');
          //           if (await canLaunch(url)) {
          //             await launch(url);
          //           } else {
          //             Toast.showToast(
          //                 S.of(context).network_error_toast, context);
          //           }
          //         },
          //         text: widget.course.info ?? S.of(context).unknown_info,
          //         linkStyle: TextStyle(color: Theme.of(context).primaryColor),
          //         options: const LinkifyOptions(humanize: false),
          //       ),
          //     ),
          //     Row(
          //       mainAxisAlignment: MainAxisAlignment.end,
          //       children: <Widget>[added
          //                 ? TextButton(
          //                     style: TextButton.styleFrom(primary: Colors.grey),
          //                     child: Text(S.of(context).lecture_added(count)),
          //                     onPressed: () {
          //                       Toast.showToast(
          //                           S.of(context).lecture_added_toast, context);
          //                     },
          //                   )
          //                 : TextButton(
          //                     style: TextButton.styleFrom(
          //                         primary: Theme.of(context).primaryColor),
          //                     child: Text(S.of(context).lecture_add(count)),
          //                     onPressed: () async {
          //                         addCourse();
          //                     },
          //                   ),
          //       ],
          //     ),
          //   ],
          // ),
        ));
  }
}
