import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../Models/PersonalSchedule.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../../Utils/ScheduleCalendarExporter.dart';
import '../../Utils/ScheduleFeedback.dart';
import '../../Utils/ScheduleCalendarReminders.dart';

class ReminderSettingsView extends StatefulWidget {
  const ReminderSettingsView({super.key});
  @override
  State<ReminderSettingsView> createState() => _ReminderSettingsViewState();
}

class _ReminderSettingsViewState extends State<ReminderSettingsView>
    with WidgetsBindingObserver {
  final _enabled = <int, bool>{15: false, 180: false, 1440: false};
  String _status = '';
  String? _widgetError;
  bool _busy = true;
  bool _permissionDenied = false, _isError = false, _awaitingSettings = false;
  VoidCallback? _retry;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        for (final n in _enabled.keys) {
          _enabled[n] = p.getBool('reminder_$n') ?? false;
        }
      });
      final saved = p.getString('reminder_status');
      if (saved != null) {
        final result = jsonDecode(saved);
        if (result is Map<String, dynamic>) _showResult(result);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isError = true;
          _status = '暂时无法读取提醒设置，请重试。';
          _retry = _load;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingSettings && !_busy) {
      _awaitingSettings = false;
      (_retry ?? _resync)();
    }
  }

  Future<void> _openSettings() async {
    if (_awaitingSettings) return;
    _awaitingSettings = true;
    try {
      final opened = await ScheduleCalendarExporter.settingsChannel
          .invokeMethod<bool>('openAppSettings');
      if (opened != true) throw StateError('settings_unavailable');
    } catch (_) {
      _awaitingSettings = false;
      if (mounted) {
        setState(() {
          _isError = true;
          _status = '无法直接打开系统设置，请在设备“设置”中找到本 App，允许访问日历后重试。';
        });
      }
    }
  }

  void _showResult(Map<String, dynamic> result) {
    if (!mounted) return;
    final widgetError = result['widgetError'];
    setState(() {
      _widgetError = widgetError is String && widgetError.isNotEmpty
          ? widgetError
          : null;
      _permissionDenied = result['permission'] == 'denied';
      _isError =
          _permissionDenied ||
          (result['failed'] as num? ?? 0) > 0 ||
          result.isEmpty ||
          result['mode'] != 'calendar' ||
          result['synced'] != true;
      _status = result.isEmpty
          ? '当前设备暂时无法安排系统提醒，请稍后重试。'
          : _describeStatus(result);
      _retry = _isError ? _resync : null;
    });
  }

  Future<void> _resync() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在重新安排提醒…';
    });
    try {
      final result = await ScheduleDerivedDataService.sync(
        await loadPersonalSchedule(),
      );
      _showResult(result);
      if (mounted && !_isError) ScheduleFeedback.haptic();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _status = ScheduleFeedback.message(
            e,
            fallback: '提醒尚未完成安排，请检查日历权限后重试。',
          );
          _retry = _resync;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(int lead, bool value) async {
    if (_busy) return;
    var saved = false;
    setState(() {
      _busy = true;
      _status = '';
      _retry = null;
      _isError = false;
    });
    try {
      if (value) {
        final granted = await ScheduleCalendarReminders.requestPermission();
        if (!granted) {
          if (mounted) {
            setState(() {
              _permissionDenied = true;
              _isError = true;
              _status = '日历权限未开启，请在系统设置中允许访问日历后重试。';
              _retry = () => _change(lead, value);
            });
          }
          return;
        }
        _permissionDenied = false;
      }
      final p = await SharedPreferences.getInstance();
      if (!await p.setBool('reminder_$lead', value)) {
        throw StateError('reminder_save_failed');
      }
      saved = true;
      _enabled[lead] = value;
      final result = await ScheduleDerivedDataService.sync(
        await loadPersonalSchedule(),
      );
      _showResult(result);
      if (mounted && !_isError) ScheduleFeedback.haptic();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _status = ScheduleFeedback.message(
            e,
            fallback: saved ? '提醒设置已保存，但提醒尚未完成安排，请重试。' : '提醒设置未保存，请重试。',
          );
          _retry = saved ? _resync : () => _change(lead, value);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describeStatus(Map<String, dynamic> result) {
    if (result['mode'] != 'calendar') return '请同步到系统日历，继续接收上课提醒。';
    if (result['synced'] != true) {
      return result['message'] as String? ?? '提醒未同步，请重试。';
    }
    final count = result['count'] as num? ?? 0;
    if (count == 0) {
      return _enabled.values.any((v) => v) ? '已同步，当前没有待提醒的课程。' : '上课提醒已关闭。';
    }
    final extras = result['supplements'] as num? ?? 0;
    return extras > 0 ? '提醒已开启，部分课程会在日历中显示补充提醒日程。' : '系统日历提醒已开启。';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('上课提醒')),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          for (final item in const {
            15: '提前 15 分钟',
            180: '提前 3 小时',
            1440: '提前 24 小时',
          }.entries)
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              title: Text(item.value),
              value: _enabled[item.key]!,
              onChanged: _busy ? null : (v) => _change(item.key, v),
            ),
          if (_status.isNotEmpty && _isError)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _isError
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
            ),
          if (_widgetError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _widgetError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_permissionDenied)
            TextButton.icon(
              onPressed: _busy ? null : _openSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('打开系统设置'),
            ),
          if (_retry != null)
            TextButton(
              onPressed: _busy ? null : _retry,
              child: const Text('重试提醒设置'),
            ),
          const SizedBox(height: 12),
          const Text('课程会同步到系统日历，按你选择的时间提醒，无需打开 App 就够了。'),
        ],
      ),
    ),
  );
}
