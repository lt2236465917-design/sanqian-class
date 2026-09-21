import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../Utils/States/MainState.dart';
import '../../Utils/ScheduleFeedback.dart';
import '../About/AboutView.dart';
import '../AddCourse/AddCourseView.dart';
import '../Import/ScreenshotImportView.dart';
import '../Import/SchoolAccountView.dart';
import '../Import/PhotoScheduleImportView.dart';
import 'DeepSeekSettingsView.dart';
import 'ReminderSettingsView.dart';
import '../ManageTable/ManageTableView.dart';
import '../Share/ShareView.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});
  static const _modes = ['跟随系统', '浅色', '深色'];

  @override
  Widget build(BuildContext context) {
    Future<void> open(Widget page, {String? successMessage}) async {
      final saved = await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => page));
      if (saved == true && successMessage != null && context.mounted) {
        ScheduleFeedback.success(context, successMessage);
      }
    }

    Widget tile(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback action,
    ) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: action,
    );
    final model = MainStateModel.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 6, bottom: 12),
              child: Text(
                '我的课表',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  tile(
                    Icons.school_outlined,
                    '学校账号与导入',
                    '中国艺术研究院 · 登录后 AI 识别课表',
                    () => open(
                      const SchoolAccountView(),
                      successMessage: '课表已保存，返回首页即可查看。',
                    ),
                  ),
                  const Divider(height: 1, indent: 18, endIndent: 18),
                  tile(
                    Icons.document_scanner_outlined,
                    '多图课表导入',
                    'AI 联合识别多张截图，核对后保存',
                    () => open(
                      const PhotoScheduleImportView(),
                      successMessage: '课表已保存，返回首页即可查看。',
                    ),
                  ),
                  const Divider(height: 1, indent: 18, endIndent: 18),
                  if (kDebugMode) ...[
                    tile(
                      Icons.photo_library_outlined,
                      '导入内置课表（调试）',
                      '中国艺术研究院 · 2026 秋季，重复导入保留修改',
                      () => open(
                        const ScreenshotImportView(),
                        successMessage: '已打开内置课表，返回首页即可查看。',
                      ),
                    ),
                    const Divider(height: 1, indent: 18, endIndent: 18),
                  ],
                  tile(
                    Icons.add_rounded,
                    '手动添加课程',
                    '补充课程、教师和上课安排',
                    () => open(
                      const AddView(),
                      successMessage: '课程已保存到当前课表，返回首页即可查看。',
                    ),
                  ),
                  const Divider(height: 1, indent: 18, endIndent: 18),
                  tile(
                    Icons.calendar_month_outlined,
                    '管理课表',
                    '切换或新增一份课表',
                    () => open(
                      const ManageTableView(),
                      successMessage: '已切换课表，返回首页即可查看。',
                    ),
                  ),
                  const Divider(height: 1, indent: 18, endIndent: 18),
                  tile(
                    Icons.ios_share_rounded,
                    '课表导入与导出',
                    '二维码分享、导入及系统日历',
                    () => open(const ShareView()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.only(left: 6, bottom: 12),
              child: Text(
                '使用偏好',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  tile(
                    Icons.key_outlined,
                    'DeepSeek 设置',
                    '保存或删除本机 API key',
                    () => open(const DeepSeekSettingsView()),
                  ),
                  const Divider(height: 1, indent: 18, endIndent: 18),
                  tile(
                    Icons.notifications_outlined,
                    '上课提醒',
                    '提前 15 分钟、3 小时或 24 小时',
                    () => open(const ReminderSettingsView()),
                  ),
                  const Divider(height: 1, indent: 18, endIndent: 18),
                  tile(
                    Icons.brightness_6_outlined,
                    '外观',
                    _modes[model.themeModeIndex ?? 0],
                    () => _chooseTheme(context),
                  ),
                  const Divider(height: 1, indent: 18, endIndent: 18),
                  tile(
                    Icons.auto_stories_outlined,
                    '关于三千上课',
                    '开源来源与许可证',
                    () => open(const AboutView()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              '导入后的课表可离线查看。\n学校调课后，请以学校最新通知为准。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.8,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _chooseTheme(BuildContext context) {
    final model = MainStateModel.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '外观',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            for (var i = 0; i < _modes.length; i++)
              ListTile(
                title: Text(_modes[i]),
                trailing: (model.themeModeIndex ?? 0) == i
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  model.changeThemeMode(i);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
