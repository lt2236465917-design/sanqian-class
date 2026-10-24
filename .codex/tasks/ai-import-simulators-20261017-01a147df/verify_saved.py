"""Read-only verification of simulator SQLite against the manual source oracle."""
import datetime
import json
import sqlite3
import sys
from pathlib import Path
from verify_results import E, norm, room, occ


def minute(value):
    hour, minute = map(int, value.split(':'))
    return hour * 60 + minute


def verify(path):
    db = sqlite3.connect('file:' + str(Path(path).resolve()) + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    results = []
    for table in db.execute('select * from CourseTable order by id'):
        data = json.loads(table['data'] or '{}')
        if 'schedule_import' not in data:
            continue
        source = json.loads(data['import_source_key'])[0]
        expected = dict(E)
        if source == 'school-portal':
            expected = {k: dict(v) for k, v in list(E.items())[:14]}
            for name, teacher in [
                ('艺术人类学理论与沿革专题研究', '方李莉'),
                ('保护非物质文化遗产政策法规解读专题', '葛玉清'),
                ('非物质文化遗产概论', '罗微'),
                ('非物质文化遗产保护理论与实践专题', '郑长铃'),
            ]:
                expected[name]['teacher'] = teacher
        expected = {norm(k): v for k, v in expected.items()}
        rows = list(db.execute('select * from Course where tableid=?', (table['id'],)))
        actual = {}
        errors = []
        pending = set()
        dates = []
        first_monday = datetime.date.fromisoformat(data['semester_start_monday'])
        if first_monday != datetime.date(2026, 9, 7):
            errors.append('Incorrect semester start')
        for row in rows:
            name = norm(row['name'])
            exp = expected.get(name)
            if exp is None:
                errors.append(name + ': unexpected course')
                continue
            points = actual.setdefault(name, [])
            metadata = json.loads(row['data'])['schedule_import_row']
            if norm(row['teacher']) != norm(exp['teacher']):
                errors.append(name + ': teacher mismatch')
            if norm(row['class_number']).lower() != norm(exp['code']).lower():
                errors.append(name + ': course code mismatch')
            if str(metadata['section']) != '1':
                errors.append(name + ': section mismatch')
            weeks = json.loads(row['weeks'])
            if not exp['meetings']:
                pending.add(name)
                if weeks or row['week_time'] or row['start_time'] or not metadata['pending_reason']:
                    errors.append(name + ': pending course given a calendar time')
                continue
            if not weeks or row['start_time'] < 1:
                errors.append(name + ': scheduled time missing')
                continue
            periods = data['class_time_list']
            start = minute(periods[row['start_time'] - 1]['start'])
            end = minute(periods[row['start_time'] - 1 + row['time_count']]['end'])
            for week in weeks:
                points.append((row['week_time'], week, start, end, room(row['classroom'])))
                dates.append(first_monday + datetime.timedelta(days=(week - 1) * 7 + row['week_time'] - 1))
        if set(actual) != set(expected):
            errors.append('Course set mismatch')
        for name, exp in expected.items():
            points = actual.get(name, [])
            if set(points) != occ(exp):
                errors.append(name + ': weekday/week/time/location mismatch')
            if len(points) != len(set(points)):
                errors.append(name + ': duplicate occurrence')
        results.append({
            'file': Path(path).name, 'table_id': table['id'], 'source': source,
            'first_week_monday': first_monday.isoformat(),
            'courses': len(actual), 'rows': len(rows),
            'occurrences': sum(len(v) for v in actual.values()), 'pending': len(pending),
            'first_class_date': min(dates).isoformat(), 'last_class_date': max(dates).isoformat(),
            'passed': not errors, 'errors': errors,
        })
    db.close()
    return results


if __name__ == '__main__':
    results = [r for path in sys.argv[1:] for r in verify(path)]
    print(json.dumps(results, ensure_ascii=False, indent=2))
    sys.exit(not results or any(not r['passed'] for r in results))
