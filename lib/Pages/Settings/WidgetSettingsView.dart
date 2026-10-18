import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../Components/ScheduleDesign.dart';
import '../../Models/PersonalSchedule.dart';
import '../../Utils/ScheduleDerivedDataService.dart';

/// Synchronizes desktop widgets from the currently selected schedule.
class WidgetSettingsView extends StatefulWidget {
  const WidgetSettingsView({super.key});
  @override
  State<WidgetSettingsView> createState() => _WidgetSettingsViewState();
}

class _WidgetSettingsViewState extends State<WidgetSettingsView> {
  bool _busy = false, _error = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh(reportSuccess: false);
    });
  }

  String _message(Object? raw, bool missing) {
    if (raw == 'App Group 尚不可用') {
      return '当前安装还不能和桌面小组件共享课表，小组件里会暂时没有课程。课表本身可以正常查看。';
    }
    if (raw is String && raw.isNotEmpty) return raw;
    if (missing) return '当前平台没有返回同步结果，请稍后重试。';
    return '已请求更新桌面课表，具体刷新时间由系统决定。';
  }

  Future<void> _refresh({bool reportSuccess = true}) async {
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
        final failed = result == null || result['widgetError'] != null;
        setState(() {
          _error = failed;
          _status = !reportSuccess && !failed
              ? null
              : _message(result?['widgetError'], result == null);
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
              description: '小尺寸看下一节，中尺寸看重点课程和后续安排，大尺寸看今日时间轴。点击课程可查看详情。',
            ),
            const ScheduleSection('添加到桌面'),
            ScheduleNotice(
              ios
                  ? 'iOS 17 及以上：长按桌面空白处 → 编辑 → 添加小组件。搜索“三千上课”可添加小、中、大尺寸；“课程表”使用同样的桌面布局，并保留锁屏组件。临近上课时，锁屏和灵动岛会显示倒计时。'
                  : '长按桌面空白处 → 小组件，找到“三千上课”，添加后拖动边框，可调整为小尺寸、中尺寸或大尺寸。不同启动器的操作名称可能不同。',
            ),
            const ScheduleSection('与当前课表同步'),
            const Text(
              '切换课表或修改课程后，App 会提交新的课程安排。时间待定的课程不显示；桌面刷新频率由系统管理。',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : () => _refresh(),
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
