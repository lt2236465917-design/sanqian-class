import 'dart:convert';
import 'dart:io';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Models/PersonalSchedule.dart';
import 'IosCalendar.dart';

class CalendarExportException implements Exception {
  final String message;
  final int savedCount;
  final bool permissionDenied;
  const CalendarExportException(
    this.message, {
    this.savedCount = 0,
    this.permissionDenied = false,
  });
}

class ScheduleCalendarExporter {
  static const settingsChannel = MethodChannel('sanqian/settings');
  final CalendarClient calendar;
  final Future<bool> Function()? requestAccess;

  ScheduleCalendarExporter({CalendarClient? calendar, this.requestAccess})
    : calendar = calendar ?? _defaultCalendar();

  static CalendarClient _defaultCalendar() {
    DeviceCalendarPlugin(); // Initializes the time-zone database.
    return Platform.isIOS ? IosCalendar() : PluginCalendar();
  }

  static List<CourseOccurrence> exportable(PersonalSchedule schedule) =>
      schedule.occurrences
          .where(
            (c) => c.start != null && c.end != null && c.end!.isAfter(c.start!),
          )
          .toList();

  Future<int> export(PersonalSchedule schedule) async {
    final entries = exportable(schedule);
    if (entries.isEmpty) {
      throw const CalendarExportException('没有可导出的课程，请先填写上课日期和起止时间。');
    }
    var saved = 0;
    try {
      final permission = await calendar.hasPermissions();
      if (!permission.isSuccess || permission.data != true) {
        final granted = requestAccess != null
            ? await requestAccess!()
            : Platform.isIOS
            ? await settingsChannel.invokeMethod<bool>(
                    'requestCalendarAccess',
                  ) ==
                  true
            : (await calendar.requestPermissions()).data == true;
        if (!granted) {
          throw const CalendarExportException(
            '日历权限未开启，请在系统设置中允许访问日历后重试。',
            permissionDenied: true,
          );
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final key = 'calendarExport.${schedule.tableId}';
      final stored = prefs.getString(key);
      final state = stored == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(stored));
      final calendars = await calendar.retrieveCalendars();
      if (!calendars.isSuccess) {
        throw const CalendarExportException('无法读取系统日历，请稍后重试。');
      }
      String? calendarId = state['calendarId'] as String?;
      final existing = calendars.data!.where(
        (c) => c.id == calendarId && c.isReadOnly != true,
      );
      if (calendarId == null || existing.isEmpty) {
        final created = await calendar.createCalendar(
          '三千上课 · ${schedule.name}',
        );
        if (!created.isSuccess) {
          throw const CalendarExportException('无法创建课程日历，请检查系统日历账户是否可用。');
        }
        calendarId = created.data!;
        state['calendarId'] = calendarId;
        state['events'] = <String, String>{};
        if (!await prefs.setString(key, jsonEncode(state))) {
          throw const CalendarExportException('无法保存导出记录，请稍后重试。');
        }
      }
      final eventIds = Map<String, dynamic>.from(state['events'] as Map? ?? {});
      final existingEvents = await calendar.retrieveEvents(
        calendarId,
        RetrieveEventsParams(
          startDate: entries.first.date,
          endDate: entries.last.date.add(const Duration(days: 2)),
        ),
      );
      if (!existingEvents.isSuccess) {
        throw const CalendarExportException('无法核对已导出的课程，请稍后重试。');
      }
      final liveIds = existingEvents.data!.map((e) => e.eventId).toSet();
      final location = timeZoneDatabase.get('Asia/Shanghai');
      TZDateTime schoolTime(DateTime date) => TZDateTime(
        location,
        date.year,
        date.month,
        date.day,
        date.hour,
        date.minute,
      );
      for (final entry in entries) {
        final course = entry.course;
        // A course row and teaching week remain stable when its time or room changes.
        final identity =
            '${course.id ?? '${course.name}:${course.weekTime}:${course.startTime}'}:${entry.week}';
        final previousId = eventIds[identity] as String?;
        final result = await calendar.createOrUpdateEvent(
          Event(
            calendarId,
            eventId: liveIds.contains(previousId) ? previousId : null,
            title: course.name,
            start: schoolTime(entry.start!),
            end: schoolTime(entry.end!),
            location: course.classroom,
            description: [
              if ((course.teacher ?? '').isNotEmpty) '教师：${course.teacher}',
              if ((course.info ?? '').isNotEmpty) course.info!,
              '来自三千上课 · 第 ${entry.week} 周',
            ].join('\n'),
          ),
        );
        if (result == null || !result.isSuccess) {
          throw CalendarExportException(
            '部分课程写入失败，请重试；已导出的课程会更新，不会重复添加。',
            savedCount: saved,
          );
        }
        saved++;
        eventIds[identity] = result.data!;
        state['events'] = eventIds;
        if (!await prefs.setString(key, jsonEncode(state))) {
          throw CalendarExportException(
            '课程已写入，但无法保存导出记录，请先检查系统日历。',
            savedCount: saved,
          );
        }
      }
      return saved;
    } on CalendarExportException {
      rethrow;
    } catch (_) {
      throw CalendarExportException(
        '导出失败，请检查日历权限和系统日历账户后重试。',
        savedCount: saved,
      );
    }
  }
}
