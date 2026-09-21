import 'dart:collection';
import 'package:flutter/material.dart' show Color;
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wheretosleepinnju/Utils/ScheduleCalendarExporter.dart';
import 'package:wheretosleepinnju/Utils/IosCalendar.dart';
import '../Models/personal_schedule_test.dart' show reviewedSchedule;

Result<T> ok<T>(T data) => Result<T>()..data = data;

class TestCalendar implements CalendarClient {
  bool allowed = true;
  int? failAt;
  int writes = 0;
  int created = 0;
  final events = <String, Event>{};
  @override
  Future<Result<bool>> hasPermissions() async => ok(allowed);
  @override
  Future<Result<bool>> requestPermissions() async => ok(allowed);
  @override
  Future<Result<UnmodifiableListView<Calendar>>> retrieveCalendars() async =>
      ok(
        UnmodifiableListView([
          Calendar(id: 'personal', name: '中国艺术研究院 · 2026 秋', isReadOnly: false),
          if (created > 0)
            Calendar(id: 'owned', name: '三千上课', isReadOnly: false),
        ]),
      );
  @override
  Future<Result<String>> createCalendar(
    String? name, {
    Color? calendarColor,
    String? localAccountName,
  }) async {
    created++;
    return ok('owned');
  }

  @override
  Future<Result<UnmodifiableListView<Event>>> retrieveEvents(
    String? id,
    RetrieveEventsParams? params,
  ) async => ok(UnmodifiableListView(events.values));
  @override
  Future<Result<String>?> createOrUpdateEvent(Event? event) async {
    writes++;
    if (writes == failAt) {
      return Result<String>()..errors.add(const ResultError(500, 'disk full'));
    }
    final id = event!.eventId ?? 'event-${events.length}';
    event.eventId = id;
    events[id] = event;
    return ok(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceCalendarPlugin();
  });
  test(
    'exports actual semester dates, classrooms and split weeks; repeat updates without duplicates',
    () async {
      final calendar = TestCalendar();
      final exporter = ScheduleCalendarExporter(calendar: calendar);
      final schedule = reviewedSchedule();
      expect(await exporter.export(schedule), 73);
      expect(calendar.created, 1);
      expect(calendar.events, hasLength(73));
      final english = calendar.events.values
          .where((e) => e.title!.contains('英语'))
          .toList();
      expect(english, hasLength(8));
      expect(english.first.start!.year, 2026);
      expect(english.first.start!.month, 9);
      expect(english.first.start!.day, 22);
      expect(english.first.start!.hour, 9);
      expect(english.first.location, '第五会议室（主校区）');
      expect(english[2].start!.month, 10);
      expect(english[2].start!.day, 13);
      expect(english[2].location, '6310（主校区）');
      expect(
        calendar.events.values.every((e) => e.calendarId == 'owned'),
        isTrue,
      );
      expect(await exporter.export(schedule), 73);
      expect(calendar.created, 1);
      expect(calendar.events, hasLength(73));
    },
  );
  test('denied permission performs no writes', () async {
    final calendar = TestCalendar()..allowed = false;
    final exporter = ScheduleCalendarExporter(
      calendar: calendar,
      requestAccess: () async => false,
    );
    await expectLater(
      exporter.export(reviewedSchedule()),
      throwsA(
        isA<CalendarExportException>().having(
          (e) => e.permissionDenied,
          'permission denied',
          true,
        ),
      ),
    );
    expect(calendar.created, 0);
    expect(calendar.writes, 0);
  });
  test(
    'an event failure reports partial progress and retry does not duplicate saved events',
    () async {
      final calendar = TestCalendar()..failAt = 3;
      final exporter = ScheduleCalendarExporter(calendar: calendar);
      await expectLater(
        exporter.export(reviewedSchedule()),
        throwsA(
          isA<CalendarExportException>().having(
            (e) => e.savedCount,
            'saved',
            2,
          ),
        ),
      );
      expect(calendar.events, hasLength(2));
      calendar.failAt = null;
      expect(await exporter.export(reviewedSchedule()), 73);
      expect(calendar.events, hasLength(73));
    },
  );
}
