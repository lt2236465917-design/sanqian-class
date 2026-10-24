# Android namespace 独立审核

Task-ID: android-namespace-copyright-20261017
Owner-Session: 01a14709-d662-7882-8a5b-a1ff3727ef4f
Reviewer: android_namespace_review
Date: 2026-10-17

## 结论：PASS

本次 Android 内部命名统一审核通过。未发现 P0/P1/P2 阻断项；主 Agent 可以进入软著材料生成阶段。此结论仅覆盖本次命名迁移及下列验证范围，不是所有业务、旧版升级或软著材料本身的验收。

## 已验证证据

1. 已读取当前 App AGENTS.md，并核对任务状态的 Task-ID / Owner-Session。没有恢复其他任务状态，审核仅写入本 review.md。
2. 独立逐字节比较 baseline-files.zip 的 89 个文件。67 个 Android 文件均能一一映射至当前文件，无新增或缺失；其中 36 个文件变化全部等于 `local.sanqian.schedule` 替换为 `love.sanqian.schedule`，目录对应迁移。其余基线文件不变。原有 ScheduleWidgetUpdater 修改已包含在基线中，没有被覆盖。已记录的既有 iOS 修改与基线 diff 一致；本次没有触及签名逻辑、业务逻辑、存储键、MethodChannel 或新增敏感信息。
3. `android/app/build.gradle:32` namespace 与 `:52` applicationId 均为 `love.sanqian.schedule`；applicationId 基线已是该值。31 份自有生产/测试包声明和目录一致；3 份 Manifest、6 条 ProGuard keep 规则已同步。195 个 Android/lib/test/tool 非构建文件未发现旧完整包名或旧完整路径标记。GeneratedPluginRegistrant 等第三方命名空间保持原本所有权，不应替换为应用包名。
4. `android/app/src/main/AndroidManifest.xml:30`、`:38`、`:79`、`:82`、`:93`、`:96` 的自有 Application/Activity/Receiver 以及 SchoolPortalActivity 均在合并 Manifest 和 APK Manifest 中解析到新包；provider authorities 也使用新 applicationId。APK 的所有 DEX 未包含旧包名点号/路径标记；8 个关键类（Application、2 个 Activity、4 个 Receiver、ScheduleImportPlugin）均存在新包 descriptor。R8 seeds 对应新包。R 资源引用通过生产编译；反射仅使用系统类，没有遗留自有类字符串。
5. `build-release.log` 显示 `flutter build apk --release` 成功。新 APK badging 为 `love.sanqian.schedule`，版本 `1.0.0` / `1`；签名验证 v2 成功。实际审核 APK 为 `build/app/outputs/flutter-apk/app-release.apk`，SHA-256：`537759ac1f4ad5f10f36e5d04b617b85e7d6bbb97d95248c9d1315b4ceb6f28c`。
6. `unit-tests.log` 显示 `:app:testDebugUnitTest` / BUILD SUCCESSFUL。独立读取 6 个当前 XML 测试报告并重新汇总：44 tests、0 failures、0 errors、0 skipped；所有测试类均在 `love.sanqian.schedule` 下。
7. 主 Agent 执行 API 35 模拟器新包安装、冷启动，过程记录见 `runtime-verification.txt`。独立读取 `launch-ui.xml`，实际节点属于新包，显示日课表首页和日周月导航。`widget-dumpsys.txt:74` 的 widget id=3 绑定 `love.sanqian.schedule/love.sanqian.schedule.ScheduleWidgetProvider`，provider zombie=false；`widget-home-ui.xml` 的新包 RemoteViews 显示“暂无已排课程”；`widget-open-activity.txt:1` 显示点击后新包 MainActivity resumed，`widget-open-ui.xml` 同样属于新包。`crash-log.txt` 为空。首次同名旧应用 widget 的结果已作废，不能计入新包通过证据；最终 dumpsys 只有新包 id=3，误加的旧 widget id=2 已移除。

## 升级影响和非阻断边界

- 信息项（非阻断）：`android/app/src/main/java/love/sanqian/schedule/ScheduleWidgetSafety.java:19` 按新 ComponentName 查找 widget。若曾安装 applicationId 为 love、内部组件仍为 local 的混合测试版本，原 widget 绑定不会自动迁移，需要重新添加；当前没有证据证明该混合版本已交付，因此不把假设的在用版本当成当前回归，也不宣称无缝升级。
- 信息项（非阻断）：`ScheduleWidgetUpdater.kt:91` 和 `ScheduleReminderScheduler.kt:69` 的 PendingIntent 组件变为新包。旧组件的既存 PendingIntent 身份与新组件不同；没有旧队列原位迁移验证。当前提醒代码负责清理历史 in-app 队列，新提醒写入系统日历，此次没有更改该逻辑。
- 旧 applicationId 为 `local.sanqian.schedule` 或 `com.lilystudio.wheretosleepinnju` 的安装是另一应用；新的 love 包不自动继承其私有数据。当前 build versionCode=1，不代表可覆盖任意既有同 ID 高版本安装。旧版数据迁移、原位升级和旧组件兼容不是本轮已验证结果。
- NOT_VERIFIED：真实设备/OEM、同 applicationId 的原位升级、已有 widget 自动迁移、真实课表导入/OCR/教务登录/课程提醒端到端、重启/时间变化广播触发后的完整行为。空课表 widget 渲染与点击通过不等于有课程场景全部通过。
- 软著材料尚未在本审核中生成或验收；PASS 仅放行后续材料步骤，不能代替材料快照一致性、PDF 和打包校验。
