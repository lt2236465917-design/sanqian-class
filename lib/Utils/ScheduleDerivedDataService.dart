import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Models/PersonalSchedule.dart';

class ScheduleDerivedDataService {
  static const channel = MethodChannel('sanqian/schedule_import');
  static Future<void> _tail = Future.value();

  static String _revision(String content) {
    var value = 2166136261;
    for (final byte in utf8.encode(content)) {
      value = ((value ^ byte) * 16777619) & 0xffffffff;
    }
    return value.toRadixString(16);
  }

  static Map<String, dynamic> snapshot(PersonalSchedule schedule) {
    int shanghaiInstant(DateTime local) => DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    ).subtract(const Duration(hours: 8)).millisecondsSinceEpoch;
    final events =
        schedule.occurrences
            .where(
              (e) =>
                  e.course.id != null &&
                  e.start != null &&
                  e.end != null &&
                  e.end!.isAfter(e.start!),
            )
            .map(
              (e) => {
                'id': '${schedule.tableId}.${e.course.id}.${e.week}',
                'courseId': e.course.id,
                'tableId': schedule.tableId,
                'title': e.course.name ?? '',
                'classroom': e.course.classroom ?? '',
                'startMs': shanghaiInstant(e.start!),
                'endMs': shanghaiInstant(e.end!),
                'clockRange': e.clockRange ?? '',
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['startMs'] as int).compareTo(b['startMs'] as int),
          );
    return {
      'schemaVersion': 1,
      'tableId': schedule.tableId,
      'tableName': schedule.name,
      'timeZone': 'Asia/Shanghai',
      'revision': _revision(jsonEncode(events)),
      'generatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'occurrences': events,
    };
  }

  static Future<Map<String, dynamic>> sync(PersonalSchedule schedule) async {
    final previous = _tail;
    final operation = () async {
      await previous;
      final preferences = await SharedPreferences.getInstance();
      final leads = [
        15,
        180,
        1440,
      ].where((n) => preferences.getBool('reminder_$n') ?? false).toList();
      final data = snapshot(schedule)..['leadMinutes'] = leads;
      try {
        final result =
            await channel.invokeMapMethod<String, dynamic>(
              'syncDerivedData',
              data,
            ) ??
            {};
        await preferences.setString('reminder_status', jsonEncode(result));
        return result;
      } on MissingPluginException {
        return <String, dynamic>{};
      }
    }();
    _tail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
