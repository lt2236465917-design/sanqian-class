# 周课表视觉改版

- Task-ID: week-schedule-visual-01a0c6e5
- Owner-Session: 01a0c6e5-d08f-7400-82a4-8f1a421ea981

## 目标

在视觉 worktree 中实现周课表双层体验：周课表首页显示不滚动的三时段缩略分布；点击后进入详情页，按周几纵向展示现有课程卡片样式，支持上下滚动且不显示滚动条。

## 范围

- `lib/Pages/Personal/PersonalHomeView.dart` 的周课表 UI、导航和课程卡片复用。
- 保留现有课程数据、详情弹窗、日课表和月课表行为。
- 不改导入、数据库、Android/iOS 原生合同。

## 验证

- `dart format` 检查受影响 Dart 文件。
- `flutter analyze` 或等价静态检查。
- 若环境允许，运行现有相关测试；真实 App/Simulator 视觉验收另行记录。
