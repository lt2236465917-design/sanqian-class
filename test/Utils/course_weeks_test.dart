import 'package:flutter_test/flutter_test.dart';
import 'package:sanqian_class/Models/CourseModel.dart';
import 'package:sanqian_class/Models/ScheduleModel.dart';
import 'package:sanqian_class/Resources/Constant.dart';
import 'package:sanqian_class/Utils/CourseWeeks.dart';

void main() {
  test('weeks parser accepts only sorted unique in-range weeks', () {
    expect(CourseWeeks.parse(null), isEmpty);
    expect(CourseWeeks.parse(''), isEmpty);
    expect(CourseWeeks.parse('[]'), isEmpty);
    expect(CourseWeeks.parse('{'), isEmpty);
    expect(CourseWeeks.parse('null'), isEmpty);
    expect(CourseWeeks.parse('["a","b"]'), isEmpty);
    expect(CourseWeeks.parse('["1","2","2","0","26"]'), [1, 2]);
    expect(CourseWeeks.parse('[3, 3, 1, 99, -1, "4"]'), [1, 3, 4]);
    expect(CourseWeeks.firstAddable(null), isNull);
    expect(CourseWeeks.firstAddable('[2, 2, 1]'), 1);
  });

  test('schedule classification keeps pending courses without throwing', () {
    final model = ScheduleModel([
      Course(1, '待定', null, 1, 1, 1, 0),
      Course(1, '空白', '', 2, 1, 1, 0),
      Course(1, '空数组', '[]', 3, 1, 1, 0),
      Course(1, '坏数据', '{', 4, 1, 1, 0),
      Course(1, '字符串周次', '["5","5","30"]', 5, 1, 1, 0),
      Course(1, '正常', '[1,2,2]', 1, 1, 1, 0),
      Course(1, '过期讲座', '[1]', 1, 1, 1, Constant.ADD_BY_LECTURE),
      Course(1, '未排时间', '[]', 0, 0, 0, 0),
    ], 5);
    expect(() => model.init(), returnsNormally);
    expect(model.activeCourses.map((c) => c.name), ['字符串周次']);
    expect(model.freeCourses.map((c) => c.name), ['未排时间']);
    expect(
      model.hideCourses.map((c) => c.name),
      containsAll(['待定', '空白', '空数组', '坏数据', '正常']),
    );
    expect(model.hideCourses.map((c) => c.name), isNot(contains('过期讲座')));
  });
}
