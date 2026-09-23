import '../../Components/ScheduleDesign.dart';
import 'package:flutter/material.dart';

import '../../Models/CourseModel.dart';
import '../../Models/CourseTableModel.dart';
import '../../Models/PersonalSchedule.dart';
import '../../Utils/QrScheduleImporter.dart';
import '../../Utils/ScheduleCalendarExporter.dart';
import '../../Utils/States/MainState.dart';
import 'QRShareView.dart';
import 'QRScanView.dart';
import 'qr_payload_codec.dart';

class ShareView extends StatefulWidget {
  const ShareView({super.key});
  @override
  State<ShareView> createState() => _ShareViewState();
}

class _ShareViewState extends State<ShareView> {
  bool _busy = false;

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (_) {
      _message('操作未完成，请重试。原有课表已保留。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('课表导入与导出')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ScheduleIntro(
            icon: Icons.ios_share_rounded,
            eyebrow: '与其他设备连接',
            title: '把课表带过去',
            description: '使用二维码分享课程，或把已确认的安排导出到系统日历。',
          ),
          const SizedBox(height: 20),
          if (_busy) const LinearProgressIndicator(),
          ScheduleActionTile(
            icon: Icons.qr_code_rounded,
            title: '导出当前课表',
            subtitle: '生成二维码，或复制完整分享串',
            onTap: _busy ? null : () => _run(_exportClassTable),
          ),
          ScheduleActionTile(
            icon: Icons.qr_code_scanner_rounded,
            title: '导入课表',
            subtitle: '扫码、选择二维码图片或粘贴分享串',
            onTap: _busy ? null : () => _run(_importFromQr),
          ),
          ScheduleActionTile(
            icon: Icons.event_available_outlined,
            title: '导出到系统日历',
            subtitle: '按课表日期导出，重复导出会更新已写入的课程',
            onTap: _busy ? null : () => _run(_exportToSystemCalendar),
          ),
        ],
      ),
    ),
  );

  Future<void> _exportClassTable() async {
    final index = await MainStateModel.of(context).getClassTable();
    final rows = await CourseProvider().getAllCourses(index);
    final table = await CourseTableProvider().getCourseTable(index);
    if (table == null || rows.isEmpty) {
      _message('当前课表还没有课程，请先导入或添加课程。');
      return;
    }
    final schedule = await loadPersonalSchedule();
    // Include the effective semester and periods even for a manually created table.
    final payload = QrPayloadCodec.buildSchedulePayload(
      tableName: table.name ?? '我的课表',
      tableData: schedule.exportTableData(table.data),
      courseRows: rows.map((e) => Map<String, dynamic>.from(e)).toList(),
    );
    final encoded = QrPayloadCodec.encodePayload(payload);
    final frames = QrPayloadCodec.buildFramesFromEncodedPayload(encoded);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QRShareView(
          frames: frames,
          singleShareText:
              '$kNcsQrScheme://$kNcsQrHost/$kNcsQrVersion/s/$encoded',
        ),
      ),
    );
  }

  Future<void> _importFromQr() async {
    final model = MainStateModel.of(context);
    final payload = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const QRScanView()),
    );
    if (payload == null || !mounted) return;
    final count = (payload['courses'] as List).length;
    final name = (payload['table'] as Map)['name'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入这份课表？'),
        content: Text('$name\n共 $count 条课程安排，将新增为独立课表，保留原有课表。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = await QrScheduleImporter.import(payload);
    await model.changeclassTable(id);
    _message('已导入并切换到 $name，返回首页即可查看。');
  }

  Future<void> _exportToSystemCalendar() async {
    final schedule = await loadPersonalSchedule();
    final entries = ScheduleCalendarExporter.exportable(schedule);
    if (!mounted) return;
    if (entries.isEmpty) {
      _message('没有可导出的课程，请先填写上课日期和起止时间。');
      return;
    }
    final skipped =
        schedule.pending.length + schedule.occurrences.length - entries.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出到系统日历'),
        content: Text(
          '将写入 ${entries.length} 次课程，使用独立的“三千上课”课程日历。'
          '${skipped > 0 ? '\n$skipped 条时间待定的安排会跳过。' : ''}'
          '\n再次导出会更新本次已记录的课程；在 App 中删除课程不会自动删除系统日历中的日程。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认导出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await ScheduleCalendarExporter().export(schedule);
      _message('已成功写入 $count 次课程。');
    } on CalendarExportException catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出未完成'),
          content: Text(
            '${error.savedCount > 0 ? '已写入 ${error.savedCount} 次课程。\n' : ''}${error.message}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
            if (error.permissionDenied)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await ScheduleCalendarExporter.settingsChannel
                      .invokeMethod<bool>('openAppSettings');
                },
                child: const Text('去设置'),
              ),
          ],
        ),
      );
    }
  }
}
