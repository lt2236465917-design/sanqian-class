import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../Models/PersonalSchedule.dart';
import '../../Utils/ScheduleDerivedDataService.dart';

class ReminderSettingsView extends StatefulWidget {
  const ReminderSettingsView({super.key});
  @override
  State<ReminderSettingsView> createState() => _ReminderSettingsViewState();
}

class _ReminderSettingsViewState extends State<ReminderSettingsView> {
  final _enabled = <int, bool>{15: false, 180: false, 1440: false};
  String _status = '';
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final n in _enabled.keys) {
        _enabled[n] = p.getBool('reminder_$n') ?? false;
      }
      final saved = p.getString('reminder_status');
      if (saved != null) {
        try {
          _status = _describeStatus(jsonDecode(saved) as Map<String, dynamic>);
        } on FormatException {
          _status = '';
        }
      }
      _busy = false;
    });
  }

  Future<void> _change(int lead, bool value) async {
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      if (value) {
        final granted =
            await ScheduleDerivedDataService.channel.invokeMethod<bool>(
              'requestReminderPermission',
            ) ??
            false;
        if (!granted) {
          throw StateError('通知权限未开启，请在系统设置中允许通知。');
        }
      }
      final p = await SharedPreferences.getInstance();
      await p.setBool('reminder_$lead', value);
      _enabled[lead] = value;
      final result = await ScheduleDerivedDataService.sync(
        await loadPersonalSchedule(),
      );
      if (mounted) setState(() => _status = _describeStatus(result));
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describeStatus(Map<String, dynamic> result) {
    if (result['permission'] == 'denied') {
      return '系统通知权限未开启；请在系统设置中允许通知后重新打开 App。';
    }
    final ms = result['coverageEndMs'] as num? ?? 0;
    final date = ms > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            ms.toInt(),
            isUtc: true,
          ).add(const Duration(hours: 8))
        : null;
    return '已安排 ${result['count'] ?? 0} 条提醒'
        '${date == null ? '' : '，最远至 ${date.month}月${date.day}日（北京时间）'}'
        '${result['limited'] == true ? '。队列已满，请定期打开 App 补排。' : '。'}'
        '${(result['failed'] as num? ?? 0) > 0 ? '部分提醒添加失败，请重试。' : ''}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('上课提醒')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final item in const {
          15: '提前 15 分钟',
          180: '提前 3 小时',
          1440: '提前 1 天',
        }.entries)
          SwitchListTile(
            title: Text(item.value),
            value: _enabled[item.key]!,
            onChanged: _busy ? null : (v) => _change(item.key, v),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_status.isNotEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(_status)),
        const Text(
          '只提醒已确认日期和钟点的课程。修改课程或切换课表后会重新安排。通知队列有限，请定期打开 App；无法保证长期不打开仍覆盖整个学期。',
        ),
      ],
    ),
  );
}
