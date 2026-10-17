import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../Resources/PersonalTheme.dart';

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于三千上课')),
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
            '三千上课基于上游开源项目及其贡献者的代码修改，遵循 Apache License 2.0。感谢所有开源贡献者。',
            style: TextStyle(height: 1.8),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _OpenSourceLicensesView(),
              ),
            ),
            child: const Text('开源许可与致谢'),
          ),
        ],
      ),
    ),
  );
}

class _OpenSourceLicensesView extends StatelessWidget {
  const _OpenSourceLicensesView();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('开源许可与致谢')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          ListTile(
            title: const Text('Apache-2.0 许可证'),
            subtitle: const Text('上游项目的开源许可证'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _SourceLicenseView()),
            ),
          ),
          ListTile(
            title: const Text('第三方开源许可证'),
            subtitle: const Text('Flutter 及依赖库的许可与致谢'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showLicensePage(
              context: context,
              applicationName: personalAppName,
            ),
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
