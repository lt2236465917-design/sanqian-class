import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../Models/ScreenshotSchedule.dart';
import '../../Utils/ScreenshotScheduleImporter.dart';
import '../../Utils/States/MainState.dart';
import '../../Utils/WeekUtil.dart';

class ScreenshotImportView extends StatefulWidget {
  const ScreenshotImportView({super.key});

  @override
  State<ScreenshotImportView> createState() => _ScreenshotImportViewState();
}

class _ScreenshotImportViewState extends State<ScreenshotImportView> {
  late final Future<ScreenshotSchedule> _schedule = _load();
  bool _importing = false;

  Future<ScreenshotSchedule> _load() async => ScreenshotSchedule.fromJson(
    jsonDecode(await rootBundle.loadString(ScreenshotSchedule.assetPath))
        as Map<String, dynamic>,
  );

  Future<void> _import(ScreenshotSchedule schedule) async {
    setState(() => _importing = true);
    try {
      final model = MainStateModel.of(context);
      final id = await ScreenshotScheduleImporter.importOrOpen(schedule);
      await WeekUtil.initWeek(schedule.data['semester_start_monday'], 1);
      await model.changeclassTable(id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('课表导入失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('截图课表')),
    body: FutureBuilder<ScreenshotSchedule>(
      future: _schedule,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('课表文件无法读取。'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final schedule = snapshot.data!;
        return SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      schedule.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${schedule.courses.length} 门课 · '
                      '${schedule.courses.length - schedule.pendingCount} 门已排课 · '
                      '${schedule.pendingCount} 门时间待定',
                    ),
                    const SizedBox(height: 8),
                    const Text('9 月 9 日开学，第一周从 9 月 7 日周一计算。'),
                    const SizedBox(height: 8),
                    for (final period in schedule.periods)
                      Text(schedule.periodDescription(period['id'])),
                    const SizedBox(height: 8),
                    const Text(
                      '这是根据已提供截图整理的内置课表。重复导入会打开已有课表并保留你的修改；不会读取新截图或自动同步学校调课。',
                    ),
                    const SizedBox(height: 16),
                    for (final course in schedule.courses)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(course['name']),
                        subtitle: Text(
                          (course['meetings'] as List).isEmpty
                              ? '时间、地点待定'
                              : '${course['credits']} 学分',
                        ),
                        childrenPadding: const EdgeInsets.only(bottom: 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (course['teacher'] as String? ?? '').isEmpty
                                ? '教师待定'
                                : '教师：${course['teacher']}',
                          ),
                          if ((course['meetings'] as List).isEmpty)
                            Text(course['note'] as String),
                          for (final meeting in course['meetings'] as List)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                '${ScreenshotSchedule.formatWeeks(List<int>.from(meeting['weeks']))} '
                                '周${'一二三四五六日'[meeting['weekday'] - 1]} '
                                '${schedule.periodDescription(meeting['period'])}\n${meeting['location']}',
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _importing ? null : () => _import(schedule),
                    child: Text(_importing ? '正在导入…' : '导入 / 更新本地课表'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
