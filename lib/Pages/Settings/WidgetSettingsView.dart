import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../Components/ScheduleDesign.dart';
import '../../Models/PersonalSchedule.dart';
import '../../Utils/ScheduleDerivedDataService.dart';

/// Controls only the registered personal schedule widget, not the legacy widget.
class WidgetSettingsView extends StatefulWidget {
  const WidgetSettingsView({super.key});
  @override
  State<WidgetSettingsView> createState() => _WidgetSettingsViewState();
}

class _WidgetSettingsViewState extends State<WidgetSettingsView> {
  bool _busy = false, _error = false;
  String? _status;
  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final schedule = await loadPersonalSchedule();
      // Widget-only refresh does not request calendar permission or write events.
      final result = await ScheduleDerivedDataService.channel
          .invokeMapMethod<String, dynamic>(
            'syncDerivedData',
            ScheduleDerivedDataService.snapshot(schedule),
          );
      if (mounted) {
        setState(() {
          _error = result == null || result['widgetError'] != null;
          _status =
              result?['widgetError'] as String? ??
              (result == null
                  ? '当前平台没有返回同步结果，请稍后重试。'
                  : '已请求更新桌面课表，具体刷新时间由系统决定。');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _status = '暂时无法同步小组件，请返回课表后重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    return Scaffold(
      appBar: AppBar(title: const Text('桌面小组件')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const ScheduleIntro(
              icon: Icons.widgets_outlined,
              eyebrow: '无需打开 App',
              title: '下一节课，就在桌面',
              description: '小尺寸突出下一节，中尺寸展示今日剩余课程。时间、地点和上课状态来自当前课表。',
            ),
            const ScheduleSection('添加到桌面'),
            ScheduleNotice(
              ios
                  ? 'iOS 17 及以上：长按桌面空白处 → 编辑 → 添加小组件，搜索“三千上课”，选择小尺寸或中尺寸。'
                  : '长按桌面空白处 → 小组件，找到“三千上课”，选择小尺寸或中尺寸并拖到桌面。不同启动器的操作名称可能不同。',
            ),
            const ScheduleSection('与当前课表同步'),
            const Text(
              '切换课表或修改课程后，App 会提交新的课程安排。时间待定的课程不显示；桌面刷新频率由系统管理。',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.sync_rounded),
              label: Text(_busy ? '正在同步…' : '刷新桌面课表'),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ScheduleNotice(_status!, error: _error),
              ),
          ],
        ),
      ),
    );
  }
}
