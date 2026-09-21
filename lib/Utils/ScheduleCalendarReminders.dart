import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_calendar/device_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'IosCalendar.dart';

/// Reconciles dated occurrences, never weekly recurrence rules or a rolling queue.
/// The journal is persisted before writes so interrupted saves can be rediscovered.
class ScheduleCalendarReminders {
  static const stateKey = 'calendarReminders.v1';
  final ReminderCalendarClient calendar;
  final DateTime Function() now;

  ScheduleCalendarReminders({
    ReminderCalendarClient? calendar,
    DateTime Function()? now,
  }) : calendar = calendar ?? defaultCalendar(),
       now = now ?? DateTime.now;

  static ReminderCalendarClient defaultCalendar() {
    DeviceCalendarPlugin(); // Initializes the time-zone database.
    return Platform.isIOS ? IosCalendar() : PluginCalendar();
  }

  static Future<bool> requestPermission() async {
    final result = await defaultCalendar().requestPermissions();
    return result.isSuccess && result.data == true;
  }

  Future<Map<String, dynamic>> sync(
    List<Map<String, dynamic>> occurrences,
    List<int> leads,
  ) async {
    var count = 0, supplements = 0;
    Map<String, dynamic> status({String? message, bool denied = false}) => {
      'mode': 'calendar',
      'synced': message == null,
      'count': count,
      'supplements': supplements,
      'failed': message == null ? 0 : 1,
      'permission': denied ? 'denied' : 'authorized',
      if (message != null) 'message': message,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(stateKey);
      final state = saved == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(saved));
      final instant = now().millisecondsSinceEpoch;
      final activeLeads =
          leads.where((v) => const [15, 180, 1440].contains(v)).toSet().toList()
            ..sort();
      final desired = <String, Map<String, dynamic>>{};
      for (final entry in occurrences) {
        final start = entry['startMs'] as int;
        final end = entry['endMs'] as int;
        final pending = activeLeads
            .where((m) => start - m * 60000 > instant)
            .toList();
        if (end > start && pending.isNotEmpty) {
          desired[entry['id'] as String] = {...entry, 'leads': pending};
        }
      }
      // With no previously owned events there is nothing to remove or authorize.
      if (desired.isEmpty && state.isEmpty) return status();
      final permission = await calendar.hasPermissions();
      if (!permission.isSuccess || permission.data != true) {
        return status(denied: true, message: '请允许访问日历后重试，旧提醒可能仍然生效。');
      }
      Future<void> persist() async {
        if (!await prefs.setString(stateKey, jsonEncode(state))) {
          throw const _CalendarFailure('无法保存日历同步记录，请重试。');
        }
      }

      if (state['owner'] == null) {
        state['owner'] = List.generate(
          16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        await persist();
      }
      final owner = state['owner'] as String;
      final prefix = '[sanqian-reminder:$owner:';
      String? keyOf(Event e) {
        final line = (e.description ?? '').split('\n').last;
        return line.startsWith(prefix) && line.endsWith(']')
            ? line.substring(prefix.length, line.length - 1)
            : null;
      }

      final name = '三千上课 · 上课提醒 · ${owner.substring(0, 8)}';
      final calendars = _require(
        await calendar.retrieveCalendars(),
        '无法读取系统日历，请重试。',
      );
      Calendar? target;
      for (final c in calendars) {
        if (c.id == state['calendarId'] ||
            (state['calendarId'] == null &&
                c.name == name &&
                c.accountType == 'LOCAL')) {
          target = c;
          break;
        }
      }
      if (target?.isReadOnly == true ||
          (target != null && target.accountType != 'LOCAL')) {
        throw const _CalendarFailure('提醒日历不再是可写入的本机日历，请检查系统日历后重试。');
      }
      if (target != null) state['calendarId'] = target.id;
      if (target == null && desired.isEmpty) {
        // The user deleted the dedicated calendar, so its events no longer exist.
        state.remove('calendarId');
        state['events'] = <String, String>{};
        await persist();
        return status();
      }
      if (target == null) {
        final id = _require(
          await calendar.createCalendar(name, localAccountName: '三千上课本机提醒'),
          '无法创建本机提醒日历，请先检查系统日历是否可用。',
        );
        state['calendarId'] = id;
        state['events'] = <String, String>{};
        await persist();
        // Never silently fall back to a cloud account.
        final check = _require(
          await calendar.retrieveCalendars(),
          '无法核对提醒日历，请重试。',
        );
        if (!check.any(
          (c) => c.id == id && c.accountType == 'LOCAL' && c.isReadOnly != true,
        )) {
          throw const _CalendarFailure('系统未提供可用的本机日历，尚未写入课程提醒。');
        }
      }
      final calendarId = state['calendarId'] as String;
      final journal = Map<String, dynamic>.from(state['events'] as Map? ?? {});
      for (final entry in desired.values) {
        final from = (entry['startMs'] as int) - 86400000;
        final to = (entry['endMs'] as int) + 86400000;
        state['from'] = min(state['from'] as int? ?? from, from);
        state['to'] = max(state['to'] as int? ?? to, to);
      }
      await persist(); // The recovery range must exist before the first event save.
      final existing = <String, Event>{};
      Future<void> collect(RetrieveEventsParams params) async {
        for (final e in _require(
          await calendar.retrieveEvents(calendarId, params),
          '无法核对已写入的提醒，请重试。',
        )) {
          if (e.eventId != null &&
              e.calendarId == calendarId &&
              keyOf(e) != null) {
            existing[e.eventId!] = e;
          }
        }
      }

      if (state['from'] != null) {
        // EventKit limits date-range queries; querying in yearly chunks also
        // recovers writes interrupted before their returned ID was journaled.
        var from = state['from'] as int;
        final end = state['to'] as int;
        while (from < end) {
          final to = min(from + 365 * 86400000, end);
          await collect(
            RetrieveEventsParams(
              startDate: DateTime.fromMillisecondsSinceEpoch(from),
              endDate: DateTime.fromMillisecondsSinceEpoch(to),
            ),
          );
          from = to;
        }
      }
      final ids = journal.values.cast<String>().toSet().toList();
      for (var i = 0; i < ids.length; i += 100) {
        await collect(
          RetrieveEventsParams(
            eventIds: ids.sublist(i, min(i + 100, ids.length)),
          ),
        );
      }
      final byKey = <String, Event>{};
      for (final e in existing.values) {
        byKey.putIfAbsent(keyOf(e)!, () => e);
      }
      final kept = <String>{};
      final zone = timeZoneDatabase.get('Asia/Shanghai');
      Set<int> alarms(Event e) =>
          (e.reminders ?? []).map((r) => r.minutes).whereType<int>().toSet();
      bool sameContent(Event a, Event b) =>
          a.title == b.title &&
          (a.location ?? '') == (b.location ?? '') &&
          a.description == b.description &&
          a.start?.millisecondsSinceEpoch == b.start?.millisecondsSinceEpoch &&
          a.end?.millisecondsSinceEpoch == b.end?.millisecondsSinceEpoch;
      Future<Event> save(
        String key,
        Map<String, dynamic> entry,
        List<int> minutes, {
        bool supplement = false,
      }) async {
        final prior = byKey[key];
        final label = minutes.first == 1440
            ? '24 小时'
            : minutes.first == 180
            ? '3 小时'
            : '15 分钟';
        final event = Event(
          calendarId,
          eventId: prior?.eventId,
          title: '${entry['title']}${supplement ? ' · 提前$label提醒' : ''}',
          location: entry['classroom'] as String?,
          description: '由三千上课自动维护，请在 App 内修改课程和提醒。\n$prefix$key]',
          start: TZDateTime.fromMillisecondsSinceEpoch(
            zone,
            entry['startMs'] as int,
          ),
          end: TZDateTime.fromMillisecondsSinceEpoch(
            zone,
            entry['endMs'] as int,
          ),
          reminders: minutes.map((m) => Reminder(minutes: m)).toList(),
        );
        final wanted = minutes.toSet();
        if (prior != null &&
            sameContent(prior, event) &&
            alarms(prior).length == wanted.length &&
            alarms(prior).containsAll(wanted)) {
          kept.add(prior.eventId!);
          return prior;
        }
        final id = _require(
          await calendar.createOrUpdateEvent(event),
          '部分提醒写入失败，请重试；已写入的提醒会核对后更新。',
        );
        journal[key] = id;
        state['events'] = journal;
        await persist();
        final readback = _require(
          await calendar.retrieveEvents(
            calendarId,
            RetrieveEventsParams(eventIds: [id]),
          ),
          '无法核对提醒是否保存，请重试。',
        );
        final matches = readback
            .where(
              (e) =>
                  e.eventId == id &&
                  e.calendarId == calendarId &&
                  keyOf(e) == key,
            )
            .toList();
        if (matches.length != 1 || !sameContent(matches.single, event)) {
          throw const _CalendarFailure('系统日历未完整保存课程，请重试。');
        }
        final stored = matches.single;
        if (alarms(stored).any((m) => !wanted.contains(m))) {
          throw const _CalendarFailure('系统日历保存的提醒时间与设置不一致，请检查日历后重试。');
        }
        kept.add(id);
        return stored;
      }

      for (final entry in desired.entries) {
        final minutes = List<int>.from(entry.value['leads'] as List);
        final primary = await save(entry.key, entry.value, minutes);
        final missing = minutes.where((m) => !alarms(primary).contains(m));
        // Some calendars truncate alarms. Keep one dated supplementary event for
        // each missing lead, and verify that its single alarm was actually saved.
        for (final lead in missing) {
          final extra = await save('${entry.key}/lead/$lead', entry.value, [
            lead,
          ], supplement: true);
          if (!alarms(extra).contains(lead)) {
            throw const _CalendarFailure('当前系统日历无法保存课程提醒，请检查日历设置后重试。');
          }
          supplements++;
        }
        count += minutes.length;
      }
      // Delete only verified owned entries, including duplicates from interrupted
      // operations. Never touch manual exports or unrelated user calendar items.
      for (final e in existing.values.where((e) => !kept.contains(e.eventId))) {
        if (!_require(await calendar.deleteOwnedEvent(e), '旧课程提醒尚未完全撤销，请重试。')) {
          throw const _CalendarFailure('旧课程提醒尚未完全撤销，请重试。');
        }
      }
      journal.removeWhere((key, id) => !kept.contains(id));
      for (final e in byKey.entries) {
        if (kept.contains(e.value.eventId)) journal[e.key] = e.value.eventId;
      }
      state['events'] = journal;
      await persist();
      return status();
    } on _CalendarFailure catch (e) {
      return status(message: e.message);
    } catch (_) {
      return status(message: '提醒未同步，旧设置可能仍然生效，请重试。');
    }
  }

  T _require<T>(Result<T>? result, String message) {
    if (result == null || !result.isSuccess || result.data == null) {
      throw _CalendarFailure(message);
    }
    return result.data as T;
  }
}

class _CalendarFailure implements Exception {
  final String message;
  const _CalendarFailure(this.message);
}
