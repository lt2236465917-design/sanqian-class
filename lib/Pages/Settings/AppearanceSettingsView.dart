import 'package:flutter/material.dart';

import '../../Components/ScheduleDesign.dart';
import '../../Utils/States/MainState.dart';

class AppearanceSettingsView extends StatelessWidget {
  const AppearanceSettingsView({super.key});
  static const modes = ['跟随系统', '浅色', '深色'];

  @override
  Widget build(BuildContext context) {
    final model = MainStateModel.of(context);
    final selected = model.themeModeIndex ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('显示外观')),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          children: [
            const ScheduleIntro(
              icon: Icons.brightness_6_outlined,
              eyebrow: '浅色、深色或跟随系统',
              title: '让课表适应周围光线',
              description: '选择后立即切换，并保留在本机。下次打开仍使用这个显示外观。',
            ),
            const ScheduleSection('显示方式'),
            for (var i = 0; i < modes.length; i++)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                title: Text(modes[i]),
                trailing: selected == i
                    ? const Icon(Icons.check_rounded)
                    : null,
                selected: selected == i,
                onTap: () => model.changeThemeMode(i),
              ),
          ],
        ),
      ),
    );
  }
}
