import '../../Components/ScheduleDesign.dart';
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
  bool _hasImportedReminders = false;
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
      _readImportedReminders(p);
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

  void _readImportedReminders(SharedPreferences preferences) {
    final raw = preferences.getString(ScheduleCalendarReminders.stateKey);
    var imported = false;
    if (raw != null) {
      try {
        final state = jsonDecode(raw);
        if (state is Map) {
          final events = state['events'];
          imported = events is Map && events.isNotEmpty;
        }
      } catch (_) {
        imported = false;
      }
    }
    _hasImportedReminders = imported;
  }

  void _showResult(Map<String, dynamic> result) {
    if (!mounted) return;
    final widgetError = result['widgetError'];
    final failure = _failureCopy(result);
    final notice = result['notice'];
    setState(() {
      _widgetError = widgetError is String && widgetError.isNotEmpty
          ? widgetError
          : null;
      _isError = failure != null || (notice is String && notice.isNotEmpty);
      _status = failure ?? (notice is String ? notice : '');
      _retry = failure != null ? _resync : null;
    });
  }

  Future<void> _resync() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ScheduleDerivedDataService.sync(
        await loadPersonalSchedule(),
      );
      _readImportedReminders(await SharedPreferences.getInstance());
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

  Future<void> _revoke() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销日历提醒'),
        content: const Text(
          '将关闭全部提前提醒，并删除三千上课已经写入系统日历的上课提醒。你自己添加的其他日程会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var saved = false;
    setState(() {
      _busy = true;
      _status = '';
      _retry = null;
      _isError = false;
    });
    try {
      final p = await SharedPreferences.getInstance();
      for (final n in _enabled.keys) {
        if (!await p.setBool('reminder_$n', false)) {
          throw StateError('reminder_save_failed');
        }
        _enabled[n] = false;
      }
      saved = true;
      final result = await ScheduleDerivedDataService.sync(
        await loadPersonalSchedule(),
      );
      _readImportedReminders(p);
      _showResult(result);
      if (mounted && !_isError) ScheduleFeedback.haptic();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _status = ScheduleFeedback.message(
            e,
            fallback: saved
                ? '提前提醒已关闭，但日历中的上课提醒尚未完全删除，请重试。'
                : '撤销未完成，请重试。',
          );
          _retry = saved ? _resync : _revoke;
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
      _readImportedReminders(p);
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

  String? _failureCopy(Map<String, dynamic> result) {
    _permissionDenied = result['permission'] == 'denied';
    if (result.isEmpty) return '当前设备暂时无法安排系统提醒，请稍后重试。';
    if (_permissionDenied) return '日历权限未开启，请在系统设置中允许访问日历后重试。';
    if (result['mode'] != 'calendar') return '请同步到系统日历，继续接收上课提醒。';
    if (result['synced'] != true || (result['failed'] as num? ?? 0) > 0) {
      return result['message'] as String? ?? '提醒未同步，请重试。';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('上课提醒')),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          const ScheduleIntro(
            icon: Icons.notifications_outlined,
            eyebrow: '提前一点，从容上课',
            title: '为课程留出准备时间',
            description: '提醒通过系统日历安排，可组合选择提前时间。待定课程会在确认时间后参与同步。',
          ),
          const ScheduleSection('提前提醒'),
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
          if (_status.isNotEmpty)
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
          if (_enabled.containsValue(true) || _hasImportedReminders)
            TextButton(
              onPressed: _busy ? null : _revoke,
              child: const Text('撤销已导入的日历提醒'),
            ),
          const SizedBox(height: 12),
          const Text('课程会同步到系统日历，按你选择的时间提醒，无需打开 App。'),
        ],
      ),
    ),
  );
}
