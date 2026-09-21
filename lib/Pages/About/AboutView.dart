import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../Resources/PersonalTheme.dart';

class AboutView extends StatelessWidget {
  const AboutView({super.key});
  static const upstream =
      'https://github.com/WheretoSleepinNJU/NJU-Class-Shedule-Flutter';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Image.asset(
                'res/personal-icon.png',
                width: 108,
                height: 108,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            personalAppName,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('把上课的日子，轻轻记好', textAlign: TextAlign.center),
          const SizedBox(height: 32),
          const Text(
            '这是一份为日常上课整理的个人课表。导入后，课程保存在手机本地；目前的课表来自学校截图，不会自动同步学校的调课通知。',
            style: TextStyle(height: 1.8),
          ),
          const SizedBox(height: 24),
          const Text(
            '开源来源',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            '基于 idealclover 与南哪课表贡献者开发的「南哪课表」修改，沿用 Apache License 2.0。感谢上游项目和所有开源贡献者。',
            style: TextStyle(height: 1.8),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('查看原项目'),
            onPressed: () async {
              final opened = await launchUrl(
                Uri.parse(upstream),
                mode: LaunchMode.externalApplication,
              );
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('暂时无法打开项目地址')));
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _SourceLicenseView()),
            ),
            child: const Text('Apache-2.0 许可证'),
          ),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: personalAppName,
            ),
            child: const Text('第三方开源许可证'),
          ),
        ],
      ),
    ),
  );
}

class _SourceLicenseView extends StatelessWidget {
  const _SourceLicenseView();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Apache-2.0')),
    body: FutureBuilder<String>(
      future: rootBundle.loadString('LICENSE'),
      builder: (context, snapshot) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SelectableText(
          snapshot.data ?? '正在读取许可证…',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
      ),
    ),
  );
}
