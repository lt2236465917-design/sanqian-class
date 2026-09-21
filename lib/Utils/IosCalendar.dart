import 'dart:collection';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/services.dart';

/// Uses one EventKit store for both the current iOS permission API and writes.
class IosCalendar implements ReminderCalendarClient {
  static const _channel = MethodChannel('sanqian/settings');
  Future<Result<T>> _call<T>(
    String method,
    Map<String, Object?> args,
    T Function(dynamic) decode,
  ) async {
    try {
      return Result<T>()
        ..data = decode(await _channel.invokeMethod(method, args));
    } on PlatformException catch (e) {
      return Result<T>()..errors.add(ResultError(500, e.message ?? e.code));
    }
  }

  @override
  Future<Result<bool>> requestPermissions() =>
      _call('requestCalendarAccess', {}, (v) => v as bool);
  @override
  Future<Result<bool>> hasPermissions() =>
      _call('calendarHasAccess', {}, (v) => v as bool);
  @override
  Future<Result<UnmodifiableListView<Calendar>>> retrieveCalendars() => _call(
    'calendarList',
    {},
    (v) => UnmodifiableListView(
      (v as List).map((c) => Calendar.fromJson(Map<String, dynamic>.from(c))),
    ),
  );
  @override
  Future<Result<String>> createCalendar(
    String? calendarName, {
    Color? calendarColor,
    String? localAccountName,
  }) => _call('calendarCreate', {
    'name': calendarName,
    'localOnly': localAccountName != null,
  }, (v) => v as String);
  @override
  Future<Result<UnmodifiableListView<Event>>> retrieveEvents(
    String? calendarId,
    RetrieveEventsParams? retrieveEventsParams,
  ) => _call(
    'calendarEvents',
    {
      'calendarId': calendarId,
      'from': retrieveEventsParams?.startDate?.millisecondsSinceEpoch
          .toDouble(),
      'to': retrieveEventsParams?.endDate?.millisecondsSinceEpoch.toDouble(),
      'eventIds': retrieveEventsParams?.eventIds,
    },
    (v) => UnmodifiableListView(
      (v as List).map((raw) {
        final event = Map<String, dynamic>.from(raw);
        // StandardMessageCodec keeps nested native dictionaries keyed by Object.
        // The device_calendar JSON constructor requires String-keyed maps.
        event['reminders'] = (event['reminders'] as List? ?? [])
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        return Event.fromJson(event);
      }),
    ),
  );
  @override
  Future<Result<String>?> createOrUpdateEvent(Event? event) =>
      _call('calendarSaveEvent', {
        'calendarId': event!.calendarId,
        'eventId': event.eventId,
        'title': event.title,
        'location': event.location,
        'description': event.description,
        'start': event.start!.millisecondsSinceEpoch.toDouble(),
        'end': event.end!.millisecondsSinceEpoch.toDouble(),
        if (event.reminders != null)
          'reminders': event.reminders!.map((r) => r.minutes).toList(),
      }, (v) => v as String);
  @override
  Future<Result<bool>> deleteOwnedEvent(Event event) =>
      _call('calendarDeleteEvent', {
        'calendarId': event.calendarId,
        'eventId': event.eventId,
        'description': event.description,
      }, (v) => v == true);
}

abstract class ReminderCalendarClient implements CalendarClient {
  Future<Result<bool>> deleteOwnedEvent(Event event);
}

abstract class CalendarClient {
  Future<Result<bool>> hasPermissions();
  Future<Result<bool>> requestPermissions();
  Future<Result<UnmodifiableListView<Calendar>>> retrieveCalendars();
  Future<Result<String>> createCalendar(
    String? calendarName, {
    Color? calendarColor,
    String? localAccountName,
  });
  Future<Result<UnmodifiableListView<Event>>> retrieveEvents(
    String? calendarId,
    RetrieveEventsParams? retrieveEventsParams,
  );
  Future<Result<String>?> createOrUpdateEvent(Event? event);
}

class PluginCalendar implements ReminderCalendarClient {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();
  @override
  Future<Result<bool>> hasPermissions() => _plugin.hasPermissions();
  @override
  Future<Result<bool>> requestPermissions() => _plugin.requestPermissions();
  @override
  Future<Result<UnmodifiableListView<Calendar>>> retrieveCalendars() =>
      _plugin.retrieveCalendars();
  @override
  Future<Result<String>> createCalendar(
    String? calendarName, {
    Color? calendarColor,
    String? localAccountName,
  }) => _plugin.createCalendar(
    calendarName,
    calendarColor: calendarColor,
    localAccountName: localAccountName,
  );
  @override
  Future<Result<UnmodifiableListView<Event>>> retrieveEvents(
    String? calendarId,
    RetrieveEventsParams? retrieveEventsParams,
  ) => _plugin.retrieveEvents(calendarId, retrieveEventsParams);
  @override
  Future<Result<String>?> createOrUpdateEvent(Event? event) =>
      _plugin.createOrUpdateEvent(event);

  @override
  Future<Result<bool>> deleteOwnedEvent(Event event) async {
    final current = await _plugin.retrieveEvents(
      event.calendarId,
      RetrieveEventsParams(eventIds: [event.eventId!]),
    );
    if (!current.isSuccess) {
      return Result<bool>()..errors.addAll(current.errors);
    }
    if (current.data!.isEmpty) return Result<bool>()..data = true;
    if (current.data!.any(
      (e) =>
          e.calendarId != event.calendarId ||
          e.description != event.description,
    )) {
      return Result<bool>()
        ..errors.add(const ResultError(409, 'Event ownership changed'));
    }
    return _plugin.deleteEvent(event.calendarId, event.eventId);
  }
}
