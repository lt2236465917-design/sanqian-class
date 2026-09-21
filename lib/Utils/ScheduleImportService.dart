import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../Models/Db/DbHelper.dart';
import '../Models/ScheduleImportDraft.dart';
import '../Resources/Constant.dart';

class ScheduleImportDiff {
  final List<String> added, changed, unchanged, pending, conflicts, removed;

  /// Rows contain name, identity, current/incoming imported fields and status.
  final List<Map<String, dynamic>> details;

  /// Opaque local equality token. Contains canonical review data; never log it
  /// or send it to a recognizer/network endpoint. Not an authorization token.
  final String? reviewToken;
  final List<Map<String, dynamic>> legacyCandidates;
  const ScheduleImportDiff({
    this.added = const [],
    this.changed = const [],
    this.unchanged = const [],
    this.pending = const [],
    this.conflicts = const [],
    this.removed = const [],
    this.details = const [],
    this.reviewToken,
    this.legacyCandidates = const [],
  });
  bool get requiresChangeConfirmation =>
      changed.isNotEmpty || removed.isNotEmpty;
}

class ScheduleImportCommitResult {
  final int tableId,
      inserted,
      updated,
      unchanged,
      preservedDeleted,
      pending,
      deleted;
  final List<String> conflicts;
  const ScheduleImportCommitResult({
    required this.tableId,
    required this.inserted,
    required this.updated,
    required this.unchanged,
    required this.preservedDeleted,
    required this.pending,
    required this.conflicts,
    this.deleted = 0,
  });
}

class ScheduleImportStoredCourse {
  final String identity, meetingKey;
  final Map<String, dynamic> fields;
  const ScheduleImportStoredCourse({
    required this.identity,
    required this.meetingKey,
    required this.fields,
  });
}

/// All decisions are recomputed in the committing SQLite transaction. Native
/// parsers never write SQLite. Sources with a different exact account/term key
/// cannot claim an existing imported table, even through mergeTableId.
class ScheduleImportService {
  static const schemaVersion = 2;
  static const metadataKey = 'schedule_import';
  static const snapshotKey = 'course_snapshot';
  static const rowMetadataKey = 'schedule_import_row';

  static ScheduleImportDiff diff(
    ScheduleImportDraft draft, {
    Iterable<ScheduleImportStoredCourse> existing = const [],
    Iterable<String> deletedIdentities = const [],
  }) {
    final rows = existing.toList();
    final added = <String>[],
        changed = <String>[],
        unchanged = <String>[],
        pending = <String>[];
    for (final course in draft.normalised().courses) {
      if (course.isPending) pending.add(course.identity);
      if (deletedIdentities.contains(course.identity)) continue;
      final matches = rows.where((r) => r.identity == course.identity).toList();
      final keys = course.meetings.map((m) => m.meetingKey).toSet();
      final oldKeys = matches.map((m) => m.meetingKey).toSet();
      if (matches.isEmpty) {
        added.add(course.identity);
      } else if (keys.length == oldKeys.length &&
          keys.containsAll(oldKeys) &&
          matches.every(
            (r) =>
                r.fields['name'] == course.name &&
                r.fields['teacher'] == course.teacher &&
                r.fields['class_number'] == course.courseCode,
          )) {
        unchanged.add(course.identity);
      } else {
        changed.add(course.identity);
      }
    }
    return ScheduleImportDiff(
      added: added,
      changed: changed,
      unchanged: unchanged,
      pending: pending,
    );
  }

  static Future<ScheduleImportDiff> preview(
    ScheduleImportDraft draft, {
    Database? database,
    int? mergeTableId,
    List<Map<String, dynamic>>? periods,
    Map<String, int> legacyBindings = const {},
  }) async {
    draft.requireValid();
    final db = database ?? await DbHelper().open();
    return db.transaction(
      (txn) async => (await _plan(
        txn,
        draft.normalised(),
        mergeTableId,
        periods,
        legacyBindings,
      )).diff,
    );
  }

  /// acceptChanges explicitly approves source additions/replacements/removals
  /// revealed by preview. Local edits and tombstones are protected even then.
  /// Exact unchanged rows retain IDs; changed meetings without stable meeting
  /// IDs are explicit remove/add operations, never ordinal guesses.
  static Future<ScheduleImportCommitResult> commit(
    ScheduleImportDraft draft, {
    Database? database,
    int? mergeTableId,
    List<Map<String, dynamic>>? periods,
    Map<String, int> legacyBindings = const {},
    bool acceptChanges = false,
    String? expectedReviewToken,
  }) async {
    draft.requireValid();
    final db = database ?? await DbHelper().open();
    return db.transaction((txn) async {
      final plan = await _plan(
        txn,
        draft.normalised(),
        mergeTableId,
        periods,
        legacyBindings,
      );
      if (legacyBindings.isNotEmpty &&
          (!acceptChanges || expectedReviewToken == null)) {
        throw StateError('legacy_binding_requires_review_confirmation');
      }
      if (expectedReviewToken != null &&
          expectedReviewToken != plan.diff.reviewToken) {
        throw StateError('import_review_stale');
      }
      if (plan.diff.requiresChangeConfirmation && !acceptChanges) {
        throw StateError('import_changes_require_confirmation');
      }
      final tableId =
          plan.tableId ??
          await txn.insert('CourseTable', {
            'name': '${draft.school} ${draft.term}',
            'data': jsonEncode(plan.tableData),
          });
      final max = await txn.rawQuery(
        'SELECT MAX(course_id) AS value FROM Course',
      );
      var next = (max.first['value'] as int? ?? -1) + 1;
      final groupIds = <String, int>{};
      for (final row in plan.current) {
        final id = row['course_id'];
        if (id is int) groupIds[_identity(row)] = id;
      }
      for (final row in plan.inserts) {
        final values = Map<String, dynamic>.from(row)..['tableid'] = tableId;
        values['course_id'] = groupIds.putIfAbsent(
          _identity(row),
          () => next++,
        );
        final id = await txn.insert('Course', values);
        plan.snapshots[_key(row)] = _snapshot(row, id);
      }
      for (final update in plan.updates) {
        await txn.update(
          'Course',
          update.values,
          where: 'id = ? AND tableid = ?',
          whereArgs: [update.id, tableId],
        );
      }
      for (final id in plan.deletes) {
        await txn.delete(
          'Course',
          where: 'id = ? AND tableid = ?',
          whereArgs: [id, tableId],
        );
      }
      final data = {
        ...plan.tableData,
        'import_source_key': draft.sourceKey,
        metadataKey: {'version': schemaVersion, 'source_key': draft.sourceKey},
        snapshotKey: plan.snapshots.values.toList(),
        'import_tombstones': plan.tombstones.toList()..sort(),
      };
      await txn.update(
        'CourseTable',
        {'data': jsonEncode(data)},
        where: 'id = ?',
        whereArgs: [tableId],
      );
      return ScheduleImportCommitResult(
        tableId: tableId,
        inserted: plan.inserts.length,
        updated: plan.updates.length,
        unchanged: plan.diff.unchanged.length,
        pending: plan.diff.pending.length,
        preservedDeleted: plan.preservedDeleted,
        conflicts: plan.diff.conflicts,
        deleted: plan.deletes.length,
      );
    });
  }

  static Future<_Plan> _plan(
    DatabaseExecutor txn,
    ScheduleImportDraft draft,
    int? mergeId,
    List<Map<String, dynamic>>? periods,
    Map<String, int> legacyBindings,
  ) async {
    final tables = await txn.query('CourseTable');
    Map<String, dynamic>? table;
    for (final candidate in tables) {
      final data = _map(candidate['data']);
      if (mergeId == null && data['import_source_key'] == draft.sourceKey ||
          candidate['id'] == mergeId) {
        if (table != null) throw StateError('ambiguous_import_source');
        table = candidate;
      }
    }
    if (mergeId != null && table == null) {
      throw StateError('merge_table_missing');
    }
    final data = _map(table?['data']);
    if (table == null && periods != null) {
      for (final period in periods) {
        final start = _minute(period['start']), end = _minute(period['end']);
        if (start == null || end == null || start >= end) {
          throw const FormatException('invalid_class_time_list');
        }
      }
      data['class_time_list'] = periods;
    }
    final previousSource = data['import_source_key'];
    if (previousSource != null && previousSource != draft.sourceKey) {
      throw StateError('import_source_account_or_term_mismatch');
    }
    // Existing semester/period definitions belong to the user's table.
    final monday = data['semester_start_monday'];
    if (monday == null || monday == '') {
      if (draft.firstWeekMonday == null) {
        throw StateError('semester_start_required');
      }
      data['semester_start_monday'] = _date(draft.firstWeekMonday!);
    }
    final current = table == null
        ? <Map<String, dynamic>>[]
        : await txn.query(
            'Course',
            where: 'tableid = ?',
            whereArgs: [table['id']],
          );
    final snapshots = <String, Map<String, dynamic>>{};
    for (final item in (data[snapshotKey] as List? ?? const [])) {
      final snapshot = _map(item);
      snapshots[_snapshotKey(snapshot)] = snapshot;
    }
    final tombstones = (data['import_tombstones'] as List? ?? const [])
        .map((e) => e.toString())
        .toSet();
    final currentIds = current.map((r) => r['id']).toSet();
    for (final entry in snapshots.entries) {
      if (entry.value['row_id'] != null &&
          !currentIds.contains(entry.value['row_id'])) {
        tombstones.add(entry.key);
      }
    }
    final incoming = <String, Map<String, dynamic>>{};
    final courseByIdentity = {for (final c in draft.courses) c.identity: c};
    for (final course in draft.courses) {
      for (final row in _courseRows(course, data, draft.sourceKey)) {
        final key = _key(row);
        if (incoming.containsKey(key) &&
            !_equal(_fields(incoming[key]!), _fields(row))) {
          throw StateError('ambiguous_duplicate_course');
        }
        incoming[key] = row;
      }
    }
    if (legacyBindings.values.toSet().length != legacyBindings.length) {
      throw StateError('legacy_binding_duplicate_target');
    }
    for (final binding in legacyBindings.entries) {
      final candidates = current
          .where((row) => row['id'] == binding.value)
          .toList();
      if (!incoming.containsKey(binding.key) ||
          candidates.length != 1 ||
          tombstones.contains(binding.key)) {
        throw StateError('legacy_binding_invalid_target');
      }
      if (_rowMeta(candidates.single).isNotEmpty ||
          snapshots.values.any(
            (snapshot) => snapshot['row_id'] == binding.value,
          )) {
        throw StateError('legacy_binding_already_owned');
      }
    }
    final added = <String>[],
        changed = <String>[],
        removed = <String>[],
        unchanged = <String>[];
    final pending = <String>[], conflicts = <String>[];
    final inserts = <Map<String, dynamic>>[],
        updates = <_Update>[],
        deletes = <int>[];
    var preserved = 0;
    final boundKeys = <String>{};
    final claimedLegacy = legacyBindings.values.toSet();
    for (final entry in incoming.entries) {
      final key = entry.key,
          row = entry.value,
          identity = _identity(entry.value);
      if (row['week_time'] == 0) pending.add(key);
      if (tombstones.contains(key)) {
        preserved++;
        continue;
      }
      final explicitLegacyId = legacyBindings[key];
      if (explicitLegacyId != null) {
        final existing = current.singleWhere(
          (row) => row['id'] == explicitLegacyId,
        );
        updates.add(
          _Update(explicitLegacyId, {
            'data': jsonEncode({
              ..._map(existing['data']),
              ..._map(row['data']),
            }),
          }),
        );
        // Explicit provenance binding is not permission to replace any course
        // field. Preserve the raw source baseline for future local protection.
        snapshots[key] = _snapshot(row, explicitLegacyId);
        changed.add(key);
        boundKeys.add(key);
        continue;
      }
      final snapshot = snapshots[key];
      final matches = current
          .where(
            (r) =>
                _key(r) == key && _rowMeta(r)['source_key'] == draft.sourceKey,
          )
          .toList();
      if (matches.length > 1) {
        conflicts.add('$key:ambiguous_rows');
        continue;
      }
      if (matches.isNotEmpty) {
        boundKeys.add(key);
        final existing = matches.single;
        if (snapshot == null) {
          conflicts.add('$key:missing_source_snapshot');
          continue;
        }
        final oldFields = _map(snapshot['fields']);
        if (_equal(oldFields, _fields(row))) {
          final nextData = jsonEncode({
            ..._map(existing['data']),
            ..._map(row['data']),
          });
          if (nextData != existing['data']) {
            updates.add(_Update(existing['id'] as int, {'data': nextData}));
          }
          unchanged.add(key);
          continue;
        }
        changed.add(key);
        final values = <String, dynamic>{};
        for (final field in _importedFields) {
          if (_equal(existing[field], oldFields[field])) {
            values[field] = row[field];
          } else {
            values[field] = existing[field];
            if (!_equal(existing[field], row[field])) {
              conflicts.add('$key:local_$field');
            }
          }
        }
        values['data'] = jsonEncode({
          ..._map(existing['data']),
          ..._map(row['data']),
        });
        updates.add(_Update(existing['id'] as int, values));
        // Store source values, never the values protected by the local merge.
        snapshots[key] = _snapshot(row, existing['id'] as int);
        continue;
      }
      // Bind a legacy row only when every imported field agrees and code is
      // unambiguous. Missing provenance never authorizes an overwrite.
      final legacy = current
          .where(
            (r) =>
                _rowMeta(r).isEmpty &&
                !claimedLegacy.contains(r['id']) &&
                _equal(_fields(r), _fields(row)),
          )
          .toList();
      if (legacy.length == 1) {
        final existing = legacy.single;
        claimedLegacy.add(existing['id'] as int);
        boundKeys.add(key);
        updates.add(
          _Update(existing['id'] as int, {
            'data': jsonEncode({
              ..._map(existing['data']),
              ..._map(row['data']),
            }),
          }),
        );
        snapshots[key] = _snapshot(row, existing['id'] as int);
        unchanged.add(key);
        continue;
      }
      final course = courseByIdentity[identity]!;
      final ambiguous = current.any(
        (r) =>
            r['name'] == row['name'] &&
            (!course.hasStableIdentity || _rowMeta(r).isEmpty),
      );
      if (legacy.length > 1 || ambiguous) {
        conflicts.add('$key:ambiguous_identity');
        continue;
      }
      final previousForCourse = snapshots.values
          .where((s) => s['identity'] == identity)
          .toList();
      final editedSourceRow = previousForCourse.any(
        (snapshot) => current.any(
          (existing) =>
              existing['id'] == snapshot['row_id'] &&
              !_equal(_fields(existing), _map(snapshot['fields'])),
        ),
      );
      if (editedSourceRow) {
        conflicts.add('$key:local_edit_prevents_replacement');
        continue;
      }

      if (previousForCourse.isNotEmpty) {
        changed.add(key);
      } else {
        added.add(key);
      }
      inserts.add(row);
    }
    // Absent source meetings are presented as removals. Preserve edited rows,
    // and keep their incoming source snapshot for future three-way comparisons.
    for (final entry in Map<String, Map<String, dynamic>>.from(
      snapshots,
    ).entries) {
      if (incoming.containsKey(entry.key) ||
          tombstones.contains(entry.key) ||
          boundKeys.contains(entry.key)) {
        continue;
      }
      final snapshot = entry.value;
      if (snapshot['identity'].toString().startsWith('candidate:')) {
        conflicts.add('${entry.key}:unstable_identity_prevents_removal');
        continue;
      }
      final matches = current
          .where((r) => r['id'] == snapshot['row_id'])
          .toList();
      if (matches.isEmpty) continue;
      final row = matches.single;
      if (!_equal(_fields(row), _map(snapshot['fields']))) {
        conflicts.add('${entry.key}:local_edit_prevents_removal');
        continue;
      }
      removed.add(entry.key);
      deletes.add(row['id'] as int);
      snapshots.remove(entry.key);
      // Confirmed source removals are also durable and never reappear silently.
      tombstones.add(entry.key);
    }
    return _Plan(
      table?['id'] as int?,
      data,
      current,
      snapshots,
      tombstones,
      inserts,
      updates,
      deletes,
      preserved,
      ScheduleImportDiff(
        reviewToken: _reviewToken(
          draft,
          table,
          current,
          periods,
          mergeId,
          legacyBindings,
        ),
        legacyCandidates: current
            .where((row) => _rowMeta(row).isEmpty)
            .map((row) => {'id': row['id'], ..._fields(row)})
            .toList(),
        added: added,
        changed: changed,
        removed: removed,
        unchanged: unchanged,
        pending: pending,
        conflicts: conflicts,
        details: [
          for (final entry in incoming.entries)
            {
              'key': entry.key,
              'name': entry.value['name'],
              'identity': _identity(entry.value),
              'bindingRowId': legacyBindings[entry.key],
              'incoming': _fields(entry.value),
              'current': current
                  .where(
                    (r) =>
                        _key(r) == entry.key ||
                        r['id'] == legacyBindings[entry.key],
                  )
                  .map(_fields)
                  .toList(),
            },
          for (final key in removed)
            {
              'key': key,
              'name': current.firstWhere((r) => _key(r) == key)['name'],
              'current': _fields(current.firstWhere((r) => _key(r) == key)),
              'incoming': null,
            },
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _courseRows(
    ScheduleImportCourseDraft course,
    Map<String, dynamic> data,
    String sourceKey,
  ) {
    final periods = (data['class_time_list'] as List? ?? const [])
        .map(_map)
        .toList();
    final meetings = course.meetings.isEmpty
        ? [ScheduleImportMeetingDraft()]
        : course.meetings;
    return meetings.map((meeting) {
      int? slot, count;
      if (meeting.startMinute != null && meeting.endMinute != null) {
        final starts = <int>[], ends = <int>[];
        for (var i = 0; i < periods.length; i++) {
          if (_minute(periods[i]['start']) == meeting.startMinute) {
            starts.add(i);
          }
          if (_minute(periods[i]['end']) == meeting.endMinute) ends.add(i);
        }
        if (starts.length == 1 &&
            ends.length == 1 &&
            ends.single >= starts.single) {
          slot = starts.single + 1;
          count = ends.single - starts.single;
        }
      } else if (meeting.periodIndex != null &&
          meeting.periodIndex! >= 1 &&
          meeting.periodIndex! + (meeting.periodCount ?? 0) <= periods.length) {
        slot = meeting.periodIndex;
        count = meeting.periodCount ?? 0;
      }
      final isPending =
          slot == null ||
          meeting.weekday == null ||
          meeting.weeks == null ||
          meeting.weeks!.isEmpty;
      return <String, dynamic>{
        'name': course.name.trim(),
        'class_number': course.courseCode,
        'teacher': course.teacher,
        'classroom': meeting.location,
        'weeks': jsonEncode(
          isPending ? <int>[] : (meeting.weeks!.toList()..sort()),
        ),
        'week_time': isPending ? 0 : meeting.weekday,
        'start_time': isPending ? 0 : slot,
        'time_count': isPending ? 0 : count,
        'import_type': Constant.ADD_BY_IMPORT,
        'info': course.pendingReason,
        'data': jsonEncode({
          rowMetadataKey: {
            'schema_version': schemaVersion,
            'source_key': sourceKey,
            'identity': course.identity,
            'meeting_key': meeting.meetingKey,
            'candidate_only': !course.hasStableIdentity,
            'original_meeting': meeting.toJson(),
            'original_course': course.toJson(),
            'section': course.section,
            'pending_reason': isPending
                ? (course.pendingReason ?? '周次、星期或目标作息待核对')
                : null,
          },
        }),
      };
    }).toList();
  }

  // Collision-free canonical serialization rather than a lossy/non-crypto
  // hash. This token stays in the local review page and is checked again
  // inside the same transaction that performs every course write.
  static String _reviewToken(
    ScheduleImportDraft draft,
    Map<String, dynamic>? table,
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>>? periods,
    int? mergeId,
    Map<String, int> legacyBindings,
  ) {
    final rows = current.toList()
      ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    return base64Url.encode(
      utf8.encode(
        jsonEncode(
          _canonical({
            'draft': draft.toJson(),
            'table': table,
            'rows': rows,
            'periods': periods,
            'mergeTableId': mergeId,
            'legacyBindings': legacyBindings,
          }),
        ),
      ),
    );
  }

  static dynamic _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static Map<String, dynamic> _rowMeta(Map<String, dynamic> row) =>
      _map(_map(row['data'])[rowMetadataKey]);
  static String _identity(Map<String, dynamic> row) =>
      _rowMeta(row)['identity']?.toString() ?? 'unbound:${row['id']}';
  static String _key(Map<String, dynamic> row) =>
      jsonEncode([_identity(row), _rowMeta(row)['meeting_key']]);
  static String _snapshotKey(Map<String, dynamic> snapshot) =>
      jsonEncode([snapshot['identity'], snapshot['meeting_key']]);
  static Map<String, dynamic> _fields(Map<String, dynamic> row) => {
    for (final field in _importedFields) field: row[field],
  };
  static Map<String, dynamic> _snapshot(Map<String, dynamic> row, int id) => {
    'identity': _identity(row),
    'meeting_key': _rowMeta(row)['meeting_key'],
    'row_id': id,
    'fields': _fields(row),
  };
  static bool _equal(dynamic a, dynamic b) => jsonEncode(a) == jsonEncode(b);
  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        final result = jsonDecode(value);
        if (result is Map) return Map<String, dynamic>.from(result);
      } on FormatException {
        /* Legacy metadata is preserved outside this key. */
      }
    }
    return {};
  }

  static int? _minute(dynamic value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch('$value');
    if (match == null) return null;
    final hour = int.parse(match[1]!), minute = int.parse(match[2]!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _Update {
  final int id;
  final Map<String, dynamic> values;
  _Update(this.id, this.values);
}

class _Plan {
  final int? tableId;
  final Map<String, dynamic> tableData;
  final List<Map<String, dynamic>> current;
  final Map<String, Map<String, dynamic>> snapshots;
  final Set<String> tombstones;
  final List<Map<String, dynamic>> inserts;
  final List<_Update> updates;
  final List<int> deletes;
  final int preservedDeleted;
  final ScheduleImportDiff diff;
  _Plan(
    this.tableId,
    this.tableData,
    this.current,
    this.snapshots,
    this.tombstones,
    this.inserts,
    this.updates,
    this.deletes,
    this.preservedDeleted,
    this.diff,
  );
}

const _importedFields = [
  'name',
  'class_number',
  'teacher',
  'classroom',
  'weeks',
  'week_time',
  'start_time',
  'time_count',
  'import_type',
  'info',
];
