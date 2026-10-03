import 'dart:collection';
import 'dart:convert';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wheretosleepinnju/Utils/IosCalendar.dart';
import 'package:wheretosleepinnju/Utils/ScheduleCalendarReminders.dart';
import 'package:wheretosleepinnju/Utils/ScheduleDerivedDataService.dart';
import '../Models/personal_schedule_test.dart' show reviewedSchedule;

Result<T> ok<T>(T value) => Result<T>()..data = value;

class FakeReminderCalendar implements ReminderCalendarClient {
  bool allowed = true, failAfterSave = false, failDelete = false;
  int maxAlarms = 3, writes = 0, nextId = 0;
  final calendars = <Calendar>[];
  final events = <String, Event>{};
  @override
  Future<Result<bool>> hasPermissions() async => ok(allowed);
  @override
  Future<Result<bool>> requestPermissions() async => ok(allowed);
  @override
  Future<Result<UnmodifiableListView<Calendar>>> retrieveCalendars() async =>
      ok(UnmodifiableListView(calendars));
  @override
  Future<Result<String>> createCalendar(
    String? name, {
    Color? calendarColor,
    String? localAccountName,
  }) async {
    expect(localAccountName, isNotNull);
    calendars.add(
      Calendar(
        id: 'reminders',
        name: name,
        isReadOnly: false,
        accountType: 'LOCAL',
      ),
    );
    return ok('reminders');
  }

  @override
  Future<Result<UnmodifiableListView<Event>>> retrieveEvents(
    String? id,
    RetrieveEventsParams? p,
  ) async => ok(
    UnmodifiableListView(
      events.values.where(
        (e) =>
            e.calendarId == id &&
            (p!.eventIds != null
                ? p.eventIds!.contains(e.eventId)
                : e.end!.isAfter(p.startDate!) &&
                      e.start!.isBefore(p.endDate!)),
      ),
    ),
  );
  @override
  Future<Result<String>?> createOrUpdateEvent(Event? event) async {
    writes++;
    final e = event!;
    e.eventId ??= 'event-${nextId++}';
    e.reminders = e.reminders!.take(maxAlarms).toList();
    events[e.eventId!] = e;
    if (failAfterSave) {
      throw StateError('connection lost after calendar committed');
    }
    return ok(e.eventId!);
  }

  @override
  Future<Result<bool>> deleteOwnedEvent(Event e) async {
    if (failDelete) return ok(false);
    expect(events[e.eventId]?.description, e.description);
    events.remove(e.eventId);
    return ok(true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeReminderCalendar calendar;
  late ScheduleCalendarReminders reminders;
  late List<Map<String, dynamic>> occurrences;
  setUp(() {
    DeviceCalendarPlugin();
    SharedPreferences.setMockInitialValues({});
    calendar = FakeReminderCalendar();
    reminders = ScheduleCalendarReminders(
      calendar: calendar,
      now: () => DateTime.utc(2026, 9, 1),
    );
    final schedule = reviewedSchedule();
    for (var i = 0; i < schedule.courses.length; i++) {
      schedule.courses[i].id = i + 1;
    }
    occurrences = List<Map<String, dynamic>>.from(
      ScheduleDerivedDataService.snapshot(schedule)['occurrences'],
    );
  });
  test(
    'iOS bridge decodes native calendar event and nested alarm maps',
    () async {
      const channel = MethodChannel('sanqian/settings');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return [
              {
                'calendarId': 'test',
                'eventId': 'native-event',
                'eventTitle': '课程',
                'eventDescription': '描述',
                'eventLocation': '教室',
                'eventStartDate': DateTime.utc(
                  2026,
                  9,
                  22,
                  1,
                ).millisecondsSinceEpoch,
                'eventEndDate': DateTime.utc(
                  2026,
                  9,
                  22,
                  4,
                ).millisecondsSinceEpoch,
                'eventStartTimeZone': 'Asia/Shanghai',
                'eventEndTimeZone': 'Asia/Shanghai',
                'reminders': [
                  {'minutes': 15},
                  {'minutes': 180},
                  {'minutes': 1440},
                ],
              },
            ];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final result = await IosCalendar().retrieveEvents(
        'test',
        const RetrieveEventsParams(eventIds: ['native-event']),
      );
      expect(result.data!.single.reminders!.map((r) => r.minutes), [
        15,
        180,
        1440,
      ]);
      expect(result.data!.single.start!.hour, 9);
    },
  );
  test(
    'whole semester has 219 alarms for 73 dated classes; resume is idempotent',
    () async {
      final result = await reminders.sync(occurrences, [15, 180, 1440]);
      expect(result['synced'], true);
      expect(result['count'], 219);
      expect(calendar.events.length, 73);
      expect(
        calendar.events.values.every((e) => e.reminders!.length == 3),
        true,
      );
      final firstDates = calendar.events.values
          .where((e) => e.title!.contains('英语'))
          .map((e) => e.start!.day)
          .toList();
      expect(firstDates.take(3), [22, 29, 13]);
      expect(
        (await reminders.sync(occurrences, [15, 180, 1440]))['synced'],
        true,
      );
      expect(calendar.writes, 73);
      expect(calendar.calendars.length, 1);
    },
  );
  test(
    'calendar truncation creates verified supplements and disabling leads removes them',
    () async {
      calendar.maxAlarms = 2;
      final result = await reminders.sync(occurrences, [15, 180, 1440]);
      expect(result['count'], 219);
      expect(result['supplements'], 73);
      expect(result['synced'], true);
      expect(calendar.events.length, 146);
      expect(calendar.events.values.expand((e) => e.reminders!).length, 219);
      await reminders.sync(occurrences, [15]);
      expect(calendar.events.length, 73);
      expect(
        calendar.events.values.every((e) => e.reminders!.single.minutes == 15),
        true,
      );
    },
  );
  test(
    'save interrupted before returning its ID is recovered without duplication',
    () async {
      calendar.failAfterSave = true;
      expect((await reminders.sync(occurrences, [15]))['synced'], false);
      expect(calendar.events.length, 1);
      calendar.failAfterSave = false;
      reminders = ScheduleCalendarReminders(
        calendar: calendar,
        now: () => DateTime.utc(2026, 9, 1),
      );
      expect((await reminders.sync(occurrences, [15]))['synced'], true);
      expect(calendar.events.length, 73);
      expect(calendar.writes, 73);
    },
  );
  test(
    'calendar created before journal ID persistence is rediscovered by owner name',
    () async {
      await reminders.sync(occurrences, [15]);
      final prefs = await SharedPreferences.getInstance();
      final state =
          jsonDecode(prefs.getString(ScheduleCalendarReminders.stateKey)!)
              as Map<String, dynamic>;
      state.remove('calendarId');
      state['events'] = {};
      await prefs.setString(
        ScheduleCalendarReminders.stateKey,
        jsonEncode(state),
      );
      expect((await reminders.sync(occurrences, [15]))['synced'], true);
      expect(calendar.events.length, 73);
      expect(calendar.calendars.length, 1);
    },
  );
  test(
    'edits, table switches and disable reconcile only owned items',
    () async {
      await reminders.sync(occurrences, [15, 180, 1440]);
      final first = calendar.events.values.first;
      final id = first.eventId!;
      final updated = {
        ...occurrences.first,
        'title': '调课',
        'classroom': '新教室',
        'startMs': (occurrences.first['startMs'] as int) + 86400000,
        'endMs': (occurrences.first['endMs'] as int) + 86400000,
      };
      await reminders.sync([updated], [15]);
      expect(calendar.events.length, 1);
      expect(calendar.events[id]!.title, '调课');
      expect(calendar.events[id]!.location, '新教室');
      // A user's own event in the dedicated calendar must also be left alone.
      calendar.events['user'] = Event(
        'reminders',
        eventId: 'user',
        title: '私人事件',
        start: first.start,
        end: first.end,
        description: '用户自己的记录',
      );
      calendar.events['exported'] = Event(
        'manual-export',
        eventId: 'exported',
        start: first.start,
        end: first.end,
        description: '手动导出',
      );
      await reminders.sync(
        [
          {...updated, 'id': 'new-table.1.1'},
        ],
        [15],
      );
      expect(calendar.events.containsKey(id), false);
      expect(calendar.events.length, 3);
      expect((await reminders.sync([], []))['synced'], true);
      expect(calendar.events.keys.toSet(), {'user', 'exported'});
    },
  );
  test(
    'permission revocation and failed deletes never report successful disable',
    () async {
      await reminders.sync(occurrences, [15]);
      calendar.allowed = false;
      final denied = await reminders.sync([], []);
      expect(denied['permission'], 'denied');
      expect(denied['synced'], false);
      expect(calendar.events.length, 73);
      calendar.allowed = true;
      calendar.failDelete = true;
      expect((await reminders.sync([], []))['synced'], false);
      calendar.failDelete = false;
      expect((await reminders.sync([], []))['synced'], true);
      expect(calendar.events, isEmpty);
    },
  );
  test(
    'a provider that refuses all alarms is not reported as successful',
    () async {
      calendar.maxAlarms = 0;
      expect((await reminders.sync(occurrences, [15]))['synced'], false);
    },
  );
  test(
    'future reminders are relative to absolute Shanghai start, past triggers omitted',
    () async {
      final entry = occurrences.first;
      final start = entry['startMs'] as int;
      reminders = ScheduleCalendarReminders(
        calendar: calendar,
        now: () => DateTime.fromMillisecondsSinceEpoch(
          start - 60 * 60000,
          isUtc: true,
        ),
      );
      final result = await reminders.sync([entry], [15, 180, 1440]);
      expect(result['count'], 1);
      expect(calendar.events.values.single.reminders!.single.minutes, 15);
      expect(
        calendar.events.values.single.start!.millisecondsSinceEpoch,
        start,
      );
    },
  );
  test(
    'a writable reminder calendar stays in use after Android relabels it',
    () async {
      final first = await reminders.sync(occurrences, [15]);
      expect(first['synced'], true);
      expect(first['message'], isNull);
      calendar.calendars.single.accountType = 'com.xiaomi';
      final again = await reminders.sync(occurrences, [15]);
      expect(again['synced'], true);
      expect(again['message'], isNull);
      expect(calendar.calendars, hasLength(1));
      expect(calendar.events, hasLength(73));
      expect(calendar.writes, 73);
    },
  );
  test(
    'a read-only remembered calendar does not block a new writable calendar',
    () async {
      const owner = 'abababababababababababababababab';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ScheduleCalendarReminders.stateKey,
        jsonEncode({
          'owner': owner,
          'calendarId': 'locked',
          'events': <String, String>{},
        }),
      );
      calendar.calendars.add(
        Calendar(
          id: 'locked',
          name: '三千上课 · 上课提醒 · abababab',
          isReadOnly: true,
          accountType: 'com.xiaomi',
        ),
      );
      final start = occurrences.first['startMs'] as int;
      final zone = timeZoneDatabase.get('Asia/Shanghai');
      calendar.events['ghost'] = Event(
        'locked',
        eventId: 'ghost',
        title: '旧课',
        description: '旧提醒\n[sanqian-reminder:$owner:ghost]',
        start: TZDateTime.fromMillisecondsSinceEpoch(zone, start),
        end: TZDateTime.fromMillisecondsSinceEpoch(zone, start + 3600000),
      );
      final result = await reminders.sync(occurrences, [15]);
      expect(result['synced'], true);
      expect(result['message'], isNull);
      expect(result['notice'], contains('只读'));
      expect(calendar.events.containsKey('ghost'), isTrue);
      expect(
        calendar.events.values
            .where((event) => event.eventId != 'ghost')
            .every((event) => event.calendarId != 'locked'),
        isTrue,
      );
    },
  );
  test(
    'reminders move off an unrelated calendar without deleting personal events',
    () async {
      const owner = 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ScheduleCalendarReminders.stateKey,
        jsonEncode({
          'owner': owner,
          'calendarId': 'personal',
          'calendarMode': 'dedicated',
          'events': {'old': 'old-event'},
        }),
      );
      calendar.calendars.add(
        Calendar(
          id: 'personal',
          name: '我的日历',
          isReadOnly: false,
          accountType: 'com.google',
          isDefault: true,
        ),
      );
      final start = occurrences.first['startMs'] as int;
      final zone = timeZoneDatabase.get('Asia/Shanghai');
      calendar.events['old-event'] = Event(
        'personal',
        eventId: 'old-event',
        title: '旧课',
        description: '由三千上课自动维护\n[sanqian-reminder:$owner:old]',
        start: TZDateTime.fromMillisecondsSinceEpoch(zone, start),
        end: TZDateTime.fromMillisecondsSinceEpoch(zone, start + 3600000),
      );
      calendar.events['mine'] = Event(
        'personal',
        eventId: 'mine',
        title: '私人日程',
        description: '自己的日程',
        start: TZDateTime.fromMillisecondsSinceEpoch(zone, start),
        end: TZDateTime.fromMillisecondsSinceEpoch(zone, start + 3600000),
      );
      final result = await reminders.sync([occurrences.first], [15]);
      expect(result['synced'], true);
      expect(calendar.events.containsKey('old-event'), isFalse);
      expect(calendar.events.containsKey('mine'), isTrue);
      expect(
        calendar.events.values
            .where((event) => event.calendarId == 'personal')
            .map((event) => event.eventId)
            .toSet(),
        {'mine'},
      );
    },
  );
}
